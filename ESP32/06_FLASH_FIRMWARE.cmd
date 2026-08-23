@echo off
chcp 65001 >nul
setlocal
if "%~1"=="" (
  echo Usage: 06_FLASH_FIRMWARE.cmd COM5
  echo Replace COM5 with the ESP32 port shown by 03_LIST_PORTS.cmd.
  pause
  exit /b 1
)
cd /d "%~dp0firmware"
where idf.py >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Open this from ESP-IDF PowerShell / IDF_PowerShell.
  pause
  exit /b 1
)
idf.py -p %~1 flash
pause
