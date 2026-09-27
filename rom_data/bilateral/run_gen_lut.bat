@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\gen_bilateral_lut.ps1"
echo.
echo Done. Press any key to close...
pause >nul
