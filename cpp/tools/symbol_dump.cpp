// symbol_dump.cpp - prints the FINAL symbol (finder + data) as text so it can be
// decoded by an independent scanner. Diagnostic tool, not part of the library.
//
//   symbol_dump.exe                      -> encode a few default texts
//   symbol_dump.exe TEXT [TEXT ...]      -> encode the given texts
//   symbol_dump.exe --cw W H c0 c1 ...   -> place the given codewords (decimal) into
//                                           the WxH symbol using the production
//                                           placeCodewords + buildSymbolMatrix
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "exalted/datamatrix_encoder.h"
#include "exalted/datamatrix_symbol_info.h"

namespace
{

void printMatrix(const std::string& label, const exalted::BitMatrix& m)
{
    std::cout << "TEXT " << label << "\n";
    std::cout << "SIZE " << m.width() << "x" << m.height() << "\n";

    for (int y = 0; y < m.height(); ++y)
    {
        for (int x = 0; x < m.width(); ++x)
        {
            std::cout << (m.get(x, y) ? '#' : '.');
        }

        std::cout << "\n";
    }

    std::cout << "END\n";
}

int dumpCodewords(int argc, char** argv)
{
    if (argc < 5)
    {
        std::cout << "ERROR usage: --cw W H c0 c1 ...\nEND\n";
        return 1;
    }

    const int width = std::stoi(argv[2]);
    const int height = std::stoi(argv[3]);
    const std::string label =
        "cw-" + std::to_string(width) + "x" + std::to_string(height);

    std::vector<std::uint8_t> codewords;

    for (int i = 4; i < argc; ++i)
    {
        codewords.push_back(static_cast<std::uint8_t>(std::stoi(argv[i])));
    }

    try
    {
        const exalted::DataMatrixSymbolInfo* info =
            exalted::findDataMatrixSymbolInfo(width, height);

        if (info == nullptr)
        {
            std::cout << "TEXT " << label << "\nERROR no symbol info\nEND\n";
            return 1;
        }

        if (static_cast<int>(codewords.size()) != info->totalCodewords())
        {
            std::cout << "TEXT " << label << "\nERROR expected "
                      << info->totalCodewords() << " codewords, got "
                      << codewords.size() << "\nEND\n";
            return 1;
        }

        const exalted::BitMatrix dataMatrix =
            exalted::DataMatrixEncoderTestAccess::placeCodewords(
                codewords, *info);

        printMatrix(
            label,
            exalted::DataMatrixEncoderTestAccess::buildSymbolMatrix(
                dataMatrix, *info));
    }
    catch (const std::exception& e)
    {
        std::cout << "TEXT " << label << "\nERROR " << e.what() << "\nEND\n";
        return 1;
    }

    return 0;
}

} // namespace

int main(int argc, char** argv)
{
    if (argc >= 2 && std::string(argv[1]) == "--cw")
    {
        return dumpCodewords(argc, argv);
    }

    std::vector<std::string> inputs;

    for (int i = 1; i < argc; ++i)
    {
        inputs.emplace_back(argv[i]);
    }

    if (inputs.empty())
    {
        inputs = { "A", "ABCDEF", "EXALTED-DATAMATRIX-0123456789" };
    }

    for (const std::string& text : inputs)
    {
        try
        {
            printMatrix(
                text,
                exalted::DataMatrixEncoder::encode(text).matrix);
        }
        catch (const std::exception& e)
        {
            std::cout << "TEXT " << text << "\nERROR " << e.what() << "\nEND\n";
        }
    }

    return 0;
}
