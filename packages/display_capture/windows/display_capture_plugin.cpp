#include "display_capture_plugin.h"

#include <dxgi.h>
#include <windows.h>

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <string>

#include "window_chrome.h"

namespace display_capture {
namespace {

constexpr char kMethodChannel[] = "com.virtualmonitor/display_capture";
constexpr char kDisplaysChannel[] = "com.virtualmonitor/display_capture/displays";
constexpr char kChromeChannel[] = "com.virtualmonitor/display_capture/chrome";
constexpr UINT kRunQueueMessage = WM_APP + 0x44;
constexpr wchar_t kDispatcherClass[] = L"DisplayCaptureDispatcher";

using flutter::EncodableMap;

const char* ErrorCodeName(int32_t rc) {
  switch (rc) {
    case DC_ERR_DISPLAY_NOT_FOUND: return "DISPLAY_NOT_FOUND";
    case DC_ERR_PERMISSION_DENIED: return "PERMISSION_DENIED";
    case DC_ERR_UNSUPPORTED: return "UNSUPPORTED";
    case DC_ERR_GPU: return "GPU_ERROR";
    case DC_ERR_CAPTURE_FAILED: return "CAPTURE_FAILED";
    default: return "INTERNAL";
  }
}

EncodableValue S(const std::string& s) { return EncodableValue(s); }

int64_t GetInt(const EncodableMap& m, const char* key, int64_t fallback) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return fallback;
  if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
  if (const auto* v = std::get_if<int64_t>(&it->second)) return *v;
  return fallback;
}

bool GetBool(const EncodableMap& m, const char* key, bool fallback) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return fallback;
  if (const auto* v = std::get_if<bool>(&it->second)) return *v;
  return fallback;
}

std::string GetString(const EncodableMap& m, const char* key) {
  auto it = m.find(EncodableValue(key));
  if (it == m.end()) return {};
  if (const auto* v = std::get_if<std::string>(&it->second)) return *v;
  return {};
}

const char* KindName(int32_t k) {
  switch (k) {
    case DC_KIND_PHYSICAL: return "physical";
    case DC_KIND_VIRTUAL: return "virtual";
    case DC_KIND_BUILTIN: return "builtIn";
    default: return "unknown";
  }
}

const char* StatusName(int32_t s) {
  switch (s) {
    case DC_STATUS_PERMISSION_DENIED: return "permissionDenied";
    case DC_STATUS_UNSUPPORTED: return "unsupported";
    case DC_STATUS_PROTECTED: return "protected";
    default: return "available";
  }
}

EncodableValue DisplayToValue(const dc_display& d) {
  EncodableMap m;
  m[S("id")] = S(d.id);
  m[S("name")] = S(d.name);
  m[S("widthPx")] = EncodableValue(static_cast<int32_t>(d.width_px));
  m[S("heightPx")] = EncodableValue(static_cast<int32_t>(d.height_px));
  m[S("scaleFactor")] = EncodableValue(d.scale);
  m[S("refreshRateHz")] = EncodableValue(d.refresh_hz);
  m[S("originX")] = EncodableValue(static_cast<int32_t>(d.origin_x));
  m[S("originY")] = EncodableValue(static_cast<int32_t>(d.origin_y));
  m[S("workX")] = EncodableValue(static_cast<int32_t>(d.work_x));
  m[S("workY")] = EncodableValue(static_cast<int32_t>(d.work_y));
  m[S("workWidth")] = EncodableValue(static_cast<int32_t>(d.work_w));
  m[S("workHeight")] = EncodableValue(static_cast<int32_t>(d.work_h));
  m[S("isPrimary")] = EncodableValue(d.is_primary != 0);
  m[S("kind")] = S(KindName(d.kind));
  m[S("captureStatus")] = S(StatusName(d.capture_status));
  if (d.status_detail[0] != '\0') {
    m[S("captureStatusDetail")] = S(d.status_detail);
  }
  return EncodableValue(std::move(m));
}

}  // namespace

// static
void DisplayCapturePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<DisplayCapturePlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

DisplayCapturePlugin::DisplayCapturePlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  // Hidden window that lets other threads run code on the platform thread.
  WNDCLASSW wc = {};
  wc.lpfnWndProc = &DisplayCapturePlugin::DispatcherProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kDispatcherClass;
  RegisterClassW(&wc);
  dispatcher_ = CreateWindowExW(0, kDispatcherClass, L"", 0, 0, 0, 0, 0,
                                HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
  SetWindowLongPtr(dispatcher_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  method_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), kMethodChannel,
      &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  displays_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), kDisplaysChannel,
      &flutter::StandardMethodCodec::GetInstance());
  displays_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*, std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            displays_sink_ = std::move(sink);
            return nullptr;
          },
          [this](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            displays_sink_.reset();
            return nullptr;
          }));

  chrome_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), kChromeChannel,
      &flutter::StandardMethodCodec::GetInstance());
  chrome_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*, std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            chrome_sink_ = std::move(sink);
            return nullptr;
          },
          [this](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            chrome_sink_.reset();
            return nullptr;
          }));

  dc_set_display_change_callback(&DisplayCapturePlugin::OnDisplayChange, this);
}

DisplayCapturePlugin::~DisplayCapturePlugin() {
  shutting_down_ = true;
  dc_set_display_change_callback(nullptr, nullptr);
  std::vector<int64_t> ids;
  for (auto& kv : sessions_) ids.push_back(kv.first);
  for (int64_t id : ids) StopCapture(id);
  if (dispatcher_) DestroyWindow(dispatcher_);
  dc_shutdown();
}

LRESULT CALLBACK DisplayCapturePlugin::DispatcherProc(HWND hwnd, UINT msg,
                                                      WPARAM wparam, LPARAM lparam) {
  if (msg == kRunQueueMessage) {
    auto* self = reinterpret_cast<DisplayCapturePlugin*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (self) self->DrainPlatformQueue();
    return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

void DisplayCapturePlugin::PostToPlatformThread(std::function<void()> fn) {
  if (shutting_down_ || !dispatcher_) return;
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    queue_.push_back(std::move(fn));
  }
  PostMessage(dispatcher_, kRunQueueMessage, 0, 0);
}

void DisplayCapturePlugin::DrainPlatformQueue() {
  for (;;) {
    std::function<void()> fn;
    {
      std::lock_guard<std::mutex> lock(queue_mutex_);
      if (queue_.empty()) return;
      fn = std::move(queue_.front());
      queue_.pop_front();
    }
    fn();
  }
}

void DisplayCapturePlugin::EnsureCoreInitialized() {
  if (core_ready_) return;
  IDXGIAdapter* adapter = nullptr;
  // The shared textures must live on the adapter Flutter renders with.
  if (!registrar_->GetGraphicsAdapter(&adapter)) adapter = nullptr;
  if (!adapter) {
    OutputDebugStringA(
        "display_capture: Flutter's graphics adapter is unavailable; using the default adapter\n");
  }
  core_ready_ = dc_init(adapter) == DC_OK;
  if (adapter) adapter->Release();
}

EncodableValue DisplayCapturePlugin::DisplaysAsValue() {
  int32_t count = 0;
  dc_list_displays(nullptr, 0, &count);
  std::vector<dc_display> list(static_cast<size_t>(std::max(count, 0)));
  if (count > 0) dc_list_displays(list.data(), count, &count);
  flutter::EncodableList out;
  for (int32_t i = 0; i < count && i < static_cast<int32_t>(list.size()); ++i) {
    out.push_back(DisplayToValue(list[i]));
  }
  return EncodableValue(std::move(out));
}

void DisplayCapturePlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& name = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  static const EncodableMap kNoArgs;
  const EncodableMap& a = args ? *args : kNoArgs;

  if (name == "listDisplays") {
    ListDisplays(result.get());
  } else if (name == "startCapture") {
    StartCapture(a, result.get());
  } else if (name == "stopCapture") {
    StopCapture(GetInt(a, "sessionId", 0));
    result->Success();
  } else if (name == "prepareShutdown") {
    const auto controller = reinterpret_cast<HWND>(GetInt(a, "nativeHandle", 0));
    if (!IsWindow(controller)) {
      result->Error("INTERNAL", "nativeHandle is not a valid HWND");
      return;
    }
    ShowWindow(controller, SW_HIDE);
    std::vector<int64_t> ids;
    for (const auto& kv : sessions_) {
      const auto owner = reinterpret_cast<HWND>(kv.second->owner_window);
      if (IsWindow(owner)) ShowWindow(owner, SW_HIDE);
      ids.push_back(kv.first);
    }
    for (int64_t id : ids) StopCapture(id);
    result->Success();
  } else if (name == "permissionState") {
    result->Success(EncodableValue(std::string("granted")));
  } else if (name == "requestPermission" || name == "openPermissionSettings") {
    result->Success();  // no-ops on Windows
  } else if (name == "setupDisplayWindow") {
    SetupDisplayWindow(a, result.get());
  } else if (name == "diagnostics") {
    Diagnostics(result.get());
  } else {
    result->NotImplemented();
  }
}

void DisplayCapturePlugin::ListDisplays(flutter::MethodResult<EncodableValue>* result) {
  result->Success(DisplaysAsValue());
}

void DisplayCapturePlugin::StartCapture(const EncodableMap& args,
                                        flutter::MethodResult<EncodableValue>* result) {
  const std::string display_id = GetString(args, "displayId");
  if (display_id.empty()) {
    result->Error("INTERNAL", "displayId is required");
    return;
  }
  EnsureCoreInitialized();

  auto rec = std::make_shared<SessionRecord>();
  rec->plugin = this;
  rec->owner_window = GetInt(args, "ownerWindowHandle", 0);
  SessionRecord* raw = rec.get();
  rec->texture = std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
      kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
      [this, raw](size_t, size_t) { return ObtainDescriptor(raw); }));
  auto* textures = registrar_->texture_registrar();
  rec->texture_id = textures->RegisterTexture(rec->texture.get());

  dc_options opts = {};
  opts.max_width = static_cast<int32_t>(GetInt(args, "maxWidthPx", 0));
  opts.max_height = static_cast<int32_t>(GetInt(args, "maxHeightPx", 0));
  opts.fps = static_cast<int32_t>(GetInt(args, "fps", 0));
  opts.show_cursor = GetBool(args, "showCursor", true) ? 1 : 0;
  opts.owner_window = rec->owner_window;

  dc_start_result start = {};
  const int32_t rc = dc_start_capture(display_id.c_str(), &opts,
                                      &DisplayCapturePlugin::OnFrame,
                                      &DisplayCapturePlugin::OnEvent, raw, &start);
  if (rc != DC_OK) {
    const char* msg = dc_last_error();
    textures->UnregisterTexture(rec->texture_id, [rec]() {});
    result->Error(ErrorCodeName(rc), msg ? msg : "Capture failed");
    return;
  }
  rec->session_id = start.session;

  rec->channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar_->messenger(),
      std::string("com.virtualmonitor/display_capture/session/") + std::to_string(start.session),
      &flutter::StandardMethodCodec::GetInstance());
  rec->channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [raw](const EncodableValue*, std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            raw->sink = std::move(sink);
            for (auto& e : raw->pending) raw->sink->Success(e);
            raw->pending.clear();
            return nullptr;
          },
          [raw](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            raw->sink.reset();
            return nullptr;
          }));
  sessions_[start.session] = rec;

  EncodableMap reply;
  reply[S("sessionId")] = EncodableValue(static_cast<int64_t>(start.session));
  reply[S("textureId")] = EncodableValue(static_cast<int64_t>(rec->texture_id));
  reply[S("widthPx")] = EncodableValue(static_cast<int32_t>(start.width));
  reply[S("heightPx")] = EncodableValue(static_cast<int32_t>(start.height));
  result->Success(EncodableValue(std::move(reply)));
}

void DisplayCapturePlugin::StopCapture(int64_t session_id) {
  auto it = sessions_.find(session_id);
  if (it == sessions_.end()) return;  // safe to call twice
  std::shared_ptr<SessionRecord> rec = it->second;
  sessions_.erase(it);

  // Stops capture and waits for in-flight frame callbacks (Rust side) ...
  dc_stop_capture(session_id);
  if (rec->channel) rec->channel->SetStreamHandler(nullptr);
  rec->sink.reset();
  // ... then unregisters the texture; the record stays alive until the engine
  // confirms it will not call ObtainDescriptor again.
  registrar_->texture_registrar()->UnregisterTexture(rec->texture_id, [rec]() {});
}

void DisplayCapturePlugin::HandleOwnerWindowDestroyed(int64_t hwnd) {
  std::vector<int64_t> victims;
  for (auto& kv : sessions_) {
    if (kv.second->owner_window == hwnd) victims.push_back(kv.first);
  }
  for (int64_t id : victims) StopCapture(id);
}

void DisplayCapturePlugin::SetupDisplayWindow(const EncodableMap& args,
                                              flutter::MethodResult<EncodableValue>* result) {
  const int64_t handle = GetInt(args, "nativeHandle", 0);
  HWND hwnd = reinterpret_cast<HWND>(handle);
  if (!handle || !IsWindow(hwnd)) {
    result->Error("INTERNAL", "nativeHandle is not a valid window");
    return;
  }
  const int x = static_cast<int>(GetInt(args, "x", 0));
  const int y = static_cast<int>(GetInt(args, "y", 0));
  ConfigureDisplayWindow(
      hwnd, x, y,
      [this](int64_t h, bool hot) {
        if (!chrome_sink_) return;
        EncodableMap m;
        m[S("nativeHandle")] = EncodableValue(h);
        m[S("hot")] = EncodableValue(hot);
        chrome_sink_->Success(EncodableValue(std::move(m)));
      },
      [this](int64_t h) { HandleOwnerWindowDestroyed(h); });
  result->Success();
}

void DisplayCapturePlugin::Diagnostics(flutter::MethodResult<EncodableValue>* result) {
  EnsureCoreInitialized();
  dc_diagnostics d = {};
  dc_get_diagnostics(&d);
  EncodableMap m;
  m[S("renderPath")] = S(d.render_path);
  m[S("backend")] = S(d.backend);
  m[S("gpuName")] = S(d.gpu_name);
  m[S("driver")] = S(d.driver);
  result->Success(EncodableValue(std::move(m)));
}

// --------------------------------------------------------------------------
// Texture hand-off
// --------------------------------------------------------------------------

namespace {
struct ReleaseContext {
  int64_t session;
  int32_t slot;
};
}  // namespace

const FlutterDesktopGpuSurfaceDescriptor* DisplayCapturePlugin::ObtainDescriptor(
    SessionRecord* rec) {
  const int64_t session = rec->session_id.load();
  if (session == 0) return nullptr;
  dc_frame frame = {};
  if (dc_acquire_frame(session, &frame) != DC_OK) return nullptr;

  auto* ctx = new ReleaseContext{session, frame.slot};
  std::lock_guard<std::mutex> lock(rec->descriptor_mutex);
  FlutterDesktopGpuSurfaceDescriptor& d = rec->descriptor;
  d = {};
  d.struct_size = sizeof(d);
  d.handle = frame.shared_handle;
  d.width = frame.width;
  d.height = frame.height;
  d.visible_width = frame.width;
  d.visible_height = frame.height;
  d.format = kFlutterDesktopPixelFormatBGRA8888;
  d.release_callback = &DisplayCapturePlugin::ReleaseDescriptor;
  d.release_context = ctx;
  return &d;
}

// static
void DisplayCapturePlugin::ReleaseDescriptor(void* context) {
  auto* ctx = static_cast<ReleaseContext*>(context);
  dc_release_frame(ctx->session, ctx->slot);
  delete ctx;
}

// --------------------------------------------------------------------------
// Core callbacks (arbitrary threads)
// --------------------------------------------------------------------------

// static
void DisplayCapturePlugin::OnFrame(void* user, int64_t session) {
  auto* rec = static_cast<SessionRecord*>(user);
  rec->session_id.store(session);
  rec->plugin->registrar_->texture_registrar()->MarkTextureFrameAvailable(rec->texture_id);
}

// static
void DisplayCapturePlugin::OnEvent(void* user, int64_t session, const dc_event* ev) {
  auto* rec = static_cast<SessionRecord*>(user);
  rec->session_id.store(session);
  EncodableMap m;
  switch (ev->kind) {
    case DC_EVENT_FRAME_SIZE:
      m[S("type")] = S("frameSize");
      m[S("widthPx")] = EncodableValue(static_cast<int32_t>(ev->width));
      m[S("heightPx")] = EncodableValue(static_cast<int32_t>(ev->height));
      break;
    case DC_EVENT_STALLED: m[S("type")] = S("stalled"); break;
    case DC_EVENT_RESUMED: m[S("type")] = S("resumed"); break;
    case DC_EVENT_DISPLAY_LOST: m[S("type")] = S("displayLost"); break;
    default:
      m[S("type")] = S("failed");
      m[S("code")] = S(ErrorCodeName(ev->code));
      m[S("message")] = S(ev->message);
      break;
  }
  DisplayCapturePlugin* plugin = rec->plugin;
  EncodableValue value(std::move(m));
  plugin->PostToPlatformThread([plugin, session, value]() {
    auto it = plugin->sessions_.find(session);
    if (it != plugin->sessions_.end()) plugin->SendSessionEvent(it->second.get(), value);
  });
}

void DisplayCapturePlugin::SendSessionEvent(SessionRecord* rec, EncodableValue event) {
  if (rec->sink) {
    rec->sink->Success(event);
  } else {
    rec->pending.push_back(std::move(event));  // delivered when Dart listens
  }
}

// static
void DisplayCapturePlugin::OnDisplayChange(void* user) {
  auto* plugin = static_cast<DisplayCapturePlugin*>(user);
  plugin->PostToPlatformThread([plugin]() {
    if (plugin->displays_sink_) plugin->displays_sink_->Success(plugin->DisplaysAsValue());
  });
}

}  // namespace display_capture
