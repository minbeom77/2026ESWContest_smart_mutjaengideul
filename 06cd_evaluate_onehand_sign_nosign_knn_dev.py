import os
import hashlib
from collections import Counter

import numpy as np


# ============================================================
# 06cd
# [실험용 / 당장은 보관 권장]
#
# ONE-HAND SIGN vs NO-SIGN
# SOURCE-AWARE BINARY VERIFIER DEVELOPMENT
#
#
# ============================================================
# 목적
# ============================================================
#
# 06cc에서 확정한:
#
#   CALIBRATION_RESERVED = 28
#
#   DEVELOPMENT_LOCO
#     SIGN    = 267
#     NO-SIGN = 308
#
#   capture cohorts = 14
#
# 를 이용하여
#
# SIGN vs NO-SIGN binary verifier 후보 representation을
#
# Leave-One-Capture-Cohort-Out
#
# 방식으로 평가한다.
#
#
# ============================================================
# 이번 단계
# ============================================================
#
# - Full172 실제 tensor를 canonical provenance에서 복원
# - hash를 다시 계산하여 06cc manifest와 일치 검증
# - 6개 representation 비교
# - Class-balanced K3 distance classifier 사용
# - 모든 sample에 OOF prediction 생성
#
#
# ============================================================
# 하지 않는 것
# ============================================================
#
# X webcam
# X runtime 수정
# X probability threshold tuning
# X K tuning
# X representation 결과 기반 재설계
# X 06am 사용
# X final fresh 사용
#
#
# ============================================================
# Binary label
# ============================================================
#
# SIGN    = 1
# NO-SIGN = 0
#
#
# ============================================================
# Classifier
# ============================================================
#
# train fold에서 representation별 standardization 후:
#
#   SIGN train 중 nearest K=3 평균거리
#   NO-SIGN train 중 nearest K=3 평균거리
#
# 비교.
#
#   d_sign <= d_nosign
#       => SIGN
#
#   d_sign > d_nosign
#       => NO-SIGN
#
#
# 클래스별로 K개를 따로 찾기 때문에
# SIGN/NO-SIGN sample 수 차이의 영향이 작다.
#
#
# K = 3 고정.
# 이번 결과로 K를 조정하지 않는다.
#
#
# ============================================================
# Candidate representations
# ============================================================
#
# C1_MOTION20
#   class-independent temporal motion scalar 20개
#
# C2_MOTION_TRAJ40
#   Motion20
#   + centered trajectory 10-phase means (20)
#
# C3_LOCAL_PHASE210
#   local hand shape 5-phase means
#   = 5 × 42 = 210
#
# C4_MOTION_LOCAL230
#   Motion20
#   + LocalPhase210
#
# C5_COMBINED250
#   Motion20
#   + Trajectory20
#   + LocalPhase210
#
# C6_FULL_TEMPORAL418
#   Motion20
#   + Trajectory20
#   + LocalPhase210
#   + LocalPhaseDelta168
#
#
# ============================================================
# Important
# ============================================================
#
# 06aj / 06an:
#   SIGN only cohort
#
# 06ap / 06bu:
#   NO-SIGN only cohort
#
# 따라서 per-fold balanced accuracy를 강제로 계산하지 않는다.
#
# 전체 575개 OOF에서:
#
#   SIGN recall
#   NO-SIGN reject rate
#   balanced accuracy
#
# 를 계산한다.
#
#
# ============================================================
# Output
# ============================================================
#
# diagnostics_v3/
#   06cd_onehand_sign_nosign_knn_dev_evaluation.npz
#
# ============================================================


FILE_TAG = "[실험용 / 당장은 보관 권장]"


# ============================================================
# Config
# ============================================================

K_NEIGHBORS = 3


EXPECTED_TIME = 80
EXPECTED_DIM = 172


SIGN_LABEL = 1
NOSIGN_LABEL = 0


# ============================================================
# Class info
# ============================================================

CLASS_NAMES = {
    2: "2353 꺼지다",
    7: "1152 아프다",
    8: "1381 괜찮다",
    9: "1290 감사",
}


# ============================================================
# Paths
# ============================================================

BASE_DIR = os.path.dirname(
    os.path.abspath(__file__)
)


DIAGNOSTICS_DIR = os.path.join(
    BASE_DIR,
    "diagnostics_v3",
)


TEMPLATE_DIR = os.path.join(
    BASE_DIR,
    "template_runtime_v3",
)


PATH_06CC = os.path.join(
    DIAGNOSTICS_DIR,
    "06cc_onehand_sign_nosign_source_split_design.npz",
)


OUTPUT_PATH = os.path.join(
    DIAGNOSTICS_DIR,
    "06cd_onehand_sign_nosign_knn_dev_evaluation.npz",
)


SEARCH_ROOTS = [
    DIAGNOSTICS_DIR,
    TEMPLATE_DIR,
]


os.makedirs(
    DIAGNOSTICS_DIR,
    exist_ok=True,
)


# ============================================================
# Same tensor-key priority as inventory/audit
# ============================================================

SAMPLE_KEY_PRIORITY = [
    "features",
    "live_features",
    "negative_features",
    "full",
    "feature_sequences",
    "sequences",
    "local84",
    "local",
    "local_features",
    "local_templates",
]


# ============================================================
# Candidate definitions
# ============================================================

CANDIDATE_NAMES = [
    "C1_MOTION20",
    "C2_MOTION_TRAJ40",
    "C3_LOCAL_PHASE210",
    "C4_MOTION_LOCAL230",
    "C5_COMBINED250",
    "C6_FULL_TEMPORAL418",
]


EXPECTED_CANDIDATE_DIMS = {
    "C1_MOTION20":
        20,

    "C2_MOTION_TRAJ40":
        40,

    "C3_LOCAL_PHASE210":
        210,

    "C4_MOTION_LOCAL230":
        230,

    "C5_COMBINED250":
        250,

    "C6_FULL_TEMPORAL418":
        418,
}


# ============================================================
# Helpers
# ============================================================

def require_file(path):

    if not os.path.exists(path):

        raise FileNotFoundError(
            f"필수 파일 없음:\n{path}"
        )


def class_text(class_id):

    return CLASS_NAMES.get(
        int(class_id),
        f"UNKNOWN({class_id})",
    )


# ============================================================
# Sample hash
#
# 06ca / 06cb와 동일한 방식.
# ============================================================

def sample_hash(sample):

    array = np.asarray(
        sample,
        dtype=np.float32,
    )


    array = np.round(
        array,
        decimals=6,
    )


    array = np.ascontiguousarray(
        array
    )


    h = hashlib.sha256()


    h.update(
        str(
            array.shape
        ).encode(
            "utf-8"
        )
    )


    h.update(
        array.tobytes()
    )


    return h.hexdigest()


# ============================================================
# Load 06cc manifest
# ============================================================

def load_06cc_manifest():

    require_file(
        PATH_06CC
    )


    data = np.load(
        PATH_06CC,
        allow_pickle=True,
    )


    required = {
        "sample_hashes",
        "resolved_categories",
        "binary_labels",
        "sign_class_ids",
        "negative_types",
        "dataset_roles",
        "capture_cohorts",
        "canonical_files",
        "canonical_sample_indices",
        "has_06am_provenance",
        "design_status",
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
            "06cc key 부족: "
            f"{sorted(missing)}"
        )


    status = str(
        np.asarray(
            data[
                "design_status"
            ]
        ).reshape(-1)[0]
    )


    if (
        status
        !=
        "READY_FOR_06CD_BINARY_VERIFIER_DEVELOPMENT"
    ):

        raise RuntimeError(
            "06cc가 READY 상태가 아닙니다.\n"
            f"status={status}"
        )


    hashes = np.asarray(
        data[
            "sample_hashes"
        ]
    ).astype(str)


    categories = np.asarray(
        data[
            "resolved_categories"
        ]
    ).astype(str)


    labels = np.asarray(
        data[
            "binary_labels"
        ],
        dtype=np.int64,
    )


    sign_class_ids = np.asarray(
        data[
            "sign_class_ids"
        ],
        dtype=np.int64,
    )


    negative_types = np.asarray(
        data[
            "negative_types"
        ]
    ).astype(str)


    roles = np.asarray(
        data[
            "dataset_roles"
        ]
    ).astype(str)


    cohorts = np.asarray(
        data[
            "capture_cohorts"
        ]
    ).astype(str)


    files = np.asarray(
        data[
            "canonical_files"
        ]
    ).astype(str)


    sample_indices = np.asarray(
        data[
            "canonical_sample_indices"
        ],
        dtype=np.int64,
    )


    has_06am = np.asarray(
        data[
            "has_06am_provenance"
        ],
        dtype=bool,
    )


    n = len(
        hashes
    )


    arrays = [
        categories,
        labels,
        sign_class_ids,
        negative_types,
        roles,
        cohorts,
        files,
        sample_indices,
        has_06am,
    ]


    if any(
        len(array)
        !=
        n

        for array in arrays
    ):

        raise RuntimeError(
            "06cc manifest array length mismatch"
        )


    records = []


    for i in range(
        n
    ):

        records.append(
            {
                "hash":
                    hashes[
                        i
                    ],

                "category":
                    categories[
                        i
                    ],

                "binary_label":
                    int(
                        labels[
                            i
                        ]
                    ),

                "sign_class_id":
                    int(
                        sign_class_ids[
                            i
                        ]
                    ),

                "negative_type":
                    negative_types[
                        i
                    ],

                "dataset_role":
                    roles[
                        i
                    ],

                "capture_cohort":
                    cohorts[
                        i
                    ],

                "canonical_file":
                    files[
                        i
                    ],

                "canonical_sample_index":
                    int(
                        sample_indices[
                            i
                        ]
                    ),

                "has_06am":
                    bool(
                        has_06am[
                            i
                        ]
                    ),
            }
        )


    return records


# ============================================================
# Manifest check
# ============================================================

def verify_manifest(records):

    development = [
        r
        for r in records
        if (
            r[
                "dataset_role"
            ]
            ==
            "DEVELOPMENT_LOCO"
        )
    ]


    calibration = [
        r
        for r in records
        if (
            r[
                "dataset_role"
            ]
            ==
            "CALIBRATION_RESERVED"
        )
    ]


    sign = sum(
        r[
            "binary_label"
        ]
        ==
        SIGN_LABEL

        for r in development
    )


    nosign = sum(
        r[
            "binary_label"
        ]
        ==
        NOSIGN_LABEL

        for r in development
    )


    cohorts = sorted(
        set(
            r[
                "capture_cohort"
            ]
            for r in development
        )
    )


    print()
    print("=" * 260)
    print("06CC MANIFEST INPUT CHECK")
    print("=" * 260)


    print(
        "Development:",
        len(
            development
        ),
    )


    print(
        "  SIGN:",
        sign,
    )


    print(
        "  NO-SIGN:",
        nosign,
    )


    print(
        "Calibration reserved:",
        len(
            calibration
        ),
    )


    print(
        "Capture cohorts:",
        len(
            cohorts
        ),
    )


    if len(
        development
    ) != 575:

        raise RuntimeError(
            "Expected DEVELOPMENT=575"
        )


    if sign != 267:

        raise RuntimeError(
            f"Expected SIGN=267, actual={sign}"
        )


    if nosign != 308:

        raise RuntimeError(
            f"Expected NO-SIGN=308, actual={nosign}"
        )


    if len(
        calibration
    ) != 28:

        raise RuntimeError(
            "Expected calibration=28"
        )


    if len(
        cohorts
    ) != 14:

        raise RuntimeError(
            "Expected capture cohorts=14"
        )


    # 06am must not enter development
    if any(
        r[
            "has_06am"
        ]
        for r in development
    ):

        raise RuntimeError(
            "06am provenance가 DEVELOPMENT에 들어옴"
        )


    print()
    print(
        "06cc manifest integrity: PASS"
    )


    return (
        development,
        calibration,
        cohorts,
    )


# ============================================================
# Locate canonical files
# ============================================================

def build_file_index():

    index = {}


    for root in SEARCH_ROOTS:

        if not os.path.isdir(
            root
        ):

            continue


        for current_root, _, filenames in os.walk(
            root
        ):

            for filename in filenames:

                if not filename.lower().endswith(
                    ".npz"
                ):

                    continue


                full_path = os.path.join(
                    current_root,
                    filename,
                )


                index.setdefault(
                    filename,
                    [],
                ).append(
                    full_path
                )


    return index


# ============================================================
# Sample tensor
# ============================================================

def valid_sample_tensor(array):

    array = np.asarray(
        array
    )


    if array.ndim != 3:

        return False


    if array.shape[
        0
    ] <= 0:

        return False


    if array.shape[
        -1
    ] not in {
        84,
        172,
    }:

        return False


    return True


def find_sample_tensor(data):

    for key in SAMPLE_KEY_PRIORITY:

        if key not in data.files:

            continue


        array = np.asarray(
            data[
                key
            ]
        )


        if valid_sample_tensor(
            array
        ):

            return (
                key,
                array,
            )


    candidates = []


    for key in data.files:

        try:

            array = np.asarray(
                data[
                    key
                ]
            )

        except Exception:

            continue


        if valid_sample_tensor(
            array
        ):

            candidates.append(
                (
                    key,
                    array,
                )
            )


    if len(
        candidates
    ) == 0:

        return (
            None,
            None,
        )


    candidates.sort(
        key=lambda item: (
            0
            if item[
                1
            ].shape[
                -1
            ]
            ==
            172
            else 1,

            item[
                0
            ],
        )
    )


    return candidates[
        0
    ]


# ============================================================
# Materialize development tensors
# ============================================================

def load_development_tensors(
    development,
):

    file_index = build_file_index()


    tensor_cache = {}


    samples = []


    print()
    print("=" * 260)
    print("CANONICAL FULL172 MATERIALIZATION CHECK")
    print("=" * 260)


    for row_index, record in enumerate(
        development,
        start=1,
    ):

        filename = record[
            "canonical_file"
        ]


        if filename not in file_index:

            raise FileNotFoundError(
                "Canonical NPZ를 찾을 수 없음:\n"
                f"{filename}"
            )


        paths = file_index[
            filename
        ]


        if len(
            paths
        ) != 1:

            raise RuntimeError(
                "동일 basename NPZ가 여러 개 존재:\n"
                f"{filename}\n"
                f"{paths}"
            )


        path = paths[
            0
        ]


        if path not in tensor_cache:

            data = np.load(
                path,
                allow_pickle=True,
            )


            tensor_key, tensor = (
                find_sample_tensor(
                    data
                )
            )


            if tensor is None:

                raise RuntimeError(
                    "Sample tensor 없음:\n"
                    f"{path}"
                )


            tensor_cache[
                path
            ] = (
                tensor_key,
                np.asarray(
                    tensor
                ),
            )


        tensor_key, tensor = (
            tensor_cache[
                path
            ]
        )


        sample_index = record[
            "canonical_sample_index"
        ]


        if not (
            0
            <=
            sample_index
            <
            len(
                tensor
            )
        ):

            raise RuntimeError(
                "Canonical sample index 범위 오류\n"
                f"file={filename}\n"
                f"index={sample_index}\n"
                f"N={len(tensor)}"
            )


        sample = np.asarray(
            tensor[
                sample_index
            ],
            dtype=np.float32,
        )


        if sample.shape != (
            EXPECTED_TIME,
            EXPECTED_DIM,
        ):

            raise RuntimeError(
                "Expected Full172 shape mismatch\n"
                f"file={filename}\n"
                f"sample={sample_index}\n"
                f"shape={sample.shape}"
            )


        rebuilt_hash = sample_hash(
            sample
        )


        if (
            rebuilt_hash
            !=
            record[
                "hash"
            ]
        ):

            raise RuntimeError(
                "06cc hash / canonical tensor 불일치\n"
                f"file={filename}\n"
                f"sample={sample_index}\n"
                f"expected={record['hash']}\n"
                f"actual={rebuilt_hash}"
            )


        samples.append(
            sample
        )


        if (
            row_index
            %
            50
            ==
            0
        ):

            print(
                f"  verified "
                f"{row_index}/"
                f"{len(development)}"
            )


    x = np.stack(
        samples,
        axis=0,
    ).astype(
        np.float32
    )


    print()
    print(
        "Materialized:",
        x.shape,
    )


    print(
        "Hash verification:",
        "PASS"
    )


    print(
        "Canonical files cached:",
        len(
            tensor_cache
        ),
    )


    return x


# ============================================================
# Active one-hand local slot
#
# Feature v3:
#
# local:
#   0:42   SLOT A
#   42:84  SLOT B
#
# 정상 one-hand에서는 SLOT A가 사용되지만
# 안전하게 energy가 큰 쪽을 선택.
# ============================================================

def get_local42(sequence):

    slot_a = np.asarray(
        sequence[
            :,
            0:42
        ],
        dtype=np.float64,
    )


    slot_b = np.asarray(
        sequence[
            :,
            42:84
        ],
        dtype=np.float64,
    )


    energy_a = float(
        np.mean(
            np.abs(
                slot_a
            )
        )
    )


    energy_b = float(
        np.mean(
            np.abs(
                slot_b
            )
        )
    )


    if energy_b > energy_a:

        return slot_b


    return slot_a


# ============================================================
# Phase means
# ============================================================

def phase_means(
    array,
    bins,
):

    array = np.asarray(
        array,
        dtype=np.float64,
    )


    t = array.shape[
        0
    ]


    edges = np.linspace(
        0,
        t,
        bins + 1,
        dtype=np.int64,
    )


    result = []


    for i in range(
        bins
    ):

        start = int(
            edges[
                i
            ]
        )


        end = int(
            edges[
                i + 1
            ]
        )


        if end <= start:

            raise RuntimeError(
                "Phase bin empty"
            )


        result.append(
            np.mean(
                array[
                    start:end
                ],
                axis=0,
            )
        )


    return np.stack(
        result,
        axis=0,
    )


# ============================================================
# Quantile helper
# ============================================================

def q(
    values,
    percentile,
):

    values = np.asarray(
        values,
        dtype=np.float64,
    )


    if len(
        values
    ) == 0:

        return 0.0


    return float(
        np.percentile(
            values,
            percentile,
        )
    )


# ============================================================
# Motion20
# ============================================================

def build_motion20(
    local42,
    trajectory,
):

    # --------------------------------------------------------
    # Local-frame motion
    # --------------------------------------------------------

    local_delta = np.diff(
        local42,
        axis=0,
    )


    local_speed = np.linalg.norm(
        local_delta,
        axis=1,
    )


    # --------------------------------------------------------
    # Wrist/global trajectory motion
    # --------------------------------------------------------

    traj_delta = np.diff(
        trajectory,
        axis=0,
    )


    traj_speed = np.linalg.norm(
        traj_delta,
        axis=1,
    )


    local_stats = [
        float(
            np.mean(
                local_speed
            )
        ),

        float(
            np.median(
                local_speed
            )
        ),

        q(
            local_speed,
            75,
        ),

        q(
            local_speed,
            90,
        ),

        float(
            np.max(
                local_speed
            )
        ),

        float(
            np.std(
                local_speed
            )
        ),
    ]


    traj_stats = [
        float(
            np.mean(
                traj_speed
            )
        ),

        float(
            np.median(
                traj_speed
            )
        ),

        q(
            traj_speed,
            75,
        ),

        q(
            traj_speed,
            90,
        ),

        float(
            np.max(
                traj_speed
            )
        ),

        float(
            np.std(
                traj_speed
            )
        ),
    ]


    displacement_vector = (
        trajectory[
            -1
        ]
        -
        trajectory[
            0
        ]
    )


    displacement = float(
        np.linalg.norm(
            displacement_vector
        )
    )


    path = float(
        np.sum(
            traj_speed
        )
    )


    straightness = (
        displacement
        /
        (
            path
            +
            1e-8
        )
    )


    # --------------------------------------------------------
    # Direction resultant
    # --------------------------------------------------------

    moving = (
        traj_speed
        >
        1e-8
    )


    if np.any(
        moving
    ):

        unit = (
            traj_delta[
                moving
            ]
            /
            traj_speed[
                moving,
                None,
            ]
        )


        direction_resultant = float(
            np.linalg.norm(
                np.mean(
                    unit,
                    axis=0,
                )
            )
        )


    else:

        direction_resultant = 0.0


    bbox = (
        np.max(
            trajectory,
            axis=0,
        )
        -
        np.min(
            trajectory,
            axis=0,
        )
    )


    segment = max(
        1,
        len(
            traj_speed
        )
        //
        4,
    )


    start_speed = float(
        np.mean(
            traj_speed[
                :segment
            ]
        )
    )


    end_speed = float(
        np.mean(
            traj_speed[
                -segment:
            ]
        )
    )


    feature = np.asarray(
        local_stats
        +
        traj_stats
        +
        [
            displacement,
            path,
            straightness,
            direction_resultant,
            float(
                bbox[
                    0
                ]
            ),
            float(
                bbox[
                    1
                ]
            ),
            start_speed,
            end_speed,
        ],
        dtype=np.float64,
    )


    if feature.shape != (
        20,
    ):

        raise RuntimeError(
            f"Motion20 shape 오류: {feature.shape}"
        )


    return feature


# ============================================================
# Representation
# ============================================================

def build_representations(
    sequence,
):

    local42 = get_local42(
        sequence
    )


    trajectory = np.asarray(
        sequence[
            :,
            168:170
        ],
        dtype=np.float64,
    )


    motion20 = build_motion20(
        local42,
        trajectory,
    )


    # --------------------------------------------------------
    # Centered trajectory:
    #
    # translation을 제거하되
    # 동작 크기는 유지.
    #
    # 10 temporal phase means × XY
    # --------------------------------------------------------

    centered_traj = (
        trajectory
        -
        trajectory[
            0
        ]
    )


    traj_phase10 = phase_means(
        centered_traj,
        bins=10,
    ).reshape(
        -1
    )


    if traj_phase10.shape != (
        20,
    ):

        raise RuntimeError(
            "Trajectory phase shape 오류"
        )


    # --------------------------------------------------------
    # Local phase:
    #
    # 5 × 42 = 210
    # --------------------------------------------------------

    local_phase5_matrix = phase_means(
        local42,
        bins=5,
    )


    local_phase210 = (
        local_phase5_matrix
        .reshape(
            -1
        )
    )


    if local_phase210.shape != (
        210,
    ):

        raise RuntimeError(
            "Local phase shape 오류"
        )


    # --------------------------------------------------------
    # Phase change:
    #
    # diff of 5 phase means
    #
    # 4 × 42 = 168
    # --------------------------------------------------------

    local_phase_delta168 = (
        np.diff(
            local_phase5_matrix,
            axis=0,
        )
        .reshape(
            -1
        )
    )


    if local_phase_delta168.shape != (
        168,
    ):

        raise RuntimeError(
            "Local phase delta shape 오류"
        )


    result = {
        "C1_MOTION20":
            motion20,

        "C2_MOTION_TRAJ40":
            np.concatenate(
                [
                    motion20,
                    traj_phase10,
                ]
            ),

        "C3_LOCAL_PHASE210":
            local_phase210,

        "C4_MOTION_LOCAL230":
            np.concatenate(
                [
                    motion20,
                    local_phase210,
                ]
            ),

        "C5_COMBINED250":
            np.concatenate(
                [
                    motion20,
                    traj_phase10,
                    local_phase210,
                ]
            ),

        "C6_FULL_TEMPORAL418":
            np.concatenate(
                [
                    motion20,
                    traj_phase10,
                    local_phase210,
                    local_phase_delta168,
                ]
            ),
    }


    for name in CANDIDATE_NAMES:

        vector = np.asarray(
            result[
                name
            ],
            dtype=np.float64,
        )


        expected = (
            EXPECTED_CANDIDATE_DIMS[
                name
            ]
        )


        if vector.shape != (
            expected,
        ):

            raise RuntimeError(
                f"{name} dimension 오류\n"
                f"expected={expected}\n"
                f"actual={vector.shape}"
            )


        if not np.all(
            np.isfinite(
                vector
            )
        ):

            raise RuntimeError(
                f"{name}: NaN/Inf 발견"
            )


        result[
            name
        ] = vector


    return result


# ============================================================
# Build all representation matrices
# ============================================================

def build_candidate_matrices(
    sequences,
):

    matrices = {
        name: []
        for name in CANDIDATE_NAMES
    }


    print()
    print("=" * 260)
    print("BUILD REPRESENTATION MATRICES")
    print("=" * 260)


    for i, sequence in enumerate(
        sequences,
        start=1,
    ):

        reps = build_representations(
            sequence
        )


        for name in CANDIDATE_NAMES:

            matrices[
                name
            ].append(
                reps[
                    name
                ]
            )


        if (
            i
            %
            50
            ==
            0
        ):

            print(
                f"  built "
                f"{i}/"
                f"{len(sequences)}"
            )


    for name in CANDIDATE_NAMES:

        matrices[
            name
        ] = np.stack(
            matrices[
                name
            ],
            axis=0,
        ).astype(
            np.float64
        )


        print(
            f"{name:<28}: "
            f"{matrices[name].shape}"
        )


    print()
    print(
        "Representation build: PASS"
    )


    return matrices


# ============================================================
# Fold standardization
# ============================================================

def standardize_train_test(
    train_x,
    test_x,
):

    mean = np.mean(
        train_x,
        axis=0,
    )


    std = np.std(
        train_x,
        axis=0,
    )


    std = np.where(
        std
        <
        1e-8,
        1.0,
        std,
    )


    train_z = (
        train_x
        -
        mean
    ) / std


    test_z = (
        test_x
        -
        mean
    ) / std


    return (
        train_z,
        test_z,
    )


# ============================================================
# K nearest mean Euclidean distance
# ============================================================

def k_nearest_mean_distance(
    query,
    reference,
    k,
):

    query = np.asarray(
        query,
        dtype=np.float64,
    )


    reference = np.asarray(
        reference,
        dtype=np.float64,
    )


    if len(
        reference
    ) < k:

        raise RuntimeError(
            "KNN reference sample 부족\n"
            f"N={len(reference)}, K={k}"
        )


    q2 = np.sum(
        query
        *
        query,
        axis=1,
        keepdims=True,
    )


    r2 = np.sum(
        reference
        *
        reference,
        axis=1,
        keepdims=True,
    ).T


    distance_squared = (
        q2
        +
        r2
        -
        2.0
        *
        (
            query
            @
            reference.T
        )
    )


    distance_squared = np.maximum(
        distance_squared,
        0.0,
    )


    nearest_squared = np.partition(
        distance_squared,
        kth=k - 1,
        axis=1,
    )[
        :,
        :k
    ]


    nearest_distance = np.sqrt(
        nearest_squared
    )


    return np.mean(
        nearest_distance,
        axis=1,
    )


# ============================================================
# Evaluate one candidate LOCO
# ============================================================

def evaluate_candidate_loco(
    x,
    labels,
    cohorts,
):

    n = len(
        labels
    )


    prediction = np.full(
        n,
        -1,
        dtype=np.int64,
    )


    sign_distance = np.full(
        n,
        np.nan,
        dtype=np.float64,
    )


    nosign_distance = np.full(
        n,
        np.nan,
        dtype=np.float64,
    )


    unique_cohorts = sorted(
        set(
            cohorts
        )
    )


    fold_rows = []


    for held_cohort in unique_cohorts:

        test_mask = (
            cohorts
            ==
            held_cohort
        )


        train_mask = (
            ~test_mask
        )


        train_x = x[
            train_mask
        ]


        test_x = x[
            test_mask
        ]


        train_y = labels[
            train_mask
        ]


        test_y = labels[
            test_mask
        ]


        (
            train_z,
            test_z,
        ) = standardize_train_test(
            train_x,
            test_x,
        )


        sign_reference = train_z[
            train_y
            ==
            SIGN_LABEL
        ]


        nosign_reference = train_z[
            train_y
            ==
            NOSIGN_LABEL
        ]


        d_sign = (
            k_nearest_mean_distance(
                query=test_z,
                reference=sign_reference,
                k=K_NEIGHBORS,
            )
        )


        d_nosign = (
            k_nearest_mean_distance(
                query=test_z,
                reference=nosign_reference,
                k=K_NEIGHBORS,
            )
        )


        pred = np.where(
            d_sign
            <=
            d_nosign,
            SIGN_LABEL,
            NOSIGN_LABEL,
        ).astype(
            np.int64
        )


        test_indices = np.where(
            test_mask
        )[0]


        prediction[
            test_indices
        ] = pred


        sign_distance[
            test_indices
        ] = d_sign


        nosign_distance[
            test_indices
        ] = d_nosign


        # ----------------------------------------------------
        # Fold-specific available-class metrics
        # ----------------------------------------------------

        sign_mask = (
            test_y
            ==
            SIGN_LABEL
        )


        nosign_mask = (
            test_y
            ==
            NOSIGN_LABEL
        )


        sign_count = int(
            np.sum(
                sign_mask
            )
        )


        nosign_count = int(
            np.sum(
                nosign_mask
            )
        )


        if sign_count > 0:

            sign_correct = int(
                np.sum(
                    pred[
                        sign_mask
                    ]
                    ==
                    SIGN_LABEL
                )
            )


            sign_recall = (
                sign_correct
                /
                sign_count
            )


        else:

            sign_correct = 0
            sign_recall = np.nan


        if nosign_count > 0:

            nosign_correct = int(
                np.sum(
                    pred[
                        nosign_mask
                    ]
                    ==
                    NOSIGN_LABEL
                )
            )


            nosign_reject = (
                nosign_correct
                /
                nosign_count
            )


        else:

            nosign_correct = 0
            nosign_reject = np.nan


        if (
            sign_count > 0
            and
            nosign_count > 0
        ):

            fold_balanced = (
                (
                    sign_recall
                    +
                    nosign_reject
                )
                /
                2.0
            )


        else:

            fold_balanced = np.nan


        fold_rows.append(
            {
                "cohort":
                    held_cohort,

                "n":
                    int(
                        len(
                            test_y
                        )
                    ),

                "sign_n":
                    sign_count,

                "nosign_n":
                    nosign_count,

                "sign_correct":
                    sign_correct,

                "nosign_correct":
                    nosign_correct,

                "sign_recall":
                    sign_recall,

                "nosign_reject":
                    nosign_reject,

                "balanced":
                    fold_balanced,
            }
        )


    if np.any(
        prediction
        <
        0
    ):

        raise RuntimeError(
            "OOF prediction 누락"
        )


    if not (
        np.all(
            np.isfinite(
                sign_distance
            )
        )
        and
        np.all(
            np.isfinite(
                nosign_distance
            )
        )
    ):

        raise RuntimeError(
            "OOF distance 누락"
        )


    # ========================================================
    # Overall
    # ========================================================

    sign_mask = (
        labels
        ==
        SIGN_LABEL
    )


    nosign_mask = (
        labels
        ==
        NOSIGN_LABEL
    )


    sign_count = int(
        np.sum(
            sign_mask
        )
    )


    nosign_count = int(
        np.sum(
            nosign_mask
        )
    )


    sign_correct = int(
        np.sum(
            prediction[
                sign_mask
            ]
            ==
            SIGN_LABEL
        )
    )


    nosign_correct = int(
        np.sum(
            prediction[
                nosign_mask
            ]
            ==
            NOSIGN_LABEL
        )
    )


    sign_recall = (
        sign_correct
        /
        sign_count
    )


    nosign_reject = (
        nosign_correct
        /
        nosign_count
    )


    balanced_accuracy = (
        sign_recall
        +
        nosign_reject
    ) / 2.0


    accuracy = float(
        np.mean(
            prediction
            ==
            labels
        )
    )


    return {
        "prediction":
            prediction,

        "sign_distance":
            sign_distance,

        "nosign_distance":
            nosign_distance,

        "margin":
            (
                nosign_distance
                -
                sign_distance
            ),

        "fold_rows":
            fold_rows,

        "sign_count":
            sign_count,

        "sign_correct":
            sign_correct,

        "sign_false_reject":
            (
                sign_count
                -
                sign_correct
            ),

        "sign_recall":
            sign_recall,

        "nosign_count":
            nosign_count,

        "nosign_correct":
            nosign_correct,

        "nosign_false_accept":
            (
                nosign_count
                -
                nosign_correct
            ),

        "nosign_reject":
            nosign_reject,

        "balanced_accuracy":
            balanced_accuracy,

        "accuracy":
            accuracy,
    }


# ============================================================
# Overall summary
# ============================================================

def print_overall_summary(
    results,
):

    print()
    print("=" * 300)
    print("06CD LOCO OVERALL SUMMARY")
    print("=" * 300)


    print(
        f"{'CANDIDATE':<28}"
        f"{'DIM':>6}"
        f"{'SIGN OK':>12}"
        f"{'SIGN FR':>10}"
        f"{'SIGN REC':>11}"
        f"{'NS REJ':>12}"
        f"{'NS FA':>9}"
        f"{'NS RATE':>11}"
        f"{'BAL ACC':>11}"
        f"{'ACC':>10}"
    )


    print("-" * 125)


    for name in CANDIDATE_NAMES:

        r = results[
            name
        ]


        print(
            f"{name:<28}"
            f"{EXPECTED_CANDIDATE_DIMS[name]:>6}"
            f"{r['sign_correct']:>6}/"
            f"{r['sign_count']:<5}"
            f"{r['sign_false_reject']:>9}"
            f"{r['sign_recall']:>11.4f}"
            f"{r['nosign_correct']:>6}/"
            f"{r['nosign_count']:<5}"
            f"{r['nosign_false_accept']:>8}"
            f"{r['nosign_reject']:>11.4f}"
            f"{r['balanced_accuracy']:>11.4f}"
            f"{r['accuracy']:>10.4f}"
        )


# ============================================================
# Positive class breakdown
# ============================================================

def print_sign_class_breakdown(
    development,
    labels,
    results,
):

    sign_class_ids = np.asarray(
        [
            r[
                "sign_class_id"
            ]
            for r in development
        ],
        dtype=np.int64,
    )


    print()
    print("=" * 300)
    print("SIGN CLASS OOF BREAKDOWN")
    print("=" * 300)


    for candidate in CANDIDATE_NAMES:

        prediction = results[
            candidate
        ][
            "prediction"
        ]


        print()
        print(
            candidate
        )


        for class_id in [
            2,
            7,
            8,
            9,
        ]:

            mask = (
                (
                    labels
                    ==
                    SIGN_LABEL
                )

                &

                (
                    sign_class_ids
                    ==
                    class_id
                )
            )


            n = int(
                np.sum(
                    mask
                )
            )


            correct = int(
                np.sum(
                    prediction[
                        mask
                    ]
                    ==
                    SIGN_LABEL
                )
            )


            false_reject = (
                n
                -
                correct
            )


            recall = (
                correct
                /
                n
                if n > 0
                else np.nan
            )


            print(
                f"  {class_text(class_id):<18}"
                f" {correct:>3}/{n:<3}"
                f" | FR={false_reject:<3}"
                f" | recall={recall:.4f}"
            )


# ============================================================
# NO-SIGN subtype breakdown
# ============================================================

def print_nosign_breakdown(
    development,
    labels,
    results,
):

    negative_types = np.asarray(
        [
            r[
                "negative_type"
            ]
            for r in development
        ]
    ).astype(str)


    unique_types = sorted(
        set(
            negative_types[
                labels
                ==
                NOSIGN_LABEL
            ]
        )
    )


    print()
    print("=" * 300)
    print("NO-SIGN TYPE OOF BREAKDOWN")
    print("=" * 300)


    for candidate in CANDIDATE_NAMES:

        prediction = results[
            candidate
        ][
            "prediction"
        ]


        print()
        print(
            candidate
        )


        for negative_type in unique_types:

            mask = (
                (
                    labels
                    ==
                    NOSIGN_LABEL
                )

                &

                (
                    negative_types
                    ==
                    negative_type
                )
            )


            n = int(
                np.sum(
                    mask
                )
            )


            rejected = int(
                np.sum(
                    prediction[
                        mask
                    ]
                    ==
                    NOSIGN_LABEL
                )
            )


            false_accept = (
                n
                -
                rejected
            )


            rate = (
                rejected
                /
                n
                if n > 0
                else np.nan
            )


            print(
                f"  {negative_type:<24}"
                f" {rejected:>3}/{n:<3}"
                f" | FA={false_accept:<3}"
                f" | reject={rate:.4f}"
            )


# ============================================================
# Cohort details
# ============================================================

def metric_text(
    value,
):

    if np.isnan(
        value
    ):

        return "-"

    return f"{value:.4f}"


def print_cohort_details(
    results,
):

    print()
    print("=" * 320)
    print("CAPTURE-COHORT LOCO DETAILS")
    print("=" * 320)


    for candidate in CANDIDATE_NAMES:

        print()
        print(
            candidate
        )


        print(
            f"{'HELD':<10}"
            f"{'N':>6}"
            f"{'SIGN':>8}"
            f"{'S-REC':>10}"
            f"{'NOSIGN':>10}"
            f"{'NS-REJ':>10}"
            f"{'BAL':>10}"
        )


        print("-" * 65)


        for row in results[
            candidate
        ][
            "fold_rows"
        ]:

            print(
                f"{row['cohort']:<10}"
                f"{row['n']:>6}"
                f"{row['sign_n']:>8}"
                f"{metric_text(row['sign_recall']):>10}"
                f"{row['nosign_n']:>10}"
                f"{metric_text(row['nosign_reject']):>10}"
                f"{metric_text(row['balanced']):>10}"
            )


# ============================================================
# Failure details
# ============================================================

def print_failure_details(
    development,
    labels,
    results,
):

    print()
    print("=" * 320)
    print("OOF FAILURE DETAILS")
    print("=" * 320)


    for candidate in CANDIDATE_NAMES:

        pred = results[
            candidate
        ][
            "prediction"
        ]


        d_sign = results[
            candidate
        ][
            "sign_distance"
        ]


        d_nosign = results[
            candidate
        ][
            "nosign_distance"
        ]


        failed = np.where(
            pred
            !=
            labels
        )[0]


        print()
        print(
            candidate
        )


        print(
            "  Total failures:",
            len(
                failed
            ),
        )


        # Prevent enormous console spam.
        for i in failed[
            :80
        ]:

            r = development[
                int(
                    i
                )
            ]


            true_text = (
                class_text(
                    r[
                        "sign_class_id"
                    ]
                )
                if labels[
                    i
                ]
                ==
                SIGN_LABEL
                else (
                    "NO-SIGN/"
                    +
                    r[
                        "negative_type"
                    ]
                )
            )


            predicted_text = (
                "SIGN"
                if pred[
                    i
                ]
                ==
                SIGN_LABEL
                else "NO-SIGN"
            )


            print(
                "    "
                f"cohort={r['capture_cohort']:<6}"
                f" | true={true_text:<24}"
                f" | pred={predicted_text:<7}"
                f" | dSIGN={d_sign[i]:.5f}"
                f" | dNO={d_nosign[i]:.5f}"
                f" | hash={r['hash'][:10]}"
            )


        if len(
            failed
        ) > 80:

            print(
                f"    ... "
                f"{len(failed) - 80} failures omitted"
            )


# ============================================================
# Safety / utility ranking
#
# 선택을 확정하지 않는다.
#
# Development에서:
#
# 1. SIGN false reject가 적은 후보
# 2. 전체 balanced accuracy가 높은 후보
# 3. NO-SIGN reject가 높은 후보
#
# 를 각각 따로 보여준다.
#
# ============================================================

def print_rankings(
    results,
):

    safety = sorted(
        CANDIDATE_NAMES,
        key=lambda name: (
            results[
                name
            ][
                "sign_false_reject"
            ],

            -results[
                name
            ][
                "nosign_reject"
            ],

            EXPECTED_CANDIDATE_DIMS[
                name
            ],
        ),
    )


    balanced = sorted(
        CANDIDATE_NAMES,
        key=lambda name: (
            -results[
                name
            ][
                "balanced_accuracy"
            ],

            results[
                name
            ][
                "sign_false_reject"
            ],

            EXPECTED_CANDIDATE_DIMS[
                name
            ],
        ),
    )


    negative = sorted(
        CANDIDATE_NAMES,
        key=lambda name: (
            -results[
                name
            ][
                "nosign_reject"
            ],

            results[
                name
            ][
                "sign_false_reject"
            ],
        ),
    )


    print()
    print("=" * 280)
    print("DEVELOPMENT CANDIDATE RANKINGS")
    print("=" * 280)


    print()
    print(
        "A. SIGN safety ranking"
    )


    for rank, name in enumerate(
        safety,
        start=1,
    ):

        r = results[
            name
        ]


        print(
            f"  {rank}. {name:<28}"
            f" FR={r['sign_false_reject']:<3}"
            f" NS-reject={r['nosign_reject']:.4f}"
        )


    print()
    print(
        "B. Overall balanced-accuracy ranking"
    )


    for rank, name in enumerate(
        balanced,
        start=1,
    ):

        r = results[
            name
        ]


        print(
            f"  {rank}. {name:<28}"
            f" BAL={r['balanced_accuracy']:.4f}"
            f" FR={r['sign_false_reject']}"
        )


    print()
    print(
        "C. NO-SIGN rejection ranking"
    )


    for rank, name in enumerate(
        negative,
        start=1,
    ):

        r = results[
            name
        ]


        print(
            f"  {rank}. {name:<28}"
            f" NS-reject={r['nosign_reject']:.4f}"
            f" FR={r['sign_false_reject']}"
        )


    return (
        safety,
        balanced,
        negative,
    )


# ============================================================
# Decision support
# ============================================================

def print_decision_support(
    results,
    safety,
    balanced,
):

    safest = safety[
        0
    ]


    best_balanced = balanced[
        0
    ]


    print()
    print("=" * 300)
    print("06CD DEVELOPMENT DECISION SUPPORT")
    print("=" * 300)


    print(
        "Safest candidate:",
        safest,
    )


    print(
        "  SIGN false reject:",
        results[
            safest
        ][
            "sign_false_reject"
        ],
    )


    print(
        "  NO-SIGN reject:",
        f"{results[safest]['nosign_reject']:.4f}",
    )


    print()
    print(
        "Best balanced candidate:",
        best_balanced,
    )


    print(
        "  SIGN false reject:",
        results[
            best_balanced
        ][
            "sign_false_reject"
        ],
    )


    print(
        "  NO-SIGN reject:",
        f"{results[best_balanced]['nosign_reject']:.4f}",
    )


    print(
        "  Balanced accuracy:",
        f"{results[best_balanced]['balanced_accuracy']:.4f}",
    )


    print()
    print(
        "IMPORTANT:"
    )


    print(
        "  ※ 여기서 candidate를 자동 채택하지 않음."
    )


    print(
        "  ※ 결과를 보고 threshold/K를 조정하지 않음."
    )


    print(
        "  ※ representation 성능이 부족하면 "
        "다음 단계에서 다른 모델 구조를 검토."
    )


    print(
        "  ※ 좋은 후보가 있어도 06am을 평가에 사용하지 않음."
    )


    print(
        "  ※ 최종 후보를 고른 뒤에는 "
        "완전히 새로운 webcam fresh validation 필요."
    )


    print(
        "  ※ 06ao runtime은 아직 수정하지 않음."
    )


    print()
    print(
        "Development status:",
        "EVALUATION_COMPLETE_NO_RUNTIME_CHANGE",
    )


# ============================================================
# Save
# ============================================================

def save_result(
    development,
    matrices,
    results,
    safety,
    balanced,
    negative,
):

    max_dim = max(
        EXPECTED_CANDIDATE_DIMS.values()
    )


    padded_features = np.full(
        (
            len(
                CANDIDATE_NAMES
            ),
            len(
                development
            ),
            max_dim,
        ),
        np.nan,
        dtype=np.float32,
    )


    for c_index, name in enumerate(
        CANDIDATE_NAMES
    ):

        dim = (
            EXPECTED_CANDIDATE_DIMS[
                name
            ]
        )


        padded_features[
            c_index,
            :,
            :dim,
        ] = matrices[
            name
        ].astype(
            np.float32
        )


    prediction_matrix = np.stack(
        [
            results[
                name
            ][
                "prediction"
            ]

            for name in CANDIDATE_NAMES
        ],
        axis=1,
    ).astype(
        np.int64
    )


    sign_distance_matrix = np.stack(
        [
            results[
                name
            ][
                "sign_distance"
            ]

            for name in CANDIDATE_NAMES
        ],
        axis=1,
    ).astype(
        np.float32
    )


    nosign_distance_matrix = np.stack(
        [
            results[
                name
            ][
                "nosign_distance"
            ]

            for name in CANDIDATE_NAMES
        ],
        axis=1,
    ).astype(
        np.float32
    )


    np.savez_compressed(
        OUTPUT_PATH,

        # ----------------------------------------------------
        # Identity
        # ----------------------------------------------------

        sample_hashes=np.asarray(
            [
                r[
                    "hash"
                ]
                for r in development
            ]
        ),

        binary_labels=np.asarray(
            [
                r[
                    "binary_label"
                ]
                for r in development
            ],
            dtype=np.int64,
        ),

        sign_class_ids=np.asarray(
            [
                r[
                    "sign_class_id"
                ]
                for r in development
            ],
            dtype=np.int64,
        ),

        negative_types=np.asarray(
            [
                r[
                    "negative_type"
                ]
                for r in development
            ]
        ),

        capture_cohorts=np.asarray(
            [
                r[
                    "capture_cohort"
                ]
                for r in development
            ]
        ),

        canonical_files=np.asarray(
            [
                r[
                    "canonical_file"
                ]
                for r in development
            ]
        ),

        canonical_sample_indices=np.asarray(
            [
                r[
                    "canonical_sample_index"
                ]
                for r in development
            ],
            dtype=np.int64,
        ),

        # ----------------------------------------------------
        # Candidates
        # ----------------------------------------------------

        candidate_names=np.asarray(
            CANDIDATE_NAMES
        ),

        candidate_dims=np.asarray(
            [
                EXPECTED_CANDIDATE_DIMS[
                    name
                ]
                for name in CANDIDATE_NAMES
            ],
            dtype=np.int64,
        ),

        candidate_feature_matrix_padded=(
            padded_features
        ),

        # ----------------------------------------------------
        # OOF
        # ----------------------------------------------------

        candidate_oof_prediction=(
            prediction_matrix
        ),

        candidate_oof_sign_distance=(
            sign_distance_matrix
        ),

        candidate_oof_nosign_distance=(
            nosign_distance_matrix
        ),

        candidate_sign_false_reject=np.asarray(
            [
                results[
                    name
                ][
                    "sign_false_reject"
                ]

                for name in CANDIDATE_NAMES
            ],
            dtype=np.int64,
        ),

        candidate_nosign_false_accept=np.asarray(
            [
                results[
                    name
                ][
                    "nosign_false_accept"
                ]

                for name in CANDIDATE_NAMES
            ],
            dtype=np.int64,
        ),

        candidate_sign_recall=np.asarray(
            [
                results[
                    name
                ][
                    "sign_recall"
                ]

                for name in CANDIDATE_NAMES
            ],
            dtype=np.float32,
        ),

        candidate_nosign_reject=np.asarray(
            [
                results[
                    name
                ][
                    "nosign_reject"
                ]

                for name in CANDIDATE_NAMES
            ],
            dtype=np.float32,
        ),

        candidate_balanced_accuracy=np.asarray(
            [
                results[
                    name
                ][
                    "balanced_accuracy"
                ]

                for name in CANDIDATE_NAMES
            ],
            dtype=np.float32,
        ),

        candidate_accuracy=np.asarray(
            [
                results[
                    name
                ][
                    "accuracy"
                ]

                for name in CANDIDATE_NAMES
            ],
            dtype=np.float32,
        ),

        # ----------------------------------------------------
        # Rankings
        # ----------------------------------------------------

        sign_safety_ranking=np.asarray(
            safety
        ),

        balanced_accuracy_ranking=np.asarray(
            balanced
        ),

        nosign_rejection_ranking=np.asarray(
            negative
        ),

        # ----------------------------------------------------
        # Frozen development policy
        # ----------------------------------------------------

        knn_k=np.asarray(
            [
                K_NEIGHBORS
            ],
            dtype=np.int64,
        ),

        split_strategy=np.asarray(
            [
                "LEAVE_ONE_CAPTURE_COHORT_OUT"
            ]
        ),

        classifier_strategy=np.asarray(
            [
                "CLASS_BALANCED_K3_MEAN_DISTANCE"
            ]
        ),

        development_status=np.asarray(
            [
                "EVALUATION_COMPLETE_NO_RUNTIME_CHANGE"
            ]
        ),

        purpose=np.asarray(
            [
                (
                    "DEVELOPMENT_EVALUATION_"
                    "ONEHAND_SIGN_VS_NOSIGN_BINARY_KNN"
                )
            ]
        ),

        note=np.asarray(
            [
                (
                    "06cd evaluates six fixed class-independent "
                    "temporal representations for a global "
                    "one-hand SIGN vs NO-SIGN verifier. "
                    "Evaluation uses the 06cc hash-deduplicated "
                    "development manifest and leave-one-capture-"
                    "cohort-out OOF predictions. "
                    "K=3 is fixed and SIGN/NO-SIGN nearest "
                    "distances are computed separately to avoid "
                    "class-count bias. "
                    "06am calibration data are excluded. "
                    "No threshold tuning, runtime modification "
                    "or final fresh validation is performed."
                )
            ]
        ),
    )


# ============================================================
# Main
# ============================================================

def main():

    print()
    print("=" * 320)


    print(
        "06cd EVALUATE ONE-HAND "
        "SIGN vs NO-SIGN BINARY KNN - DEVELOPMENT"
    )


    print("=" * 320)


    print(
        FILE_TAG
    )


    print()
    print(
        "IMPORTANT:"
    )


    print(
        "  ※ 노트북에서 실행"
    )


    print(
        "  ※ 웹캠 없음"
    )


    print(
        "  ※ capture-cohort LOCO"
    )


    print(
        "  ※ K=3 고정"
    )


    print(
        "  ※ threshold tuning 없음"
    )


    print(
        "  ※ 06am 사용 안 함"
    )


    print(
        "  ※ runtime 수정 없음"
    )


    # ========================================================
    # Prevent overwrite
    # ========================================================

    if os.path.exists(
        OUTPUT_PATH
    ):

        raise RuntimeError(
            "06cd output이 이미 존재합니다.\n"
            "동일 development 결과를 임의로 다시 만들지 마세요.\n"
            f"{OUTPUT_PATH}"
        )


    # ========================================================
    # Manifest
    # ========================================================

    all_manifest = (
        load_06cc_manifest()
    )


    (
        development,
        calibration,
        unique_cohorts,
    ) = verify_manifest(
        all_manifest
    )


    # ========================================================
    # Materialize exact tensors
    # ========================================================

    sequences = (
        load_development_tensors(
            development
        )
    )


    # ========================================================
    # Representations
    # ========================================================

    matrices = (
        build_candidate_matrices(
            sequences
        )
    )


    # ========================================================
    # Labels / cohorts
    # ========================================================

    labels = np.asarray(
        [
            r[
                "binary_label"
            ]
            for r in development
        ],
        dtype=np.int64,
    )


    cohorts = np.asarray(
        [
            r[
                "capture_cohort"
            ]
            for r in development
        ]
    ).astype(str)


    # ========================================================
    # Evaluate
    # ========================================================

    results = {}


    print()
    print("=" * 260)
    print("RUN CAPTURE-COHORT LOCO")
    print("=" * 260)


    for name in CANDIDATE_NAMES:

        print()
        print(
            "Evaluating:",
            name,
        )


        print(
            "Dimension:",
            matrices[
                name
            ].shape[
                1
            ],
        )


        result = evaluate_candidate_loco(
            x=matrices[
                name
            ],
            labels=labels,
            cohorts=cohorts,
        )


        results[
            name
        ] = result


        print(
            "  SIGN:",
            f"{result['sign_correct']}/"
            f"{result['sign_count']}",
        )


        print(
            "  SIGN false reject:",
            result[
                "sign_false_reject"
            ],
        )


        print(
            "  NO-SIGN reject:",
            f"{result['nosign_correct']}/"
            f"{result['nosign_count']}",
        )


        print(
            "  NO-SIGN false accept:",
            result[
                "nosign_false_accept"
            ],
        )


        print(
            "  Balanced accuracy:",
            f"{result['balanced_accuracy']:.6f}",
        )


    # ========================================================
    # Summaries
    # ========================================================

    print_overall_summary(
        results
    )


    print_sign_class_breakdown(
        development=development,
        labels=labels,
        results=results,
    )


    print_nosign_breakdown(
        development=development,
        labels=labels,
        results=results,
    )


    print_cohort_details(
        results
    )


    print_failure_details(
        development=development,
        labels=labels,
        results=results,
    )


    (
        safety,
        balanced,
        negative,
    ) = print_rankings(
        results
    )


    print_decision_support(
        results=results,
        safety=safety,
        balanced=balanced,
    )


    # ========================================================
    # Save
    # ========================================================

    save_result(
        development=development,
        matrices=matrices,
        results=results,
        safety=safety,
        balanced=balanced,
        negative=negative,
    )


    # ========================================================
    # Complete
    # ========================================================

    print()
    print("=" * 320)


    print(
        "06cd COMPLETE"
    )


    print("=" * 320)


    print(
        "Saved:"
    )


    print(
        OUTPUT_PATH
    )


    print()
    print(
        "다음에 보내줄 부분:"
    )


    print(
        "  1. 06CC MANIFEST INPUT CHECK"
    )


    print(
        "  2. CANONICAL FULL172 MATERIALIZATION CHECK"
    )


    print(
        "  3. BUILD REPRESENTATION MATRICES"
    )


    print(
        "  4. 06CD LOCO OVERALL SUMMARY"
    )


    print(
        "  5. SIGN CLASS OOF BREAKDOWN"
    )


    print(
        "  6. NO-SIGN TYPE OOF BREAKDOWN"
    )


    print(
        "  7. CAPTURE-COHORT LOCO DETAILS"
    )


    print(
        "  8. OOF FAILURE DETAILS"
    )


    print(
        "  9. DEVELOPMENT CANDIDATE RANKINGS"
    )


    print(
        "  10. 06CD DEVELOPMENT DECISION SUPPORT"
    )


    print()
    print(
        "핵심 판단:"
    )


    print(
        "  - 전체 SIGN 267개의 false reject가 얼마나 되는가"
    )


    print(
        "  - 4개 실제 수어 중 특정 class만 심하게 죽는가"
    )


    print(
        "  - STATIC 98 / RANDOM 210을 각각 얼마나 차단하는가"
    )


    print(
        "  - 특정 capture cohort에서만 성능이 무너지는가"
    )


    print(
        "  - Motion만으로 충분한가"
    )


    print(
        "  - Local handshape/temporal 정보를 넣었을 때 "
        "실제로 일반화가 개선되는가"
    )


    print()
    print(
        "※ 이번 결과 보고 K나 threshold를 조정하지 않습니다."
    )


    print(
        "※ 아직 06ao runtime은 수정하지 않습니다."
    )


    print("=" * 320)


if __name__ == "__main__":
    main()