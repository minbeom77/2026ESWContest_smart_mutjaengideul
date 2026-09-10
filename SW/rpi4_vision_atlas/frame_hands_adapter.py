#!/usr/bin/env python3
"""Convert one C++ vision result into the legacy (left_xy, right_xy) frame."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Mapping

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


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate C++ result.json and print its FrameHands mapping."
    )
    parser.add_argument("result_json", type=Path)
    args = parser.parse_args()

    left, right = load_frame_hands(args.result_json)
    print("LEFT:", "None" if left is None else left.shape)
    print("RIGHT:", "None" if right is None else right.shape)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
