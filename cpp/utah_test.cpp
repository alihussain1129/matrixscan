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

    BitMatrix matrix(rows, cols);

    // Desired byte: 0xA6 = 10100110
    //
    // Corner 4 positions:
    //
    // 1: (row - 1, 0)
    // 2: (row - 1, cols - 1)
    // 3: (0,       cols - 3)
    // 4: (0,       cols - 2)
    // 5: (0,       cols - 1)
    // 6: (1,       cols - 3)
    // 7: (1,       cols - 2)
    // 8: (1,       cols - 1)

    constexpr int row = 5;

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

    matrix.set(row - 1, 0,           bits[0]);
    matrix.set(row - 1, cols - 1,    bits[1]);
    matrix.set(0,       cols - 3,    bits[2]);
    matrix.set(0,       cols - 2,    bits[3]);
    matrix.set(0,       cols - 1,    bits[4]);
    matrix.set(1,       cols - 3,    bits[5]);
    matrix.set(1,       cols - 2,    bits[6]);
    matrix.set(1,       cols - 1,    bits[7]);

    const std::uint8_t actual =
        DataMatrixTraversal::readCorner4(matrix, row, cols);

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
