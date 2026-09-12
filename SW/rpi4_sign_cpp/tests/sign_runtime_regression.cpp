#include "runtime_data.hpp"
#include "sign_runtime.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

constexpr std::size_t REAL01_FRAMES =
    87;

constexpr std::size_t LANDMARK_COUNT =
    sign_engine::HAND_LANDMARK_COUNT;

constexpr double DOUBLE_TOLERANCE =
    1.0e-5;


struct ExpectedCase {
    std::string name;

    std::size_t extra_right_only =
        0;

    bool valid =
        false;

    std::int32_t final_id =
        -1;

    std::string stage;

    bool is_nosign =
        false;

    std::string usage;

    std::string source_mode;

    std::size_t selected_frames =
        0;

    std::size_t total =
        0;

    std::size_t left =
        0;

    std::size_t right =
        0;

    std::size_t both =
        0;

    double both_ratio =
        0.0;

    bool c4_evaluated =
        false;

    int c4_prediction =
        -1;

    double d_sign =
        0.0;

    double d_nosign =
        0.0;

    double c4_margin =
        0.0;

    bool onehand_ran =
        false;

    bool twohand_ran =
        false;

    bool temp_checked =
        false;

    bool temp_eligible =
        false;

    bool temp_rescued =
        false;
};


template <typename T>
std::vector<T> readBinary(
    const std::string& path
) {
    std::ifstream file(
        path,
        std::ios::binary
    );

    if (!file) {
        throw std::runtime_error(
            "Failed to open: " + path
        );
    }

    file.seekg(
        0,
        std::ios::end
    );

    const std::streamsize bytes =
        file.tellg();

    file.seekg(
        0,
        std::ios::beg
    );

    if (
        bytes < 0
        ||
        bytes
            %
            static_cast<std::streamsize>(
                sizeof(T)
            )
            !=
            0
    ) {
        throw std::runtime_error(
            "Invalid binary size: " + path
        );
    }

    const std::size_t count =
        static_cast<std::size_t>(
            bytes
        )
        /
        sizeof(T);

    std::vector<T> data(
        count
    );

    if (
        bytes > 0
        &&
        !file.read(
            reinterpret_cast<char*>(
                data.data()
            ),
            bytes
        )
    ) {
        throw std::runtime_error(
            "Failed to read: " + path
        );
    }

    return data;
}


void removeTrailingCarriageReturn(
    std::string& value
) {
    if (
        !value.empty()
        &&
        value.back() == '\r'
    ) {
        value.pop_back();
    }
}


std::vector<std::string> splitTab(
    const std::string& line
) {
    std::vector<std::string> fields;

    std::stringstream stream(
        line
    );

    std::string field;

    while (
        std::getline(
            stream,
            field,
            '\t'
        )
    ) {
        removeTrailingCarriageReturn(
            field
        );

        fields.push_back(
            field
        );
    }

    return fields;
}


bool parseBool(
    const std::string& value
) {
    if (value == "1") {
        return true;
    }

    if (value == "0") {
        return false;
    }

    throw std::runtime_error(
        "Invalid bool field: [" + value + "]"
    );
}


std::vector<ExpectedCase> readExpectedCases(
    const std::string& path
) {
    std::ifstream file(
        path
    );

    if (!file) {
        throw std::runtime_error(
            "Failed to open: " + path
        );
    }


    std::string header;

    if (
        !std::getline(
            file,
            header
        )
    ) {
        throw std::runtime_error(
            "Expected TSV is empty"
        );
    }

    removeTrailingCarriageReturn(
        header
    );


    const std::vector<std::string>
        header_fields =
            splitTab(
                header
            );


    if (
        header_fields.size()
        !=
        24
    ) {
        throw std::runtime_error(
            "Expected TSV header field count mismatch"
        );
    }


    std::vector<ExpectedCase> cases;

    std::string line;


    while (
        std::getline(
            file,
            line
        )
    ) {
        removeTrailingCarriageReturn(
            line
        );

        if (line.empty()) {
            continue;
        }


        const std::vector<std::string>
            fields =
                splitTab(
                    line
                );


        if (
            fields.size()
            !=
            24
        ) {
            throw std::runtime_error(
                "Expected TSV row field count mismatch"
            );
        }


        ExpectedCase item;


        item.name =
            fields[0];

        item.extra_right_only =
            static_cast<std::size_t>(
                std::stoull(
                    fields[1]
                )
            );

        item.valid =
            parseBool(
                fields[2]
            );

        item.final_id =
            static_cast<std::int32_t>(
                std::stoi(
                    fields[3]
                )
            );

        item.stage =
            fields[4];

        item.is_nosign =
            parseBool(
                fields[5]
            );

        item.usage =
            fields[6];

        item.source_mode =
            fields[7];

        item.selected_frames =
            static_cast<std::size_t>(
                std::stoull(
                    fields[8]
                )
            );

        item.total =
            static_cast<std::size_t>(
                std::stoull(
                    fields[9]
                )
            );

        item.left =
            static_cast<std::size_t>(
                std::stoull(
                    fields[10]
                )
            );

        item.right =
            static_cast<std::size_t>(
                std::stoull(
                    fields[11]
                )
            );

        item.both =
            static_cast<std::size_t>(
                std::stoull(
                    fields[12]
                )
            );

        item.both_ratio =
            std::stod(
                fields[13]
            );

        item.c4_evaluated =
            parseBool(
                fields[14]
            );

        item.c4_prediction =
            std::stoi(
                fields[15]
            );

        item.d_sign =
            std::stod(
                fields[16]
            );

        item.d_nosign =
            std::stod(
                fields[17]
            );

        item.c4_margin =
            std::stod(
                fields[18]
            );

        item.onehand_ran =
            parseBool(
                fields[19]
            );

        item.twohand_ran =
            parseBool(
                fields[20]
            );

        item.temp_checked =
            parseBool(
                fields[21]
            );

        item.temp_eligible =
            parseBool(
                fields[22]
            );

        item.temp_rescued =
            parseBool(
                fields[23]
            );


        cases.push_back(
            item
        );
    }


    if (
        cases.size()
        !=
        4
    ) {
        throw std::runtime_error(
            "Expected exactly 4 runtime cases"
        );
    }


    return cases;
}


sign_engine::HandLandmarks buildHand(
    const std::vector<float>& raw,
    std::size_t frame_index
) {
    sign_engine::HandLandmarks hand;


    for (
        std::size_t landmark = 0;
        landmark < LANDMARK_COUNT;
        ++landmark
    ) {
        const std::size_t offset =
            (
                frame_index
                *
                LANDMARK_COUNT
                +
                landmark
            )
            *
            2;


        hand.points[
            landmark
        ].x =
            raw[
                offset
            ];

        hand.points[
            landmark
        ].y =
            raw[
                offset + 1
            ];
    }


    return hand;
}


sign_engine::RecordingFrames buildRecording(
    const std::vector<float>& raw_left,
    const std::vector<float>& raw_right,
    std::size_t extra_right_only
) {
    sign_engine::RecordingFrames frames;


    frames.reserve(
        REAL01_FRAMES
        +
        extra_right_only
    );


    for (
        std::size_t frame = 0;
        frame < REAL01_FRAMES;
        ++frame
    ) {
        sign_engine::FrameHands item;


        item.has_left =
            true;

        item.has_right =
            true;


        item.left =
            buildHand(
                raw_left,
                frame
            );

        item.right =
            buildHand(
                raw_right,
                frame
            );


        frames.push_back(
            item
        );
    }


    for (
        std::size_t index = 0;
        index < extra_right_only;
        ++index
    ) {
        const std::size_t source_index =
            index
            %
            REAL01_FRAMES;


        sign_engine::FrameHands item;


        item.has_left =
            false;

        item.has_right =
            true;


        item.right =
            buildHand(
                raw_right,
                source_index
            );


        frames.push_back(
            item
        );
    }


    return frames;
}


bool nearDouble(
    double actual,
    double expected
) {
    return (
        std::fabs(
            actual
            -
            expected
        )
        <=
        DOUBLE_TOLERANCE
    );
}


std::string usageToString(
    sign_engine::UsageType usage
) {
    if (
        usage
        ==
        sign_engine::UsageType::OneHand
    ) {
        return "one_hand";
    }


    if (
        usage
        ==
        sign_engine::UsageType::TwoHand
    ) {
        return "two_hand";
    }


    return "invalid";
}


void printBoolResult(
    const std::string& label,
    bool actual,
    bool expected,
    bool pass
) {
    std::cout
        << std::left
        << std::setw(
            22
        )
        << label
        << ": "
        << actual
        << " / expected "
        << expected
        << " -> "
        << (
            pass
            ?
            "PASS"
            :
            "FAIL"
        )
        << '\n';
}


}  // namespace


int main() {
    try {
        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "sign_runtime_routes_frozen/";

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";


        const std::vector<float> raw_left =
            readBinary<float>(
                fixture_dir
                +
                "input_real01_left_87x21x2.bin"
            );


        const std::vector<float> raw_right =
            readBinary<float>(
                fixture_dir
                +
                "input_real01_right_87x21x2.bin"
            );


        const std::size_t expected_raw_count =
            REAL01_FRAMES
            *
            LANDMARK_COUNT
            *
            2;


        if (
            raw_left.size()
            !=
            expected_raw_count
            ||
            raw_right.size()
            !=
            expected_raw_count
        ) {
            throw std::runtime_error(
                "REAL01 raw fixture size mismatch"
            );
        }


        const std::vector<ExpectedCase> expected_cases =
            readExpectedCases(
                fixture_dir
                +
                "expected_cases.tsv"
            );


        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        bool all_pass =
            true;

        std::size_t passed_cases =
            0;


        std::cout
            << std::fixed
            << std::setprecision(
                12
            );


        std::cout
            << "========================================\n";

        std::cout
            << "SIGN RUNTIME PRODUCTION REGRESSION\n";

        std::cout
            << "========================================\n\n";


        for (
            const ExpectedCase& expected :
            expected_cases
        ) {
            const sign_engine::RecordingFrames frames =
                buildRecording(
                    raw_left,
                    raw_right,
                    expected.extra_right_only
                );


            const sign_engine::SignRecognitionResult actual =
                sign_engine::classifyRecording(
                    frames,
                    runtime
                );


            bool case_pass =
                true;


            const bool status_pass =
                actual.status
                ==
                sign_engine::SignRuntimeStatus::Success;


            const bool valid_pass =
                actual.valid
                ==
                expected.valid;


            const bool final_id_pass =
                actual.final_id
                ==
                expected.final_id;


            const bool stage_pass =
                actual.stage
                ==
                expected.stage;


            const bool nosign_pass =
                actual.is_nosign
                ==
                expected.is_nosign;


            const std::string actual_usage =
                usageToString(
                    actual.usage_type
                );


            const bool usage_pass =
                actual_usage
                ==
                expected.usage;


            const bool source_mode_pass =
                actual.source_mode
                ==
                expected.source_mode;


            const bool selected_frames_pass =
                actual.selected_frames
                ==
                expected.selected_frames;


            const bool total_pass =
                actual
                    .recording_stats
                    .total_frames
                ==
                expected.total;


            const bool left_pass =
                actual
                    .recording_stats
                    .left_count
                ==
                expected.left;


            const bool right_pass =
                actual
                    .recording_stats
                    .right_count
                ==
                expected.right;


            const bool both_pass =
                actual
                    .recording_stats
                    .both_count
                ==
                expected.both;


            const bool both_ratio_pass =
                nearDouble(
                    actual
                        .recording_stats
                        .both_ratio,
                    expected.both_ratio
                );


            const bool c4_evaluated_pass =
                actual.c4_evaluated
                ==
                expected.c4_evaluated;


            bool c4_prediction_pass =
                true;

            bool d_sign_pass =
                true;

            bool d_nosign_pass =
                true;

            bool c4_margin_pass =
                true;


            if (
                expected.c4_evaluated
            ) {
                c4_prediction_pass =
                    actual
                        .c4_gate
                        .prediction
                    ==
                    expected.c4_prediction;


                d_sign_pass =
                    nearDouble(
                        actual
                            .c4_gate
                            .d_sign,
                        expected.d_sign
                    );


                d_nosign_pass =
                    nearDouble(
                        actual
                            .c4_gate
                            .d_nosign,
                        expected.d_nosign
                    );


                c4_margin_pass =
                    nearDouble(
                        actual
                            .c4_gate
                            .margin_nosign_minus_sign,
                        expected.c4_margin
                    );
            }


            const bool onehand_ran_pass =
                actual.onehand_ran
                ==
                expected.onehand_ran;


            const bool twohand_ran_pass =
                actual.twohand_ran
                ==
                expected.twohand_ran;


            const bool temp_checked_pass =
                actual.temp_checked
                ==
                expected.temp_checked;


            const bool temp_eligible_actual =
                actual.temp_checked
                &&
                actual.temp_rescue.eligible;


            const bool temp_eligible_pass =
                temp_eligible_actual
                ==
                expected.temp_eligible;


            const bool temp_rescued_actual =
                actual.temp_checked
                &&
                actual.temp_rescue.rescued;


            const bool temp_rescued_pass =
                temp_rescued_actual
                ==
                expected.temp_rescued;


            case_pass =
                status_pass
                &&
                valid_pass
                &&
                final_id_pass
                &&
                stage_pass
                &&
                nosign_pass
                &&
                usage_pass
                &&
                source_mode_pass
                &&
                selected_frames_pass
                &&
                total_pass
                &&
                left_pass
                &&
                right_pass
                &&
                both_pass
                &&
                both_ratio_pass
                &&
                c4_evaluated_pass
                &&
                c4_prediction_pass
                &&
                d_sign_pass
                &&
                d_nosign_pass
                &&
                c4_margin_pass
                &&
                onehand_ran_pass
                &&
                twohand_ran_pass
                &&
                temp_checked_pass
                &&
                temp_eligible_pass
                &&
                temp_rescued_pass;


            if (!case_pass) {
                all_pass =
                    false;
            }
            else {
                ++passed_cases;
            }


            std::cout
                << "----------------------------------------\n";

            std::cout
                << expected.name
                << '\n';

            std::cout
                << "----------------------------------------\n";


            std::cout
                << "extra RIGHT_ONLY       : "
                << expected.extra_right_only
                << '\n';


            std::cout
                << "status Success         : "
                << status_pass
                << " -> "
                << (
                    status_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            printBoolResult(
                "valid",
                actual.valid,
                expected.valid,
                valid_pass
            );


            std::cout
                << std::left
                << std::setw(
                    22
                )
                << "source mode"
                << ": "
                << actual.source_mode
                << " / expected "
                << expected.source_mode
                << " -> "
                << (
                    source_mode_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << std::left
                << std::setw(
                    22
                )
                << "usage"
                << ": "
                << actual_usage
                << " / expected "
                << expected.usage
                << " -> "
                << (
                    usage_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << std::left
                << std::setw(
                    22
                )
                << "selected frames"
                << ": "
                << actual.selected_frames
                << " / expected "
                << expected.selected_frames
                << " -> "
                << (
                    selected_frames_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << std::left
                << std::setw(
                    22
                )
                << "both ratio"
                << ": "
                << actual
                       .recording_stats
                       .both_ratio
                << " / expected "
                << expected.both_ratio
                << " -> "
                << (
                    both_ratio_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            printBoolResult(
                "C4 evaluated",
                actual.c4_evaluated,
                expected.c4_evaluated,
                c4_evaluated_pass
            );


            if (
                expected.c4_evaluated
            ) {
                std::cout
                    << std::left
                    << std::setw(
                        22
                    )
                    << "C4 prediction"
                    << ": "
                    << actual
                           .c4_gate
                           .prediction
                    << " / expected "
                    << expected.c4_prediction
                    << " -> "
                    << (
                        c4_prediction_pass
                        ?
                        "PASS"
                        :
                        "FAIL"
                    )
                    << '\n';


                std::cout
                    << std::left
                    << std::setw(
                        22
                    )
                    << "C4 d_sign"
                    << ": "
                    << actual
                           .c4_gate
                           .d_sign
                    << " / expected "
                    << expected.d_sign
                    << " -> "
                    << (
                        d_sign_pass
                        ?
                        "PASS"
                        :
                        "FAIL"
                    )
                    << '\n';


                std::cout
                    << std::left
                    << std::setw(
                        22
                    )
                    << "C4 d_nosign"
                    << ": "
                    << actual
                           .c4_gate
                           .d_nosign
                    << " / expected "
                    << expected.d_nosign
                    << " -> "
                    << (
                        d_nosign_pass
                        ?
                        "PASS"
                        :
                        "FAIL"
                    )
                    << '\n';
            }


            printBoolResult(
                "onehand ran",
                actual.onehand_ran,
                expected.onehand_ran,
                onehand_ran_pass
            );


            printBoolResult(
                "twohand ran",
                actual.twohand_ran,
                expected.twohand_ran,
                twohand_ran_pass
            );


            printBoolResult(
                "TEMP checked",
                actual.temp_checked,
                expected.temp_checked,
                temp_checked_pass
            );


            printBoolResult(
                "TEMP eligible",
                temp_eligible_actual,
                expected.temp_eligible,
                temp_eligible_pass
            );


            printBoolResult(
                "TEMP rescued",
                temp_rescued_actual,
                expected.temp_rescued,
                temp_rescued_pass
            );


            std::cout
                << std::left
                << std::setw(
                    22
                )
                << "final_id"
                << ": "
                << actual.final_id
                << " / expected "
                << expected.final_id
                << " -> "
                << (
                    final_id_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << std::left
                << std::setw(
                    22
                )
                << "stage"
                << ": "
                << actual.stage
                << " / expected "
                << expected.stage
                << " -> "
                << (
                    stage_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            printBoolResult(
                "is_nosign",
                actual.is_nosign,
                expected.is_nosign,
                nosign_pass
            );


            std::cout
                << "CASE RESULT            : "
                << (
                    case_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << "\n\n";
        }


        std::cout
            << "========================================\n";

        std::cout
            << "PRODUCTION ROUTE SUMMARY\n";

        std::cout
            << "========================================\n";


        std::cout
            << "Frozen routes matched : "
            << passed_cases
            << " / "
            << expected_cases.size()
            << '\n';


        std::cout
            << "Tolerance             : "
            << DOUBLE_TOLERANCE
            << '\n';


        std::cout
            << "\n========================================\n";


        if (all_pass) {
            std::cout
                << "SIGN RUNTIME PRODUCTION REGRESSION PASS\n";

            std::cout
                << "4 / 4 FROZEN ROUTES MATCH\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "SIGN RUNTIME PRODUCTION REGRESSION FAIL\n";

        std::cout
            << "========================================\n";

        return 1;
    }
    catch (
        const std::exception& e
    ) {
        std::cerr
            << "ERROR: "
            << e.what()
            << '\n';

        return 1;
    }
}