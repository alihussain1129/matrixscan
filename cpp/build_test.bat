@echo off
cd /d d:\Projects\exalted\cpp
rmdir /s /q build 2>nul
mkdir build
"C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" -S . -B build -G "Visual Studio 18 2026" -A x64
if errorlevel 1 exit /b 1
"C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build build --config Debug --target datamatrix_encoder_test
if errorlevel 1 exit /b 1
build\Debug\datamatrix_encoder_test.exe
if errorlevel 1 exit /b 1
