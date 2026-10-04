#!/usr/bin/env python3
"""Convert C++ vision JSON/JSONL into legacy ``(left_xy, right_xy)`` frames."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterable, Mapping

import numpy as np


HAND_LABELS = {"LEFT", "RIGHT"}
OPPOSITE_HAND = {"LEFT": "RIGHT", "RIGHT": "LEFT"}


class FrameHandsError(ValueError):
    """Raised when a C++ result does not satisfy the FrameHands contract."""


def _model_hand(handedness_raw: float) -> str:
    if not np.isfinite(handedness_raw) or not 0.0 <= handedness_raw <= 1.0:
        raise FrameHandsError(
            f"handedness_raw must be finite and in [0, 1], got {handedness_raw}"
        )
    return "RIGHT" if handedness_raw > 0.5 else "LEFT"


def _physical_hand(handedness_raw: float) -> str:
    """Map this ONNX model's output to the anatomical hand.

    RPi4 measurements with mirrored and unflipped inputs showed that the
    model's named output is opposite to the physical hand in both cases.
    Mirroring changes coordinates, not this model-specific mapping.
    """

    return OPPOSITE_HAND[_model_hand(handedness_raw)]


def _landmarks_xy(value: Any) -> np.ndarray:
    points = np.asarray(value, dtype=np.float32)
    if points.shape != (21, 2):
        raise FrameHandsError(f"landmarks_xy shape must be (21, 2), got {points.shape}")
    if not np.all(np.isfinite(points)):
        raise FrameHandsError("landmarks_xy contains NaN or Inf")
    return points


def _validated_hands(document: Mapping[str, Any]):
    mirror_input = document.get("mirror_input")
    if not isinstance(mirror_input, bool):
        raise FrameHandsError("mirror_input must be a JSON boolean")

    hands = document.get("hands")
    if not isinstance(hands, list):
        raise FrameHandsError("hands must be a JSON array")

    validated = []
    for index, hand in enumerate(hands):
        if not isinstance(hand, Mapping):
            raise FrameHandsError(f"hands[{index}] must be an object")
        try:
            raw = float(hand["handedness_raw"])
            confidence = float(hand["hand_confidence"])
            points = _landmarks_xy(hand["landmarks_xy"])
        except KeyError as exc:
            raise FrameHandsError(f"hands[{index}] missing field: {exc.args[0]}") from exc

        model_hand = _model_hand(raw)
        if not np.isfinite(confidence) or not 0.0 <= confidence <= 1.0:
            raise FrameHandsError(
                f"hands[{index}].hand_confidence must be finite and in [0, 1]"
            )

        declared_model = str(hand.get("model_hand", model_hand)).upper()
        if declared_model not in HAND_LABELS or declared_model != model_hand:
            raise FrameHandsError(
                f"hands[{index}].model_hand disagrees with handedness_raw"
            )

        physical = _physical_hand(raw)
        declared_physical = str(hand.get("physical_hand", physical)).upper()
        if declared_physical not in {"UNVERIFIED", physical}:
            raise FrameHandsError(
                f"hands[{index}].physical_hand disagrees with handedness_raw"
            )

        validated.append(
            {
                "raw": raw,
                "confidence": confidence,
                "points": points,
                "physical": physical,
            }
        )
    return validated


def frame_hands_from_result(document: Mapping[str, Any]):
    """Return one frame using the model-specific physical-hand mapping."""

    selected: dict[str, tuple[float, np.ndarray] | None] = {
        "LEFT": None,
        "RIGHT": None,
    }
    for hand in _validated_hands(document):
        physical = hand["physical"]
        current = selected[physical]
        if current is None or hand["confidence"] > current[0]:
            selected[physical] = (hand["confidence"], hand["points"])

    left = None if selected["LEFT"] is None else selected["LEFT"][1]
    right = None if selected["RIGHT"] is None else selected["RIGHT"][1]
    return left, right


def _validate_sequence_signature(
    document: Mapping[str, Any], index: int, expected_signature
):
    mirror_input = document.get("mirror_input")
    if not isinstance(mirror_input, bool):
        raise FrameHandsError(f"frame {index}.mirror_input must be a JSON boolean")
    image_size = document.get("image_size_wh")
    if (
        not isinstance(image_size, list)
        or len(image_size) != 2
        or any(not isinstance(value, int) or value <= 0 for value in image_size)
    ):
        raise FrameHandsError(
            f"frame {index}.image_size_wh must contain two positive integers"
        )
    signature = (mirror_input, tuple(image_size))
    if expected_signature is not None and signature != expected_signature:
        raise FrameHandsError(
            f"frame {index} changed mirror_input or image_size_wh"
        )
    return signature


def recording_frames_from_results(
    documents: Iterable[Mapping[str, Any]],
):
    """Build frames, stabilizing a one-hand clip with its median raw score.

    If every accepted frame contains at most one hand, the clip is one track.
    Its median handedness score determines one physical side for the complete
    sequence, preventing transient 0.5 crossings from swapping LEFT/RIGHT.
    Multi-hand frames retain per-detection mapping; two-hand track association
    remains a separate runtime concern.
    """

    parsed = []
    expected_signature = None
    maximum_hands = 0

    for index, document in enumerate(documents):
        if not isinstance(document, Mapping):
            raise FrameHandsError(f"frame {index} must be an object")
        signature = _validate_sequence_signature(document, index, expected_signature)
        if expected_signature is None:
            expected_signature = signature
        hands = _validated_hands(document)
        maximum_hands = max(maximum_hands, len(hands))
        parsed.append(hands)

    if maximum_hands <= 1:
        observations = [hands[0] for hands in parsed if hands]
        if not observations:
            return []
        median_raw = float(np.median([hand["raw"] for hand in observations]))
        physical = _physical_hand(median_raw)
        return [
            (hand["points"], None) if physical == "LEFT" else (None, hand["points"])
            for hand in observations
        ]

    recording_frames = []
    for hands in parsed:
        selected = {"LEFT": None, "RIGHT": None}
        for hand in hands:
            physical = hand["physical"]
            current = selected[physical]
            if current is None or hand["confidence"] > current["confidence"]:
                selected[physical] = hand
        left = None if selected["LEFT"] is None else selected["LEFT"]["points"]
        right = None if selected["RIGHT"] is None else selected["RIGHT"]["points"]
        if left is not None or right is not None:
            recording_frames.append((left, right))
    return recording_frames


def _load_documents(path: str | Path):
    path = Path(path)
    with path.open("r", encoding="utf-8") as stream:
        first = stream.read(1)
        stream.seek(0)
        if first == "{":
            try:
                return [json.load(stream)]
            except json.JSONDecodeError as exc:
                if "Extra data" not in str(exc):
                    raise
                stream.seek(0)
        documents = []
        for line_number, line in enumerate(stream, 1):
            if line.strip():
                try:
                    documents.append(json.loads(line))
                except json.JSONDecodeError as exc:
                    raise FrameHandsError(
                        f"{path}: invalid JSONL at line {line_number}: {exc}"
                    ) from exc
        return documents


def load_frame_hands(result_json: str | Path):
    documents = _load_documents(result_json)
    if len(documents) != 1:
        raise FrameHandsError("load_frame_hands requires exactly one JSON document")
    return frame_hands_from_result(documents[0])


def load_recording_frames(result_json_paths: Iterable[str | Path]):
    documents = []
    for result_json in result_json_paths:
        documents.extend(_load_documents(result_json))
    return recording_frames_from_results(documents)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate C++ result JSON/JSONL and print its FrameHands mapping."
    )
    parser.add_argument("result_json", type=Path, nargs="+")
    args = parser.parse_args()

    frames = load_recording_frames(args.result_json)
    print("Accepted frames:", len(frames))
    if frames:
        left, right = frames[0]
        print("First LEFT:", "None" if left is None else left.shape)
        print("First RIGHT:", "None" if right is None else right.shape)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
