//! Windows.Graphics.Capture session: monitor -> GPU copy into the shared
//! texture pool -> notify the host (SPEC Â§8.1).

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use windows::core::{IInspectable, Interface};
use windows::Foundation::TypedEventHandler;
use windows::Graphics::Capture::{
    Direct3D11CaptureFramePool, GraphicsCaptureItem, GraphicsCaptureSession,
};
use windows::Graphics::DirectX::DirectXPixelFormat;
use windows::Graphics::SizeInt32;
use windows::Win32::Foundation::HANDLE;
use windows::Win32::Graphics::Direct3D11::{ID3D11Texture2D, D3D11_TEXTURE2D_DESC};
use windows::Win32::Graphics::Gdi::HMONITOR;
use windows::Win32::System::WinRT::Direct3D11::IDirect3DDxgiInterfaceAccess;
use windows::Win32::System::WinRT::Graphics::Capture::IGraphicsCaptureItemInterop;

use crate::gpu::{Gpu, POOL_SIZE};
use crate::pool::SlotPool;
use crate::types::*;

static NEXT_SESSION_ID: AtomicI64 = AtomicI64::new(1);

struct ActiveGuard<'a>(&'a AtomicU32);

impl Drop for ActiveGuard<'_> {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::AcqRel);
    }
}

struct SlotTex {
    tex: ID3D11Texture2D,
    handle: HANDLE,
}

// SAFETY: the shared handle is an opaque value that is only passed to the host.
unsafe impl Send for SlotTex {}
unsafe impl Sync for SlotTex {}

struct Shared {
    size: (u32, u32),
    textures: Vec<SlotTex>,
    pool: SlotPool,
}

/// State reachable from the WinRT callbacks.
struct Inner {
    id: i64,
    gpu: Arc<Gpu>,
    state: Mutex<Shared>,
    /// Bumped whenever the pool is rebuilt; stale writes are discarded.
    generation: AtomicU64,
    stopped: AtomicBool,
    /// Number of callbacks currently executing.
    active: AtomicU32,
    min_interval: Duration,
    last_frame: Mutex<Instant>,
    on_frame: OnFrameFn,
    on_event: OnEventFn,
    user: usize,
}

impl Inner {
    fn emit(&self, kind: i32, width: i32, height: i32, code: i32, message: &str) {
        if let Some(f) = self.on_event {
            let mut ev = DcEvent { kind, width, height, code, message: [0; 256] };
            write_cstr(&mut ev.message, message);
            // SAFETY: callback and user pointer come from the host and outlive the session.
            unsafe { f(self.user as *mut c_void, self.id, &ev) };
        }
    }

    fn build_textures(&self, w: u32, h: u32) -> windows::core::Result<Vec<SlotTex>> {
        (0..POOL_SIZE)
            .map(|_| self.gpu.create_shared_texture(w, h).map(|(tex, handle)| SlotTex { tex, handle }))
            .collect()
    }

    fn on_frame_arrived(&self, pool: &Direct3D11CaptureFramePool) {
        // `stop()` waits for in-flight callbacks so the host can free its
        // callback context right after stopping.
        self.active.fetch_add(1, Ordering::AcqRel);
        let _guard = ActiveGuard(&self.active);
        if self.stopped.load(Ordering::Acquire) {
            return;
        }
        let Ok(frame) = pool.TryGetNextFrame() else { return };
        let Ok(content) = frame.ContentSize() else { return };
        let (w, h) = (content.Width.max(1) as u32, content.Height.max(1) as u32);

        // Source resolution changed -> rebuild frame pool and texture pool.
        let size_changed = self.state.lock().unwrap().size != (w, h);
        if size_changed {
            drop(frame);
            if let Err(e) = self.resize(pool, content) {
                self.emit(DC_EVENT_FAILED, 0, 0, DC_ERR_GPU, &format!("resize failed: {e}"));
            } else {
                self.emit(DC_EVENT_FRAME_SIZE, w as i32, h as i32, 0, "");
            }
            return;
        }

        // Frame-rate cap.
        {
            let mut last = self.last_frame.lock().unwrap();
            if last.elapsed() < self.min_interval.mul_f32(0.9) {
                return;
            }
            *last = Instant::now();
        }

        let Some(source) = frame
            .Surface()
            .ok()
            .and_then(|s| s.cast::<IDirect3DDxgiInterfaceAccess>().ok())
            .and_then(|a| unsafe { a.GetInterface::<ID3D11Texture2D>().ok() })
        else {
            return;
        };

        // Reserve a slot (short lock), copy without holding the lock.
        let gen_before = self.generation.load(Ordering::Acquire);
        let (slot, dest) = {
            let mut st = self.state.lock().unwrap();
            let Some(slot) = st.pool.begin_write() else { return }; // all pinned -> drop frame
            (slot, st.textures[slot].tex.clone())
        };

        let ok = unsafe {
            let mut desc = D3D11_TEXTURE2D_DESC::default();
            source.GetDesc(&mut desc);
            if desc.Width == w && desc.Height == h {
                let _g = self.gpu.lock.lock().unwrap();
                self.gpu.context.CopyResource(&dest, &source);
                self.gpu.flush_and_wait();
                true
            } else {
                false
            }
        };

        {
            let mut st = self.state.lock().unwrap();
            if self.generation.load(Ordering::Acquire) != gen_before {
                return; // pool was rebuilt meanwhile; slot index is stale
            }
            if ok {
                st.pool.publish(slot);
            } else {
                st.pool.abort_write(slot);
            }
        }
        if ok {
            if let Some(f) = self.on_frame {
                // SAFETY: host-provided callback.
                unsafe { f(self.user as *mut c_void, self.id) };
            }
        }
    }

    fn resize(&self, pool: &Direct3D11CaptureFramePool, size: SizeInt32) -> windows::core::Result<()> {
        let (w, h) = (size.Width.max(1) as u32, size.Height.max(1) as u32);
        let textures = self.build_textures(w, h)?;
        pool.Recreate(
            &self.gpu.winrt_device,
            DirectXPixelFormat::B8G8R8A8UIntNormalized,
            POOL_SIZE as i32,
            size,
        )?;
        let mut st = self.state.lock().unwrap();
        self.generation.fetch_add(1, Ordering::AcqRel);
        st.size = (w, h);
        st.textures = textures;
        st.pool.reset(POOL_SIZE);
        Ok(())
    }
}

pub struct Session {
    pub id: i64,
    pub owner_window: i64,
    inner: Arc<Inner>,
    frame_pool: Direct3D11CaptureFramePool,
    item: GraphicsCaptureItem,
    capture: GraphicsCaptureSession,
    frame_token: i64,
    closed_token: i64,
}

pub struct StartParams {
    pub hmonitor: isize,
    pub options: DcOptions,
    /// Used when `options.fps <= 0`: `min(display refresh, 60)`.
    pub default_fps: u32,
    pub on_frame: OnFrameFn,
    pub on_event: OnEventFn,
    pub user: *mut c_void,
}

pub fn capture_supported() -> bool {
    GraphicsCaptureSession::IsSupported().unwrap_or(false)
}

impl Session {
    pub fn start(gpu: Arc<Gpu>, p: StartParams) -> Result<Arc<Session>, (i32, String)> {
        let internal = |what: &str, e: windows::core::Error| (DC_ERR_CAPTURE_FAILED, format!("{what}: {e}"));

        if !capture_supported() {
            return Err((DC_ERR_UNSUPPORTED, "Screen capture is not supported on this Windows version".into()));
        }

        let interop = windows::core::factory::<GraphicsCaptureItem, IGraphicsCaptureItemInterop>()
            .map_err(|e| internal("capture interop", e))?;
        let item: GraphicsCaptureItem = unsafe { interop.CreateForMonitor(HMONITOR(p.hmonitor as *mut c_void)) }
            .map_err(|e| internal("CreateForMonitor", e))?;
        let size = item.Size().map_err(|e| internal("item size", e))?;
        let (w, h) = (size.Width.max(1) as u32, size.Height.max(1) as u32);

        let id = NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed);
        let fps = if p.options.fps > 0 { p.options.fps as u32 } else { p.default_fps.clamp(1, 60) };

        let inner = Arc::new(Inner {
            id,
            gpu: gpu.clone(),
            state: Mutex::new(Shared { size: (w, h), textures: Vec::new(), pool: SlotPool::new(POOL_SIZE) }),
            generation: AtomicU64::new(0),
            stopped: AtomicBool::new(false),
            active: AtomicU32::new(0),
            min_interval: Duration::from_secs_f64(1.0 / fps as f64),
            last_frame: Mutex::new(Instant::now() - Duration::from_secs(1)),
            on_frame: p.on_frame,
            on_event: p.on_event,
            user: p.user as usize,
        });
        let textures = inner
            .build_textures(w, h)
            .map_err(|e| (DC_ERR_GPU, format!("texture pool: {e}")))?;
        inner.state.lock().unwrap().textures = textures;

        let frame_pool = Direct3D11CaptureFramePool::CreateFreeThreaded(
            &gpu.winrt_device,
            DirectXPixelFormat::B8G8R8A8UIntNormalized,
            POOL_SIZE as i32,
            size,
        )
        .map_err(|e| internal("frame pool", e))?;

        let handler_inner = inner.clone();
        let frame_token = frame_pool
            .FrameArrived(&TypedEventHandler::<Direct3D11CaptureFramePool, IInspectable>::new(
                move |sender, _| {
                    if let Some(pool) = sender.as_ref() {
                        handler_inner.on_frame_arrived(pool);
                    }
                    Ok(())
                },
            ))
            .map_err(|e| internal("FrameArrived", e))?;

        let closed_inner = inner.clone();
        let closed_token = item
            .Closed(&TypedEventHandler::<GraphicsCaptureItem, IInspectable>::new(move |_, _| {
                if !closed_inner.stopped.load(Ordering::Acquire) {
                    closed_inner.emit(DC_EVENT_DISPLAY_LOST, 0, 0, DC_ERR_DISPLAY_NOT_FOUND, "Display was disconnected");
                }
                Ok(())
            }))
            .map_err(|e| internal("Closed", e))?;

        let capture = frame_pool.CreateCaptureSession(&item).map_err(|e| internal("CreateCaptureSession", e))?;
        // Best effort: older Windows builds lack these properties (C-5).
        let _ = capture.SetIsCursorCaptureEnabled(p.options.show_cursor != 0);
        let _ = capture.SetIsBorderRequired(false);
        capture.StartCapture().map_err(|e| internal("StartCapture", e))?;

        Ok(Arc::new(Session {
            id,
            owner_window: p.options.owner_window,
            inner,
            frame_pool,
            item,
            capture,
            frame_token,
            closed_token,
        }))
    }

    pub fn size(&self) -> (u32, u32) {
        self.inner.state.lock().unwrap().size
    }

    /// Pins and returns the current frame for the host to display.
    pub fn acquire(&self) -> Option<DcFrame> {
        let mut st = self.inner.state.lock().unwrap();
        let slot = st.pool.acquire()?;
        let (w, h) = st.size;
        Some(DcFrame { shared_handle: st.textures[slot].handle.0, width: w, height: h, slot: slot as i32 })
    }

    pub fn release(&self, slot: i32) {
        if slot >= 0 {
            self.inner.state.lock().unwrap().pool.release(slot as usize);
        }
    }

    /// Stops capture and releases the OS resources. Idempotent.
    pub fn stop(&self) {
        if self.inner.stopped.swap(true, Ordering::AcqRel) {
            return;
        }
        let _ = self.frame_pool.RemoveFrameArrived(self.frame_token);
        let _ = self.item.RemoveClosed(self.closed_token);
        let _ = self.capture.Close();
        let _ = self.frame_pool.Close();
        // Wait (bounded) for callbacks that were already running.
        let deadline = Instant::now() + Duration::from_millis(500);
        while self.inner.active.load(Ordering::Acquire) > 0 && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(1));
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.stop();
    }
}

