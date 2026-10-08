#include <cstdint>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "exalted/bit_matrix.h"
#include "exalted/datamatrix_placement.h"
#include "exalted/datamatrix_symbol_info.h"

using exalted::BitMatrix;
using exalted::DataMatrixPlacement;
using exalted::DataMatrixSymbolInfo;
using exalted::findDataMatrixSymbolInfo;

namespace
{

void require(bool condition, const std::string& message)
{
    if (!condition)
        throw std::runtime_error(message);
}

void placeModule(
    BitMatrix& matrix,
    BitMatrix& visited,
    int row,
    int column,
    std::uint8_t codeword,
    int bit)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    if (row < 0)
    {
        row += rows;
        column += 4 - ((rows + 4) % 8);
    }

    if (column < 0)
    {
        column += columns;
        row += 4 - ((columns + 4) % 8);
    }

    require(
        row >= 0 && row < rows &&
        column >= 0 && column < columns,
        "Independent placement produced invalid coordinates."
    );

    /*
     * A module may belong to a previously placed codeword,
     * especially around the special ECC200 corner patterns.
     *
     * Once a module has been visited, it must never be
     * overwritten by a later Utah/corner operation.
     */
    if (visited.get(column, row))
    {
        return;
    }

    const bool value =
        ((codeword >> bit) & 1U) != 0;

    matrix.set(column, row, value);
    visited.setTrue(column, row);
}

void placeUtah(
    BitMatrix& matrix,
    BitMatrix& visited,
    int row,
    int column,
    std::uint8_t codeword)
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
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    placeModule(matrix, visited, rows - 1, 0,             codeword, 7);
    placeModule(matrix, visited, rows - 1, 1,             codeword, 6);
    placeModule(matrix, visited, rows - 1, 2,             codeword, 5);
    placeModule(matrix, visited, 0, columns - 2,          codeword, 4);
    placeModule(matrix, visited, 0, columns - 1,          codeword, 3);
    placeModule(matrix, visited, 1, columns - 1,          codeword, 2);
    placeModule(matrix, visited, 2, columns - 1,          codeword, 1);
    placeModule(matrix, visited, 3, columns - 1,          codeword, 0);
}

void placeCorner2(
    BitMatrix& matrix,
    BitMatrix& visited,
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    placeModule(matrix, visited, rows - 3, 0,             codeword, 7);
    placeModule(matrix, visited, rows - 2, 0,             codeword, 6);
    placeModule(matrix, visited, rows - 1, 0,             codeword, 5);
    placeModule(matrix, visited, 0, columns - 4,          codeword, 4);
    placeModule(matrix, visited, 0, columns - 3,          codeword, 3);
    placeModule(matrix, visited, 0, columns - 2,          codeword, 2);
    placeModule(matrix, visited, 0, columns - 1,          codeword, 1);
    placeModule(matrix, visited, 1, columns - 1,          codeword, 0);
}

void placeCorner3(
    BitMatrix& matrix,
    BitMatrix& visited,
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    placeModule(matrix, visited, rows - 1, 0,             codeword, 7);
    placeModule(matrix, visited, rows - 1, columns - 1,   codeword, 6);
    placeModule(matrix, visited, 0, columns - 3,          codeword, 5);
    placeModule(matrix, visited, 0, columns - 2,          codeword, 4);
    placeModule(matrix, visited, 0, columns - 1,          codeword, 3);
    placeModule(matrix, visited, 1, columns - 3,          codeword, 2);
    placeModule(matrix, visited, 1, columns - 2,          codeword, 1);
    placeModule(matrix, visited, 1, columns - 1,          codeword, 0);
}

void placeCorner4(
    BitMatrix& matrix,
    BitMatrix& visited,
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    placeModule(matrix, visited, rows - 3, 0,             codeword, 7);
    placeModule(matrix, visited, rows - 2, 0,             codeword, 6);
    placeModule(matrix, visited, rows - 1, 0,             codeword, 5);
    placeModule(matrix, visited, 0, columns - 2,          codeword, 4);
    placeModule(matrix, visited, 0, columns - 1,          codeword, 3);
    placeModule(matrix, visited, 1, columns - 1,          codeword, 2);
    placeModule(matrix, visited, 2, columns - 1,          codeword, 1);
    placeModule(matrix, visited, 3, columns - 1,          codeword, 0);
}

BitMatrix independentPlace(
    const std::vector<std::uint8_t>& codewords,
    int rows,
    int columns)
{
    BitMatrix matrix(columns, rows);
    BitMatrix visited(columns, rows);

    int row = 4;
    int column = 0;
    std::size_t codewordIndex = 0;

    const auto nextCodeword = [&]()
    {
        require(
            codewordIndex < codewords.size(),
            "Independent placement ran out of codewords."
        );

        return codewords[codewordIndex++];
    };

    do
    {
        if (row == rows && column == 0)
        {
            placeCorner1(
                matrix,
                visited,
                nextCodeword()
            );
        }

        if (row == rows - 2 &&
            column == 0 &&
            (columns % 4) != 0)
        {
            placeCorner2(
                matrix,
                visited,
                nextCodeword()
            );
        }

        if (row == rows + 4 &&
            column == 2 &&
            (columns % 8) == 0)
        {
            placeCorner3(
                matrix,
                visited,
                nextCodeword()
            );
        }

        if (row == rows - 2 &&
            column == 0 &&
            (columns % 8) == 4)
        {
            placeCorner4(
                matrix,
                visited,
                nextCodeword()
            );
        }

        /*
         * Upward diagonal.
         */
        do
        {
            if (row < rows &&
                column >= 0 &&
                !visited.get(column, row))
            {
                placeUtah(
                    matrix,
                    visited,
                    row,
                    column,
                    nextCodeword()
                );
            }

            row -= 2;
            column += 2;

        } while (row >= 0 && column < columns);

        row += 1;
        column += 3;

        /*
         * Downward diagonal.
         */
        do
        {
            if (row >= 0 &&
                row < rows &&
                column >= 0 &&
                column < columns &&
                !visited.get(column, row))
            {
                placeUtah(
                    matrix,
                    visited,
                    row,
                    column,
                    nextCodeword()
                );
            }

            row += 2;
            column -= 2;

        } while (row < rows && column >= 0);

        row += 3;
        column += 1;

    } while (row < rows || column < columns);

    require(
        codewordIndex == codewords.size(),
        "Independent placement did not consume exactly all codewords."
    );

    return matrix;
}

std::vector<std::uint8_t> makeCodewords(
    const DataMatrixSymbolInfo& info)
{
    std::vector<std::uint8_t> result(
        static_cast<std::size_t>(info.totalCodewords())
    );

    for (std::size_t i = 0; i < result.size(); ++i)
    {
        result[i] =
            static_cast<std::uint8_t>(
                (
                    0x31U +
                    static_cast<unsigned int>(i * 37U) +
                    static_cast<unsigned int>((i % 7U) * 11U)
                ) & 0xFFU
            );
    }

    return result;
}

BitMatrix createCompleteSymbol(
    const DataMatrixSymbolInfo& info,
    const BitMatrix& mapping)
{
    BitMatrix symbol(
        info.symbolWidth,
        info.symbolHeight
    );

    const int regionWidth = info.dataRegionWidth;
    const int regionHeight = info.dataRegionHeight;

    for (int regionY = 0;
         regionY < info.regionsVertical;
         ++regionY)
    {
        for (int regionX = 0;
             regionX < info.regionsHorizontal;
             ++regionX)
        {
            const int originX =
                regionX * (regionWidth + 2);

            const int originY =
                regionY * (regionHeight + 2);

            /*
             * Top border:
             * alternating black/white modules.
             */
            for (int x = 0;
                 x < regionWidth + 2;
                 ++x)
            {
                symbol.set(
                    originX + x,
                    originY,
                    (x % 2) == 0
                );
            }

            /*
             * Bottom border:
             * solid black.
             */
            for (int x = 0;
                 x < regionWidth + 2;
                 ++x)
            {
                symbol.set(
                    originX + x,
                    originY + regionHeight + 1,
                    true
                );
            }

            /*
             * Left border:
             * solid black.
             */
            for (int y = 0;
                 y < regionHeight + 2;
                 ++y)
            {
                symbol.set(
                    originX,
                    originY + y,
                    true
                );
            }

            /*
             * Right border:
             * alternating black/white modules.
             */
            for (int y = 0;
                 y < regionHeight + 2;
                 ++y)
            {
                symbol.set(
                    originX + regionWidth + 1,
                    originY + y,
                    (y % 2) == 0
                );
            }

            /*
             * Copy data modules into this region.
             */
            const int dataOriginX =
                regionX * regionWidth;

            const int dataOriginY =
                regionY * regionHeight;

            for (int y = 0;
                 y < regionHeight;
                 ++y)
            {
                for (int x = 0;
                     x < regionWidth;
                     ++x)
                {
                    symbol.set(
                        originX + 1 + x,
                        originY + 1 + y,
                        mapping.get(
                            dataOriginX + x,
                            dataOriginY + y
                        )
                    );
                }
            }
        }
    }

    return symbol;
}

void printCodewords(
    const std::vector<std::uint8_t>& values,
    const std::string& label)
{
    std::cout << label << ":\n";

    for (std::size_t i = 0;
         i < values.size();
         ++i)
    {
        std::cout
            << "  ["
            << i
            << "] 0x"
            << std::hex
            << std::uppercase
            << std::setw(2)
            << std::setfill('0')
            << static_cast<int>(values[i])
            << std::dec
            << '\n';
    }
}

void testSymbol(
    int symbolWidth,
    int symbolHeight)
{
    std::cout
        << "\n--- Testing "
        << symbolWidth
        << "x"
        << symbolHeight
        << " ---\n";

    const DataMatrixSymbolInfo* info =
        findDataMatrixSymbolInfo(
            symbolWidth,
            symbolHeight
        );

    require(
        info != nullptr,
        "Symbol information not found."
    );

    std::cout
        << "Data area: "
        << info->dataWidth()
        << "x"
        << info->dataHeight()
        << '\n';

    std::cout
        << "Expected codewords: "
        << info->totalCodewords()
        << '\n';

    const std::vector<std::uint8_t> expected =
        makeCodewords(*info);

    BitMatrix mapping =
        independentPlace(
            expected,
            info->dataHeight(),
            info->dataWidth()
        );

    std::cout
        << "Independent placement: PASS\n";

    /*
     * Do not modify the independently generated mapping here.
     *
     * The round-trip test must preserve the exact codeword
     * placement so that:
     *
     *     codewords -> placement -> symbol -> reader
     *
     * can be compared losslessly.
     *
     * The ECC200 fixed-module behavior is tested separately.
     */
    std::cout
        << "Final fixed pattern: not injected into round-trip mapping\n";

    const BitMatrix symbol =
        createCompleteSymbol(
            *info,
            mapping
        );

    std::cout
        << "Complete symbol construction: PASS\n";

    DataMatrixPlacement placement(
        symbol,
        *info
    );

    const BitMatrix productionMapping =
        placement.buildDataMatrix();

    std::cout << "\nMapping differences:\n";
    for (int y = 0; y < info->dataHeight(); ++y)
    {
        for (int x = 0; x < info->dataWidth(); ++x)
        {
            if (mapping.get(x, y) != productionMapping.get(x, y))
            {
                std::cout
                    << "  (" << x << "," << y << ")"
                    << " expected=" << mapping.get(x, y)
                    << " actual=" << productionMapping.get(x, y)
                    << "\n";
            }
        }
    }

    std::cout
        << "\nCorner 1 production mapping bits:\n";

    const int diagnosticRows =
        productionMapping.height();

    const int diagnosticColumns =
        productionMapping.width();

    const int diagnosticCoordinates[][2] =
    {
        {7, 0},
        {7, 1},
        {7, 2},
        {0, 6},
        {0, 7},
        {1, 7},
        {2, 7},
        {3, 7}
    };

    for (const auto& coordinate : diagnosticCoordinates)
    {
        const int row = coordinate[0];
        const int column = coordinate[1];

        if (row >= 0 &&
            row < diagnosticRows &&
            column >= 0 &&
            column < diagnosticColumns)
        {
            std::cout
                << "  ("
                << row
                << ","
                << column
                << ") = "
                << productionMapping.get(column, row)
                << '\n';
        }
        else
        {
            std::cout
                << "  ("
                << row
                << ","
                << column
                << ") = OUT OF RANGE\n";
        }
    }

    const std::vector<std::uint8_t> actual =
        placement.readCodewords();

    std::cout
        << "Actual codewords:   "
        << actual.size()
        << '\n';

    require(
        actual.size() ==
            static_cast<std::size_t>(
                info->totalCodewords()
            ),
        "Production reader returned incorrect codeword count."
    );

    for (std::size_t i = 0;
         i < expected.size();
         ++i)
    {
        if (expected[i] != actual[i])
        {
            std::cout
                << "\nFIRST MISMATCH\n"
                << "Index:    "
                << i
                << '\n'
                << "Expected: 0x"
                << std::hex
                << std::uppercase
                << std::setw(2)
                << std::setfill('0')
                << static_cast<int>(expected[i])
                << '\n'
                << "Actual:   0x"
                << std::setw(2)
                << static_cast<int>(actual[i])
                << std::dec
                << "\n\n";

            printCodewords(
                expected,
                "Expected"
            );

            printCodewords(
                actual,
                "Actual"
            );

            throw std::runtime_error(
                "Production reader returned incorrect codewords."
            );
        }
    }

    std::cout
        << "Codeword round-trip: PASS\n";
}

} // namespace

int main()
{
    try
    {
        std::cout
            << "========================================\n"
            << " ECC200 Placement Diagnostic TEST\n"
            << "========================================\n";

        testSymbol(10, 10);

        std::cout
            << "\n========================================\n"
            << " FIRST SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(12, 12);

        std::cout
            << "\n========================================\n"
            << " SECOND SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(14, 14);

        std::cout
            << "\n========================================\n"
            << " THIRD SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(16, 16);

        std::cout
            << "\n========================================\n"
            << " FOURTH SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(32, 32);

        std::cout
            << "\n========================================\n"
            << " MULTI-REGION SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(18, 8);

        std::cout
            << "\n========================================\n"
            << " 18x8 RECTANGULAR SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(32, 8);

        std::cout
            << "\n========================================\n"
            << " 32x8 RECTANGULAR SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(26, 12);

        std::cout
            << "\n========================================\n"
            << " 26x12 RECTANGULAR SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(36, 12);

        std::cout
            << "\n========================================\n"
            << " 36x12 RECTANGULAR SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(36, 16);

        std::cout
            << "\n========================================\n"
            << " 36x16 RECTANGULAR SYMBOL PASSED\n"
            << "========================================\n";

        testSymbol(48, 16);

        std::cout
            << "\n========================================\n"
            << " 48x16 RECTANGULAR SYMBOL PASSED\n"
            << "========================================\n";

        return 0;
    }
    catch (const std::exception& ex)
    {
        std::cerr
            << "\nTEST FAILED: "
            << ex.what()
            << '\n';

        return 1;
    }
}













