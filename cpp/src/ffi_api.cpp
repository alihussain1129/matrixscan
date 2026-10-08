#include "exalted/ffi_api.h"

#include <algorithm>
#include <atomic>

namespace
{
std::atomic<int32_t> g_callCount{0};
}

extern "C"
{

int32_t exalted_api_version(void)
{
    return 1;
}

int32_t exalted_probe(
    const uint8_t* luma, int32_t lumaLen,
    int32_t width, int32_t height, int32_t rowStride,
    int32_t rotationDegrees,
    int32_t* out, int32_t outLen)
{
    if (luma == nullptr || out == nullptr || outLen < 9) return -1;
    if (width <= 0 || height <= 0 || rowStride < width) return -2;

    const int64_t needed =
        static_cast<int64_t>(height - 1) * rowStride + width;
    if (needed > lumaLen) return -3;

    const int stepX = std::max(1, width / 32);
    const int stepY = std::max(1, height / 32);

    int64_t sum = 0;
    int64_t count = 0;
    int32_t minV = 255;
    int32_t maxV = 0;

    for (int y = 0; y < height; y += stepY)
    {
        const uint8_t* row = luma + static_cast<int64_t>(y) * rowStride;
        for (int x = 0; x < width; x += stepX)
        {
            const int32_t v = row[x];
            sum += v;
            ++count;
            minV = std::min(minV, v);
            maxV = std::max(maxV, v);
        }
    }

    out[0] = 1;
    out[1] = width;
    out[2] = height;
    out[3] = rowStride;
    out[4] = rotationDegrees;
    out[5] = count > 0 ? static_cast<int32_t>(sum / count) : 0;
    out[6] = minV;
    out[7] = maxV;
    out[8] = ++g_callCount;
    return 0;
}

} // extern "C"
