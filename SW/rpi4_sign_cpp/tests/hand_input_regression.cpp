#include "hand_input.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

constexpr std::int32_t WIDTH =
    640;

constexpr std::int32_t HEIGHT =
    480;

constexpr std::size_t LANDMARK_COUNT =
    sign_engine::HAND_LANDMARK_COUNT;

constexpr std::size_t XY_COUNT =
    LANDMARK_COUNT * 2;


struct TestCase {
    std::string name;

    std::vector<
        sign_engine::NormalizedHandDetection
    > detections;
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


// ============================================================
// Python fixture:
//
// x32 = np.float32(
//     (seed + 0.0137 * index) % 1.0
// )
//
// y32 = np.float32(
//     (seed * 0.5 + 0.0213 * index) % 1.0
// )
//
// C++:
//
// calculate in double
// -> cast to float
//
// This mirrors the fixture's MediaPipe float32 quantization.
// ============================================================

sign_engine::NormalizedHandDetection
makeDetection(
    const std::string& label,
    double confidence,
    double seed
) {
    sign_engine::NormalizedHandDetection
        detection;


    detection.label =
        label;


    // Python fixture:
    //
    // confidence32 = np.float32(confidence)
    // score = float(confidence32)
    //
    const float confidence32 =
        static_cast<float>(
            confidence
        );


    detection.confidence =
        static_cast<double>(
            confidence32
        );


    for (
        std::size_t index = 0;
        index < LANDMARK_COUNT;
        ++index
    ) {
        double x =
            seed
            +
            0.0137
            *
            static_cast<double>(
                index
            );


        double y =
            seed
            *
            0.5
            +
            0.0213
            *
            static_cast<double>(
                index
            );


        x =
            std::fmod(
                x,
                1.0
            );


        y =
            std::fmod(
                y,
                1.0
            );


        detection
            .landmarks[index]
            .x =
                static_cast<float>(
                    x
                );


        detection
            .landmarks[index]
            .y =
                static_cast<float>(
                    y
                );
    }


    return detection;
}


std::vector<TestCase> buildCases() {
    std::vector<TestCase> cases;


    // ========================================================
    // 1. Normal LEFT + RIGHT
    // ========================================================

    cases.push_back(
        {
            "both_normal",

            {
                makeDetection(
                    "Left",
                    0.81,
                    0.11
                ),

                makeDetection(
                    "Right",
                    0.92,
                    0.37
                ),
            },
        }
    );


    // ========================================================
    // 2. Duplicate LEFT
    //
    // 0.90 > 0.60
    // second LEFT must replace first.
    // ========================================================

    cases.push_back(
        {
            "duplicate_left_higher",

            {
                makeDetection(
                    "Left",
                    0.60,
                    0.15
                ),

                makeDetection(
                    "Left",
                    0.90,
                    0.55
                ),
            },
        }
    );


    // ========================================================
    // 3. Duplicate RIGHT, equal confidence
    //
    // Python uses strict >
    // therefore FIRST RIGHT must remain.
    // ========================================================

    cases.push_back(
        {
            "duplicate_right_equal",

            {
                makeDetection(
                    "Right",
                    0.75,
                    0.21
                ),

                makeDetection(
                    "Right",
                    0.75,
                    0.71
                ),
            },
        }
    );


    // ========================================================
    // 4. Unknown ignored + lowercase accepted
    // ========================================================

    cases.push_back(
        {
            "invalid_label_and_lowercase",

            {
                makeDetection(
                    "Unknown",
                    0.99,
                    0.44
                ),

                makeDetection(
                    "left",
                    0.33,
                    0.63
                ),
            },
        }
    );


    // ========================================================
    // 5. No detections
    // ========================================================

    cases.push_back(
        {
            "empty",
            {},
        }
    );


    return cases;
}


bool compareHandExact(
    const sign_engine::HandLandmarks& actual,
    const std::vector<float>& expected,
    double& max_error
) {
    if (
        expected.size()
        !=
        XY_COUNT
    ) {
        throw std::runtime_error(
            "Expected hand XY size mismatch"
        );
    }


    bool exact =
        true;


    for (
        std::size_t landmark = 0;
        landmark < LANDMARK_COUNT;
        ++landmark
    ) {
        const float actual_x =
            actual
                .points[landmark]
                .x;

        const float actual_y =
            actual
                .points[landmark]
                .y;


        const float expected_x =
            expected[
                landmark * 2
            ];

        const float expected_y =
            expected[
                landmark * 2 + 1
            ];


        const double x_error =
            std::fabs(
                static_cast<double>(
                    actual_x
                )
                -
                static_cast<double>(
                    expected_x
                )
            );


        const double y_error =
            std::fabs(
                static_cast<double>(
                    actual_y
                )
                -
                static_cast<double>(
                    expected_y
                )
            );


        if (
            x_error
            >
            max_error
        ) {
            max_error =
                x_error;
        }


        if (
            y_error
            >
            max_error
        ) {
            max_error =
                y_error;
        }


        // Strict float32 parity.
        if (
            actual_x
            !=
            expected_x
            ||
            actual_y
            !=
            expected_y
        ) {
            exact =
                false;
        }
    }


    return exact;
}


}  // namespace


int main() {
    try {
        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "hand_input_frozen/";


        const std::vector<TestCase> cases =
            buildCases();


        if (
            cases.size()
            !=
            5
        ) {
            throw std::runtime_error(
                "Expected 5 test cases"
            );
        }


        bool all_pass =
            true;

        std::size_t passed_cases =
            0;

        double global_max_error =
            0.0;


        std::cout
            << std::fixed
            << std::setprecision(
                12
            );


        std::cout
            << "========================================\n";

        std::cout
            << "HAND INPUT PYTHON <-> C++ REGRESSION\n";

        std::cout
            << "========================================\n\n";


        for (
            const TestCase& test :
            cases
        ) {
            const std::string prefix =
                fixture_dir
                +
                "expected_"
                +
                test.name;


            const std::vector<std::int32_t>
                expected_flags =
                    readBinary<std::int32_t>(
                        prefix
                        +
                        "_flags.bin"
                    );


            const std::vector<float>
                expected_left =
                    readBinary<float>(
                        prefix
                        +
                        "_left_21x2.bin"
                    );


            const std::vector<float>
                expected_right =
                    readBinary<float>(
                        prefix
                        +
                        "_right_21x2.bin"
                    );


            if (
                expected_flags.size()
                !=
                2
            ) {
                throw std::runtime_error(
                    test.name
                    +
                    ": flags size mismatch"
                );
            }


            if (
                expected_left.size()
                !=
                XY_COUNT
                ||
                expected_right.size()
                !=
                XY_COUNT
            ) {
                throw std::runtime_error(
                    test.name
                    +
                    ": XY fixture size mismatch"
                );
            }


            const bool expected_has_left =
                expected_flags[0]
                !=
                0;


            const bool expected_has_right =
                expected_flags[1]
                !=
                0;


            // =================================================
            // extractFrameHands()
            // =================================================

            const sign_engine::FrameHands actual =
                sign_engine::extractFrameHands(
                    test.detections,
                    WIDTH,
                    HEIGHT
                );


            bool case_pass =
                true;


            const bool left_flag_pass =
                actual.has_left
                ==
                expected_has_left;


            const bool right_flag_pass =
                actual.has_right
                ==
                expected_has_right;


            if (
                !left_flag_pass
                ||
                !right_flag_pass
            ) {
                case_pass =
                    false;
            }


            double case_max_error =
                0.0;


            bool left_xy_pass =
                true;

            bool right_xy_pass =
                true;


            if (
                expected_has_left
            ) {
                if (
                    !actual.has_left
                ) {
                    left_xy_pass =
                        false;
                }
                else {
                    left_xy_pass =
                        compareHandExact(
                            actual.left,
                            expected_left,
                            case_max_error
                        );
                }
            }


            if (
                expected_has_right
            ) {
                if (
                    !actual.has_right
                ) {
                    right_xy_pass =
                        false;
                }
                else {
                    right_xy_pass =
                        compareHandExact(
                            actual.right,
                            expected_right,
                            case_max_error
                        );
                }
            }


            if (
                !left_xy_pass
                ||
                !right_xy_pass
            ) {
                case_pass =
                    false;
            }


            if (
                case_max_error
                >
                global_max_error
            ) {
                global_max_error =
                    case_max_error;
            }


            // =================================================
            // appendDetectedFrame()
            //
            // Python capture_sequence():
            //
            // append only when LEFT or RIGHT exists.
            // =================================================

            sign_engine::RecordingFrames
                recording_frames;


            const bool appended =
                sign_engine::appendDetectedFrame(
                    recording_frames,
                    test.detections,
                    WIDTH,
                    HEIGHT
                );


            const bool expected_appended =
                expected_has_left
                ||
                expected_has_right;


            const bool append_return_pass =
                appended
                ==
                expected_appended;


            const std::size_t expected_size =
                expected_appended
                ?
                1
                :
                0;


            const bool append_size_pass =
                recording_frames.size()
                ==
                expected_size;


            if (
                !append_return_pass
                ||
                !append_size_pass
            ) {
                case_pass =
                    false;
            }


            // If appended, appended FrameHands must equal
            // extractFrameHands() result exactly.
            bool append_frame_pass =
                true;


            if (
                expected_appended
            ) {
                const sign_engine::FrameHands&
                    appended_frame =
                        recording_frames[0];


                if (
                    appended_frame.has_left
                    !=
                    actual.has_left
                    ||
                    appended_frame.has_right
                    !=
                    actual.has_right
                ) {
                    append_frame_pass =
                        false;
                }


                double append_max_error =
                    0.0;


                if (
                    actual.has_left
                ) {
                    if (
                        !compareHandExact(
                            appended_frame.left,
                            expected_left,
                            append_max_error
                        )
                    ) {
                        append_frame_pass =
                            false;
                    }
                }


                if (
                    actual.has_right
                ) {
                    if (
                        !compareHandExact(
                            appended_frame.right,
                            expected_right,
                            append_max_error
                        )
                    ) {
                        append_frame_pass =
                            false;
                    }
                }


                if (
                    append_max_error
                    >
                    global_max_error
                ) {
                    global_max_error =
                        append_max_error;
                }
            }


            if (
                !append_frame_pass
            ) {
                case_pass =
                    false;
            }


            if (
                case_pass
            ) {
                ++passed_cases;
            }
            else {
                all_pass =
                    false;
            }


            // =================================================
            // Report
            // =================================================

            std::cout
                << "----------------------------------------\n";

            std::cout
                << test.name
                << '\n';

            std::cout
                << "----------------------------------------\n";


            std::cout
                << "LEFT flag          : "
                << actual.has_left
                << " / expected "
                << expected_has_left
                << " -> "
                << (
                    left_flag_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << "RIGHT flag         : "
                << actual.has_right
                << " / expected "
                << expected_has_right
                << " -> "
                << (
                    right_flag_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << "LEFT XY exact      : "
                << (
                    left_xy_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << "RIGHT XY exact     : "
                << (
                    right_xy_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << "XY max error       : "
                << case_max_error
                << '\n';


            std::cout
                << "append return      : "
                << appended
                << " / expected "
                << expected_appended
                << " -> "
                << (
                    append_return_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << "recording size     : "
                << recording_frames.size()
                << " / expected "
                << expected_size
                << " -> "
                << (
                    append_size_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << "appended frame     : "
                << (
                    append_frame_pass
                    ?
                    "PASS"
                    :
                    "FAIL"
                )
                << '\n';


            std::cout
                << "CASE RESULT        : "
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
            << "HAND INPUT SUMMARY\n";

        std::cout
            << "========================================\n";


        std::cout
            << "Cases matched      : "
            << passed_cases
            << " / "
            << cases.size()
            << '\n';


        std::cout
            << "Global XY max error: "
            << global_max_error
            << '\n';


        std::cout
            << "Coordinate compare : exact float32\n";


        std::cout
            << "\n========================================\n";


        if (
            all_pass
        ) {
            std::cout
                << "HAND INPUT PYTHON <-> C++ REGRESSION PASS\n";

            std::cout
                << "5 / 5 INPUT SEMANTICS MATCH\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "HAND INPUT PYTHON <-> C++ REGRESSION FAIL\n";

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