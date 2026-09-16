from pathlib import Path
import hashlib

import mediapipe as mp

from mediapipe.framework import calculator_pb2
from mediapipe.python.solution_base import SolutionBase
from mediapipe.python._framework_bindings import validated_graph_config


ROOT = Path(__file__).resolve().parent

MEDIAPIPE_ROOT = (
    Path(mp.__file__).resolve().parent
)

SOURCE_BINARYPB = (
    MEDIAPIPE_ROOT
    / "modules"
    / "hand_landmark"
    / "hand_landmark_tracking_cpu.binarypb"
)

OUTPUT_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "mediapipe_assets"
)

OUTPUT_BINARYPB = (
    OUTPUT_DIR
    / "hands_0_10_21_canonical.binarypb"
)

OUTPUT_TEXT = (
    OUTPUT_DIR
    / "hands_0_10_21_canonical.pbtxt"
)

OUTPUT_INFO = (
    OUTPUT_DIR
    / "hands_0_10_21_info.txt"
)


SIDE_INPUTS = {
    "model_complexity": 1,
    "num_hands": 2,
    "use_prev_landmarks": True,
}

OUTPUTS = [
    "multi_hand_landmarks",
    "multi_hand_world_landmarks",
    "multi_handedness",
]

CALCULATOR_PARAMS = {
    (
        "palmdetectioncpu__"
        "TensorsToDetectionsCalculator."
        "min_score_thresh"
    ): 0.5,

    (
        "handlandmarkcpu__"
        "ThresholdingCalculator."
        "threshold"
    ): 0.5,
}


EXPECTED_PALM_NODE = (
    "palmdetectioncpu__"
    "TensorsToDetectionsCalculator"
)

EXPECTED_HAND_NODE = (
    "handlandmarkcpu__"
    "ThresholdingCalculator"
)


def sha256_file(
    path,
):
    digest = hashlib.sha256()

    with path.open(
        "rb"
    ) as f:
        while True:
            chunk = f.read(
                1024 * 1024
            )

            if not chunk:
                break

            digest.update(
                chunk
            )

    return digest.hexdigest()


def main():
    print(
        "=" * 90
    )

    print(
        "MEDIAPIPE HANDS CANONICAL GRAPH EXPORT"
    )

    print(
        "=" * 90
    )

    print(
        "MediaPipe version:",
        mp.__version__,
    )

    print(
        "Source binarypb  :",
        SOURCE_BINARYPB,
    )


    if (
        mp.__version__
        !=
        "0.10.21"
    ):
        raise RuntimeError(
            "MediaPipe version must be 0.10.21"
        )


    if (
        not SOURCE_BINARYPB.exists()
    ):
        raise RuntimeError(
            "Source binarypb not found"
        )


    # ========================================================
    # Same first stage as SolutionBase:
    #
    # ValidatedGraphConfig
    #   -> canonical / expanded binary_config
    # ========================================================

    validated = (
        validated_graph_config
        .ValidatedGraphConfig()
    )

    validated.initialize(
        binary_graph_path=str(
            SOURCE_BINARYPB
        )
    )


    canonical = (
        calculator_pb2
        .CalculatorGraphConfig()
    )

    canonical.ParseFromString(
        validated.binary_config
    )


    print()
    print(
        "Canonical nodes before modification:",
        len(
            canonical.node
        ),
    )


    names_before = {
        node.name
        for node
        in canonical.node
    }


    if (
        EXPECTED_PALM_NODE
        not in
        names_before
    ):
        raise RuntimeError(
            "Palm threshold node not found"
        )


    if (
        EXPECTED_HAND_NODE
        not in
        names_before
    ):
        raise RuntimeError(
            "Hand threshold node not found"
        )


    # ========================================================
    # Same calculator option modification function used by
    # MediaPipe Python SolutionBase.
    #
    # We intentionally reuse the installed 0.10.21
    # implementation instead of independently reproducing it.
    # ========================================================

    helper = object.__new__(
        SolutionBase
    )

    helper._modify_calculator_options(
        canonical,
        CALCULATOR_PARAMS,
    )


    # ========================================================
    # Verify actual values after modification.
    # ========================================================

    palm_value = None
    hand_value = None


    for node in canonical.node:

        if (
            node.name
            ==
            EXPECTED_PALM_NODE
        ):
            from mediapipe.calculators.tensor import (
                tensors_to_detections_calculator_pb2
            )

            options_type = (
                tensors_to_detections_calculator_pb2
                .TensorsToDetectionsCalculatorOptions
            )

            palm_options = (
                node.options.Extensions[
                    options_type.ext
                ]
            )

            palm_value = float(
                palm_options.min_score_thresh
            )


        if (
            node.name
            ==
            EXPECTED_HAND_NODE
        ):
            from mediapipe.calculators.util import (
                thresholding_calculator_pb2
            )

            options_type = (
                thresholding_calculator_pb2
                .ThresholdingCalculatorOptions
            )

            hand_options = (
                node.options.Extensions[
                    options_type.ext
                ]
            )

            hand_value = float(
                hand_options.threshold
            )


    if (
        palm_value is None
        or
        hand_value is None
    ):
        raise RuntimeError(
            "Modified threshold could not be read"
        )


    if (
        palm_value
        !=
        0.5
    ):
        raise RuntimeError(
            f"Palm threshold mismatch: "
            f"{palm_value}"
        )


    if (
        hand_value
        !=
        0.5
    ):
        raise RuntimeError(
            f"Hand threshold mismatch: "
            f"{hand_value}"
        )


    # ========================================================
    # Export final canonical graph.
    #
    # Side packets are intentionally NOT embedded here.
    # Python Hands passes them to start_run().
    #
    # C++ will do the same:
    #
    # num_hands          = 2
    # model_complexity   = 1
    # use_prev_landmarks = true
    # ========================================================

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    OUTPUT_BINARYPB.write_bytes(
        canonical.SerializeToString()
    )


    OUTPUT_TEXT.write_text(
        str(
            canonical
        ),
        encoding="utf-8",
    )


    source_sha = sha256_file(
        SOURCE_BINARYPB
    )

    canonical_sha = sha256_file(
        OUTPUT_BINARYPB
    )


    OUTPUT_INFO.write_text(
        "\n".join(
            [
                "mediapipe_version=0.10.21",

                (
                    "source_binarypb_sha256="
                    f"{source_sha}"
                ),

                (
                    "canonical_binarypb_sha256="
                    f"{canonical_sha}"
                ),

                "num_hands=2",
                "model_complexity=1",
                "use_prev_landmarks=true",
                "min_detection_confidence=0.5",
                "min_tracking_confidence=0.5",

                (
                    "hand_landmark_full_sha256="
                    "11c272b891e1a99ab034208e23937a8"
                    "008388cf11ed2a9d776ed3d01d0ba00e3"
                ),

                (
                    "palm_detection_full_sha256="
                    "1b14e9422c6ad006cde6581a46c8b90"
                    "dd573c07ab7f3934b5589e7cea3f89a54"
                ),
            ]
        )
        +
        "\n",
        encoding="utf-8",
    )


    print()
    print(
        "===== FINAL GRAPH ====="
    )

    print(
        "nodes:",
        len(
            canonical.node
        ),
    )

    print(
        "palm detection threshold:",
        palm_value,
    )

    print(
        "tracking threshold      :",
        hand_value,
    )


    print()
    print(
        "===== SIDE PACKETS ====="
    )

    print(
        "num_hands          :",
        SIDE_INPUTS[
            "num_hands"
        ],
    )

    print(
        "model_complexity   :",
        SIDE_INPUTS[
            "model_complexity"
        ],
    )

    print(
        "use_prev_landmarks :",
        SIDE_INPUTS[
            "use_prev_landmarks"
        ],
    )


    print()
    print(
        "===== SHA256 ====="
    )

    print(
        "source canonical source:",
        source_sha,
    )

    print(
        "final canonical graph :",
        canonical_sha,
    )


    print()
    print(
        "Output binary:",
        OUTPUT_BINARYPB,
    )

    print(
        "Output text  :",
        OUTPUT_TEXT,
    )

    print(
        "Output info  :",
        OUTPUT_INFO,
    )


    print()
    print(
        "=" * 90
    )

    print(
        "MEDIAPIPE HANDS CANONICAL GRAPH EXPORT PASS"
    )

    print(
        "=" * 90
    )


if __name__ == "__main__":
    main()