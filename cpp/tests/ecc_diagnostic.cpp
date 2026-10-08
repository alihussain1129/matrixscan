#include <cstdint>
#include <iomanip>
#include <iostream>

#include "exalted/datamatrix_encoder.h"

int main()
{
    const auto encoded =
        exalted::DataMatrixEncoder::encode("A");

    std::cout << "Data: ";

    for (const auto value : encoded.dataCodewords)
    {
        std::cout
            << "0x"
            << std::hex
            << std::setw(2)
            << std::setfill('0')
            << static_cast<int>(value)
            << " ";
    }

    std::cout << "\nECC:  ";

    for (const auto value : encoded.errorCorrectionCodewords)
    {
        std::cout
            << "0x"
            << std::hex
            << std::setw(2)
            << std::setfill('0')
            << static_cast<int>(value)
            << " ";
    }

    std::cout << "\n";

    return 0;
}
