#pragma once

#include <array>
#include <cstddef>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// Feature V3 constants
// ============================================================

constexpr double FEATURE_V3_EPS = 1e-8;

constexpr std::size_t HAND_LANDMARK_COUNT = 21;

constexpr std::size_t HAND_SCALE_LANDMARK_COUNT = 4;

constexpr std::array<std::size_t, HAND_SCALE_LANDMARK_COUNT>
HAND_SCALE_LANDMARKS = {
    5,
    9,
    13,
    17
};


constexpr std::size_t FEATURE_V3_SLOT_DIM = 42;

constexpr std::size_t FEATURE_V3_LOCAL_DIM = 84;

constexpr std::size_t FEATURE_V3_PAIR_DIM = 84;

constexpr std::size_t FEATURE_V3_TRAJECTORY_DIM = 2;

constexpr std::size_t FEATURE_V3_USAGE_MASK_DIM = 2;

constexpr std::size_t FEATURE_V3_DIM = 172;


// ============================================================
// Python hand_features.py defaults
// ============================================================

constexpr double DEFAULT_ONE_HAND_RATIO_THRESHOLD =
    0.20;

constexpr double DEFAULT_NO_MOTION_THRESHOLD =
    3.0;

constexpr std::size_t DEFAULT_ANCHOR_FRAME_COUNT =
    5;


// ============================================================
// Basic landmark types
//
// 입력:
//   frame × 21 × XY
//
// 현재 Feature V3에서는 Z를 사용하지 않는다.
// ============================================================

struct Point2f {
    float x = 0.0f;
    float y = 0.0f;
};


struct HandLandmarks {
    std::array<Point2f, HAND_LANDMARK_COUNT> points{};
};


using HandSequence =
    std::vector<HandLandmarks>;


// ============================================================
// Usage enums
// ============================================================

enum class UsageType {
    Invalid,
    OneHand,
    TwoHand
};


enum class ActiveHand {
    None,
    Left,
    Right,
    Both
};


enum class CanonicalHand {
    Left,
    Right
};


// ============================================================
// Usage result
//
// Python detect_hand_usage() 대응
// ============================================================

struct HandUsage {
    UsageType type =
        UsageType::Invalid;

    ActiveHand active_hand =
        ActiveHand::None;

    double left_score =
        0.0;

    double right_score =
        0.0;

    double ratio =
        1.0;

    // Feature V3 slot usage mask
    //
    // invalid:
    //   [0, 0]
    //
    // one-hand:
    //   [1, 0]
    //
    // two-hand:
    //   [1, 1]
    std::array<float, 2> usage_mask = {
        0.0f,
        0.0f
    };

    // 실제 physical LEFT / RIGHT detection
    std::array<float, 2> detected_mask = {
        0.0f,
        0.0f
    };
};


// ============================================================
// Feature V3 options
//
// hand_features.py 기본값을 그대로 보존.
//
// 중요:
// 최종 07g webcam runtime에서는
// no_motion_threshold = 0.0 을 사용한다.
// ============================================================

struct FeatureV3Options {
    double one_hand_ratio_threshold =
        DEFAULT_ONE_HAND_RATIO_THRESHOLD;

    double no_motion_threshold =
        DEFAULT_NO_MOTION_THRESHOLD;

    std::size_t anchor_frame_count =
        DEFAULT_ANCHOR_FRAME_COUNT;

    CanonicalHand canonical_hand =
        CanonicalHand::Right;
};


// ============================================================
// Feature V3 result
// ============================================================

struct FeatureV3Result {
    bool valid = false;

    std::size_t frame_count = 0;

    HandUsage usage;


    // --------------------------------------------------------
    // Final model input
    //
    // flat row-major:
    //
    // [frame_count, 172]
    //
    // layout:
    //
    // 0:42     SLOT A Local
    // 42:84    SLOT B Local
    // 84:126   Pair A
    // 126:168  Pair B
    // 168:170  Trajectory XY
    // 170:172  Usage Mask
    // --------------------------------------------------------

    std::vector<float> features;


    // --------------------------------------------------------
    // Debug / regression blocks
    // --------------------------------------------------------

    // [T, 42]
    std::vector<float> slot_a_local;

    // [T, 42]
    std::vector<float> slot_b_local;

    // [T, 42]
    std::vector<float> pair_a;

    // [T, 42]
    std::vector<float> pair_b;

    // [T, 2]
    std::vector<float> trajectory;

    double trajectory_scale =
        1.0;


    // Physical hand local
    //
    // [T, 42]
    std::vector<float> physical_left_local;

    // [T, 42]
    std::vector<float> physical_right_local;


    CanonicalHand canonical_hand =
        CanonicalHand::Right;

    bool canonicalized =
        false;
};


// ============================================================
// String helpers
// ============================================================

std::string usageTypeToString(
    UsageType type
);


std::string activeHandToString(
    ActiveHand hand
);


// ============================================================
// Missing sequence check
//
// Python _is_missing_sequence() 대응
// ============================================================

bool isMissingSequence(
    const HandSequence* sequence
);


// ============================================================
// Hand scale
//
// Python hand_scale()
//
// wrist = landmark 0
//
// scale landmarks:
//   5, 9, 13, 17
//
// 각 landmark와 wrist의 Euclidean distance
// 유효 distance의 mean
// ============================================================

double handScale(
    const HandLandmarks& hand
);


// ============================================================
// Single-hand sequence scale
//
// Python single_hand_sequence_scale()
//
// 각 frame handScale()
// 유효 scale의 median
//
// 유효 scale이 없으면 1.0
// ============================================================

double singleHandSequenceScale(
    const HandSequence& hand_sequence
);


// ============================================================
// Bilateral sequence scale
//
// Python sequence_scale()
//
// left + right 모든 유효 frame의 handScale()
// median
//
// make_pair_relative_features()에서 사용
// ============================================================

double sequenceScale(
    const HandSequence& left_sequence,
    const HandSequence& right_sequence
);


// ============================================================
// Local hand
//
// Python make_local_hand()
//
// frame마다:
//   wrist origin
//   / frame hand scale
//
// zero frame:
//   그대로 zero
//
// invalid frame scale:
//   sequence median fallback
//
// output:
//   flat [T, 42]
// ============================================================

std::vector<double> makeLocalHand(
    const HandSequence& hand_sequence
);


// ============================================================
// Hand motion score
//
// Python calculate_hand_motion_score()
//
// diff between frames
// → joint-wise Euclidean movement
// → mean across 21 joints per frame
// → divide by sequence scale
// → sum over time
// ============================================================

double calculateHandMotionScore(
    const HandSequence* hand_sequence
);


// ============================================================
// Hand usage
//
// Python detect_hand_usage()
// ============================================================

HandUsage detectHandUsage(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence,
    double one_hand_ratio_threshold =
        DEFAULT_ONE_HAND_RATIO_THRESHOLD,
    double no_motion_threshold =
        DEFAULT_NO_MOTION_THRESHOLD
);


// ============================================================
// One-hand canonicalization
//
// canonical RIGHT 기준:
//
// RIGHT:
//   unchanged
//
// LEFT:
//   mirror X
//
// input/output:
//   flat [T, 42]
// ============================================================

std::vector<double> canonicalizeOneHandLocal(
    const std::vector<double>& local_sequence,
    std::size_t frame_count,
    ActiveHand active_hand,
    CanonicalHand canonical_hand
);


// ============================================================
// Pair-relative features
//
// midpoint = (left wrist + right wrist) / 2
//
// pair_left  = (left  - midpoint) / sequence_scale
// pair_right = (right - midpoint) / sequence_scale
//
// outputs:
//   flat [T, 42]
// ============================================================

struct PairRelativeResult {
    std::vector<double> left;
    std::vector<double> right;
};


PairRelativeResult makePairRelativeFeatures(
    const HandSequence& left_sequence,
    const HandSequence& right_sequence
);


// ============================================================
// Normalized trajectory
//
// one-hand:
//   active wrist
//
// two-hand:
//   bilateral wrist midpoint
//
// anchor:
//   median of first N frames
//
// trajectory scale:
//   p95 radial distance
//
// one-hand handedness:
//   canonical mismatch -> X mirror
//
// output:
//   flat [T, 2]
// ============================================================

struct TrajectoryResult {
    std::vector<float> trajectory;

    double scale =
        1.0;
};


TrajectoryResult makeNormalizedTrajectory(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence,
    const HandUsage& usage,
    std::size_t anchor_frame_count =
        DEFAULT_ANCHOR_FRAME_COUNT,
    CanonicalHand canonical_hand =
        CanonicalHand::Right
);


// ============================================================
// Feature V3
//
// Python build_hand_features_v3()
//
// left/right nullptr 허용.
//
// 최종 output:
//   flat [T, 172]
// ============================================================

FeatureV3Result buildHandFeaturesV3(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence,
    const FeatureV3Options& options =
        FeatureV3Options{}
);


}  // namespace sign_engine