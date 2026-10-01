#ifndef FLUTTER_PLUGIN_DISPLAY_CAPTURE_PLUGIN_H_
#define FLUTTER_PLUGIN_DISPLAY_CAPTURE_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>

#include <atomic>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

#include "dc_core.h"

namespace display_capture {

using flutter::EncodableValue;

// One running capture session and the Flutter texture that shows it.
struct SessionRecord {
  std::atomic<int64_t> session_id{0};
  int64_t texture_id = 0;
  int64_t owner_window = 0;
  std::unique_ptr<flutter::TextureVariant> texture;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> channel;
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink;
  std::vector<EncodableValue> pending;  // events raised before Dart listened
  std::mutex descriptor_mutex;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
  class DisplayCapturePlugin* plugin = nullptr;
};

class DisplayCapturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit DisplayCapturePlugin(flutter::PluginRegistrarWindows* registrar);
  ~DisplayCapturePlugin() override;

  DisplayCapturePlugin(const DisplayCapturePlugin&) = delete;
  DisplayCapturePlugin& operator=(const DisplayCapturePlugin&) = delete;

  // Runs [fn] on the platform thread (any thread may call).
  void PostToPlatformThread(std::function<void()> fn);

  // Callbacks from the Rust core (arbitrary threads).
  static void OnFrame(void* user, int64_t session);
  static void OnEvent(void* user, int64_t session, const dc_event* ev);
  static void OnDisplayChange(void* user);

  // GPU surface callback (raster thread).
  const FlutterDesktopGpuSurfaceDescriptor* ObtainDescriptor(SessionRecord* rec);
  static void ReleaseDescriptor(void* context);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  void ListDisplays(flutter::MethodResult<EncodableValue>* result);
  void StartCapture(const flutter::EncodableMap& args,
                    flutter::MethodResult<EncodableValue>* result);
  void StopCapture(int64_t session_id);
  void SetupDisplayWindow(const flutter::EncodableMap& args,
                          flutter::MethodResult<EncodableValue>* result);
  void Diagnostics(flutter::MethodResult<EncodableValue>* result);

  EncodableValue DisplaysAsValue();
  void EnsureCoreInitialized();
  void DrainPlatformQueue();
  void SendSessionEvent(SessionRecord* rec, EncodableValue event);
  void HandleOwnerWindowDestroyed(int64_t hwnd);

  static LRESULT CALLBACK DispatcherProc(HWND, UINT, WPARAM, LPARAM);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> displays_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> chrome_channel_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> displays_sink_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> chrome_sink_;

  std::map<int64_t, std::shared_ptr<SessionRecord>> sessions_;  // platform thread only
  bool core_ready_ = false;

  HWND dispatcher_ = nullptr;
  std::mutex queue_mutex_;
  std::deque<std::function<void()>> queue_;
  std::atomic<bool> shutting_down_{false};
};

}  // namespace display_capture

#endif  // FLUTTER_PLUGIN_DISPLAY_CAPTURE_PLUGIN_H_
