import numpy as np


# ============================================================
# 공통 상수
# ============================================================

EPS = 1e-8

HAND_LANDMARK_COUNT = 21

# Wrist -> MCP
HAND_SCALE_LANDMARKS = (
    5,
    9,
    13,
    17,
)


# ============================================================
# Feature version
# ============================================================

FEATURE_V1_VERSION = (
    "global_local_xy_v1"
)

FEATURE_V2_VERSION = (
    "pair_relative_local_xy_v2"
)

FEATURE_V3_VERSION = (
    "canonical_onehand_pair_local_trajectory_xy_v3"
)


# ============================================================
# Feature dimension
#
# 기존 v1 / v2 코드를 깨지 않기 위해
# FEATURE_DIM은 168 유지.
#
# 새 v3는 FEATURE_V3_DIM 사용.
# ============================================================

FEATURE_DIM = 168

FEATURE_V3_DIM = 172


# ============================================================
# v3 기본 설정
#
# 현재 AI Hub 분석 기준 candidate threshold.
#
# 04k / 04m 결과:
#
# one-hand
#   꺼지다  weak/strong ≈ 0.04
#   아프다  ≈ 0.025
#   괜찮다  ≈ 0.033
#
# two-hand
#   감사/연기 포함 최소가 약 0.6 수준
#
# 0.20은 현재 데이터에서 충분한 간격이 있음.
#
# NO_MOTION_THRESHOLD=3.0:
#   꺼지다 REAL02 약 0.3 수준 → invalid
#
# ※ 향후 MediaPipe webcam 데이터로 다시 검증 예정.
# ============================================================

DEFAULT_ONE_HAND_RATIO_THRESHOLD = 0.20

DEFAULT_NO_MOTION_THRESHOLD = 3.0

DEFAULT_ANCHOR_FRAME_COUNT = 5

DEFAULT_CANONICAL_HAND = "RIGHT"


# ============================================================
# 기본 validation
# ============================================================

def _as_hand_sequence(
    sequence,
    name="hand_sequence",
    allow_none=False,
):

    if sequence is None:

        if allow_none:

            return None

        raise ValueError(
            f"{name} is None"
        )


    array = np.asarray(
        sequence,
        dtype=np.float64
    )


    if array.ndim != 3:

        raise ValueError(
            (
                f"{name} shape 오류: "
                f"{array.shape} "
                f"(expected T x 21 x 2)"
            )
        )


    if array.shape[1] != HAND_LANDMARK_COUNT:

        raise ValueError(
            (
                f"{name} landmark 수 오류: "
                f"{array.shape}"
            )
        )


    # 혹시 confidence 등이 뒤에 붙어 있어도
    # XY만 사용
    if array.shape[2] < 2:

        raise ValueError(
            (
                f"{name} 좌표 차원 오류: "
                f"{array.shape}"
            )
        )


    array = array[
        :,
        :,
        :2
    ]


    if not np.all(
        np.isfinite(
            array
        )
    ):

        raise ValueError(
            f"{name}에 NaN/Inf 존재"
        )


    return array


# ============================================================
# sequence 전체가 사실상 없는 손인지 검사
#
# MediaPipe:
#   검출 안 됨 → None
#
# AI Hub:
#   만약 sequence 전체가 0이면 missing으로 처리
#
# 한두 frame만 zero인 경우는
# 전체 hand를 missing으로 판정하지 않는다.
# ============================================================

def _is_missing_sequence(
    sequence
):

    if sequence is None:

        return True


    if len(
        sequence
    ) == 0:

        return True


    return bool(
        np.all(
            np.abs(
                sequence
            ) < EPS
        )
    )


# ============================================================
# 두 sequence frame 수 검사
# ============================================================

def _validate_same_frame_count(
    left_sequence,
    right_sequence
):

    if (
        left_sequence is not None
        and
        right_sequence is not None
    ):

        if (
            len(
                left_sequence
            )
            !=
            len(
                right_sequence
            )
        ):

            raise ValueError(
                (
                    "Left / Right frame 수가 다름: "
                    f"{len(left_sequence)} "
                    f"vs "
                    f"{len(right_sequence)}"
                )
            )


# ============================================================
# frame 수 얻기
# ============================================================

def _get_frame_count(
    left_sequence,
    right_sequence
):

    if (
        left_sequence is not None
        and
        not _is_missing_sequence(
            left_sequence
        )
    ):

        return len(
            left_sequence
        )


    if (
        right_sequence is not None
        and
        not _is_missing_sequence(
            right_sequence
        )
    ):

        return len(
            right_sequence
        )


    # 둘 다 실제로는 zero sequence일 수도 있으므로
    # 길이는 보존
    if left_sequence is not None:

        return len(
            left_sequence
        )


    if right_sequence is not None:

        return len(
            right_sequence
        )


    return 0


# ============================================================
# zero hand sequence
# ============================================================

def _zero_hand_sequence(
    frame_count
):

    return np.zeros(
        (
            frame_count,
            HAND_LANDMARK_COUNT,
            2
        ),
        dtype=np.float64
    )


# ============================================================
# Hand scale
#
# wrist(0)과
# MCP 5,9,13,17 거리 평균
#
# return:
#   pixel 단위 scale
# ============================================================

def hand_scale(
    hand
):

    hand = np.asarray(
        hand,
        dtype=np.float64
    )


    if hand.ndim != 2:

        raise ValueError(
            (
                "hand shape 오류: "
                f"{hand.shape}"
            )
        )


    if (
        hand.shape[0]
        !=
        HAND_LANDMARK_COUNT
    ):

        raise ValueError(
            (
                "hand landmark 수 오류: "
                f"{hand.shape}"
            )
        )


    hand = hand[
        :,
        :2
    ]


    if not np.all(
        np.isfinite(
            hand
        )
    ):

        return 0.0


    # frame 전체가 zero
    if np.all(
        np.abs(
            hand
        ) < EPS
    ):

        return 0.0


    wrist = hand[
        0
    ]


    distances = []


    for index in HAND_SCALE_LANDMARKS:

        distance = np.linalg.norm(
            hand[
                index
            ]
            -
            wrist
        )


        if (
            np.isfinite(
                distance
            )
            and
            distance > EPS
        ):

            distances.append(
                float(
                    distance
                )
            )


    if not distances:

        return 0.0


    return float(
        np.mean(
            distances
        )
    )


# ============================================================
# Sequence 대표 hand scale
#
# Left + Right의
# 모든 유효 frame hand scale median
#
# right_sequence=None도 허용
# ============================================================

def sequence_scale(
    left_sequence,
    right_sequence=None
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence",
        allow_none=True
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence",
        allow_none=True
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    scales = []


    for sequence in (
        left_sequence,
        right_sequence,
    ):

        if sequence is None:

            continue


        if _is_missing_sequence(
            sequence
        ):

            continue


        for hand in sequence:

            scale = hand_scale(
                hand
            )


            if (
                np.isfinite(
                    scale
                )
                and
                scale > EPS
            ):

                scales.append(
                    scale
                )


    if not scales:

        return 1.0


    return float(
        np.median(
            np.asarray(
                scales,
                dtype=np.float64
            )
        )
    )


# ============================================================
# 한 손 sequence 대표 scale
# ============================================================

def single_hand_sequence_scale(
    hand_sequence
):

    hand_sequence = _as_hand_sequence(
        hand_sequence,
        name="hand_sequence"
    )


    scales = []


    for hand in hand_sequence:

        value = hand_scale(
            hand
        )


        if (
            np.isfinite(
                value
            )
            and
            value > EPS
        ):

            scales.append(
                value
            )


    if not scales:

        return 1.0


    return float(
        np.median(
            scales
        )
    )


# ============================================================
# Local hand
#
# 각 frame:
#
# wrist를 원점으로 이동
# /
# 해당 frame hand scale
#
# 손의 위치 이동은 제거하고
# 손 모양을 남긴다.
#
# output:
#   (T,21,2)
# ============================================================

def make_local_hand(
    hand_sequence
):

    hand_sequence = _as_hand_sequence(
        hand_sequence,
        name="hand_sequence"
    )


    frame_count = len(
        hand_sequence
    )


    output = np.zeros(
        (
            frame_count,
            HAND_LANDMARK_COUNT,
            2
        ),
        dtype=np.float64
    )


    # frame scale이 0인 특수 frame에서
    # fallback으로 사용
    fallback_scale = (
        single_hand_sequence_scale(
            hand_sequence
        )
    )


    for frame_index in range(
        frame_count
    ):

        hand = hand_sequence[
            frame_index
        ]


        # AI Hub 특이 zero frame 대응
        if np.all(
            np.abs(
                hand
            ) < EPS
        ):

            continue


        wrist = hand[
            0
        ]


        scale = hand_scale(
            hand
        )


        if (
            not np.isfinite(
                scale
            )
            or
            scale <= EPS
        ):

            scale = fallback_scale


        if (
            not np.isfinite(
                scale
            )
            or
            scale <= EPS
        ):

            scale = 1.0


        output[
            frame_index
        ] = (
            hand
            -
            wrist
        ) / scale


    return output


# ============================================================
# v1
# 초기 bilateral wrist midpoint anchor
# ============================================================

def calculate_anchor(
    left_sequence,
    right_sequence,
    anchor_frame_count=DEFAULT_ANCHOR_FRAME_COUNT
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence"
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence"
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    frame_count = len(
        left_sequence
    )


    if frame_count == 0:

        raise ValueError(
            "빈 sequence"
        )


    count = min(
        int(
            anchor_frame_count
        ),
        frame_count
    )


    left_wrist = left_sequence[
        :count,
        0,
        :
    ]


    right_wrist = right_sequence[
        :count,
        0,
        :
    ]


    midpoint = (
        left_wrist
        +
        right_wrist
    ) / 2.0


    anchor = np.median(
        midpoint,
        axis=0
    )


    return np.asarray(
        anchor,
        dtype=np.float64
    )


# ============================================================
# v1 Absolute Global
#
# 이전 실험 재현용으로 유지.
#
# 현재 최종 feature 후보에는 사용하지 않음.
# ============================================================

def make_global_features(
    left_sequence,
    right_sequence,
    anchor=None,
    scale=None,
    anchor_frame_count=DEFAULT_ANCHOR_FRAME_COUNT
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence"
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence"
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    if anchor is None:

        anchor = calculate_anchor(
            left_sequence,
            right_sequence,
            anchor_frame_count=anchor_frame_count
        )


    anchor = np.asarray(
        anchor,
        dtype=np.float64
    ).reshape(
        2
    )


    if scale is None:

        scale = sequence_scale(
            left_sequence,
            right_sequence
        )


    if (
        not np.isfinite(
            scale
        )
        or
        scale <= EPS
    ):

        scale = 1.0


    global_left = (
        left_sequence
        -
        anchor[
            np.newaxis,
            np.newaxis,
            :
        ]
    ) / scale


    global_right = (
        right_sequence
        -
        anchor[
            np.newaxis,
            np.newaxis,
            :
        ]
    ) / scale


    return (
        global_left,
        global_right
    )


# ============================================================
# 여러 feature block 결합
#
# 각 block:
#   첫 번째 차원 = T
#
# 나머지는 자동 flatten
# ============================================================

def _combine_features(
    *parts
):

    if not parts:

        raise ValueError(
            "feature part 없음"
        )


    arrays = []


    frame_count = None


    for index, part in enumerate(
        parts
    ):

        array = np.asarray(
            part,
            dtype=np.float64
        )


        if array.ndim < 2:

            raise ValueError(
                (
                    f"part {index} shape 오류: "
                    f"{array.shape}"
                )
            )


        if frame_count is None:

            frame_count = array.shape[
                0
            ]

        elif (
            array.shape[
                0
            ]
            !=
            frame_count
        ):

            raise ValueError(
                (
                    "feature block frame 수 불일치: "
                    f"{array.shape[0]} "
                    f"vs {frame_count}"
                )
            )


        arrays.append(
            array.reshape(
                frame_count,
                -1
            )
        )


    combined = np.concatenate(
        arrays,
        axis=1
    )


    return np.asarray(
        combined,
        dtype=np.float32
    )


# ============================================================
# Feature matrix validation
# ============================================================

def _validate_feature_matrix(
    features,
    expected_dim,
    name="features"
):

    features = np.asarray(
        features
    )


    if features.ndim != 2:

        raise ValueError(
            (
                f"{name} shape 오류: "
                f"{features.shape}"
            )
        )


    if (
        features.shape[
            1
        ]
        !=
        expected_dim
    ):

        raise ValueError(
            (
                f"{name} dimension 오류: "
                f"{features.shape[1]} "
                f"(expected {expected_dim})"
            )
        )


    if not np.all(
        np.isfinite(
            features
        )
    ):

        raise ValueError(
            f"{name}에 NaN/Inf 존재"
        )


    return features


# ============================================================
# v1
#
# Global Left   42
# Global Right  42
# Local Left    42
# Local Right   42
#
# = 168
# ============================================================

def build_hand_features(
    left_sequence,
    right_sequence
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence"
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence"
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    (
        global_left,
        global_right
    ) = make_global_features(
        left_sequence,
        right_sequence
    )


    local_left = make_local_hand(
        left_sequence
    )


    local_right = make_local_hand(
        right_sequence
    )


    features = _combine_features(
        global_left,
        global_right,
        local_left,
        local_right
    )


    _validate_feature_matrix(
        features,
        FEATURE_DIM,
        name="v1 features"
    )


    return features


# ============================================================
# v2 Pair-relative
#
# 매 frame:
#
# midpoint =
#   (left wrist + right wrist) / 2
#
# 각 hand landmark를
# midpoint 기준으로 변환.
#
# 양손 상대 위치는 남고
# 공통 translation은 제거된다.
# ============================================================

def make_pair_relative_features(
    left_sequence,
    right_sequence,
    scale=None
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence"
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence"
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    if scale is None:

        scale = sequence_scale(
            left_sequence,
            right_sequence
        )


    if (
        not np.isfinite(
            scale
        )
        or
        scale <= EPS
    ):

        scale = 1.0


    left_wrist = left_sequence[
        :,
        0,
        :
    ]


    right_wrist = right_sequence[
        :,
        0,
        :
    ]


    midpoint = (
        left_wrist
        +
        right_wrist
    ) / 2.0


    midpoint = midpoint[
        :,
        np.newaxis,
        :
    ]


    pair_left = (
        left_sequence
        -
        midpoint
    ) / scale


    pair_right = (
        right_sequence
        -
        midpoint
    ) / scale


    return (
        pair_left,
        pair_right
    )


# ============================================================
# v2
#
# Pair Left    42
# Pair Right   42
# Local Left   42
# Local Right  42
#
# = 168
# ============================================================

def build_pair_local_features(
    left_sequence,
    right_sequence
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence"
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence"
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    (
        pair_left,
        pair_right
    ) = make_pair_relative_features(
        left_sequence,
        right_sequence
    )


    local_left = make_local_hand(
        left_sequence
    )


    local_right = make_local_hand(
        right_sequence
    )


    features = _combine_features(
        pair_left,
        pair_right,
        local_left,
        local_right
    )


    _validate_feature_matrix(
        features,
        FEATURE_DIM,
        name="v2 features"
    )


    return features


# ============================================================
# ============================================================
#
# Feature v3
#
# ============================================================
# ============================================================


# ============================================================
# Hand motion score
#
# frame-to-frame
# 21 landmark 평균 displacement
# /
# sequence 대표 hand size
#
# 의 전체 합.
#
# 04k / 04m hand usage 검사와 동일한 개념.
# ============================================================

def calculate_hand_motion_score(
    hand_sequence
):

    if hand_sequence is None:

        return 0.0


    hand_sequence = _as_hand_sequence(
        hand_sequence,
        name="hand_sequence"
    )


    if (
        len(
            hand_sequence
        )
        < 2
    ):

        return 0.0


    if _is_missing_sequence(
        hand_sequence
    ):

        return 0.0


    scale = single_hand_sequence_scale(
        hand_sequence
    )


    diff = np.diff(
        hand_sequence,
        axis=0
    )


    # T-1 x 21
    joint_distance = np.linalg.norm(
        diff,
        axis=2
    )


    # 각 frame의 21개 joint 평균 이동량
    frame_motion = np.mean(
        joint_distance,
        axis=1
    )


    normalized_motion = (
        frame_motion
        /
        (
            scale + EPS
        )
    )


    return float(
        np.sum(
            normalized_motion
        )
    )


# ============================================================
# Hand usage 판정
#
# 지원:
#
# 1) AI Hub
#    left + right 둘 다 존재
#
# 2) MediaPipe
#    left만 존재
#    right만 존재
#    둘 다 존재
#
#
# usage type:
#
# invalid
# one_hand
# two_hand
#
#
# 중요:
#
# usage_mask는 physical LEFT/RIGHT mask가 아니다.
#
# one-hand:
#   [1,0]
#
# two-hand:
#   [1,1]
#
# invalid:
#   [0,0]
#
# 즉 v3 feature 슬롯 사용 여부를 의미한다.
# ============================================================

def detect_hand_usage(
    left_sequence=None,
    right_sequence=None,
    one_hand_ratio_threshold=(
        DEFAULT_ONE_HAND_RATIO_THRESHOLD
    ),
    no_motion_threshold=(
        DEFAULT_NO_MOTION_THRESHOLD
    ),
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence",
        allow_none=True
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence",
        allow_none=True
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    left_detected = (
        not _is_missing_sequence(
            left_sequence
        )
    )


    right_detected = (
        not _is_missing_sequence(
            right_sequence
        )
    )


    detected_mask = np.asarray(
        [
            1.0 if left_detected else 0.0,
            1.0 if right_detected else 0.0,
        ],
        dtype=np.float32
    )


    left_score = (
        calculate_hand_motion_score(
            left_sequence
        )
        if left_detected
        else 0.0
    )


    right_score = (
        calculate_hand_motion_score(
            right_sequence
        )
        if right_detected
        else 0.0
    )


    # ========================================================
    # 손 자체가 하나도 없음
    # ========================================================

    if (
        not left_detected
        and
        not right_detected
    ):

        return {
            "type":
                "invalid",

            "active_hand":
                None,

            "left_score":
                0.0,

            "right_score":
                0.0,

            "ratio":
                1.0,

            "usage_mask":
                np.asarray(
                    [
                        0.0,
                        0.0
                    ],
                    dtype=np.float32
                ),

            # 기존 04m 호환용 alias
            "presence":
                np.asarray(
                    [
                        0.0,
                        0.0
                    ],
                    dtype=np.float32
                ),

            "detected_mask":
                detected_mask,
        }


    # ========================================================
    # MediaPipe에서 LEFT만 검출
    # ========================================================

    if (
        left_detected
        and
        not right_detected
    ):

        if (
            left_score
            <
            no_motion_threshold
        ):

            usage_type = (
                "invalid"
            )

            active_hand = None

            usage_mask = np.asarray(
                [
                    0.0,
                    0.0
                ],
                dtype=np.float32
            )

        else:

            usage_type = (
                "one_hand"
            )

            active_hand = (
                "LEFT"
            )

            usage_mask = np.asarray(
                [
                    1.0,
                    0.0
                ],
                dtype=np.float32
            )


        return {
            "type":
                usage_type,

            "active_hand":
                active_hand,

            "left_score":
                left_score,

            "right_score":
                0.0,

            "ratio":
                0.0,

            "usage_mask":
                usage_mask,

            "presence":
                usage_mask.copy(),

            "detected_mask":
                detected_mask,
        }


    # ========================================================
    # MediaPipe에서 RIGHT만 검출
    # ========================================================

    if (
        right_detected
        and
        not left_detected
    ):

        if (
            right_score
            <
            no_motion_threshold
        ):

            usage_type = (
                "invalid"
            )

            active_hand = None

            usage_mask = np.asarray(
                [
                    0.0,
                    0.0
                ],
                dtype=np.float32
            )

        else:

            usage_type = (
                "one_hand"
            )

            active_hand = (
                "RIGHT"
            )

            usage_mask = np.asarray(
                [
                    1.0,
                    0.0
                ],
                dtype=np.float32
            )


        return {
            "type":
                usage_type,

            "active_hand":
                active_hand,

            "left_score":
                0.0,

            "right_score":
                right_score,

            "ratio":
                0.0,

            "usage_mask":
                usage_mask,

            "presence":
                usage_mask.copy(),

            "detected_mask":
                detected_mask,
        }


    # ========================================================
    # 여기부터 양쪽 hand landmark 모두 존재
    # ========================================================

    stronger = max(
        left_score,
        right_score
    )


    weaker = min(
        left_score,
        right_score
    )


    # ========================================================
    # 양쪽 모두 사실상 무동작
    #
    # ex)
    # WORD2353 REAL02
    # ========================================================

    if (
        stronger
        <
        no_motion_threshold
    ):

        usage_mask = np.asarray(
            [
                0.0,
                0.0
            ],
            dtype=np.float32
        )


        return {
            "type":
                "invalid",

            "active_hand":
                None,

            "left_score":
                left_score,

            "right_score":
                right_score,

            "ratio":
                1.0,

            "usage_mask":
                usage_mask,

            "presence":
                usage_mask.copy(),

            "detected_mask":
                detected_mask,
        }


    ratio = float(
        weaker
        /
        (
            stronger + EPS
        )
    )


    # ========================================================
    # 한손 수어
    #
    # AI Hub에서는 inactive hand 좌표가 존재해도
    # 움직임이 매우 작기 때문에 여기서 판별.
    # ========================================================

    if (
        ratio
        <
        one_hand_ratio_threshold
    ):

        if (
            left_score
            >
            right_score
        ):

            active_hand = (
                "LEFT"
            )

        else:

            active_hand = (
                "RIGHT"
            )


        usage_mask = np.asarray(
            [
                1.0,
                0.0
            ],
            dtype=np.float32
        )


        return {
            "type":
                "one_hand",

            "active_hand":
                active_hand,

            "left_score":
                left_score,

            "right_score":
                right_score,

            "ratio":
                ratio,

            "usage_mask":
                usage_mask,

            "presence":
                usage_mask.copy(),

            "detected_mask":
                detected_mask,
        }


    # ========================================================
    # 양손 수어
    # ========================================================

    usage_mask = np.asarray(
        [
            1.0,
            1.0
        ],
        dtype=np.float32
    )


    return {
        "type":
            "two_hand",

        "active_hand":
            "BOTH",

        "left_score":
            left_score,

        "right_score":
            right_score,

        "ratio":
            ratio,

        "usage_mask":
            usage_mask,

        "presence":
            usage_mask.copy(),

        "detected_mask":
            detected_mask,
    }


# ============================================================
# X mirror
#
# wrist-centered Local 좌표나
# centered trajectory에서 사용.
#
# canonical hand = RIGHT 기준일 때
# LEFT active hand의 X를 뒤집는다.
# ============================================================

def mirror_x(
    values
):

    output = np.asarray(
        values,
        dtype=np.float64
    ).copy()


    output[
        ...,
        0
    ] *= -1.0


    return output


# ============================================================
# One-hand Local canonicalization
#
# 목표:
#
# AI Hub에서 RIGHT hand로 수행
# 사용자 LEFT hand로 수행
#
# 둘 다 SLOT A에 동일한 방향으로 배치.
#
#
# canonical_hand="RIGHT":
#
# RIGHT active
#   → 그대로
#
# LEFT active
#   → x mirror
# ============================================================

def canonicalize_one_hand_local(
    local_sequence,
    active_hand,
    canonical_hand=DEFAULT_CANONICAL_HAND
):

    local_sequence = np.asarray(
        local_sequence,
        dtype=np.float64
    )


    active_hand = str(
        active_hand
    ).upper()


    canonical_hand = str(
        canonical_hand
    ).upper()


    if active_hand not in (
        "LEFT",
        "RIGHT",
    ):

        raise ValueError(
            (
                "active_hand 오류: "
                f"{active_hand}"
            )
        )


    if canonical_hand not in (
        "LEFT",
        "RIGHT",
    ):

        raise ValueError(
            (
                "canonical_hand 오류: "
                f"{canonical_hand}"
            )
        )


    if (
        active_hand
        ==
        canonical_hand
    ):

        return local_sequence.copy()


    return mirror_x(
        local_sequence
    )


# ============================================================
# Normalized trajectory
#
# one-hand:
#   active wrist
#
# two-hand:
#   bilateral wrist midpoint
#
#
# 1. 첫 N frame median anchor
# 2. anchor 기준 이동
# 3. radial distance p95로 normalize
#
# 따라서 수행 크기 차이를 크게 줄이고
# 이동 방향/형태를 중심으로 남긴다.
#
#
# one-hand LEFT를 canonical RIGHT로 옮길 경우
# trajectory의 X도 같이 mirror.
# ============================================================

def make_normalized_trajectory(
    left_sequence,
    right_sequence,
    usage,
    anchor_frame_count=(
        DEFAULT_ANCHOR_FRAME_COUNT
    ),
    canonical_hand=(
        DEFAULT_CANONICAL_HAND
    ),
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence",
        allow_none=True
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence",
        allow_none=True
    )


    frame_count = _get_frame_count(
        left_sequence,
        right_sequence
    )


    if frame_count == 0:

        return (
            np.zeros(
                (
                    0,
                    2
                ),
                dtype=np.float32
            ),
            1.0
        )


    usage_type = usage[
        "type"
    ]


    # ========================================================
    # Invalid
    # ========================================================

    if usage_type == "invalid":

        return (
            np.zeros(
                (
                    frame_count,
                    2
                ),
                dtype=np.float32
            ),
            1.0
        )


    # ========================================================
    # One-hand
    # ========================================================

    if usage_type == "one_hand":

        active_hand = usage[
            "active_hand"
        ]


        if active_hand == "LEFT":

            if left_sequence is None:

                raise ValueError(
                    "LEFT active인데 left_sequence 없음"
                )


            reference = left_sequence[
                :,
                0,
                :
            ]


        elif active_hand == "RIGHT":

            if right_sequence is None:

                raise ValueError(
                    "RIGHT active인데 right_sequence 없음"
                )


            reference = right_sequence[
                :,
                0,
                :
            ]


        else:

            raise ValueError(
                (
                    "one_hand인데 active_hand 오류: "
                    f"{active_hand}"
                )
            )


    # ========================================================
    # Two-hand
    # ========================================================

    elif usage_type == "two_hand":

        if (
            left_sequence is None
            or
            right_sequence is None
        ):

            raise ValueError(
                (
                    "two_hand trajectory에는 "
                    "양손 sequence 필요"
                )
            )


        left_wrist = left_sequence[
            :,
            0,
            :
        ]


        right_wrist = right_sequence[
            :,
            0,
            :
        ]


        reference = (
            left_wrist
            +
            right_wrist
        ) / 2.0


    else:

        raise ValueError(
            (
                "usage type 오류: "
                f"{usage_type}"
            )
        )


    # ========================================================
    # 시작 anchor
    # ========================================================

    count = min(
        max(
            int(
                anchor_frame_count
            ),
            1
        ),
        len(
            reference
        )
    )


    anchor = np.median(
        reference[
            :count
        ],
        axis=0
    )


    centered = (
        reference
        -
        anchor
    )


    radial_distance = np.linalg.norm(
        centered,
        axis=1
    )


    trajectory_scale = float(
        np.percentile(
            radial_distance,
            95
        )
    )


    # 손목이 거의 움직이지 않는 수어면
    # trajectory는 사실상 zero에 가깝게 둔다.
    if (
        not np.isfinite(
            trajectory_scale
        )
        or
        trajectory_scale
        <= EPS
    ):

        trajectory_scale = 1.0


    trajectory = (
        centered
        /
        trajectory_scale
    )


    # ========================================================
    # one-hand handedness canonicalization
    # ========================================================

    if usage_type == "one_hand":

        active_hand = usage[
            "active_hand"
        ].upper()


        canonical_hand = canonical_hand.upper()


        if (
            active_hand
            !=
            canonical_hand
        ):

            trajectory = mirror_x(
                trajectory
            )


    return (
        np.asarray(
            trajectory,
            dtype=np.float32
        ),
        trajectory_scale
    )


# ============================================================
# Feature v3
#
# Canonical SLOT 구조
#
# ------------------------------------------------------------
#
# SLOT A Local                 42
# SLOT B Local                 42
#
# Pair A                       42
# Pair B                       42
#
# Normalized Trajectory XY      2
# Usage Mask                    2
#
# ------------------------------------------------------------
# TOTAL                       172
#
#
# one-hand:
#
# SLOT A
#   = active hand
#   = canonical RIGHT 방향
#
# SLOT B
#   = zero
#
# Pair A/B
#   = zero
#
# usage mask
#   = [1,0]
#
#
# two-hand:
#
# SLOT A
#   = physical LEFT local
#
# SLOT B
#   = physical RIGHT local
#
# Pair A
#   = LEFT pair
#
# Pair B
#   = RIGHT pair
#
# usage mask
#   = [1,1]
#
#
# invalid:
#
# feature = None
# usage mask = [0,0]
#
#
# MediaPipe에서 한 손만 존재하는 경우:
#
# left_sequence=None
# 또는
# right_sequence=None
#
# 지원.
# ============================================================

def build_hand_features_v3(
    left_sequence=None,
    right_sequence=None,
    one_hand_ratio_threshold=(
        DEFAULT_ONE_HAND_RATIO_THRESHOLD
    ),
    no_motion_threshold=(
        DEFAULT_NO_MOTION_THRESHOLD
    ),
    anchor_frame_count=(
        DEFAULT_ANCHOR_FRAME_COUNT
    ),
    canonical_hand=(
        DEFAULT_CANONICAL_HAND
    ),
):

    left_sequence = _as_hand_sequence(
        left_sequence,
        name="left_sequence",
        allow_none=True
    )


    right_sequence = _as_hand_sequence(
        right_sequence,
        name="right_sequence",
        allow_none=True
    )


    _validate_same_frame_count(
        left_sequence,
        right_sequence
    )


    frame_count = _get_frame_count(
        left_sequence,
        right_sequence
    )


    if frame_count == 0:

        raise ValueError(
            "빈 sequence"
        )


    usage = detect_hand_usage(
        left_sequence=left_sequence,
        right_sequence=right_sequence,
        one_hand_ratio_threshold=(
            one_hand_ratio_threshold
        ),
        no_motion_threshold=(
            no_motion_threshold
        ),
    )


    # ========================================================
    # Invalid
    # ========================================================

    if (
        usage[
            "type"
        ]
        ==
        "invalid"
    ):

        return {
            "valid":
                False,

            "feature_version":
                FEATURE_V3_VERSION,

            "feature_dim":
                FEATURE_V3_DIM,

            "features":
                None,

            "usage":
                usage,

            "usage_mask":
                usage[
                    "usage_mask"
                ].copy(),

            "detected_mask":
                usage[
                    "detected_mask"
                ].copy(),

            "slot_a_local":
                None,

            "slot_b_local":
                None,

            "pair_a":
                None,

            "pair_b":
                None,

            "trajectory":
                None,

            "trajectory_scale":
                None,

            "canonical_hand":
                canonical_hand,

            "canonicalized":
                False,
        }


    # ========================================================
    # 실제 physical hand local
    #
    # debug용으로도 반환
    # ========================================================

    if (
        left_sequence is not None
        and
        not _is_missing_sequence(
            left_sequence
        )
    ):

        physical_left_local = (
            make_local_hand(
                left_sequence
            )
        )

    else:

        physical_left_local = (
            _zero_hand_sequence(
                frame_count
            )
        )


    if (
        right_sequence is not None
        and
        not _is_missing_sequence(
            right_sequence
        )
    ):

        physical_right_local = (
            make_local_hand(
                right_sequence
            )
        )

    else:

        physical_right_local = (
            _zero_hand_sequence(
                frame_count
            )
        )


    # ========================================================
    # One-hand
    # ========================================================

    if (
        usage[
            "type"
        ]
        ==
        "one_hand"
    ):

        active_hand = usage[
            "active_hand"
        ]


        if active_hand == "LEFT":

            active_local = (
                physical_left_local
            )


        elif active_hand == "RIGHT":

            active_local = (
                physical_right_local
            )


        else:

            raise ValueError(
                (
                    "one_hand active_hand 오류: "
                    f"{active_hand}"
                )
            )


        # ----------------------------------------------------
        # 핵심:
        # active hand를 항상 canonical 방향으로
        # SLOT A에 넣음
        # ----------------------------------------------------

        slot_a_local = (
            canonicalize_one_hand_local(
                active_local,
                active_hand=active_hand,
                canonical_hand=canonical_hand
            )
        )


        slot_b_local = (
            _zero_hand_sequence(
                frame_count
            )
        )


        pair_a = (
            _zero_hand_sequence(
                frame_count
            )
        )


        pair_b = (
            _zero_hand_sequence(
                frame_count
            )
        )


        canonicalized = (
            active_hand.upper()
            !=
            canonical_hand.upper()
        )


    # ========================================================
    # Two-hand
    # ========================================================

    elif (
        usage[
            "type"
        ]
        ==
        "two_hand"
    ):

        if (
            left_sequence is None
            or
            right_sequence is None
        ):

            raise ValueError(
                (
                    "two_hand feature에는 "
                    "양손 sequence 필요"
                )
            )


        slot_a_local = (
            physical_left_local
        )


        slot_b_local = (
            physical_right_local
        )


        (
            pair_a,
            pair_b
        ) = make_pair_relative_features(
            left_sequence,
            right_sequence
        )


        canonicalized = False


    else:

        raise ValueError(
            (
                "usage type 오류: "
                f"{usage['type']}"
            )
        )


    # ========================================================
    # Trajectory
    # ========================================================

    (
        trajectory,
        trajectory_scale
    ) = make_normalized_trajectory(
        left_sequence=left_sequence,
        right_sequence=right_sequence,
        usage=usage,
        anchor_frame_count=(
            anchor_frame_count
        ),
        canonical_hand=(
            canonical_hand
        ),
    )


    # ========================================================
    # Usage mask
    #
    # frame마다 반복
    # ========================================================

    usage_mask = usage[
        "usage_mask"
    ]


    usage_mask_frames = np.repeat(
        usage_mask[
            np.newaxis,
            :
        ],
        frame_count,
        axis=0
    )


    # ========================================================
    # 172 dim 결합
    # ========================================================

    features = _combine_features(
        slot_a_local,
        slot_b_local,
        pair_a,
        pair_b,
        trajectory,
        usage_mask_frames
    )


    _validate_feature_matrix(
        features,
        FEATURE_V3_DIM,
        name="v3 features"
    )


    # ========================================================
    # 반환
    # ========================================================

    return {
        "valid":
            True,

        "feature_version":
            FEATURE_V3_VERSION,

        "feature_dim":
            FEATURE_V3_DIM,

        "features":
            features,

        "usage":
            usage,

        "usage_mask":
            usage_mask.copy(),

        "detected_mask":
            usage[
                "detected_mask"
            ].copy(),

        # ----------------------------------------------------
        # 실제 model input block
        # ----------------------------------------------------

        "slot_a_local":
            np.asarray(
                slot_a_local,
                dtype=np.float32
            ),

        "slot_b_local":
            np.asarray(
                slot_b_local,
                dtype=np.float32
            ),

        "pair_a":
            np.asarray(
                pair_a,
                dtype=np.float32
            ),

        "pair_b":
            np.asarray(
                pair_b,
                dtype=np.float32
            ),

        "trajectory":
            np.asarray(
                trajectory,
                dtype=np.float32
            ),

        "trajectory_scale":
            float(
                trajectory_scale
            ),

        # ----------------------------------------------------
        # Debug / 분석용 physical local
        # ----------------------------------------------------

        "physical_left_local":
            np.asarray(
                physical_left_local,
                dtype=np.float32
            ),

        "physical_right_local":
            np.asarray(
                physical_right_local,
                dtype=np.float32
            ),

        "canonical_hand":
            canonical_hand.upper(),

        "canonicalized":
            bool(
                canonicalized
            ),
    }


# ============================================================
# 이름 짧게 쓰고 싶을 때 alias
# ============================================================

def build_feature_v3(
    left_sequence=None,
    right_sequence=None,
    **kwargs
):

    return build_hand_features_v3(
        left_sequence=left_sequence,
        right_sequence=right_sequence,
        **kwargs
    )


# ============================================================
# Feature layout 정보
# ============================================================

def get_feature_v3_layout():

    return {
        "slot_a_local":
            {
                "start": 0,
                "end": 42,
                "dim": 42,
            },

        "slot_b_local":
            {
                "start": 42,
                "end": 84,
                "dim": 42,
            },

        "pair_a":
            {
                "start": 84,
                "end": 126,
                "dim": 42,
            },

        "pair_b":
            {
                "start": 126,
                "end": 168,
                "dim": 42,
            },

        "trajectory_xy":
            {
                "start": 168,
                "end": 170,
                "dim": 2,
            },

        "usage_mask":
            {
                "start": 170,
                "end": 172,
                "dim": 2,
            },

        "total_dim":
            FEATURE_V3_DIM,
    }