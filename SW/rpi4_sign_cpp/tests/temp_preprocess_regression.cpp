#include "sign_classifier.hpp"

#include <cmath>
#include <cstddef>
#include <iostream>


int main() {
    sign_engine::RecordingFrames recording;


    // --------------------------------------------------------
    // 20 frames
    //
    // frame 0~9
    //   LEFT + RIGHT
    //
    // frame 10~14
    //   RIGHT only
    //
    // frame 15~17
    //   LEFT only
    //
    // frame 18~19
    //   no hand
    //
    // Expected:
    //
    // total = 20
    // left  = 13
    // right = 15
    // both  = 10
    // ratio = 0.5
    // --------------------------------------------------------

    for (
        std::size_t i = 0;
        i < 20;
        ++i
    ) {
        sign_engine::FrameHands frame;


        if (
            i < 10
        ) {
            frame.has_left =
                true;

            frame.has_right =
                true;
        }
        else if (
            i < 15
        ) {
            frame.has_left =
                false;

            frame.has_right =
                true;
        }
        else if (
            i < 18
        ) {
            frame.has_left =
                true;

            frame.has_right =
                false;
        }


        // Put deterministic values in landmark 0
        // so BOTH extraction order can also be checked.

        frame.left.points[0].x =
            static_cast<float>(
                i
            );

        frame.right.points[0].x =
            static_cast<float>(
                100 + i
            );


        recording.push_back(
            frame
        );
    }


    const sign_engine::RecordingStats stats =
        sign_engine::analyzeRecordingFrames(
            recording
        );


    const sign_engine::BothHandSequences both =
        sign_engine::extractBothHandSequences(
            recording
        );


    std::cout
        << "========================================\n";

    std::cout
        << "TEMP PREPROCESS REGRESSION\n";

    std::cout
        << "========================================\n\n";


    std::cout
        << "total_frames : "
        << stats.total_frames
        << " / expected 20\n";

    std::cout
        << "left_count   : "
        << stats.left_count
        << " / expected 13\n";

    std::cout
        << "right_count  : "
        << stats.right_count
        << " / expected 15\n";

    std::cout
        << "both_count   : "
        << stats.both_count
        << " / expected 10\n";

    std::cout
        << "both_ratio   : "
        << stats.both_ratio
        << " / expected 0.5\n";

    std::cout
        << "both size    : "
        << both.size()
        << " / expected 10\n";


    bool pass =
        true;


    if (
        stats.total_frames
        !=
        20
    ) {
        pass =
            false;
    }


    if (
        stats.left_count
        !=
        13
    ) {
        pass =
            false;
    }


    if (
        stats.right_count
        !=
        15
    ) {
        pass =
            false;
    }


    if (
        stats.both_count
        !=
        10
    ) {
        pass =
            false;
    }


    if (
        std::abs(
            stats.both_ratio
            -
            0.5
        )
        >
        1e-12
    ) {
        pass =
            false;
    }


    if (
        both.size()
        !=
        10
    ) {
        pass =
            false;
    }


    if (
        both.left.size()
        !=
        both.right.size()
    ) {
        pass =
            false;
    }


    // --------------------------------------------------------
    // Original temporal order check
    // --------------------------------------------------------

    for (
        std::size_t i = 0;
        i < both.size();
        ++i
    ) {
        const float expected_left =
            static_cast<float>(
                i
            );

        const float expected_right =
            static_cast<float>(
                100 + i
            );


        if (
            both.left[
                i
            ].points[
                0
            ].x
            !=
            expected_left
        ) {
            pass =
                false;
        }


        if (
            both.right[
                i
            ].points[
                0
            ].x
            !=
            expected_right
        ) {
            pass =
                false;
        }
    }


    std::cout
        << '\n';

    std::cout
        << "========================================\n";


    if (
        pass
    ) {
        std::cout
            << "TEMP PREPROCESS REGRESSION PASS\n";

        std::cout
            << "========================================\n";

        return 0;
    }


    std::cout
        << "TEMP PREPROCESS REGRESSION FAIL\n";

    std::cout
        << "========================================\n";

    return 1;
}