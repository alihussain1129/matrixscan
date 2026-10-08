#pragma once

#include <cstddef>
#include <stdexcept>
#include <vector>

namespace exalted {

class BitMatrix {
public:
    BitMatrix() = default;

    BitMatrix(int width, int height);

    int width() const noexcept;
    int height() const noexcept;

    bool get(int x, int y) const;
    void set(int x, int y, bool value);

    void setTrue(int x, int y);
    void setFalse(int x, int y);

    void clear();

    bool isValid(int x, int y) const noexcept;

private:
    int width_ = 0;
    int height_ = 0;

    std::vector<bool> bits_;

    std::size_t index(int x, int y) const;
};

} // namespace exalted
