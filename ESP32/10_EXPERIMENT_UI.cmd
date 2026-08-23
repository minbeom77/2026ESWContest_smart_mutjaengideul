@echo off
setlocal
cd /d "%~dp0pc"
if not exist .venv\Scripts\python.exe (
  echo [ERROR] Run 01_SETUP_PC.cmd first.
  pause
  exit /b 1
)
title ESP32 Wi-Fi CSI Experiment UI
.venv\Scripts\python.exe experiment_ui.py
if errorlevel 1 (
  echo.
  echo [ERROR] Experiment UI stopped with an error.
  pause
)
