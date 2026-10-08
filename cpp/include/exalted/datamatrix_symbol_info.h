#pragma once

namespace exalted {

struct DataMatrixSymbolInfo
{
    int symbolWidth;
    int symbolHeight;

    int dataRegionWidth;
    int dataRegionHeight;

    int regionsHorizontal;
    int regionsVertical;

    int dataCodewords;
    int errorCorrectionCodewords;

    int rsBlockCount;

    int totalCodewords() const noexcept
    {
        return dataCodewords + errorCorrectionCodewords;
    }

    int dataWidth() const noexcept
    {
        return dataRegionWidth * regionsHorizontal;
    }

    int dataHeight() const noexcept
    {
        return dataRegionHeight * regionsVertical;
    }

    int regionCount() const noexcept
    {
        return regionsHorizontal * regionsVertical;
    }
};

const DataMatrixSymbolInfo* findDataMatrixSymbolInfo(
    int symbolWidth,
    int symbolHeight) noexcept;

} // namespace exalted
