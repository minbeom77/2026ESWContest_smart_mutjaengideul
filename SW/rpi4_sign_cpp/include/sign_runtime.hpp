#pragma once

#include "c4_gate.hpp"
#include "feature_v3.hpp"
#include "onehand_classifier.hpp"
#include "runtime_data.hpp"
#include "sign_classifier.hpp"
#include "sign_types.hpp"
#include "twohand_classifier.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// Frozen 06u / 07g routing constants
// ============================================================

constexpr double SIGN_RUNTIME_BOTH_RATIO_THRESHOLD =
    0.35;

constexpr std::size_t SIGN_RUNTIME_MIN_ACCEPTED_FRAMES =
    20;


// ============================================================
// Runtime status
//
// Frozen 07g behavior:
//
// INVALID INPUT
//   -> prediction하지 않음
//
// CLASSIFICATION ERROR
//   -> prediction 폐기
//
// SUCCESS
//   -> 정상 결과 또는 C4 NO-SIGN reject
// ============================================================

enum class SignRuntimeStatus {
    Success,
    InvalidInput,
    ClassificationError,
};


// ============================================================
// Production runtime result
// ============================================================

struct SignRecognitionResult {
    SignRuntimeStatus status =
        SignRuntimeStatus::InvalidInput;

    bool valid =
        false;


    // --------------------------------------------------------
    // Final prediction
    //
    // C4 NO-SIGN reject:
    //   final_id = -1
    //   is_nosign = true
    //
    // Normal sign:
    //   final_id = 0~14
    // --------------------------------------------------------

    std::int32_t final_id =
        -1;

    std::string stage;

    bool is_nosign =
        false;


    // --------------------------------------------------------
    // Final usage
    //
    // TEMP rescue success:
    //   original one_hand -> final TwoHand
    // --------------------------------------------------------

    UsageType usage_type =
        UsageType::Invalid;


    // --------------------------------------------------------
    // Original recording / routing
    // --------------------------------------------------------

    RecordingStats recording_stats;

    std::string source_mode;

    std::size_t selected_frames =
        0;


    // --------------------------------------------------------
    // Original Feature V3
    // --------------------------------------------------------

    FeatureV3Result raw_feature;

    std::vector<float> feature80;

    std::vector<float> local84;


    // --------------------------------------------------------
    // C4
    //
    // Only evaluated for original one-hand routing.
    // --------------------------------------------------------

    bool c4_evaluated =
        false;

    C4GateResult c4_gate;


    // --------------------------------------------------------
    // One-hand result
    // --------------------------------------------------------

    bool onehand_ran =
        false;

    OneHandResult onehand_result;


    // --------------------------------------------------------
    // Two-hand result
    //
    // Normal two-hand or successful TEMP rescue.
    // --------------------------------------------------------

    bool twohand_ran =
        false;

    TwoHandResult twohand_result;


    // --------------------------------------------------------
    // TEMP overlap rescue diagnostics
    // --------------------------------------------------------

    bool temp_checked =
        false;

    TempOverlapRescueResult temp_rescue;


    // --------------------------------------------------------
    // Failure diagnostic
    //
    // status != Success일 때 사용.
    // --------------------------------------------------------

    std::string error;
};


// ============================================================
// Production entry API
//
// Frozen:
//
// frames
//   -> 06u routing / Feature V3
//   -> Local84
//   -> one_hand:
//        C4
//          SIGN    -> classifyOneHand
//          NO-SIGN -> reject + TEMP rescue
//
//      two_hand:
//        classifyTwoHand
//
// Returns:
//   valid=true
//     normal sign OR valid NO-SIGN reject
//
//   valid=false
//     invalid input / classification error
// ============================================================

SignRecognitionResult classifyRecording(
    const RecordingFrames& frames,
    const RuntimeData& runtime
);


}  // namespace sign_engine