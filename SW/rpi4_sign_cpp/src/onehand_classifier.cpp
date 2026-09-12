#include "onehand_classifier.hpp"

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// Local84 extraction
//
// Python:
//
// local = feature[:, 0:LOCAL_DIM].copy()
//
// input:
//   [80, 172]
//
// output:
//   [80, 84]
// ============================================================

std::vector<float> extractLocal84(
    const std::vector<float>& feature
) {
    const std::size_t expected_size =
        TARGET_FRAMES *
        FULL_FEATURE_DIM;


    if (feature.size() != expected_size) {
        throw std::runtime_error(
            "extractLocal84: feature size mismatch"
        );
    }


    std::vector<float> local84(
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM
    );


    for (
        std::size_t frame = 0;
        frame < TARGET_FRAMES;
        ++frame
    ) {
        const std::size_t source_offset =
            frame *
            FULL_FEATURE_DIM;

        const std::size_t destination_offset =
            frame *
            LOCAL_FEATURE_DIM;


        for (
            std::size_t feature_index = 0;
            feature_index < LOCAL_FEATURE_DIM;
            ++feature_index
        ) {
            local84[
                destination_offset +
                feature_index
            ] =
                feature[
                    source_offset +
                    feature_index
                ];
        }
    }


    return local84;
}


// ============================================================
// Ranking margin
//
// Python:
//
// if len(ranking) < 2:
//     return 0.0
//
// return ranking[1]["score"] - ranking[0]["score"]
// ============================================================

float rankingMargin(
    const std::vector<ClassScore>& ranking
) {
    if (ranking.size() < 2) {
        return 0.0f;
    }


    return (
        ranking[1].score -
        ranking[0].score
    );
}


// ============================================================
// MID40 query extraction
//
// Python:
//
// query_mid40 = local[20:60, :]
//
// input:
//   [80, 84]
//
// output:
//   [40, 84]
// ============================================================

namespace {

std::vector<float> extractMid40Query(
    const std::vector<float>& local84
) {
    const std::size_t expected_size =
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM;


    if (local84.size() != expected_size) {
        throw std::runtime_error(
            "extractMid40Query: local84 size mismatch"
        );
    }


    std::vector<float> mid40(
        OFF_HURT_MID_FRAMES *
        LOCAL_FEATURE_DIM
    );


    for (
        std::size_t frame = 0;
        frame < OFF_HURT_MID_FRAMES;
        ++frame
    ) {
        const std::size_t source_frame =
            OFF_HURT_MID_START +
            frame;

        const std::size_t source_offset =
            source_frame *
            LOCAL_FEATURE_DIM;

        const std::size_t destination_offset =
            frame *
            LOCAL_FEATURE_DIM;


        for (
            std::size_t feature_index = 0;
            feature_index < LOCAL_FEATURE_DIM;
            ++feature_index
        ) {
            mid40[
                destination_offset +
                feature_index
            ] =
                local84[
                    source_offset +
                    feature_index
                ];
        }
    }


    return mid40;
}


// ============================================================
// MID40 reference extraction
//
// Python:
//
// ref_mid40 =
//     onehand_calibration["local"][
//         :,
//         20:60,
//         :
//     ]
//
// input:
//   [42, 80, 84]
//
// output:
//   [42, 40, 84]
//
// reference 순서는 그대로 유지한다.
// 따라서 class_ids와 reference index도 그대로 대응한다.
// ============================================================

std::vector<float> extractMid40References(
    const std::vector<float>& references
) {
    const std::size_t expected_size =
        ONEHAND_REFERENCE_COUNT *
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM;


    if (references.size() != expected_size) {
        throw std::runtime_error(
            "extractMid40References: reference size mismatch"
        );
    }


    std::vector<float> mid40_references(
        ONEHAND_REFERENCE_COUNT *
        OFF_HURT_MID_FRAMES *
        LOCAL_FEATURE_DIM
    );


    for (
        std::size_t reference_index = 0;
        reference_index < ONEHAND_REFERENCE_COUNT;
        ++reference_index
    ) {
        for (
            std::size_t frame = 0;
            frame < OFF_HURT_MID_FRAMES;
            ++frame
        ) {
            const std::size_t source_frame =
                OFF_HURT_MID_START +
                frame;


            const std::size_t source_offset =
                (
                    reference_index *
                    TARGET_FRAMES *
                    LOCAL_FEATURE_DIM
                )
                +
                (
                    source_frame *
                    LOCAL_FEATURE_DIM
                );


            const std::size_t destination_offset =
                (
                    reference_index *
                    OFF_HURT_MID_FRAMES *
                    LOCAL_FEATURE_DIM
                )
                +
                (
                    frame *
                    LOCAL_FEATURE_DIM
                );


            for (
                std::size_t feature_index = 0;
                feature_index < LOCAL_FEATURE_DIM;
                ++feature_index
            ) {
                mid40_references[
                    destination_offset +
                    feature_index
                ] =
                    references[
                        source_offset +
                        feature_index
                    ];
            }
        }
    }


    return mid40_references;
}


// ============================================================
// Top-2가 정확히 {2, 7}인지 검사
//
// Python:
//
// top2_ids = {
//     base_ranking[0]["class_id"],
//     base_ranking[1]["class_id"],
// }
//
// if top2_ids == OFF_HURT_IDS:
// ============================================================

bool isOffHurtTop2(
    const std::vector<ClassScore>& ranking
) {
    if (ranking.size() < 2) {
        return false;
    }


    const std::int32_t first =
        ranking[0].class_id;

    const std::int32_t second =
        ranking[1].class_id;


    return (
        (
            first == OFF_ID &&
            second == HURT_ID
        )
        ||
        (
            first == HURT_ID &&
            second == OFF_ID
        )
    );
}


}  // namespace


// ============================================================
// Final one-hand classifier
//
// Python classify_one_hand() 포팅
// ============================================================

OneHandResult classifyOneHand(
    const std::vector<float>& local84,
    const RuntimeData& runtime
) {
    const std::size_t expected_local_size =
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM;


    if (local84.size() != expected_local_size) {
        throw std::runtime_error(
            "classifyOneHand: local84 size mismatch"
        );
    }


    if (
        runtime.onehand_local.size() !=
        ONEHAND_REFERENCE_COUNT *
        TARGET_FRAMES *
        LOCAL_FEATURE_DIM
    ) {
        throw std::runtime_error(
            "classifyOneHand: runtime onehand_local size mismatch"
        );
    }


    if (
        runtime.onehand_class_ids.size() !=
        ONEHAND_REFERENCE_COUNT
    ) {
        throw std::runtime_error(
            "classifyOneHand: runtime class id size mismatch"
        );
    }


    // ========================================================
    // Final one-hand candidate IDs
    //
    // 2  = 꺼지다
    // 7  = 아프다
    // 8  = 괜찮다
    // 10 = 점등
    // 11 = 소등
    // 13 = 배고프다
    // ========================================================

    const std::vector<std::int32_t> candidate_ids = {
        2,
        7,
        8,
        10,
        11,
        13
    };


    // ========================================================
    // Base ranking
    //
    // Full80 × Local84
    // K = 3
    // ========================================================

    const std::vector<ClassScore> base_ranking =
        rankClasses(
            local84.data(),
            runtime.onehand_local,
            runtime.onehand_class_ids,
            ONEHAND_REFERENCE_COUNT,
            TARGET_FRAMES *
            LOCAL_FEATURE_DIM,
            candidate_ids,
            KNN_K
        );


    if (base_ranking.empty()) {
        throw std::runtime_error(
            "classifyOneHand: empty base ranking"
        );
    }


    const std::int32_t base_pred =
        base_ranking[0].class_id;


    const float base_margin =
        rankingMargin(
            base_ranking
        );


    // ========================================================
    // Default result
    // ========================================================

    OneHandResult result;


    result.final_id =
        base_pred;


    result.stage =
        "ONEHAND6_WEBCAM_LOCAL_K3";


    result.ranking =
        base_ranking;


    result.margin =
        base_margin;


    result.base_id =
        base_pred;


    result.base_ranking =
        base_ranking;


    result.base_margin =
        base_margin;


    // ========================================================
    // OFF / HURT MID40 tiebreak
    //
    // Base Top-2가 정확히 {2, 7}이면:
    //
    // query  : frame 20:60
    // refs   : frame 20:60
    // classes: {2, 7}
    // K      : 3
    // ========================================================

    if (
        isOffHurtTop2(
            base_ranking
        )
    ) {
        const std::vector<float> query_mid40 =
            extractMid40Query(
                local84
            );


        const std::vector<float> reference_mid40 =
            extractMid40References(
                runtime.onehand_local
            );


        const std::vector<std::int32_t> off_hurt_ids = {
            OFF_ID,
            HURT_ID
        };


        const std::vector<ClassScore> mid40_ranking =
            rankClasses(
                query_mid40.data(),
                reference_mid40,
                runtime.onehand_class_ids,
                ONEHAND_REFERENCE_COUNT,
                OFF_HURT_MID_FRAMES *
                LOCAL_FEATURE_DIM,
                off_hurt_ids,
                KNN_K
            );


        if (mid40_ranking.empty()) {
            throw std::runtime_error(
                "classifyOneHand: empty MID40 ranking"
            );
        }


        result.final_id =
            mid40_ranking[0].class_id;


        result.stage =
            "ONEHAND_OFF_HURT_MID40_K3";


        result.off_hurt_info.applied =
            true;


        result.off_hurt_info.ranking =
            mid40_ranking;


        result.off_hurt_info.margin =
            rankingMargin(
                mid40_ranking
            );


        result.off_hurt_info.start =
            OFF_HURT_MID_START;


        result.off_hurt_info.end =
            OFF_HURT_MID_END;
    }


    return result;
}


}  // namespace sign_engine