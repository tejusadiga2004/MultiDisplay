#include "window_chrome.h"

#include <commctrl.h>
#include <windowsx.h>

#include <memory>

namespace display_capture {
namespace {

constexpr UINT_PTR kTopSubclassId = 0xDC01;
constexpr UINT_PTR kChildSubclassId = 0xDC02;
constexpr int kStripHeightDip = 32;  // transparent title strip (SPEC §9.4)
constexpr int kCloseWidthDip = 46;   // close button hit area

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

struct ChromeData {
  HWND top = nullptr;
  HWND child = nullptr;
  bool close_hot = false;
  CloseHoverCallback on_hover;
  WindowDestroyedCallback on_destroyed;
};

UINT DpiOf(HWND hwnd) {
  UINT dpi = GetDpiForWindow(hwnd);
  return dpi ? dpi : 96;
}

int Scale(HWND hwnd, int dip) { return MulDiv(dip, static_cast<int>(DpiOf(hwnd)), 96); }

int FrameThickness(HWND hwnd) {
  UINT dpi = DpiOf(hwnd);
  return GetSystemMetricsForDpi(SM_CXFRAME, dpi) +
         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

// Hit test for a screen point inside the (extended) client area.
// Returns HTCLIENT when the point belongs to Flutter's content.
LRESULT HitTestClientPoint(HWND top, POINT screen) {
  POINT origin = {0, 0};
  ClientToScreen(top, &origin);
  RECT client;
  GetClientRect(top, &client);
  const int x = screen.x - origin.x;
  const int y = screen.y - origin.y;
  const int width = client.right - client.left;

  if (!IsZoomed(top)) {
    const int border = FrameThickness(top);
    if (y < border) {
      if (x < border) return HTTOPLEFT;
      if (x >= width - border) return HTTOPRIGHT;
      return HTTOP;
    }
  }
  if (y >= 0 && y < Scale(top, kStripHeightDip)) {
    if (x >= width - Scale(top, kCloseWidthDip)) return HTCLOSE;
    return HTCAPTION;
  }
  return HTCLIENT;
}

void SetHot(ChromeData* d, bool hot) {
  if (d->close_hot == hot) return;
  d->close_hot = hot;
  if (d->on_hover) d->on_hover(reinterpret_cast<int64_t>(d->top), hot);
}

void KeepOnTop(HWND hwnd) {
  SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

LRESULT CALLBACK ChildProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam,
                           UINT_PTR id, DWORD_PTR ref);

LRESULT CALLBACK TopProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam,
                         UINT_PTR id, DWORD_PTR ref) {
  auto* d = reinterpret_cast<ChromeData*>(ref);
  switch (msg) {
    case WM_NCCALCSIZE:
      if (wparam) {
        auto* p = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const RECT original = p->rgrc[0];
        const LRESULT r = DefSubclassProc(hwnd, msg, wparam, lparam);
        // Keep the default left/right/bottom frame (resize + maximize logic),
        // but let the client area start at the top of the window so the
        // content shows through the title bar.
        p->rgrc[0].top = original.top + (IsZoomed(hwnd) ? FrameThickness(hwnd) : 0);
        return r;
      }
      break;

    case WM_NCHITTEST: {
      const LRESULT hit = DefSubclassProc(hwnd, msg, wparam, lparam);
      if (hit != HTCLIENT) return hit;
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      return HitTestClientPoint(hwnd, pt);
    }

    case WM_NCMOUSEMOVE:
      if (wparam == HTCLOSE) {
        TRACKMOUSEEVENT t = {sizeof(t), TME_LEAVE | TME_NONCLIENT, hwnd, 0};
        TrackMouseEvent(&t);
        SetHot(d, true);
      } else {
        SetHot(d, false);
      }
      break;

    case WM_NCMOUSELEAVE:
      SetHot(d, false);
      break;

    case WM_NCLBUTTONDOWN:
      if (wparam == HTCLOSE) return 0;  // handled on button-up
      break;

    case WM_NCLBUTTONUP:
      if (wparam == HTCLOSE) {
        PostMessage(hwnd, WM_SYSCOMMAND, SC_CLOSE, 0);
        return 0;
      }
      break;

    case WM_ACTIVATEAPP:
    case WM_DISPLAYCHANGE:
      KeepOnTop(hwnd);
      break;

    case WM_NCDESTROY: {
      const int64_t handle = reinterpret_cast<int64_t>(hwnd);
      WindowDestroyedCallback cb = std::move(d->on_destroyed);
      // The child is normally already destroyed (its subclass went with it).
      if (d->child && IsWindow(d->child)) {
        RemoveWindowSubclass(d->child, ChildProc, kChildSubclassId);
      }
      RemoveWindowSubclass(hwnd, TopProc, kTopSubclassId);
      const LRESULT r = DefSubclassProc(hwnd, msg, wparam, lparam);
      delete d;
      if (cb) cb(handle);
      return r;
    }
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

// Flutter's view lives in a child window that covers the client area. For the
// title strip and the top resize border it must be "transparent" to hit
// testing so the top-level window's WM_NCHITTEST decides (drag / close / resize).
LRESULT CALLBACK ChildProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam,
                           UINT_PTR id, DWORD_PTR ref) {
  auto* d = reinterpret_cast<ChromeData*>(ref);
  if (msg == WM_NCHITTEST && d && d->top) {
    POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (HitTestClientPoint(d->top, pt) != HTCLIENT) return HTTRANSPARENT;
  }
  return DefSubclassProc(hwnd, msg, wparam, lparam);
}

}  // namespace

void ConfigureDisplayWindow(HWND hwnd, int x, int y, CloseHoverCallback on_hover,
                            WindowDestroyedCallback on_destroyed) {
  if (!IsWindow(hwnd)) return;

  // D-4: never capture our own window (feedback loop). Ignore failure on
  // builds older than Windows 10 2004.
  // QA/debug only: DC_DEBUG_NO_CAPTURE_EXCLUSION=1 makes the window visible to
  // screenshots (it then must not sit on the display it mirrors).
  if (GetEnvironmentVariableW(L"DC_DEBUG_NO_CAPTURE_EXCLUSION", nullptr, 0) == 0) {
    SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE);
  }

  auto* data = new ChromeData();
  data->top = hwnd;
  data->child = GetWindow(hwnd, GW_CHILD);
  data->on_hover = std::move(on_hover);
  data->on_destroyed = std::move(on_destroyed);

  if (!SetWindowSubclass(hwnd, TopProc, kTopSubclassId,
                         reinterpret_cast<DWORD_PTR>(data))) {
    delete data;
    return;
  }
  if (data->child) {
    SetWindowSubclass(data->child, ChildProc, kChildSubclassId,
                      reinterpret_cast<DWORD_PTR>(data));
  }

  // Re-run WM_NCCALCSIZE, then move + pin on top.
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
  SetWindowPos(hwnd, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
}

}  // namespace display_capture
