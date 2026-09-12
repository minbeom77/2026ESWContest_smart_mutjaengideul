import importlib.util
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parent

FROZEN_PATH = (
    ROOT
    / "07g_webcam_15class_final_frozen.py"
)

RAW_FIXTURE_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "feature_v3_twohand"
)

OUTPUT_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "temp_negative_synthetic"
)


RAW_FRAME_COUNT = 80
BOTH_COUNT = 20
TOTAL_FRAMES = 100

EXPECTED_BOTH_RATIO = 0.20


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
            "07g frozen module load spec 생성 실패"
        )

    module = importlib.util.module_from_spec(
        spec
    )

    spec.loader.exec_module(
        module
    )

    return module


def load_landmarks(path):
    raw = np.fromfile(
        path,
        dtype=np.float32,
    )

    expected_count = (
        RAW_FRAME_COUNT
        * 21
        * 2
    )

    if raw.size != expected_count:
        raise RuntimeError(
            f"{path.name}: "
            f"size={raw.size}, "
            f"expected={expected_count}"
        )

    return np.ascontiguousarray(
        raw.reshape(
            RAW_FRAME_COUNT,
            21,
            2,
        ),
        dtype=np.float32,
    )


def main():
    print(
        "=" * 80
    )

    print(
        "TEMP NEGATIVE PYTHON FIXTURE EXPORT"
    )

    print(
        "=" * 80
    )

    print()
    print(
        "TEST-ONLY synthetic recording"
    )

    print(
        "20 BOTH + 80 RIGHT_ONLY"
    )

    print(
        "both_ratio = 0.20"
    )

    print()


    frozen = load_frozen_module()


    left = load_landmarks(
        RAW_FIXTURE_DIR
        / "input_left_landmarks_80x21x2.bin"
    )

    right = load_landmarks(
        RAW_FIXTURE_DIR
        / "input_right_landmarks_80x21x2.bin"
    )


    # ========================================================
    # Synthetic original recording
    #
    # 0..19:
    #     BOTH
    #
    # 20..99:
    #     RIGHT_ONLY
    #
    # Therefore:
    #
    # total       = 100
    # left_count  = 20
    # right_count = 100
    # both_count  = 20
    # both_ratio  = 0.20
    #
    # Normal build_webcam_feature routing:
    #
    # 0.20 < BOTH_FRAME_RATIO_THRESHOLD(0.35)
    # -> one-hand branch
    #
    # right_count >= left_count
    # -> RIGHT_ONLY
    # ========================================================

    recording_frames = []


    for frame_index in range(
        TOTAL_FRAMES
    ):
        if frame_index < BOTH_COUNT:
            recording_frames.append(
                (
                    left[frame_index].copy(),
                    right[frame_index].copy(),
                )
            )

        else:
            source_index = (
                frame_index
                %
                RAW_FRAME_COUNT
            )

            recording_frames.append(
                (
                    None,
                    right[source_index].copy(),
                )
            )


    total_frames = len(
        recording_frames
    )

    left_count = sum(
        left_frame is not None

        for left_frame, right_frame
        in recording_frames
    )

    right_count = sum(
        right_frame is not None

        for left_frame, right_frame
        in recording_frames
    )

    both_count = sum(
        (
            left_frame is not None
            and
            right_frame is not None
        )

        for left_frame, right_frame
        in recording_frames
    )

    both_ratio = (
        both_count
        /
        total_frames
    )


    if total_frames != TOTAL_FRAMES:
        raise RuntimeError(
            "total_frames mismatch"
        )

    if left_count != BOTH_COUNT:
        raise RuntimeError(
            "left_count mismatch"
        )

    if right_count != TOTAL_FRAMES:
        raise RuntimeError(
            "right_count mismatch"
        )

    if both_count != BOTH_COUNT:
        raise RuntimeError(
            "both_count mismatch"
        )

    if not np.isclose(
        both_ratio,
        EXPECTED_BOTH_RATIO,
        rtol=0.0,
        atol=1e-12,
    ):
        raise RuntimeError(
            "both_ratio mismatch"
        )


    # ========================================================
    # Frozen Python original routing check
    #
    # This must be one-hand.
    # ========================================================

    original_feature_info = (
        frozen.u.build_webcam_feature(
            recording_frames
        )
    )

    (
        original_feature,
        original_usage_type,
    ) = frozen.validate_webcam_feature(
        original_feature_info
    )


    if (
        original_usage_type
        !=
        "one_hand"
    ):
        raise RuntimeError(
            "Synthetic original recording이 "
            "one_hand routing이 아님: "
            f"{original_usage_type}"
        )


    # ========================================================
    # Frozen TEMP recollection
    #
    # Exact frozen logic:
    #
    # BOTH frames only.
    # ========================================================

    both_frames_for_rescue = [
        (
            left_frame,
            right_frame,
        )

        for left_frame, right_frame
        in recording_frames

        if (
            left_frame is not None
            and
            right_frame is not None
        )
    ]


    if (
        len(both_frames_for_rescue)
        !=
        BOTH_COUNT
    ):
        raise RuntimeError(
            "TEMP BOTH recollection count mismatch"
        )


    # ========================================================
    # Exact frozen TEMP feature path
    #
    # frozen 07g:
    #
    # rescue_feature_info =
    #     u.build_webcam_feature(
    #         both_frames_for_rescue
    #     )
    #
    # validate_webcam_feature(...)
    # ========================================================

    rescue_feature_info = (
        frozen.u.build_webcam_feature(
            both_frames_for_rescue
        )
    )

    (
        rescue_feature,
        rescue_usage_type,
    ) = frozen.validate_webcam_feature(
        rescue_feature_info
    )


    if (
        rescue_usage_type
        !=
        "two_hand"
    ):
        raise RuntimeError(
            "TEMP rescue feature가 "
            "two_hand가 아님: "
            f"{rescue_usage_type}"
        )


    rescue_feature = np.ascontiguousarray(
        rescue_feature,
        dtype=np.float32,
    )


    if (
        rescue_feature.shape
        !=
        (80, 172)
    ):
        raise RuntimeError(
            "Unexpected rescue Feature V3 shape: "
            f"{rescue_feature.shape}"
        )


    rescue_local = np.ascontiguousarray(
        rescue_feature[
            :,
            0:frozen.LOCAL_DIM,
        ],
        dtype=np.float32,
    )


    if (
        rescue_local.shape
        !=
        (80, 84)
    ):
        raise RuntimeError(
            "Unexpected rescue Local84 shape: "
            f"{rescue_local.shape}"
        )


    # ========================================================
    # Frozen two-hand classifier
    # ========================================================

    aihub = (
        frozen.load_aihub_train_references()
    )


    rescue_result = (
        frozen.classify_two_hand(
            local=rescue_local,
            aihub=aihub,
        )
    )


    base_id = int(
        rescue_result[
            "base_id"
        ]
    )

    final_id = int(
        rescue_result[
            "final_id"
        ]
    )

    stage = str(
        rescue_result[
            "stage"
        ]
    )

    base_ranking = (
        rescue_result[
            "base_ranking"
        ]
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


    if ranking_scores.size < 2:
        raise RuntimeError(
            "Base ranking has fewer than 2 classes"
        )


    base_margin = np.float32(
        ranking_scores[1]
        -
        ranking_scores[0]
    )


    rescued = (
        final_id
        ==
        frozen.TEMP_ID
    )


    # This fixture is intentionally our negative case.
    if rescued:
        raise RuntimeError(
            "Expected TEMP negative fixture, "
            "but final_id == TEMP_ID"
        )


    # ========================================================
    # Export Python frozen expected fixture
    # ========================================================

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    rescue_feature.tofile(
        OUTPUT_DIR
        / "expected_rescue_feature_80x172.bin"
    )


    rescue_local.tofile(
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
        [base_id],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_base_id.bin"
    )


    np.asarray(
        [final_id],
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
        [
            total_frames,
            left_count,
            right_count,
            both_count,
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
        [int(rescued)],
        dtype=np.int32,
    ).tofile(
        OUTPUT_DIR
        / "expected_rescued.bin"
    )


    (
        OUTPUT_DIR
        / "expected_stage.txt"
    ).write_text(
        stage,
        encoding="utf-8",
    )


    (
        OUTPUT_DIR
        / "fixture_info.txt"
    ).write_text(
        "\n".join(
            [
                "fixture=TEST-ONLY synthetic TEMP negative",
                "raw_source=feature_v3_twohand",
                f"total_frames={total_frames}",
                f"left_count={left_count}",
                f"right_count={right_count}",
                f"both_count={both_count}",
                f"both_ratio={both_ratio:.17g}",
                f"original_usage={original_usage_type}",
                f"rescue_usage={rescue_usage_type}",
                f"base_id={base_id}",
                f"final_id={final_id}",
                f"stage={stage}",
                f"rescued={rescued}",
            ]
        ),
        encoding="utf-8",
    )


    # ========================================================
    # Output
    # ========================================================

    print()
    print(
        "=" * 80
    )

    print(
        "TEMP NEGATIVE PYTHON EXPECTED"
    )

    print(
        "=" * 80
    )


    print(
        "total frames       :",
        total_frames,
    )

    print(
        "left count         :",
        left_count,
    )

    print(
        "right count        :",
        right_count,
    )

    print(
        "both count         :",
        both_count,
    )

    print(
        "both ratio         :",
        f"{both_ratio:.12f}",
    )

    print(
        "original usage     :",
        original_usage_type,
    )

    print(
        "rescue BOTH frames :",
        len(
            both_frames_for_rescue
        ),
    )

    print(
        "rescue usage       :",
        rescue_usage_type,
    )

    print(
        "rescue feature     :",
        rescue_feature.shape,
    )

    print(
        "rescue Local84     :",
        rescue_local.shape,
    )

    print()

    print(
        "base_id            :",
        base_id,
    )

    print(
        "final_id           :",
        final_id,
    )

    print(
        "stage              :",
        stage,
    )

    print(
        "base_margin        :",
        f"{float(base_margin):.9f}",
    )

    print(
        "TEMP rescued       :",
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
        "TEMP NEGATIVE PYTHON FIXTURE EXPORT PASS"
    )

    print(
        "=" * 80
    )


if __name__ == "__main__":
    main()