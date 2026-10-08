#include "exalted/datamatrix_encoder.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace exalted {

namespace {

constexpr int kModuloValue = 0x12D;

class GaloisField256
{
public:
    GaloisField256()
    {
        int value = 1;

        for (int i = 0; i < 255; ++i)
        {
            alog_[i] = value;
            log_[value] = i;

            value <<= 1;

            if (value >= 256)
            {
                value ^= kModuloValue;
            }
        }
    }

    int log(int value) const
    {
        if (value <= 0 || value >= 256)
        {
            throw std::invalid_argument(
                "GF(256) logarithm input must be in range 1..255."
            );
        }

        return log_[value];
    }

    std::uint8_t exp(int value) const
    {
        value %= 255;

        if (value < 0)
        {
            value += 255;
        }

        return static_cast<std::uint8_t>(alog_[value]);
    }

private:
    std::array<int, 256> log_{};
    std::array<int, 255> alog_{};
};

const GaloisField256& field()
{
    static const GaloisField256 instance;
    return instance;
}

constexpr int kFactorSets[] =
{
    5, 7, 10, 11, 12,
    14, 15, 18, 20, 22,
    24, 27, 28, 32, 34,
    36, 38, 41, 42, 46,
    48, 50, 56, 62, 68
};

const std::array<std::vector<int>, 25> kFactors =
{
    std::vector<int>{228, 48, 15, 111, 62},

    std::vector<int>{23, 68, 144, 134, 240, 92, 254},

    std::vector<int>{28, 24, 185, 166, 223, 248, 116, 255, 110, 61},

    std::vector<int>{175, 138, 205, 12, 194, 168, 39, 245, 60, 97, 120},

    std::vector<int>{41, 153, 158, 91, 61, 42, 142, 213, 97, 178, 100, 242},

    std::vector<int>{
        156, 97, 192, 252, 95, 9, 157,
        119, 138, 45, 18, 186, 83, 185
    },

    std::vector<int>{
        116, 88, 33, 148, 201, 88, 153,
        176, 234, 145, 35, 159, 139, 223, 93
    },

    std::vector<int>{
        83, 195, 100, 39, 188, 75, 66, 61,
        241, 213, 109, 129, 94, 254, 225,
        48, 90, 188
    },

    std::vector<int>{
        15, 195, 244, 9, 233, 71, 168, 2,
        188, 160, 153, 145, 253, 79, 108,
        82, 27, 174, 186, 172
    },

    std::vector<int>{
        75, 249, 76, 201, 95, 241, 5, 123,
        71, 94, 27, 132, 1, 152, 38, 10,
        125, 217, 209, 3, 188, 236
    },

    std::vector<int>{
        52, 190, 88, 205, 109, 39, 176, 21,
        155, 197, 251, 223, 155, 21, 5, 172,
        254, 124, 12, 181, 184, 96, 50, 193
    },

    std::vector<int>{
        215, 183, 130, 96, 182, 147, 97, 74,
        143, 205, 47, 229, 29, 123, 55, 65,
        244, 246, 210, 108, 72, 134, 233, 246,
        161, 180, 232
    },

    std::vector<int>{
        211, 231, 43, 97, 71, 96, 103, 174,
        37, 151, 170, 53, 75, 34, 249, 121,
        17, 138, 110, 213, 141, 136, 120, 151,
        233, 168, 93, 255
    },

    std::vector<int>{
        227, 184, 159, 130, 228, 199, 107, 95,
        236, 21, 61, 58, 209, 120, 2, 38,
        211, 202, 103, 19, 104, 145, 2, 249,
        174, 144, 95, 55, 234, 163, 129, 104
    },

    std::vector<int>{
        190, 197, 231, 218, 210, 172, 71, 234,
        203, 95, 42, 103, 237, 116, 90, 95,
        143, 6, 189, 114, 107, 62, 154, 62,
        152, 237, 138, 89, 14, 67, 189, 179,
        4, 139
    },

    std::vector<int>{
        245, 127, 242, 218, 130, 250, 162, 181,
        102, 120, 84, 179, 220, 251, 80, 182,
        229, 18, 2, 4, 68, 33, 101, 137,
        95, 119, 115, 44, 175, 184, 59, 25,
        225, 98, 81, 112
    },

    std::vector<int>{
        109, 30, 101, 141, 239, 222, 166, 90,
        102, 168, 237, 74, 233, 143, 123, 203,
        41, 172, 103, 139, 211, 55, 183, 83,
        215, 122, 223, 170, 134, 80, 128, 220,
        169, 166, 241, 165, 181, 235
    },

    std::vector<int>{
        35, 21, 123, 106, 43, 2, 142, 6,
        222, 194, 48, 53, 99, 216, 193, 172,
        136, 101, 120, 156, 250, 137, 144, 84,
        165, 90, 211, 208, 132, 133, 15, 224,
        244, 79, 71, 81, 38, 68, 249, 220, 149
    },

    std::vector<int>{
        77, 193, 137, 31, 19, 38, 22, 153,
        247, 105, 122, 2, 245, 133, 242, 8,
        175, 95, 100, 9, 167, 105, 214, 111,
        57, 121, 21, 1, 253, 57, 54, 101,
        248, 202, 69, 50, 150, 177, 226, 5,
        9, 5
    },

    std::vector<int>{
        195, 29, 197, 200, 113, 135, 114, 178,
        160, 232, 186, 35, 129, 111, 51, 47,
        61, 11, 29, 135, 171, 83, 221, 33,
        206, 130, 127, 47, 77, 21, 43, 72,
        138, 173, 118, 144, 98, 40, 178, 141,
        62, 114, 235, 74, 62, 78
    },

    std::vector<int>{
        245, 132, 172, 223, 96, 32, 117, 22,
        238, 133, 238, 231, 205, 188, 237, 87,
        191, 106, 16, 147, 118, 23, 37, 90,
        170, 205, 131, 88, 120, 100, 66, 138,
        186, 240, 82, 44, 176, 87, 187, 147,
        160, 175, 69, 213, 92, 253, 225, 19
    },

    std::vector<int>{
        1, 166, 254, 165, 43, 167, 102, 150,
        123, 245, 74, 222, 223, 36, 230, 112,
        16, 9, 142, 14, 241, 251, 114, 65,
        156, 205, 14, 80, 76, 243, 241, 8,
        185, 25, 28, 112, 231, 79, 153, 16,
        74, 156, 183, 212, 218, 167, 91, 162,
        54, 74
    },

    std::vector<int>{
        175, 9, 223, 238, 12, 17, 220, 208,
        100, 29, 175, 170, 230, 192, 215, 235,
        150, 159, 36, 223, 38, 200, 132, 54,
        228, 146, 218, 234, 117, 203, 29, 232,
        144, 238, 22, 150, 201, 117, 62, 207,
        164, 13, 137, 245, 127, 67, 247, 28,
        155, 43, 203, 107, 233, 53, 143, 46
    },

    std::vector<int>{
        242, 93, 169, 50, 144, 210, 39, 118,
        202, 188, 201, 189, 143, 108, 196, 37,
        185, 112, 134, 230, 245, 63, 197, 190,
        250, 106, 185, 221, 175, 64, 114, 71,
        161, 44, 147, 6, 27, 218, 51, 63,
        87, 10, 40, 130, 188, 17, 163, 31,
        176, 170, 4, 107, 232, 7, 94, 166,
        224, 124, 86, 47, 11, 204
    },

    std::vector<int>{
        220, 228, 173, 89, 251, 149, 159, 56,
        89, 33, 147, 244, 154, 36, 73, 127,
        213, 136, 248, 180, 234, 197, 158, 177,
        68, 122, 93, 213, 15, 160, 227, 236,
        66, 139, 153, 185, 202, 167, 179, 25,
        220, 232, 96, 210, 231, 136, 223, 239,
        181, 241, 59, 52, 172, 25, 49, 232,
        211, 189, 64, 54, 108, 153, 132, 63,
        96, 103, 82, 186
    }
};

int factorSetIndex(int errorCorrectionCodewords)
{
    for (int i = 0; i < 25; ++i)
    {
        if (kFactorSets[i] == errorCorrectionCodewords)
        {
            return i;
        }
    }

    throw std::invalid_argument(
        "Unsupported ECC200 error correction codeword count."
    );
}

std::vector<std::uint8_t> createECCBlock(
    const std::vector<std::uint8_t>& data,
    int errorCorrectionCodewords)
{
    const int factorIndex =
        factorSetIndex(errorCorrectionCodewords);

    const std::vector<int>& factors =
        kFactors[static_cast<std::size_t>(factorIndex)];

    std::vector<std::uint8_t> ecc(
        static_cast<std::size_t>(errorCorrectionCodewords),
        0
    );

    const GaloisField256& gf = field();

    for (std::uint8_t codeword : data)
    {
        const int message =
            ecc.back() ^ codeword;

        for (int k = errorCorrectionCodewords - 1;
             k > 0;
             --k)
        {
            if (message != 0 &&
                factors[static_cast<std::size_t>(k)] != 0)
            {
                ecc[static_cast<std::size_t>(k)] =
                    static_cast<std::uint8_t>(
                        ecc[static_cast<std::size_t>(k - 1)] ^
                        gf.exp(
                            gf.log(message) +
                            gf.log(
                                factors[
                                    static_cast<std::size_t>(k)
                                ]
                            )
                        )
                    );
            }
            else
            {
                ecc[static_cast<std::size_t>(k)] =
                    ecc[static_cast<std::size_t>(k - 1)];
            }
        }

        if (message != 0 &&
            factors[0] != 0)
        {
            ecc[0] =
                gf.exp(
                    gf.log(message) +
                    gf.log(factors[0])
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

void writeCodeword(
    BitMatrix& matrix,
    BitMatrix& visited,
    int& row,
    int& column,
    std::uint8_t codeword)
{
    int currentRow = row;
    int currentColumn = column;

    auto wrapCoordinates =
        [](int& r, int& c, int rows, int columns)
        {
            if (r < 0)
            {
                r += rows;
                c += 4 - ((rows + 4) % 8);
            }

            if (c < 0)
            {
                c += columns;
                r += 4 - ((columns + 4) % 8);
            }

            if (r >= rows)
            {
                r -= rows;
            }

            if (r < 0 ||
                r >= rows ||
                c < 0 ||
                c >= columns)
            {
                throw std::out_of_range(
                    "ECC200 placement coordinate is outside data matrix."
                );
            }
        };

    auto setBit =
        [&](int r, int c, int bit)
        {
            wrapCoordinates(
                r,
                c,
                matrix.height(),
                matrix.width()
            );

            matrix.set(
                c,
                r,
                ((codeword >> bit) & 1U) != 0
            );

            visited.setTrue(c, r);
        };

    setBit(currentRow - 2, currentColumn - 2, 7);
    setBit(currentRow - 2, currentColumn - 1, 6);
    setBit(currentRow - 1, currentColumn - 2, 5);
    setBit(currentRow - 1, currentColumn - 1, 4);
    setBit(currentRow - 1, currentColumn,     3);
    setBit(currentRow,     currentColumn - 2, 2);
    setBit(currentRow,     currentColumn - 1, 1);
    setBit(currentRow,     currentColumn,     0);
}

void writeCorner1(
    BitMatrix& matrix,
    BitMatrix& visited,
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    auto setBit =
        [&](int row, int column, int bit)
        {
            matrix.set(
                column,
                row,
                ((codeword >> bit) & 1U) != 0
            );

            visited.setTrue(column, row);
        };

    setBit(rows - 1, 0, 7);
    setBit(rows - 1, 1, 6);
    setBit(rows - 1, 2, 5);
    setBit(0, columns - 2, 4);
    setBit(0, columns - 1, 3);
    setBit(1, columns - 1, 2);
    setBit(2, columns - 1, 1);
    setBit(3, columns - 1, 0);
}

void writeCorner2(
    BitMatrix& matrix,
    BitMatrix& visited,
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    auto setBit =
        [&](int row, int column, int bit)
        {
            matrix.set(
                column,
                row,
                ((codeword >> bit) & 1U) != 0
            );

            visited.setTrue(column, row);
        };

    setBit(rows - 3, 0, 7);
    setBit(rows - 2, 0, 6);
    setBit(rows - 1, 0, 5);
    setBit(0, columns - 4, 4);
    setBit(0, columns - 3, 3);
    setBit(0, columns - 2, 2);
    setBit(0, columns - 1, 1);
    setBit(1, columns - 1, 0);
}

void writeCorner3(
    BitMatrix& matrix,
    BitMatrix& visited,
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    auto setBit =
        [&](int row, int column, int bit)
        {
            matrix.set(
                column,
                row,
                ((codeword >> bit) & 1U) != 0
            );

            visited.setTrue(column, row);
        };

    setBit(rows - 1, 0, 7);
    setBit(rows - 1, columns - 1, 6);
    setBit(0, columns - 3, 5);
    setBit(0, columns - 2, 4);
    setBit(0, columns - 1, 3);
    setBit(1, columns - 3, 2);
    setBit(1, columns - 2, 1);
    setBit(1, columns - 1, 0);
}

void writeCorner4(
    BitMatrix& matrix,
    BitMatrix& visited,
    std::uint8_t codeword)
{
    const int rows = matrix.height();
    const int columns = matrix.width();

    auto setBit =
        [&](int row, int column, int bit)
        {
            matrix.set(
                column,
                row,
                ((codeword >> bit) & 1U) != 0
            );

            visited.setTrue(column, row);
        };

    setBit(rows - 3, 0, 7);
    setBit(rows - 2, 0, 6);
    setBit(rows - 1, 0, 5);
    setBit(0, columns - 2, 4);
    setBit(0, columns - 1, 3);
    setBit(1, columns - 1, 2);
    setBit(2, columns - 1, 1);
    setBit(3, columns - 1, 0);
}

} // namespace

DataMatrixEncoder::EncodedSymbol DataMatrixEncoder::encode(
    const std::string& text)
{
    std::vector<std::uint8_t> dataCodewords =
        encodeAscii(text);

    const DataMatrixSymbolInfo* symbolInfo = nullptr;

    for (int i = 0; i < 200; ++i)
    {
        const int size = i + 10;

        const DataMatrixSymbolInfo* candidate =
            findDataMatrixSymbolInfo(size, size);

        if (candidate != nullptr &&
            static_cast<int>(dataCodewords.size()) <=
                candidate->dataCodewords)
        {
            symbolInfo = candidate;
            break;
        }
    }

    if (symbolInfo == nullptr)
    {
        const int rectangularSizes[][2] =
        {
            {18, 8},
            {32, 8},
            {26, 12},
            {36, 12},
            {36, 16},
            {48, 16}
        };

        for (const auto& size : rectangularSizes)
        {
            const DataMatrixSymbolInfo* candidate =
                findDataMatrixSymbolInfo(
                    size[0],
                    size[1]
                );

            if (candidate != nullptr &&
                static_cast<int>(dataCodewords.size()) <=
                    candidate->dataCodewords)
            {
                symbolInfo = candidate;
                break;
            }
        }
    }

    if (symbolInfo == nullptr)
    {
        throw std::invalid_argument(
            "Input is too large for the currently supported "
            "Data Matrix symbol sizes."
        );
    }

    padToCapacity(
        dataCodewords,
        symbolInfo->dataCodewords
    );

    std::vector<std::uint8_t> errorCorrectionCodewords =
        generateErrorCorrection(
            dataCodewords,
            *symbolInfo
        );

    std::vector<std::uint8_t> codewords =
        dataCodewords;

    codewords.insert(
        codewords.end(),
        errorCorrectionCodewords.begin(),
        errorCorrectionCodewords.end()
    );

    const BitMatrix dataMatrix =
        placeCodewords(
            codewords,
            *symbolInfo
        );

    const BitMatrix symbolMatrix =
        buildSymbolMatrix(
            dataMatrix,
            *symbolInfo
        );

    EncodedSymbol result;

    result.symbolInfo = *symbolInfo;
    result.dataCodewords = std::move(dataCodewords);
    result.errorCorrectionCodewords =
        std::move(errorCorrectionCodewords);
    result.codewords = std::move(codewords);
    result.matrix = symbolMatrix;

    return result;
}

std::vector<std::uint8_t> DataMatrixEncoder::encodeAscii(
    const std::string& text)
{
    std::vector<std::uint8_t> codewords;

    for (std::size_t i = 0; i < text.size();)
    {
        const unsigned char current =
            static_cast<unsigned char>(text[i]);

        if (current >= '0' &&
            current <= '9' &&
            i + 1 < text.size())
        {
            const unsigned char next =
                static_cast<unsigned char>(text[i + 1]);

            if (next >= '0' && next <= '9')
            {
                const int value =
                    (current - '0') * 10 +
                    (next - '0');

                codewords.push_back(
                    static_cast<std::uint8_t>(
                        value + 130
                    )
                );

                i += 2;
                continue;
            }
        }

        if (current <= 127)
        {
            codewords.push_back(
                static_cast<std::uint8_t>(
                    current + 1
                )
            );
        }
        else
        {
            codewords.push_back(235);

            codewords.push_back(
                static_cast<std::uint8_t>(
                    current - 127
                )
            );
        }

        ++i;
    }

    return codewords;
}

void DataMatrixEncoder::padToCapacity(
    std::vector<std::uint8_t>& codewords,
    int capacity)
{
    if (static_cast<int>(codewords.size()) > capacity)
    {
        throw std::invalid_argument(
            "Encoded data exceeds Data Matrix capacity."
        );
    }

    if (static_cast<int>(codewords.size()) == capacity)
    {
        return;
    }

    codewords.push_back(129);

    int position = 1;

    while (static_cast<int>(codewords.size()) < capacity)
    {
        const std::uint8_t randomized =
            randomize253State(
                129,
                position
            );

        codewords.push_back(randomized);

        ++position;
    }
}

std::uint8_t DataMatrixEncoder::randomize253State(
    std::uint8_t codeword,
    int position)
{
    const int pseudoRandom =
        ((149 * position) % 253) + 1;

    int value =
        static_cast<int>(codeword) +
        pseudoRandom;

    if (value > 254)
    {
        value -= 254;
    }

    return static_cast<std::uint8_t>(value);
}

std::vector<std::uint8_t>
DataMatrixEncoder::generateErrorCorrection(
    const std::vector<std::uint8_t>& data,
    const DataMatrixSymbolInfo& symbolInfo)
{
    if (static_cast<int>(data.size()) !=
        symbolInfo.dataCodewords)
    {
        throw std::invalid_argument(
            "Data codeword count does not match symbol capacity."
        );
    }

    const int blockCount =
        symbolInfo.rsBlockCount;

    if (blockCount <= 0)
    {
        throw std::invalid_argument(
            "Invalid Reed-Solomon block count."
        );
    }

    std::vector<std::uint8_t> ecc(
        static_cast<std::size_t>(
            symbolInfo.errorCorrectionCodewords
        ),
        0
    );

    if (blockCount == 1)
    {
        return createECCBlock(
            data,
            symbolInfo.errorCorrectionCodewords
        );
    }

    const bool is144 =
        symbolInfo.symbolWidth == 144 &&
        symbolInfo.symbolHeight == 144;

    if (is144)
    {
        constexpr int kLargeBlockCount = 10;
        constexpr int kLargeBlockEcc = 62;

        std::vector<std::vector<std::uint8_t>> blocks;
        blocks.reserve(kLargeBlockCount);

        std::size_t position = 0;

        for (int block = 0;
             block < kLargeBlockCount;
             ++block)
        {
            const int blockDataSize =
                block < 8 ? 156 : 155;

            std::vector<std::uint8_t> blockData;

            blockData.reserve(
                static_cast<std::size_t>(
                    blockDataSize
                )
            );

            for (int i = block;
                 i < symbolInfo.dataCodewords;
                 i += kLargeBlockCount)
            {
                if (static_cast<int>(blockData.size()) <
                    blockDataSize)
                {
                    blockData.push_back(
                        data[static_cast<std::size_t>(i)]
                    );
                }
            }

            if (static_cast<int>(blockData.size()) !=
                blockDataSize)
            {
                throw std::runtime_error(
                    "Invalid 144x144 RS data block."
                );
            }

            std::vector<std::uint8_t> blockEcc =
                createECCBlock(
                    blockData,
                    kLargeBlockEcc
                );

            blocks.push_back(
                std::move(blockEcc)
            );

            position +=
                static_cast<std::size_t>(
                    blockDataSize
                );
        }

        std::size_t eccPosition = 0;

        for (int i = 0;
             i < kLargeBlockEcc;
             ++i)
        {
            for (int block = 0;
                 block < kLargeBlockCount;
                 ++block)
            {
                ecc[eccPosition++] =
                    blocks[
                        static_cast<std::size_t>(block)
                    ][
                        static_cast<std::size_t>(i)
                    ];
            }
        }

        return ecc;
    }

    const int dataPerBlock =
        symbolInfo.dataCodewords / blockCount;

    const int eccPerBlock =
        symbolInfo.errorCorrectionCodewords /
        blockCount;

    if (dataPerBlock * blockCount !=
        symbolInfo.dataCodewords)
    {
        throw std::runtime_error(
            "Data Matrix RS data does not divide evenly "
            "among the configured blocks."
        );
    }

    if (eccPerBlock * blockCount !=
        symbolInfo.errorCorrectionCodewords)
    {
        throw std::runtime_error(
            "Data Matrix RS ECC does not divide evenly "
            "among the configured blocks."
        );
    }

    std::vector<std::vector<std::uint8_t>> blockEcc;
    blockEcc.reserve(
        static_cast<std::size_t>(blockCount)
    );

    for (int block = 0;
         block < blockCount;
         ++block)
    {
        std::vector<std::uint8_t> blockData;

        blockData.reserve(
            static_cast<std::size_t>(dataPerBlock)
        );

        for (int index = block;
             index < symbolInfo.dataCodewords;
             index += blockCount)
        {
            blockData.push_back(
                data[static_cast<std::size_t>(index)]
            );
        }

        if (static_cast<int>(blockData.size()) !=
            dataPerBlock)
        {
            throw std::runtime_error(
                "Invalid interleaved Data Matrix RS block."
            );
        }

        blockEcc.push_back(
            createECCBlock(
                blockData,
                eccPerBlock
            )
        );
    }

    std::size_t outputPosition = 0;

    for (int i = 0;
         i < eccPerBlock;
         ++i)
    {
        for (int block = 0;
             block < blockCount;
             ++block)
        {
            ecc[outputPosition++] =
                blockEcc[
                    static_cast<std::size_t>(block)
                ][
                    static_cast<std::size_t>(i)
                ];
        }
    }

    return ecc;
}

BitMatrix DataMatrixEncoder::placeCodewords(
    const std::vector<std::uint8_t>& codewords,
    const DataMatrixSymbolInfo& symbolInfo)
{
    const int numRows = symbolInfo.dataHeight();
    const int numColumns = symbolInfo.dataWidth();

    BitMatrix matrix(numColumns, numRows);

    std::vector<bool> visited(
        static_cast<std::size_t>(numRows * numColumns),
        false
    );

    auto indexOf = [numColumns](int row, int column)
    {
        return static_cast<std::size_t>(
            row * numColumns + column
        );
    };

    auto setWrapped =
        [&](int row, int column, bool value)
    {
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

        if (row >= numRows)
        {
            row -= numRows;
        }

        if (row < 0 || row >= numRows ||
            column < 0 || column >= numColumns)
        {
            throw std::out_of_range(
                "ECC200 placement coordinate is outside data matrix."
            );
        }

        matrix.set(column, row, value);
        visited[indexOf(row, column)] = true;
    };


    auto writeUtah =
        [&](int row, int column, std::uint8_t codeword)
    {
        const int rows[8] =
        {
            row - 2,
            row - 2,
            row - 1,
            row - 1,
            row - 1,
            row,
            row,
            row
        };

        const int columns[8] =
        {
            column - 2,
            column - 1,
            column - 2,
            column - 1,
            column,
            column - 2,
            column - 1,
            column
        };

        for (int bit = 0; bit < 8; ++bit)
        {
            setWrapped(
                rows[bit],
                columns[bit],
                ((codeword >> (7 - bit)) & 1U) != 0
            );
        }
    };

    auto writeCorner1 =
        [&](int codewordIndex)
    {
        if (codewordIndex < 0 ||
            codewordIndex >= static_cast<int>(codewords.size()))
        {
            throw std::runtime_error(
                "Invalid Corner 1 codeword index."
            );
        }

        const std::uint8_t codeword =
            codewords[codewordIndex];

        setWrapped(
            numRows - 1,
            0,
            ((codeword >> 7) & 1U) != 0
        );

        setWrapped(
            numRows - 1,
            1,
            ((codeword >> 6) & 1U) != 0
        );

        setWrapped(
            numRows - 1,
            2,
            ((codeword >> 5) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 2,
            ((codeword >> 4) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 1,
            ((codeword >> 3) & 1U) != 0
        );

        setWrapped(
            1,
            numColumns - 1,
            ((codeword >> 2) & 1U) != 0
        );

        setWrapped(
            2,
            numColumns - 1,
            ((codeword >> 1) & 1U) != 0
        );

        setWrapped(
            3,
            numColumns - 1,
            (codeword & 1U) != 0
        );
    };

    auto writeCorner2 =
        [&](int codewordIndex)
    {
        if (codewordIndex < 0 ||
            codewordIndex >= static_cast<int>(codewords.size()))
        {
            throw std::runtime_error(
                "Invalid Corner 2 codeword index."
            );
        }

        const std::uint8_t codeword =
            codewords[codewordIndex];

        setWrapped(
            numRows - 3,
            0,
            ((codeword >> 7) & 1U) != 0
        );

        setWrapped(
            numRows - 2,
            0,
            ((codeword >> 6) & 1U) != 0
        );

        setWrapped(
            numRows - 1,
            0,
            ((codeword >> 5) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 4,
            ((codeword >> 4) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 3,
            ((codeword >> 3) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 2,
            ((codeword >> 2) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 1,
            ((codeword >> 1) & 1U) != 0
        );

        setWrapped(
            1,
            numColumns - 1,
            (codeword & 1U) != 0
        );
    };

    auto writeCorner3 =
        [&](int codewordIndex)
    {
        if (codewordIndex < 0 ||
            codewordIndex >= static_cast<int>(codewords.size()))
        {
            throw std::runtime_error(
                "Invalid Corner 3 codeword index."
            );
        }

        const std::uint8_t codeword =
            codewords[codewordIndex];

        // Canonical ECC200 Corner 3 (used when numColumns % 8 == 4).
        const int rows[8] =
        {
            numRows - 3,
            numRows - 2,
            numRows - 1,
            0,
            0,
            1,
            2,
            3
        };

        const int columns[8] =
        {
            0,
            0,
            0,
            numColumns - 2,
            numColumns - 1,
            numColumns - 1,
            numColumns - 1,
            numColumns - 1
        };

        for (int bit = 0; bit < 8; ++bit)
        {
            setWrapped(
                rows[bit],
                columns[bit],
                ((codeword >> (7 - bit)) & 1U) != 0
            );
        }
    };
            auto writeCorner4 =
        [&](int codewordIndex)
    {
        if (codewordIndex < 0 ||
            codewordIndex >= static_cast<int>(codewords.size()))
        {
            throw std::runtime_error(
                "Invalid Corner 4 codeword index."
            );
        }

        const std::uint8_t codeword =
            codewords[codewordIndex];

        setWrapped(
            numRows - 1,
            0,
            ((codeword >> 7) & 1U) != 0
        );

        setWrapped(
            numRows - 1,
            numColumns - 1,
            ((codeword >> 6) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 3,
            ((codeword >> 5) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 2,
            ((codeword >> 4) & 1U) != 0
        );

        setWrapped(
            0,
            numColumns - 1,
            ((codeword >> 3) & 1U) != 0
        );

        setWrapped(
            1,
            numColumns - 3,
            ((codeword >> 2) & 1U) != 0
        );

        setWrapped(
            1,
            numColumns - 2,
            ((codeword >> 1) & 1U) != 0
        );

        setWrapped(
            1,
            numColumns - 1,
            (codeword & 1U) != 0
        );
    };

    int row = 4;
    int column = 0;
    int codewordIndex = 0;

    while (true)
    {
        if (row == numRows &&
            column == 0)
        {
            writeCorner1(codewordIndex++);
        }

        if (row == numRows - 2 &&
            column == 0 &&
            (numColumns % 4) != 0)
        {
            writeCorner2(codewordIndex++);
        }

        if (row == numRows + 4 &&
            column == 2 &&
            (numColumns % 8) == 0)
        {
            writeCorner4(codewordIndex++);
        }

        if (row == numRows - 2 &&
            column == 0 &&
            (numColumns % 8) == 4)
        {
            writeCorner3(codewordIndex++);
        }

        do
        {
            if (row < numRows &&
                column >= 0 &&
                !visited[indexOf(row, column)])
            {
                writeUtah(
                    row,
                    column,
                    codewords[codewordIndex++]
                );
            }

            row -= 2;
            column += 2;
        }
        while (row >= 0 && column < numColumns);

        row += 1;
        column += 3;

        do
        {
            if (row >= 0 &&
                column < numColumns &&
                !visited[indexOf(row, column)])
            {
                writeUtah(
                    row,
                    column,
                    codewords[codewordIndex++]
                );
            }

            row += 2;
            column -= 2;
        }
        while (row < numRows && column >= 0);

        row += 3;
        column += 1;

        if (row >= numRows &&
            column >= numColumns)
        {
            break;
        }
    }

    if (codewordIndex != static_cast<int>(codewords.size()))
    {
        throw std::runtime_error(
            "ECC200 encoder placement did not consume all codewords."
        );
    }

    if (!visited[indexOf(numRows - 1, numColumns - 1)])
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
BitMatrix DataMatrixEncoder::buildSymbolMatrix(
    const BitMatrix& dataMatrix,
    const DataMatrixSymbolInfo& symbolInfo)
{
    BitMatrix symbol(
        symbolInfo.symbolWidth,
        symbolInfo.symbolHeight
    );

    const int regionWidth =
        symbolInfo.dataRegionWidth;

    const int regionHeight =
        symbolInfo.dataRegionHeight;

    for (int regionY = 0;
         regionY < symbolInfo.regionsVertical;
         ++regionY)
    {
        for (int regionX = 0;
             regionX < symbolInfo.regionsHorizontal;
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

            for (int y = 0;
                 y < regionHeight;
                 ++y)
            {
                for (int x = 0;
                     x < regionWidth;
                     ++x)
                {
                    symbol.set(
                        symbolOriginX + 1 + x,
                        symbolOriginY + 1 + y,
                        dataMatrix.get(
                            dataOriginX + x,
                            dataOriginY + y
                        )
                    );
                }
            }

            for (int y = 0;
                 y < regionHeight + 2;
                 ++y)
            {
                symbol.setTrue(
                    symbolOriginX,
                    symbolOriginY + y
                );
            }

            for (int x = 0;
                 x < regionWidth + 2;
                 ++x)
            {
                symbol.setTrue(
                    symbolOriginX + x,
                    symbolOriginY + regionHeight + 1
                );
            }

            for (int x = 0;
                 x < regionWidth + 2;
                 ++x)
            {
                symbol.set(
                    symbolOriginX + x,
                    symbolOriginY,
                    (x % 2) == 0
                );
            }

            for (int y = 0;
                 y < regionHeight + 2;
                 ++y)
            {
                symbol.set(
                    symbolOriginX + regionWidth + 1,
                    symbolOriginY + y,
                    (y % 2) == 0
                );
            }
        }
    }

    return symbol;
}

} // namespace exalted








