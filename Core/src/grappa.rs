// Adapted from Mak5er/AirCard-iOS 40640c4d, MIT; see ThirdParty/AirCard-MIT.txt.
// A direct reference keeps the Objective-C bridge linked into the iOS app.
pub fn generate_grappa_token<F: Fn(&str)>(
    device: Option<(u32, u32, u32)>,
    log: F,
) -> Option<Vec<u8>> {
    #[cfg(target_os = "ios")]
    unsafe {
        unsafe extern "C" {
            fn PBGetGrappaToken(
                version: u32,
                device_type: u32,
                protocol: u32,
                buffer: *mut u8,
                maximum: usize,
                length: *mut usize,
                error: *mut std::ffi::c_char,
                error_length: usize,
            ) -> std::ffi::c_int;
        }
        let (version, device_type, protocol) = device.unwrap_or((1, 0, 1));
        let mut bytes = vec![0u8; 512];
        let mut length = 0;
        let mut error = [0; 256];
        let code = PBGetGrappaToken(
            version,
            device_type,
            protocol,
            bytes.as_mut_ptr(),
            bytes.len(),
            &mut length,
            error.as_mut_ptr(),
            error.len(),
        );
        if code != 0 || length == 0 || length > bytes.len() {
            log("AirTraffic Grappa negotiation failed");
            return None;
        }
        bytes.truncate(length);
        Some(bytes)
    }
    #[cfg(not(target_os = "ios"))]
    {
        let _ = (device, log);
        None
    }
}
