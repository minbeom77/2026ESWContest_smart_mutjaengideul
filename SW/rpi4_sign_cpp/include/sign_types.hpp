#pragma once

#include "feature_v3.hpp"

#include <cstddef>
#include <vector>


namespace sign_engine {


// ============================================================
// Raw recording frame
//
// Final ATLAS / HandPose bridge -> sign engine input.
//
// IMPORTANT:
//
// TEMP / 온도 overlap rescue requires the original per-frame
// LEFT / RIGHT existence information to remain available until
// the one-hand C4 NO-SIGN decision has been made.
//
// Do NOT collapse the recording into only one HandSequence
// before upper-level routing is complete.
// ============================================================

struct FrameHands {
    bool has_left =
        false;

    bool has_right =
        false;


    HandLandmarks left{};

    HandLandmarks right{};
};


// ============================================================
// Raw recording sequence
// ============================================================

using RecordingFrames =
    std::vector<FrameHands>;


// ============================================================
// Recording statistics
//
// Used by:
//   - normal webcam routing
//   - TEMP overlap rescue eligibility
// ============================================================

struct RecordingStats {
    std::size_t total_frames =
        0;

    std::size_t left_count =
        0;

    std::size_t right_count =
        0;

    std::size_t both_count =
        0;

    double both_ratio =
        0.0;
};


// ============================================================
// BOTH-frame extraction
//
// TEMP overlap rescue recollects only frames where:
//
//   has_left == true
//   AND
//   has_right == true
//
// These two sequences therefore always have equal length.
// ============================================================

struct BothHandSequences {
    HandSequence left;
    HandSequence right;


    std::size_t size() const {
        return left.size();
    }


    bool empty() const {
        return left.empty();
    }
};


}  // namespace sign_engine