#include "exalted/datamatrix_decoder.h"

namespace exalted {

DecodeResult DataMatrixDecoder::decode()
{
    DecodeResult result;

    result.success = false;
    result.format = "Data Matrix";
    result.error = "Data Matrix decoder not implemented yet.";

    return result;
}

} // namespace exalted
