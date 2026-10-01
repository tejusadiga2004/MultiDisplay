# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "display_capture")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "display_capture_plugin")

# ---------------------------------------------------------------------------
# Rust platform layer (native/dc-windows) -> dc_windows.dll + import library.
# cargo is invoked on every build; it is a no-op when nothing changed.
# ---------------------------------------------------------------------------
find_program(DC_CARGO cargo REQUIRED)
# The Rust workspace lives inside the plugin package (works through Flutter's
# plugin symlink, which CMake cannot resolve back on Windows).
set(DC_NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../native")
set(DC_RUST_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/rust-target")
set(DC_RUST_DLL "${DC_RUST_TARGET_DIR}/release/dc_windows.dll")
set(DC_RUST_IMPLIB "${DC_RUST_TARGET_DIR}/release/dc_windows.dll.lib")

add_custom_target(dc_windows_rust ALL
  COMMAND ${CMAKE_COMMAND} -E env "CARGO_TARGET_DIR=${DC_RUST_TARGET_DIR}"
          ${DC_CARGO} build --release -p dc-windows
          --manifest-path "${DC_NATIVE_DIR}/Cargo.toml"
  BYPRODUCTS "${DC_RUST_DLL}" "${DC_RUST_IMPLIB}"
  WORKING_DIRECTORY "${DC_NATIVE_DIR}"
  COMMENT "Building Rust platform layer (dc-windows)"
  VERBATIM
)

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "display_capture_plugin.cpp"
  "display_capture_plugin.h"
  "window_chrome.cpp"
  "window_chrome.h"
  "dc_core.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/display_capture/display_capture_plugin_c_api.h"
  "display_capture_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL NOMINMAX)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  "${DC_RUST_IMPLIB}" dxgi comctl32 user32)
add_dependencies(${PLUGIN_NAME} dc_windows_rust)

# Libraries bundled next to the app executable.
set(display_capture_bundled_libraries
  "${DC_RUST_DLL}"
  PARENT_SCOPE
)

