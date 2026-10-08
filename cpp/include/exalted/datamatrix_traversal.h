#pragma once

#include <cstdint>
#include <functional>

#include "exalted/bit_matrix.h"

namespace exalted {

class DataMatrixTraversal
{
public:
    using ModuleReader = std::function<bool(int, int)>;

    static std::uint8_t readUtah(
        const BitMatrix& matrix,
        int row,
        int column);

    static std::uint8_t readCorner1(
        const BitMatrix& matrix,
        int row,
        int column);

    static std::uint8_t readCorner2(
        const BitMatrix& matrix,
        int row,
        int column);

    static std::uint8_t readCorner3(
        const BitMatrix& matrix,
        int row,
        int column);

    static std::uint8_t readCorner4(
        const BitMatrix& matrix,
        int row,
        int numCols);

    static std::uint8_t readUtah(
        const ModuleReader& reader,
        int row,
        int column);

    static std::uint8_t readCorner1(
        const ModuleReader& reader,
        int numRows,
        int numColumns);

    static std::uint8_t readCorner2(
        const ModuleReader& reader,
        int numRows,
        int numColumns);

    static std::uint8_t readCorner3(
        const ModuleReader& reader,
        int numRows,
        int numColumns);

    static std::uint8_t readCorner4(
        const ModuleReader& reader,
        int numRows,
        int numColumns);
};

} // namespace exalted
