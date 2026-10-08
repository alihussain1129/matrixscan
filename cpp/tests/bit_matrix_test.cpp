#include <iostream>
#include <stdexcept>

#include "exalted/bit_matrix.h"

using exalted::BitMatrix;

int main()
{
    try
    {
        BitMatrix matrix(5, 4);

        if (matrix.width() != 5 || matrix.height() != 4)
        {
            std::cerr << "FAIL: Incorrect dimensions.\n";
            return 1;
        }

        if (matrix.get(2, 1))
        {
            std::cerr << "FAIL: Matrix should initially be false.\n";
            return 1;
        }

        matrix.setTrue(2, 1);

        if (!matrix.get(2, 1))
        {
            std::cerr << "FAIL: setTrue/get failed.\n";
            return 1;
        }

        matrix.setFalse(2, 1);

        if (matrix.get(2, 1))
        {
            std::cerr << "FAIL: setFalse failed.\n";
            return 1;
        }

        matrix.set(4, 3, true);

        if (!matrix.get(4, 3))
        {
            std::cerr << "FAIL: set/get failed.\n";
            return 1;
        }

        if (!matrix.isValid(0, 0) ||
            !matrix.isValid(4, 3) ||
            matrix.isValid(5, 3) ||
            matrix.isValid(4, 4))
        {
            std::cerr << "FAIL: Boundary validation failed.\n";
            return 1;
        }

        bool exceptionCaught = false;

        try
        {
            matrix.get(5, 0);
        }
        catch (const std::out_of_range&)
        {
            exceptionCaught = true;
        }

        if (!exceptionCaught)
        {
            std::cerr << "FAIL: Out-of-range access was not rejected.\n";
            return 1;
        }

        matrix.setTrue(0, 0);
        matrix.setTrue(1, 1);
        matrix.clear();

        if (matrix.get(0, 0) || matrix.get(1, 1))
        {
            std::cerr << "FAIL: clear() failed.\n";
            return 1;
        }

        std::cout << "========================================\n";
        std::cout << " BitMatrix TEST PASSED\n";
        std::cout << "========================================\n";
        std::cout << "Dimensions: "
                  << matrix.width()
                  << " x "
                  << matrix.height()
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
