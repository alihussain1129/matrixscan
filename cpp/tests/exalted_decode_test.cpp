// End-to-end native decode test (no Flutter, no camera).
//
// Renders each golden fixture (a Data Matrix symbol independently verified
// elsewhere) into a grayscale image the way a camera frame looks - scaled,
// with a quiet zone, with padded rows (stride > width), and rotated - then
// calls the exact C function the Android app calls (exalted_decode).

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "exalted/ffi_api.h"

#ifndef EXALTED_GOLDEN_DIR
#error "EXALTED_GOLDEN_DIR must be defined by the build"
#endif

namespace
{

struct Symbol
{
    int width = 0;
    int height = 0;
    std::vector<std::string> rows;
};

bool load(const std::string& name, Symbol& out)
{
    std::ifstream in(std::string(EXALTED_GOLDEN_DIR) + "/" + name);
    if (!in) return false;

    std::string line;
    while (std::getline(in, line))
    {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.rfind("TEXT ", 0) == 0 || line.rfind("SIZE ", 0) == 0) continue;
        if (line == "END") break;
        out.rows.push_back(line);
    }

    out.height = static_cast<int>(out.rows.size());
    out.width = out.height > 0 ? static_cast<int>(out.rows[0].size()) : 0;
    return out.width > 0 && out.height > 0;
}

struct Image
{
    int width = 0;
    int height = 0;
    int stride = 0;
    std::vector<std::uint8_t> data;
};

Image render(const Symbol& s, int scale, int quiet, int rowPadding)
{
    Image img;
    img.width = (s.width + 2 * quiet) * scale;
    img.height = (s.height + 2 * quiet) * scale;
    img.stride = img.width + rowPadding;
    img.data.assign(static_cast<size_t>(img.stride) * img.height, 255);

    for (int y = 0; y < s.height; ++y)
        for (int x = 0; x < s.width; ++x)
            if (s.rows[y][x] == '#')
                for (int dy = 0; dy < scale; ++dy)
                    for (int dx = 0; dx < scale; ++dx)
                        img.data[static_cast<size_t>((y + quiet) * scale + dy) * img.stride +
                                 (x + quiet) * scale + dx] = 0;
    return img;
}

Image rotate90(const Image& in)
{
    Image out;
    out.width = in.height;
    out.height = in.width;
    out.stride = out.width + 7;
    out.data.assign(static_cast<size_t>(out.stride) * out.height, 255);

    for (int y = 0; y < in.height; ++y)
        for (int x = 0; x < in.width; ++x)
            out.data[static_cast<size_t>(x) * out.stride + (in.height - 1 - y)] =
                in.data[static_cast<size_t>(y) * in.stride + x];
    return out;
}

bool check(const char* label, const Image& img, const std::string& expected,
           std::int32_t expectedFormat)
{
    std::int32_t info[EXALTED_DECODE_INFO_LEN] = {};
    std::vector<std::uint8_t> text(4096);

    const int rc = exalted_decode(
        img.data.data(), static_cast<std::int32_t>(img.data.size()),
        img.width, img.height, img.stride,
        0, 1, info, EXALTED_DECODE_INFO_LEN,
        text.data(), static_cast<std::int32_t>(text.size()));

    if (rc != 1)
    {
        std::cerr << "FAIL: " << label << " rc=" << rc << " (expected 1)\n";
        return false;
    }

    const std::string got(reinterpret_cast<char*>(text.data()), info[1]);

    if (got != expected || info[0] != expectedFormat)
    {
        std::cerr << "FAIL: " << label << " got '" << got << "' format="
                  << info[0] << ", expected '" << expected << "' format="
                  << expectedFormat << "\n";
        return false;
    }

    std::cout << "PASS: " << label << " -> " << got << " (" << info[11] << " us)\n";
    return true;
}

} // namespace

int main()
{
    struct Case { const char* file; const char* text; };
    const Case cases[] = {
        {"dm_10x10_A.txt", "A"},
        {"dm_14x14_ABCDEF.txt", "ABCDEF"},
        {"dm_18x8_123456.txt", "123456"},
        {"dm_26x12_123456.txt", "123456"},
        {"dm_32x8_123456.txt", "123456"},
        {"dm_36x12_123456.txt", "123456"},
        {"dm_36x16_123456.txt", "123456"},
        {"dm_48x16_123456.txt", "123456"},
    };

    bool ok = true;

    for (const Case& c : cases)
    {
        Symbol s;
        if (!load(c.file, s))
        {
            std::cerr << "FAIL: cannot load " << c.file << "\n";
            ok = false;
            continue;
        }

        const Image img = render(s, 6, 4, 13);
        ok &= check((std::string(c.file) + " stride-padded").c_str(), img,
                    c.text, EXALTED_FMT_DATAMATRIX);
        ok &= check((std::string(c.file) + " rotated-90").c_str(), rotate90(img),
                    c.text, EXALTED_FMT_DATAMATRIX);
    }

    // A blank frame must report "no barcode", not an error.
    {
        Image blank;
        blank.width = 320; blank.height = 240; blank.stride = 320;
        blank.data.assign(320 * 240, 200);
        std::int32_t info[EXALTED_DECODE_INFO_LEN] = {};
        std::vector<std::uint8_t> text(64);
        const int rc = exalted_decode(blank.data.data(), 320 * 240, 320, 240, 320,
                                      0, 0, info, EXALTED_DECODE_INFO_LEN,
                                      text.data(), 64);
        if (rc != 0) { std::cerr << "FAIL: blank frame rc=" << rc << "\n"; ok = false; }
        else std::cout << "PASS: blank frame -> no barcode\n";
    }

    // Bad arguments are rejected with codes, never crash.
    {
        std::int32_t info[EXALTED_DECODE_INFO_LEN] = {};
        std::uint8_t text[8] = {};
        std::uint8_t px[16] = {};
        const int a = exalted_decode(nullptr, 0, 4, 4, 4, 0, 0, info, 12, text, 8);
        const int b = exalted_decode(px, 16, 4, 4, 2, 0, 0, info, 12, text, 8);
        const int c = exalted_decode(px, 8, 4, 4, 4, 0, 0, info, 12, text, 8);
        if (a != -1 || b != -2 || c != -3)
        {
            std::cerr << "FAIL: bad-argument codes " << a << " " << b << " " << c << "\n";
            ok = false;
        }
        else std::cout << "PASS: bad arguments rejected (-1, -2, -3)\n";
    }

    if (!ok) { std::cerr << "NATIVE DECODE TEST FAILED\n"; return 1; }
    std::cout << "All native decode checks passed.\n";
    return 0;
}
