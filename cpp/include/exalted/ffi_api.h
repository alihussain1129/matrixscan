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

// Format bit flags (same values as zxing-cpp's BarcodeFormat, stable ABI).
// formatsMask = 0 means "all supported formats".
#define EXALTED_FMT_AZTEC        (1 << 0)
#define EXALTED_FMT_CODABAR      (1 << 1)
#define EXALTED_FMT_CODE39       (1 << 2)
#define EXALTED_FMT_CODE93       (1 << 3)
#define EXALTED_FMT_CODE128      (1 << 4)
#define EXALTED_FMT_DATABAR      (1 << 5)
#define EXALTED_FMT_DATABAR_EXP  (1 << 6)
#define EXALTED_FMT_DATAMATRIX   (1 << 7)
#define EXALTED_FMT_EAN8         (1 << 8)
#define EXALTED_FMT_EAN13        (1 << 9)
#define EXALTED_FMT_ITF          (1 << 10)
#define EXALTED_FMT_MAXICODE     (1 << 11)
#define EXALTED_FMT_PDF417       (1 << 12)
#define EXALTED_FMT_QRCODE       (1 << 13)
#define EXALTED_FMT_UPCA         (1 << 14)
#define EXALTED_FMT_UPCE         (1 << 15)
#define EXALTED_FMT_MICROQR      (1 << 16)

// Number of int32 slots exalted_decode writes into `info`.
#define EXALTED_DECODE_INFO_LEN 12

// Decodes one barcode from an 8-bit luminance image (rows may be padded:
// rowStride >= width). Any orientation is tried.
//
// info[0]  format flag of the decoded symbol (EXALTED_FMT_*)
// info[1]  UTF-8 text length in bytes (the needed size if it did not fit)
// info[2..9] corners in image pixels: tlx tly trx try brx bry blx bly
// info[10] 1 if a symbol was found
// info[11] decode time in microseconds
//
// Returns 1 = decoded (text copied to textOut, NOT null-terminated),
//         0 = no barcode in this frame,
//        -1 null pointer or bad info/text capacity, -2 bad dimensions,
//        -3 buffer shorter than height/stride imply,
//        -4 internal exception, -5 textOut too small (info[1] = needed size).
EXALTED_API int32_t exalted_decode(
    const uint8_t* luma, int32_t lumaLen,
    int32_t width, int32_t height, int32_t rowStride,
    int32_t formatsMask, int32_t tryHarder,
    int32_t* info, int32_t infoLen,
    uint8_t* textOut, int32_t textCap);

#ifdef __cplusplus
}
#endif
