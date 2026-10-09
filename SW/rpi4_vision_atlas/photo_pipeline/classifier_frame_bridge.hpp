#pragma once

#include "vision_frame_hands.hpp"
#include <stdexcept>

// The classifier's frozen PC input restores mirrored camera X coordinates:
// x = (1 - normalized_x) * width. Keep calibrated physical hand slots intact.
// Work on a copy so preview/tracking/raw diagnostic coordinates stay unchanged.
inline sign_engine::VisionFrameDetections restoreClassifierCoordinates(
    sign_engine::VisionFrameDetections detections,
    int image_width
) {
    if (image_width <= 0) {
        throw std::invalid_argument("Classifier image width must be positive");
    }
    for (auto& hand : detections) {
        for (auto& point : hand.landmarks.points) {
            point.x = static_cast<float>(static_cast<double>(image_width) - point.x);
        }
    }
    return detections;
}
