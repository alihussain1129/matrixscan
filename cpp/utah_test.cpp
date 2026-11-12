#include <cstdint>
#include <iostream>

#include "exalted/bit_matrix.h"
#include "exalted/datamatrix_traversal.h"

using exalted::BitMatrix;
using exalted::DataMatrixTraversal;

int main()
{
    constexpr int rows = 10;
    constexpr int cols = 10;

    BitMatrix matrix(cols, rows);

    // Desired byte: 0xA6 = 10100110
    //
    // Corner 4 positions (ISO 16022:2006 Figure F.6; negative values count
    // back from the far edge of the symbol), as (row, column):
    //
    // 1: (rows - 3, 0)
    // 2: (rows - 2, 0)
    // 3: (rows - 1, 0)
    // 4: (0,        cols - 2)
    // 5: (0,        cols - 1)
    // 6: (1,        cols - 1)
    // 7: (2,        cols - 1)
    // 8: (3,        cols - 1)
    //
    // Every other module is set so that reading a wrong module is detected.

    for (int y = 0; y < rows; ++y)
    {
        for (int x = 0; x < cols; ++x)
        {
            matrix.set(x, y, true);
        }
    }

    const bool bits[8] =
    {
        true,   // 1
        false,  // 0
        true,   // 1
        false,  // 0
        false,  // 0
        true,   // 1
        true,   // 1
        false   // 0
    };

    const int coordinates[8][2] =
    {
        {rows - 3, 0},
        {rows - 2, 0},
        {rows - 1, 0},
        {0,        cols - 2},
        {0,        cols - 1},
        {1,        cols - 1},
        {2,        cols - 1},
        {3,        cols - 1}
    };

    // BitMatrix::set takes (x, y) = (column, row).
    for (int i = 0; i < 8; ++i)
    {
        matrix.set(coordinates[i][1], coordinates[i][0], bits[i]);
    }

    const std::uint8_t actual =
        DataMatrixTraversal::readCorner4(matrix, rows, cols);

    constexpr std::uint8_t expected = 0xA6;

    std::cout << "========================================\n";
    std::cout << " Data Matrix Corner 4 TEST\n";
    std::cout << "========================================\n";

    std::cout << "Expected: 0x"
              << std::hex
              << static_cast<int>(expected)
              << "\n";

    std::cout << "Actual:   0x"
              << std::hex
              << static_cast<int>(actual)
              << "\n\n";

    if (actual != expected)
    {
        std::cout << "========================================\n";
        std::cout << " Corner 4 TEST FAILED\n";
        std::cout << "========================================\n";
        return 1;
    }

    std::cout << "========================================\n";
    std::cout << " Corner 4 TEST PASSED\n";
    std::cout << "========================================\n";

    return 0;
}
