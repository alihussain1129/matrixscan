@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
cl /nologo /std:c++20 /EHsc /MDd /I include /DEXALTED_GOLDEN_DIR=\"D:/Projects/exalted/cpp/tests/golden\" tests\datamatrix_golden_test.cpp build\Debug\exalted_core.lib /Fobuild\ /Febuild\datamatrix_golden_test.exe
if errorlevel 1 exit /b 1
build\datamatrix_golden_test.exe
