#![allow(dead_code)]
//! C ABI types shared with the C++ plugin shim (`include/dc_core.h`).

use std::ffi::c_void;

pub const DC_OK: i32 = 0;
pub const DC_ERR_DISPLAY_NOT_FOUND: i32 = -1;
pub const DC_ERR_PERMISSION_DENIED: i32 = -2;
pub const DC_ERR_UNSUPPORTED: i32 = -3;
pub const DC_ERR_GPU: i32 = -5;
pub const DC_ERR_CAPTURE_FAILED: i32 = -6;
pub const DC_ERR_INTERNAL: i32 = -7;
pub const DC_ERR_INVALID_ARG: i32 = -8;

pub const DC_KIND_PHYSICAL: i32 = 0;
pub const DC_KIND_VIRTUAL: i32 = 1;
pub const DC_KIND_UNKNOWN: i32 = 2;
pub const DC_KIND_BUILTIN: i32 = 3;

pub const DC_STATUS_AVAILABLE: i32 = 0;
pub const DC_STATUS_PERMISSION_DENIED: i32 = 1;
pub const DC_STATUS_UNSUPPORTED: i32 = 2;
pub const DC_STATUS_PROTECTED: i32 = 3;

pub const DC_EVENT_FRAME_SIZE: i32 = 0;
pub const DC_EVENT_STALLED: i32 = 1;
pub const DC_EVENT_RESUMED: i32 = 2;
pub const DC_EVENT_DISPLAY_LOST: i32 = 3;
pub const DC_EVENT_FAILED: i32 = 4;

#[repr(C)]
#[derive(Clone)]
pub struct DcDisplay {
    pub id: [u8; 128],
    pub name: [u8; 256],
    pub width_px: i32,
    pub height_px: i32,
    pub scale: f64,
    pub refresh_hz: f64,
    pub origin_x: i32,
    pub origin_y: i32,
    pub work_x: i32,
    pub work_y: i32,
    pub work_w: i32,
    pub work_h: i32,
    pub is_primary: i32,
    pub kind: i32,
    pub capture_status: i32,
    pub status_detail: [u8; 160],
}

impl Default for DcDisplay {
    fn default() -> Self {
        // SAFETY: all-zero is a valid bit pattern for this plain-data struct.
        unsafe { std::mem::zeroed() }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct DcOptions {
    pub max_width: i32,
    pub max_height: i32,
    pub fps: i32,
    pub show_cursor: i32,
    pub owner_window: i64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct DcStartResult {
    pub session: i64,
    pub width: i32,
    pub height: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct DcFrame {
    pub shared_handle: *mut c_void,
    pub width: u32,
    pub height: u32,
    pub slot: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct DcEvent {
    pub kind: i32,
    pub width: i32,
    pub height: i32,
    pub code: i32,
    pub message: [u8; 256],
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct DcDiagnostics {
    pub render_path: [u8; 32],
    pub backend: [u8; 64],
    pub gpu_name: [u8; 128],
    pub driver: [u8; 64],
}

pub type OnFrameFn = Option<unsafe extern "C" fn(user: *mut c_void, session: i64)>;
pub type OnEventFn =
    Option<unsafe extern "C" fn(user: *mut c_void, session: i64, event: *const DcEvent)>;
pub type OnDisplayChangeFn = Option<unsafe extern "C" fn(user: *mut c_void)>;

/// Copies `s` into a fixed zero-terminated buffer, truncating on a char boundary.
pub fn write_cstr<const N: usize>(dst: &mut [u8; N], s: &str) {
    dst.fill(0);
    let mut end = s.len().min(N - 1);
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    dst[..end].copy_from_slice(&s.as_bytes()[..end]);
}

/// Reads a zero-terminated buffer back into a `String`.
pub fn read_cstr(src: &[u8]) -> String {
    let end = src.iter().position(|&b| b == 0).unwrap_or(src.len());
    String::from_utf8_lossy(&src[..end]).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_cstr_truncates_on_char_boundary() {
        let mut buf = [0u8; 5];
        write_cstr(&mut buf, "ab\u{00d7}\u{00d7}"); // Ã— is 2 bytes
        assert_eq!(read_cstr(&buf), "ab\u{00d7}");
        assert_eq!(buf[4], 0);
    }

    #[test]
    fn write_cstr_roundtrip() {
        let mut buf = [0u8; 16];
        write_cstr(&mut buf, "DELL U2723QE");
        assert_eq!(read_cstr(&buf), "DELL U2723QE");
    }
}

