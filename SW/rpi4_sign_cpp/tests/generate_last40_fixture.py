from pathlib import Path
import importlib.util

import numpy as np


# ============================================================
# Constants
# ============================================================

REFERENCE_COUNT = 60
TARGET_FRAMES = 80
LOCAL_DIM = 84

LAST40_START = 40
LAST40_END = 80

FIRST40_REFERENCE_INDEX = 21
LAST40_REFERENCE_INDEX = 4

EXPECTED_BASE_ID = 4
EXPECTED_FINAL_ID = 0

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
    / "aircon_cold_last40"
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
# Main
# ============================================================

def main():

    print(
        "========================================"
    )

    print(
        "AIRCON / COLD LAST40 FIXTURE GENERATOR"
    )

    print(
        "========================================"
    )

    print()

    print(
        "IMPORTANT:"
    )

    print(
        "This fixture is a TEST-ONLY temporal splice."
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
    # 3. Verify selected references
    # ========================================================

    first_class_id = int(
        runtime_class_ids[
            FIRST40_REFERENCE_INDEX
        ]
    )

    last_class_id = int(
        runtime_class_ids[
            LAST40_REFERENCE_INDEX
        ]
    )


    if first_class_id != 4:
        raise RuntimeError(
            "FIRST40 reference must be COLD class 4"
        )

    if last_class_id != 0:
        raise RuntimeError(
            "LAST40 reference must be AIRCON class 0"
        )


    # ========================================================
    # 4. Handshape40 references
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
    # 5. Build TEST-ONLY query
    #
    # first40 = COLD reference 21
    # last40  = AIRCON reference 4
    # ========================================================

    query = np.empty(
        (
            TARGET_FRAMES,
            LOCAL_DIM,
        ),
        dtype=np.float32,
    )


    query[
        0:LAST40_START,
        :
    ] = runtime_local[
        FIRST40_REFERENCE_INDEX,
        0:LAST40_START,
        :
    ]


    query[
        LAST40_START:LAST40_END,
        :
    ] = runtime_local[
        LAST40_REFERENCE_INDEX,
        LAST40_START:LAST40_END,
        :
    ]


    # ========================================================
    # 6. Frozen classification
    # ========================================================

    result = (
        frozen_07g
        .classify_two_hand(
            query,
            aihub,
        )
    )


    hot_info = result[
        "hot_info"
    ]

    ac_info = result[
        "ac_cold_info"
    ]


    # ========================================================
    # 7. Strict assertions
    # ========================================================

    if int(
        result[
            "base_id"
        ]
    ) != EXPECTED_BASE_ID:

        raise RuntimeError(
            "Expected base_id=4"
        )


    if hot_info is None:

        raise RuntimeError(
            "Expected HOT evaluation"
        )


    if bool(
        hot_info[
            "rescued"
        ]
    ):

        raise RuntimeError(
            "HOT must NOT rescue LAST40 fixture"
        )


    if ac_info is None:

        raise RuntimeError(
            "Expected AIRCON/COLD LAST40"
        )


    if (
        result[
            "stage"
        ]
        !=
        "TWOHAND_AIRCON_COLD_LAST40"
    ):

        raise RuntimeError(
            "Unexpected stage"
        )


    if int(
        result[
            "final_id"
        ]
    ) != EXPECTED_FINAL_ID:

        raise RuntimeError(
            "Expected final_id=0"
        )


    ranking = ac_info[
        "ranking"
    ]


    if len(
        ranking
    ) != 2:

        raise RuntimeError(
            "LAST40 ranking size must be 2"
        )


    if int(
        ranking[
            0
        ][
            "class_id"
        ]
    ) != 0:

        raise RuntimeError(
            "LAST40 top1 must be AIRCON class 0"
        )


    if int(
        ranking[
            1
        ][
            "class_id"
        ]
    ) != 4:

        raise RuntimeError(
            "LAST40 top2 must be COLD class 4"
        )


    # ========================================================
    # 8. Expected float fixture
    #
    # float32 [8]
    #
    # 0 base_margin
    # 1 hot_score
    # 2 base_hs_score
    # 3 hot_delta
    # 4 hot_threshold
    # 5 last40_margin
    # 6 last40_top1_score
    # 7 last40_top2_score
    # ========================================================

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

            ac_info[
                "margin"
            ],

            ranking[
                0
            ][
                "score"
            ],

            ranking[
                1
            ][
                "score"
            ],
        ],
        dtype=np.float32,
    )


    # ========================================================
    # 9. Expected int fixture
    #
    # int32 [9]
    #
    # 0 base_id
    # 1 hot_evaluated
    # 2 hot_rescued
    # 3 ac_applied
    # 4 last40_top1_id
    # 5 last40_top2_id
    # 6 final_id
    # 7 stage_code
    # 8 base_changed_by_last40
    # ========================================================

    expected_int = np.asarray(
        [
            int(
                result[
                    "base_id"
                ]
            ),

            1,

            int(
                bool(
                    hot_info[
                        "rescued"
                    ]
                )
            ),

            1,

            int(
                ranking[
                    0
                ][
                    "class_id"
                ]
            ),

            int(
                ranking[
                    1
                ][
                    "class_id"
                ]
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

            int(
                int(
                    result[
                        "base_id"
                    ]
                )
                !=
                int(
                    result[
                        "final_id"
                    ]
                )
            ),
        ],
        dtype=np.int32,
    )


    # ========================================================
    # 10. Write
    # ========================================================

    FIXTURE_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    query.tofile(
        FIXTURE_DIR
        / "input_local84_80x84.bin"
    )


    expected_float.tofile(
        FIXTURE_DIR
        / "expected_float8.bin"
    )


    expected_int.tofile(
        FIXTURE_DIR
        / "expected_int9.bin"
    )


    # ========================================================
    # 11. Output
    # ========================================================

    print(
        "first40 ref index :",
        FIRST40_REFERENCE_INDEX,
    )

    print(
        "first40 class     :",
        first_class_id,
    )

    print(
        "last40 ref index  :",
        LAST40_REFERENCE_INDEX,
    )

    print(
        "last40 class      :",
        last_class_id,
    )

    print()


    print(
        "base_id           :",
        int(
            result[
                "base_id"
            ]
        ),
    )

    print(
        "base_margin       :",
        f"{float(result['base_margin']):+.9f}",
    )

    print()


    print(
        "HOT evaluated     : True"
    )

    print(
        "HOT score         :",
        f"{float(hot_info['hot_score']):.9f}",
    )

    print(
        "base HS score     :",
        f"{float(hot_info['base_hs_score']):.9f}",
    )

    print(
        "HOT delta         :",
        f"{float(hot_info['delta']):+.9f}",
    )

    print(
        "HOT threshold     :",
        f"{float(hot_info['threshold']):+.9f}",
    )

    print(
        "HOT rescued       :",
        bool(
            hot_info[
                "rescued"
            ]
        ),
    )

    print()


    print(
        "LAST40 margin     :",
        f"{float(ac_info['margin']):+.9f}",
    )

    print(
        "LAST40 top1       :",
        int(
            ranking[
                0
            ][
                "class_id"
            ]
        ),
        f"{float(ranking[0]['score']):.9f}",
    )

    print(
        "LAST40 top2       :",
        int(
            ranking[
                1
            ][
                "class_id"
            ]
        ),
        f"{float(ranking[1]['score']):.9f}",
    )

    print()


    print(
        "final_id          :",
        int(
            result[
                "final_id"
            ]
        ),
    )

    print(
        "stage             :",
        result[
            "stage"
        ],
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
        "AIRCON / COLD LAST40 "
        "PYTHON FIXTURE GENERATION PASS"
    )


if __name__ == "__main__":
    main()