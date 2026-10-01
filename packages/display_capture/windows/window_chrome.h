#ifndef DISPLAY_CAPTURE_WINDOW_CHROME_H_
#define DISPLAY_CAPTURE_WINDOW_CHROME_H_

#include <windows.h>

#include <cstdint>
#include <functional>

namespace display_capture {

using CloseHoverCallback = std::function<void(int64_t hwnd, bool hot)>;
using WindowDestroyedCallback = std::function<void(int64_t hwnd)>;

// Applies the DisplayWindow chrome (SPEC §9.5, Windows) to an already-created
// top-level window owned by Flutter's windowing API:
//   * always on top,
//   * excluded from screen capture (D-4),
//   * client area extended over the title bar (transparent title bar),
//   * client-drawn close button region with native HTCLOSE hit-testing,
//   * native drag (HTCAPTION) and resize borders.
// Must be called on the platform (UI) thread.
void ConfigureDisplayWindow(HWND hwnd, int x, int y, CloseHoverCallback on_hover,
                            WindowDestroyedCallback on_destroyed);

}  // namespace display_capture

#endif  // DISPLAY_CAPTURE_WINDOW_CHROME_H_
