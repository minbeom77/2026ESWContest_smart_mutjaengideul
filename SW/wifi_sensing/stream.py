"""Bounded live input; no implicit replay and no unbounded serial journal."""

from collections import deque
import csv
import json
import math
import threading
import time
import uuid

from core import parse_csi_line
from live_timing import LiveClock
from radio import board_layout


def dummy_frame(t):
    """Synthetic I/Q for plumbing tests only, never an action ground truth."""
    iq = []
    for channel in range(64):
        value = 26 + 8 * math.sin(2 * math.pi * .7 * t + channel * .08)
        iq.extend([round(value), round(12 + 4 * math.sin(t * 17 + channel))])
    return parse_csi_line(json.dumps({
        't': t, 'iq': iq, 'layout': 'c6_ht20_centered64',
        'csi_profile': 'soom_original_csv', 'chip': 'esp32c6',
    }))


class Stream:
    def __init__(self):
        self.lock = threading.RLock()
        self.frames = deque(maxlen=8400)
        self.stop_event = threading.Event()
        self.thread = None
        self.started = time.perf_counter()
        self.session = uuid.uuid4().hex
        self.epoch = 0
        self.mode = 'live'
        self.connected = False
        self.error = '장비를 연결하거나 모의 신호를 시작하세요.'
        self.board = {}
        self.received = 0
        self.rejected = 0

    def now(self):
        return time.perf_counter() - self.started

    def reset(self):
        with self.lock:
            self.frames.clear()
            self.epoch += 1

    def stop(self):
        self.stop_event.set()
        with self.lock:
            self.connected = False
            self.reset()
        if self.thread:
            self.thread.join(timeout=3)
            if self.thread.is_alive():
                raise ValueError('연결 종료 중입니다. 잠시 후 다시 시도하세요.')

    def start(self, mode, device='', baud=921600):
        if mode not in ('live', 'dummy'):
            raise ValueError('실측 또는 모의 신호를 선택하세요.')
        if mode == 'live':
            from serial.tools import list_ports
            if device not in [p.device for p in list_ports.comports()]:
                raise ValueError('선택한 USB 포트가 없습니다.')
            if baud not in (115200, 460800, 921600):
                raise ValueError('지원하지 않는 baud입니다.')
        self.stop()
        self.mode = mode
        self.session = uuid.uuid4().hex
        self.board = {}
        self.received = self.rejected = 0
        self.stop_event.clear()
        self.thread = threading.Thread(
            target=self._dummy if mode == 'dummy' else self._serial,
            args=() if mode == 'dummy' else (device, baud), daemon=True,
        )
        self.thread.start()

    def snapshot(self, max_seconds=None, include_frames=True):
        with self.lock:
            fresh = (self.connected and bool(self.frames)
                     and self.now() - self.frames[-1]['t'] <= .75)
            frames = []
            if fresh and include_frames:
                if max_seconds is None:
                    frames = list(self.frames)
                else:
                    start = self.frames[-1]['t'] - max_seconds
                    for frame in reversed(self.frames):
                        if frame['t'] < start:
                            break
                        frames.append(frame)
                    frames.reverse()
            hardware = 'c6_ht20_soom_input' if self.board.get('mode') == 'espnow' else {
                'esp32': 'router_esp32', 'esp32c3': 'router_c3',
                'esp32s3': 'router_s3',
            }.get(self.board.get('chip'), 'unknown')
            return {
                'frames': frames, 'fresh': bool(fresh),
                'connected': self.connected, 'error': self.error,
                'mode': self.mode, 'session': self.session, 'epoch': self.epoch,
                'received': self.received, 'rejected': self.rejected,
                'hardware': 'synthetic' if self.mode == 'dummy' else hardware,
            }

    def _append(self, frame):
        with self.lock:
            frame['stream_epoch'] = self.epoch
            self.frames.append(frame)
            self.received += 1

    def _dummy(self):
        self.connected = True
        self.error = '모의 신호 · 실제 행동 정확도를 의미하지 않습니다.'
        start = self.now()
        index = 0
        while not self.stop_event.is_set():
            t = start + index / 60
            frame = dummy_frame(t)
            frame['device_t'] = t
            self._append(frame)
            index += 1
            self.stop_event.wait(max(0, start + index / 60 - self.now()))
        self.connected = False

    def _serial_lines(self, port):
        # Serial timeouts may split one CSI line across reads. Preserve fragments,
        # bound noisy input, and check cancellation between short chunk reads.
        pending = bytearray()
        discarding = False
        limit = 65536
        while not self.stop_event.is_set():
            chunk = port.read(max(1, min(port.in_waiting, 8192)))
            if not chunk:
                continue
            pending.extend(chunk)
            while b'\n' in pending and not self.stop_event.is_set():
                line, _, remaining = pending.partition(b'\n')
                pending = bytearray(remaining)
                if discarding:
                    discarding = False
                    continue
                if len(line) > limit:
                    self.rejected += 1
                    continue
                yield line.decode('utf-8', errors='replace').strip()
            if len(pending) > limit:
                pending.clear()
                if not discarding:
                    self.rejected += 1
                discarding = True

    def _serial(self, device, baud):
        import serial
        while not self.stop_event.is_set():
            tracker = LiveClock()
            header = None
            serial_started = self.now()
            try:
                with serial.Serial(device, baud, timeout=.2, write_timeout=1) as port:
                    port.reset_input_buffer()
                    port.write(b'{"cmd":"status"}\n')
                    if self.stop_event.is_set():
                        break
                    with self.lock:
                        self.board = {}
                    self.connected = True
                    self.error = '장치 시간 동기화 중'
                    previous_epoch = tracker.epoch
                    for line in self._serial_lines(port):
                        if not line:
                            continue
                        try:
                            event = json.loads(line)
                        except ValueError:
                            event = None
                        if isinstance(event, dict) and event.get('event') == 'status':
                            with self.lock:
                                for key in ('mode', 'chip', 'firmware', 'role'):
                                    if isinstance(event.get(key), str):
                                        self.board[key] = event[key]
                            continue
                        if 'data' in line and '[' not in line:
                            header = next(csv.reader([line]), [])
                            continue
                        now = self.now()
                        frame = parse_csi_line(line, header, now, board_layout(self.board))
                        if frame is None:
                            self.rejected += 1
                            continue
                        if frame.get('csi_profile') == 'soom_original_csv':
                            self.board.update(mode='espnow', chip='esp32c6', firmware='SOOM-original-csv')
                            tracker.arrival_jitter = .75
                        device_t = frame['t']
                        mapped = tracker.map_time(device_t, now - serial_started)
                        if tracker.epoch != previous_epoch:
                            self.reset()
                            previous_epoch = tracker.epoch
                        if frame.get('csi_profile') == 'c6_espnow_ht20_v1' and not frame.get('gain_ready'):
                            mapped = None
                        if mapped is not None:
                            frame.update(t=mapped + serial_started, device_t=device_t)
                            frame.pop('raw_line', None)
                            self._append(frame)
                            self.error = ''
            except (OSError, serial.SerialException) as exc:
                self.error = f'USB 연결 대기: {exc}'
            finally:
                self.connected = False
                self.reset()
            self.stop_event.wait(2)
