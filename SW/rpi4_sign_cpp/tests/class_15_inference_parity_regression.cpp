#include "onehand_classifier.hpp"
#include "runtime_data.hpp"
#include "twohand_classifier.hpp"

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

constexpr std::size_t ONEHAND_COUNT = 42;
constexpr std::size_t TWOHAND_COUNT = 60;

constexpr std::size_t ONEHAND_RANKING_COUNT = 6;
constexpr std::size_t TWOHAND_RANKING_COUNT = 9;

constexpr std::size_t SAMPLE_DIM =
    sign_engine::TARGET_FRAMES
    *
    sign_engine::LOCAL_FEATURE_DIM;

constexpr double TOLERANCE =
    1.0e-5;


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

    const std::streamsize byte_size =
        file.tellg();

    file.seekg(
        0,
        std::ios::beg
    );

    if (
        byte_size < 0
        ||
        byte_size
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
            byte_size
        )
        /
        sizeof(T);

    std::vector<T> data(
        count
    );

    if (
        byte_size > 0
        &&
        !file.read(
            reinterpret_cast<char*>(
                data.data()
            ),
            byte_size
        )
    ) {
        throw std::runtime_error(
            "Failed to read: " + path
        );
    }

    return data;
}


std::vector<std::string> readLines(
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

    std::vector<std::string> lines;

    std::string line;

    while (
        std::getline(
            file,
            line
        )
    ) {
        if (
            !line.empty()
            &&
            line.back() == '\r'
        ) {
            line.pop_back();
        }

        lines.push_back(
            line
        );
    }

    return lines;
}


std::vector<float> getSample(
    const std::vector<float>& flat,
    std::size_t sample_index
) {
    const std::size_t begin =
        sample_index
        *
        SAMPLE_DIM;

    const std::size_t end =
        begin
        +
        SAMPLE_DIM;

    if (
        end
        >
        flat.size()
    ) {
        throw std::runtime_error(
            "getSample: out of range"
        );
    }

    return std::vector<float>(
        flat.begin() + begin,
        flat.begin() + end
    );
}


double absoluteError(
    double actual,
    double expected
) {
    return std::fabs(
        actual
        -
        expected
    );
}


double compareFloatArrays(
    const std::vector<float>& actual,
    const std::vector<float>& expected,
    bool& pass
) {
    if (
        actual.size()
        !=
        expected.size()
    ) {
        pass =
            false;

        return 0.0;
    }

    double max_error =
        0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        const double error =
            absoluteError(
                actual[i],
                expected[i]
            );

        if (
            error
            >
            max_error
        ) {
            max_error =
                error;
        }

        if (
            error
            >
            TOLERANCE
        ) {
            pass =
                false;
        }
    }

    return max_error;
}


}  // namespace


int main() {
    try {
        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";

        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "class_15_inference_frozen/";


        // ====================================================
        // Runtime
        // ====================================================

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        // ====================================================
        // Frozen Python fixture inputs
        // ====================================================

        const std::vector<float>
            input_onehand =
                readBinary<float>(
                    fixture_dir
                    +
                    "input_onehand_local_42x80x84.bin"
                );

        const std::vector<float>
            input_twohand =
                readBinary<float>(
                    fixture_dir
                    +
                    "input_twohand_local_60x80x84.bin"
                );


        // ====================================================
        // Reference labels
        // ====================================================

        const std::vector<std::int32_t>
            expected_onehand_reference_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_onehand_reference_ids.bin"
                );

        const std::vector<std::int32_t>
            expected_twohand_reference_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_twohand_reference_ids.bin"
                );


        // ====================================================
        // Frozen final IDs
        // ====================================================

        const std::vector<std::int32_t>
            expected_onehand_final_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_onehand_final_ids.bin"
                );

        const std::vector<std::int32_t>
            expected_twohand_final_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_twohand_final_ids.bin"
                );


        // ====================================================
        // Frozen base IDs
        // ====================================================

        const std::vector<std::int32_t>
            expected_onehand_base_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_onehand_base_ids.bin"
                );

        const std::vector<std::int32_t>
            expected_twohand_base_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_twohand_base_ids.bin"
                );


        // ====================================================
        // Frozen base margins
        // ====================================================

        const std::vector<double>
            expected_onehand_base_margins =
                readBinary<double>(
                    fixture_dir
                    +
                    "expected_onehand_base_margins.bin"
                );

        const std::vector<double>
            expected_twohand_base_margins =
                readBinary<double>(
                    fixture_dir
                    +
                    "expected_twohand_base_margins.bin"
                );


        // ====================================================
        // Frozen base rankings
        // ====================================================

        const std::vector<std::int32_t>
            expected_onehand_ranking_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_onehand_base_ranking_ids_42x6.bin"
                );

        const std::vector<float>
            expected_onehand_ranking_scores =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_onehand_base_ranking_scores_42x6.bin"
                );

        const std::vector<std::int32_t>
            expected_twohand_ranking_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_twohand_base_ranking_ids_60x9.bin"
                );

        const std::vector<float>
            expected_twohand_ranking_scores =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_twohand_base_ranking_scores_60x9.bin"
                );


        // ====================================================
        // Frozen stages
        // ====================================================

        const std::vector<std::string>
            expected_onehand_stages =
                readLines(
                    fixture_dir
                    +
                    "expected_onehand_stages.txt"
                );

        const std::vector<std::string>
            expected_twohand_stages =
                readLines(
                    fixture_dir
                    +
                    "expected_twohand_stages.txt"
                );


        // ====================================================
        // Fixture shape checks
        // ====================================================

        if (
            input_onehand.size()
            !=
            ONEHAND_COUNT
            *
            SAMPLE_DIM
        ) {
            throw std::runtime_error(
                "ONE-HAND input fixture size mismatch"
            );
        }

        if (
            input_twohand.size()
            !=
            TWOHAND_COUNT
            *
            SAMPLE_DIM
        ) {
            throw std::runtime_error(
                "TWO-HAND input fixture size mismatch"
            );
        }


        if (
            expected_onehand_reference_ids.size()
                !=
                ONEHAND_COUNT
            ||
            expected_onehand_final_ids.size()
                !=
                ONEHAND_COUNT
            ||
            expected_onehand_base_ids.size()
                !=
                ONEHAND_COUNT
            ||
            expected_onehand_base_margins.size()
                !=
                ONEHAND_COUNT
            ||
            expected_onehand_stages.size()
                !=
                ONEHAND_COUNT
        ) {
            throw std::runtime_error(
                "ONE-HAND expected fixture size mismatch"
            );
        }


        if (
            expected_twohand_reference_ids.size()
                !=
                TWOHAND_COUNT
            ||
            expected_twohand_final_ids.size()
                !=
                TWOHAND_COUNT
            ||
            expected_twohand_base_ids.size()
                !=
                TWOHAND_COUNT
            ||
            expected_twohand_base_margins.size()
                !=
                TWOHAND_COUNT
            ||
            expected_twohand_stages.size()
                !=
                TWOHAND_COUNT
        ) {
            throw std::runtime_error(
                "TWO-HAND expected fixture size mismatch"
            );
        }


        if (
            expected_onehand_ranking_ids.size()
            !=
            ONEHAND_COUNT
            *
            ONEHAND_RANKING_COUNT
            ||
            expected_onehand_ranking_scores.size()
            !=
            ONEHAND_COUNT
            *
            ONEHAND_RANKING_COUNT
        ) {
            throw std::runtime_error(
                "ONE-HAND ranking fixture size mismatch"
            );
        }


        if (
            expected_twohand_ranking_ids.size()
            !=
            TWOHAND_COUNT
            *
            TWOHAND_RANKING_COUNT
            ||
            expected_twohand_ranking_scores.size()
            !=
            TWOHAND_COUNT
            *
            TWOHAND_RANKING_COUNT
        ) {
            throw std::runtime_error(
                "TWO-HAND ranking fixture size mismatch"
            );
        }


        // ====================================================
        // First verify Python fixture uses same runtime inputs.
        // ====================================================

        bool all_pass =
            true;


        const double onehand_input_max_error =
            compareFloatArrays(
                runtime.onehand_local,
                input_onehand,
                all_pass
            );

        const double twohand_input_max_error =
            compareFloatArrays(
                runtime.twohand_local,
                input_twohand,
                all_pass
            );


        bool onehand_reference_order_pass =
            runtime.onehand_class_ids
            ==
            expected_onehand_reference_ids;

        bool twohand_reference_order_pass =
            runtime.twohand_class_ids
            ==
            expected_twohand_reference_ids;


        if (
            !onehand_reference_order_pass
            ||
            !twohand_reference_order_pass
        ) {
            all_pass =
                false;
        }


        // ====================================================
        // Counters / numerical diagnostics
        // ====================================================

        std::size_t onehand_full_match =
            0;

        std::size_t twohand_full_match =
            0;

        std::size_t frozen_self_correct =
            0;

        std::size_t cpp_self_correct =
            0;


        double onehand_margin_max_error =
            0.0;

        double twohand_margin_max_error =
            0.0;

        double onehand_ranking_max_error =
            0.0;

        double twohand_ranking_max_error =
            0.0;


        // ====================================================
        // ONE-HAND 42
        // ====================================================

        std::cout
            << "========================================\n";

        std::cout
            << "15-CLASS PYTHON <-> C++ "
            << "INFERENCE PARITY REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "ONE-HAND 42 REFERENCES\n";

        std::cout
            << "----------------------------------------\n";


        for (
            std::size_t sample_index = 0;
            sample_index < ONEHAND_COUNT;
            ++sample_index
        ) {
            const std::vector<float> local84 =
                getSample(
                    input_onehand,
                    sample_index
                );


            const sign_engine::OneHandResult result =
                sign_engine::classifyOneHand(
                    local84,
                    runtime
                );


            bool sample_pass =
                true;


            const std::int32_t
                expected_reference_id =
                    expected_onehand_reference_ids[
                        sample_index
                    ];


            const std::int32_t
                expected_final_id =
                    expected_onehand_final_ids[
                        sample_index
                    ];


            const std::int32_t
                expected_base_id =
                    expected_onehand_base_ids[
                        sample_index
                    ];


            if (
                expected_final_id
                ==
                expected_reference_id
            ) {
                ++frozen_self_correct;
            }


            if (
                result.final_id
                ==
                expected_reference_id
            ) {
                ++cpp_self_correct;
            }


            if (
                result.final_id
                !=
                expected_final_id
            ) {
                sample_pass =
                    false;
            }


            if (
                result.base_id
                !=
                expected_base_id
            ) {
                sample_pass =
                    false;
            }


            if (
                result.stage
                !=
                expected_onehand_stages[
                    sample_index
                ]
            ) {
                sample_pass =
                    false;
            }


            const double margin_error =
                absoluteError(
                    result.base_margin,
                    expected_onehand_base_margins[
                        sample_index
                    ]
                );


            if (
                margin_error
                >
                onehand_margin_max_error
            ) {
                onehand_margin_max_error =
                    margin_error;
            }


            if (
                margin_error
                >
                TOLERANCE
            ) {
                sample_pass =
                    false;
            }


            if (
                result.base_ranking.size()
                !=
                ONEHAND_RANKING_COUNT
            ) {
                sample_pass =
                    false;
            }
            else {
                for (
                    std::size_t rank = 0;
                    rank
                    <
                    ONEHAND_RANKING_COUNT;
                    ++rank
                ) {
                    const std::size_t fixture_index =
                        sample_index
                        *
                        ONEHAND_RANKING_COUNT
                        +
                        rank;


                    if (
                        result
                            .base_ranking[
                                rank
                            ]
                            .class_id
                        !=
                        expected_onehand_ranking_ids[
                            fixture_index
                        ]
                    ) {
                        sample_pass =
                            false;
                    }


                    const double ranking_error =
                        absoluteError(
                            result
                                .base_ranking[
                                    rank
                                ]
                                .score,
                            expected_onehand_ranking_scores[
                                fixture_index
                            ]
                        );


                    if (
                        ranking_error
                        >
                        onehand_ranking_max_error
                    ) {
                        onehand_ranking_max_error =
                            ranking_error;
                    }


                    if (
                        ranking_error
                        >
                        TOLERANCE
                    ) {
                        sample_pass =
                            false;
                    }
                }
            }


            if (sample_pass) {
                ++onehand_full_match;
            }
            else {
                all_pass =
                    false;

                std::cout
                    << "FAIL sample="
                    << sample_index
                    << " ref="
                    << expected_reference_id
                    << " Python final="
                    << expected_final_id
                    << " C++ final="
                    << result.final_id
                    << " Python base="
                    << expected_base_id
                    << " C++ base="
                    << result.base_id
                    << " Python stage="
                    << expected_onehand_stages[
                           sample_index
                       ]
                    << " C++ stage="
                    << result.stage
                    << '\n';
            }
        }


        // ====================================================
        // TWO-HAND 60
        // ====================================================

        std::cout
            << "\nTWO-HAND 60 REFERENCES\n";

        std::cout
            << "----------------------------------------\n";


        for (
            std::size_t sample_index = 0;
            sample_index < TWOHAND_COUNT;
            ++sample_index
        ) {
            const std::vector<float> local84 =
                getSample(
                    input_twohand,
                    sample_index
                );


            const sign_engine::TwoHandResult result =
                sign_engine::classifyTwoHand(
                    local84,
                    runtime
                );


            bool sample_pass =
                true;


            const std::int32_t
                expected_reference_id =
                    expected_twohand_reference_ids[
                        sample_index
                    ];


            const std::int32_t
                expected_final_id =
                    expected_twohand_final_ids[
                        sample_index
                    ];


            const std::int32_t
                expected_base_id =
                    expected_twohand_base_ids[
                        sample_index
                    ];


            if (
                expected_final_id
                ==
                expected_reference_id
            ) {
                ++frozen_self_correct;
            }


            if (
                result.final_id
                ==
                expected_reference_id
            ) {
                ++cpp_self_correct;
            }


            if (
                result.final_id
                !=
                expected_final_id
            ) {
                sample_pass =
                    false;
            }


            if (
                result.base_id
                !=
                expected_base_id
            ) {
                sample_pass =
                    false;
            }


            if (
                result.stage
                !=
                expected_twohand_stages[
                    sample_index
                ]
            ) {
                sample_pass =
                    false;
            }


            const double margin_error =
                absoluteError(
                    result.base_margin,
                    expected_twohand_base_margins[
                        sample_index
                    ]
                );


            if (
                margin_error
                >
                twohand_margin_max_error
            ) {
                twohand_margin_max_error =
                    margin_error;
            }


            if (
                margin_error
                >
                TOLERANCE
            ) {
                sample_pass =
                    false;
            }


            if (
                result.base_ranking.size()
                !=
                TWOHAND_RANKING_COUNT
            ) {
                sample_pass =
                    false;
            }
            else {
                for (
                    std::size_t rank = 0;
                    rank
                    <
                    TWOHAND_RANKING_COUNT;
                    ++rank
                ) {
                    const std::size_t fixture_index =
                        sample_index
                        *
                        TWOHAND_RANKING_COUNT
                        +
                        rank;


                    if (
                        result
                            .base_ranking[
                                rank
                            ]
                            .class_id
                        !=
                        expected_twohand_ranking_ids[
                            fixture_index
                        ]
                    ) {
                        sample_pass =
                            false;
                    }


                    const double ranking_error =
                        absoluteError(
                            result
                                .base_ranking[
                                    rank
                                ]
                                .score,
                            expected_twohand_ranking_scores[
                                fixture_index
                            ]
                        );


                    if (
                        ranking_error
                        >
                        twohand_ranking_max_error
                    ) {
                        twohand_ranking_max_error =
                            ranking_error;
                    }


                    if (
                        ranking_error
                        >
                        TOLERANCE
                    ) {
                        sample_pass =
                            false;
                    }
                }
            }


            if (sample_pass) {
                ++twohand_full_match;
            }
            else {
                all_pass =
                    false;

                std::cout
                    << "FAIL sample="
                    << sample_index
                    << " ref="
                    << expected_reference_id
                    << " Python final="
                    << expected_final_id
                    << " C++ final="
                    << result.final_id
                    << " Python base="
                    << expected_base_id
                    << " C++ base="
                    << result.base_id
                    << " Python stage="
                    << expected_twohand_stages[
                           sample_index
                       ]
                    << " C++ stage="
                    << result.stage
                    << '\n';
            }
        }


        // ====================================================
        // Expected frozen behavior:
        //
        // 101 / 102 self-correct.
        //
        // ONE-HAND sample 6:
        // reference class 7
        // base class      7
        // final class     2
        // stage:
        // ONEHAND_OFF_HURT_MID40_K3
        //
        // This is NOT a C++ regression if Python and C++ agree.
        // ====================================================

        const bool frozen_behavior_pass =
            frozen_self_correct
            ==
            101;

        const bool cpp_behavior_pass =
            cpp_self_correct
            ==
            frozen_self_correct;


        if (
            !frozen_behavior_pass
            ||
            !cpp_behavior_pass
        ) {
            all_pass =
                false;
        }


        // ====================================================
        // Summary
        // ====================================================

        std::cout
            << std::fixed
            << std::setprecision(
                12
            );


        std::cout
            << "\n========================================\n";

        std::cout
            << "INPUT PARITY\n";

        std::cout
            << "========================================\n";


        std::cout
            << "ONE-HAND Local84 max error : "
            << onehand_input_max_error
            << '\n';

        std::cout
            << "TWO-HAND Local84 max error : "
            << twohand_input_max_error
            << '\n';

        std::cout
            << "ONE-HAND reference order   : "
            << (
                onehand_reference_order_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "TWO-HAND reference order   : "
            << (
                twohand_reference_order_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "\n========================================\n";

        std::cout
            << "INFERENCE PARITY\n";

        std::cout
            << "========================================\n";


        std::cout
            << "ONE-HAND full match        : "
            << onehand_full_match
            << " / "
            << ONEHAND_COUNT
            << '\n';

        std::cout
            << "TWO-HAND full match        : "
            << twohand_full_match
            << " / "
            << TWOHAND_COUNT
            << '\n';

        std::cout
            << "TOTAL full match           : "
            << (
                onehand_full_match
                +
                twohand_full_match
            )
            << " / 102\n";


        std::cout
            << "\nONE-HAND margin max error  : "
            << onehand_margin_max_error
            << '\n';

        std::cout
            << "ONE-HAND ranking max error : "
            << onehand_ranking_max_error
            << '\n';

        std::cout
            << "TWO-HAND margin max error  : "
            << twohand_margin_max_error
            << '\n';

        std::cout
            << "TWO-HAND ranking max error : "
            << twohand_ranking_max_error
            << '\n';


        std::cout
            << "\n========================================\n";

        std::cout
            << "FROZEN BEHAVIOR\n";

        std::cout
            << "========================================\n";


        std::cout
            << "Python self-correct       : "
            << frozen_self_correct
            << " / 102"
            << " -> "
            << (
                frozen_behavior_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "C++ self-correct          : "
            << cpp_self_correct
            << " / 102"
            << " -> "
            << (
                cpp_behavior_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "\nKnown frozen exception:\n";

        std::cout
            << "ONE-HAND sample 6 "
            << "reference=7(HURT), "
            << "final=2(OFF), "
            << "stage=ONEHAND_OFF_HURT_MID40_K3\n";


        std::cout
            << "\nTolerance                 : "
            << TOLERANCE
            << '\n';


        std::cout
            << "\n========================================\n";


        if (all_pass) {
            std::cout
                << "15-CLASS PYTHON <-> C++ "
                << "INFERENCE PARITY REGRESSION PASS\n";

            std::cout
                << "102 / 102 FROZEN OUTPUTS MATCH\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "15-CLASS PYTHON <-> C++ "
            << "INFERENCE PARITY REGRESSION FAIL\n";

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