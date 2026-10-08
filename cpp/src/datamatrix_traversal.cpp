#include "exalted/datamatrix_traversal.h"

namespace exalted {

namespace {

std::uint8_t readPattern(
    const DataMatrixTraversal::ModuleReader& reader,
    const int coordinates[][2],
    int count)
{
    std::uint8_t value = 0;

    for (int i = 0; i < count; ++i)
    {
        value <<= 1;

        if (reader(
                coordinates[i][0],
                coordinates[i][1]))
        {
            value |= 1;
        }
    }

    return value;
}

} // namespace

std::uint8_t DataMatrixTraversal::readUtah(
    const BitMatrix& matrix,
    int row,
    int column)
{
    return readUtah(
        ModuleReader(
            [&matrix](int r, int c)
            {
                return matrix.get(c, r);
            }),
        row,
        column);
}

std::uint8_t DataMatrixTraversal::readCorner1(
    const BitMatrix& matrix,
    int row,
    int column)
{
    return readCorner1(
        ModuleReader(
            [&matrix](int r, int c)
            {
                return matrix.get(c, r);
            }),
        row,
        column);
}

std::uint8_t DataMatrixTraversal::readCorner2(
    const BitMatrix& matrix,
    int row,
    int column)
{
    return readCorner2(
        ModuleReader(
            [&matrix](int r, int c)
            {
                return matrix.get(c, r);
            }),
        row,
        column);
}

std::uint8_t DataMatrixTraversal::readCorner3(
    const BitMatrix& matrix,
    int row,
    int column)
{
    return readCorner3(
        ModuleReader(
            [&matrix](int r, int c)
            {
                return matrix.get(c, r);
            }),
        row,
        column);
}

std::uint8_t DataMatrixTraversal::readCorner4(
    const BitMatrix& matrix,
    int row,
    int numCols)
{
    return readCorner4(
        ModuleReader(
            [&matrix](int r, int c)
            {
                return matrix.get(c, r);
            }),
        row,
        numCols);
}

std::uint8_t DataMatrixTraversal::readUtah(
    const ModuleReader& reader,
    int row,
    int column)
{
    const int coordinates[8][2] =
    {
        {row - 2, column - 2},
        {row - 2, column - 1},
        {row - 1, column - 2},
        {row - 1, column - 1},
        {row - 1, column},
        {row,     column - 2},
        {row,     column - 1},
        {row,     column}
    };

    return readPattern(reader, coordinates, 8);
}

std::uint8_t DataMatrixTraversal::readCorner1(
    const ModuleReader& reader,
    int numRows,
    int numColumns)
{
    const int coordinates[8][2] =
    {
        {numRows - 1, 0},
        {numRows - 1, 1},
        {numRows - 1, 2},
        {0,           numColumns - 2},
        {0,           numColumns - 1},
        {1,           numColumns - 1},
        {2,           numColumns - 1},
        {3,           numColumns - 1}
    };

    return readPattern(reader, coordinates, 8);
}

std::uint8_t DataMatrixTraversal::readCorner2(
    const ModuleReader& reader,
    int numRows,
    int numColumns)
{
    const int coordinates[8][2] =
    {
        {numRows - 3, 0},
        {numRows - 2, 0},
        {numRows - 1, 0},
        {0,           numColumns - 4},
        {0,           numColumns - 3},
        {0,           numColumns - 2},
        {0,           numColumns - 1},
        {1,           numColumns - 1}
    };

    return readPattern(reader, coordinates, 8);
}

std::uint8_t DataMatrixTraversal::readCorner3(
    const ModuleReader& reader,
    int numRows,
    int numColumns)
{
    const int coordinates[8][2] =
    {
        {numRows - 1, 0},
        {numRows - 1, numColumns - 1},
        {0,           numColumns - 3},
        {0,           numColumns - 2},
        {0,           numColumns - 1},
        {1,           numColumns - 3},
        {1,           numColumns - 2},
        {1,           numColumns - 1}
    };

    return readPattern(reader, coordinates, 8);
}

std::uint8_t DataMatrixTraversal::readCorner4(
    const ModuleReader& reader,
    int numRows,
    int numColumns)
{
    const int coordinates[8][2] =
    {
        {numRows - 3, 0},
        {numRows - 2, 0},
        {numRows - 1, 0},
        {0,           numColumns - 2},
        {0,           numColumns - 1},
        {1,           numColumns - 1},
        {2,           numColumns - 1},
        {3,           numColumns - 1}
    };

    return readPattern(reader, coordinates, 8);
}

} // namespace exalted
