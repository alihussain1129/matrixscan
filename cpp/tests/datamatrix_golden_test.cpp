// Golden regression test for Data Matrix final symbols.
//
// Each fixture in tests/golden/ is a symbol dumped by tools/symbol_dump and
// confirmed by an independent decoder (zxing-cpp). The expected rows come from
// those files, not from the code under test, so a regression in placement,
// the finder pattern, the clock tracks or the region borders fails here.

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "exalted/datamatrix_encoder.h"
#include "exalted/datamatrix_symbol_info.h"

#ifndef EXALTED_GOLDEN_DIR
#error "EXALTED_GOLDEN_DIR must be defined by the build"
#endif

namespace
{

struct Fixture
{
    int width = 0;
    int height = 0;
    std::vector<std::string> rows;
};

bool loadFixture(const std::string& name, Fixture& out)
{
    const std::string path = std::string(EXALTED_GOLDEN_DIR) + "/" + name;
    std::ifstream in(path);

    if (!in)
    {
        std::cerr << "FAIL: cannot open " << path << "\n";
        return false;
    }

    std::string line;
    bool sawSize = false;
    bool sawEnd = false;

    while (std::getline(in, line))
    {
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }

        if (line.rfind("TEXT ", 0) == 0)
        {
            continue;
        }

        if (line.rfind("ERROR", 0) == 0)
        {
            std::cerr << "FAIL: " << name << " contains: " << line << "\n";
            return false;
        }

        if (line.rfind("SIZE ", 0) == 0)
        {
            if (std::sscanf(line.c_str(), "SIZE %dx%d",
                            &out.width, &out.height) != 2)
            {
                std::cerr << "FAIL: bad SIZE line in " << name << "\n";
                return false;
            }

            sawSize = true;
            continue;
        }

        if (line == "END")
        {
            sawEnd = true;
            break;
        }

        out.rows.push_back(line);
    }

    if (!sawSize || !sawEnd)
    {
        std::cerr << "FAIL: " << name << " is missing SIZE or END\n";
        return false;
    }

    if (static_cast<int>(out.rows.size()) != out.height)
    {
        std::cerr << "FAIL: " << name << " has " << out.rows.size()
                  << " rows, expected " << out.height << "\n";
        return false;
    }

    for (const std::string& row : out.rows)
    {
        if (static_cast<int>(row.size()) != out.width)
        {
            std::cerr << "FAIL: " << name << " has a row of length "
                      << row.size() << ", expected " << out.width << "\n";
            return false;
        }
    }

    return true;
}

bool compare(const std::string& name, const exalted::BitMatrix& actual)
{
    Fixture expected;

    if (!loadFixture(name, expected))
    {
        return false;
    }

    if (actual.width() != expected.width || actual.height() != expected.height)
    {
        std::cerr << "FAIL: " << name << " size mismatch: got "
                  << actual.width() << "x" << actual.height()
                  << ", expected " << expected.width << "x"
                  << expected.height << "\n";
        return false;
    }

    for (int y = 0; y < actual.height(); ++y)
    {
        for (int x = 0; x < actual.width(); ++x)
        {
            const char got = actual.get(x, y) ? '#' : '.';

            if (got != expected.rows[y][x])
            {
                std::cerr << "FAIL: " << name << " differs at x=" << x
                          << " y=" << y << " (got '" << got
                          << "', expected '" << expected.rows[y][x] << "')\n";
                return false;
            }
        }
    }

    std::cout << "PASS: " << name << "\n";
    return true;
}

bool checkEncoded(const std::string& name, const std::string& text)
{
    try
    {
        return compare(name, exalted::DataMatrixEncoder::encode(text).matrix);
    }
    catch (const std::exception& e)
    {
        std::cerr << "FAIL: " << name << " threw: " << e.what() << "\n";
        return false;
    }
}

bool checkCodewords(
    const std::string& name,
    int width,
    int height,
    const std::vector<std::uint8_t>& codewords)
{
    try
    {
        const exalted::DataMatrixSymbolInfo* info =
            exalted::findDataMatrixSymbolInfo(width, height);

        if (info == nullptr)
        {
            std::cerr << "FAIL: " << name << " no symbol info\n";
            return false;
        }

        if (static_cast<int>(codewords.size()) != info->totalCodewords())
        {
            std::cerr << "FAIL: " << name << " wrong codeword count\n";
            return false;
        }

        const exalted::BitMatrix dataMatrix =
            exalted::DataMatrixEncoderTestAccess::placeCodewords(
                codewords, *info);

        return compare(
            name,
            exalted::DataMatrixEncoderTestAccess::buildSymbolMatrix(
                dataMatrix, *info));
    }
    catch (const std::exception& e)
    {
        std::cerr << "FAIL: " << name << " threw: " << e.what() << "\n";
        return false;
    }
}

} // namespace

int main()
{
    bool ok = true;

    // Square symbols: full production path (data encoding, RS, placement, border).
    ok &= checkEncoded("dm_10x10_A.txt", "A");
    ok &= checkEncoded("dm_14x14_ABCDEF.txt", "ABCDEF");

    // Rectangles: production placement + border, codewords supplied externally.
    ok &= checkCodewords(
        "dm_32x8_123456.txt", 32, 8,
        {142, 164, 186, 129, 115, 11, 161, 56, 206, 101, 212, 183,
         247, 119, 100, 164, 8, 157, 215, 248, 177});

    ok &= checkCodewords(
        "dm_18x8_123456.txt", 18, 8,
        {142, 164, 186, 129, 115, 248, 69, 9, 108, 180, 217, 198});

    ok &= checkCodewords(
        "dm_26x12_123456.txt", 26, 12,
        {142, 164, 186, 129, 115, 11, 161, 56, 206, 101, 251, 147, 42, 192, 87,
         237, 119, 52, 27, 251, 229, 250, 17, 83, 67, 39, 116, 89, 84, 251});

    ok &= checkCodewords(
        "dm_36x12_123456.txt", 36, 12,
        {142, 164, 186, 129, 115, 11, 161, 56, 206, 101, 251, 147, 42, 192, 87,
         237, 133, 28, 178, 73, 223, 118, 249, 28, 126, 39, 150, 19, 68, 163,
         206, 114, 83, 45, 160, 2, 138, 36, 153, 238});

    ok &= checkCodewords(
        "dm_36x16_123456.txt", 36, 16,
        {142, 164, 186, 129, 115, 11, 161, 56, 206, 101, 251, 147, 42, 192, 87,
         237, 133, 28, 178, 73, 223, 118, 14, 164, 59, 209, 104, 254, 150, 45,
         195, 90, 196, 67, 39, 229, 157, 241, 161, 243, 67, 6, 61, 208, 188, 74,
         125, 34, 110, 253, 110, 212, 78, 11, 166, 118});

    ok &= checkCodewords(
        "dm_48x16_123456.txt", 48, 16,
        {142, 164, 186, 129, 115, 11, 161, 56, 206, 101, 251, 147, 42, 192, 87,
         237, 133, 28, 178, 73, 223, 118, 14, 164, 59, 209, 104, 254, 150, 45,
         195, 90, 240, 136, 31, 181, 76, 226, 121, 17, 167, 62, 212, 107, 3, 153,
         48, 198, 93, 229, 227, 241, 194, 196, 49, 224, 136, 233, 50, 123, 34,
         102, 95, 90, 196, 0, 183, 32, 34, 54, 207, 146, 28, 9, 85, 122, 77});

    if (!ok)
    {
        std::cerr << "GOLDEN TEST FAILED\n";
        return 1;
    }

    std::cout << "All golden symbols match.\n";
    return 0;
}
