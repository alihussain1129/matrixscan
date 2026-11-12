#include "exalted/datamatrix_decoder.h"

#include <chrono>
#include <stdexcept>

#include "ReadBarcode.h"

namespace exalted {

DecodeResult DataMatrixDecoder::decode(const DecodeInput& input)
{
    DecodeResult result;
    result.format = "Data Matrix";

    if (!input.luma || input.width <= 0 || input.height <= 0 || input.rowStride < input.width) {
        result.error = "Invalid luminance image.";
        return result;
    }

    try {
        const auto start = std::chrono::steady_clock::now();
        const ZXing::ImageView image(input.luma, input.width, input.height,
                                     ZXing::ImageFormat::Lum, input.rowStride, 1);
        ZXing::ReaderOptions options;
        options.setFormats(ZXing::BarcodeFormat::DataMatrix);
        const bool harder = (input.tryHarder & 1) != 0;
        options.setTryHarder(harder);
        options.setTryInvert(harder || (input.tryHarder & 2) != 0);
        options.setTryRotate((input.tryHarder & 4) == 0);
        options.setTryDownscale((input.tryHarder & 8) == 0);
        if ((input.tryHarder & 16) != 0)
            options.setBinarizer(ZXing::Binarizer::GlobalHistogram);
        options.setMaxNumberOfSymbols(1);

        const auto barcode = ZXing::ReadBarcode(image, options);
        result.decodeTimeMs = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - start).count();
        if (!barcode.isValid()) return result;

        result.success = true;
        result.text = barcode.text();
        result.rawData = result.text;
        const auto& pos = barcode.position();
        result.corners = {pos.topLeft().x, pos.topLeft().y,
                          pos.topRight().x, pos.topRight().y,
                          pos.bottomRight().x, pos.bottomRight().y,
                          pos.bottomLeft().x, pos.bottomLeft().y};
    } catch (const std::exception& e) {
        result.error = e.what();
    } catch (...) {
        result.error = "Unknown Data Matrix decoder error.";
    }

    return result;
}

} // namespace exalted
