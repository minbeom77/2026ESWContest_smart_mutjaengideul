#include "classifier_frame_bridge.hpp"
#include "hand_input.hpp"
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <utility>

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

int main() {
    using namespace sign_engine;
    for (int width : {320, 640, 1280}) {
        VisionFrameDetections raw;
        std::vector<NormalizedHandDetection> pc_input;
        for (bool right : {false, true}) {
            VisionHandDetection observed;
            observed.handedness_raw = right ? .1 : .9;
            observed.confidence = .95;
            NormalizedHandDetection pc;
            pc.label = right ? "RIGHT" : "LEFT";
            pc.confidence = .95;
            for (std::size_t i = 0; i < 21; ++i) {
                const float x = static_cast<float>(i % 5) / 4;
                const float y = static_cast<float>(i % 4) / 4;
                observed.landmarks.points[i] = {x * width, y * 480};
                pc.landmarks[i].x = x;
                pc.landmarks[i].y = y;
            }
            raw.push_back(observed);
            pc_input.push_back(pc);
        }
        const auto converted = restoreClassifierCoordinates(raw, width);
        auto vision = buildRecordingFramesFromVision({converted});
        auto expected = extractFrameHands(pc_input, width, 480);
        require(vision.frames.size() == 1, "Frame missing");
        const auto& actual = vision.frames.front();
        require(actual.has_left && actual.has_right, "Hand slots changed");
        for (std::size_t i = 0; i < 21; ++i) {
            for (auto pair : {std::make_pair(actual.left.points[i], expected.left.points[i]),
                              std::make_pair(actual.right.points[i], expected.right.points[i])}) {
                require(std::abs(pair.first.x - pair.second.x) < 1e-4, "PC X bridge mismatch");
                require(std::abs(pair.first.y - pair.second.y) < 1e-4, "PC Y bridge mismatch");
            }
        }
        require(raw.front().landmarks.points[0].x == 0, "Raw coordinates mutated");
        require(converted.front().handedness_raw == raw.front().handedness_raw, "Hand label changed");
        require(restoreClassifierCoordinates({}, width).empty(), "Empty frame changed");
        for (std::size_t side = 0; side < raw.size(); ++side) {
            const auto single = restoreClassifierCoordinates({raw[side]}, width);
            const auto recording = buildRecordingFramesFromVision({{}, single, single, {}});
            const auto pc = extractFrameHands({pc_input[side]}, width, 480);
            require(recording.used_single_hand_stabilization, "Single-hand route missing");
            require(recording.frames.size() == 2, "Empty frames not discarded");
            for (const auto& frame : recording.frames) {
                require(frame.has_left == pc.has_left && frame.has_right == pc.has_right,
                        "Single-hand slot changed");
                const auto& actual_hand = frame.has_left ? frame.left : frame.right;
                const auto& expected_hand = pc.has_left ? pc.left : pc.right;
                for (std::size_t i = 0; i < 21; ++i) {
                    require(std::abs(actual_hand.points[i].x - expected_hand.points[i].x) < 1e-4,
                            "Single-hand X mismatch");
                    require(actual_hand.points[i].y == expected_hand.points[i].y,
                            "Single-hand Y changed");
                }
            }
        }
    }
    bool rejected = false;
    try { restoreClassifierCoordinates({}, 0); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected, "Invalid width accepted");
    std::cout << "PASS: live classifier coordinates match frozen PC bridge at three widths\n";
}
