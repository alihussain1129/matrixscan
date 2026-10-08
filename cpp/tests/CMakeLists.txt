cmake_minimum_required(VERSION 3.22.1)

project(datamatrix_symbol_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(
    datamatrix_symbol_test
    datamatrix_symbol_test.cpp
    ../src/datamatrix_symbol.cpp
)

target_include_directories(
    datamatrix_symbol_test
    PRIVATE
    ../include
)

add_executable(
    datamatrix_symbol_info_test
    datamatrix_symbol_info_test.cpp
    ../src/datamatrix_symbol_info.cpp
)

target_include_directories(
    datamatrix_symbol_info_test
    PRIVATE
    ../include
)

add_executable(
    datamatrix_placement_test
    datamatrix_placement_test.cpp
    ../src/datamatrix_placement.cpp
    ../src/datamatrix_traversal.cpp
    ../src/bit_matrix.cpp
    ../src/datamatrix_symbol_info.cpp
)

target_include_directories(
    datamatrix_placement_test
    PRIVATE
    ../include
)

add_executable(
    datamatrix_traversal_test
    datamatrix_traversal_test.cpp
    ../src/datamatrix_traversal.cpp
    ../src/bit_matrix.cpp
)

target_include_directories(
    datamatrix_traversal_test
    PRIVATE
    ../include
)
