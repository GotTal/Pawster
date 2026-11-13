pub mod archive;
#[cfg(feature = "device")]
mod airlift;
#[cfg(feature = "device")]
mod grappa;
mod ffi_util;
#[cfg(feature = "device")]
mod network;
#[cfg(feature = "device")]
mod operations;
#[cfg(feature = "device")]
mod pairing;

use ffi_util::{cstr, opt_str};
use std::ffi::c_char;

/// All returned strings are owned by this library. Null is accepted by pb_string_free.
#[no_mangle]
pub unsafe extern "C" fn pb_string_free(p: *mut c_char) {
    ffi_util::string_free(p);
}

#[no_mangle]
pub unsafe extern "C" fn pb_extract_zip(
    source: *const c_char,
    destination: *const c_char,
    output: *mut *mut c_char,
    error: *mut *mut c_char,
) -> i32 {
    if output.is_null() || error.is_null() {
        return 2;
    }
    *output = std::ptr::null_mut();
    *error = std::ptr::null_mut();
    let result = std::panic::catch_unwind(|| {
        archive::extract(
            std::path::Path::new(&opt_str(source, "")),
            std::path::Path::new(&opt_str(destination, "")),
        )
    });
    match result {
        Ok(Ok(report)) => {
            *output = cstr(serde_json::to_string(&report).unwrap());
            0
        }
        Ok(Err(message)) => {
            *error = cstr(message);
            1
        }
        Err(_) => {
            *error = cstr("Archive reader panicked; no injection was attempted");
            1
        }
    }
}

#[cfg(feature = "device")]
pub use operations::*;
