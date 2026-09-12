import contextlib
import importlib.util
import io
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent

FROZEN_PATH = (
    ROOT
    / "07g_webcam_15class_final_frozen.py"
)

OUTPUT_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "class_15_inference_frozen"
)


TARGET_FRAMES = 80
LOCAL_DIM = 84

ONEHAND_COUNT = 42
TWOHAND_COUNT = 60

ONEHAND_RANKING_COUNT = 6
TWOHAND_RANKING_COUNT = 9


EXPECTED_ONEHAND_IDS = {
    2,
    7,
    8,
    10,
    11,
    13,
}

EXPECTED_TWOHAND_IDS = {
    0,
    1,
    3,
    4,
    5,
    6,
    9,
    12,
    14,
}


def load_frozen_module():
    spec = importlib.util.spec_from_file_location(
        "frozen_07g",
        FROZEN_PATH,
    )

    if (
        spec is None
        or
        spec.loader is None
    ):
        raise RuntimeError(
            "07g frozen module load 실패"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(
        module
    )

    return module


def load_references_silent(
    frozen,
):
    buffer = io.StringIO()

    with contextlib.redirect_stdout(
        buffer
    ):
        onehand = (
            frozen.load_onehand_calibration()
        )

        aihub = (
            frozen.load_aihub_train_references()
        )

    return (
        onehand,
        aihub,
    )


def check_reference_shape(
    name,
    local,
    class_ids,
    expected_count,
):
    if (
        local.shape
        !=
        (
            expected_count,
            TARGET_FRAMES,
            LOCAL_DIM,
        )
    ):
        raise RuntimeError(
            f"{name} local shape="
            f"{local.shape}"
        )

    if (
        class_ids.shape
        !=
        (
            expected_count,
        )
    ):
        raise RuntimeError(
            f"{name} class_ids shape="
            f"{class_ids.shape}"
        )


def extract_base_ranking(
    result,
    expected_length,
    family,
    sample_index,
):
    if "base_ranking" not in result:
        raise RuntimeError(
            f"{family} sample "
            f"{sample_index}: "
            "base_ranking key 없음"
        )

    ranking = result[
        "base_ranking"
    ]

    if (
        len(ranking)
        !=
        expected_length
    ):
        raise RuntimeError(
            f"{family} sample "
            f"{sample_index}: "
            f"base_ranking length="
            f"{len(ranking)}, "
            f"expected="
            f"{expected_length}"
        )

    class_ids = []
    scores = []

    for item in ranking:
        class_ids.append(
            int(
                item[
                    "class_id"
                ]
            )
        )

        scores.append(
            float(
                item[
                    "score"
                ]
            )
        )

    return (
        class_ids,
        scores,
    )


def validate_class_set(
    name,
    class_ids,
    expected_ids,
):
    actual = set(
        int(x)
        for x
        in class_ids.tolist()
    )

    if (
        actual
        !=
        expected_ids
    ):
        raise RuntimeError(
            f"{name} class set="
            f"{sorted(actual)}, "
            f"expected="
            f"{sorted(expected_ids)}"
        )


def main():
    print(
        "=" * 90
    )

    print(
        "15-CLASS FROZEN PYTHON EXPECTED EXPORT"
    )

    print(
        "=" * 90
    )


    frozen = load_frozen_module()


    (
        onehand,
        aihub,
    ) = load_references_silent(
        frozen
    )


    # ========================================================
    # ONE-HAND
    # ========================================================

    onehand_local = np.ascontiguousarray(
        onehand[
            "local"
        ],
        dtype=np.float32,
    )

    onehand_reference_ids = np.asarray(
        onehand[
            "class_ids"
        ],
        dtype=np.int32,
    )


    check_reference_shape(
        "ONE-HAND",
        onehand_local,
        onehand_reference_ids,
        ONEHAND_COUNT,
    )

    validate_class_set(
        "ONE-HAND",
        onehand_reference_ids,
        EXPECTED_ONEHAND_IDS,
    )


    # ========================================================
    # TWO-HAND
    #
    # AIHub loader contains all train classes.
    # Frozen classify_two_hand() uses TWO_HAND_IDS only.
    #
    # Extract those exact 60 references while preserving their
    # original frozen array order.
    # ========================================================

    aihub_local = np.asarray(
        aihub[
            "local"
        ],
        dtype=np.float32,
    )

    aihub_class_ids = np.asarray(
        aihub[
            "class_ids"
        ],
        dtype=np.int64,
    )


    twohand_mask = np.isin(
        aihub_class_ids,
        np.asarray(
            sorted(
                EXPECTED_TWOHAND_IDS
            ),
            dtype=np.int64,
        ),
    )


    twohand_local = np.ascontiguousarray(
        aihub_local[
            twohand_mask
        ],
        dtype=np.float32,
    )

    twohand_reference_ids = np.asarray(
        aihub_class_ids[
            twohand_mask
        ],
        dtype=np.int32,
    )


    check_reference_shape(
        "TWO-HAND",
        twohand_local,
        twohand_reference_ids,
        TWOHAND_COUNT,
    )

    validate_class_set(
        "TWO-HAND",
        twohand_reference_ids,
        EXPECTED_TWOHAND_IDS,
    )


    # ========================================================
    # Frozen inference
    # ========================================================

    onehand_final_ids = []
    onehand_base_ids = []
    onehand_base_margins = []
    onehand_stages = []

    onehand_ranking_ids = []
    onehand_ranking_scores = []


    twohand_final_ids = []
    twohand_base_ids = []
    twohand_base_margins = []
    twohand_stages = []

    twohand_ranking_ids = []
    twohand_ranking_scores = []


    mismatch_records = []


    # ========================================================
    # 42 ONE-HAND references
    # ========================================================

    for sample_index in range(
        ONEHAND_COUNT
    ):
        local = onehand_local[
            sample_index
        ]


        result = (
            frozen.classify_one_hand(
                local=local,
                onehand_calibration=onehand,
            )
        )


        required_keys = {
            "final_id",
            "base_id",
            "base_margin",
            "stage",
            "base_ranking",
        }


        missing = (
            required_keys
            -
            set(
                result.keys()
            )
        )


        if missing:
            raise RuntimeError(
                "ONE-HAND result key 부족: "
                f"{missing}"
            )


        expected_class_id = int(
            onehand_reference_ids[
                sample_index
            ]
        )

        final_id = int(
            result[
                "final_id"
            ]
        )

        base_id = int(
            result[
                "base_id"
            ]
        )

        base_margin = float(
            result[
                "base_margin"
            ]
        )

        stage = str(
            result[
                "stage"
            ]
        )


        (
            ranking_ids,
            ranking_scores,
        ) = extract_base_ranking(
            result,
            ONEHAND_RANKING_COUNT,
            "ONE-HAND",
            sample_index,
        )


        onehand_final_ids.append(
            final_id
        )

        onehand_base_ids.append(
            base_id
        )

        onehand_base_margins.append(
            base_margin
        )

        onehand_stages.append(
            stage
        )

        onehand_ranking_ids.append(
            ranking_ids
        )

        onehand_ranking_scores.append(
            ranking_scores
        )


        if (
            final_id
            !=
            expected_class_id
        ):
            mismatch_records.append(
                (
                    "ONE-HAND",
                    sample_index,
                    expected_class_id,
                    final_id,
                    base_id,
                    stage,
                )
            )


    # ========================================================
    # 60 TWO-HAND references
    #
    # IMPORTANT:
    # classify_two_hand() must receive the complete AIHub dict,
    # exactly as frozen 07g does. The individual query comes
    # from the exact filtered two-hand reference sequence.
    # ========================================================

    for sample_index in range(
        TWOHAND_COUNT
    ):
        local = twohand_local[
            sample_index
        ]


        result = (
            frozen.classify_two_hand(
                local=local,
                aihub=aihub,
            )
        )


        required_keys = {
            "final_id",
            "base_id",
            "base_margin",
            "stage",
            "base_ranking",
        }


        missing = (
            required_keys
            -
            set(
                result.keys()
            )
        )


        if missing:
            raise RuntimeError(
                "TWO-HAND result key 부족: "
                f"{missing}"
            )


        expected_class_id = int(
            twohand_reference_ids[
                sample_index
            ]
        )

        final_id = int(
            result[
                "final_id"
            ]
        )

        base_id = int(
            result[
                "base_id"
            ]
        )

        base_margin = float(
            result[
                "base_margin"
            ]
        )

        stage = str(
            result[
                "stage"
            ]
        )


        (
            ranking_ids,
            ranking_scores,
        ) = extract_base_ranking(
            result,
            TWOHAND_RANKING_COUNT,
            "TWO-HAND",
            sample_index,
        )


        twohand_final_ids.append(
            final_id
        )

        twohand_base_ids.append(
            base_id
        )

        twohand_base_margins.append(
            base_margin
        )

        twohand_stages.append(
            stage
        )

        twohand_ranking_ids.append(
            ranking_ids
        )

        twohand_ranking_scores.append(
            ranking_scores
        )


        if (
            final_id
            !=
            expected_class_id
        ):
            mismatch_records.append(
                (
                    "TWO-HAND",
                    sample_index,
                    expected_class_id,
                    final_id,
                    base_id,
                    stage,
                )
            )


    # ========================================================
    # Convert
    # ========================================================

    onehand_final_ids = np.asarray(
        onehand_final_ids,
        dtype=np.int32,
    )

    onehand_base_ids = np.asarray(
        onehand_base_ids,
        dtype=np.int32,
    )

    onehand_base_margins = np.asarray(
        onehand_base_margins,
        dtype=np.float64,
    )

    onehand_ranking_ids = np.asarray(
        onehand_ranking_ids,
        dtype=np.int32,
    )

    onehand_ranking_scores = np.asarray(
        onehand_ranking_scores,
        dtype=np.float32,
    )


    twohand_final_ids = np.asarray(
        twohand_final_ids,
        dtype=np.int32,
    )

    twohand_base_ids = np.asarray(
        twohand_base_ids,
        dtype=np.int32,
    )

    twohand_base_margins = np.asarray(
        twohand_base_margins,
        dtype=np.float64,
    )

    twohand_ranking_ids = np.asarray(
        twohand_ranking_ids,
        dtype=np.int32,
    )

    twohand_ranking_scores = np.asarray(
        twohand_ranking_scores,
        dtype=np.float32,
    )


    if (
        onehand_ranking_ids.shape
        !=
        (
            ONEHAND_COUNT,
            ONEHAND_RANKING_COUNT,
        )
    ):
        raise RuntimeError(
            "ONE-HAND ranking ID shape 오류"
        )


    if (
        onehand_ranking_scores.shape
        !=
        (
            ONEHAND_COUNT,
            ONEHAND_RANKING_COUNT,
        )
    ):
        raise RuntimeError(
            "ONE-HAND ranking score shape 오류"
        )


    if (
        twohand_ranking_ids.shape
        !=
        (
            TWOHAND_COUNT,
            TWOHAND_RANKING_COUNT,
        )
    ):
        raise RuntimeError(
            "TWO-HAND ranking ID shape 오류"
        )


    if (
        twohand_ranking_scores.shape
        !=
        (
            TWOHAND_COUNT,
            TWOHAND_RANKING_COUNT,
        )
    ):
        raise RuntimeError(
            "TWO-HAND ranking score shape 오류"
        )


    # ========================================================
    # Summary before export
    # ========================================================

    onehand_correct = int(
        np.sum(
            onehand_final_ids
            ==
            onehand_reference_ids
        )
    )

    twohand_correct = int(
        np.sum(
            twohand_final_ids
            ==
            twohand_reference_ids
        )
    )

    total_correct = (
        onehand_correct
        +
        twohand_correct
    )


    emitted_ids = set(
        onehand_final_ids.tolist()
        +
        twohand_final_ids.tolist()
    )


    expected_all_ids = set(
        range(
            15
        )
    )


    print()
    print(
        "REFERENCE SHAPES"
    )

    print(
        "ONE-HAND Local84 :",
        onehand_local.shape,
    )

    print(
        "TWO-HAND Local84 :",
        twohand_local.shape,
    )


    print()
    print(
        "FROZEN INFERENCE SUMMARY"
    )

    print(
        "ONE-HAND correct :",
        f"{onehand_correct} / {ONEHAND_COUNT}",
    )

    print(
        "TWO-HAND correct :",
        f"{twohand_correct} / {TWOHAND_COUNT}",
    )

    print(
        "TOTAL correct    :",
        f"{total_correct} / "
        f"{ONEHAND_COUNT + TWOHAND_COUNT}",
    )

    print(
        "Emitted IDs      :",
        sorted(
            emitted_ids
        ),
    )


    print()
    print(
        "MISMATCHES"
    )


    if mismatch_records:
        for (
            family,
            sample_index,
            expected_class_id,
            final_id,
            base_id,
            stage,
        ) in mismatch_records:

            print(
                f"{family} "
                f"sample={sample_index} "
                f"expected={expected_class_id} "
                f"final={final_id} "
                f"base={base_id} "
                f"stage={stage}"
            )
    else:
        print(
            "NONE"
        )


    if (
        emitted_ids
        !=
        expected_all_ids
    ):
        raise RuntimeError(
            "Frozen classifier가 "
            "0~14 전체 ID를 emit하지 않음"
        )


    # ========================================================
    # Export
    # ========================================================

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    onehand_local.tofile(
        OUTPUT_DIR
        / "input_onehand_local_42x80x84.bin"
    )

    twohand_local.tofile(
        OUTPUT_DIR
        / "input_twohand_local_60x80x84.bin"
    )


    onehand_reference_ids.tofile(
        OUTPUT_DIR
        / "expected_onehand_reference_ids.bin"
    )

    twohand_reference_ids.tofile(
        OUTPUT_DIR
        / "expected_twohand_reference_ids.bin"
    )


    onehand_final_ids.tofile(
        OUTPUT_DIR
        / "expected_onehand_final_ids.bin"
    )

    twohand_final_ids.tofile(
        OUTPUT_DIR
        / "expected_twohand_final_ids.bin"
    )


    onehand_base_ids.tofile(
        OUTPUT_DIR
        / "expected_onehand_base_ids.bin"
    )

    twohand_base_ids.tofile(
        OUTPUT_DIR
        / "expected_twohand_base_ids.bin"
    )


    onehand_base_margins.tofile(
        OUTPUT_DIR
        / "expected_onehand_base_margins.bin"
    )

    twohand_base_margins.tofile(
        OUTPUT_DIR
        / "expected_twohand_base_margins.bin"
    )


    onehand_ranking_ids.tofile(
        OUTPUT_DIR
        / "expected_onehand_base_ranking_ids_42x6.bin"
    )

    onehand_ranking_scores.tofile(
        OUTPUT_DIR
        / "expected_onehand_base_ranking_scores_42x6.bin"
    )


    twohand_ranking_ids.tofile(
        OUTPUT_DIR
        / "expected_twohand_base_ranking_ids_60x9.bin"
    )

    twohand_ranking_scores.tofile(
        OUTPUT_DIR
        / "expected_twohand_base_ranking_scores_60x9.bin"
    )


    (
        OUTPUT_DIR
        / "expected_onehand_stages.txt"
    ).write_text(
        "\n".join(
            onehand_stages
        ),
        encoding="utf-8",
    )


    (
        OUTPUT_DIR
        / "expected_twohand_stages.txt"
    ).write_text(
        "\n".join(
            twohand_stages
        ),
        encoding="utf-8",
    )


    (
        OUTPUT_DIR
        / "fixture_info.txt"
    ).write_text(
        "\n".join(
            [
                (
                    "source="
                    "07g_webcam_15class_final_frozen.py"
                ),
                "onehand_count=42",
                "twohand_count=60",
                "total_count=102",
                (
                    "onehand_ranking_count="
                    f"{ONEHAND_RANKING_COUNT}"
                ),
                (
                    "twohand_ranking_count="
                    f"{TWOHAND_RANKING_COUNT}"
                ),
                (
                    "onehand_correct="
                    f"{onehand_correct}"
                ),
                (
                    "twohand_correct="
                    f"{twohand_correct}"
                ),
                (
                    "total_correct="
                    f"{total_correct}"
                ),
                (
                    "mismatch_count="
                    f"{len(mismatch_records)}"
                ),
                (
                    "emitted_ids="
                    + ",".join(
                        str(x)
                        for x
                        in sorted(
                            emitted_ids
                        )
                    )
                ),
            ]
        ),
        encoding="utf-8",
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
        "15-CLASS FROZEN PYTHON EXPECTED EXPORT PASS"
    )

    print(
        "=" * 90
    )


if __name__ == "__main__":
    main()