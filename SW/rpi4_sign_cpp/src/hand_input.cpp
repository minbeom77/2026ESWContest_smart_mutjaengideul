#include "hand_input.hpp"

#include <cctype>
#include <cstddef>
#include <string>


namespace sign_engine {

namespace {


// ============================================================
// Python:
//
// classification.label.upper()
//
// MediaPipe labels are ASCII Left / Right, so ASCII-compatible
// std::toupper is sufficient.
// ============================================================

std::string uppercaseLabel(
    const std::string& label
) {
    std::string result =
        label;


    for (
        char& ch :
        result
    ) {
        ch =
            static_cast<char>(
                std::toupper(
                    static_cast<unsigned char>(
                        ch
                    )
                )
            );
    }


    return result;
}


// ============================================================
// Frozen Python:
//
// x = (
//     1.0
//     -
//     float(landmark.x)
// ) * float(width)
//
// y = (
//     float(landmark.y)
//     *
//     float(height)
// )
//
// return np.asarray(points, dtype=np.float32)
//
// Important:
// Python performs arithmetic as double precision and only then
// converts to float32.
//
// Therefore C++ also performs calculation in double and casts
// the final value to float.
// ============================================================

HandLandmarks convertLandmarksToAihubXY(
    const NormalizedHandDetection& detection,
    std::int32_t width,
    std::int32_t height
) {
    HandLandmarks converted;


    const double width_double =
        static_cast<double>(
            width
        );

    const double height_double =
        static_cast<double>(
            height
        );


    for (
        std::size_t i = 0;
        i < HAND_LANDMARK_COUNT;
        ++i
    ) {
        const double normalized_x =
            static_cast<double>(
                detection
                    .landmarks[i]
                    .x
            );

        const double normalized_y =
            static_cast<double>(
                detection
                    .landmarks[i]
                    .y
            );


        const double x =
            (
                1.0
                -
                normalized_x
            )
            *
            width_double;


        const double y =
            normalized_y
            *
            height_double;


        converted
            .points[i]
            .x =
                static_cast<float>(
                    x
                );


        converted
            .points[i]
            .y =
                static_cast<float>(
                    y
                );
    }


    return converted;
}


}  // namespace


FrameHands extractFrameHands(
    const std::vector<NormalizedHandDetection>& detections,
    std::int32_t width,
    std::int32_t height
) {
    FrameHands result;


    double left_confidence =
        0.0;

    double right_confidence =
        0.0;


    // ========================================================
    // Python:
    //
    // for hand_landmarks, handedness in zip(...):
    //
    //     label = classification.label.upper()
    //
    //     confidence = float(classification.score)
    //
    //     if label not in ("LEFT", "RIGHT"):
    //         continue
    //
    //     if (
    //         label not in detected
    //         or
    //         confidence > detected[label]["confidence"]
    //     ):
    //         detected[label] = ...
    //
    // Note strict ">".
    //
    // Equal confidence does NOT replace the first detection.
    // ========================================================

    for (
        const NormalizedHandDetection& detection :
        detections
    ) {
        const std::string label =
            uppercaseLabel(
                detection.label
            );


        if (
            label != "LEFT"
            &&
            label != "RIGHT"
        ) {
            continue;
        }


        const HandLandmarks converted =
            convertLandmarksToAihubXY(
                detection,
                width,
                height
            );


        // ====================================================
        // LEFT
        // ====================================================

        if (
            label
            ==
            "LEFT"
        ) {
            if (
                !result.has_left
                ||
                detection.confidence
                    >
                    left_confidence
            ) {
                result.has_left =
                    true;

                result.left =
                    converted;

                left_confidence =
                    detection.confidence;
            }


            continue;
        }


        // ====================================================
        // RIGHT
        // ====================================================

        if (
            !result.has_right
            ||
            detection.confidence
                >
                right_confidence
        ) {
            result.has_right =
                true;

            result.right =
                converted;

            right_confidence =
                detection.confidence;
        }
    }


    return result;
}


bool appendDetectedFrame(
    RecordingFrames& recording_frames,
    const std::vector<NormalizedHandDetection>& detections,
    std::int32_t width,
    std::int32_t height
) {
    const FrameHands frame =
        extractFrameHands(
            detections,
            width,
            height
        );


    // ========================================================
    // Frozen:
    //
    // if (
    //     left_xy is not None
    //     or
    //     right_xy is not None
    // ):
    //     recording_frames.append(...)
    // ========================================================

    if (
        !frame.has_left
        &&
        !frame.has_right
    ) {
        return false;
    }


    recording_frames.push_back(
        frame
    );


    return true;
}


}  // namespace sign_engine