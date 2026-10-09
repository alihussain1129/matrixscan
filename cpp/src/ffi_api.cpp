#include "exalted/ffi_api.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#if defined(__ANDROID__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

#include "ReadBarcode.h"

namespace
{
std::atomic<int32_t> g_callCount{0};

// Separable min/max filter. Grows dark dots (min) or light dots (max) so the
// separate dots of a dot-peened Data Matrix touch and form solid modules.
void rankFilter(const uint8_t* src, int w, int h, int stride, int r,
                bool useMax, std::vector<uint8_t>& out)
{
    std::vector<uint8_t> tmp(static_cast<size_t>(w) * h);
    out.resize(static_cast<size_t>(w) * h);

    for (int y = 0; y < h; ++y)
    {
        const uint8_t* row = src + static_cast<int64_t>(y) * stride;
        uint8_t* dst = tmp.data() + static_cast<size_t>(y) * w;
        for (int x = 0; x < w; ++x)
        {
            const int lo = std::max(0, x - r);
            const int hi = std::min(w - 1, x + r);
            uint8_t v = row[lo];
            for (int i = lo + 1; i <= hi; ++i)
            {
                v = useMax ? std::max(v, row[i]) : std::min(v, row[i]);
            }
            dst[x] = v;
        }
    }

    for (int y = 0; y < h; ++y)
    {
        const int lo = std::max(0, y - r);
        const int hi = std::min(h - 1, y + r);
        uint8_t* dst = out.data() + static_cast<size_t>(y) * w;
        for (int x = 0; x < w; ++x)
        {
            uint8_t v = tmp[static_cast<size_t>(lo) * w + x];
            for (int j = lo + 1; j <= hi; ++j)
            {
                const uint8_t p = tmp[static_cast<size_t>(j) * w + x];
                v = useMax ? std::max(v, p) : std::min(v, p);
            }
            dst[x] = v;
        }
    }
}

ZXing::BarcodeFormats toFormats(int32_t mask)
{
    if (mask == 0)
    {
        return ZXing::BarcodeFormat::Any;
    }

    ZXing::BarcodeFormats formats;

    for (int bit = 0; bit < 20; ++bit)
    {
        if ((mask & (1 << bit)) != 0)
        {
            formats |= static_cast<ZXing::BarcodeFormat>(1 << bit);
        }
    }

    return formats;
}
} // namespace

extern "C"
{

int32_t exalted_api_version(void)
{
    return 2;
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

    out[0] = 2;
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

int32_t exalted_decode(
    const uint8_t* luma, int32_t lumaLen,
    int32_t width, int32_t height, int32_t rowStride,
    int32_t formatsMask, int32_t tryHarder,
    int32_t* info, int32_t infoLen,
    uint8_t* textOut, int32_t textCap)
{
    if (luma == nullptr || info == nullptr || textOut == nullptr) return -1;
    if (infoLen < EXALTED_DECODE_INFO_LEN || textCap <= 0) return -1;
    if (width <= 0 || height <= 0 || rowStride < width) return -2;

    const int64_t needed =
        static_cast<int64_t>(height - 1) * rowStride + width;
    if (needed > lumaLen) return -3;

    for (int i = 0; i < EXALTED_DECODE_INFO_LEN; ++i) info[i] = 0;

    try
    {
        #if defined(__ANDROID__)
        // Live-scan decode thread runs at low priority so the UI and raster
        // threads get the CPU first. Lowering priority is always permitted.
        if ((tryHarder & 512) != 0)
        {
            thread_local bool niceSet = false;
            if (!niceSet)
            {
                niceSet = true;
                setpriority(PRIO_PROCESS,
                            static_cast<id_t>(syscall(SYS_gettid)), 10);
            }
        }
#endif
        const auto start = std::chrono::steady_clock::now();

        // Dot-peen support: 64 = grow dark dots 1 px, 128 = 2 px,
        // +256 = grow light dots instead.
        const int dotRadius = (tryHarder & 64) != 0 ? 1
                              : (tryHarder & 128) != 0 ? 2 : 0;
        std::vector<uint8_t> fused;
        const uint8_t* src = luma;
        int srcStride = rowStride;
        if (dotRadius > 0)
        {
            rankFilter(luma, width, height, rowStride, dotRadius,
                       (tryHarder & 256) != 0, fused);
            src = fused.data();
            srcStride = width;
        }

        const ZXing::ImageView image(
            src, width, height, ZXing::ImageFormat::Lum, srcStride, 1);

        ZXing::ReaderOptions options;
        options.setFormats(toFormats(formatsMask));
        // `tryHarder` is a flags field. 0 and 1 behave as before.
        //   1 = harder + invert, 2 = invert only, 4 = no rotate,
        //   8 = no downscale, 16 = global-histogram binarizer
        const bool harder = (tryHarder & 1) != 0;
        const bool invert = harder || (tryHarder & 2) != 0;
        options.setTryRotate((tryHarder & 4) == 0);
        options.setTryHarder(harder);
        options.setTryInvert(invert);
        options.setTryDownscale((tryHarder & 8) == 0);
        if ((tryHarder & 16) != 0)
        {
            options.setBinarizer(ZXing::Binarizer::GlobalHistogram);
        }
        options.setMaxNumberOfSymbols(1);

        const ZXing::Barcode barcode = ZXing::ReadBarcode(image, options);

        const auto micros = std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - start).count();
        info[11] = static_cast<int32_t>(micros);

        if (!barcode.isValid())
        {
            return 0;
        }

        const std::string text = barcode.text();
        info[0] = static_cast<int32_t>(barcode.format());
        info[1] = static_cast<int32_t>(text.size());

        const auto& pos = barcode.position();
        info[2] = pos.topLeft().x;
        info[3] = pos.topLeft().y;
        info[4] = pos.topRight().x;
        info[5] = pos.topRight().y;
        info[6] = pos.bottomRight().x;
        info[7] = pos.bottomRight().y;
        info[8] = pos.bottomLeft().x;
        info[9] = pos.bottomLeft().y;
        info[10] = 1;

        if (static_cast<int64_t>(text.size()) > textCap)
        {
            return -5;
        }

        std::memcpy(textOut, text.data(), text.size());
        return 1;
    }
    catch (const std::exception&)
    {
        return -4;
    }
    catch (...)
    {
        return -4;
    }
}

} // extern "C"
