#pragma once

#include <stdexcept>

namespace exalted {

class DataMatrixSymbol {
public:
    DataMatrixSymbol(
        int symbolWidth,
        int symbolHeight,
        int dataRegionWidth,
        int dataRegionHeight,
        int regionsHorizontal,
        int regionsVertical
    );

    int symbolWidth() const noexcept;
    int symbolHeight() const noexcept;

    int dataRegionWidth() const noexcept;
    int dataRegionHeight() const noexcept;

    int regionsHorizontal() const noexcept;
    int regionsVertical() const noexcept;

    int dataWidth() const noexcept;
    int dataHeight() const noexcept;

    int regionCount() const noexcept;

private:
    int symbolWidth_;
    int symbolHeight_;

    int dataRegionWidth_;
    int dataRegionHeight_;

    int regionsHorizontal_;
    int regionsVertical_;
};

} // namespace exalted
