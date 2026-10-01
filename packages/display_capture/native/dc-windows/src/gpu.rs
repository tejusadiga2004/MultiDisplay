//! Shared D3D11 device (on Flutter's adapter) and the frame texture pool.

use std::sync::{Arc, Mutex};

use windows::core::Interface;
use windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
use windows::Win32::Foundation::{HANDLE, HMODULE};
use windows::Win32::Graphics::Direct3D::{
    D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_UNKNOWN, D3D_FEATURE_LEVEL_11_0,
};
use windows::Win32::Graphics::Direct3D11::{
    D3D11CreateDevice, ID3D11Device, ID3D11DeviceContext, ID3D11Multithread, ID3D11Query,
    ID3D11Texture2D, D3D11_BIND_RENDER_TARGET, D3D11_BIND_SHADER_RESOURCE,
    D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_QUERY_DESC, D3D11_QUERY_EVENT,
    D3D11_RESOURCE_MISC_SHARED, D3D11_SDK_VERSION, D3D11_TEXTURE2D_DESC, D3D11_USAGE_DEFAULT,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC};
use windows::Win32::Graphics::Dxgi::{IDXGIAdapter, IDXGIDevice, IDXGIResource};
use windows::Win32::System::WinRT::Direct3D11::CreateDirect3D11DeviceFromDXGIDevice;

pub const POOL_SIZE: usize = 3;

pub struct Gpu {
    pub device: ID3D11Device,
    pub context: ID3D11DeviceContext,
    pub winrt_device: IDirect3DDevice,
    pub adapter_name: String,
    /// Serialises use of the immediate context between capture threads.
    pub lock: Mutex<()>,
}

// SAFETY: the device is created with multithread protection enabled and all
// immediate-context use is additionally serialised through `lock`.
unsafe impl Send for Gpu {}
unsafe impl Sync for Gpu {}

impl Gpu {
    /// `adapter` MUST be the adapter Flutter renders on, otherwise the shared
    /// textures cannot be opened by the engine.
    pub fn new(adapter: Option<&IDXGIAdapter>) -> windows::core::Result<Arc<Gpu>> {
        unsafe {
            let mut device: Option<ID3D11Device> = None;
            let mut context: Option<ID3D11DeviceContext> = None;
            let levels = [D3D_FEATURE_LEVEL_11_0];
            D3D11CreateDevice(
                adapter,
                if adapter.is_some() { D3D_DRIVER_TYPE_UNKNOWN } else { D3D_DRIVER_TYPE_HARDWARE },
                HMODULE::default(),
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                Some(&levels),
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                Some(&mut context),
            )?;
            let device = device.ok_or_else(windows::core::Error::empty)?;
            let context = context.ok_or_else(windows::core::Error::empty)?;

            if let Ok(mt) = context.cast::<ID3D11Multithread>() {
                let _ = mt.SetMultithreadProtected(true);
            }

            let dxgi_device: IDXGIDevice = device.cast()?;
            let winrt_device: IDirect3DDevice =
                CreateDirect3D11DeviceFromDXGIDevice(&dxgi_device)?.cast()?;
            let adapter_name = dxgi_device
                .GetAdapter()
                .and_then(|a| a.GetDesc())
                .map(|d| {
                    let end = d.Description.iter().position(|&c| c == 0).unwrap_or(128);
                    String::from_utf16_lossy(&d.Description[..end])
                })
                .unwrap_or_default();

            Ok(Arc::new(Gpu { device, context, winrt_device, adapter_name, lock: Mutex::new(()) }))
        }
    }

    /// Creates one pool texture (BGRA8, shareable with Flutter's D3D11 device).
    pub fn create_shared_texture(&self, w: u32, h: u32) -> windows::core::Result<(ID3D11Texture2D, HANDLE)> {
        unsafe {
            let desc = D3D11_TEXTURE2D_DESC {
                Width: w,
                Height: h,
                MipLevels: 1,
                ArraySize: 1,
                Format: DXGI_FORMAT_B8G8R8A8_UNORM,
                SampleDesc: DXGI_SAMPLE_DESC { Count: 1, Quality: 0 },
                Usage: D3D11_USAGE_DEFAULT,
                BindFlags: (D3D11_BIND_SHADER_RESOURCE.0 | D3D11_BIND_RENDER_TARGET.0) as u32,
                CPUAccessFlags: 0,
                MiscFlags: D3D11_RESOURCE_MISC_SHARED.0 as u32,
            };
            let mut tex: Option<ID3D11Texture2D> = None;
            self.device.CreateTexture2D(&desc, None, Some(&mut tex))?;
            let tex = tex.ok_or_else(windows::core::Error::empty)?;
            let handle = tex.cast::<IDXGIResource>()?.GetSharedHandle()?;
            Ok((tex, handle))
        }
    }

    /// Flushes queued GPU work and waits (bounded) until it has completed, so
    /// another device reading the shared texture sees finished data.
    pub fn flush_and_wait(&self) {
        unsafe {
            let desc = D3D11_QUERY_DESC { Query: D3D11_QUERY_EVENT, MiscFlags: 0 };
            let mut query: Option<ID3D11Query> = None;
            if self.device.CreateQuery(&desc, Some(&mut query)).is_err() {
                self.context.Flush();
                return;
            }
            let Some(query) = query else {
                self.context.Flush();
                return;
            };
            self.context.End(&query);
            self.context.Flush();
            let start = std::time::Instant::now();
            loop {
                let mut done = 0u32;
                let hr = self.context.GetData(
                    &query,
                    Some(&mut done as *mut u32 as *mut _),
                    std::mem::size_of::<u32>() as u32,
                    0,
                );
                if hr.is_ok() && done != 0 {
                    break;
                }
                if start.elapsed() > std::time::Duration::from_millis(8) {
                    break;
                }
                std::hint::spin_loop();
            }
        }
    }
}
