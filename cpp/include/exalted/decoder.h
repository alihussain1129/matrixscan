#pragma once

#include "decode_result.h"

namespace exalted {

class Decoder {
public:
    virtual ~Decoder() = default;

    virtual DecodeResult decode() = 0;
};

} // namespace exalted
