use crate::{
    ffi_util::{cstr, opt_str},
    pairing::{ALPairPinCb, ALPairReadyCb, ALPairResult},
};
use std::{
    collections::HashMap,
    ffi::{c_char, c_void},
    future::Future,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, OnceLock,
    },
    time::Duration,
};

static NEXT: AtomicU64 = AtomicU64::new(1);
type Flags = Mutex<HashMap<u64, Arc<AtomicBool>>>;
static FLAGS: OnceLock<Flags> = OnceLock::new();
static QUERY_LOCK: Mutex<()> = Mutex::new(());
fn flags() -> &'static Flags {
    FLAGS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[no_mangle]
pub extern "C" fn pb_operation_new() -> u64 {
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    flags()
        .lock()
        .unwrap()
        .insert(id, Arc::new(AtomicBool::new(false)));
    id
}
#[no_mangle]
pub extern "C" fn pb_operation_cancel(id: u64) {
    if let Some(f) = flags().lock().unwrap().get(&id) {
        f.store(true, Ordering::Release);
    }
}
#[no_mangle]
pub extern "C" fn pb_operation_free(id: u64) {
    flags().lock().unwrap().remove(&id);
}

pub async fn bounded<T>(
    id: u64,
    seconds: u32,
    future: impl Future<Output = Result<T, String>>,
) -> Result<T, String> {
    let flag = flags()
        .lock()
        .unwrap()
        .get(&id)
        .cloned()
        .ok_or("Invalid operation")?;
    if flag.load(Ordering::Acquire) {
        return Err("Cancelled".into());
    }
    let cancelled = async {
        loop {
            if flag.load(Ordering::Acquire) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    };
    tokio::select! {
        biased;
        _ = cancelled => Err("Cancelled".into()),
        result = tokio::time::timeout(Duration::from_secs(seconds.clamp(1, 180) as u64), future) =>
            result.map_err(|_| "Operation timed out; check pairing and LocalDevVPN".to_string())?,
    }
}

#[no_mangle]
pub unsafe extern "C" fn pb_pair(
    id: u64,
    seconds: u32,
    name: *const c_char,
    output_path: *const c_char,
    irk: *const c_char,
    ready: ALPairReadyCb,
    pin: ALPairPinCb,
    ctx: *mut c_void,
    output: *mut ALPairResult,
) -> i32 {
    crate::pairing::run_host(
        id,
        seconds,
        b"0.0.0.0\0".as_ptr().cast(),
        0,
        name,
        b"Mac17,7\0".as_ptr().cast(),
        output_path,
        irk,
        ready,
        pin,
        ctx,
        output,
    )
}
#[no_mangle]
pub unsafe extern "C" fn pb_pair_result_free(output: *mut ALPairResult) {
    crate::pairing::result_free(output);
}

#[no_mangle]
pub unsafe extern "C" fn pb_find_container(
    id: u64,
    seconds: u32,
    pairing_path: *const c_char,
    host: *const c_char,
    output: *mut *mut c_char,
    error: *mut *mut c_char,
) -> i32 {
    pb_find_container_with_policy(id, seconds, pairing_path, host, 1, output, error)
}

#[no_mangle]
pub unsafe extern "C" fn pb_find_container_with_policy(
    id: u64,
    seconds: u32,
    pairing_path: *const c_char,
    host: *const c_char,
    allow_fallbacks: u8,
    output: *mut *mut c_char,
    error: *mut *mut c_char,
) -> i32 {
    if output.is_null() || error.is_null() {
        return 2;
    }
    *output = std::ptr::null_mut();
    *error = std::ptr::null_mut();
    let path = opt_str(pairing_path, "");
    let host = opt_str(host, "10.7.0.1");
    let result = crate::ffi_util::run_with_large_stack("Pawster-query", move || {
        let _guard = QUERY_LOCK
            .lock()
            .map_err(|_| "Query lock poisoned".to_string())?;
        idevice_ffi::run_sync_local(bounded(
            id,
            seconds,
            crate::network::find(path, host, allow_fallbacks != 0),
        ))
    })
    .and_then(|r| r);
    match result {
        Ok(path) => {
            *output = cstr(path);
            0
        }
        Err(message) => {
            *error = cstr(message);
            1
        }
    }
}

// Both operations share the route lock with discovery. Cancellation during a
// transfer is followed by bounded cleanup before this call returns.
#[no_mangle]
pub unsafe extern "C" fn pb_airlift_install(
    id: u64,
    pairing: *const c_char,
    host: *const c_char,
    fallbacks: u8,
    container: *const c_char,
    descriptor: *const c_char,
    source: *const c_char,
    recovery: *const c_char,
    error: *mut *mut c_char,
) -> i32 {
    if error.is_null() {
        return 2;
    }
    *error = std::ptr::null_mut();
    let pairing = opt_str(pairing, "");
    let host = opt_str(host, "");
    let container = opt_str(container, "");
    let descriptor = opt_str(descriptor, "");
    let source = opt_str(source, "");
    let recovery = opt_str(recovery, "");
    let result = crate::ffi_util::run_with_large_stack("Pawster-Airlift", move || {
        let _guard = QUERY_LOCK
            .lock()
            .map_err(|_| "Connection lock poisoned".to_string())?;
        idevice_ffi::run_sync_local(crate::airlift::install(
            id,
            pairing,
            host,
            fallbacks != 0,
            container,
            descriptor,
            source,
            recovery,
        ))
    })
    .and_then(|r| r);
    match result {
        Ok(()) => 0,
        Err(message) => {
            *error = cstr(message);
            1
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn pb_airlift_recover(
    id: u64,
    pairing: *const c_char,
    host: *const c_char,
    fallbacks: u8,
    recovery: *const c_char,
    error: *mut *mut c_char,
) -> i32 {
    if error.is_null() {
        return 2;
    }
    *error = std::ptr::null_mut();
    let pairing = opt_str(pairing, "");
    let host = opt_str(host, "");
    let recovery = opt_str(recovery, "");
    let result = crate::ffi_util::run_with_large_stack("Pawster-Airlift-recovery", move || {
        let _guard = QUERY_LOCK
            .lock()
            .map_err(|_| "Connection lock poisoned".to_string())?;
        idevice_ffi::run_sync_local(crate::airlift::recover(
            id,
            pairing,
            host,
            fallbacks != 0,
            recovery,
        ))
    })
    .and_then(|r| r);
    match result {
        Ok(()) => 0,
        Err(message) => {
            *error = cstr(message);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn cancel_before_start_never_runs_future() {
        let id = pb_operation_new();
        pb_operation_cancel(id);
        let result: Result<(), String> = bounded(id, 1, async { panic!("must not run") }).await;
        assert_eq!(result.unwrap_err(), "Cancelled");
        pb_operation_free(id);
    }
    #[tokio::test]
    async fn cancellation_interrupts_wait() {
        let id = pb_operation_new();
        let cancel = async {
            tokio::time::sleep(Duration::from_millis(20)).await;
            pb_operation_cancel(id);
        };
        let work = bounded(id, 10, async {
            std::future::pending::<Result<(), String>>().await
        });
        let (_, result) = tokio::join!(cancel, work);
        assert_eq!(result.unwrap_err(), "Cancelled");
        pb_operation_free(id);
    }
    #[tokio::test]
    async fn timeout_interrupts_wait() {
        let id = pb_operation_new();
        let result: Result<(), String> = bounded(id, 1, std::future::pending()).await;
        assert!(result.unwrap_err().contains("timed out"));
        pb_operation_free(id);
    }
}
