@echo off
chcp 65001 >nul
cd /d "%~dp0pc"
if not exist .venv\Scripts\python.exe (
  echo [ERROR] Run 01_SETUP_PC.cmd first.
  pause
  exit /b 1
)
.venv\Scripts\python.exe list_ports.py
echo.
echo Look for COM3, COM4, COM5, etc. that appears when the ESP32 is connected.
pause
