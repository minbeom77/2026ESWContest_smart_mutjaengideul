from pathlib import Path
import importlib.util

import numpy as np


# ============================================================
# Constants
# ============================================================

REFERENCE_COUNT = 60
TARGET_FRAMES = 80
LOCAL_DIM = 84
HANDSHAPE_DIM = 40

SAMPLE_INDEX = 0


# ============================================================
# Paths
# ============================================================

REPO_ROOT = Path(__file__).resolve().parents[3]

FROZEN_07G_PATH = (
    REPO_ROOT
    / "07g_webcam_15class_final_frozen.py"
)

TWOHAND_LOCAL_PATH = (
    REPO_ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "runtime_data"
    / "twohand_local.bin"
)

FIXTURE_DIR = (
    REPO_ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "handshape40"
)

INPUT_PATH = (
    FIXTURE_DIR
    / "input_local84_80x84.bin"
)

EXPECTED_PATH = (
    FIXTURE_DIR
    / "expected_handshape40_80x40.bin"
)


# ============================================================
# Frozen 07g loader
# ============================================================

def load_frozen_07g():
    if not FROZEN_07G_PATH.is_file():
        raise RuntimeError(
            f"07g frozen file not found: "
            f"{FROZEN_07G_PATH}"
        )

    spec = importlib.util.spec_from_file_location(
        "frozen_07g",
        FROZEN_07G_PATH,
    )

    if (
        spec is None
        or spec.loader is None
    ):
        raise RuntimeError(
            "Failed to create import spec for frozen 07g"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(
        module
    )

    if not hasattr(
        module,
        "build_twohand_handshape40",
    ):
        raise RuntimeError(
            "Frozen 07g does not contain "
            "build_twohand_handshape40()"
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
        "HANDSHAPE40 PYTHON FIXTURE GENERATOR"
    )

    print(
        "========================================"
    )

    print()

    print(
        "07g frozen:"
    )

    print(
        FROZEN_07G_PATH
    )

    print()

    print(
        "twohand local:"
    )

    print(
        TWOHAND_LOCAL_PATH
    )

    print()

    if not TWOHAND_LOCAL_PATH.is_file():
        raise RuntimeError(
            f"twohand_local.bin not found: "
            f"{TWOHAND_LOCAL_PATH}"
        )


    # ========================================================
    # 1. Read runtime two-hand Local84
    #
    # float32 [60, 80, 84]
    # ========================================================

    raw = np.fromfile(
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

    if raw.size != expected_count:
        raise RuntimeError(
            "twohand_local.bin size mismatch: "
            f"actual={raw.size}, "
            f"expected={expected_count}"
        )

    references = raw.reshape(
        REFERENCE_COUNT,
        TARGET_FRAMES,
        LOCAL_DIM,
    )


    # ========================================================
    # 2. Select one exact runtime reference
    # ========================================================

    local84 = np.asarray(
        references[
            SAMPLE_INDEX
        ],
        dtype=np.float32,
    ).copy()

    if local84.shape != (
        TARGET_FRAMES,
        LOCAL_DIM,
    ):
        raise RuntimeError(
            "Local84 sample shape mismatch: "
            f"{local84.shape}"
        )


    # ========================================================
    # 3. Load frozen Python baseline
    # ========================================================

    frozen_07g = load_frozen_07g()


    # ========================================================
    # 4. Python frozen Handshape40
    # ========================================================

    handshape40 = (
        frozen_07g
        .build_twohand_handshape40(
            local84
        )
    )

    handshape40 = np.asarray(
        handshape40,
        dtype=np.float32,
    )

    if handshape40.shape != (
        TARGET_FRAMES,
        HANDSHAPE_DIM,
    ):
        raise RuntimeError(
            "Handshape40 shape mismatch: "
            f"{handshape40.shape}"
        )


    # ========================================================
    # 5. Save regression fixture
    # ========================================================

    FIXTURE_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    local84.tofile(
        INPUT_PATH
    )

    handshape40.tofile(
        EXPECTED_PATH
    )


    # ========================================================
    # Output
    # ========================================================

    print(
        f"sample index             : "
        f"{SAMPLE_INDEX}"
    )

    print(
        f"input shape              : "
        f"{local84.shape}"
    )

    print(
        f"expected shape           : "
        f"{handshape40.shape}"
    )

    print(
        f"input dtype              : "
        f"{local84.dtype}"
    )

    print(
        f"expected dtype           : "
        f"{handshape40.dtype}"
    )

    print()

    print(
        "input fixture:"
    )

    print(
        INPUT_PATH
    )

    print()

    print(
        "expected fixture:"
    )

    print(
        EXPECTED_PATH
    )

    print()

    print(
        "HANDSHAPE40 PYTHON FIXTURE GENERATION PASS"
    )


if __name__ == "__main__":
    main()