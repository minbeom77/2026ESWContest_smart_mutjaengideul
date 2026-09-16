#include "twohand_classifier.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <utility>
#include <vector>


namespace sign_engine {

namespace {


// ============================================================
// Dimensions
// ============================================================

constexpr std::size_t FRAMES = 80;
constexpr std::size_t LOCAL_DIM = 84;
constexpr std::size_t SLOT_DIM = 42;

constexpr std::size_t LANDMARK_COUNT = 21;

constexpr std::size_t REFERENCE_COUNT = 60;

constexpr double EPS = 1e-8;

constexpr double PI =
    3.141592653589793238462643383279502884;


// ============================================================
// Final 07g candidate IDs
// ============================================================

constexpr std::array<std::int32_t, 9>
TWO_HAND_CANDIDATES = {
    TWOHAND_AIRCON_ID,
    TWOHAND_LOCK_ID,
    TWOHAND_HOT_ID,
    TWOHAND_COLD_ID,
    TWOHAND_RESCUE_ID,
    TWOHAND_SMOKE_ID,
    TWOHAND_THANKS_ID,
    TWOHAND_TEMP_ID,
    TWOHAND_THIRSTY_ID,
};


constexpr std::array<std::int32_t, 3>
HOT_TRIGGER_IDS = {
    TWOHAND_AIRCON_ID,
    TWOHAND_LOCK_ID,
    TWOHAND_COLD_ID,
};


constexpr std::array<std::int32_t, 2>
AC_COLD_CANDIDATES = {
    TWOHAND_AIRCON_ID,
    TWOHAND_COLD_ID,
};


// ============================================================
// Python handshape constants
// ============================================================

constexpr std::array<
    std::array<int, 3>,
    10
>
ANGLE_TRIPLETS = {{
    {{1, 2, 3}},
    {{2, 3, 4}},

    {{5, 6, 7}},
    {{6, 7, 8}},

    {{9, 10, 11}},
    {{10, 11, 12}},

    {{13, 14, 15}},
    {{14, 15, 16}},

    {{17, 18, 19}},
    {{18, 19, 20}},
}};


constexpr std::array<
    std::array<int, 4>,
    5
>
FINGER_CHAINS = {{
    {{1, 2, 3, 4}},
    {{5, 6, 7, 8}},
    {{9, 10, 11, 12}},
    {{13, 14, 15, 16}},
    {{17, 18, 19, 20}},
}};


constexpr std::array<int, 5>
TIP_IDS = {
    4,
    8,
    12,
    16,
    20,
};


constexpr std::array<int, 5>
PALM_IDS = {
    0,
    5,
    9,
    13,
    17,
};


// ============================================================
// Basic point helper
//
// SLOT42 layout:
//
//     x0,y0,x1,y1,...,x20,y20
// ============================================================

float pointX(
    const float* landmarks,
    int id
) {
    return landmarks[
        static_cast<std::size_t>(id) * 2
    ];
}


float pointY(
    const float* landmarks,
    int id
) {
    return landmarks[
        static_cast<std::size_t>(id) * 2 + 1
    ];
}


// ============================================================
// Python:
//
// def point_distance(a, b):
//     return float(np.linalg.norm(a - b))
//
// float32 subtraction / norm behavior is preserved as closely
// as possible before promotion to double.
// ============================================================

double pointDistance(
    float ax,
    float ay,
    float bx,
    float by
) {
    const float dx =
        ax - bx;

    const float dy =
        ay - by;

    const float squared =
        dx * dx
        +
        dy * dy;

    const float distance =
        std::sqrt(
            squared
        );

    return static_cast<double>(
        distance
    );
}


// ============================================================
// Python normalized_angle()
// ============================================================

double normalizedAngle(
    const float* landmarks,
    int a,
    int b,
    int c
) {
    const float ax =
        pointX(landmarks, a);

    const float ay =
        pointY(landmarks, a);


    const float bx =
        pointX(landmarks, b);

    const float by =
        pointY(landmarks, b);


    const float cx =
        pointX(landmarks, c);

    const float cy =
        pointY(landmarks, c);


    const float v1x =
        ax - bx;

    const float v1y =
        ay - by;


    const float v2x =
        cx - bx;

    const float v2y =
        cy - by;


    const float n1_squared =
        v1x * v1x
        +
        v1y * v1y;


    const float n2_squared =
        v2x * v2x
        +
        v2y * v2y;


    const float n1_float =
        std::sqrt(
            n1_squared
        );


    const float n2_float =
        std::sqrt(
            n2_squared
        );


    const double n1 =
        static_cast<double>(
            n1_float
        );


    const double n2 =
        static_cast<double>(
            n2_float
        );


    if (
        n1 < EPS
        ||
        n2 < EPS
    ) {
        return 0.0;
    }


    // np.dot() on float32 arrays produces float32.
    const float dot_float =
        v1x * v2x
        +
        v1y * v2y;


    double cosine =
        static_cast<double>(
            dot_float
        )
        /
        (
            n1 * n2
        );


    if (cosine < -1.0) {
        cosine = -1.0;
    }


    if (cosine > 1.0) {
        cosine = 1.0;
    }


    const double angle =
        std::acos(
            cosine
        );


    return (
        angle / PI
    );
}


// ============================================================
// Python finger_straightness()
// ============================================================

double fingerStraightness(
    const float* landmarks,
    const std::array<int, 4>& chain
) {
    const int first =
        chain.front();

    const int last =
        chain.back();


    const double direct =
        pointDistance(
            pointX(landmarks, first),
            pointY(landmarks, first),

            pointX(landmarks, last),
            pointY(landmarks, last)
        );


    double path = 0.0;


    for (
        std::size_t i = 0;
        i + 1 < chain.size();
        ++i
    ) {
        const int a =
            chain[i];

        const int b =
            chain[i + 1];


        path +=
            pointDistance(
                pointX(landmarks, a),
                pointY(landmarks, a),

                pointX(landmarks, b),
                pointY(landmarks, b)
            );
    }


    if (path < EPS) {
        return 0.0;
    }


    return (
        direct / path
    );
}


// ============================================================
// Python build_single_handshape()
//
// angle         10
// straightness   5
// tip -> palm    5
//
// total         20
// ============================================================

std::array<float, TWOHAND_HANDSHAPE_ONE_DIM>
buildSingleHandshape20(
    const float* landmarks
) {
    std::array<
        float,
        TWOHAND_HANDSHAPE_ONE_DIM
    > descriptor{};


    std::size_t out_index = 0;


    // --------------------------------------------------------
    // Angle 10
    // --------------------------------------------------------

    for (
        const auto& triplet :
        ANGLE_TRIPLETS
    ) {
        descriptor[
            out_index++
        ] =
            static_cast<float>(
                normalizedAngle(
                    landmarks,
                    triplet[0],
                    triplet[1],
                    triplet[2]
                )
            );
    }


    // --------------------------------------------------------
    // Straightness 5
    // --------------------------------------------------------

    for (
        const auto& chain :
        FINGER_CHAINS
    ) {
        descriptor[
            out_index++
        ] =
            static_cast<float>(
                fingerStraightness(
                    landmarks,
                    chain
                )
            );
    }


    // --------------------------------------------------------
    // Palm center
    //
    // Python:
    //
    // palm_center = np.mean(
    //     landmarks[PALM_IDS],
    //     axis=0,
    // )
    //
    // float32 input -> float32 result
    // --------------------------------------------------------

    float palm_x = 0.0f;
    float palm_y = 0.0f;


    for (const int id : PALM_IDS) {
        palm_x +=
            pointX(
                landmarks,
                id
            );

        palm_y +=
            pointY(
                landmarks,
                id
            );
    }


    palm_x /= 5.0f;
    palm_y /= 5.0f;


    // --------------------------------------------------------
    // Tip -> Palm 5
    // --------------------------------------------------------

    for (const int tip_id : TIP_IDS) {
        descriptor[
            out_index++
        ] =
            static_cast<float>(
                pointDistance(
                    pointX(
                        landmarks,
                        tip_id
                    ),

                    pointY(
                        landmarks,
                        tip_id
                    ),

                    palm_x,
                    palm_y
                )
            );
    }


    if (
        out_index !=
        TWOHAND_HANDSHAPE_ONE_DIM
    ) {
        throw std::runtime_error(
            "buildSingleHandshape20: "
            "descriptor size mismatch"
        );
    }


    return descriptor;
}


// ============================================================
// Internal pointer version
//
// local:
//     [80,84]
//
// result:
//     [80,40]
// ============================================================

void buildTwoHandHandshape40Internal(
    const float* local,
    float* output
) {
    for (
        std::size_t frame = 0;
        frame < FRAMES;
        ++frame
    ) {
        const float* frame_local =
            local
            +
            frame * LOCAL_DIM;


        const float* slot_a =
            frame_local;


        const float* slot_b =
            frame_local
            +
            SLOT_DIM;


        const auto hs_a =
            buildSingleHandshape20(
                slot_a
            );


        const auto hs_b =
            buildSingleHandshape20(
                slot_b
            );


        float* frame_output =
            output
            +
            frame
            *
            TWOHAND_HANDSHAPE_DIM;


        for (
            std::size_t i = 0;
            i <
            TWOHAND_HANDSHAPE_ONE_DIM;
            ++i
        ) {
            frame_output[i] =
                hs_a[i];


            frame_output[
                TWOHAND_HANDSHAPE_ONE_DIM
                +
                i
            ] =
                hs_b[i];
        }
    }
}


// ============================================================
// Candidate helper
// ============================================================

template <std::size_t N>
bool containsId(
    const std::array<std::int32_t, N>& values,
    std::int32_t target
) {
    return (
        std::find(
            values.begin(),
            values.end(),
            target
        )
        !=
        values.end()
    );
}


// ============================================================
// RMSE
//
// Python:
//
// sqrt(mean((reference - query) ** 2))
//
// Input / references are float32.
//
// Accumulation is intentionally float to stay aligned with
// NumPy float32 behavior and the already validated C++ KNN.
// ============================================================

float rmseWindow(
    const std::vector<float>& query,
    const std::vector<float>& references,

    std::size_t reference_index,

    std::size_t total_frames,
    std::size_t feature_dim,

    std::size_t start_frame,
    std::size_t frame_count
) {
    float sum_squared =
        0.0f;


    const std::size_t ref_base =
        reference_index
        *
        total_frames
        *
        feature_dim;


    for (
        std::size_t frame = 0;
        frame < frame_count;
        ++frame
    ) {
        const std::size_t source_frame =
            start_frame
            +
            frame;


        const std::size_t query_offset =
            source_frame
            *
            feature_dim;


        const std::size_t ref_offset =
            ref_base
            +
            source_frame
            *
            feature_dim;


        for (
            std::size_t dim = 0;
            dim < feature_dim;
            ++dim
        ) {
            const float difference =
                references[
                    ref_offset + dim
                ]
                -
                query[
                    query_offset + dim
                ];


            sum_squared +=
                difference
                *
                difference;
        }
    }


    const std::size_t value_count =
        frame_count
        *
        feature_dim;


    const float mean_squared =
        sum_squared
        /
        static_cast<float>(
            value_count
        );


    return std::sqrt(
        mean_squared
    );
}


// ============================================================
// Generic class ranking.
//
// Keeps global reference indices.
// ============================================================

template <std::size_t CANDIDATE_COUNT>
std::vector<ClassScore> rankWindow(
    const std::vector<float>& query,
    const std::vector<float>& references,
    const std::vector<std::int32_t>& reference_y,

    std::size_t reference_count,

    std::size_t total_frames,
    std::size_t feature_dim,

    std::size_t start_frame,
    std::size_t frame_count,

    const std::array<
        std::int32_t,
        CANDIDATE_COUNT
    >& candidate_ids,

    std::size_t k
) {
    const std::size_t expected_query =
        total_frames
        *
        feature_dim;


    const std::size_t expected_refs =
        reference_count
        *
        total_frames
        *
        feature_dim;


    if (
        query.size()
        !=
        expected_query
    ) {
        throw std::runtime_error(
            "rankWindow: query size mismatch"
        );
    }


    if (
        references.size()
        !=
        expected_refs
    ) {
        throw std::runtime_error(
            "rankWindow: reference size mismatch"
        );
    }


    if (
        reference_y.size()
        !=
        reference_count
    ) {
        throw std::runtime_error(
            "rankWindow: class id size mismatch"
        );
    }


    if (
        frame_count == 0
        ||
        start_frame + frame_count
        >
        total_frames
    ) {
        throw std::runtime_error(
            "rankWindow: invalid frame range"
        );
    }


    std::vector<ClassScore> ranking;

    ranking.reserve(
        CANDIDATE_COUNT
    );


    for (
        const std::int32_t class_id :
        candidate_ids
    ) {
        std::vector<
            std::pair<
                float,
                std::size_t
            >
        > distances;


        for (
            std::size_t ref_index = 0;
            ref_index < reference_count;
            ++ref_index
        ) {
            if (
                reference_y[
                    ref_index
                ]
                !=
                class_id
            ) {
                continue;
            }


            const float distance =
                rmseWindow(
                    query,
                    references,

                    ref_index,

                    total_frames,
                    feature_dim,

                    start_frame,
                    frame_count
                );


            distances.emplace_back(
                distance,
                ref_index
            );
        }


        if (distances.size() < k) {
            throw std::runtime_error(
                "rankWindow: candidate reference count < k"
            );
        }


        std::sort(
            distances.begin(),
            distances.end(),

            [](
                const auto& a,
                const auto& b
            ) {
                if (a.first != b.first) {
                    return (
                        a.first
                        <
                        b.first
                    );
                }

                return (
                    a.second
                    <
                    b.second
                );
            }
        );


        const std::size_t use_k =
            k;


        float score_sum =
            0.0f;


        ClassScore item;

        item.class_id =
            class_id;


        item.nearest_indices.reserve(
            use_k
        );


        item.nearest_distances.reserve(
            use_k
        );


        for (
            std::size_t i = 0;
            i < use_k;
            ++i
        ) {
            score_sum +=
                distances[i].first;


            item.nearest_distances.push_back(
                distances[i].first
            );


            item.nearest_indices.push_back(
                distances[i].second
            );
        }


        item.score =
            score_sum
            /
            static_cast<float>(
                use_k
            );


        ranking.push_back(
            std::move(item)
        );
    }


    // Python sorted by score.
    // stable_sort preserves candidate order for exact ties.
    std::stable_sort(
        ranking.begin(),
        ranking.end(),

        [](
            const ClassScore& a,
            const ClassScore& b
        ) {
            return (
                a.score
                <
                b.score
            );
        }
    );


    return ranking;
}


// ============================================================
// Margin:
//
// ranking[1].score - ranking[0].score
// ============================================================

float rankingMarginInternal(
    const std::vector<ClassScore>& ranking
) {
    if (ranking.size() < 2) {
        return 0.0f;
    }


    return (
        ranking[1].score
        -
        ranking[0].score
    );
}


// ============================================================
// Score by class id
// ============================================================

float scoreFromRankingInternal(
    const std::vector<ClassScore>& ranking,
    std::int32_t class_id
) {
    for (
        const ClassScore& item :
        ranking
    ) {
        if (
            item.class_id
            ==
            class_id
        ) {
            return item.score;
        }
    }


    throw std::runtime_error(
        "scoreFromRankingInternal: class id missing"
    );
}


// ============================================================
// Build all 60 reference Handshape40:
//
// [60,80,84]
// ->
// [60,80,40]
// ============================================================

std::vector<float> buildReferenceHandshape40(
    const std::vector<float>& references
) {
    const std::size_t expected_size =
        REFERENCE_COUNT
        *
        FRAMES
        *
        LOCAL_DIM;


    if (
        references.size()
        !=
        expected_size
    ) {
        throw std::runtime_error(
            "buildReferenceHandshape40: "
            "reference size mismatch"
        );
    }


    std::vector<float> output(
        REFERENCE_COUNT
        *
        FRAMES
        *
        TWOHAND_HANDSHAPE_DIM,
        0.0f
    );


    for (
        std::size_t reference_index = 0;
        reference_index < REFERENCE_COUNT;
        ++reference_index
    ) {
        const float* input_ptr =
            references.data()
            +
            reference_index
            *
            FRAMES
            *
            LOCAL_DIM;


        float* output_ptr =
            output.data()
            +
            reference_index
            *
            FRAMES
            *
            TWOHAND_HANDSHAPE_DIM;


        buildTwoHandHandshape40Internal(
            input_ptr,
            output_ptr
        );
    }


    return output;
}


}  // namespace


// ============================================================
// Public:
// Local84 -> Handshape40
// ============================================================

std::vector<float> buildTwoHandHandshape40(
    const std::vector<float>& local84
) {
    const std::size_t expected_size =
        FRAMES
        *
        LOCAL_DIM;


    if (
        local84.size()
        !=
        expected_size
    ) {
        throw std::invalid_argument(
            "buildTwoHandHandshape40: "
            "expected [80,84]"
        );
    }


    std::vector<float> output(
        FRAMES
        *
        TWOHAND_HANDSHAPE_DIM,
        0.0f
    );


    buildTwoHandHandshape40Internal(
        local84.data(),
        output.data()
    );


    for (const float value : output) {
        if (!std::isfinite(value)) {
            throw std::runtime_error(
                "buildTwoHandHandshape40: "
                "NaN/Inf"
            );
        }
    }


    return output;
}


// ============================================================
// Final 07g classify_two_hand()
// ============================================================

TwoHandResult classifyTwoHand(
    const std::vector<float>& local84,
    const RuntimeData& runtime_data
) {
    // ========================================================
    // Validation
    // ========================================================

    if (
        local84.size()
        !=
        FRAMES * LOCAL_DIM
    ) {
        throw std::invalid_argument(
            "classifyTwoHand: "
            "local84 must be [80,84]"
        );
    }


    if (
        runtime_data.twohand_local.size()
        !=
        REFERENCE_COUNT
        *
        FRAMES
        *
        LOCAL_DIM
    ) {
        throw std::runtime_error(
            "classifyTwoHand: "
            "twohand_local size mismatch"
        );
    }


    if (
        runtime_data.twohand_class_ids.size()
        !=
        REFERENCE_COUNT
    ) {
        throw std::runtime_error(
            "classifyTwoHand: "
            "twohand_class_ids size mismatch"
        );
    }


    TwoHandResult result;


    // ========================================================
    // Stage 1
    //
    // BASE Local Full80
    // ========================================================

    result.base_ranking =
        rankWindow(
            local84,

            runtime_data.twohand_local,
            runtime_data.twohand_class_ids,

            REFERENCE_COUNT,

            FRAMES,
            LOCAL_DIM,

            0,
            FRAMES,

            TWO_HAND_CANDIDATES,

            TWOHAND_K
        );


    if (
        result.base_ranking.empty()
    ) {
        throw std::runtime_error(
            "classifyTwoHand: "
            "empty base ranking"
        );
    }


    result.base_id =
        result.base_ranking[
            0
        ].class_id;


    result.base_margin =
        rankingMarginInternal(
            result.base_ranking
        );


    result.final_id =
        result.base_id;


    result.stage =
        "TWOHAND_BASE_LOCAL";


    bool hot_rescued =
        false;


    // ========================================================
    // Stage 2
    //
    // HOT handshape rescue
    //
    // Trigger:
    //     base in {0,1,4}
    //
    // Rescue:
    //     hot_score - base_hs_score <= -0.10
    // ========================================================

    if (
        containsId(
            HOT_TRIGGER_IDS,
            result.base_id
        )
    ) {
        result.hot_info.evaluated =
            true;


        const std::vector<float>
        query_handshape =
            buildTwoHandHandshape40(
                local84
            );


        const std::vector<float>
        reference_handshape =
            buildReferenceHandshape40(
                runtime_data.twohand_local
            );


        std::array<std::int32_t, 2>
        hot_candidates = {
            TWOHAND_HOT_ID,
            result.base_id,
        };


        result.hot_info.ranking =
            rankWindow(
                query_handshape,

                reference_handshape,
                runtime_data.twohand_class_ids,

                REFERENCE_COUNT,

                FRAMES,
                TWOHAND_HANDSHAPE_DIM,

                0,
                FRAMES,

                hot_candidates,

                TWOHAND_K
            );


        result.hot_info.hot_score =
            scoreFromRankingInternal(
                result.hot_info.ranking,
                TWOHAND_HOT_ID
            );


        result.hot_info.base_hs_score =
            scoreFromRankingInternal(
                result.hot_info.ranking,
                result.base_id
            );


        result.hot_info.delta =
            result.hot_info.hot_score
            -
            result.hot_info.base_hs_score;


        result.hot_info.threshold =
            TWOHAND_HOT_RESCUE_THRESHOLD;


        result.hot_info.rescued =
            (
                result.hot_info.delta
                <=
                TWOHAND_HOT_RESCUE_THRESHOLD
            );


        hot_rescued =
            result.hot_info.rescued;


        if (hot_rescued) {
            result.final_id =
                TWOHAND_HOT_ID;


            result.stage =
                "TWOHAND_HOT_HANDSHAPE_RESCUE";
        }
    }


    // ========================================================
    // Stage 3
    //
    // 0128 AIRCON / 1248 COLD
    //
    // Only when HOT rescue did NOT happen.
    //
    // Trigger:
    //     Base ranking top2 exactly {0,4}
    //
    // Classification:
    //     Local84 LAST40 [40:80]
    //     candidates {0,4}
    // ========================================================

    if (!hot_rescued) {
        if (
            result.base_ranking.size()
            >=
            2
        ) {
            const std::int32_t top1 =
                result.base_ranking[
                    0
                ].class_id;


            const std::int32_t top2 =
                result.base_ranking[
                    1
                ].class_id;


            const bool ac_cold_pair =
                (
                    (
                        top1 ==
                        TWOHAND_AIRCON_ID

                        &&

                        top2 ==
                        TWOHAND_COLD_ID
                    )

                    ||

                    (
                        top1 ==
                        TWOHAND_COLD_ID

                        &&

                        top2 ==
                        TWOHAND_AIRCON_ID
                    )
                );


            if (ac_cold_pair) {
                result.ac_cold_info.applied =
                    true;


                result.ac_cold_info.ranking =
                    rankWindow(
                        local84,

                        runtime_data.twohand_local,
                        runtime_data.twohand_class_ids,

                        REFERENCE_COUNT,

                        FRAMES,
                        LOCAL_DIM,

                        TWOHAND_LAST40_START,

                        TWOHAND_LAST40_END
                        -
                        TWOHAND_LAST40_START,

                        AC_COLD_CANDIDATES,

                        TWOHAND_K
                    );


                if (
                    result.ac_cold_info.ranking.empty()
                ) {
                    throw std::runtime_error(
                        "classifyTwoHand: "
                        "empty AIRCON/COLD ranking"
                    );
                }


                result.final_id =
                    result.ac_cold_info.ranking[
                        0
                    ].class_id;


                result.ac_cold_info.margin =
                    rankingMarginInternal(
                        result.ac_cold_info.ranking
                    );


                result.stage =
                    "TWOHAND_AIRCON_COLD_LAST40";
            }
        }
    }


    return result;
}


}  // namespace sign_engine
