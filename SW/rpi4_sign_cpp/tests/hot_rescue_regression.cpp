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
//
// Must match generate_hot_rescue_fixture.py
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
            "Failed to open file: " + path
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
            "Invalid file size: " + path
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
            "Failed to read file: " + path
        );
    }

    return data;
}


// ============================================================
// C++ stage -> fixture code
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
        "Unknown C++ stage: "
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
// Regression case
// ============================================================

bool runCase(
    const std::string& name,
    const std::string& fixture_prefix,
    const sign_engine::RuntimeData& runtime_data
) {
    const std::string fixture_dir =
        "SW/rpi4_sign_cpp/tests/fixtures/"
        "hot_rescue/";


    // ========================================================
    // Python fixture
    // ========================================================

    const std::vector<float> input =
        readBinary<float>(
            fixture_dir
            +
            fixture_prefix
            +
            "_input_local84_80x84.bin",

            FRAME_COUNT
            *
            LOCAL_DIM
        );


    // --------------------------------------------------------
    // Expected float32 [5]
    //
    // 0 base_margin
    // 1 hot_score
    // 2 base_hs_score
    // 3 delta
    // 4 threshold
    // --------------------------------------------------------

    const std::vector<float> expected_float =
        readBinary<float>(
            fixture_dir
            +
            fixture_prefix
            +
            "_expected_float5.bin",

            5
        );


    // --------------------------------------------------------
    // Expected int32 [5]
    //
    // 0 base_id
    // 1 hot_evaluated
    // 2 rescued
    // 3 final_id
    // 4 stage_code
    // --------------------------------------------------------

    const std::vector<std::int32_t> expected_int =
        readBinary<std::int32_t>(
            fixture_dir
            +
            fixture_prefix
            +
            "_expected_int5.bin",

            5
        );


    // ========================================================
    // C++ classification
    // ========================================================

    const sign_engine::TwoHandResult result =
        sign_engine::classifyTwoHand(
            input,
            runtime_data
        );


    const std::int32_t actual_base_id =
        result.base_id;

    const std::int32_t actual_hot_evaluated =
        result.hot_info.evaluated
        ?
        1
        :
        0;

    const std::int32_t actual_rescued =
        result.hot_info.rescued
        ?
        1
        :
        0;

    const std::int32_t actual_final_id =
        result.final_id;

    const std::int32_t actual_stage_code =
        stageToCode(
            result.stage
        );


    // ========================================================
    // Print
    // ========================================================

    std::cout
        << "----------------------------------------\n";

    std::cout
        << name
        << '\n';

    std::cout
        << "----------------------------------------\n";


    std::cout
        << "base_id       : "
        << actual_base_id
        << " / expected "
        << expected_int[0]
        << '\n';


    std::cout
        << "base_margin   : "
        << result.base_margin
        << " / expected "
        << expected_float[0]
        << '\n';


    std::cout
        << "hot evaluated : "
        << actual_hot_evaluated
        << " / expected "
        << expected_int[1]
        << '\n';


    std::cout
        << "hot_score     : "
        << result.hot_info.hot_score
        << " / expected "
        << expected_float[1]
        << '\n';


    std::cout
        << "base_hs_score : "
        << result.hot_info.base_hs_score
        << " / expected "
        << expected_float[2]
        << '\n';


    std::cout
        << "delta         : "
        << result.hot_info.delta
        << " / expected "
        << expected_float[3]
        << '\n';


    std::cout
        << "threshold     : "
        << result.hot_info.threshold
        << " / expected "
        << expected_float[4]
        << '\n';


    std::cout
        << "rescued       : "
        << actual_rescued
        << " / expected "
        << expected_int[2]
        << '\n';


    std::cout
        << "final_id      : "
        << actual_final_id
        << " / expected "
        << expected_int[3]
        << '\n';


    std::cout
        << "stage         : "
        << result.stage
        << '\n';

    std::cout
        << "stage code    : "
        << actual_stage_code
        << " / expected "
        << expected_int[4]
        << '\n';


    // ========================================================
    // Validation
    // ========================================================

    bool pass =
        true;


    if (
        actual_base_id
        !=
        expected_int[0]
    ) {
        std::cerr
            << name
            << ": base_id mismatch\n";

        pass =
            false;
    }


    if (
        actual_hot_evaluated
        !=
        expected_int[1]
    ) {
        std::cerr
            << name
            << ": hot evaluated mismatch\n";

        pass =
            false;
    }


    if (
        actual_rescued
        !=
        expected_int[2]
    ) {
        std::cerr
            << name
            << ": rescued mismatch\n";

        pass =
            false;
    }


    if (
        actual_final_id
        !=
        expected_int[3]
    ) {
        std::cerr
            << name
            << ": final_id mismatch\n";

        pass =
            false;
    }


    if (
        actual_stage_code
        !=
        expected_int[4]
    ) {
        std::cerr
            << name
            << ": stage mismatch\n";

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
            << name
            << ": base_margin mismatch\n";

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
            << name
            << ": hot_score mismatch\n";

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
            << name
            << ": base_hs_score mismatch\n";

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
            << name
            << ": delta mismatch\n";

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
            << name
            << ": threshold mismatch\n";

        pass =
            false;
    }


    std::cout
        << '\n';

    if (pass) {
        std::cout
            << name
            << " PASS\n";
    }
    else {
        std::cout
            << name
            << " FAIL\n";
    }

    std::cout
        << '\n';


    return pass;
}

}  // namespace


int main() {
    try {
        std::cout
            << std::fixed
            << std::setprecision(12);


        std::cout
            << "========================================\n";

        std::cout
            << "HOT RESCUE REGRESSION\n";

        std::cout
            << "========================================\n\n";


        // ====================================================
        // Runtime data
        //
        // classifyTwoHand() uses only:
        //   twohand_local
        //   twohand_class_ids
        // ====================================================

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data/";


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


        std::cout
            << "runtime twohand local   : "
            << runtime_data.twohand_local.size()
            << '\n';

        std::cout
            << "runtime class ids       : "
            << runtime_data.twohand_class_ids.size()
            << "\n\n";


        // ====================================================
        // Positive
        //
        // TEST-ONLY interpolation.
        //
        // Expected:
        //   base=4
        //   delta <= -0.10
        //   rescue=True
        //   final=3
        // ====================================================

        const bool positive_pass =
            runCase(
                "POSITIVE / TEST-ONLY",
                "positive",
                runtime_data
            );


        // ====================================================
        // Negative
        //
        // Real stored 06v sample.
        //
        // Expected:
        //   base=0
        //   HOT evaluated
        //   delta > -0.10
        //   rescue=False
        //   final=0
        // ====================================================

        const bool negative_pass =
            runCase(
                "NEGATIVE / REAL 06v",
                "negative",
                runtime_data
            );


        // ====================================================
        // Final
        // ====================================================

        std::cout
            << "========================================\n";


        if (
            positive_pass
            &&
            negative_pass
        ) {
            std::cout
                << "HOT RESCUE REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "HOT RESCUE REGRESSION FAIL\n";

        std::cout
            << "========================================\n";

        return 1;
    }
    catch (
        const std::exception& e
    ) {
        std::cerr
            << "HOT RESCUE REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}