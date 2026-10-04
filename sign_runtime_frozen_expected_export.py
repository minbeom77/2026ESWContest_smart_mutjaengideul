import contextlib
import importlib.util
import io
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

OUTPUT_DIR = (
    ROOT
    / "SW"
    / "rpi4_sign_cpp"
    / "tests"
    / "fixtures"
    / "sign_runtime_routes_frozen"
)


TRIM_START = 21
TRIM_END = 107

EXPECTED_JSON_COUNT = 115
EXPECTED_BOTH_COUNT = 87

ONEHAND_SIGN_EXTRA = 162
TEMP_POSITIVE_EXTRA = 247

NOSIGN_SEARCH_START = 349
NOSIGN_SEARCH_END = 1000

TEMP_RATIO_THRESHOLD = 0.20
TEMP_MIN_BOTH_FRAMES = 15


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
    people = data.get(
        "people"
    )

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

        if not isinstance(
            people[0],
            dict,
        ):
            raise RuntimeError(
                f"{file_name}: people[0] invalid"
            )

        return people[0]

    raise RuntimeError(
        f"{file_name}: invalid people type"
    )


def parse_hand(
    values,
    file_name,
    hand_name,
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
            f"{hand_name} shape="
            f"{values.shape}"
        )

    xyz = values.reshape(
        21,
        3,
    )

    return np.ascontiguousarray(
        xyz[:, 0:2],
        dtype=np.float32,
    )


def load_real01():
    paths = sorted(
        RAW_DIR.glob(
            "*_keypoints.json"
        )
    )

    if (
        len(paths)
        !=
        EXPECTED_JSON_COUNT
    ):
        raise RuntimeError(
            f"JSON count="
            f"{len(paths)}, "
            f"expected="
            f"{EXPECTED_JSON_COUNT}"
        )

    paths = paths[
        TRIM_START:
        TRIM_END + 1
    ]

    if (
        len(paths)
        !=
        EXPECTED_BOTH_COUNT
    ):
        raise RuntimeError(
            "REAL01 trim count mismatch"
        )

    left_sequence = []
    right_sequence = []

    for path in paths:
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

        left_sequence.append(
            parse_hand(
                person[
                    "hand_left_keypoints_2d"
                ],
                path.name,
                "LEFT",
            )
        )

        right_sequence.append(
            parse_hand(
                person[
                    "hand_right_keypoints_2d"
                ],
                path.name,
                "RIGHT",
            )
        )

    return (
        np.ascontiguousarray(
            np.stack(
                left_sequence,
                axis=0,
            ),
            dtype=np.float32,
        ),
        np.ascontiguousarray(
            np.stack(
                right_sequence,
                axis=0,
            ),
            dtype=np.float32,
        ),
    )


def build_recording(
    left_sequence,
    right_sequence,
    extra_right_only,
):
    frames = []

    for index in range(
        EXPECTED_BOTH_COUNT
    ):
        frames.append(
            (
                left_sequence[
                    index
                ].copy(),
                right_sequence[
                    index
                ].copy(),
            )
        )

    for index in range(
        extra_right_only
    ):
        source_index = (
            index
            %
            EXPECTED_BOTH_COUNT
        )

        frames.append(
            (
                None,
                right_sequence[
                    source_index
                ].copy(),
            )
        )

    return frames


def run_frozen_case(
    frozen,
    frames,
    c4_model,
    onehand_calibration,
    aihub,
):
    # ========================================================
    # Frozen Feature / routing
    # ========================================================

    feature_info = (
        frozen.u.build_webcam_feature(
            frames
        )
    )

    (
        feature,
        usage_type,
    ) = (
        frozen.validate_webcam_feature(
            feature_info
        )
    )

    feature = np.ascontiguousarray(
        feature,
        dtype=np.float32,
    )

    local = np.ascontiguousarray(
        feature[
            :,
            0:frozen.LOCAL_DIM,
        ],
        dtype=np.float32,
    )


    total_frames = len(
        frames
    )

    left_count = sum(
        left is not None
        for left, right
        in frames
    )

    right_count = sum(
        right is not None
        for left, right
        in frames
    )

    both_count = sum(
        (
            left is not None
            and
            right is not None
        )
        for left, right
        in frames
    )

    both_ratio = (
        both_count
        /
        total_frames
    )


    result = {
        "valid":
            True,

        "final_id":
            -1,

        "stage":
            "",

        "is_nosign":
            False,

        "usage":
            usage_type,

        "source_mode":
            str(
                feature_info.get(
                    "source_mode",
                    "",
                )
            ),

        "selected_frames":
            int(
                feature_info.get(
                    "selected_frames",
                    0,
                )
            ),

        "total":
            total_frames,

        "left":
            left_count,

        "right":
            right_count,

        "both":
            both_count,

        "both_ratio":
            both_ratio,

        "c4_evaluated":
            False,

        "c4_prediction":
            -1,

        "d_sign":
            0.0,

        "d_nosign":
            0.0,

        "c4_margin":
            0.0,

        "onehand_ran":
            False,

        "twohand_ran":
            False,

        "temp_checked":
            False,

        "temp_eligible":
            False,

        "temp_rescued":
            False,
    }


    # ========================================================
    # ONE HAND
    # ========================================================

    if (
        usage_type
        ==
        "one_hand"
    ):
        gate_result = (
            frozen.classify_onehand_c4_gate(
                feature=feature,
                c4_model=c4_model,
            )
        )

        result[
            "c4_evaluated"
        ] = True

        result[
            "c4_prediction"
        ] = int(
            gate_result[
                "prediction"
            ]
        )

        result[
            "d_sign"
        ] = float(
            gate_result[
                "d_sign"
            ]
        )

        result[
            "d_nosign"
        ] = float(
            gate_result[
                "d_nosign"
            ]
        )

        result[
            "c4_margin"
        ] = float(
            gate_result[
                "margin_nosign_minus_sign"
            ]
        )


        # ====================================================
        # C4 NO-SIGN
        # ====================================================

        if (
            gate_result[
                "prediction"
            ]
            ==
            frozen.C4_NOSIGN_LABEL
        ):
            result[
                "final_id"
            ] = -1

            result[
                "stage"
            ] = (
                "ONEHAND_C4_NOSIGN_REJECT"
            )

            result[
                "is_nosign"
            ] = True

            result[
                "temp_checked"
            ] = True


            both_frames = [
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


            can_try = (
                both_ratio
                >=
                TEMP_RATIO_THRESHOLD

                and

                len(
                    both_frames
                )
                >=
                TEMP_MIN_BOTH_FRAMES
            )


            result[
                "temp_eligible"
            ] = bool(
                can_try
            )


            if can_try:
                try:
                    rescue_feature_info = (
                        frozen.u.build_webcam_feature(
                            both_frames
                        )
                    )

                    (
                        rescue_feature,
                        rescue_usage,
                    ) = (
                        frozen.validate_webcam_feature(
                            rescue_feature_info
                        )
                    )

                    if (
                        rescue_usage
                        !=
                        "two_hand"
                    ):
                        raise RuntimeError(
                            "TEMP rescue usage != two_hand"
                        )


                    rescue_local = (
                        rescue_feature[
                            :,
                            0:frozen.LOCAL_DIM,
                        ]
                    )


                    rescue_result = (
                        frozen.classify_two_hand(
                            local=rescue_local,
                            aihub=aihub,
                        )
                    )


                    rescue_final_id = int(
                        rescue_result[
                            "final_id"
                        ]
                    )


                    if (
                        rescue_final_id
                        ==
                        frozen.TEMP_ID
                    ):
                        result[
                            "final_id"
                        ] = rescue_final_id

                        result[
                            "stage"
                        ] = (
                            "TWOHAND_TEMP_"
                            "OVERLAP_RESCUE"
                        )

                        result[
                            "is_nosign"
                        ] = False

                        result[
                            "usage"
                        ] = "two_hand"

                        result[
                            "twohand_ran"
                        ] = True

                        result[
                            "temp_rescued"
                        ] = True

                except Exception:
                    # Frozen:
                    # 기존 C4 NO-SIGN 결과 유지
                    pass


        # ====================================================
        # C4 SIGN
        # ====================================================

        else:
            onehand_result = (
                frozen.classify_one_hand(
                    local=local,
                    onehand_calibration=(
                        onehand_calibration
                    ),
                )
            )


            result[
                "final_id"
            ] = int(
                onehand_result[
                    "final_id"
                ]
            )

            result[
                "stage"
            ] = str(
                onehand_result[
                    "stage"
                ]
            )

            result[
                "is_nosign"
            ] = False

            result[
                "onehand_ran"
            ] = True


    # ========================================================
    # TWO HAND
    # ========================================================

    elif (
        usage_type
        ==
        "two_hand"
    ):
        twohand_result = (
            frozen.classify_two_hand(
                local=local,
                aihub=aihub,
            )
        )


        result[
            "final_id"
        ] = int(
            twohand_result[
                "final_id"
            ]
        )

        result[
            "stage"
        ] = str(
            twohand_result[
                "stage"
            ]
        )

        result[
            "is_nosign"
        ] = False

        result[
            "twohand_ran"
        ] = True


    else:
        raise RuntimeError(
            f"Unexpected usage_type: "
            f"{usage_type}"
        )


    return result


def run_silent(
    frozen,
    frames,
    c4_model,
    onehand_calibration,
    aihub,
):
    buffer = io.StringIO()

    with contextlib.redirect_stdout(
        buffer
    ):
        return run_frozen_case(
            frozen,
            frames,
            c4_model,
            onehand_calibration,
            aihub,
        )


def bool_int(
    value,
):
    return 1 if value else 0


def save_cases(
    cases,
):
    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    header = [
        "name",
        "extra_right_only",
        "valid",
        "final_id",
        "stage",
        "is_nosign",
        "usage",
        "source_mode",
        "selected_frames",
        "total",
        "left",
        "right",
        "both",
        "both_ratio",
        "c4_evaluated",
        "c4_prediction",
        "d_sign",
        "d_nosign",
        "c4_margin",
        "onehand_ran",
        "twohand_ran",
        "temp_checked",
        "temp_eligible",
        "temp_rescued",
    ]


    rows = [
        "\t".join(
            header
        )
    ]


    for case in cases:
        r = case[
            "result"
        ]

        values = [
            case[
                "name"
            ],

            str(
                case[
                    "extra"
                ]
            ),

            str(
                bool_int(
                    r[
                        "valid"
                    ]
                )
            ),

            str(
                r[
                    "final_id"
                ]
            ),

            r[
                "stage"
            ],

            str(
                bool_int(
                    r[
                        "is_nosign"
                    ]
                )
            ),

            r[
                "usage"
            ],

            r[
                "source_mode"
            ],

            str(
                r[
                    "selected_frames"
                ]
            ),

            str(
                r[
                    "total"
                ]
            ),

            str(
                r[
                    "left"
                ]
            ),

            str(
                r[
                    "right"
                ]
            ),

            str(
                r[
                    "both"
                ]
            ),

            f"{r['both_ratio']:.17g}",

            str(
                bool_int(
                    r[
                        "c4_evaluated"
                    ]
                )
            ),

            str(
                r[
                    "c4_prediction"
                ]
            ),

            f"{r['d_sign']:.17g}",

            f"{r['d_nosign']:.17g}",

            f"{r['c4_margin']:.17g}",

            str(
                bool_int(
                    r[
                        "onehand_ran"
                    ]
                )
            ),

            str(
                bool_int(
                    r[
                        "twohand_ran"
                    ]
                )
            ),

            str(
                bool_int(
                    r[
                        "temp_checked"
                    ]
                )
            ),

            str(
                bool_int(
                    r[
                        "temp_eligible"
                    ]
                )
            ),

            str(
                bool_int(
                    r[
                        "temp_rescued"
                    ]
                )
            ),
        ]


        rows.append(
            "\t".join(
                values
            )
        )


    (
        OUTPUT_DIR
        / "expected_cases.tsv"
    ).write_text(
        "\n".join(
            rows
        )
        +
        "\n",
        encoding="utf-8",
    )


def print_case(
    case,
):
    r = case[
        "result"
    ]

    print(
        "----------------------------------------"
    )

    print(
        case[
            "name"
        ]
    )

    print(
        "----------------------------------------"
    )

    print(
        "extra RIGHT_ONLY :",
        case[
            "extra"
        ],
    )

    print(
        "total            :",
        r[
            "total"
        ],
    )

    print(
        "both ratio       :",
        f"{r['both_ratio']:.12f}",
    )

    print(
        "source mode      :",
        r[
            "source_mode"
        ],
    )

    print(
        "usage            :",
        r[
            "usage"
        ],
    )

    print(
        "C4 evaluated     :",
        r[
            "c4_evaluated"
        ],
    )

    if (
        r[
            "c4_evaluated"
        ]
    ):
        print(
            "C4 prediction    :",
            r[
                "c4_prediction"
            ],
        )

        print(
            "d_sign           :",
            f"{r['d_sign']:.12f}",
        )

        print(
            "d_nosign         :",
            f"{r['d_nosign']:.12f}",
        )

    print(
        "onehand ran      :",
        r[
            "onehand_ran"
        ],
    )

    print(
        "twohand ran      :",
        r[
            "twohand_ran"
        ],
    )

    print(
        "TEMP checked     :",
        r[
            "temp_checked"
        ],
    )

    print(
        "TEMP eligible    :",
        r[
            "temp_eligible"
        ],
    )

    print(
        "TEMP rescued     :",
        r[
            "temp_rescued"
        ],
    )

    print(
        "final_id         :",
        r[
            "final_id"
        ],
    )

    print(
        "stage            :",
        r[
            "stage"
        ],
    )

    print(
        "is_nosign        :",
        r[
            "is_nosign"
        ],
    )

    print()


def main():
    print(
        "=" * 90
    )

    print(
        "SIGN RUNTIME FROZEN EXPECTED EXPORT"
    )

    print(
        "=" * 90
    )


    frozen = load_frozen_module()


    buffer = io.StringIO()

    with contextlib.redirect_stdout(
        buffer
    ):
        c4_model = (
            frozen.load_frozen_c4_gate()
        )

        onehand_calibration = (
            frozen.load_onehand_calibration()
        )

        aihub = (
            frozen.load_aihub_train_references()
        )


    (
        left_sequence,
        right_sequence,
    ) = load_real01()


    # ========================================================
    # CASE 1: NORMAL TWO-HAND
    # ========================================================

    normal_twohand_frames = (
        build_recording(
            left_sequence,
            right_sequence,
            0,
        )
    )


    normal_twohand = (
        run_silent(
            frozen,
            normal_twohand_frames,
            c4_model,
            onehand_calibration,
            aihub,
        )
    )


    if (
        normal_twohand[
            "usage"
        ]
        !=
        "two_hand"
        or
        normal_twohand[
            "final_id"
        ]
        !=
        12
        or
        normal_twohand[
            "is_nosign"
        ]
    ):
        raise RuntimeError(
            "NORMAL_TWOHAND expected condition failed"
        )


    # ========================================================
    # CASE 2: ONE-HAND C4 SIGN
    # ========================================================

    onehand_sign_frames = (
        build_recording(
            left_sequence,
            right_sequence,
            ONEHAND_SIGN_EXTRA,
        )
    )


    onehand_sign = (
        run_silent(
            frozen,
            onehand_sign_frames,
            c4_model,
            onehand_calibration,
            aihub,
        )
    )


    if (
        onehand_sign[
            "c4_prediction"
        ]
        !=
        frozen.C4_SIGN_LABEL
        or
        not onehand_sign[
            "onehand_ran"
        ]
        or
        onehand_sign[
            "is_nosign"
        ]
    ):
        raise RuntimeError(
            "ONEHAND_SIGN expected condition failed"
        )


    # ========================================================
    # CASE 3: C4 NO-SIGN REJECT with TEMP ineligible
    #
    # Search only below TEMP ratio threshold.
    # Stop at first actual frozen NO-SIGN.
    # ========================================================

    nosign_extra = None
    nosign_reject = None


    for extra in range(
        NOSIGN_SEARCH_START,
        NOSIGN_SEARCH_END + 1,
    ):
        frames = (
            build_recording(
                left_sequence,
                right_sequence,
                extra,
            )
        )


        ratio = (
            EXPECTED_BOTH_COUNT
            /
            len(
                frames
            )
        )


        if (
            ratio
            >=
            TEMP_RATIO_THRESHOLD
        ):
            continue


        candidate = (
            run_silent(
                frozen,
                frames,
                c4_model,
                onehand_calibration,
                aihub,
            )
        )


        if (
            candidate[
                "c4_evaluated"
            ]
            and
            candidate[
                "c4_prediction"
            ]
            ==
            frozen.C4_NOSIGN_LABEL
            and
            candidate[
                "is_nosign"
            ]
            and
            not candidate[
                "temp_eligible"
            ]
        ):
            nosign_extra = extra
            nosign_reject = candidate

            break


    if (
        nosign_extra is None
        or
        nosign_reject is None
    ):
        raise RuntimeError(
            "TEMP-ineligible C4 NO-SIGN candidate 없음"
        )


    # ========================================================
    # CASE 4: TEMP POSITIVE
    # ========================================================

    temp_positive_frames = (
        build_recording(
            left_sequence,
            right_sequence,
            TEMP_POSITIVE_EXTRA,
        )
    )


    temp_positive = (
        run_silent(
            frozen,
            temp_positive_frames,
            c4_model,
            onehand_calibration,
            aihub,
        )
    )


    if (
        temp_positive[
            "c4_prediction"
        ]
        !=
        frozen.C4_NOSIGN_LABEL
        or
        not temp_positive[
            "temp_eligible"
        ]
        or
        not temp_positive[
            "temp_rescued"
        ]
        or
        temp_positive[
            "final_id"
        ]
        !=
        12
        or
        temp_positive[
            "stage"
        ]
        !=
        "TWOHAND_TEMP_OVERLAP_RESCUE"
        or
        temp_positive[
            "is_nosign"
        ]
    ):
        raise RuntimeError(
            "TEMP_POSITIVE expected condition failed"
        )


    cases = [
        {
            "name":
                "NORMAL_TWOHAND",

            "extra":
                0,

            "result":
                normal_twohand,
        },

        {
            "name":
                "ONEHAND_SIGN",

            "extra":
                ONEHAND_SIGN_EXTRA,

            "result":
                onehand_sign,
        },

        {
            "name":
                "C4_NOSIGN_REJECT",

            "extra":
                nosign_extra,

            "result":
                nosign_reject,
        },

        {
            "name":
                "TEMP_POSITIVE",

            "extra":
                TEMP_POSITIVE_EXTRA,

            "result":
                temp_positive,
        },
    ]


    # ========================================================
    # Export raw landmarks too, so C++ production regression
    # uses the exact same REAL01 source.
    # ========================================================

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )


    left_sequence.tofile(
        OUTPUT_DIR
        / "input_real01_left_87x21x2.bin"
    )

    right_sequence.tofile(
        OUTPUT_DIR
        / "input_real01_right_87x21x2.bin"
    )


    save_cases(
        cases
    )


    print()
    print(
        "FROZEN ROUTE RESULTS"
    )

    print()


    for case in cases:
        print_case(
            case
        )


    print(
        "Output:",
        OUTPUT_DIR,
    )


    print()
    print(
        "=" * 90
    )

    print(
        "SIGN RUNTIME FROZEN EXPECTED EXPORT PASS"
    )

    print(
        "=" * 90
    )


if __name__ == "__main__":
    main()