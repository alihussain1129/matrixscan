#include "exalted/bit_matrix.h"

namespace exalted {

BitMatrix::BitMatrix(int width, int height)
    : width_(width),
      height_(height),
      bits_(static_cast<std::size_t>(width) *
            static_cast<std::size_t>(height),
            false)
{
    if (width <= 0 || height <= 0) {
        throw std::invalid_argument(
            "BitMatrix dimensions must be greater than zero."
        );
    }
}

int BitMatrix::width() const noexcept
{
    return width_;
}

int BitMatrix::height() const noexcept
{
    return height_;
}

bool BitMatrix::get(int x, int y) const
{
    return bits_.at(index(x, y));
}

void BitMatrix::set(int x, int y, bool value)
{
    bits_.at(index(x, y)) = value;
}

void BitMatrix::setTrue(int x, int y)
{
    set(x, y, true);
}

void BitMatrix::setFalse(int x, int y)
{
    set(x, y, false);
}

void BitMatrix::clear()
{
    std::fill(bits_.begin(), bits_.end(), false);
}

bool BitMatrix::isValid(int x, int y) const noexcept
{
    return x >= 0 &&
           x < width_ &&
           y >= 0 &&
           y < height_;
}

std::size_t BitMatrix::index(int x, int y) const
{
    if (!isValid(x, y)) {
        throw std::out_of_range(
            "BitMatrix coordinates are outside the matrix."
        );
    }

    return static_cast<std::size_t>(y) *
           static_cast<std::size_t>(width_) +
           static_cast<std::size_t>(x);
}

} // namespace exalted
