#include "jsonl_frame_hands.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <fstream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

namespace sign_engine {
namespace {

using json = nlohmann::json;

enum class PhysicalHand {
    Left,
    Right,
};

struct ParsedHand {
    double raw = 0.0;
    double confidence = 0.0;
    HandLandmarks landmarks{};
    PhysicalHand physical = PhysicalHand::Left;
};

struct ParsedFrame {
    bool mirror_input = false;
    int width = 0;
    int height = 0;
    std::vector<ParsedHand> hands;
};

std::string upperAscii(std::string value) {
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](unsigned char ch) {
            return static_cast<char>(std::toupper(ch));
        }
    );
    return value;
}

std::string modelHand(double raw) {
    return raw > 0.5 ? "RIGHT" : "LEFT";
}

PhysicalHand physicalHand(double raw) {
    // Exact Python reference:
    //
    // _model_hand(raw):
    //     RIGHT if raw > 0.5 else LEFT
    //
    // _physical_hand(raw):
    //     opposite of model hand
    return raw > 0.5
        ? PhysicalHand::Left
        : PhysicalHand::Right;
}

std::string physicalHandName(PhysicalHand hand) {
    return hand == PhysicalHand::Left ? "LEFT" : "RIGHT";
}

double requireFiniteNumber(
    const json& value,
    const std::string& field_name
) {
    if (!value.is_number()) {
        throw JsonlFrameHandsError(
            field_name + " must be a JSON number"
        );
    }

    const double result = value.get<double>();

    if (!std::isfinite(result)) {
        throw JsonlFrameHandsError(
            field_name + " must be finite"
        );
    }

    return result;
}

double requireUnitInterval(
    const json& value,
    const std::string& field_name
) {
    const double result = requireFiniteNumber(
        value,
        field_name
    );

    if (result < 0.0 || result > 1.0) {
        throw JsonlFrameHandsError(
            field_name + " must be in [0, 1]"
        );
    }

    return result;
}

HandLandmarks parseLandmarks(
    const json& value,
    const std::string& field_name
) {
    if (!value.is_array() || value.size() != HAND_LANDMARK_COUNT) {
        throw JsonlFrameHandsError(
            field_name + " shape must be (21, 2)"
        );
    }

    HandLandmarks landmarks{};

    for (std::size_t point_index = 0;
         point_index < HAND_LANDMARK_COUNT;
         ++point_index) {
        const json& point = value.at(point_index);

        if (!point.is_array() || point.size() != 2) {
            throw JsonlFrameHandsError(
                field_name + " shape must be (21, 2)"
            );
        }

        const double x = requireFiniteNumber(
            point.at(0),
            field_name + "[" +
                std::to_string(point_index) + "][0]"
        );

        const double y = requireFiniteNumber(
            point.at(1),
            field_name + "[" +
                std::to_string(point_index) + "][1]"
        );

        // Python reference:
        // np.asarray(..., dtype=np.float32)
        //
        // No mirroring, clamping, normalization, or other coordinate
        // transformation occurs here.
        landmarks.points[point_index].x =
            static_cast<float>(x);

        landmarks.points[point_index].y =
            static_cast<float>(y);
    }

    return landmarks;
}

ParsedHand parseHand(
    const json& hand,
    std::size_t hand_index
) {
    if (!hand.is_object()) {
        throw JsonlFrameHandsError(
            "hands[" + std::to_string(hand_index) +
            "] must be an object"
        );
    }

    const std::string prefix =
        "hands[" + std::to_string(hand_index) + "]";

    if (!hand.contains("handedness_raw")) {
        throw JsonlFrameHandsError(
            prefix + " missing field: handedness_raw"
        );
    }

    if (!hand.contains("hand_confidence")) {
        throw JsonlFrameHandsError(
            prefix + " missing field: hand_confidence"
        );
    }

    if (!hand.contains("landmarks_xy")) {
        throw JsonlFrameHandsError(
            prefix + " missing field: landmarks_xy"
        );
    }

    ParsedHand parsed{};

    parsed.raw = requireUnitInterval(
        hand.at("handedness_raw"),
        prefix + ".handedness_raw"
    );

    parsed.confidence = requireUnitInterval(
        hand.at("hand_confidence"),
        prefix + ".hand_confidence"
    );

    parsed.landmarks = parseLandmarks(
        hand.at("landmarks_xy"),
        prefix + ".landmarks_xy"
    );

    const std::string expected_model =
        modelHand(parsed.raw);

    parsed.physical =
        physicalHand(parsed.raw);

    const std::string expected_physical =
        physicalHandName(parsed.physical);

    if (hand.contains("model_hand")) {
        if (!hand.at("model_hand").is_string()) {
            throw JsonlFrameHandsError(
                prefix + ".model_hand must be a string"
            );
        }

        const std::string declared_model =
            upperAscii(
                hand.at("model_hand").get<std::string>()
            );

        if (declared_model != expected_model) {
            throw JsonlFrameHandsError(
                prefix +
                ".model_hand disagrees with handedness_raw"
            );
        }
    }

    if (hand.contains("physical_hand")) {
        if (!hand.at("physical_hand").is_string()) {
            throw JsonlFrameHandsError(
                prefix + ".physical_hand must be a string"
            );
        }

        const std::string declared_physical =
            upperAscii(
                hand.at("physical_hand").get<std::string>()
            );

        // Exact Python adapter behavior:
        // "UNVERIFIED" is explicitly accepted.
        if (declared_physical != "UNVERIFIED" &&
            declared_physical != expected_physical) {
            throw JsonlFrameHandsError(
                prefix +
                ".physical_hand disagrees with handedness_raw"
            );
        }
    }

    return parsed;
}

ParsedFrame parseFrame(
    const json& document,
    std::size_t frame_index
) {
    if (!document.is_object()) {
        throw JsonlFrameHandsError(
            "frame " + std::to_string(frame_index) +
            " must be an object"
        );
    }

    if (!document.contains("mirror_input") ||
        !document.at("mirror_input").is_boolean()) {
        throw JsonlFrameHandsError(
            "frame " + std::to_string(frame_index) +
            ".mirror_input must be a JSON boolean"
        );
    }

    if (!document.contains("image_size_wh")) {
        throw JsonlFrameHandsError(
            "frame " + std::to_string(frame_index) +
            ".image_size_wh is missing"
        );
    }

    const json& image_size =
        document.at("image_size_wh");

    if (!image_size.is_array() ||
        image_size.size() != 2 ||
        !image_size.at(0).is_number_integer() ||
        !image_size.at(1).is_number_integer()) {
        throw JsonlFrameHandsError(
            "frame " + std::to_string(frame_index) +
            ".image_size_wh must contain two positive integers"
        );
    }

    const int width =
        image_size.at(0).get<int>();

    const int height =
        image_size.at(1).get<int>();

    if (width <= 0 || height <= 0) {
        throw JsonlFrameHandsError(
            "frame " + std::to_string(frame_index) +
            ".image_size_wh must contain two positive integers"
        );
    }

    if (!document.contains("hands") ||
        !document.at("hands").is_array()) {
        throw JsonlFrameHandsError(
            "frame " + std::to_string(frame_index) +
            ".hands must be a JSON array"
        );
    }

    ParsedFrame frame{};
    frame.mirror_input =
        document.at("mirror_input").get<bool>();
    frame.width = width;
    frame.height = height;

    const json& hands = document.at("hands");

    frame.hands.reserve(hands.size());

    for (std::size_t hand_index = 0;
         hand_index < hands.size();
         ++hand_index) {
        frame.hands.push_back(
            parseHand(
                hands.at(hand_index),
                hand_index
            )
        );
    }

    return frame;
}

std::string readEntireFile(
    const std::string& path
) {
    std::ifstream input(
        path,
        std::ios::in | std::ios::binary
    );

    if (!input) {
        throw JsonlFrameHandsError(
            "could not open JSON/JSONL file: " + path
        );
    }

    std::ostringstream buffer;
    buffer << input.rdbuf();

    if (!input.eof() && input.fail()) {
        throw JsonlFrameHandsError(
            "could not read JSON/JSONL file: " + path
        );
    }

    return buffer.str();
}

std::vector<json> parseJsonOrJsonlFile(
    const std::string& path
) {
    const std::string content =
        readEntireFile(path);

    if (content.empty()) {
        return {};
    }

    // Match the Python reference's preferred single-document path:
    //
    // if first == "{":
    //     try json.load(stream)
    //
    // If the file contains multiple JSON documents (normal JSONL),
    // the whole-file parse fails and we retry line by line.
    if (content.front() == '{') {
        try {
            json document =
                json::parse(content);

            return {std::move(document)};
        } catch (const json::parse_error&) {
            // Retry as JSONL below.
        }
    }

    std::vector<json> documents;

    std::istringstream stream(content);
    std::string line;
    std::size_t line_number = 0;

    while (std::getline(stream, line)) {
        ++line_number;

        const bool only_whitespace =
            std::all_of(
                line.begin(),
                line.end(),
                [](unsigned char ch) {
                    return std::isspace(ch) != 0;
                }
            );

        if (only_whitespace) {
            continue;
        }

        try {
            documents.push_back(
                json::parse(line)
            );
        } catch (const json::parse_error& error) {
            throw JsonlFrameHandsError(
                path +
                ": invalid JSONL at line " +
                std::to_string(line_number) +
                ": " +
                error.what()
            );
        }
    }

    return documents;
}

double median(
    std::vector<double> values
) {
    if (values.empty()) {
        throw JsonlFrameHandsError(
            "internal error: median of empty values"
        );
    }

    std::sort(
        values.begin(),
        values.end()
    );

    const std::size_t size =
        values.size();

    const std::size_t middle =
        size / 2;

    if ((size % 2) != 0) {
        return values[middle];
    }

    return (
        values[middle - 1] +
        values[middle]
    ) / 2.0;
}

}  // namespace

JsonlRecordingResult loadRecordingFramesFromJson(
    const std::vector<std::string>& json_or_jsonl_paths
) {
    std::vector<json> documents;

    for (const std::string& path :
         json_or_jsonl_paths) {
        std::vector<json> loaded =
            parseJsonOrJsonlFile(path);

        documents.insert(
            documents.end(),
            std::make_move_iterator(loaded.begin()),
            std::make_move_iterator(loaded.end())
        );
    }

    JsonlRecordingResult result{};
    result.document_count =
        documents.size();

    std::vector<ParsedFrame> parsed_frames;
    parsed_frames.reserve(documents.size());

    bool signature_initialized = false;
    bool expected_mirror = false;
    int expected_width = 0;
    int expected_height = 0;

    std::size_t maximum_hands = 0;

    for (std::size_t frame_index = 0;
         frame_index < documents.size();
         ++frame_index) {
        ParsedFrame frame =
            parseFrame(
                documents[frame_index],
                frame_index
            );

        if (!signature_initialized) {
            signature_initialized = true;
            expected_mirror =
                frame.mirror_input;
            expected_width =
                frame.width;
            expected_height =
                frame.height;
        } else if (
            frame.mirror_input != expected_mirror ||
            frame.width != expected_width ||
            frame.height != expected_height
        ) {
            throw JsonlFrameHandsError(
                "frame " +
                std::to_string(frame_index) +
                " changed mirror_input or image_size_wh"
            );
        }

        maximum_hands =
            std::max(
                maximum_hands,
                frame.hands.size()
            );

        parsed_frames.push_back(
            std::move(frame)
        );
    }

    result.maximum_hands_per_frame =
        maximum_hands;

    result.has_sequence_signature =
        signature_initialized;

    if (signature_initialized) {
        result.mirror_input =
            expected_mirror;
        result.image_width =
            expected_width;
        result.image_height =
            expected_height;
    }

    // Exact Python branch:
    //
    // if maximum_hands <= 1:
    //     observations = [hands[0] for hands in parsed if hands]
    //     if not observations:
    //         return []
    //
    //     median_raw = np.median(...)
    //     physical = _physical_hand(median_raw)
    //
    //     return every observed hand in that one stabilized slot
    if (maximum_hands <= 1) {
        result.used_single_hand_stabilization =
            true;

        std::vector<const ParsedHand*> observations;
        observations.reserve(parsed_frames.size());

        std::vector<double> raw_values;
        raw_values.reserve(parsed_frames.size());

        for (const ParsedFrame& frame :
             parsed_frames) {
            if (frame.hands.empty()) {
                continue;
            }

            const ParsedHand& hand =
                frame.hands.front();

            observations.push_back(&hand);
            raw_values.push_back(hand.raw);
        }

        if (observations.empty()) {
            return result;
        }

        const double median_raw =
            median(std::move(raw_values));

        const PhysicalHand stabilized_side =
            physicalHand(median_raw);

        result.has_median_handedness =
            true;

        result.median_handedness_raw =
            median_raw;

        result.stabilized_physical_hand =
            physicalHandName(stabilized_side);

        result.frames.reserve(
            observations.size()
        );

        for (const ParsedHand* hand :
             observations) {
            FrameHands output{};

            if (stabilized_side ==
                PhysicalHand::Left) {
                output.has_left = true;
                output.left =
                    hand->landmarks;
            } else {
                output.has_right = true;
                output.right =
                    hand->landmarks;
            }

            result.frames.push_back(
                std::move(output)
            );
        }

        return result;
    }

    // Multi-hand recording:
    // choose the highest-confidence detection for each physical slot
    // independently on every frame.
    //
    // Strict '>' preserves the earlier detection on a confidence tie.
    result.used_single_hand_stabilization =
        false;

    result.frames.reserve(
        parsed_frames.size()
    );

    for (const ParsedFrame& frame :
         parsed_frames) {
        const ParsedHand* selected_left =
            nullptr;

        const ParsedHand* selected_right =
            nullptr;

        for (const ParsedHand& hand :
             frame.hands) {
            if (hand.physical ==
                PhysicalHand::Left) {
                if (selected_left == nullptr ||
                    hand.confidence >
                        selected_left->confidence) {
                    selected_left = &hand;
                }
            } else {
                if (selected_right == nullptr ||
                    hand.confidence >
                        selected_right->confidence) {
                    selected_right = &hand;
                }
            }
        }

        if (selected_left == nullptr &&
            selected_right == nullptr) {
            continue;
        }

        FrameHands output{};

        if (selected_left != nullptr) {
            output.has_left = true;
            output.left =
                selected_left->landmarks;
        }

        if (selected_right != nullptr) {
            output.has_right = true;
            output.right =
                selected_right->landmarks;
        }

        result.frames.push_back(
            std::move(output)
        );
    }

    return result;
}

}  // namespace sign_engine