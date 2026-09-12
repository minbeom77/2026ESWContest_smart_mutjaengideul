import importlib.util
from pathlib import Path
from types import SimpleNamespace

import numpy as np


ROOT = Path(__file__).resolve().parent

SOURCE_PATH = (
    ROOT
    / "06j_webcam_local_template.py"
)

OUTPUT_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "hand_input_frozen"
)

WIDTH = 640
HEIGHT = 480
LANDMARK_COUNT = 21


def load_source_module():
    spec = importlib.util.spec_from_file_location(
        "source_06j",
        SOURCE_PATH,
    )

    if (
        spec is None
        or
        spec.loader is None
    ):
        raise RuntimeError(
            "06j module load 실패"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(
        module
    )

    return module


def make_landmarks(
    seed,
):
    points = []

    for index in range(
        LANDMARK_COUNT
    ):
        # ====================================================
        # MediaPipe landmark.x / landmark.y are protobuf
        # float fields.
        #
        # Python receives that float32 value as Python float.
        #
        # Therefore the synthetic fixture must quantize to
        # float32 BEFORE calling frozen extract_hands().
        # ====================================================

        x32 = np.float32(
            (
                seed
                +
                0.0137
                *
                index
            )
            %
            1.0
        )

        y32 = np.float32(
            (
                seed
                *
                0.5
                +
                0.0213
                *
                index
            )
            %
            1.0
        )

        points.append(
            SimpleNamespace(
                x=float(
                    x32
                ),
                y=float(
                    y32
                ),
            )
        )

    return SimpleNamespace(
        landmark=points
    )


def make_detection(
    label,
    confidence,
    seed,
):
    hand_landmarks = (
        make_landmarks(
            seed
        )
    )

    confidence32 = np.float32(
        confidence
    )

    handedness = SimpleNamespace(
        classification=[
            SimpleNamespace(
                label=label,
                score=float(
                    confidence32
                ),
            )
        ]
    )

    return (
        hand_landmarks,
        handedness,
    )


def make_results(
    detections,
):
    if not detections:
        return SimpleNamespace(
            multi_hand_landmarks=None,
            multi_handedness=None,
        )

    return SimpleNamespace(
        multi_hand_landmarks=[
            detection[0]
            for detection
            in detections
        ],

        multi_handedness=[
            detection[1]
            for detection
            in detections
        ],
    )


def flatten_xy(
    detected,
    label,
):
    if label not in detected:
        return np.zeros(
            (
                LANDMARK_COUNT,
                2,
            ),
            dtype=np.float32,
        )

    xy = np.asarray(
        detected[
            label
        ][
            "xy"
        ],
        dtype=np.float32,
    )

    if (
        xy.shape
        !=
        (
            LANDMARK_COUNT,
            2,
        )
    ):
        raise RuntimeError(
            f"{label} shape="
            f"{xy.shape}"
        )

    return xy


def run_case(
    source,
    name,
    detections,
):
    results = make_results(
        detections
    )

    detected = (
        source.extract_hands(
            results,
            WIDTH,
            HEIGHT,
        )
    )

    has_left = (
        "LEFT"
        in detected
    )

    has_right = (
        "RIGHT"
        in detected
    )

    left_xy = flatten_xy(
        detected,
        "LEFT",
    )

    right_xy = flatten_xy(
        detected,
        "RIGHT",
    )

    left_confidence = (
        float(
            detected[
                "LEFT"
            ][
                "confidence"
            ]
        )
        if has_left
        else
        0.0
    )

    right_confidence = (
        float(
            detected[
                "RIGHT"
            ][
                "confidence"
            ]
        )
        if has_right
        else
        0.0
    )

    return {
        "name":
            name,

        "has_left":
            has_left,

        "has_right":
            has_right,

        "left_confidence":
            left_confidence,

        "right_confidence":
            right_confidence,

        "left_xy":
            left_xy,

        "right_xy":
            right_xy,
    }


def main():
    print(
        "=" * 90
    )

    print(
        "HAND INPUT FROZEN PYTHON EXPECTED EXPORT"
    )

    print(
        "=" * 90
    )

    source = load_source_module()


    # ========================================================
    # CASE 1
    # Normal LEFT + RIGHT
    # ========================================================

    case_both = run_case(
        source,
        "BOTH_NORMAL",
        [
            make_detection(
                "Left",
                0.81,
                0.11,
            ),

            make_detection(
                "Right",
                0.92,
                0.37,
            ),
        ],
    )


    # ========================================================
    # CASE 2
    # Duplicate LEFT:
    # higher confidence replaces first.
    # ========================================================

    case_duplicate_higher = run_case(
        source,
        "DUPLICATE_LEFT_HIGHER",
        [
            make_detection(
                "Left",
                0.60,
                0.15,
            ),

            make_detection(
                "Left",
                0.90,
                0.55,
            ),
        ],
    )


    # ========================================================
    # CASE 3
    # Equal confidence:
    # strict ">" means first RIGHT remains.
    # ========================================================

    case_duplicate_equal = run_case(
        source,
        "DUPLICATE_RIGHT_EQUAL",
        [
            make_detection(
                "Right",
                0.75,
                0.21,
            ),

            make_detection(
                "Right",
                0.75,
                0.71,
            ),
        ],
    )


    # ========================================================
    # CASE 4
    # Unknown ignored.
    # lowercase left -> LEFT.
    # ========================================================

    case_invalid_label = run_case(
        source,
        "INVALID_LABEL_AND_LOWERCASE",
        [
            make_detection(
                "Unknown",
                0.99,
                0.44,
            ),

            make_detection(
                "left",
                0.33,
                0.63,
            ),
        ],
    )


    # ========================================================
    # CASE 5
    # No hands.
    # ========================================================

    case_empty = run_case(
        source,
        "EMPTY",
        [],
    )


    cases = [
        case_both,
        case_duplicate_higher,
        case_duplicate_equal,
        case_invalid_label,
        case_empty,
    ]


    # ========================================================
    # Semantic checks
    # ========================================================

    if (
        not case_both[
            "has_left"
        ]
        or
        not case_both[
            "has_right"
        ]
    ):
        raise RuntimeError(
            "BOTH_NORMAL failed"
        )


    if (
        not case_duplicate_higher[
            "has_left"
        ]
        or
        case_duplicate_higher[
            "has_right"
        ]
    ):
        raise RuntimeError(
            "DUPLICATE_LEFT_HIGHER failed"
        )


    if (
        not case_duplicate_equal[
            "has_right"
        ]
        or
        case_duplicate_equal[
            "has_left"
        ]
    ):
        raise RuntimeError(
            "DUPLICATE_RIGHT_EQUAL failed"
        )


    if (
        not case_invalid_label[
            "has_left"
        ]
        or
        case_invalid_label[
            "has_right"
        ]
    ):
        raise RuntimeError(
            "INVALID_LABEL_AND_LOWERCASE failed"
        )


    if (
        case_empty[
            "has_left"
        ]
        or
        case_empty[
            "has_right"
        ]
    ):
        raise RuntimeError(
            "EMPTY failed"
        )


    # ========================================================
    # Export
    # ========================================================

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    for case in cases:
        name = case[
            "name"
        ].lower()


        flags = np.asarray(
            [
                1
                if case[
                    "has_left"
                ]
                else
                0,

                1
                if case[
                    "has_right"
                ]
                else
                0,
            ],
            dtype=np.int32,
        )


        confidences = np.asarray(
            [
                case[
                    "left_confidence"
                ],

                case[
                    "right_confidence"
                ],
            ],
            dtype=np.float64,
        )


        flags.tofile(
            OUTPUT_DIR
            /
            f"expected_{name}_flags.bin"
        )


        confidences.tofile(
            OUTPUT_DIR
            /
            f"expected_{name}_confidence.bin"
        )


        case[
            "left_xy"
        ].tofile(
            OUTPUT_DIR
            /
            f"expected_{name}_left_21x2.bin"
        )


        case[
            "right_xy"
        ].tofile(
            OUTPUT_DIR
            /
            f"expected_{name}_right_21x2.bin"
        )


    (
        OUTPUT_DIR
        /
        "fixture_info.txt"
    ).write_text(
        "\n".join(
            [
                (
                    "source="
                    "06j_webcam_local_template.py"
                ),
                "input_precision=mediapipe_float32",
                f"width={WIDTH}",
                f"height={HEIGHT}",
                "landmark_count=21",
                "case_count=5",
                (
                    "coordinate_rule="
                    "x=(1.0-landmark.x)*width;"
                    "y=landmark.y*height;"
                    "dtype=float32"
                ),
                (
                    "duplicate_rule="
                    "strict confidence >;"
                    "equal keeps first"
                ),
            ]
        ),
        encoding="utf-8",
    )


    print()

    for case in cases:
        print(
            "----------------------------------------"
        )

        print(
            case[
                "name"
            ]
        )

        print(
            "----------------------------------------"
        )

        print(
            "has_left        :",
            case[
                "has_left"
            ],
        )

        print(
            "has_right       :",
            case[
                "has_right"
            ],
        )

        print(
            "left confidence :",
            case[
                "left_confidence"
            ],
        )

        print(
            "right confidence:",
            case[
                "right_confidence"
            ],
        )


        if (
            case[
                "has_left"
            ]
        ):
            print(
                "LEFT first XY    :",
                case[
                    "left_xy"
                ][0].tolist(),
            )


        if (
            case[
                "has_right"
            ]
        ):
            print(
                "RIGHT first XY   :",
                case[
                    "right_xy"
                ][0].tolist(),
            )


        print()


    print(
        "Output:",
        OUTPUT_DIR,
    )

    print()

    print(
        "=" * 90
    )

    print(
        "HAND INPUT FROZEN PYTHON EXPECTED EXPORT PASS"
    )

    print(
        "=" * 90
    )


if __name__ == "__main__":
    main()