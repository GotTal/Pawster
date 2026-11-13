#ifndef POSTERBRIDGE_H
#define POSTERBRIDGE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*PBReadyCallback)(void *, const char *, uint16_t, const char *const *, const char *const *, size_t);
typedef void (*PBPinCallback)(const char *, void *);
typedef struct { char *error; char *device_name; char *device_model; char *device_udid; char *pairing_file_path; char *host_alt_irk_hex; } PBPairResult;
void pb_string_free(char *);
int32_t pb_extract_zip(const char *, const char *, char **, char **);
uint64_t pb_operation_new(void);
void pb_operation_cancel(uint64_t);
void pb_operation_free(uint64_t);
int32_t pb_pair(uint64_t, uint32_t, const char *, const char *, const char *, PBReadyCallback, PBPinCallback, void *, PBPairResult *);
void pb_pair_result_free(PBPairResult *);
int32_t pb_find_container(uint64_t, uint32_t, const char *, const char *, char **, char **);
// allow_fallbacks: 0 = use only the supplied peer; 1 = allow compatible default hosts.
int32_t pb_find_container_with_policy(uint64_t, uint32_t, const char *, const char *, uint8_t, char **, char **);
// Sends a new UUID-named Collections descriptor only. Zero means SENT, not target-verified.
int32_t pb_airlift_install(uint64_t, const char *, const char *, uint8_t, const char *, const char *, const char *, const char *, char **);
// Restores transaction-owned temporary Books sync state; never removes wallpapers.
int32_t pb_airlift_recover(uint64_t, const char *, const char *, uint8_t, const char *, char **);
#ifdef __cplusplus
}
#endif
#endif
