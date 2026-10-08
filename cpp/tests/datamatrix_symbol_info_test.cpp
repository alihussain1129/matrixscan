#include <cassert>
#include <iostream>

#include "exalted/datamatrix_symbol_info.h"

using exalted::DataMatrixSymbolInfo;
using exalted::findDataMatrixSymbolInfo;

int main()
{
    std::cout << "========================================\n";
    std::cout << " Data Matrix Symbol Info TEST\n";
    std::cout << "========================================\n";

    constexpr int expectedSymbols = 30;

    const int symbols[][2] =
    {
        {10, 10},
        {12, 12},
        {14, 14},
        {16, 16},
        {18, 18},
        {20, 20},
        {22, 22},
        {24, 24},
        {26, 26},

        {32, 32},
        {36, 36},
        {40, 40},
        {44, 44},
        {48, 48},
        {52, 52},

        {64, 64},
        {72, 72},
        {80, 80},
        {88, 88},
        {96, 96},
        {104, 104},

        {120, 120},
        {132, 132},
        {144, 144},

        // Rectangular symbols.
        {18, 8},
        {32, 8},
        {26, 12},
        {36, 12},
        {36, 16},
        {48, 16}
    };

    constexpr int symbolCount =
        static_cast<int>(sizeof(symbols) / sizeof(symbols[0]));

    assert(symbolCount == expectedSymbols);

    for (int i = 0; i < symbolCount; ++i)
    {
        const int width = symbols[i][0];
        const int height = symbols[i][1];

        const DataMatrixSymbolInfo* info =
            findDataMatrixSymbolInfo(width, height);

        assert(info != nullptr);
        assert(info->symbolWidth == width);
        assert(info->symbolHeight == height);
        assert(info->totalCodewords() > 0);
        assert(info->dataWidth() > 0);
        assert(info->dataHeight() > 0);
        assert(info->regionCount() > 0);

        std::cout
            << "PASS: "
            << width
            << "x"
            << height
            << " | Data="
            << info->dataCodewords
            << " | ECC="
            << info->errorCorrectionCodewords
            << " | Regions="
            << info->regionsHorizontal
            << "x"
            << info->regionsVertical
            << "\n";
    }

    // Unsupported size must return nullptr.
    assert(findDataMatrixSymbolInfo(11, 11) == nullptr);
    assert(findDataMatrixSymbolInfo(18, 18 + 1) == nullptr);

    std::cout << "\n========================================\n";
    std::cout << " ALL 30 SYMBOLS TEST PASSED\n";
    std::cout << "========================================\n";

    return 0;
}
