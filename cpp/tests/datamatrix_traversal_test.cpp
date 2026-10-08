#include <cstdint>
#include <iostream>
#include <stdexcept>

#include "exalted/bit_matrix.h"
#include "exalted/datamatrix_traversal.h"

using exalted::BitMatrix;
using exalted::DataMatrixTraversal;

namespace
{
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

        /*
         * ------------------------------------------------------------
         * Corner 1
         * ------------------------------------------------------------
         *
         * Anchor:
         *     row    = 10
         *     column = 5
         *
         * Reads:
         *
         * (9,5) (9,6) (9,7)
         * (10,3) (10,4) (10,5)
         * (11,4) (11,5)
         *
         * Expected:
         *     00111100 = 0x3C
         */
        {
            BitMatrix matrix(20, 20);

            const int coordinates[8][2] =
            {
                {9,  5},
                {9,  6},
                {9,  7},
                {10, 3},
                {10, 4},
                {10, 5},
                {11, 4},
                {11, 5}
            };

            const bool values[8] =
            {
                false, false, true, true,
                true, true, false, false
            };

            setBits(matrix, coordinates, values);

            const auto actual =
                DataMatrixTraversal::readCorner1(matrix, 10, 5);

            requireEqual("Corner 1", 0x3C, actual);
        }

        /*
         * ------------------------------------------------------------
         * Corner 2
         * ------------------------------------------------------------
         *
         * Anchor:
         *     row    = 5
         *     column = 8
         *
         * Reads:
         *
         * (2,8) (3,8) (4,8)
         * (5,4) (5,5) (5,6) (5,7)
         * (6,7)
         *
         * Expected:
         *     10010110 = 0x96
         */
        {
            BitMatrix matrix(20, 20);

            const int coordinates[8][2] =
            {
                {2, 8},
                {3, 8},
                {4, 8},
                {5, 4},
                {5, 5},
                {5, 6},
                {5, 7},
                {6, 7}
            };

            const bool values[8] =
            {
                true, false, false, true,
                false, true, true, false
            };

            setBits(matrix, coordinates, values);

            const auto actual =
                DataMatrixTraversal::readCorner2(matrix, 5, 8);

            requireEqual("Corner 2", 0x96, actual);
        }

        /*
         * ------------------------------------------------------------
         * Corner 3
         * ------------------------------------------------------------
         *
         * Anchor:
         *     row    = 5
         *     column = 10
         *
         * Reads:
         *
         * (2,10) (3,10) (4,10)
         * (5,8) (5,9) (5,10)
         * (6,9) (7,9)
         *
         * Expected:
         *     01011010 = 0x5A
         */
        {
            BitMatrix matrix(20, 20);

            const int coordinates[8][2] =
            {
                {2, 10},
                {3, 10},
                {4, 10},
                {5, 8},
                {5, 9},
                {5, 10},
                {6, 9},
                {7, 9}
            };

            const bool values[8] =
            {
                false, true, false, true,
                true, false, true, false
            };

            setBits(matrix, coordinates, values);

            const auto actual =
                DataMatrixTraversal::readCorner3(matrix, 5, 10);

            requireEqual("Corner 3", 0x5A, actual);
        }

        /*
         * ------------------------------------------------------------
         * Corner 4
         * ------------------------------------------------------------
         *
         * numCols = 20
         * row     = 10
         *
         * Reads:
         *
         * (9,0)
         * (9,19)
         * (0,17) (0,18) (0,19)
         * (1,17) (1,18) (1,19)
         *
         * Expected:
         *     11000011 = 0xC3
         */
        {
            BitMatrix matrix(20, 20);

            const int coordinates[8][2] =
            {
                {9,  0},
                {9, 19},
                {0, 17},
                {0, 18},
                {0, 19},
                {1, 17},
                {1, 18},
                {1, 19}
            };

            const bool values[8] =
            {
                true, true, false, false,
                false, false, true, true
            };

            setBits(matrix, coordinates, values);

            const auto actual =
                DataMatrixTraversal::readCorner4(matrix, 10, 20);

            requireEqual("Corner 4", 0xC3, actual);
        }

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
