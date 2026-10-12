// Dot-peen regression test (no Flutter, no camera).
//
// Renders each golden Data Matrix symbol the way a dot-peened mark looks: every
// dark module becomes a separate round dot, with gaps between dots. A plain
// decode cannot read that; the dot-merging flags of exalted_decode must. The
// flag list below must match lib/ffi/dot_peen_flags.dart.

#include <cstdint>
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

const int kLadder[] = {3096, 4104, 4120, 5144, 2056, 1032,
                       3354, 4362, 4378, 2314};

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

// Dark round dots (diameter 0.6 x pitch) on a light background, softened by
// one 3x3 box blur like a camera would. lightOnDark inverts the whole frame.
Image renderDots(const Symbol& s, int pitch, int quiet, bool lightOnDark)
{
    Image img;
    img.width = (s.width + 2 * quiet) * pitch;
    img.height = (s.height + 2 * quiet) * pitch;
    img.stride = img.width + 11;
    std::vector<std::uint8_t> sharp(
        static_cast<size_t>(img.width) * img.height, 255);

    const double r = pitch * 0.30;
    for (int my = 0; my < s.height; ++my)
        for (int mx = 0; mx < s.width; ++mx)
        {
            if (s.rows[my][mx] != '#') continue;
            const double cx = (mx + quiet) * pitch + pitch / 2.0;
            const double cy = (my + quiet) * pitch + pitch / 2.0;
            for (int y = static_cast<int>(cy - r) - 1; y <= static_cast<int>(cy + r) + 1; ++y)
                for (int x = static_cast<int>(cx - r) - 1; x <= static_cast<int>(cx + r) + 1; ++x)
                {
                    const double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
                    if (dx * dx + dy * dy <= r * r)
                        sharp[static_cast<size_t>(y) * img.width + x] = 0;
                }
        }

    img.data.assign(static_cast<size_t>(img.stride) * img.height, 255);
    for (int y = 0; y < img.height; ++y)
        for (int x = 0; x < img.width; ++x)
        {
            int sum = 0, n = 0;
            for (int j = -1; j <= 1; ++j)
                for (int i = -1; i <= 1; ++i)
                {
                    const int yy = y + j, xx = x + i;
                    if (yy < 0 || xx < 0 || yy >= img.height || xx >= img.width) continue;
                    sum += sharp[static_cast<size_t>(yy) * img.width + xx];
                    ++n;
                }
            const int v = sum / n;
            img.data[static_cast<size_t>(y) * img.stride + x] =
                static_cast<std::uint8_t>(lightOnDark ? 255 - v : v);
        }
    return img;
}

int decode(const Image& img, int flags, std::string& got)
{
    std::int32_t info[EXALTED_DECODE_INFO_LEN] = {};
    std::vector<std::uint8_t> text(4096);
    const int rc = exalted_decode(
        img.data.data(), static_cast<std::int32_t>(img.data.size()),
        img.width, img.height, img.stride,
        EXALTED_FMT_DATAMATRIX, flags, info, EXALTED_DECODE_INFO_LEN,
        text.data(), static_cast<std::int32_t>(text.size()));
    if (rc == 1) got.assign(reinterpret_cast<char*>(text.data()), info[1]);
    return rc;
}

bool textOf(const std::string& file, std::string& out)
{
    // These are known-good payloads confirmed by exalted_decode_test.
    // Some golden-file TEXT headers describe the matrix/codeword fixture,
    // not the decoded payload.
    if (file == "dm_14x14_ABCDEF.txt")
        out = "ABCDEF";
    else if (file == "dm_26x12_123456.txt" ||
             file == "dm_36x16_123456.txt")
        out = "123456";
    else
        return false;

    return true;
}

} // namespace

int main()
{
    // Golden symbols reused from exalted_decode_test.cpp (same directory).
    const char* files[] = {"dm_14x14_ABCDEF.txt", "dm_26x12_123456.txt",
                           "dm_36x16_123456.txt"};
    const int pitches[] = {8, 12, 16, 20};
    bool ok = true;

    for (const char* file : files)
    {
        Symbol s;
        std::string expected;
        if (!load(file, s) || !textOf(file, expected))
        {
            std::cerr << "FAIL: cannot load " << file << "\n";
            ok = false;
            continue;
        }
        for (const bool light : {false, true})
            for (const int pitch : pitches)
            {
                const Image img = renderDots(s, pitch, 4, light);
                std::string got;
                const int plain = decode(img, 1, got);

                int hitFlag = -1;
                for (const int f : kLadder)
                {
                    got.clear();
                    if (decode(img, f, got) == 1 && got == expected) { hitFlag = f; break; }
                }
                const std::string label = std::string(file) + (light ? " light" : " dark ") +
                                          " pitch=" + std::to_string(pitch);
                if (hitFlag < 0)
                {
                    std::cerr << "FAIL: " << label << " (plain rc=" << plain << ")\n";
                    ok = false;
                }
                else
                    std::cout << "PASS: " << label << " flag=" << hitFlag
                              << " (plain decode rc=" << plain << ")\n";
            }
    }

    // No phantom reads: noise and blank frames must stay "no barcode".
    for (const bool noise : {false, true})
    {
        Image img;
        img.width = 640; img.height = 480; img.stride = 640;
        img.data.assign(640 * 480, 200);
        std::uint32_t seed = 12345;
        if (noise)
            for (auto& p : img.data)
            {
                seed = seed * 1664525u + 1013904223u;
                p = static_cast<std::uint8_t>(seed >> 24);
            }
        int phantom = 0;
        for (const int f : kLadder)
        {
            std::string got;
            if (decode(img, f, got) != 0) ++phantom;
        }
        if (phantom) { std::cerr << "FAIL: " << (noise ? "noise" : "blank") << " frame gave " << phantom << " reads\n"; ok = false; }
        else std::cout << "PASS: " << (noise ? "noise" : "blank") << " frame -> no barcode on every dot flag\n";
    }

    if (!ok) { std::cerr << "DOT-PEEN DECODE TEST FAILED\n"; return 1; }
    std::cout << "All dot-peen decode checks passed.\n";
    return 0;
}