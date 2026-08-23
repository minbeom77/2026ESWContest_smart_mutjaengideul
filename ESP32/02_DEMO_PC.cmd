@echo off
chcp 65001 >nul
cd /d "%~dp0pc"
if not exist .venv\Scripts\python.exe (
  echo [ERROR] Run 01_SETUP_PC.cmd first.
  pause
  exit /b 1
)
.venv\Scripts\python.exe csi_capture.py --demo
