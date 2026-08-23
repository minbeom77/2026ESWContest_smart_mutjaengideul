#!/usr/bin/env python3
"""Summarize a captured CSI CSV and display two diagnostic figures."""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


def amplitude_centered(values: list[int]) -> np.ndarray:
    raw = np.asarray(values, dtype=np.float64)
    raw = raw[: raw.size - (raw.size % 2)]
    imag = raw[0::2]
    real = raw[1::2]
    amplitude_db = 20.0 * np.log10(np.hypot(real, imag) + 1e-9)
    return amplitude_db - np.median(amplitude_db)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("file", type=Path)
    parser.add_argument("--save-prefix", type=Path)
    args = parser.parse_args()

    rows = []
    with args.file.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            try:
                row["host_time_unix"] = float(row["host_time_unix"])
                row["seq"] = int(row["seq"])
                row["rssi"] = int(row["rssi"])
                row["data"] = json.loads(row["data_json"])
                rows.append(row)
            except (ValueError, TypeError, json.JSONDecodeError):
                continue

    if len(rows) < 2:
        print("분석할 유효 프레임이 2개 미만입니다.")
        return 1

    length_counts = Counter(len(row["data"]) for row in rows)
    modal_length = length_counts.most_common(1)[0][0]
    selected = [row for row in rows if len(row["data"]) == modal_length]
    amplitudes = np.vstack([amplitude_centered(row["data"]) for row in selected])
    times = np.asarray([row["host_time_unix"] for row in selected])
    times -= times[0]
    scores = np.zeros(len(selected), dtype=np.float64)
    scores[1:] = np.mean(np.abs(np.diff(amplitudes, axis=0)), axis=1)
    rssis = np.asarray([row["rssi"] for row in selected], dtype=np.float64)

    duration = max(times[-1], 1e-9)
    seqs = np.asarray([row["seq"] for row in selected], dtype=np.int64)
    missing = max(0, int(seqs[-1] - seqs[0] + 1 - len(seqs)))

    print(f"파일: {args.file}")
    print(f"전체 유효 프레임: {len(rows):,}")
    print(f"대표 CSI 길이: {modal_length} raw values ({modal_length // 2} complex bins)")
    print(f"대표 길이 프레임: {len(selected):,}")
    print(f"시간: {duration:.2f} s")
    print(f"평균 수집률: {(len(selected) - 1) / duration:.2f} fps")
    print(f"시퀀스 누락 추정: {missing:,}")
    print(f"RSSI: mean={np.mean(rssis):.2f} dBm, std={np.std(rssis):.2f}")
    print(
        "움직임 점수: "
        f"median={np.median(scores):.4f}, "
        f"p95={np.percentile(scores, 95):.4f}, "
        f"max={np.max(scores):.4f}"
    )
    print(f"CSI 길이 분포: {dict(length_counts.most_common(8))}")

    heat_figure = plt.figure("Captured CSI amplitude heatmap")
    heat_axis = heat_figure.add_axes((0.10, 0.12, 0.84, 0.80))
    heat_axis.imshow(amplitudes, aspect="auto", origin="lower", interpolation="nearest")
    heat_axis.set_xlabel("Subcarrier index")
    heat_axis.set_ylabel("Frame")
    heat_axis.set_title("Median-normalized CSI amplitude")

    score_figure = plt.figure("Captured movement score")
    score_axis = score_figure.add_axes((0.12, 0.14, 0.82, 0.78))
    score_axis.plot(times, scores)
    score_axis.set_xlabel("Seconds")
    score_axis.set_ylabel("Mean frame-to-frame change (dB)")
    score_axis.set_title("Movement score")
    score_axis.grid(True, alpha=0.3)

    if args.save_prefix:
        args.save_prefix.parent.mkdir(parents=True, exist_ok=True)
        heat_path = args.save_prefix.with_name(args.save_prefix.name + "_heatmap.png")
        score_path = args.save_prefix.with_name(args.save_prefix.name + "_score.png")
        heat_figure.savefig(heat_path, dpi=160, bbox_inches="tight")
        score_figure.savefig(score_path, dpi=160, bbox_inches="tight")
        print(f"저장: {heat_path}")
        print(f"저장: {score_path}")

    plt.show()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
