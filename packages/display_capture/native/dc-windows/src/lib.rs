//! Windows platform layer of the Display Controller (SPEC §8.1).
//!
//! Exposes a small C ABI (see `windows/include/dc_core.h` in the plugin) used
//! by the thin C++ Flutter plugin shim.

mod capture;
mod enumerate;
mod gpu;
mod pool;
mod types;
mod watch;

use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::{Arc, Mutex, OnceLock};

use windows::core::Interface;
use windows::Win32::Graphics::Dxgi::IDXGIAdapter;

use capture::{Session, StartParams};
use gpu::Gpu;
use types::*;

struct Global {
    gpu: Option<Arc<Gpu>>,
    sessions: HashMap<i64, Arc<Session>>,
}

fn global() -> &'static Mutex<Global> {
    static G: OnceLock<Mutex<Global>> = OnceLock::new();
    G.get_or_init(|| Mutex::new(Global { gpu: None, sessions: HashMap::new() }))
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

fn set_error(msg: impl AsRef<str>) {
    let c = CString::new(msg.as_ref().replace('\0', " ")).unwrap_or_default();
    LAST_ERROR.with(|e| *e.borrow_mut() = c);
}

fn fail(code: i32, msg: impl AsRef<str>) -> i32 {
    log::warn!("dc error {code}: {}", msg.as_ref());
    set_error(msg);
    code
}

/// Returns the shared GPU, creating it on Flutter's adapter on first use.
fn gpu() -> Result<Arc<Gpu>, (i32, String)> {
    let g = global().lock().unwrap();
    g.gpu.clone().ok_or((DC_ERR_GPU, "dc_init was not called or the GPU could not be created".into()))
}

/// Initialises the GPU on `dxgi_adapter` (an `IDXGIAdapter*`, may be null for the
/// default hardware adapter). The adapter is not consumed; the caller keeps its
/// own reference.
#[no_mangle]
pub unsafe extern "C" fn dc_init(dxgi_adapter: *mut c_void) -> i32 {
    let adapter: Option<IDXGIAdapter> = if dxgi_adapter.is_null() {
        None
    } else {
        IDXGIAdapter::from_raw_borrowed(&dxgi_adapter).cloned()
    };
    match Gpu::new(adapter.as_ref()) {
        Ok(gpu) => {
            global().lock().unwrap().gpu = Some(gpu);
            DC_OK
        }
        Err(e) => fail(DC_ERR_GPU, format!("D3D11 device creation failed: {e}")),
    }
}

#[no_mangle]
pub extern "C" fn dc_shutdown() {
    let sessions: Vec<_> = {
        let mut g = global().lock().unwrap();
        g.sessions.drain().map(|(_, s)| s).collect()
    };
    for s in sessions {
        s.stop();
    }
    global().lock().unwrap().gpu = None;
}

#[no_mangle]
pub unsafe extern "C" fn dc_list_displays(out: *mut DcDisplay, cap: i32, count: *mut i32) -> i32 {
    if count.is_null() || (out.is_null() && cap > 0) {
        return fail(DC_ERR_INVALID_ARG, "null argument");
    }
    let supported = capture::capture_supported();
    let list = enumerate::enumerate_displays();
    *count = list.len() as i32;
    for (i, d) in list.iter().take(cap.max(0) as usize).enumerate() {
        *out.add(i) = enumerate::to_c_display(d, supported);
    }
    DC_OK
}

#[no_mangle]
pub unsafe extern "C" fn dc_set_display_change_callback(cb: OnDisplayChangeFn, user: *mut c_void) -> i32 {
    watch::set_callback(cb, user);
    DC_OK
}

#[no_mangle]
pub unsafe extern "C" fn dc_start_capture(
    display_id: *const c_char,
    options: *const DcOptions,
    on_frame: OnFrameFn,
    on_event: OnEventFn,
    user: *mut c_void,
    out: *mut DcStartResult,
) -> i32 {
    if display_id.is_null() || options.is_null() || out.is_null() {
        return fail(DC_ERR_INVALID_ARG, "null argument");
    }
    let id = CStr::from_ptr(display_id).to_string_lossy().into_owned();
    let options = *options;
    let gpu = match gpu() {
        Ok(g) => g,
        Err((c, m)) => return fail(c, m),
    };
    let Some(display) = enumerate::enumerate_displays().into_iter().find(|d| d.id == id) else {
        return fail(DC_ERR_DISPLAY_NOT_FOUND, format!("Display {id} is not connected"));
    };
    let default_fps = if display.refresh_hz >= 1.0 { display.refresh_hz.round() as u32 } else { 60 };

    let params = StartParams { hmonitor: display.hmonitor, options, default_fps, on_frame, on_event, user };
    match Session::start(gpu, params) {
        Ok(session) => {
            let (w, h) = session.size();
            *out = DcStartResult { session: session.id, width: w as i32, height: h as i32 };
            global().lock().unwrap().sessions.insert(session.id, session);
            DC_OK
        }
        Err((code, msg)) => fail(code, msg),
    }
}

fn session(id: i64) -> Option<Arc<Session>> {
    global().lock().unwrap().sessions.get(&id).cloned()
}

#[no_mangle]
pub unsafe extern "C" fn dc_acquire_frame(session_id: i64, out: *mut DcFrame) -> i32 {
    if out.is_null() {
        return fail(DC_ERR_INVALID_ARG, "null argument");
    }
    match session(session_id).and_then(|s| s.acquire()) {
        Some(f) => {
            *out = f;
            DC_OK
        }
        None => DC_ERR_INTERNAL,
    }
}

#[no_mangle]
pub extern "C" fn dc_release_frame(session_id: i64, slot: i32) {
    if let Some(s) = session(session_id) {
        s.release(slot);
    }
}

#[no_mangle]
pub extern "C" fn dc_stop_capture(session_id: i64) -> i32 {
    let s = global().lock().unwrap().sessions.remove(&session_id);
    if let Some(s) = s {
        s.stop();
    }
    DC_OK
}

/// Stops every session whose owner window is `native_window` (HWND).
#[no_mangle]
pub extern "C" fn dc_stop_sessions_for_window(native_window: i64) {
    let victims: Vec<_> = {
        let mut g = global().lock().unwrap();
        let ids: Vec<i64> =
            g.sessions.values().filter(|s| s.owner_window == native_window).map(|s| s.id).collect();
        ids.into_iter().filter_map(|id| g.sessions.remove(&id)).collect()
    };
    for s in victims {
        s.stop();
    }
}

#[no_mangle]
pub unsafe extern "C" fn dc_get_diagnostics(out: *mut DcDiagnostics) -> i32 {
    if out.is_null() {
        return fail(DC_ERR_INVALID_ARG, "null argument");
    }
    let mut d = DcDiagnostics {
        render_path: [0; 32],
        backend: [0; 64],
        gpu_name: [0; 128],
        driver: [0; 64],
    };
    write_cstr(&mut d.render_path, "d3d11-shared");
    write_cstr(&mut d.backend, "Windows.Graphics.Capture + Direct3D 11");
    if let Ok(g) = gpu() {
        write_cstr(&mut d.gpu_name, &g.adapter_name);
    }
    write_cstr(&mut d.driver, env!("CARGO_PKG_VERSION"));
    *out = d;
    DC_OK
}

/// Thread-local description of the last failing call (UTF-8, never null).
#[no_mangle]
pub extern "C" fn dc_last_error() -> *const c_char {
    LAST_ERROR.with(|e| e.borrow().as_ptr())
}
