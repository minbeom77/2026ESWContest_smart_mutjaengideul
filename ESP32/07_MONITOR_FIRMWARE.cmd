@echo off
chcp 65001 >nul
setlocal
if "%~1"=="" (
  echo Usage: 07_MONITOR_FIRMWARE.cmd COM5
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
echo Exit monitor with Ctrl+]
idf.py -p %~1 monitor
