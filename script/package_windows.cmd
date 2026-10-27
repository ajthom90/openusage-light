@echo off
rem Builds the Windows programs in release mode and zips them with the runtime libraries they need, so the
rem zip runs on a PC with no Swift installed: dist\OpenUsageLight-windows-<arch>.zip (arch is x64 or arm64).
rem
rem Run from the repository root in a prompt where Swift and the Visual Studio build tools are set up (a
rem "Native Tools" prompt, or after vcvarsall.bat for the architecture you are building for).
setlocal

set ARCH=x64
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set ARCH=arm64
set NAME=OpenUsageLight-windows-%ARCH%

echo ==^> swift build (release, %ARCH%)
swift build -c release --product OpenUsageLight || exit /b 1
swift build -c release --product openusage || exit /b 1
for /f "delims=" %%B in ('swift build -c release --show-bin-path') do set BIN=%%B

set STAGE=dist\%NAME%
if exist "%STAGE%" rmdir /s /q "%STAGE%"
if exist "dist\%NAME%.zip" del /q "dist\%NAME%.zip"
mkdir "%STAGE%" || exit /b 1

echo ==^> staging %STAGE%
copy /y "%BIN%\OpenUsageLight.exe" "%STAGE%\" >nul || exit /b 1
copy /y "%BIN%\openusage.exe" "%STAGE%\" >nul || exit /b 1

rem The Swift runtime: every library in the folder swiftCore.dll is found in.
set RUNTIME=
for /f "delims=" %%D in ('where swiftCore.dll 2^>nul') do if not defined RUNTIME set "RUNTIME=%%~dpD"
if not defined RUNTIME (
  echo swiftCore.dll is not on PATH; cannot find the Swift runtime to bundle. >&2
  exit /b 1
)
copy /y "%RUNTIME%*.dll" "%STAGE%\" >nul || exit /b 1

rem The Microsoft C runtime, shipped beside the program ("app-local") for PCs without the redistributable.
for %%C in (vcruntime140.dll vcruntime140_1.dll msvcp140.dll concrt140.dll) do (
  if exist "%SystemRoot%\System32\%%C" copy /y "%SystemRoot%\System32\%%C" "%STAGE%\" >nul
)

echo ==^> zipping dist\%NAME%.zip
tar -a -cf "dist\%NAME%.zip" -C dist "%NAME%" || exit /b 1
echo done: dist\%NAME%.zip
endlocal
