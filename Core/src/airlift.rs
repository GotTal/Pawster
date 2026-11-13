// Folder transport adapted from Mak5er/AirCard-iOS 40640c4d, MIT.
// See ThirdParty/AirCard-MIT.txt. Restricted to NEW Collections descriptors.
use crate::network::{connect_tunnel, Logger};
use crate::operations::bounded;
use idevice::afc::{opcode::AfcFopenMode, AfcClient};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    io::{self, Read, Write},
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

const BOOKS: &str = "Books/Sync/Books.plist";
const MAX_BOOKS: usize = 1024 * 1024;
pub const COLLECTIONS: &str = "Library/Application Support/PRBPosterExtensionDataStore/61/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors";

fn uuid(value: &str) -> bool {
    value.len() == 36
        && value.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        })
}
fn normalized_container(value: &str) -> Result<String, String> {
    let value = value.strip_prefix("/private").unwrap_or(value);
    let tail = value
        .strip_prefix("/var/mobile/Containers/Data/Application/")
        .ok_or("Invalid PosterBoard container")?;
    if !uuid(tail) {
        return Err("Invalid PosterBoard container UUID".into());
    }
    Ok(value.into())
}
fn random_hex(n: usize) -> Result<String, String> {
    let mut bytes = vec![0; n];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .map_err(|e| e.to_string())?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
fn validate_source_tree(root: &Path) -> Result<(), String> {
    fn walk(path: &Path, depth: usize, bytes: &mut u64, count: &mut usize) -> Result<(), String> {
        let meta = std::fs::symlink_metadata(path).map_err(|e| e.to_string())?;
        if meta.file_type().is_symlink() || (!meta.is_dir() && !meta.is_file()) || depth > 32 {
            return Err("Source contains links, special files or excessive depth".into());
        }
        *count += 1;
        *bytes += if meta.is_file() { meta.len() } else { 0 };
        if *count > 20000 || *bytes > 256 * 1024 * 1024 {
            return Err("Airlift descriptor exceeds 256 MiB or 20000 entries".into());
        }
        if meta.is_dir() {
            for item in std::fs::read_dir(path).map_err(|e| e.to_string())? {
                walk(
                    &item.map_err(|e| e.to_string())?.path(),
                    depth + 1,
                    bytes,
                    count,
                )?;
            }
        }
        Ok(())
    }
    if !root.is_dir() {
        return Err("Descriptor source must be a directory".into());
    }
    walk(root, 0, &mut 0, &mut 0)
}

#[derive(Serialize, Deserialize)]
struct BookBackup {
    container: String,
    original: Option<Vec<u8>>,
    manifest: Vec<u8>,
    source: String,
    link: String,
    restored: bool,
    original_hash: Option<String>,
    manifest_hash: String,
}
fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn state_path(directory: &Path) -> PathBuf {
    directory.join("books-state.json")
}
fn save_state(directory: &Path, state: &BookBackup) -> Result<(), String> {
    std::fs::create_dir_all(directory).map_err(|e| e.to_string())?;
    let path = directory.join("books-state.pending");
    let mut file = std::fs::File::create(&path).map_err(|e| e.to_string())?;
    file.write_all(&serde_json::to_vec(state).map_err(|e| e.to_string())?)
        .and_then(|_| file.sync_all())
        .map_err(|e| e.to_string())?;
    std::fs::rename(path, state_path(directory)).map_err(|e| e.to_string())
}
fn recovery_directory(pairing: &Path, directory: &Path) -> Result<PathBuf, String> {
    let supplied_app = pairing.parent().ok_or("Invalid pairing location")?;
    let app = supplied_app.canonicalize().map_err(|e| e.to_string())?;
    let relative = directory
        .strip_prefix(supplied_app.join("Transactions"))
        .map_err(|_| "Invalid recovery location")?;
    let parts: Vec<_> = relative.components().collect();
    if parts.len() != 3
        || !uuid(&parts[0].as_os_str().to_string_lossy())
        || parts[1].as_os_str() != "airlift"
        || !uuid(&parts[2].as_os_str().to_string_lossy())
    {
        return Err("Invalid recovery location".into());
    }
    let mut cursor = app.join("Transactions");
    for part in parts {
        cursor.push(part);
        match std::fs::symlink_metadata(&cursor) {
            Ok(meta) if meta.file_type().is_symlink() || !meta.is_dir() => {
                return Err("Recovery path contains a link or non-directory".into())
            }
            Ok(_) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(cursor)
}
fn read_state(path: &Path) -> Result<BookBackup, String> {
    let meta = std::fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !meta.is_file() || meta.file_type().is_symlink() || meta.len() > 8 * 1024 * 1024 {
        return Err("Invalid AirTraffic recovery record".into());
    }
    let state: BookBackup =
        serde_json::from_slice(&std::fs::read(path).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    normalized_container(&state.container)?;
    if state
        .original
        .as_ref()
        .is_some_and(|bytes| bytes.len() > MAX_BOOKS)
        || state.manifest.len() > MAX_BOOKS
        || state.original.as_ref().map(|bytes| digest(bytes)) != state.original_hash
        || digest(&state.manifest) != state.manifest_hash
    {
        return Err("AirTraffic recovery backup failed checksum or size validation".into());
    }
    for (value, prefix) in [
        (&state.source, "pawster-airlift-src-"),
        (&state.link, "pawster-airlift-link-"),
    ] {
        if !value
            .strip_prefix(prefix)
            .is_some_and(|tail| tail.len() == 20 && tail.bytes().all(|b| b.is_ascii_hexdigit()))
        {
            return Err("Invalid AirTraffic staging identity".into());
        }
    }
    Ok(state)
}
fn no_pending_recovery(pairing: &Path) -> Result<(), String> {
    let transactions = pairing
        .parent()
        .ok_or("Invalid pairing location")?
        .join("Transactions");
    for transaction in std::fs::read_dir(transactions).map_err(|e| e.to_string())? {
        let transaction = transaction.map_err(|e| e.to_string())?;
        if !uuid(&transaction.file_name().to_string_lossy()) {
            continue;
        }
        let root = transaction.path().join("airlift");
        if !root.try_exists().map_err(|e| e.to_string())? {
            continue;
        }
        for entry in std::fs::read_dir(root).map_err(|e| e.to_string())? {
            let path = entry
                .map_err(|e| e.to_string())?
                .path()
                .join("books-state.json");
            if path.try_exists().map_err(|e| e.to_string())? && !read_state(&path)?.restored {
                return Err("Unfinished AirTraffic cleanup exists. Restore synchronization state from Operation History first.".into());
            }
        }
    }
    Ok(())
}
async fn read_books(afc: &mut AfcClient) -> Result<Option<Vec<u8>>, String> {
    let info = match afc.get_file_info(BOOKS).await {
        Ok(info) => info,
        Err(idevice::IdeviceError::Afc(idevice::afc::errors::AfcError::ObjectNotFound)) => {
            return Ok(None)
        }
        Err(e) => return Err(format!("Books state inspection failed: {e}")),
    };
    if info.size > MAX_BOOKS || info.st_ifmt != "S_IFREG" || info.st_link_target.is_some() {
        return Err("Books state is too large or not a regular file".into());
    }
    let mut file = afc
        .open(BOOKS, AfcFopenMode::RdOnly)
        .await
        .map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    let result = (&mut file)
        .take(MAX_BOOKS as u64 + 1)
        .read_to_end(&mut bytes)
        .await
        .map_err(|e| e.to_string());
    let close = file.close().await.map_err(|e| e.to_string());
    result?;
    close?;
    if bytes.len() > MAX_BOOKS {
        return Err("Books state grew beyond the size limit".into());
    }
    Ok(Some(bytes))
}
async fn write_books(afc: &mut AfcClient, bytes: &[u8]) -> Result<(), String> {
    let mut file = afc
        .open(BOOKS, AfcFopenMode::WrOnly)
        .await
        .map_err(|e| e.to_string())?;
    let result = file.write_entire(bytes).await.map_err(|e| e.to_string());
    let close = file.close().await.map_err(|e| e.to_string());
    result?;
    close
}
fn needs_restoration(current: Option<&[u8]>, state: &BookBackup) -> Result<bool, String> {
    if current == state.original.as_deref() {
        return Ok(false);
    }
    if current == Some(state.manifest.as_slice()) {
        return Ok(true);
    }
    Err("Books sync state changed independently; recovery backup was retained without overwriting it".into())
}
async fn restore(
    afc: &mut AfcClient,
    directory: &Path,
    state: &mut BookBackup,
) -> Result<(), String> {
    let current = read_books(afc).await?;
    if needs_restoration(current.as_deref(), state)? {
        match &state.original {
            Some(bytes) => write_books(afc, bytes).await?,
            None => afc.remove(BOOKS).await.map_err(|e| e.to_string())?,
        }
    }
    if read_books(afc).await? != state.original {
        return Err("Books restoration did not verify".into());
    }
    // Remove the link itself, never recursively traverse it into the target container.
    for path in [format!("Airlock/Book/{}", state.link), state.link.clone()] {
        match afc.remove(&path).await {
            Ok(_)
            | Err(idevice::IdeviceError::Afc(idevice::afc::errors::AfcError::ObjectNotFound)) => {}
            Err(e) => return Err(e.to_string()),
        }
    }
    match afc.remove_all(&state.source).await {
        Ok(_) | Err(idevice::IdeviceError::Afc(idevice::afc::errors::AfcError::ObjectNotFound)) => {
        }
        Err(e) => return Err(e.to_string()),
    }
    state.restored = true;
    save_state(directory, state)
}

pub async fn install(
    id: u64,
    pairing: String,
    host: String,
    fallbacks: bool,
    expected: String,
    descriptor: String,
    source_path: String,
    recovery: String,
) -> Result<(), String> {
    if !uuid(&descriptor) {
        return Err("Invalid descriptor UUID".into());
    }
    let expected = normalized_container(&expected)?;
    let directory = recovery_directory(Path::new(&pairing), Path::new(&recovery))?;
    no_pending_recovery(Path::new(&pairing))?;
    let actual = bounded(
        id,
        35,
        crate::network::find(pairing.clone(), host, fallbacks),
    )
    .await?;
    if normalized_container(&actual)? != expected {
        return Err("PosterBoard container changed".into());
    }
    let logger = &Logger::silent();
    let target_parent_dir = format!("{expected}/{COLLECTIONS}");
    let folder = Path::new(&source_path);
    validate_source_tree(folder)?;
    let archive = build_folder_archive(&target_parent_dir, folder).map_err(|e| e.to_string())?;
    let token = random_hex(10)?;
    let source = format!("pawster-airlift-src-{token}");
    let link_destination = format!("pawster-airlift-link-{token}");
    let identifiers = vec![
        format!("../../{source}/p0/p1/p2/link"),
        format!("../../{source}/payload"),
    ];
    let destinations = vec![
        link_destination.clone(),
        format!("{link_destination}/{descriptor}"),
    ];
    let books_plist = build_books_plist(&identifiers).map_err(|e| e.to_string())?;
    let pairing_bytes = std::fs::read(&pairing).map_err(|e| e.to_string())?;
    let mut tunnel = bounded(id, 20, connect_tunnel(&pairing_bytes, &logger)).await?;
    let mut afc = bounded(id, 15, tunnel.connect_afc(&logger)).await?;
    let original = bounded(id, 15, read_books(&mut afc)).await?;
    let mut state = BookBackup {
        container: expected,
        original_hash: original.as_ref().map(|bytes| digest(bytes)),
        manifest_hash: digest(&books_plist),
        original,
        manifest: books_plist.clone(),
        source: source.clone(),
        link: link_destination.clone(),
        restored: false,
    };
    save_state(&directory, &state)?; // Durable backup before every mutation, including staging.
    let dest_name = descriptor;
    let result = bounded(id, 150, async {
            // ── STEP 1: Stage via streaming_zip_conduit
    let mut zip_stream = tunnel
        .wallpaper_service("com.apple.streaming_zip_conduit", logger)
        .await?;

    let mut zip_init_dict = plist::Dictionary::new();
    zip_init_dict.insert("MediaSubdir".to_string(), plist::Value::String(source.clone()));
    let mut init_buf = Vec::new();
    plist::to_writer_binary(&mut init_buf, &plist::Value::Dictionary(zip_init_dict))
        .map_err(|e| format!("encode MediaSubdir: {e}"))?;
    let init_len_bytes = (init_buf.len() as u32).to_be_bytes();
    zip_stream.write_all(&init_len_bytes).await.map_err(|e| format!("write MediaSubdir length: {e}"))?;
    zip_stream.write_all(&init_buf).await.map_err(|e| format!("write MediaSubdir body: {e}"))?;
    zip_stream.flush().await.map_err(|e| format!("flush: {e}"))?;

    zip_stream.write_all(&archive).await.map_err(|e| format!("write archive bytes: {e}"))?;
    zip_stream.flush().await.map_err(|e| format!("flush: {e}"))?;

    let mut resp_len_buf = [0u8; 4];
    zip_stream.read_exact(&mut resp_len_buf).await.map_err(|e| format!("read zip response length: {e}"))?;
    let resp_len = u32::from_be_bytes(resp_len_buf) as usize;
    if resp_len == 0 || resp_len > 1024 * 1024 { return Err("Invalid StreamingZip response size".into()); }
    let mut resp_body = vec![0u8; resp_len];
    zip_stream.read_exact(&mut resp_body).await.map_err(|e| format!("read zip response body: {e}"))?;
    drop(zip_stream);

    // Verify source objects in AFC
    let source_link = format!("{source}/p0/p1/p2/link");
    let source_payload = format!("{source}/payload");
    if afc.get_file_info(&source).await.is_err()
        || afc.get_file_info(&source_link).await.is_err()
        || afc.get_file_info(&source_payload).await.is_err()
    {

        return Err(format!("Stage verification failed for {dest_name}: extracted files not present in Media"));
    }
    logger.log("airlift: staged folder verified in AFC");

    // Ensure Airlock, Books and Books/Sync directories exist
    let _ = afc.mk_dir("Airlock").await;
    let _ = afc.mk_dir("Airlock/Book").await;
    let _ = afc.mk_dir("Books").await;
    let _ = afc.mk_dir("Books/Sync").await;
    let mut books_fd = afc
        .open("Books/Sync/Books.plist", AfcFopenMode::WrOnly)
        .await
        .map_err(|e| format!("AFC open Books.plist: {e:?}"))?;
    books_fd.write_entire(&books_plist).await.map_err(|e| format!("AFC write Books.plist: {e:?}"))?;
    let _ = books_fd.close().await;

    // ── STEP 2: AirTraffic Sync via com.apple.atc
    let mut atc_stream = tunnel
        .wallpaper_service("com.apple.atc", logger)
        .await?;

    // Wait for SyncAllowed
    let mut grappa_info: Option<(u32, u32, u32)> = None;
    for _ in 0..12 {
        match tokio::time::timeout(
            std::time::Duration::from_millis(1500),
            read_atc_dict(&mut atc_stream),
        )
        .await
        {
            Ok(Ok(dict)) => {
                if let Some(name) = atc_message_name(&dict) {
                    logger.log(format!("airlift: atc received '{name}' for '{dest_name}'"));
                    if name == "Capabilities" {
                        if let Some(params) = dict.get("Params").and_then(|p| p.as_dictionary()) {
                            if let Some(gi) = params.get("GrappaSupportInfo").and_then(|g| g.as_dictionary()) {
                                let ver = gi.get("version").and_then(|v| v.as_unsigned_integer()).unwrap_or(1) as u32;
                                let dt = gi.get("deviceType").and_then(|v| v.as_unsigned_integer()).unwrap_or(0) as u32;
                                let pv = gi.get("protocolVersion").and_then(|v| v.as_unsigned_integer()).unwrap_or(1) as u32;
                                logger.log(format!("airlift: captured GrappaSupportInfo: version={ver}, deviceType={dt}, protocolVersion={pv}"));
                                grappa_info = Some((ver, dt, pv));
                            }
                        }
                    }
                    if name == "SyncAllowed" {
                        break;
                    }
                }
            }
            Ok(Err(_)) => break,
            Err(_) => {}
        }
    }

    // HostInfo
    let mut host_info_dict = plist::Dictionary::new();
    host_info_dict.insert("Type".into(), plist::Value::String("iTunes".into()));
    host_info_dict.insert("Version".into(), plist::Value::String("13.7.0.161".into()));
    host_info_dict.insert("MacOSVersion".into(), plist::Value::String("15.0".into()));
    host_info_dict.insert("SyncHostName".into(), plist::Value::String("airlift".into()));
    let library_id = format!("{}-{}-{}-{}-{}", random_hex(4)?, random_hex(2)?, random_hex(2)?, random_hex(2)?, random_hex(6)?);
    host_info_dict.insert("LibraryID".into(), plist::Value::String(library_id));
    host_info_dict.insert("SyncedDataclasses".into(), plist::Value::Array(vec![plist::Value::String("Book".into())]));
    host_info_dict.insert("SyncedAssetTypes".into(), plist::Value::Array(vec![plist::Value::String("Book".into())]));
    host_info_dict.insert("Wakeable".into(), plist::Value::Boolean(false));

    let grappa_token = crate::grappa::generate_grappa_token(grappa_info, |s| logger.log(s));
    if grappa_token.is_none() { return Err("AirTraffic Grappa negotiation failed; no descriptor payload was sent".into()); }
    if let Some(ref token) = grappa_token {
        host_info_dict.insert("Grappa".into(), plist::Value::Data(token.clone()));
    }

    let mut host_info_params = plist::Dictionary::new();
    host_info_params.insert("HostInfo".into(), plist::Value::Dictionary(host_info_dict.clone()));
    host_info_params.insert("LocalCloudSupport".into(), plist::Value::Boolean(false));

    let msg_host_info = make_atc_msg("HostInfo", 0, Some(host_info_params));
    send_atc_dict(&mut atc_stream, &msg_host_info).await?;

    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    // RequestingSync
    let mut sync_req_params = plist::Dictionary::new();
    sync_req_params.insert("Dataclasses".into(), plist::Value::Array(vec![plist::Value::String("Book".into())]));
    sync_req_params.insert("DataclassAnchors".into(), plist::Value::Dictionary(plist::Dictionary::new()));
    sync_req_params.insert("HostInfo".into(), plist::Value::Dictionary(host_info_dict));
    if let Some(token) = grappa_token {
        sync_req_params.insert("Grappa".into(), plist::Value::Data(token));
    }

    let msg_sync_req = make_atc_msg("RequestingSync", 1, Some(sync_req_params));
    send_atc_dict(&mut atc_stream, &msg_sync_req).await?;

    // Wait for ReadyForSync
    let mut ready = false;
    for _ in 0..24 {
        match tokio::time::timeout(
            std::time::Duration::from_secs(5),
            read_atc_dict(&mut atc_stream),
        )
        .await
        {
            Ok(Ok(dict)) => {
                if let Some(name) = atc_message_name(&dict) {
                    logger.log(format!("airlift: atc sync state for '{dest_name}': '{name}'"));
                    if name == "Ping" {
                        let pong = make_atc_msg("Pong", 1, None);
                        let _ = send_atc_dict(&mut atc_stream, &pong).await;
                        continue;
                    }
                    if name == "ReadyForSync" || name == "AssetManifest" {
                        ready = true;
                        break;
                    }
                    if name == "SyncFailed" {
                        logger.log(format!("airlift: atc sync notice for '{dest_name}' (non-fatal; response details omitted)"));
                        continue;
                    }
                }
            }
            Ok(Err(e)) => return Err(format!("ATC read error: {e}")),
            Err(_) => {}
        }
    }

    if !ready {


        return Err(format!("AirTraffic: ReadyForSync not observed for {dest_name} (ensure Apple Books is installed)"));
    }
    logger.log(format!("airlift: ReadyForSync observed for '{dest_name}'"));

    // FinishedSyncingMetadata
    let mut sync_types = plist::Dictionary::new();
    sync_types.insert("Book".into(), plist::Value::Integer(1.into()));
    let mut meta_params = plist::Dictionary::new();
    meta_params.insert("SyncTypes".into(), plist::Value::Dictionary(sync_types));
    meta_params.insert("DataclassAnchors".into(), plist::Value::Dictionary(plist::Dictionary::new()));

    let msg_meta = make_atc_msg("FinishedSyncingMetadata", 1, Some(meta_params));
    send_atc_dict(&mut atc_stream, &msg_meta).await?;

    // Wait for AssetManifest
    let mut manifest_observed = false;
    for _ in 0..20 {
        match tokio::time::timeout(
            std::time::Duration::from_secs(5),
            read_atc_dict(&mut atc_stream),
        )
        .await
        {
            Ok(Ok(dict)) => {
                if let Some(name) = atc_message_name(&dict) {
                    logger.log(format!("airlift: atc manifest message for '{dest_name}': '{name}'"));
                    if name == "Ping" {
                        let pong = make_atc_msg("Pong", 1, None);
                        let _ = send_atc_dict(&mut atc_stream, &pong).await;
                        continue;
                    }
                    if name == "AssetManifest" {
                        manifest_observed = true;
                        break;
                    }
                    if name == "SyncFailed" {
                        logger.log(format!("airlift: atc manifest notice for '{dest_name}' (non-fatal; response details omitted)"));
                        continue;
                    }
                    if name == "SyncFinished" {
                        break;
                    }
                }
            }
            Ok(Err(e)) => return Err(format!("ATC manifest read error: {e}")),
            Err(_) => {}
        }
    }

    if !manifest_observed {


        return Err(format!("AirTraffic: AssetManifest not observed for {dest_name} (ensure Apple Books is installed)"));
    }
    logger.log(format!("airlift: AssetManifest observed for '{dest_name}'"));

    // Send FileComplete: 1) link -> link_dest, 2) payload -> link_dest/dest_name
    for (idx, (id, dest)) in identifiers.iter().zip(destinations.iter()).enumerate() {
        let mut file_complete_params = plist::Dictionary::new();
        file_complete_params.insert("AssetID".into(), plist::Value::String(id.clone()));
        file_complete_params.insert("Dataclass".into(), plist::Value::String("Book".into()));
        file_complete_params.insert("AssetPath".into(), plist::Value::String(dest.clone()));

        let msg_fc = make_atc_msg("FileComplete", 1, Some(file_complete_params));
        send_atc_dict(&mut atc_stream, &msg_fc).await?;
        logger.log(format!("airlift: FileComplete sent [{}/{}] -> {dest}", idx + 1, identifiers.len()));

        if idx + 1 < identifiers.len() {
            tokio::time::sleep(std::time::Duration::from_millis(900)).await;
        }
    }

    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    drop(atc_stream);


        Ok(())
    }).await;
    drop(afc); // A cancelled read may leave the protocol out of sync; use a fresh AFC session.
    let cleanup = tokio::time::timeout(Duration::from_secs(20), async {
        tokio::time::sleep(Duration::from_secs(2)).await;
        let mut fresh = tunnel.connect_afc(&logger).await?;
        restore(&mut fresh, &directory, &mut state).await
    })
    .await
    .map_err(|_| "AirTraffic cleanup timed out; recovery backup retained".to_string())
    .and_then(|r| r);
    match (result, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(e), Ok(())) => Err(e),
        (result, Err(e)) => Err(format!(
            "{}; synchronization recovery required: {e}",
            result
                .err()
                .unwrap_or_else(|| "Payload sent without target verification".into())
        )),
    }
}
pub async fn recover(
    id: u64,
    pairing: String,
    host: String,
    fallbacks: bool,
    recovery: String,
) -> Result<(), String> {
    let directory = recovery_directory(Path::new(&pairing), Path::new(&recovery))?;
    if !state_path(&directory)
        .try_exists()
        .map_err(|e| e.to_string())?
    {
        return Ok(());
    }
    let mut state = read_state(&state_path(&directory))?;
    if state.restored {
        return Ok(());
    }
    // Route setup remains shared; this query is read-only and invokes no injection engine.
    let actual = bounded(
        id,
        35,
        crate::network::find(pairing.clone(), host, fallbacks),
    )
    .await?;
    if normalized_container(&actual)? != state.container {
        return Err("Recovery belongs to a different PosterBoard container".into());
    }
    let bytes = std::fs::read(pairing).map_err(|e| e.to_string())?;
    let logger = Logger::silent();
    let mut tunnel = bounded(id, 20, connect_tunnel(&bytes, &logger)).await?;
    // Once restoration begins, finish it even if cancellation arrives.
    tokio::time::timeout(Duration::from_secs(20), async {
        let mut afc = tunnel.connect_afc(&logger).await?;
        restore(&mut afc, &directory, &mut state).await
    })
    .await
    .map_err(|_| "Synchronization recovery timed out".to_string())?
}

fn atc_message_name(dict: &plist::Dictionary) -> Option<String> {
    if let Some(plist::Value::String(s)) = dict.get("Command") {
        return Some(s.clone());
    }
    if let Some(plist::Value::String(s)) = dict.get("MessageName") {
        return Some(s.clone());
    }
    None
}

fn atc_session_number(dict: &plist::Dictionary) -> Option<i64> {
    if let Some(plist::Value::Integer(n)) = dict.get("Session") {
        return n.as_signed();
    }
    if let Some(plist::Value::Integer(n)) = dict.get("SessionNumber") {
        return n.as_signed();
    }
    None
}

fn make_atc_msg(
    command: &str,
    session: i64,
    params: Option<plist::Dictionary>,
) -> plist::Dictionary {
    let mut msg = plist::Dictionary::new();
    msg.insert("Command".into(), plist::Value::String(command.into()));
    msg.insert("Session".into(), plist::Value::Integer(session.into()));
    if let Some(p) = params {
        msg.insert("Params".into(), plist::Value::Dictionary(p));
    }
    msg
}

async fn read_atc_dict<S: AsyncReadExt + Unpin>(
    stream: &mut S,
) -> Result<plist::Dictionary, String> {
    let mut len_buf = [0u8; 4];
    stream
        .read_exact(&mut len_buf)
        .await
        .map_err(|e| format!("read length: {e}"))?;
    // AirTraffic protocol uses little-endian 32-bit length on Apple platforms.
    // We check both for maximum resilience.
    let len_le = u32::from_le_bytes(len_buf) as usize;
    let len_be = u32::from_be_bytes(len_buf) as usize;
    let len = if len_le > 0 && len_le <= 10 * 1024 * 1024 {
        len_le
    } else if len_be > 0 && len_be <= 10 * 1024 * 1024 {
        len_be
    } else {
        return Err(format!(
            "ATC message length invalid: raw={:?}, le={}, be={}",
            len_buf, len_le, len_be
        ));
    };
    let mut body = vec![0u8; len];
    stream
        .read_exact(&mut body)
        .await
        .map_err(|e| format!("read body (len={len}): {e}"))?;
    let val: plist::Value = plist::from_bytes(&body).map_err(|e| format!("decode plist: {e}"))?;
    match val {
        plist::Value::Dictionary(d) => Ok(d),
        _ => Err("expected plist dictionary".into()),
    }
}

async fn send_atc_dict<S: AsyncWriteExt + Unpin>(
    stream: &mut S,
    dict: &plist::Dictionary,
) -> Result<(), String> {
    let mut buf = Vec::new();
    let top = plist::Value::Dictionary(dict.clone());
    plist::to_writer_binary(&mut buf, &top).map_err(|e| format!("encode plist: {e}"))?;
    // AirTrafficHost natively uses little-endian length prefix
    let len_bytes = (buf.len() as u32).to_le_bytes();
    stream
        .write_all(&len_bytes)
        .await
        .map_err(|e| format!("write length: {e}"))?;
    stream
        .write_all(&buf)
        .await
        .map_err(|e| format!("write body: {e}"))?;
    stream.flush().await.map_err(|e| format!("flush: {e}"))?;
    Ok(())
}

// ---------------------------------------------------------------------------
// RSD Service Connection Helper (RSD Shim -> RSD Bare -> Lockdown Fallback)
// ---------------------------------------------------------------------------

fn build_folder_archive(
    target_parent_dir: &str,
    folder_path: &std::path::Path,
) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    use zip::{
        write::{ExtendedFileOptions, FileOptions},
        CompressionMethod, ZipWriter,
    };

    let target_tail = target_parent_dir.trim_start_matches('/');
    let mut buf = Vec::new();
    let mut zip = ZipWriter::new(io::Cursor::new(&mut buf));

    fn zip_opts(mode: u32) -> FileOptions<'static, ExtendedFileOptions> {
        let mut opts = FileOptions::default()
            .compression_method(CompressionMethod::Stored)
            .unix_permissions(mode);
        let mode_bytes = (mode as u16).to_le_bytes();
        let _ = opts.add_extra_data(0x5A53, Box::new(mode_bytes), false);
        opts
    }

    // META-INF
    zip.add_directory("META-INF/", zip_opts(0o040755))?;
    zip.start_file("META-INF/com.apple.ZipMetadata.plist", zip_opts(0o100600))?;
    let meta_plist: plist::Value = {
        let mut d = plist::Dictionary::new();
        d.insert("Version".to_owned(), plist::Value::Integer(2.into()));
        plist::Value::Dictionary(d)
    };
    let mut meta_buf = Vec::new();
    plist::to_writer_binary(&mut meta_buf, &meta_plist)?;
    zip.write_all(&meta_buf)?;

    // p0/p1/p2 dirs
    for dir in &["p0/", "p0/p1/", "p0/p1/p2/"] {
        zip.add_directory(*dir, zip_opts(0o040755))?;
    }

    // symlink: p0/p1/p2/link → ../../../{target_tail}
    zip.add_symlink(
        "p0/p1/p2/link",
        format!("../../../{target_tail}"),
        zip_opts(0o120777),
    )?;

    // target directory components
    let mut cursor = String::new();
    for component in target_tail.split('/') {
        if component.is_empty() {
            continue;
        }
        cursor.push_str(component);
        cursor.push('/');
        zip.add_directory(&cursor, zip_opts(0o040755))?;
    }

    // payload root directory
    zip.add_directory("payload/", zip_opts(0o040755))?;

    // Walk folder_path recursively and add directories & files
    fn walk_dir(
        dir: &std::path::Path,
        base: &std::path::Path,
        zip: &mut ZipWriter<io::Cursor<&mut Vec<u8>>>,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            let file_name = entry.file_name().to_string_lossy().to_string();
            if file_name == "__MACOSX" {
                continue;
            }
            let metadata = std::fs::symlink_metadata(&path)?;
            if metadata.file_type().is_symlink() || (!metadata.is_dir() && !metadata.is_file()) {
                return Err("Source contains a link or special file".into());
            }
            let rel = path.strip_prefix(base)?.to_string_lossy().to_string();
            if path.is_dir() {
                let dir_entry = format!("payload/{rel}/");
                zip.add_directory(&dir_entry, zip_opts(0o040755))?;
                walk_dir(&path, base, zip)?;
            } else if path.is_file() {
                let file_entry = format!("payload/{rel}");
                zip.start_file(&file_entry, zip_opts(0o100644))?;
                let data = std::fs::read(&path)?;
                zip.write_all(&data)?;
            }
        }
        Ok(())
    }

    validate_source_tree(folder_path)?;
    walk_dir(folder_path, folder_path, &mut zip)?;
    zip.finish()?;
    Ok(buf)
}

/// Build the Books.plist sync manifest.
/// Matches `build_books(identifiers)` in airlift.py.
fn build_books_plist(
    identifiers: &[String],
) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    let rows: Vec<plist::Value> = identifiers
        .iter()
        .enumerate()
        .map(|(i, id)| {
            let mut d = plist::Dictionary::new();
            d.insert("Persistent ID".to_owned(), plist::Value::String(id.clone()));
            d.insert(
                "Item ID".to_owned(),
                plist::Value::String((i + 1).to_string()),
            );
            d.insert("DSID".to_owned(), plist::Value::String("1".to_owned()));
            plist::Value::Dictionary(d)
        })
        .collect();
    let mut top = plist::Dictionary::new();
    top.insert("Books".to_owned(), plist::Value::Array(rows));
    let mut buf = Vec::new();
    plist::to_writer_binary(&mut buf, &top)?;
    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn target_is_only_a_container_root() {
        let root = "/var/mobile/Containers/Data/Application/E7A3AB7B-F016-4CD1-ACC7-16A6EDB58C2A";
        assert_eq!(
            normalized_container(&format!("/private{root}")).unwrap(),
            root
        );
        for bad in [
            format!("{root}/Library"),
            format!("{root}/../other"),
            "/var/mobile/Library".into(),
        ] {
            assert!(normalized_container(&bad).is_err());
        }
    }
    #[test]
    fn archive_preserves_hidden_files_and_rejects_symlinks() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join(".asset"), b"payload").unwrap();
        let archive = build_folder_archive("/var/mobile/target", dir.path()).unwrap();
        let mut zip = zip::ZipArchive::new(io::Cursor::new(archive)).unwrap();
        let mut bytes = Vec::new();
        zip.by_name("payload/.asset")
            .unwrap()
            .read_to_end(&mut bytes)
            .unwrap();
        assert_eq!(bytes, b"payload");
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(dir.path().join(".asset"), dir.path().join("alias"))
                .unwrap();
            assert!(build_folder_archive("/var/mobile/target", dir.path()).is_err());
        }
    }
    #[test]
    fn recovery_state_survives_restart_and_rejects_unowned_cleanup_names() {
        let dir = tempfile::tempdir().unwrap();
        let mut state = BookBackup {
            container:
                "/var/mobile/Containers/Data/Application/E7A3AB7B-F016-4CD1-ACC7-16A6EDB58C2A"
                    .into(),
            original_hash: Some(digest(b"previous")),
            manifest_hash: digest(b"new"),
            original: Some(b"previous".to_vec()),
            manifest: b"new".to_vec(),
            source: "pawster-airlift-src-01234567890123456789".into(),
            link: "pawster-airlift-link-01234567890123456789".into(),
            restored: false,
        };
        save_state(dir.path(), &state).unwrap();
        assert_eq!(
            read_state(&state_path(dir.path()))
                .unwrap()
                .original
                .unwrap(),
            b"previous"
        );
        assert!(!needs_restoration(Some(b"previous"), &state).unwrap());
        assert!(needs_restoration(Some(b"new"), &state).unwrap());
        assert!(needs_restoration(Some(b"independently changed"), &state).is_err());
        assert!(needs_restoration(None, &state).is_err());
        state.original = Some(b"corrupted".to_vec());
        save_state(dir.path(), &state).unwrap();
        assert!(read_state(&state_path(dir.path())).is_err());
        state.original = Some(b"previous".to_vec());
        state.source = "../other".into();
        save_state(dir.path(), &state).unwrap();
        assert!(read_state(&state_path(dir.path())).is_err());
    }
}
