// Adapted from Mak5er/AirCard-iOS 40640c4d, MIT. Path queries only.
use idevice::pairing_file::PairingFile;
use idevice::provider::{IdeviceProvider, TcpProvider};
use idevice::remote_pairing::RpPairingFile;
use idevice::services::installation_proxy::InstallationProxyClient;
use idevice::services::lockdown::LockdownClient;
use idevice::{Idevice, IdeviceService, ReadWrite};
use std::ffi::{c_char, c_void, CString};
const RSD_PORT: u16 = 49152;
type ALLogCallback = Option<extern "C" fn(*mut c_void, *const c_char)>;

struct Logger {
    cb: ALLogCallback,
    ctx: *mut c_void,
}

unsafe impl Send for Logger {}
unsafe impl Sync for Logger {}

impl Logger {
    fn log(&self, msg: impl AsRef<str>) {
        let s = msg.as_ref();
        tracing::info!("{s}");
        if let Some(cb) = self.cb {
            if let Ok(c) = CString::new(s) {
                cb(self.ctx, c.as_ptr());
            }
        }
    }
}

enum AppDeviceTunnel {
    Rsd {
        adapter: idevice::tcp::handle::AdapterHandle,
        handshake: idevice::services::rsd::RsdHandshake,
    },
    Lockdown {
        provider: TcpProvider,
        pairing_file: PairingFile,
        legacy: bool,
    },
}

impl AppDeviceTunnel {
    async fn connect_installation_proxy(
        &mut self,
        logger: &Logger,
    ) -> Result<InstallationProxyClient, String> {
        match self {
            AppDeviceTunnel::Rsd { adapter, handshake } => handshake
                .connect::<InstallationProxyClient>(adapter)
                .await
                .map_err(|e| format!("InstallationProxy connect over RSD failed: {e:?}")),
            AppDeviceTunnel::Lockdown {
                provider,
                pairing_file,
                legacy,
            } => {
                let stream = connect_service_lockdown(
                    provider,
                    pairing_file,
                    *legacy,
                    "com.apple.mobile.installation_proxy",
                    logger,
                )
                .await?;
                let idevice = Idevice::new(stream, "Airlift");
                Ok(InstallationProxyClient::new(idevice))
            }
        }
    }
}

async fn connect_service_lockdown(
    provider: &TcpProvider,
    pairing_file: &PairingFile,
    legacy: bool,
    service_name: &str,
    logger: &Logger,
) -> Result<Box<dyn ReadWrite>, String> {
    logger.log(format!(
        "airlift: starting '{service_name}' via Lockdown..."
    ));
    let mut lockdown = LockdownClient::connect(provider)
        .await
        .map_err(|e| format!("Lockdown connect failed: {e:?}"))?;

    let _ = lockdown
        .start_session(pairing_file)
        .await
        .map_err(|e| format!("Lockdown start_session failed: {e:?}"))?;

    let (port, ssl) = lockdown
        .start_service(service_name)
        .await
        .map_err(|e| format!("Lockdown start_service('{service_name}') failed: {e:?}"))?;

    logger.log(format!(
        "airlift: '{service_name}' started on port {port} (ssl={ssl})"
    ));
    let mut idevice = provider
        .connect(port)
        .await
        .map_err(|e| format!("Connect to service port {port} failed: {e:?}"))?;

    if ssl {
        idevice
            .start_session(pairing_file, legacy)
            .await
            .map_err(|e| format!("Service TLS session failed: {e:?}"))?;
    }

    idevice
        .get_socket()
        .ok_or_else(|| "Failed to get socket from idevice".to_string())
}

static TARGET_HOST: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);
static EXTRA_TARGET_HOSTS: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

#[derive(Clone, Debug)]
pub enum CachedRouteMode {
    RsdRawRpPairing,
    RsdRemoteXpc,
    Lockdown,
}

#[derive(Clone, Debug)]
pub struct CachedRoute {
    pub host: String,
    pub mode: CachedRouteMode,
}

static LAST_WORKING_ROUTE: std::sync::Mutex<Option<CachedRoute>> = std::sync::Mutex::new(None);

pub fn set_last_working_route(route: CachedRoute) {
    if let Ok(mut lock) = LAST_WORKING_ROUTE.lock() {
        *lock = Some(route);
    }
}

pub fn get_last_working_route() -> Option<CachedRoute> {
    LAST_WORKING_ROUTE.lock().ok().and_then(|g| g.clone())
}

pub fn clear_last_working_route() {
    if let Ok(mut lock) = LAST_WORKING_ROUTE.lock() {
        *lock = None;
    }
}

pub fn set_target_host(host: Option<String>) {
    if let Ok(mut lock) = TARGET_HOST.lock() {
        *lock = host;
    }
}

pub fn set_target_hosts(hosts: Vec<String>) {
    if let Ok(mut lock) = EXTRA_TARGET_HOSTS.lock() {
        *lock = hosts;
    }
}

pub fn clear_target_hosts() {
    if let Ok(mut lock) = TARGET_HOST.lock() {
        *lock = None;
    }
    if let Ok(mut lock) = EXTRA_TARGET_HOSTS.lock() {
        lock.clear();
    }
    clear_last_working_route();
}

fn resolve_target_hosts() -> Vec<String> {
    let mut targets: Vec<String> = Vec::new();

    // 1. Configured target host from Swift / user setting
    if let Ok(guard) = TARGET_HOST.lock() {
        if let Some(ref host) = *guard {
            let h = host.trim();
            if !h.is_empty() && !targets.contains(&h.to_string()) {
                targets.push(h.to_string());
            }
        }
    }

    // 2. Extra candidates discovered by Swift (e.g. Wi-Fi en0, VPN interface)
    if let Ok(guard) = EXTRA_TARGET_HOSTS.lock() {
        for host in guard.iter() {
            let h = host.trim();
            if !h.is_empty() && !targets.contains(&h.to_string()) {
                targets.push(h.to_string());
            }
        }
    }

    // 3. Known default tunnel / loopback VPN gateway IPs (LocalDevVPN, SideStore, WireGuard)
    let default_fallbacks = ["10.7.0.1", "10.7.0.2", "10.7.0.3"];
    for fb in &default_fallbacks {
        let s = fb.to_string();
        if !targets.contains(&s) {
            targets.push(s);
        }
    }

    // Note: Do NOT auto-append 127.0.0.1 on iOS! Connecting to 127.0.0.1 causes remotepairingdeviced
    // to reject the control channel from local machine, enter an invalidated policy drop state,
    // and refuse all subsequent network connections until Developer Mode is toggled off and on.

    targets
}

async fn try_lockdown(
    target_ips: &[String],
    pf: &PairingFile,
    logger: &Logger,
    last_err: &mut String,
) -> Option<AppDeviceTunnel> {
    logger.log("airlift: attempting Lockdown connection on port 62078...");
    for ip_str in target_ips {
        let Ok(ip) = ip_str.parse::<std::net::Ipv4Addr>() else {
            continue;
        };
        if ip.is_loopback() {
            continue;
        }

        let provider = TcpProvider {
            addr: std::net::IpAddr::V4(ip),
            scope_id: None,
            pairing_file: pf.clone(),
            label: "Airlift".to_string(),
        };

        logger.log(format!(
            "airlift: connecting to lockdownd on {ip_str}:62078..."
        ));
        match tokio::time::timeout(
            std::time::Duration::from_millis(800),
            LockdownClient::connect(&provider),
        )
        .await
        {
            Ok(Ok(mut lockdown)) => match lockdown.start_session(pf).await {
                Ok(legacy) => {
                    logger.log(format!("airlift: connected to lockdownd on {ip_str}:62078 with TLS session (legacy={legacy})!"));
                    set_last_working_route(CachedRoute {
                        host: ip_str.clone(),
                        mode: CachedRouteMode::Lockdown,
                    });
                    return Some(AppDeviceTunnel::Lockdown {
                        provider,
                        pairing_file: pf.clone(),
                        legacy,
                    });
                }
                Err(e) => {
                    let err_msg =
                        format!("lockdownd start_session on {ip_str}:62078 failed: {e:?}");
                    logger.log(format!("airlift: {err_msg}"));
                    *last_err = err_msg;
                }
            },
            Ok(Err(e)) => {
                let err_msg = format!("connect to lockdownd on {ip_str}:62078 failed: {e:?}");
                logger.log(format!("airlift: {err_msg}"));
                *last_err = err_msg;
            }
            Err(_) => {
                let err_msg = format!("connect to lockdownd on {ip_str}:62078 timed out");
                logger.log(format!("airlift: {err_msg}"));
                *last_err = err_msg;
            }
        }
    }
    None
}

async fn try_rsd(
    target_ips: &[String],
    mut rpf: RpPairingFile,
    logger: &Logger,
    last_err: &mut String,
) -> Option<AppDeviceTunnel> {
    logger.log("airlift: attempting RSD tunnel on port 49152...");
    let extra_hosts: Vec<std::net::IpAddr> = target_ips
        .iter()
        .filter_map(|s| s.parse::<std::net::IpAddr>().ok())
        .filter(|ip| !ip.is_loopback())
        .collect();

    for ip_str in target_ips {
        let Ok(ip) = ip_str.parse::<std::net::Ipv4Addr>() else {
            continue;
        };
        if ip.is_loopback() {
            continue;
        }
        let socket_addr = std::net::SocketAddr::new(std::net::IpAddr::V4(ip), RSD_PORT);

        logger.log(format!(
            "airlift: trying RSD tunnel on {ip_str}:{RSD_PORT} via RemoteXPC..."
        ));
        match tokio::time::timeout(
            std::time::Duration::from_millis(2500),
            idevice_ffi::tunnel_provider::tunnel_create_remotexpc_multihost_async(
                socket_addr,
                "Airlift",
                &mut rpf,
                &extra_hosts,
            ),
        )
        .await
        {
            Ok(Ok((adapter, handshake))) => {
                logger.log(format!(
                    "airlift: tunnel connected successfully on {ip_str}:{RSD_PORT} via RemoteXPC!"
                ));
                set_last_working_route(CachedRoute {
                    host: ip_str.clone(),
                    mode: CachedRouteMode::RsdRemoteXpc,
                });
                return Some(AppDeviceTunnel::Rsd { adapter, handshake });
            }
            Ok(Err(failure)) => {
                let err_msg = format!(
                    "{ip_str}:{RSD_PORT}: {:?} ({:?})",
                    failure.error, failure.kind
                );
                logger.log(format!(
                    "airlift: RemoteXPC on {ip_str}:{RSD_PORT} failed: {err_msg}"
                ));
                *last_err = err_msg;

                if failure.kind
                    != idevice_ffi::tunnel_provider::TunnelFailureKind::TunnelFailureRsdUnreachable
                {
                    logger.log(format!(
                        "airlift: fallback trying raw RPPairing on {ip_str}:{RSD_PORT}..."
                    ));
                    match tokio::time::timeout(
                        std::time::Duration::from_millis(2500),
                        idevice_ffi::tunnel_provider::tunnel_create_rppairing_multihost_async(
                            socket_addr,
                            "Airlift",
                            &mut rpf,
                            &extra_hosts,
                        ),
                    )
                    .await
                    {
                        Ok(Ok((adapter, handshake))) => {
                            logger.log(format!("airlift: tunnel connected successfully on {ip_str}:{RSD_PORT} via raw RPPairing!"));
                            set_last_working_route(CachedRoute {
                                host: ip_str.clone(),
                                mode: CachedRouteMode::RsdRawRpPairing,
                            });
                            return Some(AppDeviceTunnel::Rsd { adapter, handshake });
                        }
                        Ok(Err(raw_failure)) => {
                            let is_pair_verify = raw_failure.kind == idevice_ffi::tunnel_provider::TunnelFailureKind::TunnelFailurePairVerify;
                            let extra_hint = if is_pair_verify {
                                " (iPhone rejected pairing keys — re-pair in Settings › Privacy & Security › Developer Mode)"
                            } else {
                                ""
                            };
                            logger.log(format!("airlift: raw RPPairing on {ip_str}:{RSD_PORT} failed: {:?}{extra_hint}", raw_failure.kind));
                            *last_err =
                                format!("{ip_str}:{RSD_PORT}: {:?}{extra_hint}", raw_failure.kind);
                        }
                        Err(_) => {
                            let err_msg =
                                format!("{ip_str}:{RSD_PORT}: raw RPPairing timed out after 2.5s");
                            logger.log(format!("airlift: {err_msg}"));
                            *last_err = err_msg;
                        }
                    }
                }
            }
            Err(_) => {
                let err_msg = format!("{ip_str}:{RSD_PORT}: RemoteXPC timed out after 2.5s");
                logger.log(format!("airlift: {err_msg}"));
                *last_err = err_msg;
            }
        }
    }
    None
}

async fn connect_tunnel(pairing_bytes: &[u8], logger: &Logger) -> Result<AppDeviceTunnel, String> {
    let mut last_error = String::new();
    let target_ips = resolve_target_hosts();

    let parsed_lockdown = PairingFile::from_bytes(pairing_bytes).ok();
    let parsed_rp = RpPairingFile::from_bytes(pairing_bytes).ok();

    if parsed_lockdown.is_none() && parsed_rp.is_none() {
        return Err("Pairing file is invalid: carries neither a valid Lockdown record nor Remote Pairing credentials.".to_string());
    }

    // 0. Fast-path: Check cached working route from previous operation
    if let Some(cached) = get_last_working_route() {
        if let Ok(ip) = cached.host.parse::<std::net::Ipv4Addr>() {
            let socket_addr = std::net::SocketAddr::new(std::net::IpAddr::V4(ip), RSD_PORT);
            let extra_hosts: Vec<std::net::IpAddr> = vec![std::net::IpAddr::V4(ip)];
            match cached.mode {
                CachedRouteMode::RsdRawRpPairing => {
                    if let Some(mut rpf) = RpPairingFile::from_bytes(pairing_bytes).ok() {
                        logger.log(format!(
                            "airlift: fast-reconnecting to RSD on {}:{RSD_PORT} (raw RPPairing)...",
                            cached.host
                        ));
                        if let Ok(Ok((adapter, handshake))) = tokio::time::timeout(
                            std::time::Duration::from_millis(2000),
                            idevice_ffi::tunnel_provider::tunnel_create_rppairing_multihost_async(
                                socket_addr,
                                "Airlift",
                                &mut rpf,
                                &extra_hosts,
                            ),
                        )
                        .await
                        {
                            logger.log(format!(
                                "airlift: tunnel connected via cached route on {}:{RSD_PORT} ✅",
                                cached.host
                            ));
                            return Ok(AppDeviceTunnel::Rsd { adapter, handshake });
                        }
                    }
                }
                CachedRouteMode::RsdRemoteXpc => {
                    if let Some(mut rpf) = RpPairingFile::from_bytes(pairing_bytes).ok() {
                        logger.log(format!(
                            "airlift: fast-reconnecting to RSD on {}:{RSD_PORT} (RemoteXPC)...",
                            cached.host
                        ));
                        if let Ok(Ok((adapter, handshake))) = tokio::time::timeout(
                            std::time::Duration::from_millis(2000),
                            idevice_ffi::tunnel_provider::tunnel_create_remotexpc_multihost_async(
                                socket_addr,
                                "Airlift",
                                &mut rpf,
                                &extra_hosts,
                            ),
                        )
                        .await
                        {
                            logger.log(format!(
                                "airlift: tunnel connected via cached route on {}:{RSD_PORT} ✅",
                                cached.host
                            ));
                            return Ok(AppDeviceTunnel::Rsd { adapter, handshake });
                        }
                    }
                }
                CachedRouteMode::Lockdown => {
                    if let Some(pf) = &parsed_lockdown {
                        let provider = TcpProvider {
                            addr: std::net::IpAddr::V4(ip),
                            scope_id: None,
                            pairing_file: pf.clone(),
                            label: "Airlift".to_string(),
                        };
                        logger.log(format!(
                            "airlift: fast-reconnecting to Lockdown on {}:62078...",
                            cached.host
                        ));
                        if let Ok(Ok(mut lockdown)) = tokio::time::timeout(
                            std::time::Duration::from_millis(1500),
                            LockdownClient::connect(&provider),
                        )
                        .await
                        {
                            if let Ok(legacy) = lockdown.start_session(pf).await {
                                logger.log(format!(
                                    "airlift: connected via cached Lockdown route on {}:62078 ✅",
                                    cached.host
                                ));
                                return Ok(AppDeviceTunnel::Lockdown {
                                    provider,
                                    pairing_file: pf.clone(),
                                    legacy,
                                });
                            }
                        }
                    }
                }
            }
            logger.log("airlift: cached route failed, re-probing routes...");
            clear_last_working_route();
        }
    }

    // 1. If Remote Pairing credentials exist, RSD is the primary modern protocol on iOS 17+.
    // Prioritize RSD FIRST to avoid wasted timeouts on lockdown port 62078.
    if let Some(rpf) = parsed_rp {
        if let Some(tunnel) = try_rsd(&target_ips, rpf, logger, &mut last_error).await {
            return Ok(tunnel);
        }
        logger.log("airlift: RSD route did not establish, checking Lockdown route...");
    }

    // 2. If RSD was not available or failed, try Lockdown route
    if let Some(pf) = &parsed_lockdown {
        if let Some(tunnel) = try_lockdown(&target_ips, pf, logger, &mut last_error).await {
            return Ok(tunnel);
        }
    }

    Err(format!(
        "Device connection failed: {last_error}. Ensure a loopback VPN (e.g. LocalDevVPN or SideStore WireGuard) is active."
    ))
}

async fn exploit_find_container(
    pairing_path: String,
    bundle_id: String,
    logger: &Logger,
) -> Result<String, String> {
    logger.log(format!(
        "airlift: looking up container for '{bundle_id}'..."
    ));
    let pairing_bytes = std::fs::read(&pairing_path)
        .map_err(|e| format!("Failed to read pairing file at {pairing_path}: {e}"))?;

    let mut tunnel = connect_tunnel(&pairing_bytes, logger).await?;
    let mut inst_client = tunnel.connect_installation_proxy(logger).await?;

    let apps = inst_client
        .get_apps(Some("Any"), Some(vec![bundle_id.clone()]))
        .await
        .map_err(|e| format!("InstallationProxy get_apps('{bundle_id}') failed: {e:?}"))?;

    if let Some(app_info) = apps.get(&bundle_id) {
        if let Some(dict) = app_info.as_dictionary() {
            if let Some(container) = dict.get("Container").and_then(|v| v.as_string()) {
                let normalized = if container.starts_with("/private/var/") {
                    container.replacen("/private/var/", "/var/", 1)
                } else {
                    container.to_string()
                };
                logger.log(format!(
                    "airlift: found container for '{bundle_id}': {normalized}"
                ));
                return Ok(normalized);
            }
        }
    }

    Err(format!(
        "Container for '{bundle_id}' not found in InstallationProxy response"
    ))
}

pub async fn find(pairing_path: String, host: String) -> Result<String, String> {
    let ip: std::net::Ipv4Addr = host.parse().map_err(|_| "Invalid tunnel IPv4 address")?;
    if ip.is_loopback() || ip.is_unspecified() || !ip.is_private() {
        return Err("Use a private VPN gateway address".into());
    }
    if get_last_working_route().is_some_and(|route| route.host != host) {
        clear_last_working_route();
    }
    set_target_host(Some(host));
    let logger = Logger {
        cb: None,
        ctx: std::ptr::null_mut(),
    };
    exploit_find_container(pairing_path, "com.apple.PosterBoard".into(), &logger).await
}
