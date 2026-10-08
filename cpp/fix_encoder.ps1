# Build and run tests
cd d:\Projects\exalted\cpp
rmdir /s /q build 2>nul
mkdir build
& "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" -S . -B build -G "Visual Studio 18 2026" -A x64
