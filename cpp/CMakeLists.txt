cmake_minimum_required(VERSION 3.20)

project(exalted_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

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

add_subdirectory(tests)
