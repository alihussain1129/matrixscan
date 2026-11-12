#pragma once

#include "decode_result.h"

namespace exalted {

struct DecodeInput {
    const unsigned char* luma = nullptr;
    int width = 0;
    int height = 0;
    int rowStride = 0;
    int tryHarder = 0;
};

class Decoder {
public:
    virtual ~Decoder() = default;

    virtual DecodeResult decode(const DecodeInput& input) = 0;
};

} // namespace exalted
