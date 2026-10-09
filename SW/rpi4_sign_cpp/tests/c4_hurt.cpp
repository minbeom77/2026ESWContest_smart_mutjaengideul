#include "c4_gate.hpp"
#include "runtime_data.hpp"

#include <cmath>
#include <cstddef>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

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
        expected_count * sizeof(T);

    if (
        file_size < 0 ||
        static_cast<std::size_t>(file_size) != expected_bytes
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

    if (!file.read(
            reinterpret_cast<char*>(data.data()),
            static_cast<std::streamsize>(expected_bytes)
        )) {

        throw std::runtime_error(
            "Failed to read file: " + path
        );
    }

    return data;
}


double maxAbsoluteError(
    const std::vector<double>& actual,
    const std::vector<double>& expected
) {
    if (actual.size() != expected.size()) {
        throw std::runtime_error(
            "maxAbsoluteError: size mismatch"
        );
    }

    double max_error = 0.0;

    for (std::size_t i = 0; i < actual.size(); ++i) {

        const double error =
            std::abs(
                actual[i] -
                expected[i]
            );

        if (error > max_error) {
            max_error = error;
        }
    }

    return max_error;
}


double meanAbsoluteError(
    const std::vector<double>& actual,
    const std::vector<double>& expected
) {
    if (actual.size() != expected.size()) {
        throw std::runtime_error(
            "meanAbsoluteError: size mismatch"
        );
    }

    if (actual.empty()) {
        return 0.0;
    }

    double sum = 0.0;

    for (std::size_t i = 0; i < actual.size(); ++i) {

        sum += std::abs(
            actual[i] -
            expected[i]
        );
    }

    return sum /
           static_cast<double>(
               actual.size()
           );
}

}  // namespace


int main() {
    try {
        constexpr double FEATURE_TOLERANCE =
            1e-5;

        constexpr double DISTANCE_TOLERANCE =
            1e-5;

        constexpr double EXPECTED_D_SIGN =
            4.9974123804128725;

        constexpr double EXPECTED_D_NOSIGN =
            7.674819260304955;


        const std::string base =
            "SW/rpi4_sign_cpp/tests/fixtures/hurt/";

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";


        // ====================================================
        // Load runtime data
        // ====================================================

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        // ====================================================
        // Load Python regression fixture
        //
        // input_feature: [80, 172] float32
        // expected C4:   [230]     float64
        // expected Z:    [230]     float64
        // ====================================================

        const std::vector<float> input_feature =
            readBinary<float>(
                base +
                "input_feature_80x172.bin",

                sign_engine::TARGET_FRAMES *
                sign_engine::FULL_FEATURE_DIM
            );


        const std::vector<double> expected_c4 =
            readBinary<double>(
                base +
                "expected_c4_feature230_f64.bin",

                sign_engine::C4_FEATURE_DIM
            );


        const std::vector<double> expected_z =
            readBinary<double>(
                base +
                "expected_c4_z230_f64.bin",

                sign_engine::C4_FEATURE_DIM
            );


        // ====================================================
        // C++ C4 feature
        // ====================================================

        const std::vector<double> actual_c4 =
            sign_engine::buildC4Feature(
                input_feature
            );


        const double c4_max_error =
            maxAbsoluteError(
                actual_c4,
                expected_c4
            );


        const double c4_mean_error =
            meanAbsoluteError(
                actual_c4,
                expected_c4
            );


        // ====================================================
        // C++ standardized C4
        // ====================================================

        const std::vector<double> actual_z =
            sign_engine::standardizeC4Feature(
                actual_c4,
                runtime
            );


        const double z_max_error =
            maxAbsoluteError(
                actual_z,
                expected_z
            );


        const double z_mean_error =
            meanAbsoluteError(
                actual_z,
                expected_z
            );


        // ====================================================
        // C4 SIGN / NO-SIGN
        // ====================================================

        const sign_engine::C4GateResult result =
            sign_engine::classifyOnehandC4Gate(
                input_feature,
                runtime
            );


        // ====================================================
        // Output
        // ====================================================

        std::cout
            << std::fixed
            << std::setprecision(12);


        std::cout
            << "C4 feature max abs error : "
            << c4_max_error
            << '\n';


        std::cout
            << "C4 feature mean abs error: "
            << c4_mean_error
            << '\n';


        std::cout
            << "C4 z max abs error       : "
            << z_max_error
            << '\n';


        std::cout
            << "C4 z mean abs error      : "
            << z_mean_error
            << '\n';


        std::cout
            << "d_sign                    : "
            << result.d_sign
            << '\n';


        std::cout
            << "expected d_sign           : "
            << EXPECTED_D_SIGN
            << '\n';


        std::cout
            << "d_nosign                  : "
            << result.d_nosign
            << '\n';


        std::cout
            << "expected d_nosign         : "
            << EXPECTED_D_NOSIGN
            << '\n';


        std::cout
            << "prediction                : "
            << result.prediction
            << " ("
            << (
                result.prediction ==
                sign_engine::C4_SIGN_LABEL
                ?
                "SIGN"
                :
                "NO-SIGN"
            )
            << ")\n";


        // ====================================================
        // Regression checks
        // ====================================================

        bool pass = true;


        if (
            c4_max_error >
            FEATURE_TOLERANCE
        ) {
            std::cerr
                << "C4 feature mismatch\n";

            pass = false;
        }


        if (
            z_max_error >
            FEATURE_TOLERANCE
        ) {
            std::cerr
                << "C4 standardized feature mismatch\n";

            pass = false;
        }


        if (
            std::abs(
                result.d_sign -
                EXPECTED_D_SIGN
            )
            >
            DISTANCE_TOLERANCE
        ) {
            std::cerr
                << "d_sign mismatch\n";

            pass = false;
        }


        if (
            std::abs(
                result.d_nosign -
                EXPECTED_D_NOSIGN
            )
            >
            DISTANCE_TOLERANCE
        ) {
            std::cerr
                << "d_nosign mismatch\n";

            pass = false;
        }


        if (
            result.prediction !=
            sign_engine::C4_SIGN_LABEL
        ) {
            std::cerr
                << "C4 prediction mismatch\n";

            pass = false;
        }


        if (!pass) {

            std::cout
                << "\nC4 HURT REGRESSION FAIL\n";

            return 1;
        }


        std::cout
            << "\nC4 HURT REGRESSION PASS\n";

        return 0;
    }
    catch (const std::exception& e) {

        std::cerr
            << "C4 HURT REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}