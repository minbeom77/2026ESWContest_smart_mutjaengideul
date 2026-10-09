#pragma once

#include "vision_frame_hands.hpp"

#include <cstddef>
#include <optional>

class LiveSignSession {
public:
    LiveSignSession(
        std::size_t minimum_hand_frames = 20,
        std::size_t maximum_hand_frames = 90,
        std::size_t end_gap_frames = 5
    );

    std::optional<
        sign_engine::VisionRecordingDetections
    > push(
        sign_engine::VisionFrameDetections frame
    );

    std::optional<
        sign_engine::VisionRecordingDetections
    > flush();

    bool isRecording() const;

private:
    enum class State {
        Idle,
        Recording,
        AwaitRelease,
    };

    std::optional<
        sign_engine::VisionRecordingDetections
    > finish(
        bool await_release
    );

    void resetRecording();

    std::size_t minimum_hand_frames_;
    std::size_t maximum_hand_frames_;
    std::size_t end_gap_frames_;

    State state_ = State::Idle;

    sign_engine::VisionRecordingDetections
        recording_;

    std::size_t observed_hand_frames_ = 0;
    std::size_t empty_streak_ = 0;
    std::size_t release_empty_streak_ = 0;
};
