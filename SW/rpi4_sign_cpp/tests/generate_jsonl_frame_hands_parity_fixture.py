#!/usr/bin/env python3

import argparse
import importlib.util
import json
import struct
from pathlib import Path

import numpy as np


def load_adapter(adapter_path: Path):
    spec = importlib.util.spec_from_file_location(
        "frame_hands_adapter_reference",
        adapter_path,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import adapter: {adapter_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def landmarks(value: float):
    points = []

    for index in range(21):
        x = value + index * 0.12345
        y = value + index * 0.23456
        points.append([x, y])

    return points


def hand(raw: float, confidence: float, value: float):
    model = "RIGHT" if raw > 0.5 else "LEFT"
    physical = "LEFT" if model == "RIGHT" else "RIGHT"

    return {
        "handedness_raw": raw,
        "model_hand": model,
        "physical_hand": physical,
        "hand_confidence": confidence,
        "landmarks_xy": landmarks(value),
    }


def frame(hands):
    return {
        "mirror_input": True,
        "image_size_wh": [640, 480],
        "hands": hands,
    }


def write_jsonl(path: Path, documents):
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for document in documents:
            stream.write(json.dumps(document, separators=(",", ":")))
            stream.write("\n")


def float32_hex(value) -> str:
    packed = struct.pack("<f", np.float32(value))
    bits = struct.unpack("<I", packed)[0]
    return f"{bits:08X}"


def write_dump(path: Path, result):
    frames = result

    with path.open("w", encoding="utf-8", newline="\n") as stream:
        stream.write(f"frames {len(frames)}\n")

        for frame_index, (left, right) in enumerate(frames):
            has_left = left is not None
            has_right = right is not None

            stream.write(
                f"frame {frame_index} "
                f"left {1 if has_left else 0} "
                f"right {1 if has_right else 0}\n"
            )

            if has_left:
                array = np.asarray(left, dtype=np.float32)

                for point_index in range(21):
                    stream.write(
                        f"L {point_index} "
                        f"{float32_hex(array[point_index, 0])} "
                        f"{float32_hex(array[point_index, 1])}\n"
                    )

            if has_right:
                array = np.asarray(right, dtype=np.float32)

                for point_index in range(21):
                    stream.write(
                        f"R {point_index} "
                        f"{float32_hex(array[point_index, 0])} "
                        f"{float32_hex(array[point_index, 1])}\n"
                    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--adapter",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
    )

    args = parser.parse_args()

    adapter = load_adapter(args.adapter)

    args.output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    # --------------------------------------------------------
    # Case 1: single-hand recording
    #
    # Raw values deliberately cross 0.5.
    # Median = 0.30.
    #
    # model LEFT -> physical RIGHT.
    #
    # The empty frame must be excluded.
    # --------------------------------------------------------

    raw_values = [
        0.20,
        0.25,
        0.70,
        None,
        0.30,
        0.65,
        0.28,
        0.32,
    ]

    single_documents = []

    for index, raw in enumerate(raw_values):
        if raw is None:
            single_documents.append(frame([]))
        else:
            single_documents.append(
                frame([
                    hand(
                        raw=raw,
                        confidence=0.80 + index * 0.01,
                        value=10.0 + index,
                    )
                ])
            )

    single_jsonl = (
        args.output_dir /
        "single_hand.jsonl"
    )

    write_jsonl(
        single_jsonl,
        single_documents,
    )

    single_frames = adapter.load_recording_frames(
        [single_jsonl]
    )

    write_dump(
        args.output_dir /
        "single_hand_expected.txt",
        single_frames,
    )

    # --------------------------------------------------------
    # Case 2: multi-hand recording
    #
    # Exercises:
    #   - two physical slots
    #   - duplicate physical slot
    #   - higher confidence wins
    #   - equal confidence keeps earlier detection
    #   - empty frame exclusion
    # --------------------------------------------------------

    multi_documents = [
        frame([]),

        frame([
            hand(0.80, 0.70, 20.0),
            hand(0.90, 0.95, 30.0),
        ]),

        frame([
            hand(0.80, 0.90, 40.0),
            hand(0.20, 0.85, 50.0),
        ]),

        frame([
            hand(0.90, 0.80, 60.0),
            hand(0.85, 0.80, 70.0),
        ]),

        frame([]),
    ]

    multi_jsonl = (
        args.output_dir /
        "multi_hand.jsonl"
    )

    write_jsonl(
        multi_jsonl,
        multi_documents,
    )

    multi_frames = adapter.load_recording_frames(
        [multi_jsonl]
    )

    write_dump(
        args.output_dir /
        "multi_hand_expected.txt",
        multi_frames,
    )

    print("JSONL FRAMEHANDS PYTHON FIXTURE EXPORT PASS")
    print("single frames:", len(single_frames))
    print("multi frames :", len(multi_frames))
    print("output       :", args.output_dir)


if __name__ == "__main__":
    main()