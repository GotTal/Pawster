use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    collections::HashSet,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
};
use unicode_normalization::UnicodeNormalization;

pub const MAX_ARCHIVE: u64 = 512 * 1024 * 1024;
pub const MAX_EXPANDED: u64 = 1024 * 1024 * 1024;
pub const MAX_FILE: u64 = 256 * 1024 * 1024;
pub const MAX_ENTRIES: usize = 20_000;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub files: Vec<String>,
    pub uncompressed_bytes: u64,
    pub sha256: String,
}

pub fn safe_relative(name: &str) -> Result<PathBuf, String> {
    if name.is_empty()
        || name.len() > 2048
        || name.starts_with('/')
        || name.contains('\\')
        || name.chars().any(char::is_control)
    {
        return Err("Invalid archive path".into());
    }
    let mut out = PathBuf::new();
    for part in name.trim_end_matches('/').split('/') {
        if part.is_empty()
            || part == "."
            || part == ".."
            || part.contains(':')
            || part.ends_with('.')
            || part.ends_with(' ')
        {
            return Err(format!("Unsafe archive component: {part}"));
        }
        out.push(part);
    }
    Ok(out)
}

pub fn extract(source: &Path, destination: &Path) -> Result<Report, String> {
    if !destination.is_absolute() || destination.exists() {
        return Err("Extraction destination must be a new absolute directory".into());
    }
    let file = File::open(source).map_err(|e| e.to_string())?;
    if file.metadata().map_err(|e| e.to_string())?.len() > MAX_ARCHIVE {
        return Err("Archive exceeds 512 MiB".into());
    }
    let mut zip = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    if zip.len() == 0 || zip.len() > MAX_ENTRIES {
        return Err("Invalid archive entry count".into());
    }
    let mut names = HashSet::new();
    let mut declared = 0u64;
    // Validate every entry before creating any files. Symlinks and special files are rejected.
    for i in 0..zip.len() {
        let entry = zip.by_index(i).map_err(|e| e.to_string())?;
        let rel = safe_relative(entry.name())?;
        let key: String = rel
            .to_string_lossy()
            .nfc()
            .flat_map(char::to_lowercase)
            .collect();
        if !names.insert(key) {
            return Err("Duplicate or case-colliding archive path".into());
        }
        if let Some(mode) = entry.unix_mode() {
            let kind = mode & 0o170000;
            if kind != 0 && kind != 0o100000 && kind != 0o040000 {
                return Err("Archive contains a symbolic link or special file".into());
            }
        }
        if entry.size() > MAX_FILE {
            return Err("Archive file exceeds 256 MiB".into());
        }
        declared = declared
            .checked_add(entry.size())
            .ok_or("Archive size overflow")?;
        if declared > MAX_EXPANDED {
            return Err("Expanded archive exceeds 1 GiB".into());
        }
    }
    fs::create_dir(destination).map_err(|e| e.to_string())?;
    let result = (|| {
        let mut files = vec![];
        let mut total = 0u64;
        for i in 0..zip.len() {
            let mut entry = zip.by_index(i).map_err(|e| e.to_string())?;
            let rel = safe_relative(entry.name())?;
            let target = destination.join(&rel);
            if entry.is_dir() {
                fs::create_dir_all(&target).map_err(|e| e.to_string())?;
                continue;
            }
            fs::create_dir_all(target.parent().ok_or("Missing parent")?)
                .map_err(|e| e.to_string())?;
            let mut output = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&target)
                .map_err(|e| e.to_string())?;
            let mut buf = [0u8; 64 * 1024];
            let mut written = 0u64;
            loop {
                let n = entry.read(&mut buf).map_err(|e| e.to_string())?;
                if n == 0 {
                    break;
                }
                written += n as u64;
                total += n as u64;
                if written > MAX_FILE || total > MAX_EXPANDED {
                    return Err("Expanded archive exceeds limits".into());
                }
                output.write_all(&buf[..n]).map_err(|e| e.to_string())?;
            }
            output.sync_all().map_err(|e| e.to_string())?;
            files.push(rel.to_string_lossy().replace('\\', "/"));
        }
        let mut hash = Sha256::new();
        let mut source = File::open(source).map_err(|e| e.to_string())?;
        let mut buf = [0u8; 64 * 1024];
        loop {
            let n = source.read(&mut buf).map_err(|e| e.to_string())?;
            if n == 0 {
                break;
            }
            hash.update(&buf[..n]);
        }
        Ok(Report {
            files,
            uncompressed_bytes: total,
            sha256: format!("{:x}", hash.finalize()),
        })
    })();
    if result.is_err() {
        let _ = fs::remove_dir_all(destination);
    }
    result
}
