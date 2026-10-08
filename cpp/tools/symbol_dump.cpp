// symbol_dump.cpp - prints the FINAL encoded symbol (finder + data) as text so it
// can be decoded by an independent scanner. Diagnostic tool, not part of the library.
#include <iostream>
#include <string>
#include <vector>

#include "exalted/datamatrix_encoder.h"

int main(int argc, char** argv)
{
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
            const auto symbol = exalted::DataMatrixEncoder::encode(text);
            const exalted::BitMatrix& m = symbol.matrix;

            std::cout << "TEXT " << text << "\n";
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
        catch (const std::exception& e)
        {
            std::cout << "TEXT " << text << "\n";
            std::cout << "ERROR " << e.what() << "\n";
            std::cout << "END\n";
        }
    }

    return 0;
}
