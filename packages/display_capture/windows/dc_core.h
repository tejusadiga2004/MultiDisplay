// C ABI of the Rust platform layer (native/dc-windows). Keep in sync with
// native/dc-windows/src/types.rs and lib.rs.
#ifndef DISPLAY_CAPTURE_DC_CORE_H_
#define DISPLAY_CAPTURE_DC_CORE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DC_OK 0
#define DC_ERR_DISPLAY_NOT_FOUND (-1)
#define DC_ERR_PERMISSION_DENIED (-2)
#define DC_ERR_UNSUPPORTED (-3)
#define DC_ERR_GPU (-5)
#define DC_ERR_CAPTURE_FAILED (-6)
#define DC_ERR_INTERNAL (-7)
#define DC_ERR_INVALID_ARG (-8)

#define DC_KIND_PHYSICAL 0
#define DC_KIND_VIRTUAL 1
#define DC_KIND_UNKNOWN 2
#define DC_KIND_BUILTIN 3

#define DC_STATUS_AVAILABLE 0
#define DC_STATUS_PERMISSION_DENIED 1
#define DC_STATUS_UNSUPPORTED 2
#define DC_STATUS_PROTECTED 3

#define DC_EVENT_FRAME_SIZE 0
#define DC_EVENT_STALLED 1
#define DC_EVENT_RESUMED 2
#define DC_EVENT_DISPLAY_LOST 3
#define DC_EVENT_FAILED 4

typedef struct dc_display {
  char id[128];
  char name[256];
  int32_t width_px, height_px;
  double scale, refresh_hz;
  int32_t origin_x, origin_y;
  int32_t work_x, work_y, work_w, work_h;
  int32_t is_primary;
  int32_t kind;
  int32_t capture_status;
  char status_detail[160];
} dc_display;

typedef struct dc_options {
  int32_t max_width, max_height;
  int32_t fps;
  int32_t show_cursor;
  int64_t owner_window;
} dc_options;

typedef struct dc_start_result {
  int64_t session;
  int32_t width, height;
} dc_start_result;

typedef struct dc_frame {
  void* shared_handle;
  uint32_t width, height;
  int32_t slot;
} dc_frame;

typedef struct dc_event {
  int32_t kind;
  int32_t width, height;
  int32_t code;
  char message[256];
} dc_event;

typedef struct dc_diagnostics {
  char render_path[32];
  char backend[64];
  char gpu_name[128];
  char driver[64];
} dc_diagnostics;

typedef void (*dc_on_frame_fn)(void* user, int64_t session);
typedef void (*dc_on_event_fn)(void* user, int64_t session, const dc_event* ev);
typedef void (*dc_on_display_change_fn)(void* user);

int32_t dc_init(void* dxgi_adapter);
void dc_shutdown(void);
int32_t dc_list_displays(dc_display* out, int32_t cap, int32_t* count);
int32_t dc_set_display_change_callback(dc_on_display_change_fn cb, void* user);
int32_t dc_start_capture(const char* display_id, const dc_options* options,
                         dc_on_frame_fn on_frame, dc_on_event_fn on_event,
                         void* user, dc_start_result* out);
int32_t dc_acquire_frame(int64_t session, dc_frame* out);
void dc_release_frame(int64_t session, int32_t slot);
int32_t dc_stop_capture(int64_t session);
void dc_stop_sessions_for_window(int64_t native_window);
int32_t dc_get_diagnostics(dc_diagnostics* out);
const char* dc_last_error(void);

#ifdef __cplusplus
}
#endif

#endif  // DISPLAY_CAPTURE_DC_CORE_H_
