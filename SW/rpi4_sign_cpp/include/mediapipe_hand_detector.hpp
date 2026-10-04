#pragma once

#include "hand_input.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// MediaPipe Hands C++ detector
//
// Frozen Python parity target:
//
// mp.solutions.hands.Hands(
//     static_image_mode=False,
//     max_num_hands=2,
//     model_complexity=1,
//     min_detection_confidence=0.5,
//     min_tracking_confidence=0.5,
// )
//
// Input image preprocessing:
//
// frame = cv2.flip(frame, 1)
// rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
//
// Important:
//   The detector returns normalized MediaPipe coordinates.
//
//   Pixel conversion:
//       x = (1 - x) * width
//       y = y * height
//
//   is NOT performed here.
//
//   That conversion remains exclusively in hand_input.cpp
//   so frozen Python extract_hands() semantics stay centralized.
// ============================================================

class MediaPipeHandDetector {
public:
    // --------------------------------------------------------
    // Construct detector from the frozen canonical graph.
    // --------------------------------------------------------

    explicit MediaPipeHandDetector(
        const std::string& graph_path
    );


    // --------------------------------------------------------
    // Non-copyable
    //
    // CalculatorGraph owns runtime state.
    // --------------------------------------------------------

    MediaPipeHandDetector(
        const MediaPipeHandDetector&
    ) = delete;

    MediaPipeHandDetector& operator=(
        const MediaPipeHandDetector&
    ) = delete;


    // --------------------------------------------------------
    // Movable
    // --------------------------------------------------------

    MediaPipeHandDetector(
        MediaPipeHandDetector&&
    ) noexcept;

    MediaPipeHandDetector& operator=(
        MediaPipeHandDetector&&
    ) noexcept;


    // --------------------------------------------------------
    // Destructor
    // --------------------------------------------------------

    ~MediaPipeHandDetector();


    // --------------------------------------------------------
    // Process one BGR camera frame.
    //
    // Frozen Python preprocessing is performed internally:
    //
    //   1. horizontal flip
    //   2. BGR -> RGB
    //   3. MediaPipe Hands graph
    //
    // Return:
    //   zero, one, or two normalized hand detections.
    //
    // No extra confidence threshold is applied here.
    // --------------------------------------------------------

    std::vector<NormalizedHandDetection>
    processBgrFrame(
        const std::uint8_t* bgr_data,
        std::int32_t width,
        std::int32_t height,
        std::int32_t stride_bytes
    );


private:
    // Hide MediaPipe implementation details from the public
    // project header.
    class Impl;

    std::unique_ptr<Impl> impl_;
};


}  // namespace sign_engine