# Display Controller — Multi-Display Mirroring App
### Implementation Specification v1.0

Platforms: Windows, macOS, Linux (Flutter Desktop)

---

## 0. How to read this document

* **MUST / MUST NOT / SHOULD** are used in the RFC-2119 sense.
* Everything the original brief states is a **Requirement** (`R-n`, §1).
* Where the brief was silent or ambiguous, this spec does **not** leave a gap and does **not** silently guess. Every such point is listed in **§2 Decision Register** as `D-n`, with the chosen behaviour and the reason. A reviewer can overturn any `D-n` without touching the rest of the spec; the affected sections are referenced.
* Where a platform physically cannot satisfy a requirement, it is listed in **§3 Platform Constraints** (`C-n`) with the exact degraded behaviour. These are facts about the OS/Flutter, not choices.
* §4 onward is the buildable design.

---

## 1. Requirements (verbatim intent from the brief)

| ID | Requirement |
|----|-------------|
| R-1 | App has a window named **Display Controller** listing **all** displays connected to the machine, **including virtual displays**. |
| R-2 | Each list row has a **toggle** to select that display. Default **Off**. |
| R-3 | When the app is launched, or when the user enables a display, a new window called **DisplayWindow** is created showing the live contents of that display. One DisplayWindow per selected display. |
| R-4 | DisplayWindow is **always on top**, has a **transparent title bar**, and has the **normal window close button**. |
| R-5 | Closing a DisplayWindow turns the corresponding toggle **Off** in the Display Controller. |
| R-6 | Every DisplayWindow shows, **bottom-right**, a small text with the **display name and its resolution**. |
| R-7 | Built with **Flutter Desktop**. Layered: **UI layer → API layer → Platform layer**. |
| R-8 | UI layer holds Display Controller and DisplayWindow plus their view models/logic. DisplayWindow uses **GPU-accelerated frame rendering**: DirectX on Windows, Metal on macOS, Vulkan on Linux. |
| R-9 | API layer is used by the UI layer, **uniform across platforms**, provides (a) enumerate displays, (b) start/stop screen recording. Best design for connecting the accelerated renderer to the API is decided here (§6). |
| R-10 | Platform layer is separate native code per OS. **Windows**: Rust, DirectX (or better). **macOS**: Swift package, Metal for rendering, ScreenCaptureKit for capture. **Linux**: Vulkan for acceleration. |
| R-11 | Flutter bridges (plugin/FFI/channels) as required. |

---

## 2. Decision Register (items the brief left open)

Each row is binding for implementation. "Confirm?" records product-owner sign-off. **All decisions D-1 to D-15 are now confirmed** (D-1, D-2, D-6, D-14 amended by the owner; all others accepted as written).

| ID | Open point | Decision | Why | Confirm? |
|----|------------|----------|-----|----------|
| D-1 | R-2 says default Off, R-3 says windows are created "when the app is launched". | **CONFIRMED by product owner.** The Off default applies **on first launch ever** (no windows). The set of selected displays is **saved between relaunches**; on every later launch, a DisplayWindow is created **only** for displays that were On when the app last ran **and are still connected**. No window is created for any other display. | Owner decision. | Confirmed |
| D-2 | What "display contents" means. | **CONFIRMED.** Live **mirror** (screen capture) of the whole display, **including the cursor**, **fitted within the DisplayWindow size** (whole display always visible, aspect preserved, letterboxed as in D-3). Capture runs at the display's native pixel resolution; no audio. | Owner decision. | Confirmed |
| D-3 | Where a DisplayWindow appears. | On the **first connected display that is not the mirrored one**; if only one display exists, on that same display. Initial client size = source aspect ratio, fitted to **50 % of that target display's work area** (min 320×180). Window is resizable; aspect ratio is **not** locked; video is letterboxed (`BoxFit.contain`, black bars). | Avoids placing a mirror directly over its own source. | Confirmed |
| D-4 | Feedback loop (window on top of the display it mirrors would capture itself). | Platforms that can exclude our own windows from capture MUST do so (Win: `WDA_EXCLUDEFROMCAPTURE`; macOS: `SCContentFilter excludingWindows`). Linux cannot (C-3); documented limitation. | Prevents infinite-mirror effect. | No |
| D-5 | Which fields "Name" and "resolution" use (R-6). | Name = OS display name (§5.2). Resolution = **native pixel** resolution of the display, formatted `{w}×{h}` (U+00D7), e.g. `Dell U2723QE · 3840×2160`. Not the window size, not HiDPI-scaled points. | Unambiguous and stable. | No |
| D-6 | What "virtual displays" are detected as. | Any display the OS reports as capturable, incl. indirect/virtual adapters (Win), `CGVirtualDisplay`/Sidecar/Dummy-plug (mac), virtual outputs (Linux). Row shows a **Virtual** badge when the OS can positively identify it as such (§5.2), otherwise no badge. **Additionally (owner decision):** on every OS, a display whose **name contains the word "Virtual"** (case-insensitive substring) is classified `virtual`. This name rule is applied in addition to the OS-specific rules and wins over `physical`/`unknown`. | OS APIs don't always expose it. | Confirmed |
| D-7 | Hot-plug. | Display list updates live. A newly connected display appears with toggle Off. A disconnected display's DisplayWindow closes automatically, the row disappears; its saved selection is **deleted**. On reconnect it appears **Off**. | Predictable; no surprise windows. | No |
| D-8 | Closing the Display Controller. | Closes all DisplayWindows and **quits** the app. Closing the last DisplayWindow does **not** quit. | Controller is the app's main window. | No |
| D-9 | Display not capturable (permission denied, protected, unsupported). | Row stays visible, toggle is **disabled**, with a secondary line giving the reason (§7.3). | R-1 says list all displays. | No |
| D-10 | Frame rate. | Target = `min(display refresh rate, 60)` fps. Capture delivers only when content changes where the OS supports that (WGC, SCK); last frame is retained. | Power vs smoothness. | No |
| D-11 | Mouse/keyboard interaction inside DisplayWindow. | **None forwarded.** The window is view-only. Clicks on video do nothing (except window drag in the title-bar strip). | Brief says display only. | No |
| D-12 | Languages / theming. | English only (strings externalised in ARB files for later translation). Material 3, follows system light/dark. | Not specified. | No |
| D-13 | Multi-window mechanism in Flutter. | **CONFIRMED (owner decision): Flutter's experimental built-in windowing API** (Flutter `main` channel, enabled with `flutter config --enable-windowing`). **One engine, one isolate, one `FlutterView` per window** (Display Controller + each DisplayWindow). No `desktop_multi_window` package. Facts about the installed SDK that drive the design are in §9.0a. Anything that API lacks (always-on-top, transparent title bar, window position, capture exclusion) is done in the `display_capture` plugin using the native window handle the API exposes. | Owner decision. | Confirmed |
| D-14 | Min OS versions. | Windows **10 2004 (build 19041)**; macOS **14.0** (owner decision; ScreenCaptureKit; Metal required); Linux: GTK 3, Mesa/Vulkan 1.1+ driver, PipeWire ≥ 0.3.40 + xdg-desktop-portal ScreenCast v4+ **or** X11 session (fallback §8.3). | API availability. | No |
| D-15 | Distribution/signing. | Out of scope for v1 (dev builds). macOS app **not sandboxed**; hardened runtime allowed. | Not specified. | No |


---

## 3. Platform Constraints (hard facts, not choices)

| ID | Fact | Resulting behaviour |
|----|------|---------------------|
| C-1 | **Flutter's own rasterizer** is Impeller/Metal on macOS, OpenGL-via-**ANGLE→Direct3D 11** on Windows, and **OpenGL** (GTK embedder) on Linux. Flutter's Linux embedder cannot be switched to Vulkan today. | The "accelerated rendering" in R-8 is satisfied as: frames are produced, converted and scaled **on the GPU in the platform layer** (D3D11 / Metal / **Vulkan**) and handed to Flutter as a **GPU texture with zero CPU copy**. On Linux the last hop is Vulkan→OpenGL via external-memory interop (§8.3). If a driver lacks the interop extensions, fall back to a CPU `PixelBufferTexture` and report `renderPath = "cpu-fallback"` in diagnostics. |
| C-2 | Linux Wayland has **no protocol for always-on-top** or for clients to pick their screen position. | R-4 "always on top" is guaranteed on Windows, macOS and Linux/X11 (`_NET_WM_STATE_ABOVE`). On Wayland it is **best-effort** (request via GTK; honoured by some compositors). The Display Controller shows a one-time info banner on Wayland: "Always-on-top may not be honored by your compositor." Window placement per D-3 on Wayland is also best-effort. |
| C-3 | Linux screen capture APIs cannot exclude windows of the caller. | Feedback loop (D-4) is possible if a DisplayWindow sits on its own source display. App prefers D-3 placement; with a single display a warning is logged and a one-time banner is shown. |
| C-4 | Linux Wayland capture goes through the **xdg-desktop-portal** picker; the app cannot choose the monitor silently. | See §8.3 flow and error `WRONG_SOURCE`. |
| C-5 | Windows draws a yellow capture border around Windows.Graphics.Capture sources unless disabled (Win 11 / build ≥ 22000 for desktop apps). | Set `IsBorderRequired = false` when supported; otherwise border stays (not an error). |
| C-6 | A Windows "transparent title bar with normal close button" cannot be obtained from the stock frame. | See §9.5 (client-extended frame + native `HTCLOSE` hit-test). |
| C-7 | Flutter's windowing API (`package:flutter/src/widgets/_window.dart`) is **experimental and `@internal`**: Flutter states it will make breaking changes even in patch versions, it throws `UnsupportedError` unless the `windowing` feature flag is on, and it has **no** always-on-top, title-bar-style, window-position or capture-exclusion API. | The app is **pinned to the exact Flutter commit** (T-0). All use of the API is confined to one adapter file (`lib/services/flutter_windowing_service.dart`, §9.3) with `// ignore_for_file: invalid_use_of_internal_member`. Missing capabilities live in the native plugin (§9.5, §6.3 `setupDisplayWindow`). The app cannot be published to pub.dev / used with stable Flutter (acceptable: not a package). |

---

## 4. Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│ UI LAYER (Dart / Flutter)                                                  │
│  DisplayControllerPage (HookWidget) + useDisplayControllerViewModel        │
│  DisplayWindowPage     (HookWidget) + useDisplayWindowViewModel            │
│  (state management: flutter_hooks, §9.0)                                   │
│  WindowService (abstraction over multi-window)   SettingsStore             │
└───────────────▲────────────────────────────────────────────────────────────┘
                │ depends ONLY on abstract DisplayCaptureApi
┌───────────────┴────────────────────────────────────────────────────────────┐
│ API LAYER (Dart package `display_capture_api`)                             │
│  abstract class DisplayCaptureApi  + models + errors                       │
│  MethodChannel/EventChannel implementation  (`PluginDisplayCaptureApi`)    │
└───────────────▲────────────────────────────────────────────────────────────┘
                │ identical wire protocol on every OS (§6.3)
┌───────────────┴────────────────────────────────────────────────────────────┐
│ PLATFORM LAYER (native, one per OS, Flutter plugin `display_capture`)      │
│  Windows: Rust core (D3D11 + Windows.Graphics.Capture) + thin C++ shim     │
│  macOS:   Swift Package (ScreenCaptureKit + Metal), Swift plugin class     │
│  Linux:   Rust core (Vulkan + PipeWire/portal) + thin C GObject shim       │
└────────────────────────────────────────────────────────────────────────────┘
```

Rules:
1. UI layer MUST NOT import anything under `platform/`. It imports `display_capture_api` only.
2. API layer contains no business logic; it is a typed, uniform facade. Native code MUST NOT contain UI logic.
3. All platform differences are hidden below the wire protocol; the Dart side has **zero** `Platform.isX` branches except in `WindowService` chrome configuration (§9) and the Wayland banner.

### 4.1 Repository layout

```
VirtualMonitor/
├─ SPEC.md
├─ .fvmrc                         # exact Flutter version (pin at bootstrap, §14 T-0)
├─ pubspec.yaml                   # app
├─ lib/
│  ├─ main.dart                   # entry; routes by window args (§9.1)
│  ├─ ui/
│  │  ├─ controller/  display_controller_page.dart, display_row.dart, display_controller_logic.dart, use_display_controller_view_model.dart, display_controller_state.dart
│  │  ├─ display_window/ display_window_page.dart, display_window_logic.dart, use_display_window_view_model.dart, display_window_state.dart, name_resolution_label.dart, window_chrome.dart
│  │  └─ theme.dart
│  ├─ services/  app_services.dart (InheritedWidget), window_service.dart, flutter_windowing_service.dart, settings_store.dart
│  └─ l10n/app_en.arb
├─ packages/
│  ├─ display_capture_api/        # API layer (pure Dart + channel impl)
│  │  └─ lib/ display_capture_api.dart, models.dart, errors.dart, plugin_api.dart
│  └─ display_capture/            # Flutter plugin (federated-style, per-OS dirs)
│     ├─ pubspec.yaml             # platforms: windows, macos, linux → pluginClass
│     ├─ windows/ CMakeLists.txt, display_capture_plugin.cpp/.h, include/dc_core.h
│     ├─ macos/   display_capture/Package.swift, Sources/DisplayCapture/*.swift
│     └─ linux/   CMakeLists.txt, display_capture_plugin.c/.h, include/dc_core.h
├─ native/                        # Rust workspace (Windows + Linux)
│  ├─ Cargo.toml
│  ├─ dc-common/   # types, C ABI, ring buffer, logging
│  ├─ dc-windows/  # cdylib: D3D11 + WGC
│  └─ dc-linux/    # cdylib: Vulkan + PipeWire + portal
└─ test/, integration_test/, native/**/tests
```

---

## 5. Domain model (identical in all layers)

### 5.1 `DisplayInfo`

| Field | Type | Meaning |
|-------|------|---------|
| `id` | `String` | **Stable** per-display id (see §5.2). Used as persistence key and as capture target. |
| `name` | `String` | Human-readable name. Never empty (fallback `"Display {n}"`, n = 1-based index in enumeration order). |
| `widthPx`, `heightPx` | `int` | Native pixel resolution (> 0). |
| `scaleFactor` | `double` | OS scale (1.0, 1.25, 2.0 …). |
| `refreshRateHz` | `double` | `0` if unknown. |
| `originX`, `originY` | `int` | Top-left in the OS virtual desktop in **physical pixels**. |
| `isPrimary` | `bool` | |
| `kind` | `enum { physical, virtual, unknown }` | D-6. |
| `captureStatus` | `enum { available, permissionDenied, unsupported, protected }` | D-9. |
| `captureStatusDetail` | `String?` | Human-readable reason when not `available`. |

Ordering: primary first, then ascending `originX`, then `originY`, then `id`.

### 5.2 Per-OS enumeration rules

**Windows (Rust, `dc-windows`)**
* Enumerate with `EnumDisplayMonitors` + `GetMonitorInfoW`(`MONITORINFOEXW`) for geometry; `EnumDisplaySettingsW(ENUM_CURRENT_SETTINGS)` for pixels/Hz; `GetDpiForMonitor(MDT_EFFECTIVE_DPI)/96` for scale.
* Name & kind: `QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS)` → match `DISPLAYCONFIG_PATH_INFO.sourceInfo.id` to the monitor's GDI device name via `DisplayConfigGetDeviceInfo(DISPLAYCONFIG_SOURCE_DEVICE_NAME)`; read `DISPLAYCONFIG_TARGET_DEVICE_NAME.monitorFriendlyDeviceName` (fallback `EnumDisplayDevicesW` DeviceString, fallback `"Display n"`). `kind = virtual` iff the display name contains "Virtual" (case-insensitive, D-6) **or** `outputTechnology ∈ {DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INDIRECT_WIRED (11), DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INDIRECT_VIRTUAL (12)}`; else `physical`; `unknown` when the path can't be matched.
* `id` = `"win:" + monitorDevicePath` (`DISPLAYCONFIG_TARGET_DEVICE_NAME.monitorDevicePath`) or, if unavailable, `"win:" + GDI device name`.
* Change notification: hidden message-only window handling `WM_DISPLAYCHANGE` and `WM_DEVICECHANGE`(`DBT_DEVNODES_CHANGED`); debounce 300 ms, then re-enumerate and emit `displaysChanged`.

**macOS (Swift)**
* `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` → `displays: [SCDisplay]` are the capturable set. Additionally `CGGetOnlineDisplayList` to find displays that are online but missing from SCK (list them with `captureStatus = unsupported`, detail "Not available to ScreenCaptureKit (mirrored or asleep)").
* Name: matching `NSScreen` via `deviceDescription["NSScreenNumber"] == CGDirectDisplayID` → `localizedName`; fallback `"Display n"`.
* Pixels: `CGDisplayModeGetPixelWidth/Height(CGDisplayCopyDisplayMode)`; scale = `NSScreen.backingScaleFactor`; Hz = `CGDisplayModeGetRefreshRate` (0 → unknown).
* `id` = `"mac:" + uuidString(CGDisplayCreateUUIDFromDisplayID)`.
* `kind`: `virtual` when the display name contains "Virtual" (case-insensitive, D-6), or when SCK reports the display but `CGDisplayVendorNumber` is `0`, or the model/vendor equals a known virtual-display vendor list kept in `VirtualDisplayVendors.swift` (initially empty, extendable); otherwise `physical`. Never throws.
* Permission: if `CGPreflightScreenCaptureAccess() == false` → every row `captureStatus = permissionDenied`, detail "Screen Recording permission required". Enumeration geometry still works via `NSScreen`/CG.
* Change notification: `NSApplication.didChangeScreenParametersNotification` and `CGDisplayRegisterReconfigurationCallback`; debounce 300 ms.

**Linux (C shim + Rust)**
* Enumeration in the C shim with **GDK** (`GdkDisplay`/`GdkMonitor`): geometry (`gdk_monitor_get_geometry` × `scale_factor`), name = `gdk_monitor_get_model` (fallback `gdk_monitor_get_manufacturer`+model; fallback `"Display n"`), refresh = `gdk_monitor_get_refresh_rate/1000`, primary = `gdk_monitor_is_primary` (Wayland: first monitor).
* `id`: X11 → `"x11:" + RandR output name` (e.g. `x11:DP-1`); Wayland → `"wl:" + connector name` from `xdg-output` name (GDK ≥ 3.24 provides connector via `gdk_monitor_get_model` only on some versions; the shim MUST read `zxdg_output_v1.name` via the Wayland registry when GDK doesn't yield it). If neither yields a name: `"gdk:" + index`.
* `kind = virtual` when the display name contains "Virtual" (case-insensitive, D-6), or when connector name starts with `Virtual-` (Mesa/QXL/virtio/vkms outputs), `VIRTUAL`, or `HEADLESS-`; else `physical`.
* Change notification: `GdkDisplay` `monitor-added`/`monitor-removed` and `GdkMonitor` `notify::geometry`; debounce 300 ms.
* `captureStatus`: `available` by default; `unsupported` + detail "No portal or X11 capture backend" if §8.3 probing fails at startup.

---

## 6. API Layer

### 6.1 Dart interface (`display_capture_api`)

```dart
abstract class DisplayCaptureApi {
  /// Current displays, ordered per §5.1. Never throws for "no displays" (returns []).
  Future<List<DisplayInfo>> listDisplays();

  /// Emits the full new list every time the set or properties of displays change (debounced natively).
  Stream<List<DisplayInfo>> get displaysChanged;

  /// Starts capturing [displayId]. Creates a Flutter external texture in the
  /// engine and returns a handle. Idempotent per displayId + ownerWindowHandle:
  /// a second call returns the same session.
  Future<CaptureSession> startCapture(String displayId, {CaptureOptions options = const CaptureOptions()});

  /// Stops and releases the session and its texture. Safe to call twice.
  Future<void> stopCapture(int sessionId);

  /// Events for one session (frame size changes, errors, display lost, stalled/resumed).
  Stream<CaptureEvent> captureEvents(int sessionId);

  /// Screen-recording permission state (macOS meaningful; others always granted).
  Future<PermissionState> permissionState();
  Future<void> requestPermission();           // macOS: CGRequestScreenCaptureAccess; others: no-op
  Future<void> openPermissionSettings();      // macOS: opens System Settings → Privacy → Screen Recording; others: no-op

  /// Registers a native window (by identifier) so it is excluded from capture (D-4). §9.4
  /// Configures a DisplayWindow's native window (§9.5): always-on-top, transparent title bar +
  /// standard close button, exclusion from screen capture (D-4), and initial position.
  /// [nativeHandle] is the window handle exposed by Flutter's WindowController
  /// (HWND / NSWindow* / GtkWindow* as an int address). Call once per window, before startCapture.
  Future<void> setupDisplayWindow({required int nativeHandle, required WindowFrame initialFrame});
  /// Emits when the user hovers/leaves the Windows-drawn close button (Windows only; never emits elsewhere).
  Stream<CloseHoverEvent> get closeHoverEvents;   // {nativeHandle, hot}

  Future<DiagnosticsInfo> diagnostics();      // renderPath, backend names, driver strings
}
```

```dart
class CaptureOptions { final int? maxWidthPx; final int? maxHeightPx; final int? fps; final bool showCursor; /* defaults: null,null,null(=D-10),true */ }
class CaptureSession { final int sessionId; final int textureId; final int widthPx; final int heightPx; }
enum PermissionState { granted, denied, notDetermined }
sealed class CaptureEvent {}
  class FrameSizeChanged extends CaptureEvent { int widthPx, heightPx; }
  class CaptureStalled extends CaptureEvent {}            // no frame for > 2000 ms while display on
  class CaptureResumed extends CaptureEvent {}
  class DisplayLost extends CaptureEvent {}               // session already torn down natively
  class CaptureFailed extends CaptureEvent { CaptureError error; }
class DiagnosticsInfo { String renderPath; /* "d3d11-shared" | "metal-iosurface" | "vulkan-gl-interop" | "cpu-fallback" */ String backend; String gpuName; String driver; }
```

### 6.2 Errors

`CaptureError { code, message }` with `code` one of:

| code | When |
|------|------|
| `DISPLAY_NOT_FOUND` | id not currently connected |
| `PERMISSION_DENIED` | macOS TCC denied; Linux portal denied/cancelled by user |
| `UNSUPPORTED` | OS/API/GPU requirement unmet (D-14) |
| `WRONG_SOURCE` | Linux: user picked a different monitor in the portal dialog than requested |
| `GPU_ERROR` | device lost / out of memory / interop failure and no fallback |
| `CAPTURE_FAILED` | backend error mid-session |
| `INTERNAL` | anything else |

Dart maps `PlatformException.code` 1:1 to `CaptureErrorCode`.

### 6.3 Wire protocol (identical for all OSes)

* MethodChannel `com.virtualmonitor/display_capture` (StandardMethodCodec).
* EventChannel `com.virtualmonitor/display_capture/displays` (stream of `List<Map>` display lists).
* EventChannel `com.virtualmonitor/display_capture/session/{sessionId}` (one per session; created on `startCapture`, cancelled on `stopCapture`).

| Method | Args (Map) | Result |
|--------|-----------|--------|
| `listDisplays` | – | `List<Map>` DisplayInfo (`id,name,widthPx,heightPx,scaleFactor,refreshRateHz,originX,originY,isPrimary,kind,captureStatus,captureStatusDetail`; enums as lowercase strings) |
| `startCapture` | `displayId, maxWidthPx?, maxHeightPx?, fps?, showCursor` | `{sessionId, textureId, widthPx, heightPx}` |
| `stopCapture` | `sessionId` | `null` |
| `permissionState` | – | `"granted"|"denied"|"notDetermined"` |
| `requestPermission`, `openPermissionSettings` | – | `null` |
| `setupDisplayWindow` | `nativeHandle` (int64 address of HWND / `NSWindow*` / `GtkWindow*`), `x,y,width,height` (physical px, virtual-desktop coords; ignored where the OS forbids placement, C-2) | `null` |

`startCapture` additionally takes `ownerWindowHandle` (int64, optional). If given, the native layer **stops every session owned by that window when the native window is destroyed** (safety net in addition to the explicit `stopCapture`). Hover events for the Windows close button travel on EventChannel `com.virtualmonitor/display_capture/chrome` as `{nativeHandle, hot}`.
| `diagnostics` | – | Map |

Session event Map: `{type: "frameSize"|"stalled"|"resumed"|"displayLost"|"failed", widthPx?, heightPx?, code?, message?}`.

Threading contract: method calls arrive on the platform (main) thread; native work runs on dedicated threads (§7). Replies are sent on the platform thread.

### 6.4 How the accelerated renderer connects to the API (decision)

**Chosen design: external GPU texture per capture session, owned by the window (`ownerWindowHandle`) that called `startCapture`.**

1. Dart calls `startCapture` → native creates the capture pipeline and registers an external texture with the engine's single `FlutterTextureRegistrar`, returns `textureId`.
2. UI renders it with Flutter's `Texture(textureId: id, filterQuality: FilterQuality.medium)` — no pixel data ever crosses Dart.
3. Native pipeline: *OS capture → GPU convert/scale into one of N=3 pooled textures → mark latest → `MarkTextureFrameAvailable`*. Flutter's raster thread pulls the latest texture via the platform-specific callback (§7). Texture pool slots in use by the raster thread are never overwritten (ref-counted/`in_use` flag); if all slots are busy the new frame is dropped (latest-wins).
4. Rejected alternatives: (a) streaming frames to Dart over FFI/channels (CPU copies, 8 MB/frame at 4K); (b) a native child window/overlay over Flutter (breaks z-order, transparency, resizing); (c) `dart:ffi` `Pointer` pixel buffers rendered via `CustomPainter` (not GPU-resident).

---

## 7. Platform Layer — common behaviour

### 7.1 Session lifecycle (all OSes)
`startCapture` → state `Starting` → first frame → `Running`. `stopCapture` / engine detach / owner window destroyed → `Stopping` → all GPU/OS resources released within 1 s → `Closed`. A session is bound to its `ownerWindowHandle`; **when that native window is destroyed (closed by user, `destroy()`, or crash of the Dart side), every session it owns MUST be stopped automatically**, and when the engine/plugin is destroyed all sessions are stopped.
Maximum concurrent sessions: unlimited by spec; each uses its own thread(s) and device context.

### 7.2 Frame pipeline contract
* Output pixel format: **BGRA8 (8-bit, premultiplied alpha ignored, alpha forced 1.0)**.
* Output size: source native pixels; if `maxWidthPx/maxHeightPx` are set, scaled to fit preserving aspect (bilinear on GPU).
* Latency target (capture → texture available): ≤ 1 frame interval. Pool size 3. No frame queue growth: **latest-wins**.
* On source resolution change: native rebuilds the pool/stream, emits `frameSize`, and the texture keeps the same `textureId`.
* Stall: no frame for > 2 s while the display is online → `stalled`; next frame → `resumed`. (A static desktop produces no WGC/SCK frames; stall detection therefore only emits `stalled` if the OS also reports no frame *and* a 2 s poll of the capture source — `GraphicsCaptureSession` alive / `SCStream` not stopped — shows it healthy, in which case **no event** is emitted. Implementers MUST NOT show a "stalled" UI for static content; the UI shows nothing for `stalled` other than a debug log. Reserved for future use.)

### 7.3 `captureStatus` detail strings (exact)
| status | detail |
|--------|--------|
| `permissionDenied` | `Screen Recording permission required` (macOS) / `Screen sharing was denied` (Linux, after a denied portal prompt in this run) |
| `unsupported` | `Capture is not supported for this display` or the specific strings in §5.2 |
| `protected` | `This display shows protected content and cannot be captured` (only if the OS reports it) |

---

## 8. Platform Layer — per OS

### 8.1 Windows — Rust (`dc-windows`) + C++ shim

**Crates**: `windows` (official `windows-rs`; features: `Graphics_Capture`, `Graphics_DirectX_Direct3D11`, `Win32_Graphics_Direct3D11`, `Win32_Graphics_Dxgi_Common`, `Win32_Graphics_Gdi`, `Win32_UI_WindowsAndMessaging`, `Win32_Devices_Display`, `Win32_UI_HiDpi`, `Win32_System_WinRT_Direct3D11`, `Win32_System_WinRT_Graphics_Capture`), `crossbeam-channel`, `log`.
Build: `cargo build --release -p dc-windows` produces `dc_windows.dll` + `dc_windows.dll.lib`; `windows/CMakeLists.txt` invokes cargo (via `add_custom_command`) and bundles the DLL (`PLUGIN_BUNDLED_LIBRARIES`).

**Capture**: Windows.Graphics.Capture (WGC). `IGraphicsCaptureItemInterop::CreateForMonitor(HMONITOR)` → `Direct3D11CaptureFramePool::CreateFreeThreaded(device, B8G8R8A8UIntNormalized, 3, size)` → `FrameArrived` callback. `GraphicsCaptureSession.IsCursorCaptureEnabled = showCursor`; `IsBorderRequired = false` (C-5, ignore failure). `HMONITOR` is resolved from `DisplayInfo.id` at start time by re-enumeration.

**Device**: The shim passes the `IDXGIAdapter*` obtained from `FlutterDesktopViewGetGraphicsAdapter(view)`; Rust creates its `ID3D11Device` on **that adapter** with `D3D11_CREATE_DEVICE_BGRA_SUPPORT`. (Different adapters would break sharing.)

**Convert/scale**: `ID3D11VideoProcessor` (or a fullscreen-triangle pixel shader when `max*` set) writes into 3 pooled `ID3D11Texture2D` (BGRA8, `D3D11_RESOURCE_MISC_SHARED`, `BIND_RENDER_TARGET | BIND_SHADER_RESOURCE`). After writing: `ID3D11DeviceContext::Flush()` and an event query waited (≤ 4 ms) so the consumer sees complete data. Shared handle = `IDXGIResource::GetSharedHandle` (legacy, no close needed).

**Flutter hand-off (C++ shim)**: `FlutterDesktopTextureRegistrarRegisterExternalTexture` with `FlutterDesktopTextureType::kFlutterDesktopGpuSurfaceTexture`, `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`; the obtain-callback returns a `FlutterDesktopGpuSurfaceDescriptor{handle, visible_width, visible_height, width, height, format = kFlutterDesktopPixelFormatBGRA8888, release_callback}` for the latest ready pool slot, marking it `in_use` until `release_callback`. Rust → shim notification via C callback `dc_on_frame(session_id)` which calls `MarkExternalTextureFrameAvailable`.

**Self-exclusion**: performed inside `setupDisplayWindow(hwnd)` → `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)`. The DisplayWindow MUST call `setupDisplayWindow` before the first `startCapture` (§9.4). If the call fails, log a warning and continue.

**Rust C ABI** (`include/dc_core.h`, same file shape for Linux):
```c
typedef struct dc_display { char id[128]; char name[256]; int32_t width_px, height_px; double scale, refresh_hz; int32_t origin_x, origin_y; int32_t is_primary; int32_t kind; int32_t capture_status; char status_detail[160]; } dc_display;
int32_t dc_list_displays(dc_display* out, int32_t cap, int32_t* count);           // returns 0 or negative error
int32_t dc_set_display_change_callback(void (*cb)(void* user), void* user);
int32_t dc_start_capture(const char* display_id, const dc_options* opt, void* adapter, void (*on_frame)(void*,int64_t), void (*on_event)(void*,int64_t,const dc_event*), void* user, int64_t* out_session);
int32_t dc_acquire_frame(int64_t session, dc_frame* out);   // latest ready slot; sets in_use
void    dc_release_frame(int64_t session, int32_t slot);
int32_t dc_stop_capture(int64_t session);
int32_t dc_exclude_window(int64_t native_window);
const char* dc_last_error(void);                              // thread-local, UTF-8
```
`dc_frame` carries `{shared_handle, width, height, slot}`.

### 8.2 macOS — Swift Package (`DisplayCapture`)

`Package.swift`: `platforms: [.macOS("14.0")]` (also set `MACOSX_DEPLOYMENT_TARGET = 14.0` in the Flutter macOS runner and podspec/Xcode project), product `.library(name: "display-capture", type: .static)`, target `DisplayCapture` (frameworks: ScreenCaptureKit, Metal, MetalKit, CoreVideo, CoreMedia, AppKit, FlutterMacOS). Metal shaders compiled as `.metal` resource (default library `Bundle.module`).

**Components**
* `DisplayEnumerator` — §5.2.
* `CaptureSession` — owns `SCStream`, `SCStreamOutput` (queue: dedicated serial `DispatchQueue(label:"dc.capture", qos:.userInteractive)`), `MetalFramePipeline`, `FlutterTexture` adapter.
* `MetalFramePipeline` — `MTLDevice` = `MTLCreateSystemDefaultDevice()`; `CVMetalTextureCache`; output pool of 3 `CVPixelBuffer` (`kCVPixelFormatType_32BGRA`, attributes `kCVPixelBufferMetalCompatibilityKey`, `kCVPixelBufferIOSurfacePropertiesKey: [:]`, `kCVPixelBufferCGImageCompatibilityKey`). Per frame: wrap input IOSurface as `MTLTexture` and output buffer as `MTLTexture`; run one **render pass** (fullscreen triangle, bilinear sampler) from input to output; commit; on `addCompletedHandler` publish the buffer as "latest" and call `textureRegistry.textureFrameAvailable(id)`.
* `FrameTexture: NSObject, FlutterTexture` — `copyPixelBuffer()` returns `Unmanaged.passRetained(latest)` (Flutter releases). Flutter's Impeller/Metal path samples the IOSurface-backed buffer without CPU copy.

**SCK configuration**: `SCContentFilter(display: scDisplay, excludingWindows: ourSCWindows)` where `ourSCWindows` = `SCShareableContent.windows` filtered to the `windowNumber`s of `NSWindow`s registered through `setupDisplayWindow` (refreshed on every new DisplayWindow; the filter of all running streams is updated live with `SCStream.updateContentFilter`). `SCStreamConfiguration`: `width/height` = display pixel size (or scaled per options), `pixelFormat = kCVPixelFormatType_32BGRA`, `showsCursor = showCursor`, `minimumFrameInterval = CMTime(1, fps)` (fps per D-10), `queueDepth = 4`, `colorSpaceName = CGColorSpace.sRGB`, `capturesAudio = false`. Only `.complete` frames (`SCStreamFrameInfo.status`) are processed; `.idle` ignored.

**Permission**: `permissionState` → `CGPreflightScreenCaptureAccess()`; `granted`/`denied` (macOS offers no `notDetermined` readout → return `notDetermined` only if the app has never called `requestPermission`, tracked in `UserDefaults("dc.permissionRequested")`). `requestPermission` → `CGRequestScreenCaptureAccess()`. `openPermissionSettings` → open `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`. `Info.plist`: `NSScreenCaptureUsageDescription` = "Display Controller mirrors the displays you select into windows." macOS note: after the user grants permission the app MUST be relaunched for SCK to work; the Display Controller banner says so.

**Errors**: `SCStreamDelegate.stream(_:didStopWithError:)` → `failed` event with `CAPTURE_FAILED` (or `PERMISSION_DENIED` for `SCStreamError.userDeclined`).

### 8.3 Linux — Rust (`dc-linux`) + C GObject shim

**Crates**: `ash` (Vulkan 1.1+), `pipewire`, `ashpd` (xdg-desktop-portal ScreenCast), `x11rb` (X11 fallback incl. `shm`, `randr`), `crossbeam-channel`, `libc`, `log`.
Build: `cargo build --release -p dc-linux` → `libdc_linux.so`, bundled by `linux/CMakeLists.txt`. The C shim implements `FlPluginRegistrar`, GDK enumeration (§5.2), channels, and the `FlTextureGL` subclass.

**Capture backends (chosen at startup, reported in `diagnostics().backend`)**
1. **`portal-pipewire`** (default, Wayland and X11): `org.freedesktop.portal.ScreenCast` via ashpd: `CreateSession` → `SelectSources(types=MONITOR, multiple=false, cursor_mode = showCursor ? Embedded : Hidden, persist_mode=2 (until revoked))` → `Start` → `OpenPipeWireRemote` → PipeWire stream on returned node. The `restore_token` is stored per `displayId` in `~/.config/<app>/portal_tokens.json` (0600) so the picker is skipped next time.
   Source matching (C-4): the portal's `Start` response gives each stream's `position` and `size` (logical px). The stream is accepted iff its rectangle equals the requested display's logical geometry (`origin / scale`, `size / scale`) ± 1 px. Otherwise stop session, emit `WRONG_SOURCE` ("You selected a different monitor than the one requested").
2. **`x11-shm`** (fallback when no portal ScreenCast or PipeWire is available **and** `XDG_SESSION_TYPE=x11`): per-display `XShmGetImage` on the root window with the display's RandR rectangle, at the target fps, into a persistently-mapped Vulkan staging buffer (CPU path into Vulkan, GPU path from there on). `exclude` impossible (C-3).
3. Neither available → every display `captureStatus = unsupported`.

**PipeWire negotiation**: offer formats `BGRx`, `BGRA` (SPA_VIDEO_FORMAT) with DMA-BUF modifiers (`SPA_PARAM_EnumFormat` with `SPA_FORMAT_VIDEO_modifier`) first, then SHM `BGRx/BGRA` without modifier. Buffer types: `SPA_DATA_DmaBuf` preferred, `SPA_DATA_MemFd` fallback. Frame rate: `max_framerate = fps`.

**Vulkan pipeline**
* Instance ext: `VK_KHR_external_memory_capabilities`, `VK_KHR_get_physical_device_properties2`. Device ext: `VK_KHR_external_memory`, `VK_KHR_external_memory_fd`, `VK_EXT_external_memory_dma_buf`, `VK_EXT_image_drm_format_modifier`, `VK_KHR_external_semaphore_fd`, `VK_KHR_timeline_semaphore` (or core 1.2), `VK_KHR_dedicated_allocation`.
* GPU selection: the **same GPU that Flutter's GL context renders on**. The shim reads the GL renderer's device UUID with `GL_EXT_memory_object` `glGetUnsignedBytevEXT(GL_DEVICE_UUID_EXT)` and Rust picks the `VkPhysicalDevice` whose `VkPhysicalDeviceIDProperties.deviceUUID` matches; if no match → `renderPath="cpu-fallback"`.
* Per frame: import incoming DMA-BUF as `VkImage` (`VkImageDrmFormatModifierExplicitCreateInfoEXT` + `VkImportMemoryFdInfoKHR`; fd is `dup`'d; sync via `DMA_BUF_IOCTL_EXPORT_SYNC_FILE` into a `VkSemaphore` import when kernel ≥ 5.20, else `vkQueueWaitIdle` bounded wait). SHM buffers are copied through a staging buffer into a `VkImage`. A **graphics pass** (vertex-less fullscreen triangle, bilinear sampler, SPIR-V compiled at build time by `glslc`, files in `dc-linux/shaders/`) renders into one of 3 **exportable** output images (`VK_IMAGE_TILING_OPTIMAL`, `B8G8R8A8_UNORM`, `VkExternalMemoryImageCreateInfo` with `OPAQUE_FD`, dedicated allocation).
* Each output slot exports its memory FD once at creation, plus a binary semaphore FD pair for Vulkan→GL sync.

**Flutter hand-off (C shim)**: a `FlTextureGL` subclass `DcTexture` whose `populate(width,height,error)` runs on Flutter's raster thread with the GL context current:
 1. First use of a slot: `glCreateMemoryObjectsEXT`, `glImportMemoryFdEXT(mem, size, GL_HANDLE_TYPE_OPAQUE_FD_EXT, fd)`, `glCreateTextures(GL_TEXTURE_2D)`, `glTextureStorageMem2DEXT(tex, 1, GL_RGBA8, w, h, mem, 0)` (BGRA vs RGBA swizzle: set texture swizzle R↔B via `GL_TEXTURE_SWIZZLE_R/B`).
 2. Every frame: `glWaitSemaphoreEXT` on the imported semaphore, then return `target=GL_TEXTURE_2D, name=tex, width, height` through `fl_texture_gl_populate`. A `release` path marks the slot reusable.
 3. If any GL extension is missing (`GL_EXT_memory_object`, `GL_EXT_memory_object_fd`, `GL_EXT_semaphore`, `GL_EXT_semaphore_fd`) → backend uses `FlPixelBufferTexture` with a mapped readback buffer and `renderPath="cpu-fallback"`.

**Self-exclusion**: none (C-3). **Always-on-top** etc.: §9.

---

## 9. UI Layer

### 9.0 State management: `flutter_hooks` (owner decision)

* State management uses **`flutter_hooks`** (pin exact version in `pubspec.yaml`). No `provider`, `riverpod`, `bloc`, or `get_it`. The only other state primitive allowed is Flutter's own `ValueNotifier`/`Stream`.
* Every screen/widget with state or lifecycle is a **`HookWidget`**. `StatefulWidget` is not used in the UI layer (exception: none planned).
* **Layering of view-model code** (keeps logic unit-testable without a widget tree):
  1. `*Logic` — plain Dart class, no Flutter widget imports; constructor-injected `DisplayCaptureApi`, `WindowService`, `SettingsStore`; owns a `ValueNotifier<XState>` where `XState` is an **immutable** class (`copyWith`, value equality); exposes action methods (`setEnabled`, `retry`, …) and `dispose()` which cancels all subscriptions.
  2. `use*ViewModel` — a **custom hook** (`Hook`-based function) that creates the logic with `useMemoized`, runs `init()` in `useEffect(() { logic.init(); return logic.dispose; }, [logic])`, and returns `({XState state, XActions actions})` by reading `useValueListenable(logic.state)`.
  3. Pages (`DisplayControllerPage`, `DisplayWindowPage`, `DisplayRow`) are `HookWidget`s that call the hook and render. Ephemeral UI state (hover, banner dismissal, SnackBar triggering) uses `useState`, `useEffect`, `useListenable`, `useStream` directly in the widget.
* **Dependency injection without a DI package**: `AppServices` (holds `DisplayCaptureApi`, `WindowService`, `SettingsStore`) is an `InheritedWidget` at the root of the app, **above `WindowManager`** so every window's view tree sees it (`AppServices.of(context)`); hooks read it via `useContext()`. Tests supply fakes through the same widget.
* Streams from the API (`displaysChanged`, `captureEvents`, window events) are subscribed **inside `*Logic.init()`** and mapped into state; widgets never subscribe to API streams directly.
* Side effects reaching the UI (SnackBar, dialog) are modelled as a one-shot `Stream<UiEffect>` on the logic and consumed with `useStream`/`useEffect` in the page.
* There is **one isolate**, so all windows share the same Dart objects: the `DisplayControllerLogic` and each `DisplayWindowLogic` live in the same heap, and no cross-window message passing exists. `DisplayControllerLogic` owns the list of `DisplayWindowLogic`s through `WindowService`.

### 9.0a Facts about the installed Flutter windowing API (verified against the SDK on this machine)

SDK: Flutter `3.49.0-1.0.pre-200`, channel `main`, framework revision `fab991537b` (2026-09-29), Dart 3.14.0-dev, at `C:\flutter`. File: `packages/flutter/lib/src/widgets/_window.dart` (+ `_window_win32.dart`, `_window_macos.dart`, `_window_linux.dart`).

| Fact | Consequence for this app |
|------|--------------------------|
| Enabled by `flutter config --enable-windowing` (or env `FLUTTER_WINDOWING`); runtime flag `isWindowingEnabled`; APIs throw `UnsupportedError` otherwise. | Dev/CI/build steps MUST enable it (T-0). |
| Imported as `package:flutter/src/widgets/_window.dart`; members are `@internal`. | Confined to one adapter file (C-7). |
| `WindowController({required Size size, BoxConstraints? constraints, String? title, WindowControllerDelegate? delegate})` creates a native top-level window; `WindowController.shrinkWrap(...)` exists but is **not used**. Members: `contentSize, title, isActivated, isMaximized, isMinimized, isFullscreen, setSize, setConstraints, setTitle, activate, setMaximized, setMinimized, setFullscreen, destroy(), isDestroyed, rootView`. | Display Controller and DisplayWindows are `WindowController`s. Min size 320×180 via `constraints`. |
| `WindowControllerDelegate` (mixin class) has `onWindowCloseRequested(WindowController)` (default: `destroy()`) and `onWindowDestroyed()`. | **R-5 is implemented here**: the delegate for every DisplayWindow reports closed → Controller toggle Off. Delegates are Dart callbacks in the same isolate. |
| `Window({controller, child})` renders `child` into that window's `View`; `WindowScope` exposes the controller to descendants. `WindowManager(initialWindows: [WindowEntry])` + `WindowRegistry` (register/unregister at runtime via `WindowRegistry.maybeOf(context)`) render windows at the app root. | Root = `runWidget(AppServices(child: WindowManager(initialWindows: [controllerEntry])))`; DisplayWindows are added/removed through the registry. |
| Each platform's concrete controller exposes the native handle: Win32 `windowHandle` (`HWND`, `Pointer<Void>`), macOS `windowHandle` (`Pointer<Void>`), Linux `windowHandle` (`GtkWindow*`). | Passed to the plugin as `nativeHandle` (`pointer.address`). T-1 verifies the macOS pointer is the `NSWindow*`. |
| **Not available**: always-on-top, title-bar style/transparency, window position on regular windows, capture exclusion. (Position exists only for popup/tooltip/satellite types.) | Done natively in the plugin via `setupDisplayWindow` (§9.5). |
| `WindowingOwnerWin32` has a private `_WindowsMessageHandler` hook for `WndProc` messages. | **Not used** (private). Windows message handling is done by the plugin with `SetWindowSubclass`. |
| Reference runner/CMake/MainMenu for each OS lives in `examples/multiple_windows`. | T-0 copies the runner files from that example into the app's `windows/ macos/ linux/` folders instead of the stable templates. |

### 9.1 Windows & process model
* One OS process, **one engine, N+1 views**: view 0 = Display Controller window, view k = DisplayWindow k. `main()` calls `runWidget(AppRoot())` where `AppRoot` = `AppServices` → `WindowManager(initialWindows: [WindowEntry(controllerWindowController, (_) => const DisplayControllerPage())])`. DisplayWindows are registered later via `WindowRegistry`.
* The `display_capture` plugin is registered once (single engine). Its `FlutterTextureRegistrar` serves **all** views: a `textureId` may be used by a `Texture` widget in any view (each DisplayWindow uses its own).
* Window lifecycle events come from `WindowControllerDelegate` callbacks (§9.0a), not from messages. The `WindowService` converts them into `WindowEvent`s: `opened {displayId}`, `closed {displayId}`, `failed {displayId, code, message}`.

### 9.2 Display Controller window

* Native window title `Display Controller`; default size 560×640, min 480×360, standard OS frame (opaque title bar). Single instance (a second launch focuses the first; implemented with a per-OS single-instance lock: Windows named mutex `Global\VirtualMonitor.DisplayController`, macOS `LSMultipleInstancesProhibited=YES`, Linux `GApplication` unique `com.virtualmonitor.DisplayController`).
* Layout (top→bottom):
  1. Header: title `Display Controller` (headlineSmall) + subtitle `"{n} displays"` / `"1 display"` / `"No displays"`.
  2. Optional banners (stacked, dismissible per session, `MaterialBanner`): permission (macOS, §8.2: text *"Screen Recording permission is required to show displays."*, buttons **Grant Access** → `requestPermission`, **Open Settings** → `openPermissionSettings`); Wayland always-on-top notice (C-2); single-display feedback notice on Linux (C-3: *"Only one display is connected. The window will show itself."*).
  3. `ListView` of `DisplayRow`s.
* **DisplayRow** (height 72, horizontal padding 16): leading icon (`Icons.monitor`; `Icons.cast` for virtual), title = `name` (bodyLarge, 1 line, ellipsis), subtitle = `"{w}×{h} · {hz:.0f} Hz"` (+ `" · Primary"`) (+ `" · Virtual"`) — `Hz` omitted if unknown; second subtitle line `captureStatusDetail` (error color) when not `available`. Trailing `Switch` (Material 3); `value` = enabled; **disabled** when `captureStatus != available` or while a start is in flight (shows 16 px `CircularProgressIndicator` replacing the thumb area in addition to being disabled).
* Empty state: centered icon + `"No displays found"`.
* Error state (enumeration threw): centered `"Couldn't read displays"` + message + **Retry** button.
* Accessibility: row `Semantics(label: "{name}, {w} by {h}", toggled: enabled)`; Switch focusable, Space toggles; full keyboard navigation.

**DisplayControllerViewModel** (§9.0 pattern: plain-Dart `DisplayControllerLogic` holding `ValueNotifier<DisplayControllerState>`; exposed to the page by the hook `useDisplayControllerViewModel()`; depends on `DisplayCaptureApi`, `WindowService`, `SettingsStore`)

State (immutable `DisplayControllerState`): `List<DisplayRowState> rows` where `DisplayRowState{DisplayInfo info; bool enabled; bool busy; String? error}`, `ViewStatus status{loading, ready, error}`, `PermissionState permission`.
Events/behaviour:
1. `init()`: `permissionState()`, `listDisplays()`, subscribe `displaysChanged`, load persisted enabled ids (D-1), for each persisted id still present and `available` → `setEnabled(id,true)`.
2. `setEnabled(id, true)`: if row busy → ignore; set `busy`; `windowService.open(DisplayWindowSpec)`; on success `enabled=true`, persist; on failure `enabled=false`, `error` shown as SnackBar `"Couldn't open window for {name}: {message}"`.
3. `setEnabled(id, false)`: `windowService.close(id)`; `enabled=false`; persist.
4. `onWindowClosed(id)` (from `WindowEvent.closed`, §9.1): `enabled=false`, persist, `busy=false` (**R-5**). Must be triggered when the window is closed by any means (title-bar close, Alt+F4, Cmd+W, `destroy()`).
5. `onDisplaysChanged(list)`: diff by `id`: removed → close its window (if any), delete persisted state, drop row; added → append Off; changed (res/name) → update row, and if enabled, nothing else (the window receives `FrameSizeChanged`).
6. `onWindowFailed(id, err)`: `enabled=false`, persist, SnackBar.
7. `dispose`/Controller close (D-8): `windowService.closeAll()` then exit.

### 9.3 `WindowService` abstraction

```dart
abstract class WindowService {
  Future<void> open(DisplayWindowSpec spec);          // creates DisplayWindow, resolves when its logic emits `ready` (or throws on `failed`)
  Future<void> close(String displayId);
  Future<void> closeAll();
  bool isOpen(String displayId);
  Stream<WindowEvent> get events;                      // closed / failed / ready
}
class DisplayWindowSpec { String displayId, displayName; int widthPx, heightPx; WindowFrame initialFrame; /* D-3 */ }
class WindowFrame { int x, y, width, height; /* physical px, virtual-desktop coordinates */ }
```
Implementation `FlutterWindowingService` (file `lib/services/flutter_windowing_service.dart`, the only file importing `_window.dart`). `open(spec)`:
1. Create `WindowController(size: spec.initialFrame.size, constraints: BoxConstraints(minWidth: 320, minHeight: 180), title: spec.displayName, delegate: _Delegate(displayId))` where `_Delegate.onWindowCloseRequested` calls `controller.destroy()` (default behaviour) and `onWindowDestroyed` emits `WindowEvent.closed(displayId)`.
2. Register `WindowEntry(controller, (_) => DisplayWindowPage(spec: spec, nativeHandle: controller.windowHandle.address))` in the `WindowRegistry`.
3. Resolve once `DisplayWindowLogic` reports `ready` (i.e. `setupDisplayWindow` and `startCapture` have finished, or failed → `failed`).

`close(id)` → `controller.destroy()` (idempotent) and unregister the entry. `closeAll()` does so for all windows.

Capabilities used from the Flutter API: create window with size/constraints/title, `destroy()`, close-requested/destroyed delegate, `windowHandle`. Capabilities **not** in the API and supplied by the plugin through `setupDisplayWindow` (§9.5): always-on-top, transparent title bar + close button, window position, capture exclusion.

Initial frame computation (D-3): target monitor = first display ≠ source (by §5.1 order) else source; `workArea` from that monitor in **logical** px; `maxW = workArea.w*0.5`, `maxH = workArea.h*0.5`; scale = `min(maxW/ w_src_logical, maxH/h_src_logical, 1.0)`; size = `src_logical * scale` (floor, min 320×180); position = centred in `workArea` of the target, then cascaded by `+32,+32` per already-open DisplayWindow on that target (wrap to 0 after 8). Because `WindowController` has no position parameter, the **size** goes to the `WindowController` constructor and the **position** is applied by the plugin in `setupDisplayWindow` (`WindowFrame` carries both; physical px).

### 9.4 DisplayWindow

Visual structure (`Stack`, background `Colors.black`):
1. `Texture(textureId, filterQuality: FilterQuality.medium)` wrapped in `FittedBox(fit: BoxFit.contain)` sized to the session's `widthPx×heightPx` (so aspect-correct, letterboxed).
2. **Title strip** (top, height 32 logical px, full width): a transparent region reserved for the native title bar behaviour (drag, double-click maximize, per OS native handling, §9.5). Dart draws **no** gesture handling there; the video is visible beneath it.
3. Platform close affordance (§9.5).
4. **Name/resolution label** (R-6): `Positioned(right: 12, bottom: 12)`, wrapped in `IgnorePointer`; content `Text("{name} · {w}×{h}")` — `labelMedium`, white, `letterSpacing 0.2`, max one line, ellipsis (max width = 60 % of window width); decoration: `Color(0x99000000)` background, `BorderRadius.circular(6)`, padding `EdgeInsets.symmetric(horizontal: 8, vertical: 4)`; `Semantics(label:"Display {name}, {w} by {h}")`. Values update on `FrameSizeChanged`; name from `DisplayWindowSpec` (the Controller calls `DisplayWindowLogic.updateName(name)` directly, same isolate, when `displaysChanged` reports a new name).
5. State overlays (centered, over black): `Starting` → spinner; `Failed` → icon + message + **Retry** (calls `startCapture` again) and for `PERMISSION_DENIED` on macOS a **Open Settings** button.

**DisplayWindowViewModel** (§9.0 pattern: `DisplayWindowLogic` + hook `useDisplayWindowViewModel(spec)`): states `starting → running → failed/closed`.
* On init: `api.setupDisplayWindow(nativeHandle, initialFrame)` (await; also provides capture exclusion), then `api.startCapture(displayId, ownerWindowHandle: nativeHandle)`; emit `ready`. On any error emit `failed` **and** show the Failed overlay. The window stays open showing the error until the user closes it (or presses Retry); the Controller toggle is Off meanwhile (Controller rule 6). Toggling On again for that display closes the failed window and opens a fresh one.
* Subscribes `captureEvents`; `FrameSizeChanged` → rebuild; `DisplayLost` → emit `closed` and destroy the window.
* On window close (native `onClose` hook, or `dispose`): `api.stopCapture`, then emit `closed {displayId}` — the event MUST be emitted even if `stopCapture` throws (try/finally). The `WindowControllerDelegate.onWindowDestroyed` path emits `closed` independently, so the toggle goes Off even if the page was already torn down; the Controller ignores duplicates.

### 9.5 Title bar & close button (R-4), per OS

Requirement: title bar visually **transparent** (video visible through/under it), still a real **window with the platform's standard close button**, always on top.

Because Flutter's windowing API creates and owns the native window (§9.0a), **all of the following is applied by the plugin to an already-created native window** from `setupDisplayWindow(nativeHandle, frame)`, not by editing runner code. Each close path must end in Flutter's own close handling so `WindowControllerDelegate.onWindowCloseRequested` runs: Windows via `WM_CLOSE`/`SC_CLOSE`, macOS via the standard close button (`windowShouldClose`), Linux via `gtk_window_close` (which emits `delete-event`).

| OS | Implementation |
|----|----------------|
| **macOS** | `NSWindow`: `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `styleMask |= .fullSizeContentView`, keep `.titled .closable .resizable .miniaturizable`; **standard traffic-light close button** retained; hide minimize/zoom buttons? **No — leave all three standard buttons** (brief says "normal window close button"; hiding others is not requested). `level = .floating`; `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`; `isMovableByWindowBackground = false` (title strip drags natively because it is the title bar region). Applied on the main thread to the `NSWindow*` from `nativeHandle` (T-1 verifies the pointer type); position via `setFrameOrigin`. |
| **Windows** | Keep `WS_OVERLAPPEDWINDOW` frame. The plugin installs a **window subclass** on the `HWND` (`SetWindowSubclass`, removed on `WM_NCDESTROY`, which also stops sessions owned by that window) and in its subclass proc: handle `WM_NCCALCSIZE` (when `wParam==TRUE`) by returning `0` after reducing only left/right/bottom by the frame thickness (client area then extends under the caption; top border 1 px stays for resize); handle `WM_NCHITTEST`: result of `DefWindowProc` → if point is in the top 32 px strip → `HTCAPTION`, **except** inside the close-button rectangle (top-right 46×32 logical px scaled by DPI) → return `HTCLOSE`. Flutter draws a **close button visual** in that 46×32 rect: `Icons.close` glyph 10 px (Segoe Fluent), transparent normally, `#C42B1C` background + white glyph on hover (hover tracked from `WM_NCMOUSEMOVE`/`WM_NCMOUSELEAVE` in the subclass and sent to Dart on the `…/chrome` EventChannel as `{nativeHandle, hot}`; `DisplayWindowPage` filters by its own `nativeHandle`), pressed `#B22A1A`; a click is handled natively (`HTCLOSE` → `WM_SYSCOMMAND SC_CLOSE`), so Alt+F4/snap layouts/accessibility all behave natively. Always-on-top: `SetWindowPos(HWND_TOPMOST, …, SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE)`; re-applied on `WM_ACTIVATEAPP` and `WM_DISPLAYCHANGE`. |
| **Linux** | Plugin, given the `GtkWindow*` from `nativeHandle`, on the GTK main thread: `gtk_window_set_decorated(FALSE)`, RGBA visual (`gtk_widget_set_visual`), `gtk_widget_set_app_paintable(TRUE)`; the window's current child (the `FlView`) is re-parented into a new `GtkOverlay` (`g_object_ref`, `gtk_container_remove`, `gtk_overlay_add`/`gtk_container_add`) whose overlay children are the close button and the drag strip below. **If the window already has a `GtkHeaderBar` titlebar or re-parenting fails, the plugin leaves the native decorated title bar untouched (opaque, standard close button), sets `diagnostics.chromeMode = "native-fallback"` and logs a warning** — R-4 "transparent" is then not met on that system (reported, not silent). Close button: `GtkButton` with image `window-close-symbolic`, CSS classes `titlebutton close` (so the **active GTK theme draws the normal close button**), aligned top-right, 8 px margin; click → `gtk_window_close`. Drag: a 32 px-high transparent `GtkEventBox` overlay across the top (excluding the close button) → `gtk_window_begin_move_drag` on button-press. Resize: `gtk_window_set_resizable(TRUE)` + invisible 6 px resize grips via `gtk_window_begin_resize_drag` from edge `GtkEventBox`es. Position: `gtk_window_move` (X11 only, C-2). Always-on-top: `gtk_window_set_keep_above(TRUE)` (C-2). a `GtkButton` with image `window-close-symbolic`, CSS classes `titlebutton close` (so the **active GTK theme draws the normal close button**), aligned top-right, 8 px margin; click → `gtk_window_close`. Dragging: Flutter title strip calls channel `dc/window/startDrag` → `gtk_window_begin_move_drag`. Resize: `gtk_window_set_resizable(TRUE)` + invisible 6 px resize grips via `gtk_window_begin_resize_drag` from edge `GtkEventBox`es. Always-on-top: `gtk_window_set_keep_above(TRUE)` (C-2). |

The Dart `window_chrome.dart` renders nothing for the close button on macOS and Linux (native widget) and renders the visual only on Windows. Dragging is native on every OS (no Dart gesture).

### 9.6 Theming & sizes (summary)
Material 3, seed colour `0xFF3F6AE0`. Controller uses default scaffold. DisplayWindow ignores theme except label styles above.

### 9.7 Persistence (`SettingsStore`)
`shared_preferences`, key `enabledDisplayIds` (`List<String>`), key `schemaVersion=1`. Written on every toggle change/removal (D-1, D-7). Window frames are **not** persisted.

---

## 10. Concurrency & performance requirements

| Aspect | Requirement |
|--------|-------------|
| Threads | Dart UI thread never blocks on native work > 16 ms. Each session: 1 capture thread (+ 1 render thread on Linux). Enumeration on a worker thread. |
| CPU | ≤ 5 % of one core per 4K@60 session on reference hardware (Win/mac with iGPU or better); Linux zero-copy path same; cpu-fallback exempt. |
| Memory | ≤ 4 pool textures/session + ≤ 50 MB additional Dart heap per DisplayWindow view. |
| Startup | Display Controller visible and list populated ≤ 1.5 s after process start (cold). DisplayWindow first frame ≤ 1 s after open. |
| Teardown | Close → all native resources freed ≤ 1 s; no leaked textures (verified by §12 tests). |
| Frame pacing | Frame drops allowed (latest-wins); no accumulating latency > 2 frames. |

---

## 11. Logging, diagnostics, errors
* Dart: `package:logging`, levels `INFO` default; file `~/…/display_controller.log` (per-OS app-data dir), rotate at 5 MB × 3.
* Native: Windows/Linux `log` crate → same file via callback `dc_set_log_callback(void(*)(int level,const char*))`; macOS `os.Logger(subsystem:"com.virtualmonitor", category:"capture")`.
* `diagnostics()` result is shown in a hidden **About** dialog (Controller: `Ctrl/Cmd+Shift+D`).
* No telemetry. No network access.

---

## 12. Test plan

**Unit (Dart)**: `DisplayControllerLogic` (tested directly, no widgets) with fake `DisplayCaptureApi`/`WindowService`: default Off (R-2); persistence restore (D-1); toggle on opens window; `onWindowClosed` turns Off (R-5); hot-plug add/remove (D-7); non-capturable disabled (D-9); open failure resets toggle. `DisplayWindowLogic`: start/stop/ failure / try-finally close message; label text formatting (`"{name} · 3840×2160"`).

**Hook/Widget (Dart)**: `use*ViewModel` hooks tested with `HookBuilder` in `testWidgets` (init/dispose lifecycle: subscriptions cancelled on unmount); row rendering (all subtitle permutations), label position bottom-right and `IgnorePointer`, empty/error states, banners, semantics.

**Contract tests**: one shared Dart test suite run against each OS's real plugin (integration) and a recorded fake: method names, argument/return maps, error codes (§6).

**Native**
* Windows (Rust): enumeration parsing with mocked `QueryDisplayConfig` data; pool slot state machine (in_use/latest-wins) property tests; WGC capture smoke test on CI runner with virtual display driver (skipped if none).
* macOS (XCTest): enumerator mapping; pool/ordering; Metal pass output equality against CPU reference for a gradient (tolerance ±1/255).
* Linux (Rust): portal stream-matching function (position/size ±1 px); modifier negotiation selection; Vulkan pass golden-image test with lavapipe (software Vulkan) in CI.

**Integration (per OS, `integration_test` + scripted display)**: launch → enable display → DisplayWindow exists, is topmost, shows label; close window → toggle Off; disable toggle → window closes; relaunch → restored per D-1; unplug (virtual display removal) → window closes.

**Manual acceptance checklist** (must all pass on each OS, §13).

---

## 13. Acceptance criteria

1. First launch: Display Controller lists every display (incl. a virtual one) with all toggles **Off**; no DisplayWindow exists. (R-1, R-2, D-1)
2. Toggle On → within 1 s a DisplayWindow opens with live video of that display; per-display independent windows for multiple displays. (R-3)
3. DisplayWindow is above all normal windows (Win/mac/X11 verified; Wayland best-effort per C-2), has a transparent title bar with the platform-standard close button. (R-4)
4. Clicking close (or Alt+F4 / Cmd+W) closes the window and the toggle returns to Off. (R-5)
5. Bottom-right label shows `Name · W×H` in native pixels; updates on resolution change. (R-6)
6. Quit/relaunch restores On displays (D-1). Display hot-unplug closes its window; list updates live.
7. `diagnostics().renderPath` is `d3d11-shared` (Win), `metal-iosurface` (mac), `vulkan-gl-interop` (Linux; `cpu-fallback` only on drivers lacking §8.3 extensions).
8. Architecture rules (§4): UI imports only `display_capture_api`; no `Platform.isX` outside §9.5 chrome and banners (lint-enforced via `import_lint`/`custom_lint` rule).
9. No resource leaks after 100 open/close cycles (GPU memory and handle count within ±5 % of baseline).

---

## 14. Delivery order (tasks)

| # | Task | Done when |
|---|------|-----------|
| T-0 | Bootstrap: pin Flutter to the **`main` checkout `fab991537b` (3.49.0-1.0.pre-200)** (record the commit in `.fvmrc`/README); run `flutter config --enable-windowing`; copy runner files from `examples/multiple_windows` for each OS; verify these exact APIs exist in that checkout: Windows `FlutterDesktopGpuSurfaceTexture` + `FlutterDesktopViewGetGraphicsAdapter`, macOS `FlutterTexture` + SwiftPM plugin support, Linux `FlTextureGL`. Any API that is missing blocks the corresponding platform and MUST be reported, not worked around silently. | Hello-texture sample renders a solid GPU texture in a second `WindowController` window on all 3 OSes |
| T-1 | `FlutterWindowingService` over `WindowController`/`WindowRegistry`; verify `windowHandle` of each OS (macOS pointer is `NSWindow*`; Linux is `GtkWindow*`; Win32 is `HWND`); verify the close-requested/destroyed delegate fires for title-bar close, Alt+F4, Cmd+W and `destroy()`; implement plugin `setupDisplayWindow` stubs. | Open/close/notify-closed works with the fake capture on all OSes |
| T-2 | API layer package + fake implementation + contract tests | §12 contract suite green on fake |
| T-3 | Display Controller UI + VM with fake API | Widget/unit tests green |
| T-4 | macOS platform layer (enumeration → SCK capture → Metal → texture) | Acceptance 1–7 on macOS |
| T-5 | Windows platform layer (enumeration → WGC → D3D11 → texture) | Acceptance 1–7 on Windows |
| T-6 | Linux platform layer (GDK enumeration → portal/PipeWire → Vulkan → GL interop → texture; X11 fallback; cpu-fallback) | Acceptance 1–7 on Linux (GNOME-Wayland, KDE-Wayland, X11) |
| T-7 | Title-bar chrome per §9.5 on all OSes | Acceptance 3–4 |
| T-8 | Persistence, hot-plug, banners, logging, diagnostics | Acceptance 6 |
| T-9 | Perf/leak tests, CI for all OSes | Acceptance 8–9 and §10 |

---

## 15. Explicitly out of scope (v1)
Audio capture; remote/network streaming; input forwarding to mirrored displays; recording to a file; per-window crop/zoom; window-level capture (only whole displays); multiple Controllers; localisation beyond English; installers/notarization/signing (D-15); mobile/web platforms.
