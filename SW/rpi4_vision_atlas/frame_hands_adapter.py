#!/usr/bin/env python3
"""Convert C++ vision results into legacy (left_xy, right_xy) frames."""

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


def _landmarks_xy(value: Any) -> np.ndarray:
    points = np.asarray(value, dtype=np.float32)
    if points.shape != (21, 2):
        raise FrameHandsError(f"landmarks_xy shape must be (21, 2), got {points.shape}")
    if not np.all(np.isfinite(points)):
        raise FrameHandsError("landmarks_xy contains NaN or Inf")
    return points


def frame_hands_from_result(document: Mapping[str, Any]):
    """Return the `(left_xy, right_xy)` pair expected by build_webcam_feature."""

    mirror_input = document.get("mirror_input")
    if not isinstance(mirror_input, bool):
        raise FrameHandsError("mirror_input must be a JSON boolean")

    hands = document.get("hands")
    if not isinstance(hands, list):
        raise FrameHandsError("hands must be a JSON array")

    selected: dict[str, tuple[float, np.ndarray] | None] = {
        "LEFT": None,
        "RIGHT": None,
    }

    for index, hand in enumerate(hands):
        if not isinstance(hand, Mapping):
            raise FrameHandsError(f"hands[{index}] must be an object")

        try:
            raw = float(hand["handedness_raw"])
            confidence = float(hand["hand_confidence"])
            points = _landmarks_xy(hand["landmarks_xy"])
        except KeyError as exc:
            raise FrameHandsError(f"hands[{index}] missing field: {exc.args[0]}") from exc

        if not np.isfinite(confidence) or not 0.0 <= confidence <= 1.0:
            raise FrameHandsError(
                f"hands[{index}].hand_confidence must be finite and in [0, 1]"
            )

        model_hand = _model_hand(raw)
        declared_model = str(hand.get("model_hand", model_hand)).upper()
        if declared_model not in HAND_LABELS or declared_model != model_hand:
            raise FrameHandsError(
                f"hands[{index}].model_hand disagrees with handedness_raw"
            )

        physical_hand = model_hand if mirror_input else OPPOSITE_HAND[model_hand]
        declared_physical = str(
            hand.get("physical_hand", physical_hand)
        ).upper()
        if declared_physical not in {"UNVERIFIED", physical_hand}:
            raise FrameHandsError(
                f"hands[{index}].physical_hand disagrees with mirror_input"
            )

        current = selected[physical_hand]
        if current is None or confidence > current[0]:
            selected[physical_hand] = (confidence, points)

    left = None if selected["LEFT"] is None else selected["LEFT"][1]
    right = None if selected["RIGHT"] is None else selected["RIGHT"][1]
    return left, right


def load_frame_hands(result_json: str | Path):
    with Path(result_json).open("r", encoding="utf-8") as stream:
        document = json.load(stream)
    return frame_hands_from_result(document)


def recording_frames_from_results(
    documents: Iterable[Mapping[str, Any]],
):
    """Build the non-empty frame list expected by build_webcam_feature."""

    recording_frames = []
    expected_mirror = None
    expected_size = None

    for index, document in enumerate(documents):
        if not isinstance(document, Mapping):
            raise FrameHandsError(f"frame {index} must be an object")

        mirror_input = document.get("mirror_input")
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
        if expected_mirror is None:
            expected_mirror, expected_size = signature
        elif signature != (expected_mirror, expected_size):
            raise FrameHandsError(
                f"frame {index} changed mirror_input or image_size_wh"
            )

        left, right = frame_hands_from_result(document)
        if left is not None or right is not None:
            recording_frames.append((left, right))

    return recording_frames


def load_recording_frames(result_json_paths: Iterable[str | Path]):
    documents = []
    for result_json in result_json_paths:
        with Path(result_json).open("r", encoding="utf-8") as stream:
            documents.append(json.load(stream))
    return recording_frames_from_results(documents)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate C++ result.json and print its FrameHands mapping."
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
