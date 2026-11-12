#pragma once

#include <string>
#include <array>

namespace exalted {

struct DecodeResult {
    bool success = false;
    std::string format;
    std::string text;
    std::string rawData;
    std::string error;
    double decodeTimeMs = 0.0;
    std::array<int, 8> corners{};
};

} // namespace exalted
