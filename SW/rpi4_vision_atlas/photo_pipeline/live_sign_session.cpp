#include "live_sign_session.hpp"

#include <stdexcept>
#include <utility>

LiveSignSession::LiveSignSession(
    std::size_t minimum_hand_frames,
    std::size_t maximum_hand_frames,
    std::size_t end_gap_frames
)
    : minimum_hand_frames_(
          minimum_hand_frames
      ),
      maximum_hand_frames_(
          maximum_hand_frames
      ),
      end_gap_frames_(
          end_gap_frames
      ) {
    if (
        minimum_hand_frames_ == 0 ||
        maximum_hand_frames_ <
            minimum_hand_frames_ ||
        end_gap_frames_ == 0
    ) {
        throw std::invalid_argument(
            "Invalid live sign session limits"
        );
    }

    recording_.reserve(
        maximum_hand_frames_ +
        end_gap_frames_
    );
}

bool LiveSignSession::isRecording() const {
    return state_ == State::Recording;
}

void LiveSignSession::resetRecording() {
    recording_.clear();
    observed_hand_frames_ = 0;
    empty_streak_ = 0;
}

std::optional<
    sign_engine::VisionRecordingDetections
> LiveSignSession::finish(
    bool await_release
) {
    const bool accepted =
        observed_hand_frames_ >=
        minimum_hand_frames_;

    auto completed =
        std::move(recording_);

    resetRecording();

    state_ = await_release
        ? State::AwaitRelease
        : State::Idle;

    release_empty_streak_ = 0;

    if (!accepted) {
        return std::nullopt;
    }

    return completed;
}

std::optional<
    sign_engine::VisionRecordingDetections
> LiveSignSession::push(
    sign_engine::VisionFrameDetections frame
) {
    const bool has_hands =
        !frame.empty();

    if (state_ == State::AwaitRelease) {
        if (has_hands) {
            release_empty_streak_ = 0;
        } else {
            ++release_empty_streak_;

            if (
                release_empty_streak_ >=
                end_gap_frames_
            ) {
                state_ = State::Idle;
                release_empty_streak_ = 0;
            }
        }

        return std::nullopt;
    }

    if (state_ == State::Idle) {
        if (!has_hands) {
            return std::nullopt;
        }

        state_ = State::Recording;
        resetRecording();
    }

    recording_.push_back(
        std::move(frame)
    );

    if (has_hands) {
        ++observed_hand_frames_;
        empty_streak_ = 0;

        if (
            observed_hand_frames_ >=
            maximum_hand_frames_
        ) {
            return finish(
                true
            );
        }

        return std::nullopt;
    }

    ++empty_streak_;

    if (empty_streak_ < end_gap_frames_) {
        return std::nullopt;
    }

    recording_.resize(
        recording_.size() -
        empty_streak_
    );

    return finish(
        false
    );
}

std::optional<
    sign_engine::VisionRecordingDetections
> LiveSignSession::flush() {
    if (state_ != State::Recording) {
        state_ = State::Idle;
        release_empty_streak_ = 0;

        return std::nullopt;
    }

    while (
        !recording_.empty() &&
        recording_.back().empty()
    ) {
        recording_.pop_back();
    }

    return finish(
        false
    );
}
