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

CANDIDATE_INDICES = [
    0,  # expected HOT rescue positive
    2,  # expected HOT rescue negative
]


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
# Main
# ============================================================

def main():
    print(
        "========================================"
    )
    print(
        "HOT FIXTURE CANDIDATE VERIFICATION"
    )
    print(
        "========================================"
    )
    print()


    # ========================================================
    # 1. Load old HOT trial source
    # ========================================================

    source = np.load(
        SOURCE_NPZ_PATH,
        allow_pickle=False,
    )

    features = np.asarray(
        source["features"],
        dtype=np.float32,
    )

    if features.shape != (
        8,
        TARGET_FRAMES,
        FULL_DIM,
    ):
        raise RuntimeError(
            "06v features shape mismatch: "
            f"{features.shape}"
        )


    # ========================================================
    # 2. Exact Local84 extraction
    #
    # frozen runtime:
    # local = feature[:, 0:LOCAL_DIM].copy()
    # ========================================================

    locals84 = features[
        :,
        :,
        0:LOCAL_DIM,
    ].copy()

    if locals84.shape != (
        8,
        TARGET_FRAMES,
        LOCAL_DIM,
    ):
        raise RuntimeError(
            "Local84 shape mismatch: "
            f"{locals84.shape}"
        )


    # ========================================================
    # 3. Current runtime references
    # ========================================================

    runtime_local_raw = np.fromfile(
        TWOHAND_LOCAL_PATH,
        dtype=np.float32,
    )

    expected_local_count = (
        REFERENCE_COUNT
        *
        TARGET_FRAMES
        *
        LOCAL_DIM
    )

    if (
        runtime_local_raw.size
        !=
        expected_local_count
    ):
        raise RuntimeError(
            "twohand_local.bin size mismatch"
        )

    runtime_local = runtime_local_raw.reshape(
        REFERENCE_COUNT,
        TARGET_FRAMES,
        LOCAL_DIM,
    )


    runtime_class_ids = np.fromfile(
        TWOHAND_CLASS_IDS_PATH,
        dtype=np.int32,
    )

    if runtime_class_ids.shape != (
        REFERENCE_COUNT,
    ):
        raise RuntimeError(
            "twohand_class_ids.bin shape mismatch: "
            f"{runtime_class_ids.shape}"
        )


    # ========================================================
    # 4. Frozen Python
    # ========================================================

    frozen_07g = load_frozen_07g()


    # ========================================================
    # 5. Current reference Handshape40
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

    if runtime_handshape40.shape != (
        REFERENCE_COUNT,
        TARGET_FRAMES,
        40,
    ):
        raise RuntimeError(
            "runtime Handshape40 shape mismatch: "
            f"{runtime_handshape40.shape}"
        )


    aihub = {
        "local": runtime_local,
        "handshape40": runtime_handshape40,
        "class_ids": runtime_class_ids,
    }


    # ========================================================
    # 6. Verify selected candidates
    # ========================================================

    for index in CANDIDATE_INDICES:
        print(
            "----------------------------------------"
        )

        print(
            f"index                  : {index}"
        )

        print(
            f"old true_id            : "
            f"{int(source['true_class_ids'][index])}"
        )

        print(
            f"old base_id            : "
            f"{int(source['base_class_ids'][index])}"
        )

        print(
            f"old hot_score          : "
            f"{float(source['hot_scores'][index]):.9f}"
        )

        print(
            f"old base_hs_score      : "
            f"{float(source['base_handshape_scores'][index]):.9f}"
        )

        print(
            f"old delta              : "
            f"{float(source['hot_deltas'][index]):+.9f}"
        )

        print()


        result = (
            frozen_07g
            .classify_two_hand(
                locals84[index],
                aihub,
            )
        )


        print(
            f"CURRENT base_id        : "
            f"{int(result['base_id'])}"
        )

        print(
            f"CURRENT base_margin    : "
            f"{float(result['base_margin']):+.9f}"
        )


        hot_info = result[
            "hot_info"
        ]

        if hot_info is None:
            print(
                "CURRENT hot evaluated  : False"
            )
        else:
            print(
                "CURRENT hot evaluated  : True"
            )

            print(
                f"CURRENT hot_score      : "
                f"{float(hot_info['hot_score']):.9f}"
            )

            print(
                f"CURRENT base_hs_score  : "
                f"{float(hot_info['base_hs_score']):.9f}"
            )

            print(
                f"CURRENT delta          : "
                f"{float(hot_info['delta']):+.9f}"
            )

            print(
                f"CURRENT threshold      : "
                f"{float(hot_info['threshold']):+.9f}"
            )

            print(
                f"CURRENT rescued        : "
                f"{bool(hot_info['rescued'])}"
            )


        print(
            f"CURRENT final_id       : "
            f"{int(result['final_id'])}"
        )

        print(
            f"CURRENT stage          : "
            f"{result['stage']}"
        )

        print()


    print(
        "========================================"
    )
    print(
        "HOT FIXTURE CANDIDATE VERIFICATION DONE"
    )
    print(
        "========================================"
    )


if __name__ == "__main__":
    main()