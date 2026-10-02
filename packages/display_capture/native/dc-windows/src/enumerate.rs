//! Display enumeration (SPEC Â§5.2, Windows).

use std::collections::HashMap;
use std::mem::size_of;

use windows::core::{BOOL, PCWSTR};
use windows::Win32::Devices::Display::{
    DisplayConfigGetDeviceInfo, GetDisplayConfigBufferSizes, QueryDisplayConfig,
    DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME, DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME,
    DISPLAYCONFIG_DEVICE_INFO_HEADER, DISPLAYCONFIG_MODE_INFO, DISPLAYCONFIG_PATH_INFO,
    DISPLAYCONFIG_SOURCE_DEVICE_NAME, DISPLAYCONFIG_TARGET_DEVICE_NAME, QDC_ONLY_ACTIVE_PATHS,
};
use windows::Win32::Foundation::{LPARAM, RECT};
use windows::Win32::Graphics::Gdi::{
    EnumDisplayDevicesW, EnumDisplayMonitors, EnumDisplaySettingsW, GetMonitorInfoW, DEVMODEW,
    DISPLAY_DEVICEW, ENUM_CURRENT_SETTINGS, HDC, HMONITOR, MONITORINFO, MONITORINFOEXW,
};
use windows::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};

use crate::types::*;

// `DISPLAYCONFIG_VIDEO_OUTPUT_TECHNOLOGY` values (wingdi.h).
const OUTPUT_TECH_LVDS: i32 = 6;
const OUTPUT_TECH_DISPLAYPORT_EMBEDDED: i32 = 11;
const OUTPUT_TECH_UDI_EMBEDDED: i32 = 13;
const OUTPUT_TECH_INDIRECT_WIRED: i32 = 16;
const OUTPUT_TECH_INDIRECT_VIRTUAL: i32 = 17;
const OUTPUT_TECH_INTERNAL: i32 = 0x8000_0000_u32 as i32;

#[derive(Debug, Clone, PartialEq)]
pub struct DisplayRecord {
    pub id: String,
    pub name: String,
    pub width_px: i32,
    pub height_px: i32,
    pub scale: f64,
    pub refresh_hz: f64,
    pub origin_x: i32,
    pub origin_y: i32,
    pub work: (i32, i32, i32, i32), // x, y, w, h
    pub is_primary: bool,
    pub kind: i32,
    pub hmonitor: isize,
}

// ---------------------------------------------------------------------------
// Pure logic (unit tested)
// ---------------------------------------------------------------------------

/// D-6: a display whose name contains "Virtual" (case-insensitive) is virtual;
/// otherwise the OS output technology decides (indirect → virtual, embedded /
/// internal → built-in, anything else → physical); unknown if it can't be matched.
pub fn classify_kind(name: &str, output_technology: Option<i32>) -> i32 {
    if name.to_lowercase().contains("virtual") {
        return DC_KIND_VIRTUAL;
    }
    match output_technology {
        Some(OUTPUT_TECH_INDIRECT_WIRED) | Some(OUTPUT_TECH_INDIRECT_VIRTUAL) => DC_KIND_VIRTUAL,
        Some(OUTPUT_TECH_LVDS)
        | Some(OUTPUT_TECH_DISPLAYPORT_EMBEDDED)
        | Some(OUTPUT_TECH_UDI_EMBEDDED)
        | Some(OUTPUT_TECH_INTERNAL) => DC_KIND_BUILTIN,
        Some(_) => DC_KIND_PHYSICAL,
        None => DC_KIND_UNKNOWN,
    }
}

/// Order: primary first, then originX, originY, id (SPEC Â§5.1).
pub fn sort_displays(list: &mut [DisplayRecord]) {
    list.sort_by(|a, b| {
        b.is_primary
            .cmp(&a.is_primary)
            .then(a.origin_x.cmp(&b.origin_x))
            .then(a.origin_y.cmp(&b.origin_y))
            .then(a.id.cmp(&b.id))
    });
}

/// Replaces empty names with "Display n" (1-based, in sorted order).
pub fn apply_fallback_names(list: &mut [DisplayRecord]) {
    for (i, d) in list.iter_mut().enumerate() {
        if d.name.trim().is_empty() {
            d.name = format!("Display {}", i + 1);
        }
    }
}

// ---------------------------------------------------------------------------
// Win32
// ---------------------------------------------------------------------------

fn wide_to_string(w: &[u16]) -> String {
    let end = w.iter().position(|&c| c == 0).unwrap_or(w.len());
    String::from_utf16_lossy(&w[..end])
}

struct TargetInfo {
    friendly_name: String,
    device_path: String,
    output_technology: i32,
}

/// GDI device name (`\\.\DISPLAY1`) -> target info from the active display paths.
fn query_targets() -> HashMap<String, TargetInfo> {
    let mut map = HashMap::new();
    unsafe {
        let mut path_count = 0u32;
        let mut mode_count = 0u32;
        if GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &mut path_count, &mut mode_count)
            .is_err()
        {
            return map;
        }
        let mut paths = vec![DISPLAYCONFIG_PATH_INFO::default(); path_count as usize];
        let mut modes = vec![DISPLAYCONFIG_MODE_INFO::default(); mode_count as usize];
        if QueryDisplayConfig(
            QDC_ONLY_ACTIVE_PATHS,
            &mut path_count,
            paths.as_mut_ptr(),
            &mut mode_count,
            modes.as_mut_ptr(),
            None,
        )
        .is_err()
        {
            return map;
        }
        for path in paths.iter().take(path_count as usize) {
            let mut source = DISPLAYCONFIG_SOURCE_DEVICE_NAME::default();
            source.header = DISPLAYCONFIG_DEVICE_INFO_HEADER {
                r#type: DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
                size: size_of::<DISPLAYCONFIG_SOURCE_DEVICE_NAME>() as u32,
                adapterId: path.sourceInfo.adapterId,
                id: path.sourceInfo.id,
            };
            if DisplayConfigGetDeviceInfo(&mut source.header) != 0 {
                continue;
            }
            let gdi_name = wide_to_string(&source.viewGdiDeviceName);

            let mut target = DISPLAYCONFIG_TARGET_DEVICE_NAME::default();
            target.header = DISPLAYCONFIG_DEVICE_INFO_HEADER {
                r#type: DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME,
                size: size_of::<DISPLAYCONFIG_TARGET_DEVICE_NAME>() as u32,
                adapterId: path.targetInfo.adapterId,
                id: path.targetInfo.id,
            };
            let (friendly, device_path) = if DisplayConfigGetDeviceInfo(&mut target.header) == 0 {
                (
                    wide_to_string(&target.monitorFriendlyDeviceName),
                    wide_to_string(&target.monitorDevicePath),
                )
            } else {
                (String::new(), String::new())
            };
            map.insert(
                gdi_name,
                TargetInfo {
                    friendly_name: friendly,
                    device_path,
                    output_technology: path.targetInfo.outputTechnology.0,
                },
            );
        }
    }
    map
}

fn monitor_device_string(gdi_name: &[u16]) -> String {
    unsafe {
        let mut dd = DISPLAY_DEVICEW {
            cb: size_of::<DISPLAY_DEVICEW>() as u32,
            ..Default::default()
        };
        if EnumDisplayDevicesW(PCWSTR(gdi_name.as_ptr()), 0, &mut dd, 0).as_bool() {
            wide_to_string(&dd.DeviceString)
        } else {
            String::new()
        }
    }
}

unsafe extern "system" fn collect_monitor(
    monitor: HMONITOR,
    _hdc: HDC,
    _rect: *mut RECT,
    data: LPARAM,
) -> BOOL {
    let out = &mut *(data.0 as *mut Vec<HMONITOR>);
    out.push(monitor);
    BOOL(1)
}

/// Enumerates all active displays, including virtual ones.
pub fn enumerate_displays() -> Vec<DisplayRecord> {
    let mut monitors: Vec<HMONITOR> = Vec::new();
    unsafe {
        let _ = EnumDisplayMonitors(
            None,
            None,
            Some(collect_monitor),
            LPARAM(&mut monitors as *mut _ as isize),
        );
    }
    let targets = query_targets();
    let mut out = Vec::new();

    for hmon in monitors {
        unsafe {
            let mut info = MONITORINFOEXW::default();
            info.monitorInfo.cbSize = size_of::<MONITORINFOEXW>() as u32;
            if !GetMonitorInfoW(hmon, &mut info as *mut _ as *mut MONITORINFO).as_bool() {
                continue;
            }
            let gdi_name = wide_to_string(&info.szDevice);
            let rc = info.monitorInfo.rcMonitor;
            let work = info.monitorInfo.rcWork;

            let mut mode = DEVMODEW {
                dmSize: size_of::<DEVMODEW>() as u16,
                ..Default::default()
            };
            let (mut w, mut h, mut hz) = (rc.right - rc.left, rc.bottom - rc.top, 0.0);
            if EnumDisplaySettingsW(PCWSTR(info.szDevice.as_ptr()), ENUM_CURRENT_SETTINGS, &mut mode)
                .as_bool()
            {
                if mode.dmPelsWidth > 0 && mode.dmPelsHeight > 0 {
                    w = mode.dmPelsWidth as i32;
                    h = mode.dmPelsHeight as i32;
                }
                if mode.dmDisplayFrequency > 1 {
                    hz = mode.dmDisplayFrequency as f64;
                }
            }

            let (mut dpi_x, mut dpi_y) = (96u32, 96u32);
            let _ = GetDpiForMonitor(hmon, MDT_EFFECTIVE_DPI, &mut dpi_x, &mut dpi_y);

            let target = targets.get(&gdi_name);
            let mut name = target.map(|t| t.friendly_name.clone()).unwrap_or_default();
            if name.trim().is_empty() {
                name = monitor_device_string(&info.szDevice);
            }
            let id = match target {
                Some(t) if !t.device_path.is_empty() => format!("win:{}", t.device_path),
                _ => format!("win:{}", gdi_name),
            };
            let kind = classify_kind(&name, target.map(|t| t.output_technology));

            out.push(DisplayRecord {
                id,
                name,
                width_px: w,
                height_px: h,
                scale: dpi_x as f64 / 96.0,
                refresh_hz: hz,
                origin_x: rc.left,
                origin_y: rc.top,
                work: (work.left, work.top, work.right - work.left, work.bottom - work.top),
                is_primary: (info.monitorInfo.dwFlags & 1) != 0, // MONITORINFOF_PRIMARY
                kind,
                hmonitor: hmon.0 as isize,
            });
        }
    }
    sort_displays(&mut out);
    apply_fallback_names(&mut out);
    out
}

pub fn to_c_display(d: &DisplayRecord, capture_supported: bool) -> DcDisplay {
    let mut c = DcDisplay::default();
    write_cstr(&mut c.id, &d.id);
    write_cstr(&mut c.name, &d.name);
    c.width_px = d.width_px;
    c.height_px = d.height_px;
    c.scale = d.scale;
    c.refresh_hz = d.refresh_hz;
    c.origin_x = d.origin_x;
    c.origin_y = d.origin_y;
    c.work_x = d.work.0;
    c.work_y = d.work.1;
    c.work_w = d.work.2;
    c.work_h = d.work.3;
    c.is_primary = d.is_primary as i32;
    c.kind = d.kind;
    if capture_supported {
        c.capture_status = DC_STATUS_AVAILABLE;
    } else {
        c.capture_status = DC_STATUS_UNSUPPORTED;
        write_cstr(
            &mut c.status_detail,
            "Screen capture is not supported on this version of Windows",
        );
    }
    c
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(id: &str, x: i32, y: i32, primary: bool, name: &str) -> DisplayRecord {
        DisplayRecord {
            id: id.into(),
            name: name.into(),
            width_px: 1920,
            height_px: 1080,
            scale: 1.0,
            refresh_hz: 60.0,
            origin_x: x,
            origin_y: y,
            work: (x, y, 1920, 1040),
            is_primary: primary,
            kind: DC_KIND_PHYSICAL,
            hmonitor: 0,
        }
    }

    #[test]
    fn name_containing_virtual_wins() {
        assert_eq!(classify_kind("Virtual Display 1", Some(5)), DC_KIND_VIRTUAL);
        assert_eq!(classify_kind("my VIRTUAL monitor", None), DC_KIND_VIRTUAL);
    }

    #[test]
    fn indirect_output_is_virtual() {
        assert_eq!(classify_kind("Generic Monitor", Some(16)), DC_KIND_VIRTUAL);
        assert_eq!(classify_kind("Generic Monitor", Some(17)), DC_KIND_VIRTUAL);
        assert_eq!(classify_kind("Dell U2723QE", Some(10)), DC_KIND_PHYSICAL);
        assert_eq!(classify_kind("Dell U2723QE", None), DC_KIND_UNKNOWN);
    }

    #[test]
    fn embedded_or_internal_output_is_builtin() {
        assert_eq!(classify_kind("Laptop Panel", Some(6)), DC_KIND_BUILTIN);
        assert_eq!(classify_kind("Laptop Panel", Some(11)), DC_KIND_BUILTIN);
        assert_eq!(classify_kind("Laptop Panel", Some(13)), DC_KIND_BUILTIN);
        assert_eq!(classify_kind("Laptop Panel", Some(i32::MIN)), DC_KIND_BUILTIN);
        assert_eq!(classify_kind("Virtual Panel", Some(11)), DC_KIND_VIRTUAL);
    }

    #[test]
    fn sorted_primary_first_then_origin() {
        let mut v = vec![
            rec("c", 1920, 0, false, "C"),
            rec("a", -1920, 0, false, "A"),
            rec("p", 0, 0, true, "P"),
            rec("b", 1920, -100, false, "B"),
        ];
        sort_displays(&mut v);
        let ids: Vec<_> = v.iter().map(|d| d.id.as_str()).collect();
        assert_eq!(ids, ["p", "a", "b", "c"]);
    }

    #[test]
    fn empty_names_get_numbered_fallback() {
        let mut v = vec![rec("p", 0, 0, true, ""), rec("a", 1920, 0, false, "  ")];
        apply_fallback_names(&mut v);
        assert_eq!(v[0].name, "Display 1");
        assert_eq!(v[1].name, "Display 2");
    }
}

