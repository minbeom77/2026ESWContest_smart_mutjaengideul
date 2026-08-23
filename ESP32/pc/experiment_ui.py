#!/usr/bin/env python3
"""Windows experiment UI for labeled ESP32 Wi-Fi CSI capture."""

from __future__ import annotations

import csv
import json
import os
import queue
import shutil
import threading
import time
import tkinter as tk
import warnings
from collections import Counter, deque
from datetime import datetime, timezone
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk
from typing import Any, Optional

import numpy as np
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
from matplotlib import colormaps, rcParams

from csi_capture import (
    CSIFrame,
    CSIParser,
    CaptureWriter,
    DemoFrameSource,
    SerialFrameSource,
    build_output_path,
)

try:
    from serial.tools import list_ports
except ImportError:  # pragma: no cover
    list_ports = None


DEFAULT_BAUD = 921_600
DEFAULT_DURATION = 60
HEATMAP_HISTORY = 400
SCORE_HISTORY = 10_000

ACTION_PRESETS: dict[str, tuple[tuple[str, str], ...]] = {
    "기준/환경": (
        ("empty", "빈 공간"),
        ("still", "사람 정지"),
        ("environment_change", "문·가구 등 환경 변화"),
    ),
    "일상 행동": (
        ("walk", "걷기"),
        ("sit_down", "앉기"),
        ("stand_up", "일어서기"),
        ("turn_body", "몸 돌리기"),
        ("lie_down", "눕기"),
    ),
    "낙상 실험": (
        ("fall_forward", "전방 낙상"),
        ("fall_backward", "후방 낙상"),
        ("fall_side", "측면 낙상"),
        ("fall_then_still", "낙상 후 움직임 없음"),
    ),
    "화장실 미끄러짐": (
        ("bathroom_slip", "바닥 미끄러짐"),
        ("bathroom_sit", "변기 앉기·일어서기"),
        ("bathroom_fall", "화장실 낙상"),
        ("bathroom_recovery", "넘어진 후 일어나기"),
    ),
    "침실/수면 행동": (
        ("bed_enter", "침대에 눕기"),
        ("sleep_still", "수면 중 정지"),
        ("sleep_turn", "뒤척임"),
        ("bed_exit", "침대에서 일어나기"),
    ),
    "응급/이상 행동": (
        ("collapse", "갑작스러운 쓰러짐"),
        ("long_inactivity", "장시간 움직임 없음"),
        ("repeated_motion", "반복 이상 움직임"),
    ),
    "사용자 정의": (("custom", "직접 입력"),),
}

CATALOG_FIELDS = (
    "csv_file",
    "metadata_file",
    "label",
    "category",
    "action",
    "trial",
    "participant",
    "distance_m",
    "started_at",
    "finished_at",
    "requested_duration_seconds",
    "elapsed_seconds",
    "frames",
    "average_fps",
    "estimated_missing",
    "parse_errors",
    "movement_score_median",
    "movement_score_p95",
    "movement_score_max",
    "result",
    "notes",
)

rcParams["font.family"] = "Malgun Gothic"
rcParams["axes.unicode_minus"] = False


def safe_label(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in value.strip())
    return cleaned.strip("_") or "unlabeled"


def read_metadata(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def rebuild_catalog(output_dir: Path) -> Path:
    """Create a durable flat table for later statistics or ML preparation."""
    output_dir.mkdir(parents=True, exist_ok=True)
    catalog_path = output_dir / "experiment_catalog.csv"
    temporary_path = output_dir / "experiment_catalog.tmp"
    rows: list[dict[str, Any]] = []
    known_csv: set[Path] = set()

    for metadata_path in sorted(output_dir.glob("csi_*.json")):
        metadata = read_metadata(metadata_path)
        csv_value = metadata.get("csv_path")
        csv_path = Path(csv_value) if csv_value else metadata_path.with_suffix(".csv")
        if not csv_path.is_absolute():
            csv_path = output_dir / csv_path.name
        if not csv_path.exists():
            fallback = metadata_path.with_suffix(".csv")
            if not fallback.exists():
                continue
            csv_path = fallback
        known_csv.add(csv_path.resolve())
        row = {field: metadata.get(field, "") for field in CATALOG_FIELDS}
        row["csv_file"] = csv_path.name
        row["metadata_file"] = metadata_path.name
        row["category"] = metadata.get("category", "미분류")
        row["action"] = metadata.get("action", metadata.get("state", ""))
        rows.append(row)

    for csv_path in sorted(output_dir.glob("csi_*.csv")):
        if csv_path.resolve() in known_csv:
            continue
        label = csv_path.stem
        try:
            with csv_path.open("r", newline="", encoding="utf-8-sig") as handle:
                first = next(csv.DictReader(handle), None)
                if first and first.get("label"):
                    label = first["label"]
        except OSError:
            continue
        row = {field: "" for field in CATALOG_FIELDS}
        row.update(
            {
                "csv_file": csv_path.name,
                "label": label,
                "category": "미분류",
                "action": label.rsplit("_", 1)[0],
                "result": "legacy",
            }
        )
        rows.append(row)

    with temporary_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=CATALOG_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary_path, catalog_path)
    return catalog_path


def rewrite_csv_label(path: Path, new_label: str) -> None:
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    with path.open("r", newline="", encoding="utf-8-sig") as source:
        reader = csv.DictReader(source)
        if not reader.fieldnames:
            raise ValueError("CSV 헤더를 찾을 수 없습니다.")
        with temporary_path.open("w", newline="", encoding="utf-8-sig") as target:
            writer = csv.DictWriter(target, fieldnames=reader.fieldnames)
            writer.writeheader()
            for row in reader:
                row["label"] = new_label
                writer.writerow(row)
    os.replace(temporary_path, path)


def destination_for_label(path: Path, new_label: str) -> Path:
    parts = path.stem.split("_")
    prefix = "_".join(parts[:3]) if len(parts) >= 3 and parts[0] == "csi" else path.stem
    candidate = path.with_name(f"{prefix}_{safe_label(new_label)}{path.suffix}")
    counter = 2
    while candidate.exists() and candidate.resolve() != path.resolve():
        candidate = path.with_name(f"{prefix}_{safe_label(new_label)}_{counter}{path.suffix}")
        counter += 1
    return candidate


def cleaned_amplitude(frame: CSIFrame) -> np.ndarray:
    """Return a conservative amplitude feature without changing saved raw CSI."""
    values = np.asarray(frame.data, dtype=np.float64)
    if frame.first_word_invalid and values.size >= 4:
        values = values[4:]

    usable = values.size - (values.size % 2)
    if usable < 2:
        return np.empty(0, dtype=np.float64)

    values = values[:usable]
    imag = values[0::2]
    real = values[1::2]
    magnitude = np.hypot(real, imag)

    amplitude_db = np.full(magnitude.shape, np.nan, dtype=np.float64)
    valid = magnitude > 0.0
    amplitude_db[valid] = 20.0 * np.log10(magnitude[valid] + 1e-9)
    if np.any(valid):
        amplitude_db -= np.nanmedian(amplitude_db)
    return amplitude_db


def load_session_scores(path: Path) -> dict[str, Any]:
    """Load one saved CSV and reproduce the UI's preliminary movement score."""
    temporal_window: deque[np.ndarray] = deque(maxlen=3)
    score_window: deque[float] = deque(maxlen=5)
    previous: Optional[np.ndarray] = None
    times: list[float] = []
    scores: list[float] = []
    first_time: Optional[float] = None
    label = path.stem
    rows = 0

    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            try:
                host_time = float(row["host_time_unix"])
                frame = CSIFrame(
                    host_time=host_time,
                    seq=int(row["seq"]),
                    mac=row["mac"],
                    rssi=int(row["rssi"]),
                    rate=int(row["rate"]),
                    noise_floor=int(row["noise_floor"]),
                    channel=int(row["channel"]),
                    device_timestamp=int(row["device_timestamp"]),
                    sig_len=int(row["sig_len"]),
                    rx_format=int(row["rx_format"]),
                    reported_len=int(row["reported_len"]),
                    first_word_invalid=int(row["first_word_invalid"]),
                    data=[int(value) for value in json.loads(row["data_json"])],
                )
            except (KeyError, TypeError, ValueError, json.JSONDecodeError):
                continue

            rows += 1
            if row.get("label"):
                label = row["label"]
            amplitude = cleaned_amplitude(frame)
            if not amplitude.size:
                continue
            if temporal_window and temporal_window[-1].size != amplitude.size:
                temporal_window.clear()
                score_window.clear()
                previous = None
            temporal_window.append(amplitude)
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", category=RuntimeWarning)
                filtered = np.nanmedian(np.vstack(temporal_window), axis=0)

            score = 0.0
            if previous is not None and previous.size == filtered.size:
                valid = np.isfinite(previous) & np.isfinite(filtered)
                if np.any(valid):
                    score = float(np.median(np.abs(filtered[valid] - previous[valid])))
            previous = filtered.copy()
            score_window.append(score)
            first_time = host_time if first_time is None else first_time
            times.append(host_time - first_time)
            scores.append(float(np.median(score_window)))

    if not scores:
        raise ValueError(f"유효한 CSI 프레임이 없습니다: {path.name}")

    score_array = np.asarray(scores, dtype=np.float64)
    time_array = np.asarray(times, dtype=np.float64)
    metadata = read_metadata(path.with_suffix(".json"))
    return {
        "path": path,
        "label": label,
        "category": metadata.get("category", "미분류"),
        "action": metadata.get("action", metadata.get("state", "")),
        "rows": rows,
        "times": time_array,
        "scores": score_array,
        "duration": float(time_array[-1]) if time_array.size else 0.0,
        "median": float(np.median(score_array)),
        "p95": float(np.percentile(score_array, 95)),
        "maximum": float(np.max(score_array)),
    }


def show_session_comparison(parent: tk.Misc, paths: list[Path]) -> None:
    if not paths:
        raise ValueError("표시할 실험 파일이 없습니다.")
    sessions = [load_session_scores(path) for path in paths]
    window = tk.Toplevel(parent)
    window.title("CSI 실험 결과" if len(sessions) == 1 else f"CSI 실험 {len(sessions)}개 비교")
    window.geometry("1180x800")
    window.minsize(900, 620)

    summary = ttk.LabelFrame(window, text="요약", padding=10)
    summary.pack(fill="x", padx=12, pady=(12, 6))
    columns = ("category", "label", "frames", "duration", "median", "p95", "maximum")
    summary_table = ttk.Treeview(
        summary,
        columns=columns,
        show="headings",
        height=min(max(len(sessions), 1), 7),
    )
    headings = {
        "category": "행동 분야",
        "label": "라벨",
        "frames": "프레임",
        "duration": "길이(초)",
        "median": "중앙값(dB)",
        "p95": "95%(dB)",
        "maximum": "최댓값(dB)",
    }
    widths = {
        "category": 150,
        "label": 180,
        "frames": 90,
        "duration": 90,
        "median": 110,
        "p95": 110,
        "maximum": 110,
    }
    for column in columns:
        summary_table.heading(column, text=headings[column])
        summary_table.column(column, width=widths[column], anchor="center")
    for session in sessions:
        values = (
            session["category"],
            session["label"],
            f"{session['rows']:,}",
            f"{session['duration']:.1f}",
            f"{session['median']:.4f}",
            f"{session['p95']:.4f}",
            f"{session['maximum']:.4f}",
        )
        summary_table.insert("", "end", values=values)
    summary_table.pack(fill="x")

    figure = Figure(figsize=(10.5, 6.2), dpi=100, constrained_layout=True)
    score_axis = figure.add_subplot(211)
    distribution_axis = figure.add_subplot(212)
    color_map = colormaps["tab20"] if len(sessions) <= 20 else colormaps["hsv"]
    if len(sessions) <= 20:
        colors = [color_map(index) for index in range(len(sessions))]
    else:
        colors = [
            color_map(index / max(len(sessions), 1)) for index in range(len(sessions))
        ]
    duplicate_labels = Counter(session["label"] for session in sessions)
    for index, (session, color) in enumerate(zip(sessions, colors), start=1):
        times = session["times"]
        scores = session["scores"]
        legend_label = session["label"]
        if duplicate_labels[legend_label] > 1:
            legend_label = f"{legend_label} ({session['category']}, #{index})"
        stride = max(1, int(np.ceil(scores.size / 5000)))
        score_axis.plot(
            times[::stride],
            scores[::stride],
            label=legend_label,
            color=color,
            linewidth=1.2,
            alpha=0.9,
        )
        distribution_axis.hist(
            scores,
            bins=40,
            density=True,
            alpha=0.45,
            color=color,
            label=legend_label,
        )
        distribution_axis.axvline(session["p95"], color=color, linestyle="--", alpha=0.9)

    score_axis.set_title(
        "시간에 따른 움직임 점수"
        if len(sessions) > 1
        else f"{sessions[0]['label']} — 시간별 움직임 점수"
    )
    score_axis.set_xlabel("측정 시간 (초)")
    score_axis.set_ylabel("Median 변화량 (dB)")
    score_axis.grid(True, alpha=0.3)
    score_axis.legend()
    distribution_axis.set_title("움직임 점수 분포 - 점선은 각 세션의 95% 값")
    distribution_axis.set_xlabel("움직임 점수 (dB)")
    distribution_axis.set_ylabel("밀도")
    distribution_axis.grid(True, alpha=0.3)
    distribution_axis.legend()

    canvas = FigureCanvasTkAgg(figure, master=window)
    canvas.draw()
    canvas.get_tk_widget().pack(fill="both", expand=True, padx=12, pady=(6, 12))
    window.comparison_canvas = canvas  # type: ignore[attr-defined]


class CaptureWorker(threading.Thread):
    """Read, parse, and save CSI without blocking the Tk main thread."""

    def __init__(
        self,
        *,
        events: queue.Queue[tuple[str, Any]],
        stop_event: threading.Event,
        output_dir: Path,
        label: str,
        duration: float,
        port: str,
        baud: int,
        metadata: dict[str, Any],
        demo: bool = False,
    ) -> None:
        super().__init__(daemon=True)
        self.events = events
        self.stop_event = stop_event
        self.output_dir = output_dir
        self.label = label
        self.duration = duration
        self.port = port
        self.baud = baud
        self.metadata = metadata
        self.demo = demo

    def emit(self, kind: str, payload: Any) -> None:
        try:
            self.events.put_nowait((kind, payload))
        except queue.Full:
            if kind != "frame":
                try:
                    self.events.get_nowait()
                    self.events.put_nowait((kind, payload))
                except (queue.Empty, queue.Full):
                    pass

    def run(self) -> None:
        source = None
        writer = None
        output_path: Optional[Path] = None
        counters: Counter[str] = Counter()
        lengths: Counter[int] = Counter()
        first_seq: Optional[int] = None
        last_seq: Optional[int] = None
        temporal_window: deque[np.ndarray] = deque(maxlen=3)
        score_window: deque[float] = deque(maxlen=5)
        all_scores: list[float] = []
        previous: Optional[np.ndarray] = None
        start = 0.0
        finished_reason = "stopped"

        try:
            self.emit("phase", "ESP32 연결 및 Wi-Fi 재연결 대기 중…")
            source = (
                DemoFrameSource(rate_hz=30.0)
                if self.demo
                else SerialFrameSource(self.port, self.baud)
            )
            output_path = build_output_path(self.output_dir, self.label)
            writer = CaptureWriter(output_path, self.label)
            parser = CSIParser()
            start = time.monotonic()
            self.emit(
                "ready",
                {
                    "path": str(output_path.resolve()),
                    "source": "DEMO" if self.demo else f"{self.port} @ {self.baud}",
                },
            )

            last_status = start
            while not self.stop_event.is_set():
                now = time.monotonic()
                elapsed = now - start
                if self.duration > 0 and elapsed >= self.duration:
                    finished_reason = "completed"
                    break

                try:
                    line = source.read_line()
                except Exception as exc:
                    counters["source_errors"] += 1
                    raise RuntimeError(f"시리얼 입력 오류: {exc}") from exc

                if not line:
                    continue
                counters["lines"] += 1
                frame = parser.parse(line)
                if frame is None:
                    if line.startswith("CSI_DATA"):
                        counters["parse_errors"] += 1
                    continue

                writer.write(frame)
                counters["parsed"] += 1
                lengths[len(frame.data)] += 1
                first_seq = frame.seq if first_seq is None else first_seq
                last_seq = frame.seq

                amplitude = cleaned_amplitude(frame)
                if amplitude.size:
                    if temporal_window and temporal_window[-1].size != amplitude.size:
                        temporal_window.clear()
                        score_window.clear()
                        previous = None
                    temporal_window.append(amplitude)
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore", category=RuntimeWarning)
                        filtered = np.nanmedian(np.vstack(temporal_window), axis=0)

                    score = 0.0
                    if previous is not None and previous.size == filtered.size:
                        valid = np.isfinite(previous) & np.isfinite(filtered)
                        if np.any(valid):
                            score = float(np.median(np.abs(filtered[valid] - previous[valid])))
                    previous = filtered.copy()
                    score_window.append(score)
                    smooth_score = float(np.median(score_window))
                    all_scores.append(smooth_score)
                    self.emit(
                        "frame",
                        {
                            "amplitude": filtered,
                            "score": smooth_score,
                            "elapsed": elapsed,
                            "rssi": frame.rssi,
                        },
                    )

                if now - last_status >= 0.25:
                    count = writer.count
                    missing = 0
                    if first_seq is not None and last_seq is not None:
                        missing = max(0, (last_seq - first_seq + 1) - count)
                    self.emit(
                        "status",
                        {
                            "count": count,
                            "fps": count / max(elapsed, 1e-9),
                            "missing": missing,
                            "parse_errors": counters["parse_errors"],
                            "elapsed": elapsed,
                            "remaining": max(0.0, self.duration - elapsed),
                        },
                    )
                    last_status = now

        except Exception as exc:
            finished_reason = "error"
            self.emit("error", str(exc))
        finally:
            self.stop_event.set()
            if source is not None:
                try:
                    source.close()
                except Exception:
                    pass
            if writer is not None:
                try:
                    writer.close()
                except Exception:
                    pass

            elapsed = max(time.monotonic() - start, 1e-9) if start else 0.0
            count = writer.count if writer is not None else 0
            missing = 0
            if first_seq is not None and last_seq is not None:
                missing = max(0, (last_seq - first_seq + 1) - count)

            result = {
                **self.metadata,
                "result": finished_reason,
                "csv_path": str(output_path.resolve()) if output_path else "",
                "finished_at": datetime.now(timezone.utc).isoformat(),
                "frames": count,
                "elapsed_seconds": round(elapsed, 3),
                "average_fps": round(count / elapsed, 3) if elapsed else 0.0,
                "estimated_missing": missing,
                "parse_errors": counters["parse_errors"],
                "source_errors": counters["source_errors"],
                "csi_length_distribution": dict(lengths),
                "movement_score_median": (
                    round(float(np.median(all_scores)), 6) if all_scores else 0.0
                ),
                "movement_score_p95": (
                    round(float(np.percentile(all_scores, 95)), 6) if all_scores else 0.0
                ),
                "movement_score_max": round(float(np.max(all_scores)), 6) if all_scores else 0.0,
            }

            if output_path is not None:
                metadata_path = output_path.with_suffix(".json")
                try:
                    metadata_path.write_text(
                        json.dumps(result, ensure_ascii=False, indent=2),
                        encoding="utf-8",
                    )
                    result["metadata_path"] = str(metadata_path.resolve())
                except Exception as exc:
                    result["metadata_error"] = str(exc)
            self.emit("done", result)


class ExperimentApp:
    def __init__(
        self,
        root: tk.Tk,
        app_title: str = "ESP32 Wi-Fi CSI 실험실",
    ) -> None:
        self.root = root
        self.app_title = app_title
        self.root.title(app_title)
        self.root.geometry("1500x930")
        self.root.minsize(1200, 780)

        self.events: queue.Queue[tuple[str, Any]] = queue.Queue(maxsize=2000)
        self.stop_event: Optional[threading.Event] = None
        self.worker: Optional[CaptureWorker] = None
        self.latest_csv: Optional[Path] = None
        self.running = False

        self.plot_amplitudes: deque[np.ndarray] = deque(maxlen=HEATMAP_HISTORY)
        self.plot_scores: deque[float] = deque(maxlen=SCORE_HISTORY)
        self.plot_times: deque[float] = deque(maxlen=SCORE_HISTORY)
        self.last_plot_draw = 0.0
        self.history_paths: dict[str, Path] = {}
        self.history_metadata: dict[str, dict[str, Any]] = {}
        self.preview_after_id: Optional[str] = None
        self.last_preview_path: Optional[Path] = None

        self.port_var = tk.StringVar(value="COM7")
        self.baud_var = tk.StringVar(value=str(DEFAULT_BAUD))
        self.category_var = tk.StringVar(value="기준/환경")
        self.action_var = tk.StringVar(value="empty - 빈 공간")
        self.trial_var = tk.IntVar(value=1)
        self.duration_var = tk.StringVar(value=str(DEFAULT_DURATION))
        self.participant_var = tk.StringVar()
        self.distance_var = tk.StringVar()
        self.demo_var = tk.BooleanVar(value=False)
        self.label_preview_var = tk.StringVar(value="empty_01")
        self.phase_var = tk.StringVar(value="준비됨")
        self.source_var = tk.StringVar(value="-")
        self.file_var = tk.StringVar(value="-")
        self.frames_var = tk.StringVar(value="0")
        self.fps_var = tk.StringVar(value="0.0")
        self.missing_var = tk.StringVar(value="0")
        self.errors_var = tk.StringVar(value="0")
        self.remaining_var = tk.StringVar(value="60.0초")
        self.latest_score_var = tk.StringVar(value="0.000 dB")

        self._configure_style()
        self._build_layout()
        self._bind_updates()
        self.update_action_choices()
        self.refresh_ports()
        self.load_saved_sessions()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(100, self.poll_events)

    def _configure_style(self) -> None:
        style = ttk.Style(self.root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("맑은 고딕", 18, "bold"))
        style.configure("Section.TLabel", font=("맑은 고딕", 11, "bold"))
        style.configure("Metric.TLabel", font=("맑은 고딕", 16, "bold"))
        style.configure("Start.TButton", font=("맑은 고딕", 12, "bold"), padding=10)
        style.configure("Stop.TButton", font=("맑은 고딕", 12, "bold"), padding=10)

    def _build_layout(self) -> None:
        outer = ttk.Frame(self.root, padding=14)
        outer.pack(fill="both", expand=True)
        outer.columnconfigure(1, weight=1)
        outer.rowconfigure(1, weight=1)

        ttk.Label(outer, text=self.app_title, style="Title.TLabel").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 12)
        )
        controls = ttk.Frame(outer, width=350)
        controls.grid(row=1, column=0, sticky="nsw", padx=(0, 14))
        controls.grid_propagate(False)

        experiment_box = ttk.LabelFrame(controls, text="실험 설정", padding=12)
        experiment_box.pack(fill="x")
        experiment_box.columnconfigure(1, weight=1)

        row = 0
        ttk.Label(experiment_box, text="COM 포트").grid(row=row, column=0, sticky="w", pady=4)
        port_line = ttk.Frame(experiment_box)
        port_line.grid(row=row, column=1, sticky="ew", pady=4)
        port_line.columnconfigure(0, weight=1)
        self.port_combo = ttk.Combobox(port_line, textvariable=self.port_var, width=12)
        self.port_combo.grid(row=0, column=0, sticky="ew")
        self.refresh_button = ttk.Button(port_line, text="새로고침", command=self.refresh_ports)
        self.refresh_button.grid(row=0, column=1, padx=(6, 0))

        row += 1
        ttk.Label(experiment_box, text="Baud").grid(row=row, column=0, sticky="w", pady=4)
        self.baud_combo = ttk.Combobox(
            experiment_box,
            textvariable=self.baud_var,
            values=("921600", "115200"),
            state="readonly",
        )
        self.baud_combo.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        ttk.Label(experiment_box, text="행동 분야").grid(row=row, column=0, sticky="w", pady=4)
        self.category_combo = ttk.Combobox(
            experiment_box,
            textvariable=self.category_var,
            values=tuple(ACTION_PRESETS),
            state="readonly",
        )
        self.category_combo.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        ttk.Label(experiment_box, text="세부 행동").grid(row=row, column=0, sticky="w", pady=4)
        self.state_combo = ttk.Combobox(
            experiment_box,
            textvariable=self.action_var,
        )
        self.state_combo.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        ttk.Label(experiment_box, text="회차").grid(row=row, column=0, sticky="w", pady=4)
        self.trial_spin = ttk.Spinbox(
            experiment_box, from_=1, to=999, textvariable=self.trial_var, width=8
        )
        self.trial_spin.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        ttk.Label(experiment_box, text="시간(초)").grid(row=row, column=0, sticky="w", pady=4)
        self.duration_entry = ttk.Entry(experiment_box, textvariable=self.duration_var)
        self.duration_entry.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        ttk.Label(experiment_box, text="참가자").grid(row=row, column=0, sticky="w", pady=4)
        self.participant_entry = ttk.Entry(experiment_box, textvariable=self.participant_var)
        self.participant_entry.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        ttk.Label(experiment_box, text="거리(m)").grid(row=row, column=0, sticky="w", pady=4)
        self.distance_entry = ttk.Entry(experiment_box, textvariable=self.distance_var)
        self.distance_entry.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        ttk.Label(experiment_box, text="메모").grid(row=row, column=0, sticky="nw", pady=4)
        self.notes_text = tk.Text(experiment_box, height=4, width=24, wrap="word")
        self.notes_text.grid(row=row, column=1, sticky="ew", pady=4)

        row += 1
        self.demo_check = ttk.Checkbutton(
            experiment_box,
            text="데모 모드 (ESP32 없이 테스트)",
            variable=self.demo_var,
        )
        self.demo_check.grid(row=row, column=0, columnspan=2, sticky="w", pady=(8, 2))

        row += 1
        ttk.Separator(experiment_box).grid(
            row=row, column=0, columnspan=2, sticky="ew", pady=8
        )
        row += 1
        ttk.Label(experiment_box, text="저장 라벨").grid(row=row, column=0, sticky="w")
        self.label_entry = ttk.Entry(
            experiment_box,
            textvariable=self.label_preview_var,
            font=("맑은 고딕", 10, "bold"),
        )
        self.label_entry.grid(row=row, column=1, sticky="ew")

        button_line = ttk.Frame(controls)
        button_line.pack(fill="x", pady=10)
        button_line.columnconfigure((0, 1), weight=1)
        self.start_button = ttk.Button(
            button_line,
            text="▶ 실험 시작",
            style="Start.TButton",
            command=self.start_capture,
        )
        self.start_button.grid(row=0, column=0, sticky="ew", padx=(0, 5))
        self.stop_button = ttk.Button(
            button_line,
            text="■ 중지",
            style="Stop.TButton",
            command=self.stop_capture,
            state="disabled",
        )
        self.stop_button.grid(row=0, column=1, sticky="ew", padx=(5, 0))

        status_box = ttk.LabelFrame(controls, text="실시간 상태", padding=12)
        status_box.pack(fill="x")
        status_box.columnconfigure(1, weight=1)
        self._status_row(status_box, 0, "상태", self.phase_var)
        self._status_row(status_box, 1, "입력", self.source_var)
        self._status_row(status_box, 2, "프레임", self.frames_var, metric=True)
        self._status_row(status_box, 3, "FPS", self.fps_var, metric=True)
        self._status_row(status_box, 4, "누락 추정", self.missing_var)
        self._status_row(status_box, 5, "파싱 오류", self.errors_var)
        self._status_row(status_box, 6, "남은 시간", self.remaining_var)
        self._status_row(status_box, 7, "움직임 점수", self.latest_score_var)

        file_box = ttk.LabelFrame(controls, text="저장", padding=12)
        file_box.pack(fill="x", pady=(10, 0))
        ttk.Label(file_box, textvariable=self.file_var, wraplength=310).pack(anchor="w")
        file_buttons = ttk.Frame(file_box)
        file_buttons.pack(fill="x", pady=(8, 0))
        file_buttons.columnconfigure((0, 1), weight=1)
        ttk.Button(file_buttons, text="sessions 폴더", command=self.open_sessions).grid(
            row=0, column=0, sticky="ew", padx=(0, 4)
        )
        self.open_csv_button = ttk.Button(
            file_buttons,
            text="최근 CSV 열기",
            command=self.open_latest_csv,
            state="disabled",
        )
        self.open_csv_button.grid(row=0, column=1, sticky="ew", padx=(4, 0))

        graph_area = ttk.Frame(outer)
        graph_area.grid(row=1, column=1, sticky="nsew")
        graph_area.rowconfigure(0, weight=1)
        graph_area.columnconfigure(0, weight=1)
        self.figure = Figure(figsize=(9.5, 7.2), dpi=100, constrained_layout=True)
        self.heat_axis = self.figure.add_subplot(211)
        self.score_axis = self.figure.add_subplot(212)
        self.heat_image = None
        self.score_line = None
        self._reset_axes()
        self.canvas = FigureCanvasTkAgg(self.figure, master=graph_area)
        self.canvas.draw()
        self.canvas.get_tk_widget().grid(row=0, column=0, sticky="nsew")

        history_box = ttk.LabelFrame(graph_area, text="완료된 실험", padding=8)
        history_box.grid(row=1, column=0, sticky="ew", pady=(10, 0))
        columns = ("category", "label", "frames", "fps", "missing", "result")
        self.history = ttk.Treeview(
            history_box,
            columns=columns,
            show="headings",
            height=6,
            selectmode="extended",
        )
        headings = {
            "category": "행동 분야",
            "label": "라벨",
            "frames": "프레임",
            "fps": "평균 FPS",
            "missing": "누락",
            "result": "결과",
        }
        widths = {
            "category": 150,
            "label": 190,
            "frames": 90,
            "fps": 90,
            "missing": 90,
            "result": 90,
        }
        for column in columns:
            self.history.heading(column, text=headings[column])
            self.history.column(column, width=widths[column], anchor="center")
        self.history.pack(fill="x")
        self.history.bind("<<TreeviewSelect>>", self.on_history_selection)
        comparison_line = ttk.Frame(history_box)
        comparison_line.pack(fill="x", pady=(7, 0))
        ttk.Label(
            comparison_line,
            text="한 개 클릭: 결과 보기 / Ctrl+클릭: 여러 실험 선택",
        ).pack(side="left")
        ttk.Button(
            comparison_line,
            text="선택 실험 비교",
            command=self.compare_sessions,
        ).pack(side="right")
        management_line = ttk.Frame(history_box)
        management_line.pack(fill="x", pady=(6, 0))
        ttk.Button(management_line, text="라벨 수정", command=self.rename_selected).pack(
            side="left", padx=(0, 5)
        )
        ttk.Button(
            management_line,
            text="선택 파일 휴지통",
            command=self.trash_selected,
        ).pack(side="left", padx=5)
        ttk.Button(
            management_line,
            text="목록 새로고침",
            command=self.load_saved_sessions,
        ).pack(side="left", padx=5)
        ttk.Button(
            management_line,
            text="통합 카탈로그 CSV",
            command=self.open_catalog,
        ).pack(side="right")

    def _reset_axes(self) -> None:
        self.heat_axis.clear()
        self.score_axis.clear()
        self.heat_axis.set_title(f"정제 CSI 진폭 히트맵 — 최근 {HEATMAP_HISTORY}프레임")
        self.heat_axis.set_xlabel("서브캐리어 인덱스")
        self.heat_axis.set_ylabel("최근 프레임")
        self.score_axis.set_title("빠른 움직임 점수 (초기 지표)")
        self.score_axis.set_xlabel("측정 시간 (초)")
        self.score_axis.set_ylabel("Median 변화량 (dB)")
        self.score_axis.grid(True, alpha=0.3)
        (self.score_line,) = self.score_axis.plot([], [], color="#d1495b", linewidth=1.5)

    @staticmethod
    def _status_row(
        parent: ttk.Widget,
        row: int,
        label: str,
        variable: tk.StringVar,
        *,
        metric: bool = False,
    ) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", pady=2)
        style = "Metric.TLabel" if metric else "TLabel"
        ttk.Label(parent, textvariable=variable, style=style).grid(
            row=row, column=1, sticky="e", pady=2
        )

    def _bind_updates(self) -> None:
        self.category_var.trace_add("write", lambda *_: self.update_action_choices())
        self.action_var.trace_add("write", lambda *_: self.update_label_preview())
        self.trial_var.trace_add("write", lambda *_: self.update_label_preview())
        self.duration_var.trace_add("write", lambda *_: self.update_remaining_preview())

    def update_action_choices(self) -> None:
        category = self.category_var.get()
        choices = [
            f"{code} - {description}"
            for code, description in ACTION_PRESETS.get(
                category, ACTION_PRESETS["사용자 정의"]
            )
        ]
        current = self.action_var.get().strip()
        self.state_combo["values"] = choices
        if current not in choices:
            self.action_var.set(choices[0])
        else:
            self.update_label_preview()

    def current_action_code(self) -> str:
        value = self.action_var.get().strip()
        if " - " in value:
            value = value.split(" - ", 1)[0]
        return safe_label(value or "unlabeled")

    def update_label_preview(self) -> None:
        action = self.current_action_code()
        try:
            trial = max(1, int(self.trial_var.get()))
        except (ValueError, tk.TclError):
            trial = 1
        self.label_preview_var.set(f"{action}_{trial:02d}")

    def update_remaining_preview(self) -> None:
        if self.running:
            return
        try:
            self.remaining_var.set(f"{float(self.duration_var.get()):.1f}초")
        except ValueError:
            self.remaining_var.set("-")

    def refresh_ports(self) -> None:
        if list_ports is None:
            return
        devices = [item.device for item in list_ports.comports()]
        self.port_combo["values"] = devices
        if self.port_var.get() not in devices and devices:
            preferred = next((value for value in devices if value.upper() == "COM7"), devices[0])
            self.port_var.set(preferred)

    def make_metadata(self, label: str, duration: float, baud: int) -> dict[str, Any]:
        action = self.current_action_code()
        return {
            "schema_version": 2,
            "label": label,
            "category": self.category_var.get().strip() or "미분류",
            "action": action,
            "state": action,
            "trial": int(self.trial_var.get()),
            "participant": self.participant_var.get().strip(),
            "distance_m": self.distance_var.get().strip(),
            "notes": self.notes_text.get("1.0", "end").strip(),
            "requested_duration_seconds": duration,
            "port": "DEMO" if self.demo_var.get() else self.port_var.get().strip(),
            "baud": baud,
            "started_at": datetime.now(timezone.utc).isoformat(),
        }

    def start_capture(self) -> None:
        if self.running:
            return
        try:
            duration = float(self.duration_var.get())
            if duration <= 0 or duration > 3600:
                raise ValueError
        except ValueError:
            messagebox.showerror("입력 오류", "측정 시간은 1~3600초 사이 숫자로 입력하세요.")
            return
        try:
            baud = int(self.baud_var.get())
        except ValueError:
            messagebox.showerror("입력 오류", "올바른 baud 값을 선택하세요.")
            return

        port = self.port_var.get().strip()
        if not self.demo_var.get() and not port:
            messagebox.showerror("입력 오류", "ESP32 COM 포트를 선택하세요.")
            return

        label = safe_label(self.label_preview_var.get())
        self.label_preview_var.set(label)
        duration = float(duration)
        output_dir = Path(__file__).resolve().parent / "sessions"
        metadata = self.make_metadata(label, duration, baud)
        self.clear_plot()
        self.frames_var.set("0")
        self.fps_var.set("0.0")
        self.missing_var.set("0")
        self.errors_var.set("0")
        self.latest_score_var.set("0.000 dB")
        self.remaining_var.set(f"{duration:.1f}초")
        self.file_var.set("파일 준비 중…")
        self.source_var.set("연결 중…")
        self.phase_var.set("연결 중")

        self.stop_event = threading.Event()
        self.worker = CaptureWorker(
            events=self.events,
            stop_event=self.stop_event,
            output_dir=output_dir,
            label=label,
            duration=duration,
            port=port,
            baud=baud,
            metadata=metadata,
            demo=self.demo_var.get(),
        )
        self.running = True
        self.set_controls_enabled(False)
        self.stop_button.configure(state="normal")
        self.worker.start()

    def stop_capture(self) -> None:
        if self.stop_event is not None:
            self.phase_var.set("중지 요청 중…")
            self.stop_event.set()

    def set_controls_enabled(self, enabled: bool) -> None:
        normal = "normal" if enabled else "disabled"
        readonly = "readonly" if enabled else "disabled"
        for widget in (
            self.port_combo,
            self.state_combo,
            self.trial_spin,
            self.duration_entry,
            self.participant_entry,
            self.distance_entry,
            self.label_entry,
            self.refresh_button,
            self.demo_check,
            self.start_button,
        ):
            widget.configure(state=normal)
        self.category_combo.configure(state=readonly)
        self.baud_combo.configure(state=readonly)
        self.notes_text.configure(state=normal)

    def poll_events(self) -> None:
        plot_dirty = False
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "phase":
                    self.phase_var.set(str(payload))
                elif kind == "ready":
                    self.phase_var.set("측정 중")
                    self.source_var.set(payload["source"])
                    self.file_var.set(payload["path"])
                    self.latest_csv = Path(payload["path"])
                elif kind == "frame":
                    amplitude = payload["amplitude"]
                    if self.plot_amplitudes and self.plot_amplitudes[-1].size != amplitude.size:
                        self.clear_plot()
                    self.plot_amplitudes.append(amplitude)
                    self.plot_scores.append(float(payload["score"]))
                    self.plot_times.append(float(payload["elapsed"]))
                    self.latest_score_var.set(f"{float(payload['score']):.3f} dB")
                    plot_dirty = True
                elif kind == "status":
                    self.frames_var.set(f"{payload['count']:,}")
                    self.fps_var.set(f"{payload['fps']:.1f}")
                    self.missing_var.set(f"{payload['missing']:,}")
                    self.errors_var.set(f"{payload['parse_errors']:,}")
                    self.remaining_var.set(f"{payload['remaining']:.1f}초")
                elif kind == "error":
                    self.phase_var.set("오류")
                    messagebox.showerror("캡처 오류", str(payload))
                elif kind == "done":
                    self.finish_capture(payload)
        except queue.Empty:
            pass

        now = time.monotonic()
        if plot_dirty and now - self.last_plot_draw >= 0.15:
            self.update_plot()
            self.last_plot_draw = now
        self.root.after(100, self.poll_events)

    def update_plot(self) -> None:
        if not self.plot_amplitudes:
            return
        matrix = np.vstack(self.plot_amplitudes)
        masked = np.ma.masked_invalid(matrix)
        rows, columns = matrix.shape

        if self.heat_image is None or self.heat_image.get_array().shape != matrix.shape:
            self.heat_axis.clear()
            self.heat_axis.set_title(
                f"정제 CSI 진폭 히트맵 — 최근 {HEATMAP_HISTORY}프레임"
            )
            self.heat_axis.set_xlabel("서브캐리어 인덱스")
            self.heat_axis.set_ylabel("최근 프레임")
            self.heat_image = self.heat_axis.imshow(
                masked,
                aspect="auto",
                origin="lower",
                interpolation="nearest",
                cmap="viridis",
            )
        else:
            self.heat_image.set_data(masked)

        self.heat_image.set_extent((0, columns, 0, rows))
        self.heat_axis.set_xlim(0, columns)
        self.heat_axis.set_ylim(0, max(rows, 2))
        finite = matrix[np.isfinite(matrix)]
        if finite.size:
            low, high = np.percentile(finite, [5, 95])
            if high > low:
                self.heat_image.set_clim(low, high)

        x_values = np.asarray(self.plot_times)
        y_values = np.asarray(self.plot_scores)
        self.score_line.set_data(x_values, y_values)
        self.score_axis.set_xlim(max(0.0, x_values[0]), max(10.0, x_values[-1]))
        if y_values.size:
            high = max(0.1, float(np.percentile(y_values, 98)) * 1.2)
            self.score_axis.set_ylim(0.0, high)
        self.canvas.draw_idle()

    def clear_plot(self) -> None:
        self.plot_amplitudes.clear()
        self.plot_scores.clear()
        self.plot_times.clear()
        self.heat_image = None
        self._reset_axes()
        if hasattr(self, "canvas"):
            self.canvas.draw_idle()

    def finish_capture(self, result: dict[str, Any]) -> None:
        self.running = False
        self.stop_button.configure(state="disabled")
        self.set_controls_enabled(True)
        self.phase_var.set("완료" if result["result"] == "completed" else result["result"])
        self.frames_var.set(f"{result['frames']:,}")
        self.fps_var.set(f"{result['average_fps']:.1f}")
        self.missing_var.set(f"{result['estimated_missing']:,}")
        self.errors_var.set(f"{result['parse_errors']:,}")
        self.remaining_var.set("0.0초")

        csv_path = result.get("csv_path")
        if csv_path:
            self.latest_csv = Path(csv_path)
            self.file_var.set(csv_path)
            self.open_csv_button.configure(state="normal")
        self.load_saved_sessions()
        if result["result"] == "completed" and result["frames"] > 0:
            self.trial_var.set(int(self.trial_var.get()) + 1)
        self.worker = None
        self.stop_event = None

    def sessions_dir(self) -> Path:
        path = Path(__file__).resolve().parent / "sessions"
        path.mkdir(parents=True, exist_ok=True)
        return path

    @staticmethod
    def _display_number(value: Any, decimals: Optional[int] = None) -> str:
        try:
            number = float(value)
        except (TypeError, ValueError):
            return str(value or "-")
        if decimals is not None:
            return f"{number:.{decimals}f}"
        return f"{int(number):,}"

    def load_saved_sessions(self) -> None:
        selected_paths = {
            self.history_paths[item].resolve()
            for item in self.history.selection()
            if item in self.history_paths and self.history_paths[item].exists()
        }
        for item in self.history.get_children():
            self.history.delete(item)
        self.history_paths.clear()
        self.history_metadata.clear()

        try:
            catalog_path = rebuild_catalog(self.sessions_dir())
            with catalog_path.open("r", newline="", encoding="utf-8-sig") as handle:
                rows = list(csv.DictReader(handle))
        except OSError as exc:
            messagebox.showerror("목록 오류", f"저장된 실험 목록을 읽지 못했습니다.\n{exc}")
            return

        restored: list[str] = []
        for row in reversed(rows):
            csv_name = row.get("csv_file", "")
            csv_path = self.sessions_dir() / Path(csv_name).name
            if not csv_name or not csv_path.exists():
                continue
            item = self.history.insert(
                "",
                "end",
                values=(
                    row.get("category") or "미분류",
                    row.get("label") or csv_path.stem,
                    self._display_number(row.get("frames")),
                    self._display_number(row.get("average_fps"), 1),
                    self._display_number(row.get("estimated_missing")),
                    row.get("result") or "saved",
                ),
            )
            self.history_paths[item] = csv_path
            self.history_metadata[item] = dict(row)
            if csv_path.resolve() in selected_paths:
                restored.append(item)

        if restored:
            self.history.selection_set(restored)
        self.phase_var.set(f"저장 실험 {len(self.history_paths)}개 불러옴")

    def _selected_session_paths(self) -> list[Path]:
        return [
            self.history_paths[item]
            for item in self.history.selection()
            if item in self.history_paths and self.history_paths[item].exists()
        ]

    def on_history_selection(self, _event: Any = None) -> None:
        if self.preview_after_id is not None:
            self.root.after_cancel(self.preview_after_id)
            self.preview_after_id = None
        if self.running or len(self._selected_session_paths()) != 1:
            return
        self.preview_after_id = self.root.after(350, self.preview_selected_session)

    def preview_selected_session(self) -> None:
        self.preview_after_id = None
        paths = self._selected_session_paths()
        if self.running or len(paths) != 1:
            return
        try:
            self.phase_var.set("실험 결과 분석 중…")
            self.root.update_idletasks()
            show_session_comparison(self.root, paths)
            self.last_preview_path = paths[0]
            self.phase_var.set("결과 창 열림")
        except Exception as exc:
            self.phase_var.set("결과 분석 오류")
            messagebox.showerror("결과 보기 오류", str(exc))

    def rename_selected(self) -> None:
        paths = self._selected_session_paths()
        if len(paths) != 1:
            messagebox.showinfo("라벨 수정", "라벨을 수정할 실험 한 개만 선택하세요.")
            return
        old_csv = paths[0]
        selected_item = self.history.selection()[0]
        metadata = read_metadata(old_csv.with_suffix(".json"))
        current_label = str(
            metadata.get("label")
            or self.history_metadata.get(selected_item, {}).get("label")
            or old_csv.stem
        )
        entered = simpledialog.askstring(
            "라벨 수정",
            "새 라벨을 입력하세요. CSV 내부 라벨과 JSON 메타데이터도 함께 변경됩니다.",
            initialvalue=current_label,
            parent=self.root,
        )
        if entered is None:
            return
        new_label = safe_label(entered)
        try:
            rewrite_csv_label(old_csv, new_label)
            new_csv = destination_for_label(old_csv, new_label)
            old_json = old_csv.with_suffix(".json")
            if new_csv.resolve() != old_csv.resolve():
                old_csv.replace(new_csv)
            new_json = new_csv.with_suffix(".json")
            if old_json.exists() and old_json.resolve() != new_json.resolve():
                if new_json.exists():
                    new_json = new_csv.with_name(
                        f"{new_csv.stem}_{datetime.now():%H%M%S}.json"
                    )
                old_json.replace(new_json)

            metadata.setdefault("original_label", current_label)
            metadata.update(
                {
                    "label": new_label,
                    "csv_path": str(new_csv.resolve()),
                    "metadata_path": str(new_json.resolve()),
                    "renamed_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            new_json.write_text(
                json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            self.latest_csv = new_csv if self.latest_csv == old_csv else self.latest_csv
            self.load_saved_sessions()
            self.phase_var.set(f"라벨 수정 완료: {new_label}")
        except Exception as exc:
            messagebox.showerror("라벨 수정 오류", str(exc))

    def trash_selected(self) -> None:
        paths = self._selected_session_paths()
        if not paths:
            messagebox.showinfo("파일 휴지통", "옮길 실험을 한 개 이상 선택하세요.")
            return
        labels = [path.stem for path in paths[:5]]
        suffix = "" if len(paths) <= 5 else f"\n외 {len(paths) - 5}개"
        if not messagebox.askyesno(
            "파일 휴지통",
            f"선택한 실험 {len(paths)}개를 복구 가능한 _trash 폴더로 옮길까요?\n\n"
            + "\n".join(labels)
            + suffix,
            parent=self.root,
        ):
            return

        sessions = self.sessions_dir().resolve()
        trash_dir = sessions / "_trash" / datetime.now().strftime("%Y%m%d_%H%M%S")
        trash_dir.mkdir(parents=True, exist_ok=True)
        moved = 0
        try:
            for csv_path in paths:
                resolved = csv_path.resolve()
                if not resolved.is_relative_to(sessions):
                    raise ValueError(f"sessions 밖의 파일은 이동하지 않습니다: {csv_path}")
                for source in (resolved, resolved.with_suffix(".json")):
                    if not source.exists():
                        continue
                    destination = trash_dir / source.name
                    counter = 2
                    while destination.exists():
                        destination = trash_dir / f"{source.stem}_{counter}{source.suffix}"
                        counter += 1
                    shutil.move(str(source), str(destination))
                moved += 1
            self.load_saved_sessions()
            self.phase_var.set(f"실험 {moved}개를 휴지통으로 이동")
            messagebox.showinfo(
                "이동 완료",
                f"실험 {moved}개를 옮겼습니다. 필요하면 아래 폴더에서 복구할 수 있습니다.\n{trash_dir}",
                parent=self.root,
            )
        except Exception as exc:
            self.load_saved_sessions()
            messagebox.showerror("파일 이동 오류", str(exc))

    def open_catalog(self) -> None:
        try:
            catalog_path = rebuild_catalog(self.sessions_dir())
            os.startfile(catalog_path)  # type: ignore[attr-defined]
            self.phase_var.set("통합 카탈로그 CSV 열림")
        except Exception as exc:
            messagebox.showerror("카탈로그 오류", str(exc))

    def open_sessions(self) -> None:
        os.startfile(self.sessions_dir())  # type: ignore[attr-defined]

    def open_latest_csv(self) -> None:
        if self.latest_csv is not None and self.latest_csv.exists():
            os.startfile(self.latest_csv)  # type: ignore[attr-defined]

    def compare_sessions(self) -> None:
        if self.preview_after_id is not None:
            self.root.after_cancel(self.preview_after_id)
            self.preview_after_id = None
        selected_paths = self._selected_session_paths()
        if len(selected_paths) < 2:
            filenames = filedialog.askopenfilenames(
                parent=self.root,
                title="비교할 CSI CSV 파일을 2개 이상 선택",
                initialdir=self.sessions_dir(),
                filetypes=(("CSI CSV", "*.csv"), ("모든 파일", "*.*")),
            )
            selected_paths = [Path(name) for name in filenames]
        if not selected_paths:
            return
        if len(selected_paths) < 2:
            messagebox.showerror("선택 오류", "비교할 CSV 파일을 2개 이상 선택하세요.")
            return
        try:
            self.phase_var.set("비교 분석 중…")
            self.root.update_idletasks()
            show_session_comparison(self.root, selected_paths)
            self.phase_var.set("비교 창 열림")
        except Exception as exc:
            self.phase_var.set("비교 오류")
            messagebox.showerror("비교 오류", str(exc))

    def on_close(self) -> None:
        if self.running:
            if not messagebox.askyesno("종료", "측정을 중지하고 UI를 종료할까요?"):
                return
            self.stop_capture()
            self.root.after(700, self.root.destroy)
        else:
            self.root.destroy()


def main() -> None:
    root = tk.Tk()
    ExperimentApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
