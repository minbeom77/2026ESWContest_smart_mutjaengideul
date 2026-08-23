\
    $ErrorActionPreference = "Stop"
    Set-Location $PSScriptRoot
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw "Python launcher 'py' not found. Install Python 3.10+ first."
    }
    if (-not (Test-Path ".venv")) {
        py -3 -m venv .venv
    }
    & .\.venv\Scripts\python.exe -m pip install --upgrade pip
    & .\.venv\Scripts\python.exe -m pip install -r requirements.txt
    Write-Host "설치 완료"
    Write-Host "포트 확인: .\.venv\Scripts\python.exe list_ports.py"
    Write-Host "데모 실행: .\.venv\Scripts\python.exe csi_capture.py --demo"
