@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0firmware"
where idf.py >nul 2>&1
if errorlevel 1 (
  echo [ERROR] idf.py was not found.
  echo Open this project from the ESP-IDF PowerShell / IDF_PowerShell installed by EIM.
  pause
  exit /b 1
)
idf.py set-target esp32
if errorlevel 1 exit /b 1
idf.py menuconfig
