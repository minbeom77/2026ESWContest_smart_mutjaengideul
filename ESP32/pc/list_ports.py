#!/usr/bin/env python3
from serial.tools import list_ports

ports = list(list_ports.comports())
if not ports:
    print("사용 가능한 시리얼 포트를 찾지 못했습니다.")
else:
    print("사용 가능한 시리얼 포트:")
    for item in ports:
        print(f"  {item.device:16} {item.description} [{item.hwid}]")
