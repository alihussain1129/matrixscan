#include <cstdint>
#include <iostream>
#include <stdexcept>

#include "exalted/bit_matrix.h"
#include "exalted/datamatrix_traversal.h"

using exalted::BitMatrix;
using exalted::DataMatrixTraversal;

namespace
{
    struct BitPos
    {
        int row;
        int col;
    };

    // Corner layouts from ISO 16022:2006, Figures F.3 to F.6. A negative
    // value counts back from the symbol's far edge. These tables are written
    // independently of the implementation under test and were cross-checked
    // against the vendored zxing-cpp (core/src/datamatrix/DMBitLayout.cpp).
    constexpr BitPos kCorner1[8] = {{-1, 0}, {-1, 1}, {-1, 2}, {0, -2},
                                    {0, -1}, {1, -1}, {2, -1}, {3, -1}};
    constexpr BitPos kCorner2[8] = {{-3, 0}, {-2, 0}, {-1, 0}, {0, -4},
                                    {0, -3}, {0, -2}, {0, -1}, {1, -1}};
    constexpr BitPos kCorner3[8] = {{-1, 0}, {-1, -1}, {0, -3}, {0, -2},
                                    {0, -1}, {1, -3}, {1, -2}, {1, -1}};
    constexpr BitPos kCorner4[8] = {{-3, 0}, {-2, 0}, {-1, 0}, {0, -2},
                                    {0, -1}, {1, -1}, {2, -1}, {3, -1}};

    int resolve(int value, int extent)
    {
        return value < 0 ? extent + value : value;
    }

    void requireEqual(
        const char* name,
        std::uint8_t expected,
        std::uint8_t actual)
    {
        if (expected != actual)
        {
            std::cerr
                << name
                << " FAILED: expected=0x"
                << std::hex
                << static_cast<int>(expected)
                << " actual=0x"
                << static_cast<int>(actual)
                << std::dec
                << '\n';

            throw std::runtime_error(name);
        }

        std::cout
            << name
            << " PASS: 0x"
            << std::hex
            << static_cast<int>(actual)
            << std::dec
            << '\n';
    }

    void setBits(
        BitMatrix& matrix,
        const int coordinates[8][2],
        const bool values[8])
    {
        for (int i = 0; i < 8; ++i)
        {
            matrix.set(
                coordinates[i][1],
                coordinates[i][0],
                values[i]);
        }
    }

    // Builds a symbol of numRows x numCols whose every module equals
    // `background` except for the eight corner positions, which take `values`
    // (first = MSB). Callers run every pattern against BOTH a 1 and a 0
    // background: a read of a wrong module returns the background value, so
    // it is caught whichever bit the pattern holds at that position.
    BitMatrix makeCornerMatrix(
        const BitPos (&layout)[8],
        int numRows,
        int numCols,
        const bool values[8],
        bool background)
    {
        BitMatrix matrix(numCols, numRows);

        for (int y = 0; y < numRows; ++y)
        {
            for (int x = 0; x < numCols; ++x)
            {
                matrix.set(x, y, background);
            }
        }

        for (int i = 0; i < 8; ++i)
        {
            matrix.set(
                resolve(layout[i].col, numCols),
                resolve(layout[i].row, numRows),
                values[i]);
        }

        return matrix;
    }

    using CornerReader = std::uint8_t (*)(const BitMatrix&, int, int);

    // Walking-one / walking-zero check. For each of the eight positions in
    // turn, only that module differs from the background, so the result must
    // be exactly that bit (MSB first). Unlike a fixed pattern, this detects
    // every single misplaced coordinate and every ordering mistake.
    void requireWalkingBits(
        const char* name,
        const BitPos (&layout)[8],
        CornerReader reader,
        int numRows,
        int numCols)
    {
        for (const bool background : {false, true})
        {
            for (int i = 0; i < 8; ++i)
            {
                bool values[8];
                for (int k = 0; k < 8; ++k)
                {
                    values[k] = background;
                }
                values[i] = !background;

                const BitMatrix matrix = makeCornerMatrix(
                    layout, numRows, numCols, values, background);

                const std::uint8_t single =
                    static_cast<std::uint8_t>(1u << (7 - i));
                const std::uint8_t expected =
                    background ? static_cast<std::uint8_t>(~single) : single;

                if (reader(matrix, numRows, numCols) != expected)
                {
                    std::cerr << name << " walking bit " << i
                              << " (background " << background
                              << ") FAILED\n";
                    throw std::runtime_error(name);
                }
            }
        }

        std::cout << name << " walking-bit PASS (16 cases)\n";
    }
}

int main()
{
    try
    {
        std::cout << "========================================\n";
        std::cout << " ECC200 Traversal Unit TEST\n";
        std::cout << "========================================\n\n";

        /*
         * ------------------------------------------------------------
         * Utah
         * ------------------------------------------------------------
         *
         * Anchor:
         *     row    = 10
         *     column = 10
         *
         * ECC200 Utah reads:
         *
         * (8,8) (8,9) (9,8) (9,9)
         * (9,10) (10,8) (10,9) (10,10)
         *
         * Expected:
         *     10100101 = 0xA5
         */
        {
            BitMatrix matrix(20, 20);

            const int coordinates[8][2] =
            {
                {8,  8},
                {8,  9},
                {9,  8},
                {9,  9},
                {9, 10},
                {10, 8},
                {10, 9},
                {10, 10}
            };

            const bool values[8] =
            {
                true, false, true, false,
                false, true, false, true
            };

            setBits(matrix, coordinates, values);

            const auto actual =
                DataMatrixTraversal::readUtah(matrix, 10, 10);

            requireEqual("Utah", 0xA5, actual);
        }

        // The four corner patterns use a non-square 10 x 14 symbol so a
        // swapped rows/columns argument cannot go unnoticed.
        constexpr int kRows = 10;
        constexpr int kCols = 14;

        {
            // 10110001
            const bool values[8] =
                {true, false, true, true, false, false, false, true};
            for (const bool background : {true, false})
            {
                const BitMatrix matrix = makeCornerMatrix(
                    kCorner1, kRows, kCols, values, background);
                requireEqual(
                    background ? "Corner 1 (bg=1)" : "Corner 1 (bg=0)",
                    0xB1,
                    DataMatrixTraversal::readCorner1(matrix, kRows, kCols));
            }
        }

        {
            // 01101001
            const bool values[8] =
                {false, true, true, false, true, false, false, true};
            for (const bool background : {true, false})
            {
                const BitMatrix matrix = makeCornerMatrix(
                    kCorner2, kRows, kCols, values, background);
                requireEqual(
                    background ? "Corner 2 (bg=1)" : "Corner 2 (bg=0)",
                    0x69,
                    DataMatrixTraversal::readCorner2(matrix, kRows, kCols));
            }
        }

        {
            // 11010010
            const bool values[8] =
                {true, true, false, true, false, false, true, false};
            for (const bool background : {true, false})
            {
                const BitMatrix matrix = makeCornerMatrix(
                    kCorner3, kRows, kCols, values, background);
                requireEqual(
                    background ? "Corner 3 (bg=1)" : "Corner 3 (bg=0)",
                    0xD2,
                    DataMatrixTraversal::readCorner3(matrix, kRows, kCols));
            }
        }

        {
            // 00101101
            const bool values[8] =
                {false, false, true, false, true, true, false, true};
            for (const bool background : {true, false})
            {
                const BitMatrix matrix = makeCornerMatrix(
                    kCorner4, kRows, kCols, values, background);
                requireEqual(
                    background ? "Corner 4 (bg=1)" : "Corner 4 (bg=0)",
                    0x2D,
                    DataMatrixTraversal::readCorner4(matrix, kRows, kCols));
            }
        }

        requireWalkingBits(
            "Corner 1", kCorner1, DataMatrixTraversal::readCorner1,
            kRows, kCols);
        requireWalkingBits(
            "Corner 2", kCorner2, DataMatrixTraversal::readCorner2,
            kRows, kCols);
        requireWalkingBits(
            "Corner 3", kCorner3, DataMatrixTraversal::readCorner3,
            kRows, kCols);
        requireWalkingBits(
            "Corner 4", kCorner4, DataMatrixTraversal::readCorner4,
            kRows, kCols);

        std::cout << "\n========================================\n";
        std::cout << " ECC200 TRAVERSAL TEST PASSED\n";
        std::cout << "========================================\n";

        return 0;
    }
    catch (const std::exception& ex)
    {
        std::cerr << "\nTEST FAILED: " << ex.what() << '\n';
        return 1;
    }
}
