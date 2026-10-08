#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "exalted/bit_matrix.h"
#include "exalted/datamatrix_symbol_info.h"

#include "exalted/datamatrix_encoder.h"

using exalted::BitMatrix;
using exalted::DataMatrixEncoder;
using exalted::DataMatrixEncoderTestAccess;
using exalted::DataMatrixSymbolInfo;
using exalted::findDataMatrixSymbolInfo;

namespace
{

void requireEqual(
    const std::vector<std::uint8_t>& actual,
    const std::vector<std::uint8_t>& expected,
    const std::string& message)
{
    if (actual != expected)
    {
        std::cerr << "FAIL: " << message << "\n";
        std::cerr << "Expected: ";

        for (const auto value : expected)
        {
            std::cerr
                << "0x"
                << std::hex
                << static_cast<int>(value)
                << " ";
        }

        std::cerr << "\nActual:   ";

        for (const auto value : actual)
        {
            std::cerr
                << "0x"
                << std::hex
                << static_cast<int>(value)
                << " ";
        }

        std::cerr << std::dec << "\n";

        throw std::runtime_error(message);
    }

    std::cout << "PASS: " << message << "\n";
}

void requireTrue(
    const bool condition,
    const std::string& message)
{
    if (!condition)
    {
        throw std::runtime_error(
            "FAIL: " + message
        );
    }

    std::cout << "PASS: " << message << "\n";
}

std::uint8_t gfMultiply(
    const std::uint8_t a,
    const std::uint8_t b)
{
    std::uint16_t aa = a;
    std::uint16_t bb = b;
    std::uint16_t result = 0;

    while (bb != 0)
    {
        if ((bb & 1U) != 0)
        {
            result ^= aa;
        }

        aa <<= 1;

        if ((aa & 0x100U) != 0)
        {
            aa ^= 0x12DU;
        }

        bb >>= 1;
    }

    return static_cast<std::uint8_t>(result);
}

std::vector<std::uint8_t> independentReedSolomon(
    const std::vector<std::uint8_t>& data,
    const int eccCount)
{
    if (eccCount != 5)
    {
        throw std::runtime_error(
            "This independent ECC oracle currently supports exactly 5 ECC codewords."
        );
    }

    const std::uint8_t factors[] =
    {
        228, 48, 15, 111, 62
    };

    std::vector<std::uint8_t> ecc(
        static_cast<std::size_t>(eccCount),
        0
    );

    for (const auto value : data)
    {
        const std::uint8_t m =
            static_cast<std::uint8_t>(
                ecc[static_cast<std::size_t>(eccCount - 1)] ^ value
            );

        for (int k = eccCount - 1; k > 0; --k)
        {
            if (m != 0 && factors[k] != 0)
            {
                ecc[static_cast<std::size_t>(k)] =
                    static_cast<std::uint8_t>(
                        ecc[static_cast<std::size_t>(k - 1)] ^
                        gfMultiply(
                            m,
                            factors[k]
                        )
                    );
            }
            else
            {
                ecc[static_cast<std::size_t>(k)] =
                    ecc[static_cast<std::size_t>(k - 1)];
            }
        }

        if (m != 0 && factors[0] != 0)
        {
            ecc[0] =
                gfMultiply(
                    m,
                    factors[0]
                );
        }
        else
        {
            ecc[0] = 0;
        }
    }

    std::reverse(ecc.begin(), ecc.end());

    return ecc;
}
void testIndependentReedSolomon()
{
    std::cout << "\n--- Independent Reed-Solomon ---\n";

    requireEqual(
        independentReedSolomon(
            {
                66,
                129,
                25
            },
            5
        ),
        {
            124,
            163,
            64,
            233,
            106
        },
        "independent RS ECC for \"A\""
    );

    requireEqual(
        independentReedSolomon(
            {
                142,
                164,
                186
            },
            5
        ),
        {
            114,
            25,
            5,
            88,
            102
        },
        "independent RS ECC for \"123456\""
    );
}

void testEncoderGoldenVectors()
{
    std::cout << "\n--- Encoder Golden Vectors ---\n";

    const auto encodedA =
        DataMatrixEncoder::encode("A");

    requireEqual(
        encodedA.dataCodewords,
        {
            66,
            129,
            25
        },
        "\"A\" encoder data codewords"
    );

    requireEqual(
        encodedA.errorCorrectionCodewords,
        {
            124,
            163,
            64,
            233,
            106
        },
        "\"A\" encoder ECC codewords"
    );

    const auto encoded123456 =
        DataMatrixEncoder::encode("123456");

    requireEqual(
        encoded123456.dataCodewords,
        {
            142,
            164,
            186
        },
        "\"123456\" encoder data codewords"
    );

    requireTrue(
        encoded123456.errorCorrectionCodewords.size() == 5,
        "\"123456\" encoder ECC count"
    );

    requireEqual(
        encoded123456.codewords,
        {
            142,
            164,
            186,
            114,
            25,
            5,
            88,
            102
        },
        "\"123456\" complete codeword stream"
    );

    const auto extended =
        DataMatrixEncoder::encode(
            std::string("\xC4", 1)
        );

    requireTrue(
        !extended.dataCodewords.empty(),
        "extended ASCII prefix encoding"
    );
}

void placeModule(
    BitMatrix& matrix,
    BitMatrix& visited,
    const int row,
    const int column,
    const std::uint8_t codeword,
    const int bit)
{
    int wrappedRow = row;
    int wrappedColumn = column;

    const int numRows = matrix.height();
    const int numColumns = matrix.width();

    if (wrappedRow < 0)
    {
        wrappedRow += numRows;
        wrappedColumn +=
            4 - ((numRows + 4) % 8);
    }

    if (wrappedColumn < 0)
    {
        wrappedColumn += numColumns;
        wrappedRow +=
            4 - ((numColumns + 4) % 8);
    }

    wrappedRow %= numRows;
    wrappedColumn %= numColumns;

    matrix.set(
        wrappedColumn,
        wrappedRow,
        ((codeword >> bit) & 1U) != 0
    );

    visited.setTrue(
        wrappedColumn,
        wrappedRow
    );
}

void placeUtah(
    BitMatrix& matrix,
    BitMatrix& visited,
    const int row,
    const int column,
    const std::uint8_t codeword)
{
    placeModule(matrix, visited, row - 2, column - 2, codeword, 7);
    placeModule(matrix, visited, row - 2, column - 1, codeword, 6);
    placeModule(matrix, visited, row - 1, column - 2, codeword, 5);
    placeModule(matrix, visited, row - 1, column - 1, codeword, 4);
    placeModule(matrix, visited, row - 1, column,     codeword, 3);
    placeModule(matrix, visited, row,     column - 2, codeword, 2);
    placeModule(matrix, visited, row,     column - 1, codeword, 1);
    placeModule(matrix, visited, row,     column,     codeword, 0);
}

void placeCorner1(
    BitMatrix& matrix,
    BitMatrix& visited,
    const std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    placeModule(matrix, visited, rows - 1, 0, codeword, 7);
    placeModule(matrix, visited, rows - 1, 1, codeword, 6);
    placeModule(matrix, visited, rows - 1, 2, codeword, 5);
    placeModule(matrix, visited, 0, columns - 2, codeword, 4);
    placeModule(matrix, visited, 0, columns - 1, codeword, 3);
    placeModule(matrix, visited, 1, columns - 1, codeword, 2);
    placeModule(matrix, visited, 2, columns - 1, codeword, 1);
    placeModule(matrix, visited, 3, columns - 1, codeword, 0);
}

void placeCorner2(
    BitMatrix& matrix,
    BitMatrix& visited,
    const std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    placeModule(matrix, visited, rows - 3, 0, codeword, 7);
    placeModule(matrix, visited, rows - 2, 0, codeword, 6);
    placeModule(matrix, visited, rows - 1, 0, codeword, 5);
    placeModule(matrix, visited, 0, columns - 4, codeword, 4);
    placeModule(matrix, visited, 0, columns - 3, codeword, 3);
    placeModule(matrix, visited, 0, columns - 2, codeword, 2);
    placeModule(matrix, visited, 0, columns - 1, codeword, 1);
    placeModule(matrix, visited, 1, columns - 1, codeword, 0);
}

void placeCorner3(
    BitMatrix& matrix,
    BitMatrix& visited,
    const std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    // Canonical ECC200 Corner 3 (numColumns % 8 == 4).
    // Verified independently: a zxing-cpp decode of a 32x8 symbol placed
    // with this pattern returns the original text.
    placeModule(matrix, visited, rows - 3, 0, codeword, 7);
    placeModule(matrix, visited, rows - 2, 0, codeword, 6);
    placeModule(matrix, visited, rows - 1, 0, codeword, 5);
    placeModule(matrix, visited, 0, columns - 2, codeword, 4);
    placeModule(matrix, visited, 0, columns - 1, codeword, 3);
    placeModule(matrix, visited, 1, columns - 1, codeword, 2);
    placeModule(matrix, visited, 2, columns - 1, codeword, 1);
    placeModule(matrix, visited, 3, columns - 1, codeword, 0);
}
void placeCorner4(
    BitMatrix& matrix,
    BitMatrix& visited,
    const std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    placeModule(matrix, visited, rows - 1, 0, codeword, 7);
    placeModule(matrix, visited, rows - 1, columns - 1, codeword, 6);
    placeModule(matrix, visited, 0, columns - 3, codeword, 5);
    placeModule(matrix, visited, 0, columns - 2, codeword, 4);
    placeModule(matrix, visited, 0, columns - 1, codeword, 3);
    placeModule(matrix, visited, 1, columns - 3, codeword, 2);
    placeModule(matrix, visited, 1, columns - 2, codeword, 1);
    placeModule(matrix, visited, 1, columns - 1, codeword, 0);
}

BitMatrix independentPlace(
    const std::vector<std::uint8_t>& codewords,
    const DataMatrixSymbolInfo& symbolInfo)
{
    const int numRows = symbolInfo.dataHeight();
    const int numColumns = symbolInfo.dataWidth();

    BitMatrix matrix(
        numColumns,
        numRows
    );

    BitMatrix visited(
        numColumns,
        numRows
    );

    int row = 4;
    int column = 0;
    int codewordIndex = 0;

    while (true)
    {
        if (row == numRows &&
            column == 0)
        {
            if (codewordIndex >=
                static_cast<int>(codewords.size()))
            {
                break;
            }

            placeCorner1(
                matrix,
                visited,
                codewords[codewordIndex++]
            );
        }

        if (row == numRows - 2 &&
            column == 0 &&
            (numColumns % 4) != 0)
        {
            if (codewordIndex >=
                static_cast<int>(codewords.size()))
            {
                break;
            }

            placeCorner2(
                matrix,
                visited,
                codewords[codewordIndex++]
            );
        }

        if (row == numRows - 2 &&
            column == 0 &&
            (numColumns % 8) == 4)
        {
            if (codewordIndex >=
                static_cast<int>(codewords.size()))
            {
                break;
            }

            placeCorner3(
                matrix,
                visited,
                codewords[codewordIndex++]
            );
        }

        if (row == numRows + 4 &&
            column == 2 &&
            (numColumns % 8) == 0)
        {
            if (codewordIndex >=
                static_cast<int>(codewords.size()))
            {
                break;
            }

            placeCorner4(
                matrix,
                visited,
                codewords[codewordIndex++]
            );
        }

        while (row >= 0 &&
               column < numColumns)
        {
            if (row < numRows &&
                column >= 0 &&
                !visited.get(column, row))
            {
                if (codewordIndex >=
                    static_cast<int>(codewords.size()))
                {
                    break;
                }

                placeUtah(
                    matrix,
                    visited,
                    row,
                    column,
                    codewords[codewordIndex++]
                );
            }

            row -= 2;
            column += 2;
        }

        row += 1;
        column += 3;

        while (row < numRows &&
               column >= 0)
        {
            if (row >= 0 &&
                column < numColumns &&
                !visited.get(column, row))
            {
                if (codewordIndex >=
                    static_cast<int>(codewords.size()))
                {
                    break;
                }

                placeUtah(
                    matrix,
                    visited,
                    row,
                    column,
                    codewords[codewordIndex++]
                );
            }

            row += 2;
            column -= 2;
        }

        row += 3;
        column += 1;

        if (row >= numRows &&
            column >= numColumns)
        {
            break;
        }
    }

    if (codewordIndex !=
        static_cast<int>(codewords.size()))
    {
        throw std::runtime_error(
            "Independent placement did not consume all codewords."
        );
    }

    if (!visited.get(
            numColumns - 1,
            numRows - 1))
    {
        matrix.set(
            numColumns - 1,
            numRows - 1,
            true
        );

        matrix.set(
            numColumns - 2,
            numRows - 2,
            true
        );
    }

    return matrix;
}

void compareMatrices(
    const BitMatrix& actual,
    const BitMatrix& expected,
    const std::string& name)
{
    if (actual.width() != expected.width() ||
        actual.height() != expected.height())
    {
        throw std::runtime_error(
            "FAIL: " + name +
            " dimensions differ."
        );
    }

    for (int row = 0; row < actual.height(); ++row)
    {
        for (int column = 0;
             column < actual.width();
             ++column)
        {
            if (actual.get(column, row) !=
                expected.get(column, row))
            {
                std::cerr
                    << "FAIL: " << name
                    << " mismatch at "
                    << "row=" << row
                    << ", column=" << column
                    << "\n";

                throw std::runtime_error(
                    name + " matrix mismatch."
                );
            }
        }
    }

    std::cout << "PASS: " << name << "\n";
}

std::vector<std::uint8_t> makeTestCodewords(
    const DataMatrixSymbolInfo& symbolInfo)
{
    const int totalCodewords =
        symbolInfo.totalCodewords();

    std::vector<std::uint8_t> codewords;

    codewords.reserve(
        static_cast<std::size_t>(totalCodewords)
    );

    for (int i = 0; i < totalCodewords; ++i)
    {
        codewords.push_back(
            static_cast<std::uint8_t>(
                (i * 73 + 29) & 0xFF
            )
        );
    }

    return codewords;
}

void testProductionPlacementForSymbol(
    const int width,
    const int height)
{
    const DataMatrixSymbolInfo* symbolInfo =
        findDataMatrixSymbolInfo(
            width,
            height
        );

    requireTrue(
        symbolInfo != nullptr,
        "symbol info exists for " +
        std::to_string(width) +
        "x" +
        std::to_string(height)
    );

    const auto codewords =
        makeTestCodewords(*symbolInfo);

    const BitMatrix actual =
        DataMatrixEncoderTestAccess::placeCodewords(
            codewords,
            *symbolInfo
        );

    const BitMatrix expected =
        independentPlace(
            codewords,
            *symbolInfo
        );

    compareMatrices(
        actual,
        expected,
        "production placement " +
        std::to_string(width) +
        "x" +
        std::to_string(height)
    );
}

void testProductionRectangularPlacement()
{
    std::cout
        << "\n--- Production Rectangular Placement ---\n";

    const int rectangularSymbols[][2] =
    {
        {18, 8},
        {32, 8},
        {26, 12},
        {36, 12},
        {36, 16},
        {48, 16}
    };

    for (const auto& dimensions : rectangularSymbols)
    {
        const int width = dimensions[0];
        const int height = dimensions[1];

        std::cout
            << "\nTesting production placement "
            << width
            << "x"
            << height
            << "...\n";

        testProductionPlacementForSymbol(
            width,
            height
        );
    }
}

void testProductionMatrix()
{
    std::cout
        << "\n--- Production Matrix / Independent Oracle ---\n";

    struct Target
    {
        int width;
        int height;
        int textLength;
    };

    const Target targets[] =
    {
        {10, 10, 1},
        {12, 12, 4},
        {14, 14, 6},
        {16, 16, 9},
        {32, 32, 45}
    };

    for (const auto& target : targets)
    {
        std::cout
            << "\nTesting production encoder "
            << target.width
            << "x"
            << target.height
            << "...\n";

        std::string text(
            static_cast<std::size_t>(target.textLength),
            'A'
        );

        const auto encoded =
            DataMatrixEncoder::encode(text);

        requireTrue(
            encoded.matrix.width() == target.width &&
            encoded.matrix.height() == target.height,
            "production symbol size " +
            std::to_string(target.width) +
            "x" +
            std::to_string(target.height)
        );

        const auto independentData =
            independentPlace(
                encoded.codewords,
                encoded.symbolInfo
            );

        const auto independentComplete =
            DataMatrixEncoderTestAccess::buildSymbolMatrix(
                independentData,
                encoded.symbolInfo
            );

        compareMatrices(
            encoded.matrix,
            independentComplete,
            "production matrix " +
            std::to_string(target.width) +
            "x" +
            std::to_string(target.height) +
            " textLength=" +
            std::to_string(target.textLength)
        );
    }
}

}

int main()
{
    try
    {
        std::cout
            << "========================================\n"
            << " ECC200 ENCODER + PLACEMENT TEST\n"
            << "========================================\n";

        testIndependentReedSolomon();
        testEncoderGoldenVectors();
        testProductionMatrix();
        testProductionRectangularPlacement();

        std::cout
            << "\n========================================\n"
            << " ALL TESTS PASSED\n"
            << "========================================\n";

        return 0;
    }
    catch (const std::exception& exception)
    {
        std::cerr
            << "\nTEST FAILURE:\n"
            << exception.what()
            << "\n";

        return 1;
    }
}


