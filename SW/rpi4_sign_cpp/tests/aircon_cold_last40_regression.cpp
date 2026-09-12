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

constexpr std::size_t FRAME_COUNT =
    80;

constexpr std::size_t LOCAL_DIM =
    84;

constexpr std::size_t REFERENCE_COUNT =
    60;

constexpr double FLOAT_TOLERANCE =
    1e-5;


// ============================================================
// Stage codes
// ============================================================

constexpr std::int32_t STAGE_BASE =
    0;

constexpr std::int32_t STAGE_HOT_RESCUE =
    1;

constexpr std::int32_t STAGE_AIRCON_COLD_LAST40 =
    2;


// ============================================================
// Binary reader
// ============================================================

template <typename T>
std::vector<T> readBinary(
    const std::string& path,
    std::size_t expected_count
) {
    std::ifstream file(
        path,
        std::ios::binary | std::ios::ate
    );

    if (!file.is_open()) {
        throw std::runtime_error(
            "Failed to open file: "
            +
            path
        );
    }

    const std::streamsize file_size =
        file.tellg();

    const std::size_t expected_bytes =
        expected_count
        *
        sizeof(T);

    if (
        file_size < 0
        ||
        static_cast<std::size_t>(
            file_size
        )
        !=
        expected_bytes
    ) {
        throw std::runtime_error(
            "Invalid file size: "
            +
            path
        );
    }

    file.seekg(
        0,
        std::ios::beg
    );

    std::vector<T> data(
        expected_count
    );

    if (
        !file.read(
            reinterpret_cast<char*>(
                data.data()
            ),
            static_cast<std::streamsize>(
                expected_bytes
            )
        )
    ) {
        throw std::runtime_error(
            "Failed to read file: "
            +
            path
        );
    }

    return data;
}


// ============================================================
// Stage -> fixture code
// ============================================================

std::int32_t stageToCode(
    const std::string& stage
) {
    if (
        stage
        ==
        "TWOHAND_BASE_LOCAL"
    ) {
        return STAGE_BASE;
    }

    if (
        stage
        ==
        "TWOHAND_HOT_HANDSHAPE_RESCUE"
    ) {
        return STAGE_HOT_RESCUE;
    }

    if (
        stage
        ==
        "TWOHAND_AIRCON_COLD_LAST40"
    ) {
        return STAGE_AIRCON_COLD_LAST40;
    }

    throw std::runtime_error(
        "Unknown stage: "
        +
        stage
    );
}


// ============================================================
// Float comparison
// ============================================================

bool almostEqual(
    float actual,
    float expected,
    double tolerance =
        FLOAT_TOLERANCE
) {
    if (
        !std::isfinite(actual)
        ||
        !std::isfinite(expected)
    ) {
        return false;
    }

    return (
        std::abs(
            static_cast<double>(
                actual
            )
            -
            static_cast<double>(
                expected
            )
        )
        <=
        tolerance
    );
}


// ============================================================
// Main
// ============================================================

}  // namespace


int main() {
    try {
        std::cout
            << std::fixed
            << std::setprecision(12);


        std::cout
            << "========================================\n";

        std::cout
            << "AIRCON / COLD LAST40 REGRESSION\n";

        std::cout
            << "========================================\n\n";


        // ====================================================
        // Paths
        // ====================================================

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data/";

        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "aircon_cold_last40/";


        // ====================================================
        // Runtime data
        // ====================================================

        sign_engine::RuntimeData runtime_data{};


        runtime_data.twohand_local =
            readBinary<float>(
                runtime_dir
                +
                "twohand_local.bin",

                REFERENCE_COUNT
                *
                FRAME_COUNT
                *
                LOCAL_DIM
            );


        runtime_data.twohand_class_ids =
            readBinary<std::int32_t>(
                runtime_dir
                +
                "twohand_class_ids.bin",

                REFERENCE_COUNT
            );


        // ====================================================
        // Fixture input
        // ====================================================

        const std::vector<float> input =
            readBinary<float>(
                fixture_dir
                +
                "input_local84_80x84.bin",

                FRAME_COUNT
                *
                LOCAL_DIM
            );


        // ====================================================
        // Expected float32 [8]
        //
        // 0 base_margin
        // 1 hot_score
        // 2 base_hs_score
        // 3 hot_delta
        // 4 hot_threshold
        // 5 last40_margin
        // 6 last40_top1_score
        // 7 last40_top2_score
        // ====================================================

        const std::vector<float> expected_float =
            readBinary<float>(
                fixture_dir
                +
                "expected_float8.bin",

                8
            );


        // ====================================================
        // Expected int32 [9]
        //
        // 0 base_id
        // 1 hot_evaluated
        // 2 hot_rescued
        // 3 ac_applied
        // 4 last40_top1_id
        // 5 last40_top2_id
        // 6 final_id
        // 7 stage_code
        // 8 base_changed_by_last40
        // ====================================================

        const std::vector<std::int32_t> expected_int =
            readBinary<std::int32_t>(
                fixture_dir
                +
                "expected_int9.bin",

                9
            );


        // ====================================================
        // C++ classify
        // ====================================================

        const sign_engine::TwoHandResult result =
            sign_engine::classifyTwoHand(
                input,
                runtime_data
            );


        // ====================================================
        // Extract actual values
        // ====================================================

        const std::int32_t hot_evaluated =
            result.hot_info.evaluated
            ?
            1
            :
            0;


        const std::int32_t hot_rescued =
            result.hot_info.rescued
            ?
            1
            :
            0;


        const std::int32_t ac_applied =
            result.ac_cold_info.applied
            ?
            1
            :
            0;


        if (
            result.ac_cold_info.ranking.size()
            !=
            2
        ) {
            throw std::runtime_error(
                "LAST40 ranking size must be 2"
            );
        }


        const std::int32_t last40_top1_id =
            result.ac_cold_info.ranking[
                0
            ].class_id;


        const std::int32_t last40_top2_id =
            result.ac_cold_info.ranking[
                1
            ].class_id;


        const float last40_top1_score =
            result.ac_cold_info.ranking[
                0
            ].score;


        const float last40_top2_score =
            result.ac_cold_info.ranking[
                1
            ].score;


        const std::int32_t stage_code =
            stageToCode(
                result.stage
            );


        const std::int32_t base_changed =
            (
                result.base_id
                !=
                result.final_id
            )
            ?
            1
            :
            0;


        // ====================================================
        // Print
        // ====================================================

        std::cout
            << "base_id           : "
            << result.base_id
            << " / expected "
            << expected_int[0]
            << '\n';


        std::cout
            << "base_margin       : "
            << result.base_margin
            << " / expected "
            << expected_float[0]
            << '\n';


        std::cout
            << '\n';


        std::cout
            << "HOT evaluated     : "
            << hot_evaluated
            << " / expected "
            << expected_int[1]
            << '\n';


        std::cout
            << "HOT score         : "
            << result.hot_info.hot_score
            << " / expected "
            << expected_float[1]
            << '\n';


        std::cout
            << "base HS score     : "
            << result.hot_info.base_hs_score
            << " / expected "
            << expected_float[2]
            << '\n';


        std::cout
            << "HOT delta         : "
            << result.hot_info.delta
            << " / expected "
            << expected_float[3]
            << '\n';


        std::cout
            << "HOT threshold     : "
            << result.hot_info.threshold
            << " / expected "
            << expected_float[4]
            << '\n';


        std::cout
            << "HOT rescued       : "
            << hot_rescued
            << " / expected "
            << expected_int[2]
            << '\n';


        std::cout
            << '\n';


        std::cout
            << "LAST40 applied    : "
            << ac_applied
            << " / expected "
            << expected_int[3]
            << '\n';


        std::cout
            << "LAST40 margin     : "
            << result.ac_cold_info.margin
            << " / expected "
            << expected_float[5]
            << '\n';


        std::cout
            << "LAST40 top1 id    : "
            << last40_top1_id
            << " / expected "
            << expected_int[4]
            << '\n';


        std::cout
            << "LAST40 top1 score : "
            << last40_top1_score
            << " / expected "
            << expected_float[6]
            << '\n';


        std::cout
            << "LAST40 top2 id    : "
            << last40_top2_id
            << " / expected "
            << expected_int[5]
            << '\n';


        std::cout
            << "LAST40 top2 score : "
            << last40_top2_score
            << " / expected "
            << expected_float[7]
            << '\n';


        std::cout
            << '\n';


        std::cout
            << "final_id          : "
            << result.final_id
            << " / expected "
            << expected_int[6]
            << '\n';


        std::cout
            << "stage             : "
            << result.stage
            << '\n';


        std::cout
            << "stage code        : "
            << stage_code
            << " / expected "
            << expected_int[7]
            << '\n';


        std::cout
            << "base changed      : "
            << base_changed
            << " / expected "
            << expected_int[8]
            << '\n';


        // ====================================================
        // Validate
        // ====================================================

        bool pass =
            true;


        if (
            result.base_id
            !=
            expected_int[0]
        ) {
            std::cerr
                << "base_id mismatch\n";

            pass =
                false;
        }


        if (
            hot_evaluated
            !=
            expected_int[1]
        ) {
            std::cerr
                << "hot_evaluated mismatch\n";

            pass =
                false;
        }


        if (
            hot_rescued
            !=
            expected_int[2]
        ) {
            std::cerr
                << "hot_rescued mismatch\n";

            pass =
                false;
        }


        if (
            ac_applied
            !=
            expected_int[3]
        ) {
            std::cerr
                << "LAST40 applied mismatch\n";

            pass =
                false;
        }


        if (
            last40_top1_id
            !=
            expected_int[4]
        ) {
            std::cerr
                << "LAST40 top1 id mismatch\n";

            pass =
                false;
        }


        if (
            last40_top2_id
            !=
            expected_int[5]
        ) {
            std::cerr
                << "LAST40 top2 id mismatch\n";

            pass =
                false;
        }


        if (
            result.final_id
            !=
            expected_int[6]
        ) {
            std::cerr
                << "final_id mismatch\n";

            pass =
                false;
        }


        if (
            stage_code
            !=
            expected_int[7]
        ) {
            std::cerr
                << "stage mismatch\n";

            pass =
                false;
        }


        if (
            base_changed
            !=
            expected_int[8]
        ) {
            std::cerr
                << "base changed mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                result.base_margin,
                expected_float[0]
            )
        ) {
            std::cerr
                << "base_margin mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                result.hot_info.hot_score,
                expected_float[1]
            )
        ) {
            std::cerr
                << "HOT score mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                result.hot_info.base_hs_score,
                expected_float[2]
            )
        ) {
            std::cerr
                << "base HS score mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                result.hot_info.delta,
                expected_float[3]
            )
        ) {
            std::cerr
                << "HOT delta mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                result.hot_info.threshold,
                expected_float[4]
            )
        ) {
            std::cerr
                << "HOT threshold mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                result.ac_cold_info.margin,
                expected_float[5]
            )
        ) {
            std::cerr
                << "LAST40 margin mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                last40_top1_score,
                expected_float[6]
            )
        ) {
            std::cerr
                << "LAST40 top1 score mismatch\n";

            pass =
                false;
        }


        if (
            !almostEqual(
                last40_top2_score,
                expected_float[7]
            )
        ) {
            std::cerr
                << "LAST40 top2 score mismatch\n";

            pass =
                false;
        }


        // ====================================================
        // Final
        // ====================================================

        std::cout
            << '\n';

        std::cout
            << "========================================\n";


        if (pass) {
            std::cout
                << "AIRCON / COLD LAST40 REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "AIRCON / COLD LAST40 REGRESSION FAIL\n";

        std::cout
            << "========================================\n";

        return 1;
    }
    catch (
        const std::exception& e
    ) {
        std::cerr
            << "AIRCON / COLD LAST40 REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}