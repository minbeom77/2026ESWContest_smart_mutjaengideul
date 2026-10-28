"""Operator event controller. Does not read CSI or produce model metrics."""
import json
from pathlib import Path
import queue
import socket
import struct
import threading
import time
import tkinter as tk
from tkinter import ttk
import uuid


TOPIC = 'safehub/csi/bedroom/event'


def envelope(fall, now=None):
    return {
        'message_id': str(uuid.uuid4()),
        'device': 'safehub_manual_demo',
        'event': 'fall_detected' if fall else 'normal',
        'confidence': 0.0,  # No measured model score exists for a manual event.
        'priority': 9 if fall else 1,
        'timestamp': int(time.time() if now is None else now),
    }


def string(value):
    raw = value.encode('utf-8')
    return struct.pack('!H', len(raw)) + raw


def packet(kind, body):
    size, encoded = len(body), bytearray()
    while True:
        part = size % 128
        size //= 128
        encoded.append(part | (128 if size else 0))
        if not size:
            break
    return bytes([kind]) + bytes(encoded) + body


def read_exact(connection, count):
    data = bytearray()
    while len(data) < count:
        block = connection.recv(count - len(data))
        if not block:
            raise ConnectionError('MQTT 연결이 종료됐어요.')
        data.extend(block)
    return bytes(data)


def read_packet(connection):
    kind = read_exact(connection, 1)[0]
    size, multiplier = 0, 1
    for _ in range(4):
        value = read_exact(connection, 1)[0]
        size += (value & 127) * multiplier
        if not value & 128:
            if size > 65536:
                raise ConnectionError('응답 패킷이 너무 큽니다.')
            return kind, read_exact(connection, size)
        multiplier *= 128
    raise ConnectionError('잘못된 MQTT 응답입니다.')


def publish(host, port, payload):
    with socket.create_connection((host, port), timeout=4) as connection:
        connection.settimeout(4)
        connect = string('MQTT') + bytes([4, 2]) + struct.pack('!H', 15)
        connect += string('safehub-demo-' + uuid.uuid4().hex[:12])
        connection.sendall(packet(0x10, connect))
        kind, reply = read_packet(connection)
        if kind != 0x20 or reply != b'\x00\x00':
            raise ConnectionError('MQTT 서버가 연결을 승인하지 않았어요.')
        body = string(TOPIC) + b'\x00\x01'
        body += json.dumps(payload, ensure_ascii=False).encode('utf-8')
        # QoS 1, retain false: commands are never replayed on app startup.
        connection.sendall(packet(0x32, body))
        kind, reply = read_packet(connection)
        if kind != 0x40 or reply != b'\x00\x01':
            raise ConnectionError('MQTT 수신 확인이 오지 않았어요.')
        connection.sendall(b'\xe0\x00')


def main():
    root = tk.Tk()
    root.title('SafeHub · 낙상 이벤트 리모컨')
    root.geometry('660x480')
    root.minsize(600, 440)
    root.configure(bg='#f7f5f2')
    style = ttk.Style(root)
    style.configure('TLabel', background='#f7f5f2', font=('맑은 고딕', 12))
    panel = ttk.Frame(root, padding=24)
    panel.pack(fill='both', expand=True)
    ttk.Label(panel, text='SafeHub 이벤트 리모컨', font=('맑은 고딕', 23, 'bold')).pack(anchor='w')
    ttk.Label(panel, text='연동 시연용 입력 · 실제 CSI 측정/학습과 분리').pack(anchor='w', pady=(8, 18))
    row = ttk.Frame(panel)
    row.pack(fill='x')
    ttk.Label(row, text='Pi5 주소').pack(side='left')
    host = tk.StringVar(value='172.20.47.16')
    port = tk.StringVar(value='1883')
    ttk.Entry(row, textvariable=host, width=30, font=('맑은 고딕', 13)).pack(side='left', padx=8)
    ttk.Entry(row, textvariable=port, width=6, font=('맑은 고딕', 13)).pack(side='left')
    status = tk.StringVar(value='노트북과 Pi5가 같은 네트워크에 연결되어 있어야 해요.')
    results = queue.Queue()
    buttons = []

    def send(fall):
        address = host.get().strip()
        try:
            number = int(port.get())
            if not address or not 1 <= number <= 65535:
                raise ValueError()
        except ValueError:
            status.set('Pi5 주소와 포트 번호를 확인해 주세요.')
            return
        for button in buttons:
            button.configure(state='disabled')
        status.set('전송 중…')
        payload = envelope(fall)

        def worker():
            try:
                publish(address, number, payload)
                with (Path(__file__).parent / 'operator-events.jsonl').open('a', encoding='utf-8') as log:
                    log.write(json.dumps(payload, ensure_ascii=False) + '\n')
                results.put('낙상 이벤트 전송 확인 · 화면/장치 반응을 확인하세요.' if fall
                            else '평상시 복귀 전송 확인 · 리모컨 낙상 경고만 종료해요.')
            except Exception as error:
                results.put('실패: ' + str(error))
        threading.Thread(target=worker, daemon=True).start()

    for title, fall, color in [('낙상 이벤트 보내기', True, '#8d2345'),
                               ('평상시로 복귀', False, '#315e55')]:
        button = tk.Button(panel, text=title, command=lambda f=fall: send(f),
                           font=('맑은 고딕', 22, 'bold'), bg=color, fg='white',
                           activebackground=color, activeforeground='white',
                           relief='flat', pady=15, cursor='hand2')
        button.pack(fill='x', pady=(16, 0))
        buttons.append(button)
    ttk.Label(panel, textvariable=status, wraplength=600).pack(anchor='w', pady=18)

    def poll():
        try:
            status.set(results.get_nowait())
            for button in buttons:
                button.configure(state='normal')
        except queue.Empty:
            pass
        root.after(100, poll)
    poll()
    root.mainloop()


if __name__ == '__main__':
    main()
