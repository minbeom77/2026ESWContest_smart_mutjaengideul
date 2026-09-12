#include "jsonl_frame_hands.hpp"

#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::uint32_t floatBits(float value) {
    std::uint32_t bits = 0;

    static_assert(
        sizeof(bits) == sizeof(value),
        "float must be 32-bit"
    );

    std::memcpy(
        &bits,
        &value,
        sizeof(bits)
    );

    return bits;
}

void writeHand(
    std::ostringstream& output,
    char side,
    const sign_engine::HandLandmarks& hand
) {
    for (std::size_t point = 0;
         point < sign_engine::HAND_LANDMARK_COUNT;
         ++point) {
        output
            << side << ' '
            << point << ' '
            << std::uppercase
            << std::hex
            << std::setw(8)
            << std::setfill('0')
            << floatBits(hand.points[point].x)
            << ' '
            << std::setw(8)
            << std::setfill('0')
            << floatBits(hand.points[point].y)
            << std::dec
            << '\n';
    }
}

std::string dumpFrames(
    const sign_engine::RecordingFrames& frames
) {
    std::ostringstream output;

    output
        << "frames "
        << frames.size()
        << '\n';

    for (std::size_t frame_index = 0;
         frame_index < frames.size();
         ++frame_index) {
        const sign_engine::FrameHands& frame =
            frames[frame_index];

        output
            << "frame "
            << frame_index
            << " left "
            << (frame.has_left ? 1 : 0)
            << " right "
            << (frame.has_right ? 1 : 0)
            << '\n';

        if (frame.has_left) {
            writeHand(
                output,
                'L',
                frame.left
            );
        }

        if (frame.has_right) {
            writeHand(
                output,
                'R',
                frame.right
            );
        }
    }

    return output.str();
}

std::string readFile(
    const std::string& path
) {
    std::ifstream input(
        path,
        std::ios::in | std::ios::binary
    );

    if (!input) {
        throw std::runtime_error(
            "cannot open expected file: " + path
        );
    }

    std::ostringstream buffer;
    buffer << input.rdbuf();

    return buffer.str();
}

std::vector<std::string> splitLines(
    const std::string& text
) {
    std::vector<std::string> lines;

    std::istringstream input(text);
    std::string line;

    while (std::getline(input, line)) {
        if (!line.empty() &&
            line.back() == '\r') {
            line.pop_back();
        }

        lines.push_back(line);
    }

    return lines;
}

void compareExact(
    const std::string& actual,
    const std::string& expected
) {
    const std::vector<std::string> actual_lines =
        splitLines(actual);

    const std::vector<std::string> expected_lines =
        splitLines(expected);

    const std::size_t common =
        actual_lines.size() < expected_lines.size()
            ? actual_lines.size()
            : expected_lines.size();

    for (std::size_t index = 0;
         index < common;
         ++index) {
        if (actual_lines[index] !=
            expected_lines[index]) {
            std::ostringstream message;

            message
                << "parity mismatch at line "
                << (index + 1)
                << "\nexpected: "
                << expected_lines[index]
                << "\nactual  : "
                << actual_lines[index];

            throw std::runtime_error(
                message.str()
            );
        }
    }

    if (actual_lines.size() !=
        expected_lines.size()) {
        std::ostringstream message;

        message
            << "line count mismatch: expected "
            << expected_lines.size()
            << ", actual "
            << actual_lines.size();

        throw std::runtime_error(
            message.str()
        );
    }
}

}  // namespace

int main(
    int argc,
    char** argv
) {
    try {
        if (argc != 3) {
            std::cerr
                << "Usage:\n"
                << "  jsonl_frame_hands_parity "
                << "<input.jsonl> <expected.txt>\n";

            return 2;
        }

        const std::string input_path =
            argv[1];

        const std::string expected_path =
            argv[2];

        const sign_engine::JsonlRecordingResult result =
            sign_engine::loadRecordingFramesFromJson(
                {input_path}
            );

        const std::string actual =
            dumpFrames(
                result.frames
            );

        const std::string expected =
            readFile(
                expected_path
            );

        compareExact(
            actual,
            expected
        );

        std::cout
            << "documents       : "
            << result.document_count
            << '\n'
            << "frames          : "
            << result.frames.size()
            << '\n'
            << "maximum hands   : "
            << result.maximum_hands_per_frame
            << '\n'
            << "single stabilize: "
            << (
                result.used_single_hand_stabilization
                    ? "true"
                    : "false"
            )
            << '\n';

        if (result.has_median_handedness) {
            std::cout
                << "median raw      : "
                << result.median_handedness_raw
                << '\n'
                << "stabilized hand : "
                << result.stabilized_physical_hand
                << '\n';
        }

        std::cout
            << "JSONL FRAMEHANDS PARITY PASS\n";

        return 0;
    } catch (const std::exception& error) {
        std::cerr
            << "JSONL FRAMEHANDS PARITY FAIL\n"
            << error.what()
            << '\n';

        return 1;
    }
}