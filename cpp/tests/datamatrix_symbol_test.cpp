#include <iostream>
#include <stdexcept>

#include "exalted/datamatrix_symbol.h"

using exalted::DataMatrixSymbol;

int main()
{
    try
    {
        DataMatrixSymbol symbol(
            10,  // symbol width
            10,  // symbol height
            8,   // data region width
            8,   // data region height
            1,   // horizontal regions
            1    // vertical regions
        );

        if (symbol.symbolWidth() != 10 ||
            symbol.symbolHeight() != 10)
        {
            std::cerr << "FAIL: Symbol dimensions incorrect.\n";
            return 1;
        }

        if (symbol.dataRegionWidth() != 8 ||
            symbol.dataRegionHeight() != 8)
        {
            std::cerr << "FAIL: Data region dimensions incorrect.\n";
            return 1;
        }

        if (symbol.regionsHorizontal() != 1 ||
            symbol.regionsVertical() != 1)
        {
            std::cerr << "FAIL: Region counts incorrect.\n";
            return 1;
        }

        if (symbol.dataWidth() != 8 ||
            symbol.dataHeight() != 8)
        {
            std::cerr << "FAIL: Calculated data dimensions incorrect.\n";
            return 1;
        }

        if (symbol.regionCount() != 1)
        {
            std::cerr << "FAIL: Region count calculation incorrect.\n";
            return 1;
        }

        bool exceptionCaught = false;

        try
        {
            DataMatrixSymbol invalid(
                0,
                10,
                8,
                8,
                1,
                1
            );
        }
        catch (const std::invalid_argument&)
        {
            exceptionCaught = true;
        }

        if (!exceptionCaught)
        {
            std::cerr << "FAIL: Invalid dimensions were accepted.\n";
            return 1;
        }

        std::cout << "========================================\n";
        std::cout << " DataMatrixSymbol TEST PASSED\n";
        std::cout << "========================================\n";
        std::cout << "Symbol: "
                  << symbol.symbolWidth()
                  << " x "
                  << symbol.symbolHeight()
                  << "\n";

        std::cout << "Data area: "
                  << symbol.dataWidth()
                  << " x "
                  << symbol.dataHeight()
                  << "\n";

        std::cout << "Regions: "
                  << symbol.regionCount()
                  << "\n";

        return 0;
    }
    catch (const std::exception& ex)
    {
        std::cerr << "FAIL: Unexpected exception: "
                  << ex.what()
                  << "\n";

        return 1;
    }
}
