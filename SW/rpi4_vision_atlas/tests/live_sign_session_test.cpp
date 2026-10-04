#include "live_sign_session.hpp"

#include <cassert>
#include <cstddef>
#include <iostream>

namespace {

sign_engine::VisionFrameDetections
handFrame() {
    return sign_engine::VisionFrameDetections(
        1
    );
}

sign_engine::VisionFrameDetections
emptyFrame() {
    return {};
}

void pushHands(
    LiveSignSession& session,
    std::size_t count
) {
    for (std::size_t index = 0;
         index < count;
         ++index) {
        const auto completed =
            session.push(
                handFrame()
            );

        assert(
            !completed.has_value()
        );
    }
}

void pushEmpty(
    LiveSignSession& session,
    std::size_t count
) {
    for (std::size_t index = 0;
         index < count;
         ++index) {
        session.push(
            emptyFrame()
        );
    }
}

}  // namespace

int main() {
    {
        LiveSignSession session;

        pushEmpty(
            session,
            20
        );

        assert(
            !session.isRecording()
        );
    }

    {
        LiveSignSession session;

        pushHands(
            session,
            19
        );

        std::optional<
            sign_engine::VisionRecordingDetections
        > completed;

        for (int index = 0;
             index < 5;
             ++index) {
            completed =
                session.push(
                    emptyFrame()
                );
        }

        assert(
            !completed.has_value()
        );

        assert(
            !session.isRecording()
        );
    }

    {
        LiveSignSession session;

        pushHands(
            session,
            20
        );

        std::optional<
            sign_engine::VisionRecordingDetections
        > completed;

        for (int index = 0;
             index < 5;
             ++index) {
            completed =
                session.push(
                    emptyFrame()
                );
        }

        assert(
            completed.has_value()
        );

        assert(
            completed->size() == 20
        );
    }

    {
        LiveSignSession session;

        std::optional<
            sign_engine::VisionRecordingDetections
        > completed;

        for (int index = 0;
             index < 90;
             ++index) {
            completed =
                session.push(
                    handFrame()
                );
        }

        assert(
            completed.has_value()
        );

        assert(
            completed->size() == 90
        );

        for (int index = 0;
             index < 10;
             ++index) {
            assert(
                !session.push(
                    handFrame()
                ).has_value()
            );
        }

        pushEmpty(
            session,
            5
        );

        assert(
            !session.push(
                handFrame()
            ).has_value()
        );

        assert(
            session.isRecording()
        );
    }

    {
        LiveSignSession session;

        pushHands(
            session,
            25
        );

        const auto completed =
            session.flush();

        assert(
            completed.has_value()
        );

        assert(
            completed->size() == 25
        );
    }

    std::cout
        << "LIVE_SIGN_SESSION_PASS\n";

    return 0;
}
