#pragma once
#include <stdint.h>

#if defined(_WIN32)
#define EXALTED_API __declspec(dllexport)
#else
#define EXALTED_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Bumped whenever the C ABI changes.
EXALTED_API int32_t exalted_api_version(void);

// Diagnostic only: inspects a luminance buffer without decoding it.
// out[0..8] = apiVersion, width, height, rowStride, rotation,
//             meanLuma, minLuma, maxLuma, callCount
// Returns 0 on success, -1 null/outLen, -2 bad dimensions, -3 buffer too short.
EXALTED_API int32_t exalted_probe(
    const uint8_t* luma, int32_t lumaLen,
    int32_t width, int32_t height, int32_t rowStride,
    int32_t rotationDegrees,
    int32_t* out, int32_t outLen);

#ifdef __cplusplus
}
#endif
