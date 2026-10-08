#include <iostream>
#include "exalted/datamatrix_encoder.h"

using exalted::DataMatrixEncoder;

int main()
{
    const auto encoded =
        DataMatrixEncoder::encode("123456");

    std::cout
        << "Width:  "
        << encoded.symbolInfo.symbolWidth
        << '\n';

    std::cout
        << "Height: "
        << encoded.symbolInfo.symbolHeight
        << '\n';

    std::cout
        << "Data codewords: "
        << encoded.dataCodewords.size()
        << '\n';

    std::cout
        << "ECC codewords: "
        << encoded.errorCorrectionCodewords.size()
        << '\n';

    std::cout << "Data:";
    for (const auto value : encoded.dataCodewords)
    {
        std::cout
            << ' '
            << static_cast<int>(value);
    }

    std::cout << "\nECC:";
    for (const auto value : encoded.errorCorrectionCodewords)
    {
        std::cout
            << ' '
            << static_cast<int>(value);
    }

    std::cout << '\n';

    return 0;
}
