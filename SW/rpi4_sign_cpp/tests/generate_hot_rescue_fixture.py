from pathlib import Path
import importlib.util

import numpy as np


# ============================================================
# Constants
# ============================================================

REFERENCE_COUNT = 60
TARGET_FRAMES = 80
FULL_DIM = 172
LOCAL_DIM = 84

POSITIVE_SOURCE_INDEX = 0
POSITIVE_TARGET_REFERENCE_INDEX = 0

POSITIVE_ALPHA = np.float32(
    0.300000012
)

NEGATIVE_SOURCE_INDEX = 2

STAGE_BASE = 0
STAGE_HOT_RESCUE = 1
STAGE_AIRCON_COLD_LAST40 = 2


# ============================================================
# Paths
# ============================================================

REPO_ROOT = Path(__file__).resolve().parents[3]

FROZEN_07G_PATH = (
    REPO_ROOT
    / "07g_webcam_15class_final_frozen.py"
)

SOURCE_NPZ_PATH = (
    REPO_ROOT
    / "diagnostics_v3"
    / "06v_hot_rescue_margin_trials.npz"
)

RUNTIME_DIR = (
    REPO_ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "runtime_data"
)

TWOHAND_LOCAL_PATH = (
    RUNTIME_DIR
    / "twohand_local.bin"
)

TWOHAND_CLASS_IDS_PATH = (
    RUNTIME_DIR
    / "twohand_class_ids.bin"
)

FIXTURE_DIR = (
    REPO_ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "hot_rescue"
)


# ============================================================
# Frozen 07g loader
# ============================================================

def load_frozen_07g():
    spec = importlib.util.spec_from_file_location(
        "frozen_07g",
        FROZEN_07G_PATH,
    )

    if (
        spec is None
        or spec.loader is None
    ):
        raise RuntimeError(
            "Failed to load frozen 07g"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(
        module
    )

    return module


# ============================================================
# Stage code
# ============================================================

def stage_to_code(
    stage,
):
    if stage == "TWOHAND_BASE_LOCAL":
        return STAGE_BASE

    if stage == "TWOHAND_HOT_HANDSHAPE_RESCUE":
        return STAGE_HOT_RESCUE

    if stage == "TWOHAND_AIRCON_COLD_LAST40":
        return STAGE_AIRCON_COLD_LAST40

    raise RuntimeError(
        f"Unknown stage: {stage}"
    )


# ============================================================
# Expected result packing
#
# float32 [5]:
#   0 base_margin
#   1 hot_score
#   2 base_hs_score
#   3 delta
#   4 threshold
#
# int32 [5]:
#   0 base_id
#   1 hot_evaluated
#   2 rescued
#   3 final_id
#   4 stage_code
# ============================================================

def pack_expected(
    result,
):
    hot_info = result[
        "hot_info"
    ]

    hot_evaluated = (
        hot_info
        is not None
    )

    if not hot_evaluated:
        raise RuntimeError(
            "HOT fixture requires "
            "hot_info to be present"
        )

    expected_float = np.asarray(
        [
            result[
                "base_margin"
            ],
            hot_info[
                "hot_score"
            ],
            hot_info[
                "base_hs_score"
            ],
            hot_info[
                "delta"
            ],
            hot_info[
                "threshold"
            ],
        ],
        dtype=np.float32,
    )

    expected_int = np.asarray(
        [
            int(
                result[
                    "base_id"
                ]
            ),
            int(
                hot_evaluated
            ),
            int(
                bool(
                    hot_info[
                        "rescued"
                    ]
                )
            ),
            int(
                result[
                    "final_id"
                ]
            ),
            int(
                stage_to_code(
                    result[
                        "stage"
                    ]
                )
            ),
        ],
        dtype=np.int32,
    )

    return (
        expected_float,
        expected_int,
    )


# ============================================================
# Print result
# ============================================================

def print_case(
    name,
    result,
):
    hot_info = result[
        "hot_info"
    ]

    print(
        "----------------------------------------"
    )

    print(
        name
    )

    print(
        "----------------------------------------"
    )

    print(
        "base_id       :",
        int(
            result[
                "base_id"
            ]
        ),
    )

    print(
        "base_margin   :",
        f"{float(result['base_margin']):+.9f}",
    )

    if hot_info is None:
        print(
            "hot evaluated : False"
        )

    else:
        print(
            "hot evaluated : True"
        )

        print(
            "hot_score     :",
            f"{float(hot_info['hot_score']):.9f}",
        )

        print(
            "base_hs_score :",
            f"{float(hot_info['base_hs_score']):.9f}",
        )

        print(
            "delta         :",
            f"{float(hot_info['delta']):+.9f}",
        )

        print(
            "threshold     :",
            f"{float(hot_info['threshold']):+.9f}",
        )

        print(
            "rescued       :",
            bool(
                hot_info[
                    "rescued"
                ]
            ),
        )

    print(
        "final_id      :",
        int(
            result[
                "final_id"
            ]
        ),
    )

    print(
        "stage         :",
        result[
            "stage"
        ],
    )

    print()


# ============================================================
# Main
# ============================================================

def main():
    print(
        "========================================"
    )
    print(
        "HOT RESCUE PYTHON FIXTURE GENERATOR"
    )
    print(
        "========================================"
    )
    print()

    print(
        "IMPORTANT:"
    )
    print(
        "Positive case is TEST-ONLY interpolation."
    )
    print(
        "It is NOT real-world recognition evidence."
    )
    print()


    # ========================================================
    # 1. Frozen Python
    # ========================================================

    frozen_07g = load_frozen_07g()


    # ========================================================
    # 2. Current runtime references
    # ========================================================

    runtime_local_raw = np.fromfile(
        TWOHAND_LOCAL_PATH,
        dtype=np.float32,
    )

    expected_count = (
        REFERENCE_COUNT
        *
        TARGET_FRAMES
        *
        LOCAL_DIM
    )

    if (
        runtime_local_raw.size
        !=
        expected_count
    ):
        raise RuntimeError(
            "twohand_local.bin size mismatch"
        )

    runtime_local = (
        runtime_local_raw
        .reshape(
            REFERENCE_COUNT,
            TARGET_FRAMES,
            LOCAL_DIM,
        )
    )


    runtime_class_ids = np.fromfile(
        TWOHAND_CLASS_IDS_PATH,
        dtype=np.int32,
    )

    if runtime_class_ids.shape != (
        REFERENCE_COUNT,
    ):
        raise RuntimeError(
            "twohand_class_ids.bin shape mismatch"
        )


    # ========================================================
    # 3. Current Handshape40 references
    # ========================================================

    runtime_handshape40 = np.stack(
        [
            frozen_07g
            .build_twohand_handshape40(
                sample
            )
            for sample in runtime_local
        ],
        axis=0,
    ).astype(
        np.float32
    )


    aihub = {
        "local":
            runtime_local,

        "handshape40":
            runtime_handshape40,

        "class_ids":
            runtime_class_ids,
    }


    # ========================================================
    # 4. Load 06v source
    # ========================================================

    source = np.load(
        SOURCE_NPZ_PATH,
        allow_pickle=False,
    )

    features = np.asarray(
        source[
            "features"
        ],
        dtype=np.float32,
    )

    if features.shape != (
        8,
        TARGET_FRAMES,
        FULL_DIM,
    ):
        raise RuntimeError(
            "06v features shape mismatch"
        )


    source_locals = features[
        :,
        :,
        0:LOCAL_DIM,
    ].copy()


    # ========================================================
    # 5. Positive query
    #
    # TEST-ONLY deterministic interpolation
    # ========================================================

    source_local = source_locals[
        POSITIVE_SOURCE_INDEX
    ]

    target_local = runtime_local[
        POSITIVE_TARGET_REFERENCE_INDEX
    ]

    one_minus_alpha = np.float32(
        1.0
        -
        POSITIVE_ALPHA
    )

    positive_local = (
        source_local
        *
        one_minus_alpha
        +
        target_local
        *
        POSITIVE_ALPHA
    ).astype(
        np.float32
    )


    positive_result = (
        frozen_07g
        .classify_two_hand(
            positive_local,
            aihub,
        )
    )


    # ========================================================
    # 6. Strict positive assertions
    # ========================================================

    positive_hot = positive_result[
        "hot_info"
    ]

    if positive_hot is None:
        raise RuntimeError(
            "Positive fixture: HOT not evaluated"
        )

    if int(
        positive_result[
            "base_id"
        ]
    ) != 4:
        raise RuntimeError(
            "Positive fixture: "
            "expected base_id=4"
        )

    if not bool(
        positive_hot[
            "rescued"
        ]
    ):
        raise RuntimeError(
            "Positive fixture: "
            "expected rescued=True"
        )

    if int(
        positive_result[
            "final_id"
        ]
    ) != 3:
        raise RuntimeError(
            "Positive fixture: "
            "expected final_id=3"
        )

    if (
        positive_result[
            "stage"
        ]
        !=
        "TWOHAND_HOT_HANDSHAPE_RESCUE"
    ):
        raise RuntimeError(
            "Positive fixture: "
            "unexpected stage"
        )


    # ========================================================
    # 7. Negative query
    #
    # Real stored 06v sample.
    # ========================================================

    negative_local = source_locals[
        NEGATIVE_SOURCE_INDEX
    ].astype(
        np.float32,
        copy=True,
    )


    negative_result = (
        frozen_07g
        .classify_two_hand(
            negative_local,
            aihub,
        )
    )


    # ========================================================
    # 8. Strict negative assertions
    # ========================================================

    negative_hot = negative_result[
        "hot_info"
    ]

    if negative_hot is None:
        raise RuntimeError(
            "Negative fixture: HOT not evaluated"
        )

    if int(
        negative_result[
            "base_id"
        ]
    ) != 0:
        raise RuntimeError(
            "Negative fixture: "
            "expected base_id=0"
        )

    if bool(
        negative_hot[
            "rescued"
        ]
    ):
        raise RuntimeError(
            "Negative fixture: "
            "expected rescued=False"
        )

    if int(
        negative_result[
            "final_id"
        ]
    ) != 0:
        raise RuntimeError(
            "Negative fixture: "
            "expected final_id=0"
        )

    if (
        negative_result[
            "stage"
        ]
        !=
        "TWOHAND_BASE_LOCAL"
    ):
        raise RuntimeError(
            "Negative fixture: "
            "unexpected stage"
        )


    # ========================================================
    # 9. Pack expected values
    # ========================================================

    (
        positive_expected_float,
        positive_expected_int,
    ) = pack_expected(
        positive_result
    )

    (
        negative_expected_float,
        negative_expected_int,
    ) = pack_expected(
        negative_result
    )


    # ========================================================
    # 10. Write fixtures
    # ========================================================

    FIXTURE_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    positive_local.tofile(
        FIXTURE_DIR
        / "positive_input_local84_80x84.bin"
    )

    positive_expected_float.tofile(
        FIXTURE_DIR
        / "positive_expected_float5.bin"
    )

    positive_expected_int.tofile(
        FIXTURE_DIR
        / "positive_expected_int5.bin"
    )


    negative_local.tofile(
        FIXTURE_DIR
        / "negative_input_local84_80x84.bin"
    )

    negative_expected_float.tofile(
        FIXTURE_DIR
        / "negative_expected_float5.bin"
    )

    negative_expected_int.tofile(
        FIXTURE_DIR
        / "negative_expected_int5.bin"
    )


    # ========================================================
    # 11. Output
    # ========================================================

    print_case(
        "POSITIVE / TEST-ONLY",
        positive_result,
    )

    print_case(
        "NEGATIVE / REAL 06v",
        negative_result,
    )


    print(
        "positive alpha          :",
        f"{float(POSITIVE_ALPHA):.9f}",
    )

    print(
        "positive source index   :",
        POSITIVE_SOURCE_INDEX,
    )

    print(
        "positive target ref idx :",
        POSITIVE_TARGET_REFERENCE_INDEX,
    )

    print(
        "negative source index   :",
        NEGATIVE_SOURCE_INDEX,
    )

    print()

    print(
        "fixture directory:"
    )

    print(
        FIXTURE_DIR
    )

    print()

    print(
        "HOT RESCUE PYTHON FIXTURE GENERATION PASS"
    )


if __name__ == "__main__":
    main()