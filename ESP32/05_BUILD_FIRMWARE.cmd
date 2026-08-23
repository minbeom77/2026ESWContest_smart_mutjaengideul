@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0firmware"
where idf.py >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Open this from ESP-IDF PowerShell / IDF_PowerShell.
  pause
  exit /b 1
)
idf.py build
echo.
if errorlevel 1 (
  echo [ERROR] Build failed. Copy the last error lines and send them to ChatGPT.
) else (
  echo [OK] Build complete. Next: 03_LIST_PORTS.cmd, then 06_FLASH_FIRMWARE.cmd COMx
)
pause
