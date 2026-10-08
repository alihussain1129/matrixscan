#include "exalted/datamatrix_placement.h"

#include <stdexcept>

namespace exalted {

DataMatrixPlacement::DataMatrixPlacement(
    const BitMatrix& symbolMatrix,
    const DataMatrixSymbolInfo& symbolInfo)
    : symbolMatrix_(symbolMatrix),
      symbolInfo_(symbolInfo)
{
    if (symbolMatrix_.width() != symbolInfo_.symbolWidth ||
        symbolMatrix_.height() != symbolInfo_.symbolHeight)
    {
        throw std::invalid_argument(
            "Symbol matrix dimensions do not match Data Matrix symbol info."
        );
    }
}

BitMatrix DataMatrixPlacement::buildDataMatrix() const
{
    return buildMappingMatrix();
}

std::vector<std::uint8_t> DataMatrixPlacement::readCodewords() const
{
    const BitMatrix matrix = buildMappingMatrix();

    const int rows = matrix.height();
    const int columns = matrix.width();

    BitMatrix visited(columns, rows);

    const DataMatrixTraversal::ModuleReader reader =
        [&matrix, &visited, rows, columns](int row, int column)
        {
            DataMatrixPlacement::wrapCoordinates(
                row,
                column,
                rows,
                columns
            );

            visited.setTrue(column, row);

            return matrix.get(column, row);
        };

    std::vector<std::uint8_t> codewords;

    codewords.reserve(
        static_cast<std::size_t>(symbolInfo_.totalCodewords())
    );

    int row = 4;
    int column = 0;

    bool corner1Read = false;
    bool corner2Read = false;
    bool corner3Read = false;
    bool corner4Read = false;

    do
    {
        /*
         * ECC 200 special corner conditions.
         *
         * These conditions follow the decoder traversal,
         * not the encoder's placement conditions.
         */

        // Corner 1.
        if (row == rows &&
            column == 0 &&
            !corner1Read)
        {
            codewords.push_back(
                DataMatrixTraversal::readCorner1(
                    reader,
                    rows,
                    columns
                )
            );

            row -= 2;
            column += 2;

            corner1Read = true;
        }

        // Corner 2.
        else if (row == rows - 2 &&
                 column == 0 &&
                 (columns % 4) != 0 &&
                 !corner2Read)
        {
            codewords.push_back(
                DataMatrixTraversal::readCorner2(
                    reader,
                    rows,
                    columns
                )
            );

            row -= 2;
            column += 2;

            corner2Read = true;
        }

        // Corner 3.
        else if (row == rows + 4 &&
                 column == 2 &&
                 (columns % 8) == 0 &&
                 !corner3Read)
        {
            codewords.push_back(
                DataMatrixTraversal::readCorner3(
                    reader,
                    rows,
                    columns
                )
            );

            row -= 2;
            column += 2;

            corner3Read = true;
        }

        // Corner 4.
        else if (row == rows - 2 &&
                 column == 0 &&
                 (columns % 8) == 4 &&
                 !corner4Read)
        {
            codewords.push_back(
                DataMatrixTraversal::readCorner4(
                    reader,
                    rows,
                    columns
                )
            );

            row -= 2;
            column += 2;

            corner4Read = true;
        }

        else
        {
            // Upward diagonal.
            do
            {
                if (row < rows &&
                    column >= 0 &&
                    !visited.get(column, row))
                {
                    codewords.push_back(
                        DataMatrixTraversal::readUtah(
                            reader,
                            row,
                            column
                        )
                    );
                }

                row -= 2;
                column += 2;

            } while (row >= 0 && column < columns);

            row += 1;
            column += 3;

            // Downward diagonal.
            do
            {
                if (row >= 0 &&
                    row < rows &&
                    column >= 0 &&
                    column < columns &&
                    !visited.get(column, row))
                {
                    codewords.push_back(
                        DataMatrixTraversal::readUtah(
                            reader,
                            row,
                            column
                        )
                    );
                }

                row += 2;
                column -= 2;

            } while (row < rows && column >= 0);

            row += 3;
            column += 1;
        }

    } while (row < rows || column < columns);

    return codewords;
}

BitMatrix DataMatrixPlacement::buildMappingMatrix() const
{
    const int dataWidth = symbolInfo_.dataWidth();
    const int dataHeight = symbolInfo_.dataHeight();

    BitMatrix dataMatrix(dataWidth, dataHeight);

    const int regionWidth = symbolInfo_.dataRegionWidth;
    const int regionHeight = symbolInfo_.dataRegionHeight;

    for (int regionY = 0;
         regionY < symbolInfo_.regionsVertical;
         ++regionY)
    {
        for (int regionX = 0;
             regionX < symbolInfo_.regionsHorizontal;
             ++regionX)
        {
            const int symbolOriginX =
                regionX * (regionWidth + 2);

            const int symbolOriginY =
                regionY * (regionHeight + 2);

            const int dataOriginX =
                regionX * regionWidth;

            const int dataOriginY =
                regionY * regionHeight;

            for (int y = 0; y < regionHeight; ++y)
            {
                for (int x = 0; x < regionWidth; ++x)
                {
                    dataMatrix.set(
                        dataOriginX + x,
                        dataOriginY + y,
                        symbolMatrix_.get(
                            symbolOriginX + 1 + x,
                            symbolOriginY + 1 + y
                        )
                    );
                }
            }
        }
    }

    return dataMatrix;
}

void DataMatrixPlacement::wrapCoordinates(
    int& row,
    int& column,
    int numRows,
    int numColumns)
{
    /*
     * ECC 200 coupled coordinate wrapping.
     */
    if (row < 0)
    {
        row += numRows;
        column += 4 - ((numRows + 4) % 8);
    }

    if (column < 0)
    {
        column += numColumns;
        row += 4 - ((numColumns + 4) % 8);
    }

    /*
     * The decoder has one additional row normalization
     * after the two ECC 200 wrapping rules.
     */
    if (row >= numRows)
    {
        row -= numRows;
    }

    if (row < 0 ||
        row >= numRows ||
        column < 0 ||
        column >= numColumns)
    {
        throw std::out_of_range(
            "ECC200 placement coordinate is outside the data matrix."
        );
    }
}

} // namespace exalted


