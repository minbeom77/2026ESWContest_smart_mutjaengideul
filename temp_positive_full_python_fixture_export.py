import importlib.util
import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent

FROZEN_PATH = (
    ROOT
    / "07g_webcam_15class_final_frozen.py"
)

RAW_DIR = (
    ROOT
    / "raw_test_data"
    / "NIA_SL_WORD2563_REAL01_F"
)

NEW5_PATH = (
    ROOT
    / "new5_reference_v3"
    / "new5_train_v3_80f.npz"
)

OUTPUT_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "temp_positive_full_real01"
)


TRIM_START = 21
TRIM_END = 107

EXPECTED_ORIGINAL_JSON_FRAMES = 115
EXPECTED_BOTH_FRAMES = 87

EXTRA_RIGHT_ONLY = 247
EXPECTED_TOTAL_FRAMES = 334

EXPECTED_CLASS_ID = 12
NPZ_INDEX = 12

TOLERANCE = 1.0e-5


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


def extract_person(
    data,
    file_name,
):
    if "people" not in data:
        raise RuntimeError(
            f"{file_name}: people 없음"
        )

    people = data["people"]

    if isinstance(
        people,
        dict,
    ):
        return people

    if isinstance(
        people,
        list,
    ):
        if not people:
            raise RuntimeError(
                f"{file_name}: people 비어 있음"
            )

        person = people[0]

        if not isinstance(
            person,
            dict,
        ):
            raise RuntimeError(
                f"{file_name}: "
                "people[0]이 dict가 아님"
            )

        return person

    raise RuntimeError(
        f"{file_name}: "
        f"지원하지 않는 people type="
        f"{type(people).__name__}"
    )


def parse_hand_2d(
    values,
    hand_name,
    file_name,
):
    values = np.asarray(
        values,
        dtype=np.float32,
    )

    if (
        values.shape
        !=
        (63,)
    ):
        raise RuntimeError(
            f"{file_name}: "
            f"{hand_name} size="
            f"{values.shape}, "
            "expected=(63,)"
        )

    values = values.reshape(
        21,
        3,
    )

    return np.ascontiguousarray(
        values[:, 0:2],
        dtype=np.float32,
    )


def load_real01_trimmed():
    json_files = sorted(
        RAW_DIR.glob(
            "*_keypoints.json"
        )
    )

    if (
        len(json_files)
        !=
        EXPECTED_ORIGINAL_JSON_FRAMES
    ):
        raise RuntimeError(
            f"JSON count={len(json_files)}, "
            f"expected="
            f"{EXPECTED_ORIGINAL_JSON_FRAMES}"
        )

    trimmed_files = json_files[
        TRIM_START:
        TRIM_END + 1
    ]

    if (
        len(trimmed_files)
        !=
        EXPECTED_BOTH_FRAMES
    ):
        raise RuntimeError(
            f"Trim count="
            f"{len(trimmed_files)}, "
            f"expected="
            f"{EXPECTED_BOTH_FRAMES}"
        )

    left_sequence = []
    right_sequence = []

    for path in trimmed_files:
        with path.open(
            "r",
            encoding="utf-8",
        ) as f:
            data = json.load(
                f
            )

        person = extract_person(
            data,
            path.name,
        )

        left = parse_hand_2d(
            person[
                "hand_left_keypoints_2d"
            ],
            "LEFT",
            path.name,
        )

        right = parse_hand_2d(
            person[
                "hand_right_keypoints_2d"
            ],
            "RIGHT",
            path.name,
        )

        left_sequence.append(
            left
        )

        right_sequence.append(
            right
        )

    left_sequence = np.ascontiguousarray(
        np.stack(
            left_sequence,
            axis=0,
        ),
        dtype=np.float32,
    )

    right_sequence = np.ascontiguousarray(
        np.stack(
            right_sequence,
            axis=0,
        ),
        dtype=np.float32,
    )

    return (
        left_sequence,
        right_sequence,
    )


def build_original_recording(
    left_sequence,
    right_sequence,
):
    recording_frames = []

    # ========================================================
    # REAL01 BOTH 87 frames
    # ========================================================

    for frame_index in range(
        EXPECTED_BOTH_FRAMES
    ):
        recording_frames.append(
            (
                left_sequence[
                    frame_index
                ].copy(),
                right_sequence[
                    frame_index
                ].copy(),
            )
        )

    # ========================================================
    # TEST-ONLY RIGHT_ONLY padding
    #
    # Frozen C4 candidate probe에서 고정:
    #
    # extra RIGHT_ONLY = 247
    # total            = 334
    # ========================================================

    for index in range(
        EXTRA_RIGHT_ONLY
    ):
        source_index = (
            index
            %
            EXPECTED_BOTH_FRAMES
        )

        recording_frames.append(
            (
                None,
                right_sequence[
                    source_index
                ].copy(),
            )
        )

    return recording_frames


def main():
    print(
        "=" * 90
    )

    print(
        "TEMP POSITIVE FULL PYTHON FIXTURE EXPORT"
    )

    print(
        "=" * 90
    )


    frozen = load_frozen_module()


    (
        left_sequence,
        right_sequence,
    ) = load_real01_trimmed()


    print()
    print(
        "RAW REAL01"
    )

    print(
        "LEFT shape        :",
        left_sequence.shape,
    )

    print(
        "RIGHT shape       :",
        right_sequence.shape,
    )


    recording_frames = (
        build_original_recording(
            left_sequence,
            right_sequence,
        )
    )


    total_frames = len(
        recording_frames
    )

    left_count = sum(
        left is not None

        for left, right
        in recording_frames
    )

    right_count = sum(
        right is not None

        for left, right
        in recording_frames
    )

    both_count = sum(
        (
            left is not None
            and
            right is not None
        )

        for left, right
        in recording_frames
    )

    both_ratio = (
        both_count
        /
        total_frames
    )


    if (
        total_frames
        !=
        EXPECTED_TOTAL_FRAMES
    ):
        raise RuntimeError(
            "Total frame count mismatch"
        )

    if (
        both_count
        !=
        EXPECTED_BOTH_FRAMES
    ):
        raise RuntimeError(
            "BOTH frame count mismatch"
        )


    print()
    print(
        "SYNTHETIC ORIGINAL RECORDING"
    )

    print(
        "total frames      :",
        total_frames,
    )

    print(
        "left count        :",
        left_count,
    )

    print(
        "right count       :",
        right_count,
    )

    print(
        "both count        :",
        both_count,
    )

    print(
        "both ratio        :",
        f"{both_ratio:.12f}",
    )

    print(
        "extra RIGHT_ONLY  :",
        EXTRA_RIGHT_ONLY,
    )


    # ========================================================
    # Stage 1
    #
    # Frozen original routing / Feature V3
    # ========================================================

    print()
    print(
        "[1] ORIGINAL FROZEN FEATURE"
    )


    original_feature_info = (
        frozen.u.build_webcam_feature(
            recording_frames
        )
    )


    (
        original_feature,
        original_usage_type,
    ) = (
        frozen.validate_webcam_feature(
            original_feature_info
        )
    )


    original_feature = (
        np.ascontiguousarray(
            original_feature,
            dtype=np.float32,
        )
    )


    if (
        original_usage_type
        !=
        "one_hand"
    ):
        raise RuntimeError(
            "Original routing is not one_hand: "
            f"{original_usage_type}"
        )


    original_both_ratio = float(
        original_feature_info.get(
            "both_ratio",
            0.0,
        )
    )


    if (
        not np.isclose(
            original_both_ratio,
            both_ratio,
            rtol=0.0,
            atol=1.0e-12,
        )
    ):
        raise RuntimeError(
            "feature_info both_ratio mismatch"
        )


    print()
    print(
        "Original usage    :",
        original_usage_type,
    )

    print(
        "Original feature  :",
        original_feature.shape,
    )


    # ========================================================
    # Stage 2
    #
    # Exact frozen C4
    # ========================================================

    print()
    print(
        "[2] FROZEN C4"
    )


    c4_model = (
        frozen.load_frozen_c4_gate()
    )


    c4_feature = np.ascontiguousarray(
        frozen.build_c4_feature(
            original_feature
        ),
        dtype=np.float32,
    )


    if (
        c4_feature.shape
        !=
        (230,)
    ):
        raise RuntimeError(
            f"C4 feature shape="
            f"{c4_feature.shape}"
        )


    c4_result = (
        frozen.classify_onehand_c4_gate(
            feature=original_feature,
            c4_model=c4_model,
        )
    )


    c4_prediction = int(
        c4_result[
            "prediction"
        ]
    )

    c4_d_sign = float(
        c4_result[
            "d_sign"
        ]
    )

    c4_d_nosign = float(
        c4_result[
            "d_nosign"
        ]
    )

    c4_margin = float(
        c4_result[
            "margin_nosign_minus_sign"
        ]
    )


    if (
        c4_prediction
        !=
        frozen.C4_NOSIGN_LABEL
    ):
        raise RuntimeError(
            "Expected frozen C4 NO-SIGN"
        )


    print(
        "prediction        : NO-SIGN"
    )

    print(
        "d_sign            :",
        f"{c4_d_sign:.12f}",
    )

    print(
        "d_nosign          :",
        f"{c4_d_nosign:.12f}",
    )

    print(
        "margin            :",
        f"{c4_margin:.12f}",
    )


    # ========================================================
    # Stage 3
    #
    # Exact frozen TEMP trigger
    # ========================================================

    both_frames_for_rescue = [
        (
            left,
            right,
        )

        for left, right
        in recording_frames

        if (
            left is not None
            and
            right is not None
        )
    ]


    min_both_frames = 15


    can_try_temp_rescue = (
        original_both_ratio
        >=
        0.20

        and

        len(
            both_frames_for_rescue
        )
        >=
        min_both_frames
    )


    if not can_try_temp_rescue:
        raise RuntimeError(
            "TEMP eligibility failed"
        )


    print()
    print(
        "[3] TEMP ELIGIBILITY"
    )

    print(
        "both ratio        :",
        f"{original_both_ratio:.12f}",
    )

    print(
        "both frames       :",
        len(
            both_frames_for_rescue
        ),
    )

    print(
        "eligible          :",
        can_try_temp_rescue,
    )


    # ========================================================
    # Stage 4
    #
    # Exact frozen BOTH recollection -> Feature V3
    # ========================================================

    print()
    print(
        "[4] TEMP RESCUE FEATURE"
    )


    rescue_feature_info = (
        frozen.u.build_webcam_feature(
            both_frames_for_rescue
        )
    )


    (
        rescue_feature,
        rescue_usage_type,
    ) = (
        frozen.validate_webcam_feature(
            rescue_feature_info
        )
    )


    rescue_feature = (
        np.ascontiguousarray(
            rescue_feature,
            dtype=np.float32,
        )
    )


    if (
        rescue_usage_type
        !=
        "two_hand"
    ):
        raise RuntimeError(
            "TEMP rescue usage is not two_hand"
        )


    if (
        rescue_feature.shape
        !=
        (80, 172)
    ):
        raise RuntimeError(
            "TEMP rescue feature shape mismatch"
        )


    rescue_local84 = (
        np.ascontiguousarray(
            rescue_feature[
                :,
                0:frozen.LOCAL_DIM,
            ],
            dtype=np.float32,
        )
    )


    print()
    print(
        "Rescue usage      :",
        rescue_usage_type,
    )

    print(
        "Rescue feature    :",
        rescue_feature.shape,
    )

    print(
        "Rescue Local84    :",
        rescue_local84.shape,
    )


    # ========================================================
    # Verify rescue feature against existing REAL01 NPZ.
    # ========================================================

    with np.load(
        NEW5_PATH,
        allow_pickle=True,
    ) as data:

        expected_npz_feature = (
            np.ascontiguousarray(
                data[
                    "features"
                ][
                    NPZ_INDEX
                ],
                dtype=np.float32,
            )
        )

        npz_class_id = int(
            data[
                "class_ids"
            ][
                NPZ_INDEX
            ]
        )

        npz_real_id = str(
            data[
                "real_ids"
            ][
                NPZ_INDEX
            ]
        )


    if (
        npz_class_id
        !=
        EXPECTED_CLASS_ID
    ):
        raise RuntimeError(
            "NPZ class mismatch"
        )

    if (
        npz_real_id
        !=
        "REAL01"
    ):
        raise RuntimeError(
            "NPZ REAL ID mismatch"
        )


    rescue_npz_diff = np.abs(
        rescue_feature
        -
        expected_npz_feature
    )


    rescue_npz_max_error = float(
        np.max(
            rescue_npz_diff
        )
    )

    rescue_npz_mean_error = float(
        np.mean(
            rescue_npz_diff
        )
    )


    if (
        rescue_npz_max_error
        >
        TOLERANCE
    ):
        raise RuntimeError(
            "Rescue feature != existing NPZ"
        )


    # ========================================================
    # Stage 5
    #
    # Frozen two-hand hierarchy
    # ========================================================

    print()
    print(
        "[5] TWO-HAND CLASSIFIER"
    )


    aihub = (
        frozen.load_aihub_train_references()
    )


    rescue_result = (
        frozen.classify_two_hand(
            local=rescue_local84,
            aihub=aihub,
        )
    )


    base_id = int(
        rescue_result[
            "base_id"
        ]
    )

    rescue_final_id = int(
        rescue_result[
            "final_id"
        ]
    )

    pre_temp_stage = str(
        rescue_result[
            "stage"
        ]
    )

    base_ranking = (
        rescue_result[
            "base_ranking"
        ]
    )


    if (
        rescue_final_id
        !=
        frozen.TEMP_ID
    ):
        raise RuntimeError(
            "TEMP classifier final_id != TEMP_ID"
        )


    ranking_class_ids = np.asarray(
        [
            int(item["class_id"])

            for item
            in base_ranking
        ],
        dtype=np.int32,
    )


    ranking_scores = np.asarray(
        [
            float(item["score"])

            for item
            in base_ranking
        ],
        dtype=np.float32,
    )


    if (
        ranking_scores.size
        <
        2
    ):
        raise RuntimeError(
            "Ranking size < 2"
        )


    base_margin = np.float32(
        ranking_scores[1]
        -
        ranking_scores[0]
    )


    # ========================================================
    # Stage 6
    #
    # Frozen TEMP success override
    #
    # 07g:
    #
    # rescue_result["stage"] =
    #     "TWOHAND_TEMP_OVERLAP_RESCUE"
    #
    # rescue_result["is_nosign"] = False
    # ========================================================

    final_stage = (
        "TWOHAND_TEMP_OVERLAP_RESCUE"
    )

    final_is_nosign = False

    rescued = True


    print()
    print(
        "base_id           :",
        base_id,
    )

    print(
        "final_id          :",
        rescue_final_id,
    )

    print(
        "pre-TEMP stage    :",
        pre_temp_stage,
    )

    print(
        "final stage       :",
        final_stage,
    )

    print(
        "rescued           :",
        rescued,
    )


    # ========================================================
    # Export fixture
    # ========================================================

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    # Real raw XY after verified JSON parser + stored trim.
    left_sequence.tofile(
        OUTPUT_DIR
        / "input_real01_left_87x21x2.bin"
    )

    right_sequence.tofile(
        OUTPUT_DIR
        / "input_real01_right_87x21x2.bin"
    )


    original_feature.tofile(
        OUTPUT_DIR
        / "expected_original_feature_80x172.bin"
    )

    c4_feature.tofile(
        OUTPUT_DIR
        / "expected_c4_feature_230.bin"
    )

    rescue_feature.tofile(
        OUTPUT_DIR
        / "expected_rescue_feature_80x172.bin"
    )

    rescue_local84.tofile(
        OUTPUT_DIR
        / "expected_rescue_local84_80x84.bin"
    )

    ranking_class_ids.tofile(
        OUTPUT_DIR
        / "expected_base_ranking_class_ids.bin"
    )

    ranking_scores.tofile(
        OUTPUT_DIR
        / "expected_base_ranking_scores.bin"
    )


    np.asarray(
        [
            total_frames,
            left_count,
            right_count,
            both_count,
            EXTRA_RIGHT_ONLY,
        ],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_recording_counts.bin"
    )


    np.asarray(
        [both_ratio],
        dtype=np.float64,
    ).tofile(
        OUTPUT_DIR
        / "expected_both_ratio.bin"
    )


    np.asarray(
        [
            c4_prediction,
        ],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_c4_prediction.bin"
    )


    np.asarray(
        [
            c4_d_sign,
            c4_d_nosign,
            c4_margin,
        ],
        dtype=np.float64,
    ).tofile(
        OUTPUT_DIR
        / "expected_c4_distances.bin"
    )


    np.asarray(
        [base_id],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_base_id.bin"
    )


    np.asarray(
        [rescue_final_id],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_final_id.bin"
    )


    np.asarray(
        [base_margin],
        dtype=np.float32,
    ).tofile(
        OUTPUT_DIR
        / "expected_base_margin.bin"
    )


    np.asarray(
        [1],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_rescued.bin"
    )


    np.asarray(
        [int(final_is_nosign)],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_final_is_nosign.bin"
    )


    (
        OUTPUT_DIR
        / "expected_original_usage.txt"
    ).write_text(
        original_usage_type,
        encoding="utf-8",
    )


    (
        OUTPUT_DIR
        / "expected_rescue_usage.txt"
    ).write_text(
        rescue_usage_type,
        encoding="utf-8",
    )


    (
        OUTPUT_DIR
        / "expected_pre_temp_stage.txt"
    ).write_text(
        pre_temp_stage,
        encoding="utf-8",
    )


    (
        OUTPUT_DIR
        / "expected_final_stage.txt"
    ).write_text(
        final_stage,
        encoding="utf-8",
    )


    (
        OUTPUT_DIR
        / "fixture_info.txt"
    ).write_text(
        "\n".join(
            [
                "fixture=TEST-ONLY synthetic TEMP positive",
                "real_source=NIA_SL_WORD2563_REAL01_F",
                "class_id=12",
                "word_code=2563",
                "real_id=REAL01",
                "json_frames=115",
                "trim_start=21",
                "trim_end=107",
                "trim_frames=87",
                "extra_right_only=247",
                "total_frames=334",
                f"both_ratio={both_ratio:.17g}",
                "original_usage=one_hand",
                "c4_prediction=NO-SIGN",
                "rescue_usage=two_hand",
                f"base_id={base_id}",
                f"final_id={rescue_final_id}",
                f"pre_temp_stage={pre_temp_stage}",
                f"final_stage={final_stage}",
                "rescued=True",
                (
                    "rescue_npz_max_error="
                    f"{rescue_npz_max_error:.17g}"
                ),
            ]
        ),
        encoding="utf-8",
    )


    # ========================================================
    # Final report
    # ========================================================

    print()
    print(
        "=" * 90
    )

    print(
        "TEMP POSITIVE FULL PYTHON EXPECTED"
    )

    print(
        "=" * 90
    )


    print(
        "original usage        :",
        original_usage_type,
    )

    print(
        "C4 prediction         : NO-SIGN"
    )

    print(
        "TEMP eligible         :",
        can_try_temp_rescue,
    )

    print(
        "rescue BOTH frames    :",
        len(
            both_frames_for_rescue
        ),
    )

    print(
        "rescue usage          :",
        rescue_usage_type,
    )

    print(
        "rescue NPZ max error  :",
        f"{rescue_npz_max_error:.12f}",
    )

    print(
        "rescue NPZ mean error :",
        f"{rescue_npz_mean_error:.12f}",
    )

    print(
        "base_id               :",
        base_id,
    )

    print(
        "final_id              :",
        rescue_final_id,
    )

    print(
        "pre-TEMP stage        :",
        pre_temp_stage,
    )

    print(
        "final stage           :",
        final_stage,
    )

    print(
        "rescued               :",
        rescued,
    )

    print()


    print(
        "BASE RANKING"
    )


    for rank_index, (
        class_id,
        score,
    ) in enumerate(
        zip(
            ranking_class_ids,
            ranking_scores,
        ),
        start=1,
    ):
        print(
            f"  {rank_index}. "
            f"class {int(class_id)} "
            f"| score {float(score):.9f}"
        )


    print()
    print(
        "Output:",
        OUTPUT_DIR,
    )

    print()
    print(
        "TEMP POSITIVE FULL PYTHON FIXTURE EXPORT PASS"
    )

    print(
        "=" * 90
    )


if __name__ == "__main__":
    main()