#include "include/display_capture/display_capture_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "display_capture_plugin.h"

void DisplayCapturePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  display_capture::DisplayCapturePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
