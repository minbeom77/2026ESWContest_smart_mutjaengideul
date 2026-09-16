import os
import importlib.util

import numpy as np


# ============================================================
# 파일 정보
# ============================================================

FILE_TAG = "[테스트용 / 나중에 삭제 가능]"


# ============================================================
# 클래스
# ============================================================

OFF_ID = 2       # 2353 꺼지다
HURT_ID = 7      # 1152 아프다
OKAY_ID = 8      # 1381 괜찮다


ONE_HAND_IDS = [
    OFF_ID,
    HURT_ID,
    OKAY_ID,
]


# ============================================================
# 설정
# ============================================================

TARGET_FRAMES = 80
FULL_DIM = 172

LOCAL_START = 0
LOCAL_END = 84

TRAJ_START = 168
TRAJ_END = 170

FIRST60_START = 0
FIRST60_END = 48

LAST40_START = 48
LAST40_END = 80

K = 3


# ============================================================
# 촬영 계획
# ============================================================

TRIAL_PLAN = [
    {
        "true_id": OFF_ID,
        "repeat": 1,
    },
    {
        "true_id": OFF_ID,
        "repeat": 2,
    },
    {
        "true_id": OFF_ID,
        "repeat": 3,
    },

    {
        "true_id": OKAY_ID,
        "repeat": 1,
    },
    {
        "true_id": OKAY_ID,
        "repeat": 2,
    },
    {
        "true_id": OKAY_ID,
        "repeat": 3,
    },
]


# ============================================================
# 경로
# ============================================================

BASE_DIR = os.path.dirname(
    os.path.abspath(__file__)
)


RUNTIME_PATH = os.path.join(
    BASE_DIR,
    "06u_webcam_combined_hierarchy.py",
)


REFERENCE_PATH = os.path.join(
    BASE_DIR,
    "reference_data",
    "04p_v3_reference_80f.npz",
)


TRAIN_TEMPLATE_PATH = os.path.join(
    BASE_DIR,
    "template_runtime_v3",
    "05n_local_templates_train.npz",
)


SAVE_DIR = os.path.join(
    BASE_DIR,
    "diagnostics_v3",
)


SAVE_PATH = os.path.join(
    SAVE_DIR,
    "06z_off_okay_onehand_trials.npz",
)


os.makedirs(
    SAVE_DIR,
    exist_ok=True,
)


# ============================================================
# 06u import
# ============================================================

if not os.path.exists(
    RUNTIME_PATH
):

    raise FileNotFoundError(
        f"06u 파일 없음:\n"
        f"{RUNTIME_PATH}"
    )


spec = importlib.util.spec_from_file_location(
    "runtime06u",
    RUNTIME_PATH,
)


u = importlib.util.module_from_spec(
    spec
)


spec.loader.exec_module(
    u
)


# ============================================================
# 표시
# ============================================================

def class_text(
    class_id,
):

    label, word, usage = (
        u.runtime.CLASS_INFO[
            int(class_id)
        ]
    )


    return (
        f"{word[-4:]} "
        f"{label}"
    )


# ============================================================
# 파일 확인
# ============================================================

def check_required_files():

    print()
    print("=" * 120)
    print("FILE CHECK")
    print("=" * 120)


    paths = [
        RUNTIME_PATH,
        REFERENCE_PATH,
        TRAIN_TEMPLATE_PATH,
    ]


    for path in paths:

        if not os.path.exists(
            path
        ):

            raise FileNotFoundError(
                f"파일 없음:\n"
                f"{path}"
            )


        print(
            "PASS :",
            path,
        )


# ============================================================
# 04p 전체 107개
#
# +
#
# 05n TRAIN 67개의 class_id / real_id
#
# →
#
# 04p full172에서 TRAIN만 복원
# ============================================================

def load_train_full_references():

    # --------------------------------------------------------
    # 전체 04p
    # --------------------------------------------------------

    ref = np.load(
        REFERENCE_PATH,
        allow_pickle=True,
    )


    required_ref = {
        "features",
        "class_ids",
        "real_ids",
        "usage_types",
    }


    missing = (
        required_ref
        -
        set(ref.files)
    )


    if missing:

        raise RuntimeError(
            f"04p key 부족: "
            f"{missing}"
        )


    all_features = np.asarray(
        ref[
            "features"
        ],
        dtype=np.float32,
    )


    all_class_ids = np.asarray(
        ref[
            "class_ids"
        ],
        dtype=np.int64,
    )


    all_real_ids = np.asarray(
        ref[
            "real_ids"
        ]
    ).astype(str)


    all_usage_types = np.asarray(
        ref[
            "usage_types"
        ]
    ).astype(str)


    if all_features.shape != (
        107,
        TARGET_FRAMES,
        FULL_DIM,
    ):

        raise RuntimeError(
            "04p feature shape 오류: "
            f"{all_features.shape}"
        )


    if not np.all(
        np.isfinite(
            all_features
        )
    ):

        raise RuntimeError(
            "04p NaN/Inf"
        )


    # --------------------------------------------------------
    # 05n TRAIN
    # --------------------------------------------------------

    train_npz = np.load(
        TRAIN_TEMPLATE_PATH,
        allow_pickle=True,
    )


    required_train = {
        "class_ids",
        "real_ids",
    }


    missing = (
        required_train
        -
        set(train_npz.files)
    )


    if missing:

        raise RuntimeError(
            f"05n key 부족: "
            f"{missing}"
        )


    train_class_ids = np.asarray(
        train_npz[
            "class_ids"
        ],
        dtype=np.int64,
    )


    train_real_ids = np.asarray(
        train_npz[
            "real_ids"
        ]
    ).astype(str)


    if len(
        train_class_ids
    ) != 67:

        raise RuntimeError(
            "05n TRAIN template 수가 "
            f"67이 아님: "
            f"{len(train_class_ids)}"
        )


    if len(
        train_real_ids
    ) != len(
        train_class_ids
    ):

        raise RuntimeError(
            "05n class/REAL 개수 불일치"
        )


    # --------------------------------------------------------
    # TRAIN key
    # --------------------------------------------------------

    train_keys = {
        (
            int(class_id),
            str(real_id),
        )

        for class_id, real_id
        in zip(
            train_class_ids,
            train_real_ids,
        )
    }


    selected_indices = []


    for i in range(
        len(
            all_features
        )
    ):

        key = (
            int(
                all_class_ids[
                    i
                ]
            ),

            str(
                all_real_ids[
                    i
                ]
            ),
        )


        if key in train_keys:

            selected_indices.append(
                i
            )


    selected_indices = np.asarray(
        selected_indices,
        dtype=np.int64,
    )


    train_features = all_features[
        selected_indices
    ]


    train_y = all_class_ids[
        selected_indices
    ]


    train_real = all_real_ids[
        selected_indices
    ]


    train_usage = all_usage_types[
        selected_indices
    ]


    # --------------------------------------------------------
    # 정확히 TRAIN 67개가 복원됐는지
    # --------------------------------------------------------

    recovered_keys = {
        (
            int(class_id),
            str(real_id),
        )

        for class_id, real_id
        in zip(
            train_y,
            train_real,
        )
    }


    print()
    print("=" * 120)
    print("TRAIN-ONLY FULL172 RECONSTRUCTION")
    print("=" * 120)


    print(
        "04p total      :",
        all_features.shape,
    )


    print(
        "05n TRAIN keys :",
        len(
            train_keys
        ),
    )


    print(
        "Recovered      :",
        train_features.shape,
    )


    print(
        "Key equality   :",
        (
            "PASS"
            if recovered_keys
            ==
            train_keys
            else "FAIL"
        ),
    )


    if (
        train_features.shape
        !=
        (
            67,
            80,
            172,
        )
    ):

        raise RuntimeError(
            "TRAIN 복원 shape 오류: "
            f"{train_features.shape}"
        )


    if (
        recovered_keys
        !=
        train_keys
    ):

        missing_keys = (
            train_keys
            -
            recovered_keys
        )


        raise RuntimeError(
            "TRAIN key 복원 실패: "
            f"{missing_keys}"
        )


    # --------------------------------------------------------
    # one-hand 분포
    # --------------------------------------------------------

    print()
    print(
        "ONE-HAND TRAIN:"
    )


    for class_id in (
        ONE_HAND_IDS
    ):

        count = int(
            np.sum(
                train_y
                ==
                class_id
            )
        )


        print(
            f"  "
            f"{class_text(class_id):<16}"
            f": "
            f"{count}"
        )


    return {
        "features":
            train_features,

        "class_ids":
            train_y,

        "real_ids":
            train_real,

        "usage_types":
            train_usage,
    }


# ============================================================
# Handshape ACTIVE SLOT A
#
# one_hand v3에서는 실제 활성 손이
# canonical SLOT A = Local 0:42
#
# u.build_handshape_sequence(Local84)
# 결과:
#   A 20 + B 20 = 40
#
# 여기서는 실제 활성 A의 20차원만 사용
# ============================================================

def build_active_handshape(
    local_feature,
):

    hs40 = (
        u.build_handshape_sequence(
            local_feature
        )
    )


    if hs40.shape != (
        80,
        40,
    ):

        raise RuntimeError(
            "Handshape shape 오류: "
            f"{hs40.shape}"
        )


    active20 = hs40[
        :,
        0:20,
    ].copy()


    if active20.shape != (
        80,
        20,
    ):

        raise RuntimeError(
            "Active Handshape 오류: "
            f"{active20.shape}"
        )


    return active20


# ============================================================
# TRAIN Handshape 생성
# ============================================================

def build_train_handshape(
    train,
):

    features = train[
        "features"
    ]


    output = []


    for feature in features:

        local = feature[
            :,
            LOCAL_START:
            LOCAL_END,
        ]


        output.append(
            build_active_handshape(
                local
            )
        )


    output = np.stack(
        output,
        axis=0,
    ).astype(
        np.float32
    )


    if output.shape != (
        67,
        80,
        20,
    ):

        raise RuntimeError(
            "TRAIN Handshape 오류: "
            f"{output.shape}"
        )


    print()
    print("=" * 120)
    print("TRAIN HANDSHAPE")
    print("=" * 120)


    print(
        "Shape:",
        output.shape,
    )


    print(
        "Finite:",
        (
            "PASS"
            if np.all(
                np.isfinite(
                    output
                )
            )
            else "FAIL"
        ),
    )


    return output


# ============================================================
# K-nearest class RMSE
# ============================================================

def class_score(
    query,
    references,
):

    query = np.asarray(
        query,
        dtype=np.float32,
    )


    references = np.asarray(
        references,
        dtype=np.float32,
    )


    diff = (
        references
        -
        query[
            None,
            ...
        ]
    )


    axes = tuple(
        range(
            1,
            diff.ndim,
        )
    )


    distances = np.sqrt(
        np.mean(
            diff ** 2,
            axis=axes,
        )
    )


    order = np.argsort(
        distances
    )


    selected = distances[
        order[:K]
    ]


    return float(
        np.mean(
            selected
        )
    )


# ============================================================
# Ranking
# ============================================================

def make_ranking(
    query,
    reference_features,
    reference_class_ids,
):

    ranking = []


    for class_id in (
        ONE_HAND_IDS
    ):

        indices = np.where(
            reference_class_ids
            ==
            class_id
        )[0]


        if len(indices) < K:

            raise RuntimeError(
                f"{class_text(class_id)} "
                f"reference 부족"
            )


        score = class_score(
            query=query,
            references=(
                reference_features[
                    indices
                ]
            ),
        )


        ranking.append(
            {
                "class_id":
                    int(class_id),

                "score":
                    float(score),
            }
        )


    ranking.sort(
        key=lambda x:
        x[
            "score"
        ]
    )


    return ranking


# ============================================================
# 특정 class score
# ============================================================

def ranking_score(
    ranking,
    class_id,
):

    for item in ranking:

        if (
            int(
                item[
                    "class_id"
                ]
            )
            ==
            int(
                class_id
            )
        ):

            return float(
                item[
                    "score"
                ]
            )


    raise RuntimeError(
        f"ranking에 "
        f"{class_id} 없음"
    )


# ============================================================
# 2353 ↔ 1381 delta
#
# score(2353) - score(1381)
#
# 음수:
#   2353 꺼지다 쪽
#
# 양수:
#   1381 괜찮다 쪽
# ============================================================

def off_okay_delta(
    ranking,
):

    off_score = (
        ranking_score(
            ranking,
            OFF_ID,
        )
    )


    okay_score = (
        ranking_score(
            ranking,
            OKAY_ID,
        )
    )


    return (
        float(
            off_score
            -
            okay_score
        )
    )


# ============================================================
# trajectory 요약
# ============================================================

def trajectory_summary(
    trajectory,
):

    trajectory = np.asarray(
        trajectory,
        dtype=np.float32,
    )


    if trajectory.shape != (
        80,
        2,
    ):

        raise RuntimeError(
            "Trajectory shape 오류: "
            f"{trajectory.shape}"
        )


    # 시작/끝 일부 frame 평균으로
    # 한 frame 노이즈 완화

    start = np.mean(
        trajectory[
            0:8
        ],
        axis=0,
    )


    end = np.mean(
        trajectory[
            -8:
        ],
        axis=0,
    )


    delta = (
        end
        -
        start
    )


    dx = float(
        delta[0]
    )


    dy = float(
        delta[1]
    )


    displacement = float(
        np.linalg.norm(
            delta
        )
    )


    frame_diff = np.diff(
        trajectory,
        axis=0,
    )


    path_length = float(
        np.sum(
            np.linalg.norm(
                frame_diff,
                axis=1,
            )
        )
    )


    x_range = float(
        np.max(
            trajectory[
                :,
                0
            ]
        )
        -
        np.min(
            trajectory[
                :,
                0
            ]
        )
    )


    y_range = float(
        np.max(
            trajectory[
                :,
                1
            ]
        )
        -
        np.min(
            trajectory[
                :,
                1
            ]
        )
    )


    return {
        "dx":
            dx,

        "dy":
            dy,

        "displacement":
            displacement,

        "path_length":
            path_length,

        "x_range":
            x_range,

        "y_range":
            y_range,
    }


# ============================================================
# TRAIN trajectory 통계
# ============================================================

def print_train_trajectory_stats(
    train,
):

    print()
    print("=" * 145)
    print("TRAIN TRAJECTORY SUMMARY")
    print("=" * 145)


    print(
        "※ feature[168:170]의 "
        "정규화 trajectory 기준"
    )


    for class_id in (
        ONE_HAND_IDS
    ):

        indices = np.where(
            train[
                "class_ids"
            ]
            ==
            class_id
        )[0]


        summaries = []


        for index in indices:

            trajectory = (
                train[
                    "features"
                ][
                    index,
                    :,
                    TRAJ_START:
                    TRAJ_END,
                ]
            )


            summaries.append(
                trajectory_summary(
                    trajectory
                )
            )


        dx = np.asarray(
            [
                s["dx"]
                for s in summaries
            ],
            dtype=np.float32,
        )


        dy = np.asarray(
            [
                s["dy"]
                for s in summaries
            ],
            dtype=np.float32,
        )


        disp = np.asarray(
            [
                s[
                    "displacement"
                ]
                for s in summaries
            ],
            dtype=np.float32,
        )


        path = np.asarray(
            [
                s[
                    "path_length"
                ]
                for s in summaries
            ],
            dtype=np.float32,
        )


        print()
        print(
            class_text(
                class_id
            )
        )


        print(
            f"  n          : "
            f"{len(summaries)}"
        )


        print(
            f"  dx mean    : "
            f"{np.mean(dx):+.4f}"
        )


        print(
            f"  dy mean    : "
            f"{np.mean(dy):+.4f}"
        )


        print(
            f"  displacement mean : "
            f"{np.mean(disp):.4f}"
        )


        print(
            f"  path length mean  : "
            f"{np.mean(path):.4f}"
        )


# ============================================================
# 한 live feature 분석
# ============================================================

def analyze_feature(
    feature,
    train,
    train_handshape,
):

    feature = np.asarray(
        feature,
        dtype=np.float32,
    )


    if feature.shape != (
        80,
        172,
    ):

        raise RuntimeError(
            "Live feature shape 오류: "
            f"{feature.shape}"
        )


    local = feature[
        :,
        LOCAL_START:
        LOCAL_END,
    ].copy()


    trajectory = feature[
        :,
        TRAJ_START:
        TRAJ_END,
    ].copy()


    handshape = (
        build_active_handshape(
            local
        )
    )


    train_features = (
        train[
            "features"
        ]
    )


    train_y = (
        train[
            "class_ids"
        ]
    )


    train_local = train_features[
        :,
        :,
        LOCAL_START:
        LOCAL_END,
    ]


    train_traj = train_features[
        :,
        :,
        TRAJ_START:
        TRAJ_END,
    ]


    # ========================================================
    # Local FULL
    # ========================================================

    local_full = (
        make_ranking(
            query=local,
            reference_features=(
                train_local
            ),
            reference_class_ids=(
                train_y
            ),
        )
    )


    # ========================================================
    # Local FIRST60
    # ========================================================

    local_first60 = (
        make_ranking(
            query=(
                local[
                    FIRST60_START:
                    FIRST60_END
                ]
            ),

            reference_features=(
                train_local[
                    :,
                    FIRST60_START:
                    FIRST60_END,
                    :
                ]
            ),

            reference_class_ids=(
                train_y
            ),
        )
    )


    # ========================================================
    # Local LAST40
    # ========================================================

    local_last40 = (
        make_ranking(
            query=(
                local[
                    LAST40_START:
                    LAST40_END
                ]
            ),

            reference_features=(
                train_local[
                    :,
                    LAST40_START:
                    LAST40_END,
                    :
                ]
            ),

            reference_class_ids=(
                train_y
            ),
        )
    )


    # ========================================================
    # Handshape ACTIVE20 FULL
    # ========================================================

    hs_full = (
        make_ranking(
            query=(
                handshape
            ),

            reference_features=(
                train_handshape
            ),

            reference_class_ids=(
                train_y
            ),
        )
    )


    # ========================================================
    # Handshape ACTIVE20 LAST40
    # ========================================================

    hs_last40 = (
        make_ranking(
            query=(
                handshape[
                    LAST40_START:
                    LAST40_END
                ]
            ),

            reference_features=(
                train_handshape[
                    :,
                    LAST40_START:
                    LAST40_END,
                    :
                ]
            ),

            reference_class_ids=(
                train_y
            ),
        )
    )


    # ========================================================
    # Trajectory FULL
    # ========================================================

    traj_full = (
        make_ranking(
            query=(
                trajectory
            ),

            reference_features=(
                train_traj
            ),

            reference_class_ids=(
                train_y
            ),
        )
    )


    # ========================================================
    # 결과
    # ========================================================

    return {
        "local_full":
            local_full,

        "local_first60":
            local_first60,

        "local_last40":
            local_last40,

        "hs_full":
            hs_full,

        "hs_last40":
            hs_last40,

        "traj_full":
            traj_full,

        "local_full_delta":
            off_okay_delta(
                local_full
            ),

        "local_first60_delta":
            off_okay_delta(
                local_first60
            ),

        "local_last40_delta":
            off_okay_delta(
                local_last40
            ),

        "hs_full_delta":
            off_okay_delta(
                hs_full
            ),

        "hs_last40_delta":
            off_okay_delta(
                hs_last40
            ),

        "traj_full_delta":
            off_okay_delta(
                traj_full
            ),

        "trajectory_summary":
            trajectory_summary(
                trajectory
            ),
    }


# ============================================================
# Ranking 출력
# ============================================================

def print_ranking(
    title,
    ranking,
):

    print()
    print(
        title
    )


    for rank_index, item in enumerate(
        ranking,
        start=1,
    ):

        print(
            f"  "
            f"{rank_index}. "
            f"{class_text(item['class_id']):<16}"
            f" | "
            f"{item['score']:.6f}"
        )


    print(
        f"  2353-1381 delta : "
        f"{off_okay_delta(ranking):+.6f}"
    )


    print(
        "    delta < 0 → 2353 꺼지다"
    )


    print(
        "    delta > 0 → 1381 괜찮다"
    )


# ============================================================
# 촬영
# ============================================================

def capture_trial(
    trial_number,
    true_id,
    repeat,
):

    while True:

        print()
        print("=" * 130)

        print(
            f"TRIAL "
            f"{trial_number}/"
            f"{len(TRIAL_PLAN)}"
        )

        print("=" * 130)


        print(
            "TRUE TARGET :",
            class_text(
                true_id
            ),
        )


        print(
            "REPEAT      :",
            f"{repeat}/3",
        )


        print()
        print(
            "평소처럼 자연스럽게 수어하세요."
        )


        print(
            "S → 수어 → E"
        )


        frames = (
            u.capture_sequence()
        )


        if frames is None:

            return None


        try:

            feature_info = (
                u.build_webcam_feature(
                    frames
                )
            )


        except Exception as e:

            print()
            print(
                "INVALID CAPTURE:"
            )

            print(
                e
            )


            input(
                "\nEnter를 누르면 "
                "같은 trial을 다시 촬영..."
            )


            continue


        if (
            feature_info[
                "usage_type"
            ]
            !=
            "one_hand"
        ):

            print()
            print(
                "INVALID:"
            )


            print(
                "이번 실험은 one_hand여야 하는데 "
                f"{feature_info['usage_type']}로 "
                "판정됨"
            )


            input(
                "\nEnter를 누르면 "
                "같은 trial을 다시 촬영..."
            )


            continue


        return (
            feature_info
        )


# ============================================================
# 그룹 delta 출력
# ============================================================

def print_group_delta(
    records,
    true_id,
    key,
    title,
):

    values = np.asarray(
        [
            r[
                key
            ]

            for r in records

            if (
                r[
                    "true_id"
                ]
                ==
                true_id
            )
        ],
        dtype=np.float32,
    )


    if len(values) == 0:

        return


    print(
        f"{title:<24}"
        f": "
        f"{[round(float(x), 6) for x in values]}"
        f" | mean "
        f"{np.mean(values):+.6f}"
    )


# ============================================================
# Main
# ============================================================

def main():

    print()
    print("=" * 150)

    print(
        "06z DIAGNOSE "
        "2353 OFF vs 1381 OKAY"
    )

    print("=" * 150)


    print(
        FILE_TAG
    )


    print()
    print(
        "Targets:"
    )

    print(
        "  2353 꺼지다 × 3"
    )

    print(
        "  1381 괜찮다 × 3"
    )


    print()
    print(
        "Diagnostics:"
    )

    print(
        "  Local FULL80"
    )

    print(
        "  Local FIRST60"
    )

    print(
        "  Local LAST40"
    )

    print(
        "  Handshape ACTIVE20 FULL80"
    )

    print(
        "  Handshape ACTIVE20 LAST40"
    )

    print(
        "  Trajectory FULL80"
    )


    print()
    print(
        "※ TRAIN reference만 사용"
    )

    print(
        "※ VAL / TEST 사용 없음"
    )

    print(
        "※ classifier 수정 없음"
    )

    print(
        "※ 이번에는 rescue rule을 만들지 않음"
    )


    # ========================================================
    # 준비
    # ========================================================

    check_required_files()


    train = (
        load_train_full_references()
    )


    train_handshape = (
        build_train_handshape(
            train
        )
    )


    print_train_trajectory_stats(
        train
    )


    # ========================================================
    # Live trials
    # ========================================================

    records = []


    for trial_number, plan in enumerate(
        TRIAL_PLAN,
        start=1,
    ):

        true_id = int(
            plan[
                "true_id"
            ]
        )


        repeat = int(
            plan[
                "repeat"
            ]
        )


        feature_info = (
            capture_trial(
                trial_number=(
                    trial_number
                ),

                true_id=(
                    true_id
                ),

                repeat=(
                    repeat
                ),
            )
        )


        if feature_info is None:

            print()
            print(
                "사용자가 실험을 종료했습니다."
            )

            break


        feature = np.asarray(
            feature_info[
                "feature"
            ],
            dtype=np.float32,
        )


        analysis = (
            analyze_feature(
                feature=(
                    feature
                ),

                train=(
                    train
                ),

                train_handshape=(
                    train_handshape
                ),
            )
        )


        # ====================================================
        # Trial 출력
        # ====================================================

        print()
        print("=" * 145)

        print(
            f"TRIAL {trial_number} RESULT"
        )

        print("=" * 145)


        print(
            "TRUE:",
            class_text(
                true_id
            ),
        )


        print(
            "Source mode:",
            feature_info[
                "source_mode"
            ],
        )


        print(
            "Selected:",
            feature_info[
                "selected_frames"
            ],
        )


        print(
            "Both ratio:",
            f"{feature_info['both_ratio']:.3f}",
        )


        print_ranking(
            "LOCAL FULL80",
            analysis[
                "local_full"
            ],
        )


        print_ranking(
            "LOCAL FIRST60",
            analysis[
                "local_first60"
            ],
        )


        print_ranking(
            "LOCAL LAST40",
            analysis[
                "local_last40"
            ],
        )


        print_ranking(
            "HANDSHAPE ACTIVE20 FULL80",
            analysis[
                "hs_full"
            ],
        )


        print_ranking(
            "HANDSHAPE ACTIVE20 LAST40",
            analysis[
                "hs_last40"
            ],
        )


        print_ranking(
            "TRAJECTORY FULL80",
            analysis[
                "traj_full"
            ],
        )


        t = (
            analysis[
                "trajectory_summary"
            ]
        )


        print()
        print(
            "TRAJECTORY MOTION:"
        )


        print(
            f"  dx           : "
            f"{t['dx']:+.6f}"
        )


        print(
            f"  dy           : "
            f"{t['dy']:+.6f}"
        )


        print(
            f"  displacement : "
            f"{t['displacement']:.6f}"
        )


        print(
            f"  path length  : "
            f"{t['path_length']:.6f}"
        )


        print(
            f"  x range      : "
            f"{t['x_range']:.6f}"
        )


        print(
            f"  y range      : "
            f"{t['y_range']:.6f}"
        )


        # ====================================================
        # 저장 record
        # ====================================================

        record = {
            "trial":
                int(
                    trial_number
                ),

            "true_id":
                int(
                    true_id
                ),

            "repeat":
                int(
                    repeat
                ),

            "feature":
                feature,

            "source_mode":
                str(
                    feature_info[
                        "source_mode"
                    ]
                ),

            "selected_frames":
                int(
                    feature_info[
                        "selected_frames"
                    ]
                ),

            "both_ratio":
                float(
                    feature_info[
                        "both_ratio"
                    ]
                ),

            "local_full_pred":
                int(
                    analysis[
                        "local_full"
                    ][0][
                        "class_id"
                    ]
                ),

            "local_first60_pred":
                int(
                    analysis[
                        "local_first60"
                    ][0][
                        "class_id"
                    ]
                ),

            "local_last40_pred":
                int(
                    analysis[
                        "local_last40"
                    ][0][
                        "class_id"
                    ]
                ),

            "hs_full_pred":
                int(
                    analysis[
                        "hs_full"
                    ][0][
                        "class_id"
                    ]
                ),

            "hs_last40_pred":
                int(
                    analysis[
                        "hs_last40"
                    ][0][
                        "class_id"
                    ]
                ),

            "traj_full_pred":
                int(
                    analysis[
                        "traj_full"
                    ][0][
                        "class_id"
                    ]
                ),

            "local_full_delta":
                float(
                    analysis[
                        "local_full_delta"
                    ]
                ),

            "local_first60_delta":
                float(
                    analysis[
                        "local_first60_delta"
                    ]
                ),

            "local_last40_delta":
                float(
                    analysis[
                        "local_last40_delta"
                    ]
                ),

            "hs_full_delta":
                float(
                    analysis[
                        "hs_full_delta"
                    ]
                ),

            "hs_last40_delta":
                float(
                    analysis[
                        "hs_last40_delta"
                    ]
                ),

            "traj_full_delta":
                float(
                    analysis[
                        "traj_full_delta"
                    ]
                ),

            "dx":
                float(
                    t[
                        "dx"
                    ]
                ),

            "dy":
                float(
                    t[
                        "dy"
                    ]
                ),

            "displacement":
                float(
                    t[
                        "displacement"
                    ]
                ),

            "path_length":
                float(
                    t[
                        "path_length"
                    ]
                ),

            "x_range":
                float(
                    t[
                        "x_range"
                    ]
                ),

            "y_range":
                float(
                    t[
                        "y_range"
                    ]
                ),
        }


        records.append(
            record
        )


        if (
            trial_number
            <
            len(
                TRIAL_PLAN
            )
        ):

            input(
                "\nEnter를 누르면 "
                "다음 trial로 진행..."
            )


    # ========================================================
    # 완료된 trial 체크
    # ========================================================

    if not records:

        print(
            "저장할 trial 없음"
        )

        return


    # ========================================================
    # 전체 Summary
    # ========================================================

    print()
    print("=" * 220)

    print(
        "06z DIAGNOSTIC SUMMARY"
    )

    print("=" * 220)


    print(
        f"{'TRIAL':<7}"
        f"{'TRUE':<17}"
        f"{'LOCAL':<17}"
        f"{'FIRST60':<17}"
        f"{'LAST40':<17}"
        f"{'HS FULL':<17}"
        f"{'HS LAST40':<17}"
        f"{'TRAJ':<17}"
        f"{'DX':>10}"
        f"{'DY':>10}"
        f"{'PATH':>10}"
    )


    print("-" * 220)


    for r in records:

        print(
            f"{r['trial']:<7}"
            f"{class_text(r['true_id']):<17}"
            f"{class_text(r['local_full_pred']):<17}"
            f"{class_text(r['local_first60_pred']):<17}"
            f"{class_text(r['local_last40_pred']):<17}"
            f"{class_text(r['hs_full_pred']):<17}"
            f"{class_text(r['hs_last40_pred']):<17}"
            f"{class_text(r['traj_full_pred']):<17}"
            f"{r['dx']:>+10.4f}"
            f"{r['dy']:>+10.4f}"
            f"{r['path_length']:>10.4f}"
        )


    # ========================================================
    # Delta 분포
    # ========================================================

    print()
    print("=" * 160)

    print(
        "06z 2353 - 1381 DELTA DISTRIBUTION"
    )

    print("=" * 160)


    print(
        "해석:"
    )

    print(
        "  delta < 0 → 2353 꺼지다"
    )

    print(
        "  delta > 0 → 1381 괜찮다"
    )


    for true_id in [
        OFF_ID,
        OKAY_ID,
    ]:

        print()
        print("-" * 120)

        print(
            class_text(
                true_id
            )
        )

        print("-" * 120)


        print_group_delta(
            records,
            true_id,
            "local_full_delta",
            "Local FULL80",
        )


        print_group_delta(
            records,
            true_id,
            "local_first60_delta",
            "Local FIRST60",
        )


        print_group_delta(
            records,
            true_id,
            "local_last40_delta",
            "Local LAST40",
        )


        print_group_delta(
            records,
            true_id,
            "hs_full_delta",
            "Handshape FULL",
        )


        print_group_delta(
            records,
            true_id,
            "hs_last40_delta",
            "Handshape LAST40",
        )


        print_group_delta(
            records,
            true_id,
            "traj_full_delta",
            "Trajectory FULL",
        )


    # ========================================================
    # 저장
    # ========================================================

    features = np.stack(
        [
            r[
                "feature"
            ]

            for r in records
        ],
        axis=0,
    ).astype(
        np.float32
    )


    np.savez_compressed(
        SAVE_PATH,

        features=(
            features
        ),

        trial_ids=np.asarray(
            [
                r["trial"]
                for r in records
            ],
            dtype=np.int64,
        ),

        true_class_ids=np.asarray(
            [
                r["true_id"]
                for r in records
            ],
            dtype=np.int64,
        ),

        repeat_ids=np.asarray(
            [
                r["repeat"]
                for r in records
            ],
            dtype=np.int64,
        ),

        source_modes=np.asarray(
            [
                r["source_mode"]
                for r in records
            ]
        ),

        selected_frames=np.asarray(
            [
                r["selected_frames"]
                for r in records
            ],
            dtype=np.int64,
        ),

        both_ratios=np.asarray(
            [
                r["both_ratio"]
                for r in records
            ],
            dtype=np.float32,
        ),

        local_full_preds=np.asarray(
            [
                r["local_full_pred"]
                for r in records
            ],
            dtype=np.int64,
        ),

        local_first60_preds=np.asarray(
            [
                r["local_first60_pred"]
                for r in records
            ],
            dtype=np.int64,
        ),

        local_last40_preds=np.asarray(
            [
                r["local_last40_pred"]
                for r in records
            ],
            dtype=np.int64,
        ),

        hs_full_preds=np.asarray(
            [
                r["hs_full_pred"]
                for r in records
            ],
            dtype=np.int64,
        ),

        hs_last40_preds=np.asarray(
            [
                r["hs_last40_pred"]
                for r in records
            ],
            dtype=np.int64,
        ),

        traj_full_preds=np.asarray(
            [
                r["traj_full_pred"]
                for r in records
            ],
            dtype=np.int64,
        ),

        local_full_deltas=np.asarray(
            [
                r["local_full_delta"]
                for r in records
            ],
            dtype=np.float32,
        ),

        local_first60_deltas=np.asarray(
            [
                r["local_first60_delta"]
                for r in records
            ],
            dtype=np.float32,
        ),

        local_last40_deltas=np.asarray(
            [
                r["local_last40_delta"]
                for r in records
            ],
            dtype=np.float32,
        ),

        hs_full_deltas=np.asarray(
            [
                r["hs_full_delta"]
                for r in records
            ],
            dtype=np.float32,
        ),

        hs_last40_deltas=np.asarray(
            [
                r["hs_last40_delta"]
                for r in records
            ],
            dtype=np.float32,
        ),

        traj_full_deltas=np.asarray(
            [
                r["traj_full_delta"]
                for r in records
            ],
            dtype=np.float32,
        ),

        dx=np.asarray(
            [
                r["dx"]
                for r in records
            ],
            dtype=np.float32,
        ),

        dy=np.asarray(
            [
                r["dy"]
                for r in records
            ],
            dtype=np.float32,
        ),

        displacement=np.asarray(
            [
                r["displacement"]
                for r in records
            ],
            dtype=np.float32,
        ),

        path_length=np.asarray(
            [
                r["path_length"]
                for r in records
            ],
            dtype=np.float32,
        ),

        x_range=np.asarray(
            [
                r["x_range"]
                for r in records
            ],
            dtype=np.float32,
        ),

        y_range=np.asarray(
            [
                r["y_range"]
                for r in records
            ],
            dtype=np.float32,
        ),
    )


    # ========================================================
    # 완료
    # ========================================================

    print()
    print("=" * 160)

    print(
        "06z COMPLETE"
    )

    print("=" * 160)


    print(
        "Valid trials:",
        len(
            records
        ),
        "/",
        len(
            TRIAL_PLAN
        ),
    )


    print()
    print(
        "Saved:"
    )

    print(
        SAVE_PATH
    )


    print()
    print(
        "다음 판단:"
    )


    print(
        "  1. Local FULL만 "
        "2353을 놓치는지"
    )


    print(
        "  2. FIRST60 / LAST40 중 "
        "어느 구간이 더 잘 분리되는지"
    )


    print(
        "  3. Handshape가 "
        "2353↔1381을 분리하는지"
    )


    print(
        "  4. Trajectory가 "
        "둘을 분리하는지"
    )


    print(
        "  5. dx/dy/path에서 "
        "두 수어의 이동 패턴이 "
        "다르게 나타나는지"
    )


    print()
    print(
        "※ 결과를 본 뒤에만 "
        "rescue 여부를 결정합니다."
    )


    print(
        "※ TEST 사용 없음"
    )

    print("=" * 160)


if __name__ == "__main__":
    main()