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
#ifdef __cplusplus
}
#endif
#endif
