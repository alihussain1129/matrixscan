#pragma once

#include "decoder.h"

namespace exalted {

class DataMatrixDecoder final : public Decoder {
public:
    DataMatrixDecoder() = default;
    ~DataMatrixDecoder() override = default;

    DecodeResult decode() override;
};

} // namespace exalted
