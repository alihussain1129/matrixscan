#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "exalted/bit_matrix.h"
#include "exalted/datamatrix_symbol_info.h"

namespace exalted {

class DataMatrixEncoderTestAccess;

class DataMatrixEncoder
{
public:
    struct EncodedSymbol
    {
        DataMatrixSymbolInfo symbolInfo;
        std::vector<std::uint8_t> dataCodewords;
        std::vector<std::uint8_t> errorCorrectionCodewords;
        std::vector<std::uint8_t> codewords;
        BitMatrix matrix;
    };

    static EncodedSymbol encode(
        const std::string& text);

private:
    friend class DataMatrixEncoderTestAccess;

    static std::vector<std::uint8_t> encodeAscii(
        const std::string& text);

    static void padToCapacity(
        std::vector<std::uint8_t>& codewords,
        int capacity);

    static std::uint8_t randomize253State(
        std::uint8_t codeword,
        int position);

    static std::vector<std::uint8_t> generateErrorCorrection(
        const std::vector<std::uint8_t>& data,
        const DataMatrixSymbolInfo& symbolInfo);

    static BitMatrix placeCodewords(
        const std::vector<std::uint8_t>& codewords,
        const DataMatrixSymbolInfo& symbolInfo);

    static BitMatrix buildSymbolMatrix(
        const BitMatrix& dataMatrix,
        const DataMatrixSymbolInfo& symbolInfo);
};

class DataMatrixEncoderTestAccess
{
public:
    static BitMatrix placeCodewords(
        const std::vector<std::uint8_t>& codewords,
        const DataMatrixSymbolInfo& symbolInfo)
    {
        return DataMatrixEncoder::placeCodewords(
            codewords,
            symbolInfo
        );
    }

    static BitMatrix buildSymbolMatrix(
        const BitMatrix& dataMatrix,
        const DataMatrixSymbolInfo& symbolInfo)
    {
        return DataMatrixEncoder::buildSymbolMatrix(
            dataMatrix,
            symbolInfo
        );
    }
};

} // namespace exalted
