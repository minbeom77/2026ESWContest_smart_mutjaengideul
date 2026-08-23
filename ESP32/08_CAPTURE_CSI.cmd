@echo off
chcp 65001 >nul
setlocal
if "%~1"=="" (
  echo Usage: 08_CAPTURE_CSI.cmd COM5 [label] [seconds]
  echo Example: 08_CAPTURE_CSI.cmd COM5 moving 60
  pause
  exit /b 1
)
set PORT=%~1
set LABEL=%~2
set SECONDS=%~3
if "%LABEL%"=="" set LABEL=first_test
cd /d "%~dp0pc"
if not exist .venv\Scripts\python.exe (
  echo [ERROR] Run 01_SETUP_PC.cmd first.
  pause
  exit /b 1
)
if "%SECONDS%"=="" (
  .venv\Scripts\python.exe csi_capture.py --port %PORT% --baud 921600 --label %LABEL%
) else (
  .venv\Scripts\python.exe csi_capture.py --port %PORT% --baud 921600 --label %LABEL% --duration %SECONDS%
)
