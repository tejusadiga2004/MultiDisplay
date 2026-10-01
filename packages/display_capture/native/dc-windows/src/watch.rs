//! Display hot-plug / configuration change notification (SPEC §5.2).
//!
//! A hidden top-level window (message-only windows do not receive broadcast
//! messages) listens to `WM_DISPLAYCHANGE` / `WM_DEVICECHANGE` and reports a
//! debounced change (300 ms) through the registered callback.

use std::ffi::c_void;
use std::sync::{Mutex, Once};

use windows::core::w;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, KillTimer, RegisterClassW,
    SetTimer, TranslateMessage, CW_USEDEFAULT, MSG, WINDOW_EX_STYLE, WM_DEVICECHANGE,
    WM_DISPLAYCHANGE, WM_TIMER, WNDCLASSW, WS_POPUP,
};

use crate::types::OnDisplayChangeFn;

const DEBOUNCE_TIMER_ID: usize = 1;
const DEBOUNCE_MS: u32 = 300;
const DBT_DEVNODES_CHANGED: usize = 0x0007;

struct Callback {
    func: OnDisplayChangeFn,
    user: usize,
}

static CALLBACK: Mutex<Option<Callback>> = Mutex::new(None);
static START: Once = Once::new();

pub fn set_callback(func: OnDisplayChangeFn, user: *mut c_void) {
    *CALLBACK.lock().unwrap() = func.map(|_| Callback { func, user: user as usize });
    START.call_once(|| {
        std::thread::Builder::new()
            .name("dc-display-watch".into())
            .spawn(run_message_loop)
            .expect("spawn display watcher");
    });
}

fn fire() {
    let cb = CALLBACK.lock().unwrap();
    if let Some(cb) = cb.as_ref() {
        if let Some(f) = cb.func {
            // SAFETY: the callback and user pointer were supplied by the host.
            unsafe { f(cb.user as *mut c_void) };
        }
    }
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_DISPLAYCHANGE => {
            let _ = SetTimer(Some(hwnd), DEBOUNCE_TIMER_ID, DEBOUNCE_MS, None);
            LRESULT(0)
        }
        WM_DEVICECHANGE if wparam.0 == DBT_DEVNODES_CHANGED => {
            let _ = SetTimer(Some(hwnd), DEBOUNCE_TIMER_ID, DEBOUNCE_MS, None);
            LRESULT(0)
        }
        WM_TIMER if wparam.0 == DEBOUNCE_TIMER_ID => {
            let _ = KillTimer(Some(hwnd), DEBOUNCE_TIMER_ID);
            fire();
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn run_message_loop() {
    unsafe {
        let hinstance = GetModuleHandleW(None).unwrap_or_default();
        let class_name = w!("DcDisplayWatchWindow");
        let wc = WNDCLASSW {
            lpfnWndProc: Some(wnd_proc),
            hInstance: hinstance.into(),
            lpszClassName: class_name,
            ..Default::default()
        };
        RegisterClassW(&wc);
        let hwnd = CreateWindowExW(
            WINDOW_EX_STYLE(0),
            class_name,
            w!("dc-display-watch"),
            WS_POPUP,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            0,
            0,
            None,
            None,
            Some(hinstance.into()),
            None,
        );
        if hwnd.is_err() {
            log::error!("display watcher window could not be created");
            return;
        }
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}
