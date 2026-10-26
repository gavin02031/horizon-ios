#ifndef HORIZON_IOS_BRIDGE_H
#define HORIZON_IOS_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
uint32_t horizon_ios_bridge_api_version(void);
const char *horizon_ios_minecraft_version(void);
int32_t horizon_ios_resources_status(void);
bool horizon_ios_create_documents_directory(void);
// iPhone-native CAMetalLayer and merged controller + touch input.
int32_t horizon_ios_metal_open(void *ui_view, uint32_t width, uint32_t height);
void horizon_ios_metal_resize(uint32_t width, uint32_t height);
void horizon_ios_metal_close(void);
bool horizon_ios_metal_frame(float frame_dt_seconds);
void horizon_ios_pad_snapshot(uint32_t source, uint32_t buttons,
    float left_x, float left_y, float right_x, float right_y,
    float left_trigger, float right_trigger);
uint64_t horizon_ios_preview_ticks(void);
#ifdef __cplusplus
}
#endif
#endif
