#pragma once

#include "sign_types.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// One MediaPipe normalized landmark
//
// MediaPipe Hands:
//   x, y are normalized image coordinates.
// ============================================================

struct NormalizedHandPoint {
    float x = 0.0f;
    float y = 0.0f;
};


// ============================================================
// One detected MediaPipe hand
//
// label:
//   typically "Left" / "Right"
//
// confidence:
//   handedness classification score
//
// No additional confidence threshold is applied here.
// This mirrors frozen Python extract_hands().
// ============================================================

struct NormalizedHandDetection {
    std::string label;

    double confidence =
        0.0;

    std::array<
        NormalizedHandPoint,
        HAND_LANDMARK_COUNT
    > landmarks{};
};


// ============================================================
// MediaPipe detection -> FrameHands
//
// Frozen Python semantics:
//
// label = classification.label.upper()
//
// if label not in ("LEFT", "RIGHT"):
//     continue
//
// xy:
//     x = (1.0 - landmark.x) * width
//     y = landmark.y * height
//     dtype = np.float32
//
// Duplicate LEFT / RIGHT:
//     keep the one with greater confidence.
//     Equal confidence keeps the earlier detection.
// ============================================================

FrameHands extractFrameHands(
    const std::vector<NormalizedHandDetection>& detections,
    std::int32_t width,
    std::int32_t height
);


// ============================================================
// Frozen capture_sequence() recording behavior:
//
// if left_xy is not None or right_xy is not None:
//     recording_frames.append((left_xy, right_xy))
//
// Returns:
//   true  -> frame appended
//   false -> neither hand detected, frame discarded
// ============================================================

bool appendDetectedFrame(
    RecordingFrames& recording_frames,
    const std::vector<NormalizedHandDetection>& detections,
    std::int32_t width,
    std::int32_t height
);


}  // namespace sign_engine