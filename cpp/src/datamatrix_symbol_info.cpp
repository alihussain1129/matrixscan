#include "exalted/datamatrix_symbol_info.h"

namespace exalted {
namespace {

constexpr DataMatrixSymbolInfo kSymbolTable[] =
{
    // Square ECC 200 symbols.
    //
    // width height regionWidth regionHeight regionsX regionsY
    // dataCW ECCCW RSBlocks

    {10,   10,  8,  8,  1, 1,     3,   5,  1},
    {12,   12, 10, 10,  1, 1,     5,   7,  1},
    {14,   14, 12, 12,  1, 1,     8,  10, 1},
    {16,   16, 14, 14, 1, 1,     12,  12, 1},
    {18,   18, 16, 16, 1, 1,     18,  14, 1},
    {20,   20, 18, 18, 1, 1,     22,  18, 1},
    {22,   22, 20, 20, 1, 1,     30,  20, 1},
    {24,   24, 22, 22, 1, 1,     36,  24, 1},
    {26,   26, 24, 24, 1, 1,     44,  28, 1},

    {32,   32, 14, 14, 2, 2,     62,  36, 1},
    {36,   36, 16, 16, 2, 2,     86,  42, 1},
    {40,   40, 18, 18, 2, 2,    114,  48, 1},
    {44,   44, 20, 20, 2, 2,    144,  56, 1},
    {48,   48, 22, 22, 2, 2,    174,  68, 1},

    {52,   52, 24, 24, 2, 2,    204,  84, 2},

    {64,   64, 14, 14, 4, 4,    280, 112, 2},
    {72,   72, 16, 16, 4, 4,    368, 144, 4},
    {80,   80, 18, 18, 4, 4,    456, 192, 4},
    {88,   88, 20, 20, 4, 4,    576, 224, 4},
    {96,   96, 22, 22, 4, 4,    696, 272, 4},
    {104, 104, 24, 24, 4, 4,    816, 336, 6},

    {120, 120, 18, 18, 6, 6,   1050, 408, 6},
    {132, 132, 20, 20, 6, 6,   1304, 496, 8},
    {144, 144, 22, 22, 6, 6,   1558, 620, 10},

    // Rectangular ECC 200 symbols.

    {18,   8, 16,  6, 1, 1,      5,   7,  1},
    {32,   8, 14,  6, 2, 1,     10,  11, 1},
    {26,  12, 24, 10, 1, 1,     16,  14, 1},
    {36,  12, 16, 10, 2, 1,     22,  18, 1},
    {36,  16, 16, 14, 2, 1,     32,  24, 1},
    {48,  16, 22, 14, 2, 1,     49,  28, 1}
};

} // namespace

const DataMatrixSymbolInfo* findDataMatrixSymbolInfo(
    int symbolWidth,
    int symbolHeight) noexcept
{
    for (const auto& info : kSymbolTable)
    {
        if (info.symbolWidth == symbolWidth &&
            info.symbolHeight == symbolHeight)
        {
            return &info;
        }
    }

    return nullptr;
}

} // namespace exalted

