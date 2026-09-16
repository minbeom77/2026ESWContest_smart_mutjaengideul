import os
import hashlib
import importlib.util

import numpy as np


# ============================================================
# 파일 정보
# ============================================================

FILE_TAG = "[15-CLASS EXPANSION / ONE-HAND6 + TWO-HAND9 + TEMP OVERLAP RESCUE]"


# ============================================================
# 클래스
# ============================================================

AIRCON_ID = 0       # 0128 에어컨
LOCK_ID = 1         # 0527 문잠그다
OFF_ID = 2          # 2353 꺼지다
HOT_ID = 3          # 1382 덥다
COLD_ID = 4         # 1248 춥다
RESCUE_ID = 5       # 1588 구조
SMOKE_ID = 6        # 1570 연기
HURT_ID = 7         # 1152 아프다
OKAY_ID = 8         # 1381 괜찮다
THANKS_ID = 9       # 1290 감사

LIGHT_ON_ID = 10    # 2403 점등
LIGHT_OFF_ID = 11   # 2404 소등
TEMP_ID = 12        # 2563 온도
HUNGRY_ID = 13      # 0953 배고프다
THIRSTY_ID = 14     # 2036 목마르다


CLASS_INFO = {
    AIRCON_ID: {
        "word_code": "0128",
        "label": "에어컨",
    },

    LOCK_ID: {
        "word_code": "0527",
        "label": "문잠그다",
    },

    OFF_ID: {
        "word_code": "2353",
        "label": "꺼지다",
    },

    HOT_ID: {
        "word_code": "1382",
        "label": "덥다",
    },

    COLD_ID: {
        "word_code": "1248",
        "label": "춥다",
    },

    RESCUE_ID: {
        "word_code": "1588",
        "label": "구조",
    },

    SMOKE_ID: {
        "word_code": "1570",
        "label": "연기",
    },

    HURT_ID: {
        "word_code": "1152",
        "label": "아프다",
    },

    OKAY_ID: {
        "word_code": "1381",
        "label": "괜찮다",
    },

    THANKS_ID: {
        "word_code": "1290",
        "label": "감사",
    },

    LIGHT_ON_ID: {
        "word_code": "2403",
        "label": "점등",
    },

    LIGHT_OFF_ID: {
        "word_code": "2404",
        "label": "소등",
    },

    TEMP_ID: {
        "word_code": "2563",
        "label": "온도",
    },

    HUNGRY_ID: {
        "word_code": "0953",
        "label": "배고프다",
    },

    THIRSTY_ID: {
        "word_code": "2036",
        "label": "목마르다",
    },
}


# ============================================================
# ONE-HAND 후보
#
# 중요:
# 감사가 MediaPipe에서 RIGHT_ONLY로 들어오는 경우를
# 여기서 fallback 처리한다.
# ============================================================

ONE_HAND_IDS = [
    OFF_ID,
    HURT_ID,
    OKAY_ID,
    LIGHT_ON_ID,
    LIGHT_OFF_ID,
    HUNGRY_ID,
]


# ============================================================
# TWO-HAND 후보
#
# 감사가 정상적으로 양손 검출되는 경우에는
# 기존대로 여기서 처리한다.
# ============================================================

TWO_HAND_IDS = [
    AIRCON_ID,
    LOCK_ID,
    HOT_ID,
    COLD_ID,
    RESCUE_ID,
    SMOKE_ID,
    THANKS_ID,
    TEMP_ID,
    THIRSTY_ID,
]


# ============================================================
# HOT rescue trigger
# ============================================================

HOT_TRIGGER_BASE_IDS = {
    AIRCON_ID,
    LOCK_ID,
    COLD_ID,
}


# ============================================================
# 에어컨 / 춥다
# ============================================================

AC_COLD_IDS = {
    AIRCON_ID,
    COLD_ID,
}


# ============================================================
# 꺼지다 / 아프다 MID40 tiebreak
#
# 개발 진단:
# - 2353 blind 20개: FULL80 12/20 -> proposed 20/20
# - 1152 blind 20개: BASE 20/20, MID40 자체도 20/20 1152 유지
#
# 규칙:
# BASE Top-2가 정확히 {2353, 1152}일 때만
# MID40(frame 20:60) pairwise K3로 최종 결정
# ============================================================

OFF_HURT_IDS = {
    OFF_ID,
    HURT_ID,
}

OFF_HURT_MID_START = 20
OFF_HURT_MID_END = 60


# ============================================================
# Feature 설정
# ============================================================

TARGET_FRAMES = 80

FULL_DIM = 172
LOCAL_DIM = 84

SLOT_DIM = 42

HANDSHAPE_ONE_DIM = 20
HANDSHAPE_TWO_DIM = 40


# ============================================================
# Template classifier
# ============================================================

K = 3


# ============================================================
# Frozen C4 SIGN vs NO-SIGN gate
#
# 06ce에서 동결되고 06ch / 06ci에서 독립 fresh 검증 완료.
#
# Representation:
#   C4_MOTION_LOCAL230
#
# Classifier:
#   class-balanced K3 mean Euclidean distance
#
# Decision:
#   dSIGN <= dNO-SIGN -> SIGN
#   dSIGN >  dNO-SIGN -> NO-SIGN
#
# Threshold:
#   NONE
# ============================================================

C4_CANDIDATE_NAME = "C4_MOTION_LOCAL230"
C4_FEATURE_DIM = 230
C4_K = 3

C4_SIGN_LABEL = 1
C4_NOSIGN_LABEL = 0

C4_EXPECTED_SIGN_REFERENCES = 288
C4_EXPECTED_NOSIGN_REFERENCES = 308

C4_EXPECTED_SHA256 = (
    "fe988edce990a87652dcdb7f36522ca1e6459567eac689d63944454be6d1950a"
)


# ============================================================
# 기존 검증된 HOT rescue threshold
# ============================================================

HOT_RESCUE_THRESHOLD = -0.10


# ============================================================
# 에어컨 / 춥다 temporal 구간
# ============================================================

LAST40_START = 40
LAST40_END = 80


# ============================================================
# 경로
# ============================================================

BASE_DIR = os.path.dirname(
    os.path.abspath(__file__)
)


# ------------------------------------------------------------
# Webcam capture + Feature V3
# ------------------------------------------------------------

RUNTIME_06U_PATH = os.path.join(
    BASE_DIR,
    "06u_webcam_combined_hierarchy.py",
)


# ------------------------------------------------------------
# TRAIN full172 reconstruction
# + handshape helper
# ------------------------------------------------------------

DIAG_06Z_PATH = os.path.join(
    BASE_DIR,
    "06z_diagnose_off_okay_onehand.py",
)


# ------------------------------------------------------------
# 검증 끝난 ONE-HAND 4-class calibration
#
# 2353 ×7
# 1152 ×7
# 1381 ×7
# 1290 ×7
# = 28
# ------------------------------------------------------------

ONEHAND_CALIBRATION_PATH = os.path.join(
    BASE_DIR,
    "template_runtime_v3",
    "07f_onehand6_webcam_calibration_42.npz",
)


# ------------------------------------------------------------
# Frozen C4 artifact
# ------------------------------------------------------------

C4_FROZEN_PATH = os.path.join(
    BASE_DIR,
    "diagnostics_v3",
    "07e_expanded_onehand7_sign_nosign_c4_model.npz",
)


# ------------------------------------------------------------
# Exact C4 representation builder used in development/fresh
# ------------------------------------------------------------

DIAG_06CD_PATH = os.path.join(
    BASE_DIR,
    "06cd_evaluate_onehand_sign_nosign_knn_dev.py",
)


# ============================================================
# Dynamic import
# ============================================================

def import_module_from_path(
    module_name,
    path,
):

    if not os.path.exists(path):

        raise FileNotFoundError(
            f"필수 파일이 없습니다:\n{path}"
        )


    spec = importlib.util.spec_from_file_location(
        module_name,
        path,
    )


    if (
        spec is None
        or
        spec.loader is None
    ):

        raise RuntimeError(
            f"모듈 import 실패:\n{path}"
        )


    module = importlib.util.module_from_spec(
        spec
    )


    spec.loader.exec_module(
        module
    )


    return module


# ============================================================
# Helpers import
# ============================================================

u = import_module_from_path(
    "runtime06u",
    RUNTIME_06U_PATH,
)


z = import_module_from_path(
    "diag06z",
    DIAG_06Z_PATH,
)


cd = import_module_from_path(
    "diag06cd",
    DIAG_06CD_PATH,
)


# ============================================================
# 표시
# ============================================================

def class_text(
    class_id,
):

    info = CLASS_INFO[
        int(class_id)
    ]


    return (
        f"{info['word_code']} "
        f"{info['label']}"
    )


# ============================================================
# RMSE
# ============================================================

def rmse_distances(
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


    return np.sqrt(
        np.mean(
            diff ** 2,
            axis=axes,
        )
    )


# ============================================================
# 클래스별 K nearest mean
# ============================================================

def get_class_score(
    query,
    references,
    reference_y,
    class_id,
    k=K,
):

    class_id = int(
        class_id
    )


    indices = np.where(
        reference_y
        ==
        class_id
    )[0]


    if len(indices) < k:

        raise RuntimeError(
            f"{class_text(class_id)} "
            f"reference 부족: "
            f"{len(indices)} < K={k}"
        )


    distances = rmse_distances(
        query=query,
        references=references[
            indices
        ],
    )


    order = np.argsort(
        distances
    )


    selected = distances[
        order[
            :k
        ]
    ]


    nearest_indices = indices[
        order[
            :k
        ]
    ]


    return {
        "class_id":
            class_id,

        "score":
            float(
                np.mean(
                    selected
                )
            ),

        "nearest_indices":
            nearest_indices,

        "nearest_distances":
            selected,
    }


# ============================================================
# Ranking
# ============================================================

def rank_classes(
    query,
    references,
    reference_y,
    candidate_ids,
    k=K,
):

    ranking = []


    for class_id in candidate_ids:

        ranking.append(
            get_class_score(
                query=query,
                references=references,
                reference_y=reference_y,
                class_id=class_id,
                k=k,
            )
        )


    ranking.sort(
        key=lambda x:
        x[
            "score"
        ]
    )


    return ranking


# ============================================================
# 특정 class score 찾기
# ============================================================

def score_from_ranking(
    ranking,
    class_id,
):

    class_id = int(
        class_id
    )


    for item in ranking:

        if (
            int(
                item[
                    "class_id"
                ]
            )
            ==
            class_id
        ):

            return float(
                item[
                    "score"
                ]
            )


    raise RuntimeError(
        f"Ranking에서 "
        f"{class_text(class_id)} "
        f"score를 찾지 못함"
    )


# ============================================================
# Ranking margin
#
# 2등 - 1등
#
# 현재 no-sign rejection에는 사용하지 않는다.
# ============================================================

def ranking_margin(
    ranking,
):

    if len(ranking) < 2:

        return 0.0


    return float(
        ranking[
            1
        ][
            "score"
        ]
        -
        ranking[
            0
        ][
            "score"
        ]
    )


# ============================================================
# Handshape20
#
# 기존 06z helper 그대로 사용
# ============================================================

def build_handshape20_from_local84(
    local84,
):

    local84 = np.asarray(
        local84,
        dtype=np.float32,
    )


    if (
        local84.ndim != 2
        or
        local84.shape[1]
        !=
        LOCAL_DIM
    ):

        raise RuntimeError(
            "Handshape20 입력 오류: "
            f"{local84.shape}"
        )


    hs = z.build_active_handshape(
        local84
    )


    hs = np.asarray(
        hs,
        dtype=np.float32,
    )


    if hs.shape != (
        local84.shape[0],
        HANDSHAPE_ONE_DIM,
    ):

        raise RuntimeError(
            "Handshape20 출력 오류: "
            f"{hs.shape}"
        )


    return hs


# ============================================================
# Two-hand Handshape40
#
# slot A 42
# slot B 42
#
# 각각 Handshape20 생성 후 연결
# ============================================================

def build_twohand_handshape40(
    local84,
):

    local84 = np.asarray(
        local84,
        dtype=np.float32,
    )


    if (
        local84.ndim != 2
        or
        local84.shape[1]
        !=
        LOCAL_DIM
    ):

        raise RuntimeError(
            "Two-hand Local 입력 오류: "
            f"{local84.shape}"
        )


    frames = local84.shape[
        0
    ]


    # ========================================================
    # SLOT A
    # ========================================================

    a_only = np.zeros(
        (
            frames,
            LOCAL_DIM,
        ),
        dtype=np.float32,
    )


    a_only[
        :,
        0:SLOT_DIM
    ] = local84[
        :,
        0:SLOT_DIM
    ]


    hs_a = build_handshape20_from_local84(
        a_only
    )


    # ========================================================
    # SLOT B
    # ========================================================

    b_only = np.zeros(
        (
            frames,
            LOCAL_DIM,
        ),
        dtype=np.float32,
    )


    b_only[
        :,
        0:SLOT_DIM
    ] = local84[
        :,
        SLOT_DIM:
        LOCAL_DIM
    ]


    hs_b = build_handshape20_from_local84(
        b_only
    )


    # ========================================================
    # 20 + 20 = 40
    # ========================================================

    hs40 = np.concatenate(
        [
            hs_a,
            hs_b,
        ],
        axis=1,
    ).astype(
        np.float32
    )


    if hs40.shape != (
        frames,
        HANDSHAPE_TWO_DIM,
    ):

        raise RuntimeError(
            "Handshape40 shape 오류: "
            f"{hs40.shape}"
        )


    return hs40


# ============================================================
# 전체 reference Handshape40
# ============================================================

def build_twohand_handshape40_set(
    local_features,
):

    output = []


    for local in local_features:

        output.append(
            build_twohand_handshape40(
                local
            )
        )


    return np.stack(
        output,
        axis=0,
    ).astype(
        np.float32
    )


# ============================================================
# AIHub TRAIN reference
#
# Two-hand branch에서만 사용
# ============================================================

def load_aihub_train_references():

    print()
    print("=" * 120)

    print(
        "AIHUB TRAIN REFERENCES"
    )

    print("=" * 120)


    train = (
        z.load_train_full_references()
    )


    full = np.asarray(
        train[
            "features"
        ],
        dtype=np.float32,
    )


    class_ids = np.asarray(
        train[
            "class_ids"
        ],
        dtype=np.int64,
    )


    if (
        full.ndim != 3
        or
        full.shape[1:]
        !=
        (
            TARGET_FRAMES,
            FULL_DIM,
        )
    ):

        raise RuntimeError(
            "AIHub TRAIN shape 오류: "
            f"{full.shape}"
        )


    if len(full) != len(
        class_ids
    ):

        raise RuntimeError(
            "AIHub feature / class "
            "개수 불일치"
        )


    if not np.all(
        np.isfinite(
            full
        )
    ):

        raise RuntimeError(
            "AIHub TRAIN NaN / Inf"
        )



    # ========================================================
    # 신규 5-class TRAIN 중 TWO-HAND 2개 추가
    #
    # 12 = 2563 온도
    # 14 = 2036 목마르다
    # ========================================================

    new5_train_path = os.path.join(
        BASE_DIR,
        "new5_reference_v3",
        "new5_train_v3_80f.npz",
    )

    if not os.path.exists(
        new5_train_path
    ):

        raise FileNotFoundError(
            "신규 5-class TRAIN reference 없음:\n"
            f"{new5_train_path}"
        )


    new5 = np.load(
        new5_train_path,
        allow_pickle=False,
    )


    required_new5 = {
        "features",
        "class_ids",
        "usage_types",
    }


    missing_new5 = (
        required_new5
        -
        set(
            new5.files
        )
    )


    if missing_new5:

        raise RuntimeError(
            "new5 TRAIN key 부족: "
            f"{missing_new5}"
        )


    new5_full = np.asarray(
        new5[
            "features"
        ],
        dtype=np.float32,
    )


    new5_class_ids = np.asarray(
        new5[
            "class_ids"
        ],
        dtype=np.int64,
    )


    new5_usage_types = np.asarray(
        new5[
            "usage_types"
        ]
    ).astype(str)


    if (
        new5_full.ndim != 3
        or
        new5_full.shape[1:]
        !=
        (
            TARGET_FRAMES,
            FULL_DIM,
        )
    ):

        raise RuntimeError(
            "new5 TRAIN shape 오류: "
            f"{new5_full.shape}"
        )


    if (
        len(new5_full)
        !=
        len(new5_class_ids)
        or
        len(new5_full)
        !=
        len(new5_usage_types)
    ):

        raise RuntimeError(
            "new5 TRAIN 배열 개수 불일치"
        )


    if not np.all(
        np.isfinite(
            new5_full
        )
    ):

        raise RuntimeError(
            "new5 TRAIN NaN / Inf"
        )


    new_twohand_mask = (
        (
            new5_class_ids
            ==
            TEMP_ID
        )
        |
        (
            new5_class_ids
            ==
            THIRSTY_ID
        )
    ) & (
        new5_usage_types
        ==
        "two_hand"
    )


    new_twohand_full = (
        new5_full[
            new_twohand_mask
        ]
    )


    new_twohand_class_ids = (
        new5_class_ids[
            new_twohand_mask
        ]
    )


    temp_count = int(
        np.sum(
            new_twohand_class_ids
            ==
            TEMP_ID
        )
    )


    thirsty_count = int(
        np.sum(
            new_twohand_class_ids
            ==
            THIRSTY_ID
        )
    )


    if temp_count != 6:

        raise RuntimeError(
            "2563 온도 TRAIN 개수 오류: "
            f"{temp_count}"
        )


    if thirsty_count != 6:

        raise RuntimeError(
            "2036 목마르다 TRAIN 개수 오류: "
            f"{thirsty_count}"
        )


    if len(
        new_twohand_full
    ) != 12:

        raise RuntimeError(
            "신규 TWO-HAND TRAIN 총 개수 오류: "
            f"{len(new_twohand_full)}"
        )


    if np.any(
        class_ids
        ==
        TEMP_ID
    ):

        raise RuntimeError(
            "기존 TRAIN에 이미 온도 class 존재"
        )


    if np.any(
        class_ids
        ==
        THIRSTY_ID
    ):

        raise RuntimeError(
            "기존 TRAIN에 이미 목마르다 class 존재"
        )


    print(
        "Original TRAIN:",
        full.shape,
    )


    full = np.concatenate(
        [
            full,
            new_twohand_full,
        ],
        axis=0,
    )


    class_ids = np.concatenate(
        [
            class_ids,
            new_twohand_class_ids,
        ],
        axis=0,
    )


    print(
        "Expanded TRAIN:",
        full.shape,
    )


    local = full[
        :,
        :,
        0:LOCAL_DIM,
    ].copy()


    print(
        "Full  :",
        full.shape,
    )


    print(
        "Local :",
        local.shape,
    )


    print()
    print(
        "TRAIN distribution:"
    )


    for class_id in sorted(
        np.unique(
            class_ids
        ).tolist()
    ):

        count = int(
            np.sum(
                class_ids
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


    print()
    print(
        "Building AIHub "
        "two-hand Handshape40..."
    )


    handshape40 = (
        build_twohand_handshape40_set(
            local
        )
    )


    print(
        "Handshape40:",
        handshape40.shape,
    )


    print(
        "AIHub reference load: PASS"
    )


    return {
        "full":
            full,

        "local":
            local,

        "handshape40":
            handshape40,

        "class_ids":
            class_ids,
    }


# ============================================================
# One-hand 7-class Webcam calibration
#
# 06am:
#
# 2353 ×7
# 1152 ×7
# 1381 ×7
# 1290 ×7
#
# total 28
# ============================================================

def load_onehand_calibration():

    print()
    print("=" * 120)

    print(
        "ONE-HAND 6-CLASS "
        "WEBCAM CALIBRATION"
    )

    print("=" * 120)


    if not os.path.exists(
        ONEHAND_CALIBRATION_PATH
    ):

        raise FileNotFoundError(
            "07f calibration 없음:\n"
            f"{ONEHAND_CALIBRATION_PATH}"
        )


    data = np.load(
        ONEHAND_CALIBRATION_PATH,
        allow_pickle=True,
    )


    required = {
        "features",
        "class_ids",
    }


    missing = (
        required
        -
        set(data.files)
    )


    if missing:

        raise RuntimeError(
            f"07c key 부족: "
            f"{missing}"
        )


    full = np.asarray(
        data[
            "features"
        ],
        dtype=np.float32,
    )


    class_ids = np.asarray(
        data[
            "class_ids"
        ],
        dtype=np.int64,
    )


    if full.shape != (
        42,
        TARGET_FRAMES,
        FULL_DIM,
    ):

        raise RuntimeError(
            "07f calibration shape 오류: "
            f"{full.shape}"
        )


    if class_ids.shape != (
        42,
    ):

        raise RuntimeError(
            "07c class_ids 오류: "
            f"{class_ids.shape}"
        )


    if not np.all(
        np.isfinite(
            full
        )
    ):

        raise RuntimeError(
            "07f calibration NaN / Inf"
        )


    local = full[
        :,
        :,
        0:LOCAL_DIM,
    ].copy()


    print(
        "Full  :",
        full.shape,
    )


    print(
        "Local :",
        local.shape,
    )


    print()
    print(
        "Distribution:"
    )


    for class_id in ONE_HAND_IDS:

        count = int(
            np.sum(
                class_ids
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


        if count != 7:

            raise RuntimeError(
                f"{class_text(class_id)} "
                f"calibration 수 오류: "
                f"{count}"
            )


    unexpected = (
        set(
            class_ids.tolist()
        )
        -
        set(
            ONE_HAND_IDS
        )
    )


    if unexpected:

        raise RuntimeError(
            "06am calibration에 "
            "예상하지 못한 class 존재: "
            f"{unexpected}"
        )


    print()
    print(
        "One-hand 6-class "
        "calibration load: PASS"
    )


    return {
        "full":
            full,

        "local":
            local,

        "class_ids":
            class_ids,
    }


# ============================================================
# Frozen C4 hash helper
# ============================================================

def sha256_array(
    hasher,
    name,
    array,
):

    array = np.asarray(
        array
    )


    array = np.ascontiguousarray(
        array
    )


    hasher.update(
        name.encode(
            "utf-8"
        )
    )


    hasher.update(
        str(
            array.shape
        ).encode(
            "utf-8"
        )
    )


    hasher.update(
        str(
            array.dtype
        ).encode(
            "utf-8"
        )
    )


    hasher.update(
        array.tobytes()
    )


def rebuild_c4_hash(
    candidate_name,
    k,
    mean,
    std,
    sign_reference,
    nosign_reference,
):

    h = hashlib.sha256()


    h.update(
        str(
            candidate_name
        ).encode(
            "utf-8"
        )
    )


    h.update(
        str(
            int(k)
        ).encode(
            "utf-8"
        )
    )


    sha256_array(
        h,
        "mean",
        mean,
    )


    sha256_array(
        h,
        "std",
        std,
    )


    sha256_array(
        h,
        "sign_reference",
        sign_reference,
    )


    sha256_array(
        h,
        "nosign_reference",
        nosign_reference,
    )


    return h.hexdigest()


# ============================================================
# Frozen C4 model load
# ============================================================

def load_frozen_c4_gate():

    print()
    print("=" * 120)

    print(
        "FROZEN C4 SIGN / NO-SIGN GATE"
    )

    print("=" * 120)


    if not os.path.exists(
        C4_FROZEN_PATH
    ):

        raise FileNotFoundError(
            "Frozen C4 artifact 없음:\n"
            f"{C4_FROZEN_PATH}"
        )


    if not hasattr(
        cd,
        "build_representations",
    ):

        raise RuntimeError(
            "06cd.build_representations 없음"
        )


    data = np.load(
        C4_FROZEN_PATH,
        allow_pickle=True,
    )


    required = {
        "candidate_name",
        "feature_dim",
        "knn_k",
        "feature_mean",
        "feature_std",
        "sign_reference_z",
        "nosign_reference_z",
        "frozen_model_sha256",
        "frozen_status",
    }


    missing = (
        required
        -
        set(
            data.files
        )
    )


    if missing:

        raise RuntimeError(
            "Frozen C4 key 부족: "
            f"{sorted(missing)}"
        )


    candidate = str(
        np.asarray(
            data[
                "candidate_name"
            ]
        ).reshape(-1)[0]
    )


    feature_dim = int(
        np.asarray(
            data[
                "feature_dim"
            ]
        ).reshape(-1)[0]
    )


    k = int(
        np.asarray(
            data[
                "knn_k"
            ]
        ).reshape(-1)[0]
    )


    mean = np.asarray(
        data[
            "feature_mean"
        ],
        dtype=np.float32,
    )


    std = np.asarray(
        data[
            "feature_std"
        ],
        dtype=np.float32,
    )


    sign_reference = np.asarray(
        data[
            "sign_reference_z"
        ],
        dtype=np.float32,
    )


    nosign_reference = np.asarray(
        data[
            "nosign_reference_z"
        ],
        dtype=np.float32,
    )


    stored_sha = str(
        np.asarray(
            data[
                "frozen_model_sha256"
            ]
        ).reshape(-1)[0]
    )


    frozen_status = str(
        np.asarray(
            data[
                "frozen_status"
            ]
        ).reshape(-1)[0]
    )


    rebuilt_sha = rebuild_c4_hash(
        candidate_name=candidate,
        k=k,
        mean=mean,
        std=std,
        sign_reference=sign_reference,
        nosign_reference=nosign_reference,
    )


    print(
        "Candidate :",
        candidate,
    )


    print(
        "Feature   :",
        feature_dim,
    )


    print(
        "K         :",
        k,
    )


    print(
        "Threshold : NONE"
    )


    print(
        "SIGN refs :",
        sign_reference.shape,
    )


    print(
        "NO refs   :",
        nosign_reference.shape,
    )


    print(
        "SHA256    :",
        stored_sha,
    )


    if candidate != C4_CANDIDATE_NAME:

        raise RuntimeError(
            "Frozen C4 candidate mismatch"
        )


    if feature_dim != C4_FEATURE_DIM:

        raise RuntimeError(
            "Frozen C4 feature dimension mismatch"
        )


    if k != C4_K:

        raise RuntimeError(
            "Frozen C4 K mismatch"
        )


    if mean.shape != (
        C4_FEATURE_DIM,
    ):

        raise RuntimeError(
            f"Frozen C4 mean shape 오류: {mean.shape}"
        )


    if std.shape != (
        C4_FEATURE_DIM,
    ):

        raise RuntimeError(
            f"Frozen C4 std shape 오류: {std.shape}"
        )


    if sign_reference.shape != (
        C4_EXPECTED_SIGN_REFERENCES,
        C4_FEATURE_DIM,
    ):

        raise RuntimeError(
            "Frozen C4 SIGN reference shape 오류"
        )


    if nosign_reference.shape != (
        C4_EXPECTED_NOSIGN_REFERENCES,
        C4_FEATURE_DIM,
    ):

        raise RuntimeError(
            "Frozen C4 NO-SIGN reference shape 오류"
        )


    if not (
        np.all(
            np.isfinite(
                mean
            )
        )
        and
        np.all(
            np.isfinite(
                std
            )
        )
        and
        np.all(
            np.isfinite(
                sign_reference
            )
        )
        and
        np.all(
            np.isfinite(
                nosign_reference
            )
        )
    ):

        raise RuntimeError(
            "Frozen C4 NaN / Inf"
        )


    if np.any(
        std <= 0
    ):

        raise RuntimeError(
            "Frozen C4 std <= 0"
        )


    if stored_sha != C4_EXPECTED_SHA256:

        raise RuntimeError(
            "Frozen C4 stored SHA mismatch"
        )


    if rebuilt_sha != C4_EXPECTED_SHA256:

        raise RuntimeError(
            "Frozen C4 rebuilt SHA mismatch"
        )


    if (
        frozen_status
        !=
        "EXPANDED_CANDIDATE_PENDING_LIVE_VALIDATION"
    ):

        raise RuntimeError(
            "Frozen C4 status mismatch"
        )


    print()
    print(
        "Frozen C4 gate load: PASS"
    )


    return {
        "candidate":
            candidate,

        "k":
            k,

        "mean":
            mean.astype(
                np.float64
            ),

        "std":
            std.astype(
                np.float64
            ),

        "sign_reference":
            sign_reference.astype(
                np.float64
            ),

        "nosign_reference":
            nosign_reference.astype(
                np.float64
            ),

        "sha256":
            stored_sha,
    }


# ============================================================
# Frozen C4 feature
# ============================================================

def build_c4_feature(
    feature,
):

    feature = np.asarray(
        feature,
        dtype=np.float32,
    )


    if feature.shape != (
        TARGET_FRAMES,
        FULL_DIM,
    ):

        raise RuntimeError(
            "C4 input feature shape 오류: "
            f"{feature.shape}"
        )


    representations = (
        cd.build_representations(
            feature
        )
    )


    if (
        C4_CANDIDATE_NAME
        not in
        representations
    ):

        raise RuntimeError(
            "06cd representation에 C4 없음"
        )


    c4 = np.asarray(
        representations[
            C4_CANDIDATE_NAME
        ],
        dtype=np.float64,
    )


    if c4.shape != (
        C4_FEATURE_DIM,
    ):

        raise RuntimeError(
            "C4 feature shape 오류: "
            f"{c4.shape}"
        )


    if not np.all(
        np.isfinite(
            c4
        )
    ):

        raise RuntimeError(
            "C4 feature NaN / Inf"
        )


    return c4


# ============================================================
# Frozen C4 mean KNN distance
# ============================================================

def c4_nearest_k_mean_distance(
    vector,
    references,
    k,
):

    vector = np.asarray(
        vector,
        dtype=np.float64,
    )


    references = np.asarray(
        references,
        dtype=np.float64,
    )


    delta = (
        references
        -
        vector[
            None,
            :
        ]
    )


    squared = np.sum(
        delta
        *
        delta,
        axis=1,
    )


    nearest_squared = np.partition(
        squared,
        kth=k - 1,
    )[
        :k
    ]


    return float(
        np.mean(
            np.sqrt(
                np.maximum(
                    nearest_squared,
                    0.0,
                )
            )
        )
    )


# ============================================================
# Frozen C4 inference
# ============================================================

def classify_onehand_c4_gate(
    feature,
    c4_model,
):

    c4 = build_c4_feature(
        feature
    )


    z_feature = (
        c4
        -
        c4_model[
            "mean"
        ]
    ) / c4_model[
        "std"
    ]


    d_sign = c4_nearest_k_mean_distance(
        vector=z_feature,
        references=c4_model[
            "sign_reference"
        ],
        k=c4_model[
            "k"
        ],
    )


    d_nosign = c4_nearest_k_mean_distance(
        vector=z_feature,
        references=c4_model[
            "nosign_reference"
        ],
        k=c4_model[
            "k"
        ],
    )


    prediction = (
        C4_SIGN_LABEL
        if d_sign <= d_nosign
        else C4_NOSIGN_LABEL
    )


    return {
        "prediction":
            int(
                prediction
            ),

        "d_sign":
            float(
                d_sign
            ),

        "d_nosign":
            float(
                d_nosign
            ),

        "margin_nosign_minus_sign":
            float(
                d_nosign
                -
                d_sign
            ),
    }


# ============================================================
# Frozen C4 gate display
# ============================================================

def print_onehand_c4_gate_result(
    gate_result,
):

    print()
    print("=" * 120)

    print(
        "ONE-HAND C4 SIGN / NO-SIGN GATE"
    )

    print("=" * 120)


    print(
        "Candidate :",
        C4_CANDIDATE_NAME,
    )


    print(
        "Feature   : Motion20 + LocalPhase210"
    )


    print(
        "K         :",
        C4_K,
    )


    print(
        "Threshold : NONE"
    )


    print()
    print(
        "dSIGN     :",
        f"{gate_result['d_sign']:.6f}",
    )


    print(
        "dNO-SIGN  :",
        f"{gate_result['d_nosign']:.6f}",
    )


    print(
        "Margin    :",
        f"{gate_result['margin_nosign_minus_sign']:+.6f}",
    )


    print()
    print(
        "GATE      :",
        (
            "SIGN"
            if gate_result[
                "prediction"
            ]
            ==
            C4_SIGN_LABEL
            else "NO-SIGN"
        ),
    )


# ============================================================
# ONE-HAND CLASSIFIER
#
# Base:
# Webcam calibration49
# RAW Local84 Full80
# K=3
#
# 후보:
# 2353 / 1152 / 1381 / 2403 / 2404 / 0953
#
# 추가 후보 규칙:
# BASE Top-2가 정확히 {2353,1152}이면
# MID40(frame 20:60) pairwise K3로 최종 결정
# ============================================================

def classify_one_hand(
    local,
    onehand_calibration,
):

    base_ranking = rank_classes(
        query=local,
        references=(
            onehand_calibration[
                "local"
            ]
        ),
        reference_y=(
            onehand_calibration[
                "class_ids"
            ]
        ),
        candidate_ids=(
            ONE_HAND_IDS
        ),
        k=K,
    )


    base_pred = int(
        base_ranking[
            0
        ][
            "class_id"
        ]
    )


    base_margin = ranking_margin(
        base_ranking
    )


    final_id = base_pred

    stage = (
        "ONEHAND6_WEBCAM_LOCAL_K3"
    )

    off_hurt_info = None


    top2_ids = {
        int(
            base_ranking[
                0
            ][
                "class_id"
            ]
        ),
        int(
            base_ranking[
                1
            ][
                "class_id"
            ]
        ),
    }


    if top2_ids == OFF_HURT_IDS:

        query_mid40 = local[
            OFF_HURT_MID_START:
            OFF_HURT_MID_END,
            :
        ]


        ref_mid40 = (
            onehand_calibration[
                "local"
            ][
                :,
                OFF_HURT_MID_START:
                OFF_HURT_MID_END,
                :
            ]
        )


        mid40_ranking = rank_classes(
            query=query_mid40,
            references=ref_mid40,
            reference_y=(
                onehand_calibration[
                    "class_ids"
                ]
            ),
            candidate_ids=[
                OFF_ID,
                HURT_ID,
            ],
            k=K,
        )


        final_id = int(
            mid40_ranking[
                0
            ][
                "class_id"
            ]
        )


        off_hurt_info = {
            "ranking":
                mid40_ranking,

            "margin":
                float(
                    ranking_margin(
                        mid40_ranking
                    )
                ),

            "start":
                OFF_HURT_MID_START,

            "end":
                OFF_HURT_MID_END,
        }


        stage = (
            "ONEHAND_OFF_HURT_MID40_K3"
        )


    return {
        "final_id":
            final_id,

        "stage":
            stage,

        "ranking":
            base_ranking,

        "margin":
            float(
                base_margin
            ),

        "base_id":
            base_pred,

        "base_ranking":
            base_ranking,

        "base_margin":
            float(
                base_margin
            ),

        "off_hurt_info":
            off_hurt_info,
    }


# ============================================================
# TWO-HAND CLASSIFIER
#
# 기존 06ak 그대로
#
# Stage 1:
# AIHub TRAIN Local Full80 K3
#
# Stage 2:
# HOT rescue
#
# Stage 3:
# 0128 / 1248 LAST40
# ============================================================

def classify_two_hand(
    local,
    aihub,
):

    # ========================================================
    # Stage 1
    # BASE Local Full80
    # ========================================================

    base_ranking = rank_classes(
        query=local,
        references=(
            aihub[
                "local"
            ]
        ),
        reference_y=(
            aihub[
                "class_ids"
            ]
        ),
        candidate_ids=(
            TWO_HAND_IDS
        ),
        k=K,
    )


    base_id = int(
        base_ranking[
            0
        ][
            "class_id"
        ]
    )


    base_margin = ranking_margin(
        base_ranking
    )


    final_id = base_id


    stage = (
        "TWOHAND_BASE_LOCAL"
    )


    hot_info = None

    ac_cold_info = None

    hot_rescued = False


    # ========================================================
    # Stage 2
    # HOT handshape rescue
    # ========================================================

    if (
        base_id
        in
        HOT_TRIGGER_BASE_IDS
    ):

        query_hs40 = (
            build_twohand_handshape40(
                local
            )
        )


        hot_ranking = rank_classes(
            query=query_hs40,
            references=(
                aihub[
                    "handshape40"
                ]
            ),
            reference_y=(
                aihub[
                    "class_ids"
                ]
            ),
            candidate_ids=[
                HOT_ID,
                base_id,
            ],
            k=K,
        )


        hot_score = score_from_ranking(
            hot_ranking,
            HOT_ID,
        )


        base_hs_score = score_from_ranking(
            hot_ranking,
            base_id,
        )


        hot_delta = float(
            hot_score
            -
            base_hs_score
        )


        hot_rescued = (
            hot_delta
            <=
            HOT_RESCUE_THRESHOLD
        )


        hot_info = {
            "hot_score":
                hot_score,

            "base_hs_score":
                base_hs_score,

            "delta":
                hot_delta,

            "threshold":
                HOT_RESCUE_THRESHOLD,

            "rescued":
                bool(
                    hot_rescued
                ),
        }


        if hot_rescued:

            final_id = HOT_ID


            stage = (
                "TWOHAND_HOT_"
                "HANDSHAPE_RESCUE"
            )


    # ========================================================
    # Stage 3
    # 0128 / 1248 LAST40
    # ========================================================

    if not hot_rescued:

        top2_ids = {
            int(
                base_ranking[
                    0
                ][
                    "class_id"
                ]
            ),

            int(
                base_ranking[
                    1
                ][
                    "class_id"
                ]
            ),
        }


        if top2_ids == AC_COLD_IDS:

            query_last40 = local[
                LAST40_START:
                LAST40_END,
                :
            ]


            ref_last40 = (
                aihub[
                    "local"
                ][
                    :,
                    LAST40_START:
                    LAST40_END,
                    :
                ]
            )


            ac_cold_ranking = (
                rank_classes(
                    query=query_last40,
                    references=ref_last40,
                    reference_y=(
                        aihub[
                            "class_ids"
                        ]
                    ),
                    candidate_ids=[
                        AIRCON_ID,
                        COLD_ID,
                    ],
                    k=K,
                )
            )


            final_id = int(
                ac_cold_ranking[
                    0
                ][
                    "class_id"
                ]
            )


            ac_cold_info = {
                "ranking":
                    ac_cold_ranking,

                "margin":
                    ranking_margin(
                        ac_cold_ranking
                    ),
            }


            stage = (
                "TWOHAND_"
                "AIRCON_COLD_LAST40"
            )


    return {
        "final_id":
            final_id,

        "stage":
            stage,

        "base_id":
            base_id,

        "base_ranking":
            base_ranking,

        "base_margin":
            float(
                base_margin
            ),

        "hot_info":
            hot_info,

        "ac_cold_info":
            ac_cold_info,
    }


# ============================================================
# Ranking 출력
# ============================================================

def print_ranking(
    title,
    ranking,
    max_items=None,
):

    print()
    print(
        title
    )


    if max_items is None:

        max_items = len(
            ranking
        )


    for rank_index, item in enumerate(
        ranking[
            :max_items
        ],
        start=1,
    ):

        print(
            f"  "
            f"{rank_index}. "
            f"{class_text(item['class_id']):<16}"
            f" | "
            f"{item['score']:.6f}"
        )


# ============================================================
# ONE-HAND 결과
# ============================================================

def print_onehand_result(
    result,
):

    print()
    print("=" * 120)

    print(
        "ONE-HAND 6-CLASS "
        "CLASSIFIER"
    )

    print("=" * 120)


    print(
        "Classifier : "
        "WEBCAM CALIBRATION 42"
    )


    print(
        "Base       : "
        "RAW Local84 Full80 K3"
    )


    print(
        "Candidates : "
        "2353 / 1152 / "
        "1381 / "
        "2403 / 2404 / 0953"
    )


    print_ranking(
        "ONE-HAND BASE RANKING:",
        result[
            "base_ranking"
        ],
    )


    print()
    print(
        "BASE   :",
        class_text(
            result[
                "base_id"
            ]
        ),
    )


    print(
        "Margin :",
        f"{result['base_margin']:+.6f}",
    )


    off_hurt_info = result[
        "off_hurt_info"
    ]


    if off_hurt_info is not None:

        print()
        print(
            "2353 / 1152 MID40 TIEBREAK:"
        )

        print(
            "  Frames :",
            (
                f"{off_hurt_info['start']}"
                f":"
                f"{off_hurt_info['end']}"
            ),
        )


        print_ranking(
            "MID40 PAIR RANKING:",
            off_hurt_info[
                "ranking"
            ],
        )


        print(
            "MID40 margin:",
            f"{off_hurt_info['margin']:+.6f}",
        )


    print()
    print(
        "Stage  :",
        result[
            "stage"
        ],
    )


    print()
    print(
        "FINAL  :",
        class_text(
            result[
                "final_id"
            ]
        ),
    )


# ============================================================
# TWO-HAND 결과
# ============================================================

def print_twohand_result(
    result,
):

    print()
    print("=" * 120)

    print(
        "TWO-HAND HIERARCHY"
    )

    print("=" * 120)


    print_ranking(
        "BASE LOCAL TOP-5:",
        result[
            "base_ranking"
        ],
        max_items=5,
    )


    print()
    print(
        "BASE   :",
        class_text(
            result[
                "base_id"
            ]
        ),
    )


    print(
        "Margin :",
        f"{result['base_margin']:+.6f}",
    )


    # ========================================================
    # HOT
    # ========================================================

    hot_info = result[
        "hot_info"
    ]


    if hot_info is not None:

        print()
        print(
            "HOT RESCUE CHECK:"
        )


        print(
            "  1382 HS     :",
            f"{hot_info['hot_score']:.6f}",
        )


        print(
            "  Base HS     :",
            f"{hot_info['base_hs_score']:.6f}",
        )


        print(
            "  HOT delta   :",
            f"{hot_info['delta']:+.6f}",
        )


        print(
            "  Threshold   :",
            f"{hot_info['threshold']:+.6f}",
        )


        print(
            "  Rescue      :",
            (
                "YES"
                if hot_info[
                    "rescued"
                ]
                else "NO"
            ),
        )


    # ========================================================
    # AC / COLD
    # ========================================================

    ac_info = result[
        "ac_cold_info"
    ]


    if ac_info is not None:

        print_ranking(
            "AIRCON / COLD LAST40:",
            ac_info[
                "ranking"
            ],
        )


        print(
            "LAST40 margin:",
            f"{ac_info['margin']:+.6f}",
        )


    print()
    print(
        "Stage  :",
        result[
            "stage"
        ],
    )


    print()
    print(
        "FINAL  :",
        class_text(
            result[
                "final_id"
            ]
        ),
    )


# ============================================================
# Webcam Feature validation
# ============================================================

def validate_webcam_feature(
    feature_info,
):

    if (
        "feature"
        not in feature_info
    ):

        raise RuntimeError(
            "feature_info에 "
            "feature 없음"
        )


    feature = np.asarray(
        feature_info[
            "feature"
        ],
        dtype=np.float32,
    )


    if feature.shape != (
        TARGET_FRAMES,
        FULL_DIM,
    ):

        raise RuntimeError(
            "Webcam feature shape 오류: "
            f"{feature.shape}"
        )


    if not np.all(
        np.isfinite(
            feature
        )
    ):

        raise RuntimeError(
            "Webcam feature NaN / Inf"
        )


    usage_type = str(
        feature_info[
            "usage_type"
        ]
    )


    if usage_type not in {
        "one_hand",
        "two_hand",
    }:

        raise RuntimeError(
            f"지원하지 않는 usage_type: "
            f"{usage_type}"
        )


    return (
        feature,
        usage_type,
    )


# ============================================================
# Capture 정보
# ============================================================

def print_capture_info(
    feature_info,
):

    print()
    print("=" * 120)

    print(
        "CAPTURE / FEATURE"
    )

    print("=" * 120)


    print(
        "Usage type     :",
        feature_info[
            "usage_type"
        ],
    )


    if (
        "source_mode"
        in feature_info
    ):

        print(
            "Source mode    :",
            feature_info[
                "source_mode"
            ],
        )


    if (
        "selected_frames"
        in feature_info
    ):

        print(
            "Selected frames:",
            feature_info[
                "selected_frames"
            ],
        )


    if (
        "both_ratio"
        in feature_info
    ):

        print(
            "Both ratio     :",
            f"{feature_info['both_ratio']:.3f}",
        )


    if (
        "detected_mask"
        in feature_info
    ):

        print(
            "Detected mask  :",
            feature_info[
                "detected_mask"
            ],
        )


    if (
        "usage_mask"
        in feature_info
    ):

        print(
            "Usage mask     :",
            feature_info[
                "usage_mask"
            ],
        )


# ============================================================
# 시작 정보
# ============================================================

def print_startup_info():

    print()
    print("=" * 160)

    print(
        "07a WEBCAM 15-CLASS EXPANSION RUNTIME"
    )

    print("=" * 160)

    print(
        FILE_TAG
    )


    # ========================================================
    # ONE HAND
    # ========================================================

    print()
    print(
        "[ONE HAND - 6 CLASSES]"
    )

    print(
        "2353 꺼지다 / "
        "1152 아프다 / "
        "1381 괜찮다"
    )

    print(
        "2403 점등 / "
        "2404 소등 / "
        "0953 배고프다"
    )

    print(
        "→ 07f webcam calibration 42"
    )

    print(
        "→ RAW Local84 Full80 / class별 K=3 mean RMSE"
    )

    print(
        "→ Frozen C4 SIGN / NO-SIGN gate 적용"
    )

    print(
        "→ 2353 / 1152 MID40 tiebreak 유지"
    )


    # ========================================================
    # TWO HAND
    # ========================================================

    print()
    print(
        "[TWO HAND - 9 CLASSES]"
    )

    print(
        "0128 에어컨 / "
        "0527 문잠그다 / "
        "1382 덥다 / "
        "1248 춥다"
    )

    print(
        "1588 구조 / "
        "1570 연기 / "
        "1290 감사 / "
        "2563 온도 / "
        "2036 목마르다"
    )

    print(
        "→ AIHub TRAIN RAW Local84 K3"
    )

    print(
        "→ HOT rescue "
        f"(threshold={HOT_RESCUE_THRESHOLD})"
    )

    print(
        "→ 0128 / 1248 Local LAST40"
    )

    print(
        "→ 2563 온도 TEMP OVERLAP RESCUE"
    )


    # ========================================================
    # ROUTING
    # ========================================================

    print()
    print(
        "[ROUTING]"
    )

    print(
        "1290 감사"
    )

    print(
        "  → TWO-HAND ONLY"
    )

    print(
        "2563 온도"
    )

    print(
        "  → 정상 양손 검출: 기존 two-hand branch"
    )

    print(
        "  → 손 겹침으로 one-hand 오인 + C4 NO-SIGN"
    )

    print(
        "  → both_ratio >= 0.20 "
        "and both frames >= 15"
    )

    print(
        "  → two-hand 재구성 결과가 온도일 때만 rescue"
    )


    # ========================================================
    # NO-SIGN
    # ========================================================

    print()
    print(
        "[NO-SIGN]"
    )

    print(
        "ONE-HAND : Frozen C4 rejection APPLIED"
    )

    print(
        "TWO-HAND : NO-SIGN rejection NOT APPLIED"
    )


    # ========================================================
    # BASELINE
    # ========================================================

    print()
    print(
        "[BASELINE]"
    )

    print(
        "Frozen baseline 06ct는 수정하지 않았습니다."
    )

    print("=" * 160)


def main():

    print_startup_info()


    # ========================================================
    # Reference load
    # ========================================================

    print()
    print(
        "초기 reference를 "
        "로드합니다..."
    )


    aihub = (
        load_aihub_train_references()
    )


    onehand_calibration = (
        load_onehand_calibration()
    )


    c4_model = (
        load_frozen_c4_gate()
    )


    print()
    print("=" * 160)

    print(
        "STARTUP CHECK COMPLETE"
    )

    print("=" * 160)


    print(
        "Webcam recognition을 "
        "시작합니다."
    )


    print(
        "S = 녹화 시작"
    )


    print(
        "E = 녹화 종료"
    )


    print(
        "Q = webcam 화면에서 종료"
    )


    # ========================================================
    # Runtime loop
    # ========================================================

    while True:

        print()
        print("=" * 160)

        print(
            "READY FOR NEXT SIGN"
        )

        print("=" * 160)


        print(
            "S → 수어 → E"
        )


        # ====================================================
        # Capture
        # ====================================================

        try:

            frames = (
                u.capture_sequence()
            )


        except KeyboardInterrupt:

            print()
            print(
                "KeyboardInterrupt → 종료"
            )

            break


        except Exception as e:

            print()
            print(
                "CAPTURE ERROR:"
            )


            print(
                repr(e)
            )


            continue


        if frames is None:

            print()
            print(
                "Webcam 종료 요청"
            )

            break


        # ====================================================
        # Feature V3
        # ====================================================

        try:

            feature_info = (
                u.build_webcam_feature(
                    frames
                )
            )


            (
                feature,
                usage_type,
            ) = validate_webcam_feature(
                feature_info
            )


        except Exception as e:

            print()
            print("=" * 120)

            print(
                "INVALID INPUT"
            )

            print("=" * 120)


            print(
                repr(e)
            )


            print()
            print(
                "이번 입력은 "
                "prediction하지 않습니다."
            )


            continue


        # ====================================================
        # Local84
        # ====================================================

        local = feature[
            :,
            0:LOCAL_DIM,
        ].copy()


        print_capture_info(
            feature_info
        )


        # ====================================================
        # Classification
        # ====================================================

        try:

            # =================================================
            # ONE HAND
            #
            # 2353 / 1152 / 1381 / 2403 / 2404 / 0953
            # =================================================

            if usage_type == "one_hand":

                gate_result = (
                    classify_onehand_c4_gate(
                        feature=feature,
                        c4_model=c4_model,
                    )
                )


                print_onehand_c4_gate_result(
                    gate_result
                )


                if (
                    gate_result[
                        "prediction"
                    ]
                    ==
                    C4_NOSIGN_LABEL
                ):

                    # =========================================
                    # 기본값:
                    # C4가 NO-SIGN이면 기존대로 차단
                    # =========================================

                    result = {
                        "final_id":
                            None,

                        "stage":
                            "ONEHAND_C4_NOSIGN_REJECT",

                        "is_nosign":
                            True,

                        "c4_gate":
                            gate_result,
                    }


                    # =========================================
                    # TEMP OVERLAP RESCUE
                    #
                    # 온도(2563)는 두 손이 겹치기 때문에
                    # MediaPipe가 일부 구간에서 한 손을
                    # 놓칠 수 있다.
                    #
                    # 조건:
                    # 1) 원래 routing은 one_hand
                    # 2) C4는 NO-SIGN
                    # 3) 녹화 중 양손 프레임 비율 >= 0.25
                    # 4) 실제 양손 프레임 수가 충분함
                    #
                    # 양손으로 동시에 잡힌 frame만 다시
                    # 06u에 전달하면 BOTH ratio=1.0이므로
                    # 정상적인 two-hand Feature V3를 만든다.
                    #
                    # 그리고 최종 결과가 TEMP_ID일 때만
                    # rescue를 허용한다.
                    # =========================================

                    original_both_ratio = float(
                        feature_info.get(
                            "both_ratio",
                            0.0,
                        )
                    )


                    both_frames_for_rescue = [
                        (
                            left,
                            right,
                        )
                        for left, right
                        in frames
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


                    if can_try_temp_rescue:

                        print()
                        print("=" * 120)

                        print(
                            "TEMP OVERLAP RESCUE CHECK"
                        )

                        print("=" * 120)

                        print(
                            "Original usage :",
                            usage_type,
                        )

                        print(
                            "Both ratio     :",
                            f"{original_both_ratio:.3f}",
                        )

                        print(
                            "Both frames    :",
                            len(
                                both_frames_for_rescue
                            ),
                        )

                        print(
                            "Required frames:",
                            min_both_frames,
                        )


                        try:

                            rescue_feature_info = (
                                u.build_webcam_feature(
                                    both_frames_for_rescue
                                )
                            )


                            (
                                rescue_feature,
                                rescue_usage_type,
                            ) = validate_webcam_feature(
                                rescue_feature_info
                            )


                            if (
                                rescue_usage_type
                                !=
                                "two_hand"
                            ):

                                raise RuntimeError(
                                    "TEMP rescue feature가 "
                                    "two_hand가 아님"
                                )


                            rescue_local = (
                                rescue_feature[
                                    :,
                                    0:LOCAL_DIM,
                                ]
                            )


                            rescue_result = (
                                classify_two_hand(
                                    local=rescue_local,
                                    aihub=aihub,
                                )
                            )


                            rescue_final_id = int(
                                rescue_result[
                                    "final_id"
                                ]
                            )


                            print()
                            print(
                                "Rescue candidate:",
                                class_text(
                                    rescue_final_id
                                ),
                            )


                            if (
                                rescue_final_id
                                ==
                                TEMP_ID
                            ):

                                rescue_result[
                                    "stage"
                                ] = (
                                    "TWOHAND_TEMP_"
                                    "OVERLAP_RESCUE"
                                )


                                rescue_result[
                                    "is_nosign"
                                ] = False


                                rescue_result[
                                    "c4_gate"
                                ] = gate_result


                                result = (
                                    rescue_result
                                )


                                usage_type = (
                                    "two_hand"
                                )


                                print(
                                    "TEMP rescue     : YES"
                                )


                                print_twohand_result(
                                    result
                                )


                            else:

                                print(
                                    "TEMP rescue     : NO"
                                )


                        except Exception as rescue_error:

                            print()
                            print(
                                "TEMP rescue error:",
                                repr(
                                    rescue_error
                                ),
                            )

                            print(
                                "기존 C4 NO-SIGN "
                                "결과를 유지합니다."
                            )


                else:

                    result = classify_one_hand(
                        local=local,
                        onehand_calibration=(
                            onehand_calibration
                        ),
                    )


                    result[
                        "is_nosign"
                    ] = False


                    result[
                        "c4_gate"
                    ] = gate_result


                    print_onehand_result(
                        result
                    )


            # =================================================
            # TWO HAND
            #
            # 기존 hierarchy
            # =================================================

            elif usage_type == "two_hand":

                result = classify_two_hand(
                    local=local,
                    aihub=aihub,
                )


                print_twohand_result(
                    result
                )


            else:

                raise RuntimeError(
                    f"Unexpected usage_type: "
                    f"{usage_type}"
                )


        except Exception as e:

            print()
            print("=" * 120)

            print(
                "CLASSIFICATION ERROR"
            )

            print("=" * 120)


            print(
                repr(e)
            )


            print()
            print(
                "이번 prediction은 "
                "폐기합니다."
            )


            continue


        # ====================================================
        # 최종 출력
        # ====================================================

        is_nosign = bool(
            result.get(
                "is_nosign",
                False,
            )
        )


        print()
        print("=" * 160)

        print(
            "FINAL PREDICTION"
        )

        print("=" * 160)


        print(
            "Usage :",
            usage_type,
        )


        print(
            "Stage :",
            result[
                "stage"
            ],
        )


        if is_nosign:

            final_id = None


            print()
            print(
                ">>> NO-SIGN"
            )


            print()
            print(
                "※ Frozen C4가 one-hand 입력을 "
                "NO-SIGN으로 차단했습니다."
            )


            print(
                "※ one-hand 6-class classifier는 "
                "실행하지 않았습니다."
            )


        else:

            final_id = int(
                result[
                    "final_id"
                ]
            )


            print()
            print(
                ">>>",
                class_text(
                    final_id
                ),
            )


            # ------------------------------------------------
            # 감사 fallback 여부 표시
            # ------------------------------------------------

            if (
                final_id == THANKS_ID
                and
                usage_type == "one_hand"
            ):

                print()
                print(
                    "※ 1290 감사가 "
                    "one-hand fallback으로 "
                    "복구되었습니다."
                )


            elif (
                final_id == THANKS_ID
                and
                usage_type == "two_hand"
            ):

                print()
                print(
                    "※ 1290 감사가 "
                    "two-hand branch에서 "
                    "인식되었습니다."
                )


        print()


        if usage_type == "one_hand":

            print(
                "※ ONE-HAND NO-SIGN REJECTION: "
                "FROZEN C4 APPLIED"
            )


        else:

            print(
                "※ TWO-HAND NO-SIGN REJECTION: "
                "NOT APPLIED"
            )


        print("=" * 160)


        # ====================================================
        # 다음 입력
        # ====================================================

        command = input(
            "\nEnter = 다음 수어 / "
            "Q = 종료 : "
        ).strip().lower()


        if command == "q":

            break


    # ========================================================
    # 종료
    # ========================================================

    print()
    print("=" * 160)

    print(
        "07a RUNTIME END"
    )

    print("=" * 160)


if __name__ == "__main__":
    main()