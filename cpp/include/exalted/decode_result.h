#pragma once

#include <string>

namespace exalted {

struct DecodeResult {
    bool success = false;
    std::string format;
    std::string text;
    std::string rawData;
    std::string error;
    double decodeTimeMs = 0.0;
};

} // namespace exalted
