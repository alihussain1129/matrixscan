#include "exalted/datamatrix_symbol.h"

namespace exalted {

DataMatrixSymbol::DataMatrixSymbol(
    int symbolWidth,
    int symbolHeight,
    int dataRegionWidth,
    int dataRegionHeight,
    int regionsHorizontal,
    int regionsVertical
)
    : symbolWidth_(symbolWidth),
      symbolHeight_(symbolHeight),
      dataRegionWidth_(dataRegionWidth),
      dataRegionHeight_(dataRegionHeight),
      regionsHorizontal_(regionsHorizontal),
      regionsVertical_(regionsVertical)
{
    if (symbolWidth <= 0 ||
        symbolHeight <= 0 ||
        dataRegionWidth <= 0 ||
        dataRegionHeight <= 0 ||
        regionsHorizontal <= 0 ||
        regionsVertical <= 0)
    {
        throw std::invalid_argument(
            "Data Matrix symbol dimensions must be greater than zero."
        );
    }
}

int DataMatrixSymbol::symbolWidth() const noexcept
{
    return symbolWidth_;
}

int DataMatrixSymbol::symbolHeight() const noexcept
{
    return symbolHeight_;
}

int DataMatrixSymbol::dataRegionWidth() const noexcept
{
    return dataRegionWidth_;
}

int DataMatrixSymbol::dataRegionHeight() const noexcept
{
    return dataRegionHeight_;
}

int DataMatrixSymbol::regionsHorizontal() const noexcept
{
    return regionsHorizontal_;
}

int DataMatrixSymbol::regionsVertical() const noexcept
{
    return regionsVertical_;
}

int DataMatrixSymbol::dataWidth() const noexcept
{
    return dataRegionWidth_ * regionsHorizontal_;
}

int DataMatrixSymbol::dataHeight() const noexcept
{
    return dataRegionHeight_ * regionsVertical_;
}

int DataMatrixSymbol::regionCount() const noexcept
{
    return regionsHorizontal_ * regionsVertical_;
}

} // namespace exalted
