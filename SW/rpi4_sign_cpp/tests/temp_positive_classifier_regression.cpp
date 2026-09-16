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

constexpr float TOLERANCE =
    1.0e-5f;


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


std::string readText(
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

    std::string value;

    std::getline(
        file,
        value
    );

    return value;
}


bool near(
    float actual,
    float expected
) {
    return std::fabs(
        actual - expected
    )
    <=
    TOLERANCE;
}


}  // namespace


int main() {
    try {
        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "temp_positive_real01/";

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";


        // ====================================================
        // Python frozen 07g fixture
        // ====================================================

        const std::vector<float> local84 =
            readBinary<float>(
                fixture_dir
                +
                "input_local84_80x84.bin"
            );

        const std::vector<std::int32_t>
            expected_ranking_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_base_ranking_class_ids.bin"
                );

        const std::vector<float>
            expected_ranking_scores =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_base_ranking_scores.bin"
                );

        const std::vector<std::int32_t>
            expected_base_id_data =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_base_id.bin"
                );

        const std::vector<std::int32_t>
            expected_final_id_data =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_final_id.bin"
                );

        const std::vector<float>
            expected_base_margin_data =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_base_margin.bin"
                );

        const std::string expected_stage =
            readText(
                fixture_dir
                +
                "expected_stage.txt"
            );


        // ====================================================
        // Fixture validation
        // ====================================================

        const std::size_t expected_local_size =
            sign_engine::TARGET_FRAMES
            *
            sign_engine::LOCAL_FEATURE_DIM;

        if (
            local84.size()
            !=
            expected_local_size
        ) {
            throw std::runtime_error(
                "Local84 fixture size mismatch"
            );
        }

        if (
            expected_base_id_data.size()
            !=
            1
        ) {
            throw std::runtime_error(
                "expected_base_id size mismatch"
            );
        }

        if (
            expected_final_id_data.size()
            !=
            1
        ) {
            throw std::runtime_error(
                "expected_final_id size mismatch"
            );
        }

        if (
            expected_base_margin_data.size()
            !=
            1
        ) {
            throw std::runtime_error(
                "expected_base_margin size mismatch"
            );
        }

        if (
            expected_ranking_ids.size()
            !=
            expected_ranking_scores.size()
        ) {
            throw std::runtime_error(
                "expected ranking size mismatch"
            );
        }


        // ====================================================
        // C++ runtime
        // ====================================================

        const sign_engine::RuntimeData runtime_data =
            sign_engine::loadRuntimeData(
                runtime_dir
            );

        const sign_engine::TwoHandResult result =
            sign_engine::classifyTwoHand(
                local84,
                runtime_data
            );


        const std::int32_t expected_base_id =
            expected_base_id_data[0];

        const std::int32_t expected_final_id =
            expected_final_id_data[0];

        const float expected_base_margin =
            expected_base_margin_data[0];


        bool all_pass =
            true;


        // ====================================================
        // Main result comparisons
        // ====================================================

        const bool base_id_pass =
            result.base_id
            ==
            expected_base_id;

        const bool final_id_pass =
            result.final_id
            ==
            expected_final_id;

        const bool stage_pass =
            result.stage
            ==
            expected_stage;

        const bool margin_pass =
            near(
                result.base_margin,
                expected_base_margin
            );

        const bool ranking_count_pass =
            result.base_ranking.size()
            ==
            expected_ranking_ids.size();


        all_pass =
            base_id_pass
            &&
            final_id_pass
            &&
            stage_pass
            &&
            margin_pass
            &&
            ranking_count_pass;


        // ====================================================
        // Ranking numerical comparison
        // ====================================================

        float max_abs_error =
            0.0f;

        double sum_abs_error =
            0.0;

        std::size_t compared_scores =
            0;


        if (
            ranking_count_pass
        ) {
            for (
                std::size_t i = 0;
                i
                <
                result.base_ranking.size();
                ++i
            ) {
                const std::int32_t actual_class_id =
                    result
                        .base_ranking[i]
                        .class_id;

                const float actual_score =
                    result
                        .base_ranking[i]
                        .score;

                const std::int32_t expected_class_id =
                    expected_ranking_ids[i];

                const float expected_score =
                    expected_ranking_scores[i];


                if (
                    actual_class_id
                    !=
                    expected_class_id
                ) {
                    all_pass =
                        false;
                }


                const float abs_error =
                    std::fabs(
                        actual_score
                        -
                        expected_score
                    );

                if (
                    abs_error
                    >
                    max_abs_error
                ) {
                    max_abs_error =
                        abs_error;
                }

                sum_abs_error +=
                    static_cast<double>(
                        abs_error
                    );

                ++compared_scores;


                if (
                    abs_error
                    >
                    TOLERANCE
                ) {
                    all_pass =
                        false;
                }
            }
        }


        const double mean_abs_error =
            (
                compared_scores > 0
            )
            ?
            (
                sum_abs_error
                /
                static_cast<double>(
                    compared_scores
                )
            )
            :
            0.0;


        // ====================================================
        // Output
        // ====================================================

        std::cout
            << std::fixed
            << std::setprecision(
                12
            );


        std::cout
            << "========================================\n";

        std::cout
            << "TEMP POSITIVE CLASSIFIER REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "fixture Local84 size : "
            << local84.size()
            << " / expected "
            << expected_local_size
            << '\n';


        std::cout
            << "\nRESULT\n";

        std::cout
            << "base_id              : "
            << result.base_id
            << " / expected "
            << expected_base_id
            << " -> "
            << (
                base_id_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "final_id             : "
            << result.final_id
            << " / expected "
            << expected_final_id
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
            << "stage                : "
            << result.stage
            << " / expected "
            << expected_stage
            << " -> "
            << (
                stage_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "base_margin          : "
            << result.base_margin
            << " / expected "
            << expected_base_margin
            << " -> "
            << (
                margin_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "\nBASE RANKING\n";


        if (
            ranking_count_pass
        ) {
            for (
                std::size_t i = 0;
                i
                <
                result.base_ranking.size();
                ++i
            ) {
                const std::int32_t actual_class_id =
                    result
                        .base_ranking[i]
                        .class_id;

                const float actual_score =
                    result
                        .base_ranking[i]
                        .score;

                const std::int32_t expected_class_id =
                    expected_ranking_ids[i];

                const float expected_score =
                    expected_ranking_scores[i];

                const float error =
                    std::fabs(
                        actual_score
                        -
                        expected_score
                    );


                std::cout
                    << "  "
                    << (
                        i + 1
                    )
                    << ". class "
                    << actual_class_id
                    << " / expected "
                    << expected_class_id
                    << " | score "
                    << actual_score
                    << " / expected "
                    << expected_score
                    << " | error "
                    << error
                    << '\n';
            }
        }
        else {
            std::cout
                << "ranking count mismatch: "
                << result.base_ranking.size()
                << " / expected "
                << expected_ranking_ids.size()
                << '\n';
        }


        std::cout
            << "\nNUMERICAL ERROR\n";

        std::cout
            << "max abs error         : "
            << max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << mean_abs_error
            << '\n';

        std::cout
            << "tolerance             : "
            << TOLERANCE
            << '\n';


        std::cout
            << "\nTEMP target class 12 : "
            << (
                result.final_id
                ==
                sign_engine::TWOHAND_TEMP_ID
            )
            << " / expected 1\n";


        if (
            result.final_id
            !=
            sign_engine::TWOHAND_TEMP_ID
        ) {
            all_pass =
                false;
        }


        std::cout
            << "\n========================================\n";


        if (
            all_pass
        ) {
            std::cout
                << "TEMP POSITIVE CLASSIFIER REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "TEMP POSITIVE CLASSIFIER REGRESSION FAIL\n";

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