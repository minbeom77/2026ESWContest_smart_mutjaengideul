@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0pc"
set "PYEXE="
where py >nul 2>&1 && set "PYEXE=py -3"
if not defined PYEXE (
  where python >nul 2>&1 && set "PYEXE=python"
)
if not defined PYEXE (
  echo [ERROR] Python 3 was not found.
  echo Install Python 3.10+ for Windows, then run this file again.
  pause
  exit /b 1
)
if not exist .venv %PYEXE% -m venv .venv
if errorlevel 1 exit /b 1
.venv\Scripts\python.exe -m pip install --upgrade pip
if errorlevel 1 exit /b 1
.venv\Scripts\python.exe -m pip install -r requirements.txt
if errorlevel 1 exit /b 1
echo.
echo [OK] PC Python environment is ready.
echo Next: run 02_DEMO_PC.cmd
pause
