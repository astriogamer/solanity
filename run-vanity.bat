@echo off
echo ========================================
echo Solana Vanity Address Generator
echo ========================================
echo.

REM Check if executable exists
if not exist "src\release\cuda_ed25519_vanity.exe" (
    echo ERROR: cuda_ed25519_vanity.exe not found!
    echo Please run build.bat first to compile the project.
    echo.
    pause
    exit /b 1
)

REM Copy config file if it exists in root
if exist "vanity-config.json" (
    echo Copying vanity-config.json to executable directory...
    copy /Y "vanity-config.json" "src\release\" >nul
    echo.
)

REM Run the vanity generator
cd src\release
echo Starting vanity address generator...
echo.
cuda_ed25519_vanity.exe

echo.
echo ========================================
echo Generator stopped
echo ========================================
pause
