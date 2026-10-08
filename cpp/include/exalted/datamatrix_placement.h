#pragma once

#include <cstdint>
#include <vector>

#include "exalted/bit_matrix.h"
#include "exalted/datamatrix_symbol_info.h"
#include "exalted/datamatrix_traversal.h"

namespace exalted {

class DataMatrixPlacement
{
public:
    DataMatrixPlacement(
        const BitMatrix& symbolMatrix,
        const DataMatrixSymbolInfo& symbolInfo);

    // Extracts the data modules from the complete ECC 200 symbol
    // and returns them as a compact data-only matrix.
    BitMatrix buildDataMatrix() const;

    // Reads all data-region modules in ECC 200 codeword order.
    std::vector<std::uint8_t> readCodewords() const;

private:
    const BitMatrix& symbolMatrix_;
    const DataMatrixSymbolInfo& symbolInfo_;

    BitMatrix buildMappingMatrix() const;

    static void wrapCoordinates(
        int& row,
        int& column,
        int numRows,
        int numColumns);
};

} // namespace exalted
