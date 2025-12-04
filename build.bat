@echo off
echo ========================================
echo Building Solana Vanity Address Generator
echo ========================================
echo.

REM Set build mode (release or debug)
set BUILD_MODE=release

REM Navigate to src directory and build
echo Building in %BUILD_MODE% mode...
cd src
make V=%BUILD_MODE%

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================
    echo BUILD FAILED!
    echo ========================================
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================
echo BUILD SUCCESSFUL!
echo ========================================
echo.
echo Executable location: src\%BUILD_MODE%\cuda_ed25519_vanity.exe
echo.
echo To run the vanity generator:
echo   cd src\%BUILD_MODE%
echo   cuda_ed25519_vanity.exe
echo.
echo Or copy vanity-config.json to src\%BUILD_MODE%\ and run from there
echo ========================================
pause
