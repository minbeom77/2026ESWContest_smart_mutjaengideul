#!/usr/bin/env python3
"""Capture ESP32 CSI CSV output, save it, and show live diagnostics.

Works with this starter firmware for the classic ESP32 / ESP-WROOM-32.
Run with --demo before connecting hardware.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import queue
import random
import signal
import sys
import threading
import time
from collections import Counter, deque
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from io import StringIO
from typing import Iterable, Optional

import numpy as np

try:
    import serial
except ImportError:  # pragma: no cover
    serial = None


@dataclass(slots=True)
class CSIFrame:
    host_time: float
    seq: int
    mac: str
    rssi: int
    rate: int
    noise_floor: int
    channel: int
    device_timestamp: int
    sig_len: int
    rx_format: int
    reported_len: int
    first_word_invalid: int
    data: list[int]

    def amplitude_db_centered(self) -> np.ndarray:
        values = np.asarray(self.data, dtype=np.float64)
        usable = values.size - (values.size % 2)
        if usable < 2:
            return np.empty(0, dtype=np.float64)
        values = values[:usable]
        imag = values[0::2]
        real = values[1::2]
        amplitude = np.hypot(real, imag)
        amplitude_db = 20.0 * np.log10(amplitude + 1e-9)
        return amplitude_db - np.median(amplitude_db)


class CSIParser:
    """Parse CSI CSV lines with a header-aware and headerless fallback."""

    def __init__(self) -> None:
        self.header: Optional[list[str]] = None

    @staticmethod
    def _as_int(value: object, default: int = 0) -> int:
        try:
            return int(str(value).strip())
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _parse_data(text: str) -> list[int]:
        text = text.strip()
        try:
            raw = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid CSI array: {exc}") from exc
        if not isinstance(raw, list):
            raise ValueError("CSI data field is not a list")
        return [int(value) for value in raw]

    def parse(self, line: str, host_time: Optional[float] = None) -> Optional[CSIFrame]:
        line = line.strip()
        if not line:
            return None

        try:
            row = next(csv.reader([line]))
        except csv.Error:
            return None

        if not row:
            return None

        if row[0] == "type":
            self.header = [item.strip() for item in row]
            return None

        if row[0] != "CSI_DATA" or len(row) < 8:
            return None

        values: dict[str, str] = {}
        if self.header and len(self.header) == len(row):
            values = dict(zip(self.header, row))

        try:
            data = self._parse_data(row[-1])
        except ValueError:
            return None

        # Common fields used by the starter firmware.
        seq = self._as_int(values.get("seq", row[1]))
        mac = values.get("mac", row[2]).strip()
        rssi = self._as_int(values.get("rssi", row[3]))
        rate = self._as_int(values.get("rate", row[4]))
        noise_floor = self._as_int(values.get("noise_floor", 0))
        reported_len = self._as_int(values.get("len", row[-3]), len(data))
        first_word = self._as_int(values.get("first_word", row[-2]))

        if values:
            channel = self._as_int(values.get("channel", 0))
            device_timestamp = self._as_int(values.get("local_timestamp", 0))
            sig_len = self._as_int(values.get("sig_len", 0))
            rx_format = self._as_int(
                values.get("rx_format", values.get("rx_state", 0))
            )
        elif len(row) == 13:  # This starter firmware.
            channel = self._as_int(row[6])
            device_timestamp = self._as_int(row[7])
            sig_len = self._as_int(row[8])
            rx_format = self._as_int(row[9])
        elif len(row) == 15:  # Espressif C5/C6 current example.
            channel = self._as_int(row[8])
            device_timestamp = self._as_int(row[9])
            sig_len = self._as_int(row[10])
            rx_format = self._as_int(row[11])
        else:
            channel = 0
            device_timestamp = 0
            sig_len = 0
            rx_format = 0

        if reported_len > 0 and len(data) > reported_len:
            data = data[:reported_len]

        return CSIFrame(
            host_time=time.time() if host_time is None else host_time,
            seq=seq,
            mac=mac,
            rssi=rssi,
            rate=rate,
            noise_floor=noise_floor,
            channel=channel,
            device_timestamp=device_timestamp,
            sig_len=sig_len,
            rx_format=rx_format,
            reported_len=reported_len,
            first_word_invalid=first_word,
            data=data,
        )


class FrameSource:
    def read_line(self) -> str:
        raise NotImplementedError

    def close(self) -> None:
        pass


class SerialFrameSource(FrameSource):
    def __init__(self, port: str, baud: int) -> None:
        if serial is None:
            raise RuntimeError("pyserial is not installed")

        # Configure DTR/RTS before opening the port. Some CH340-based ESP32
        # boards otherwise remain in reset when a plain pyserial client opens
        # the port, even though idf.py monitor works correctly.
        self.serial = serial.Serial()
        self.serial.port = port
        self.serial.baudrate = baud
        self.serial.timeout = 0.5
        self.serial.dtr = False
        self.serial.rts = False
        self.serial.open()

        # Pulse EN through RTS while keeping GPIO0 high through DTR. This boots
        # the application normally and gives Wi-Fi time to reconnect before
        # stale startup output is discarded.
        self.serial.dtr = False
        self.serial.rts = True
        time.sleep(0.1)
        self.serial.rts = False
        time.sleep(5.0)
        self.serial.reset_input_buffer()

    def read_line(self) -> str:
        raw = self.serial.readline()
        return raw.decode("utf-8", errors="ignore")

    def close(self) -> None:
        if self.serial.is_open:
            self.serial.close()


class DemoFrameSource(FrameSource):
    """Generate synthetic CSI-like frames to verify the PC software."""

    def __init__(self, rate_hz: float = 30.0, subcarriers: int = 64) -> None:
        self.period = 1.0 / rate_hz
        self.subcarriers = subcarriers
        self.seq = 0
        self.start = time.monotonic()
        self.next_time = time.monotonic()
        self.header_sent = False

    def read_line(self) -> str:
        now = time.monotonic()
        if now < self.next_time:
            time.sleep(self.next_time - now)
        self.next_time += self.period

        if not self.header_sent:
            self.header_sent = True
            return (
                "type,seq,mac,rssi,rate,noise_floor,channel,local_timestamp,"
                "sig_len,rx_format,len,first_word,data\n"
            )

        elapsed = time.monotonic() - self.start
        # Every 12 seconds: quiet -> small movement -> large movement.
        phase = int(elapsed // 4.0) % 3
        movement = (0.15, 0.8, 2.2)[phase]
        values: list[int] = []
        for index in range(self.subcarriers):
            angle = index * 0.17 + elapsed * (0.15 + movement * 0.25)
            amp = 25.0 + 5.0 * math.sin(index * 0.11)
            amp += movement * 4.0 * math.sin(elapsed * 3.0 + index * 0.07)
            amp += random.gauss(0.0, 0.4)
            imag = int(np.clip(amp * math.sin(angle), -127, 127))
            real = int(np.clip(amp * math.cos(angle), -127, 127))
            values.extend((imag, real))

        row = [
            "CSI_DATA",
            str(self.seq),
            "aa:bb:cc:dd:ee:ff",
            str(-42 + random.randint(-1, 1)),
            "11",
            "-95",
            "6",
            str(int(elapsed * 1_000_000)),
            "64",
            "1",
            str(len(values)),
            "0",
            json.dumps(values, separators=(",", ":")),
        ]
        self.seq += 1
        buffer = StringIO()
        csv.writer(buffer, lineterminator="\n").writerow(row)
        return buffer.getvalue()


class CaptureWriter:
    FIELDNAMES = [
        "host_time_iso",
        "host_time_unix",
        "label",
        "seq",
        "mac",
        "rssi",
        "rate",
        "noise_floor",
        "channel",
        "device_timestamp",
        "sig_len",
        "rx_format",
        "reported_len",
        "first_word_invalid",
        "data_json",
    ]

    def __init__(self, path: Path, label: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.label = label
        self.handle = path.open("w", newline="", encoding="utf-8")
        self.writer = csv.DictWriter(self.handle, fieldnames=self.FIELDNAMES)
        self.writer.writeheader()
        self.count = 0

    def write(self, frame: CSIFrame) -> None:
        instant = datetime.fromtimestamp(frame.host_time, tz=timezone.utc)
        self.writer.writerow(
            {
                "host_time_iso": instant.isoformat(),
                "host_time_unix": f"{frame.host_time:.6f}",
                "label": self.label,
                "seq": frame.seq,
                "mac": frame.mac,
                "rssi": frame.rssi,
                "rate": frame.rate,
                "noise_floor": frame.noise_floor,
                "channel": frame.channel,
                "device_timestamp": frame.device_timestamp,
                "sig_len": frame.sig_len,
                "rx_format": frame.rx_format,
                "reported_len": frame.reported_len,
                "first_word_invalid": frame.first_word_invalid,
                "data_json": json.dumps(frame.data, separators=(",", ":")),
            }
        )
        self.count += 1
        if self.count % 100 == 0:
            self.handle.flush()

    def close(self) -> None:
        self.handle.flush()
        self.handle.close()


class LivePlot:
    def __init__(self, history: int = 240) -> None:
        import matplotlib.pyplot as plt

        self.plt = plt
        self.history = history
        self.amplitudes: deque[np.ndarray] = deque(maxlen=history)
        self.scores: deque[float] = deque(maxlen=history)
        self.times: deque[float] = deque(maxlen=history)
        self.previous: Optional[np.ndarray] = None
        self.current_length: Optional[int] = None

        self.heat_figure = plt.figure("CSI amplitude heatmap")
        self.heat_axis = self.heat_figure.add_axes((0.10, 0.12, 0.84, 0.80))
        self.heat_image = None

        self.score_figure = plt.figure("CSI movement score")
        self.score_axis = self.score_figure.add_axes((0.12, 0.14, 0.82, 0.78))
        (self.score_line,) = self.score_axis.plot([], [])
        self.score_axis.set_xlabel("Seconds")
        self.score_axis.set_ylabel("Mean frame-to-frame change (dB)")
        self.score_axis.grid(True, alpha=0.3)

        plt.ion()
        plt.show(block=False)

    def add(self, frame: CSIFrame) -> None:
        amplitude = frame.amplitude_db_centered()
        if amplitude.size == 0:
            return

        if self.current_length != amplitude.size:
            self.current_length = amplitude.size
            self.amplitudes.clear()
            self.scores.clear()
            self.times.clear()
            self.previous = None

        score = 0.0
        if self.previous is not None and self.previous.size == amplitude.size:
            score = float(np.mean(np.abs(amplitude - self.previous)))
        self.previous = amplitude

        self.amplitudes.append(amplitude)
        self.scores.append(score)
        self.times.append(frame.host_time)

    def update(self) -> bool:
        if not self.plt.fignum_exists(self.heat_figure.number):
            return False
        if not self.plt.fignum_exists(self.score_figure.number):
            return False
        if not self.amplitudes:
            self.plt.pause(0.001)
            return True

        matrix = np.vstack(self.amplitudes)
        if self.heat_image is None or self.heat_image.get_array().shape != matrix.shape:
            self.heat_axis.clear()
            self.heat_axis.set_xlabel("Subcarrier index")
            self.heat_axis.set_ylabel("Recent frame")
            self.heat_axis.set_title("Per-frame median-normalized CSI amplitude")
            self.heat_image = self.heat_axis.imshow(
                matrix,
                aspect="auto",
                origin="lower",
                interpolation="nearest",
            )
        else:
            self.heat_image.set_data(matrix)
        finite = matrix[np.isfinite(matrix)]
        if finite.size:
            low, high = np.percentile(finite, [5, 95])
            if high > low:
                self.heat_image.set_clim(low, high)

        base_time = self.times[0]
        x_values = np.asarray(self.times) - base_time
        y_values = np.asarray(self.scores)
        self.score_line.set_data(x_values, y_values)
        self.score_axis.relim()
        self.score_axis.autoscale_view()
        self.score_axis.set_title(
            f"Movement score — latest {y_values[-1]:.3f} dB"
        )

        self.heat_figure.canvas.draw_idle()
        self.score_figure.canvas.draw_idle()
        self.plt.pause(0.001)
        return True

    def close(self) -> None:
        self.plt.close("all")


def build_output_path(output_dir: Path, label: str) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_label = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in label)
    suffix = f"_{safe_label}" if safe_label else ""
    return output_dir / f"csi_{timestamp}{suffix}.csv"


def reader_worker(
    source: FrameSource,
    output_queue: queue.Queue[CSIFrame],
    stop_event: threading.Event,
    counters: Counter,
) -> None:
    parser = CSIParser()
    while not stop_event.is_set():
        try:
            line = source.read_line()
        except Exception as exc:  # Serial disconnects should stop cleanly.
            counters["source_errors"] += 1
            print(f"\n[오류] 입력 장치 읽기 실패: {exc}", file=sys.stderr)
            stop_event.set()
            break

        if not line:
            continue
        counters["lines"] += 1
        frame = parser.parse(line)
        if frame is None:
            if line.startswith("CSI_DATA"):
                counters["parse_errors"] += 1
            continue

        counters["parsed"] += 1
        try:
            output_queue.put_nowait(frame)
        except queue.Full:
            counters["pc_queue_drops"] += 1
            try:
                output_queue.get_nowait()
            except queue.Empty:
                pass
            try:
                output_queue.put_nowait(frame)
            except queue.Full:
                pass


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="ESP32-C6 router CSI capture and live plot"
    )
    parser.add_argument("--port", help="Serial port, e.g. COM5")
    parser.add_argument("--baud", type=int, default=921_600)
    parser.add_argument("--duration", type=float, default=0.0, help="Seconds; 0 = until Ctrl+C")
    parser.add_argument("--label", default="unlabeled", help="Session label saved in CSV")
    parser.add_argument("--output-dir", type=Path, default=Path("sessions"))
    parser.add_argument("--no-plot", action="store_true")
    parser.add_argument("--demo", action="store_true", help="Use synthetic data")
    parser.add_argument("--demo-rate", type=float, default=30.0)
    return parser.parse_args(argv)


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)
    if not args.demo and not args.port:
        print("--port가 필요합니다. 먼저 'python list_ports.py'를 실행하세요.", file=sys.stderr)
        return 2

    source: FrameSource
    if args.demo:
        source = DemoFrameSource(rate_hz=args.demo_rate)
        source_name = "demo"
    else:
        source = SerialFrameSource(args.port, args.baud)
        source_name = f"{args.port} @ {args.baud}"

    output_path = build_output_path(args.output_dir, args.label)
    writer = CaptureWriter(output_path, args.label)
    live_plot = None if args.no_plot else LivePlot()

    stop_event = threading.Event()
    frame_queue: queue.Queue[CSIFrame] = queue.Queue(maxsize=5000)
    counters: Counter = Counter()
    worker = threading.Thread(
        target=reader_worker,
        args=(source, frame_queue, stop_event, counters),
        daemon=True,
    )

    def request_stop(signum: int, frame: object) -> None:
        del signum, frame
        stop_event.set()

    signal.signal(signal.SIGINT, request_stop)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, request_stop)

    print(f"입력: {source_name}")
    print(f"저장: {output_path.resolve()}")
    print("중지: Ctrl+C")

    start = time.monotonic()
    last_status = start
    first_seq: Optional[int] = None
    last_seq: Optional[int] = None
    lengths: Counter = Counter()

    worker.start()
    try:
        while not stop_event.is_set():
            now = time.monotonic()
            if args.duration > 0 and now - start >= args.duration:
                stop_event.set()
                break

            processed = 0
            while processed < 1000:
                try:
                    frame = frame_queue.get_nowait()
                except queue.Empty:
                    break
                writer.write(frame)
                lengths[len(frame.data)] += 1
                first_seq = frame.seq if first_seq is None else first_seq
                last_seq = frame.seq
                if live_plot is not None:
                    live_plot.add(frame)
                processed += 1

            if live_plot is not None and not live_plot.update():
                stop_event.set()
                break
            if live_plot is None:
                time.sleep(0.01)

            if now - last_status >= 2.0:
                elapsed = max(now - start, 1e-9)
                fps = writer.count / elapsed
                estimated_missing = 0
                if first_seq is not None and last_seq is not None:
                    estimated_missing = max(0, (last_seq - first_seq + 1) - writer.count)
                print(
                    f"\r프레임 {writer.count:,} | {fps:5.1f} fps | "
                    f"누락 추정 {estimated_missing:,} | 파싱 오류 {counters['parse_errors']:,}",
                    end="",
                    flush=True,
                )
                last_status = now
    finally:
        stop_event.set()
        worker.join(timeout=2.0)
        source.close()
        writer.close()
        if live_plot is not None:
            live_plot.close()

    elapsed = max(time.monotonic() - start, 1e-9)
    estimated_missing = 0
    if first_seq is not None and last_seq is not None:
        estimated_missing = max(0, (last_seq - first_seq + 1) - writer.count)
    print()
    print("캡처 완료")
    print(f"  저장 파일: {output_path.resolve()}")
    print(f"  유효 프레임: {writer.count:,}")
    print(f"  평균 속도: {writer.count / elapsed:.1f} fps")
    print(f"  시퀀스 누락 추정: {estimated_missing:,}")
    print(f"  PC 큐 드롭: {counters['pc_queue_drops']:,}")
    print(f"  CSI 길이 분포: {dict(lengths.most_common(5))}")
    return 0 if writer.count > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
