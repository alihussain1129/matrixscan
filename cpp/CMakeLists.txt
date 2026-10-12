cmake_minimum_required(VERSION 3.20)

project(exalted_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Flutter debug builds compile native code at -O0; a decoder at -O0 is far
# too slow to judge on a phone. Keep optimisation on for Android debug builds.
if(ANDROID)
    set(CMAKE_CXX_FLAGS_DEBUG "-O2 -g0" CACHE STRING "" FORCE)
    set(CMAKE_C_FLAGS_DEBUG "-O2 -g0" CACHE STRING "" FORCE)
endif()

# ---- zxing-cpp (vendored, readers only) -----------------------------------
set(ZXING_READERS ON CACHE BOOL "" FORCE)
set(ZXING_WRITERS OFF CACHE STRING "" FORCE)
set(ZXING_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ZXING_BLACKBOX_TESTS OFF CACHE BOOL "" FORCE)
set(ZXING_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(ZXING_C_API OFF CACHE BOOL "" FORCE)
set(ZXING_PYTHON_MODULE OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/zxing-cpp EXCLUDE_FROM_ALL)

# ---- EXALTED C++ core (encoder, placement, decoder abstraction) ------------
add_library(exalted_core
    src/decode_result.cpp
    src/decoder.cpp
    src/datamatrix_decoder.cpp
    src/bit_matrix.cpp
    src/datamatrix_symbol.cpp
    src/datamatrix_symbol_info.cpp
    src/datamatrix_traversal.cpp
    src/datamatrix_placement.cpp
    src/datamatrix_encoder.cpp
)

target_include_directories(exalted_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# ---- Shared library loaded by Flutter through dart:ffi ---------------------
# Android: libexalted_ffi.so
add_library(exalted_ffi SHARED
    src/ffi_api.cpp
)

target_link_libraries(exalted_ffi
    PRIVATE
        exalted_core
        ZXing::ZXing
)

# ---- Desktop-only test executables (not built for Android) -----------------
if(NOT ANDROID)
    add_executable(utah_test
        utah_test.cpp
    )

    target_link_libraries(utah_test
        PRIVATE
            exalted_core
    )

    add_executable(datamatrix_encoder_test
        tests/datamatrix_encoder_test.cpp
    )

    target_link_libraries(datamatrix_encoder_test
        PRIVATE
            exalted_core
    )

    # Native decode test: same C function the app calls, on the golden symbols.
    add_executable(exalted_decode_test
        tests/exalted_decode_test.cpp
        src/ffi_api.cpp
    )

    target_include_directories(exalted_decode_test
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/include
    )

    target_link_libraries(exalted_decode_test
        PRIVATE
            ZXing::ZXing
    )

    target_compile_definitions(exalted_decode_test
        PRIVATE
            EXALTED_GOLDEN_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/golden"
    )

    # Dot-peen decode test: synthetic dot-peened symbols through exalted_decode.
    add_executable(exalted_dotpeen_test
        tests/exalted_dotpeen_test.cpp
        src/ffi_api.cpp
    )

    target_include_directories(exalted_dotpeen_test
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/include
    )

    target_link_libraries(exalted_dotpeen_test
        PRIVATE
            ZXing::ZXing
    )

    target_compile_definitions(exalted_dotpeen_test
        PRIVATE
            EXALTED_GOLDEN_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/golden"
    )
    add_subdirectory(tests)
endif()
