#include "twohand_classifier.hpp"

#include <cmath>
#include <cstddef>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
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
        static_cast<std::size_t>(file_size) !=
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


double maxAbsoluteError(
    const std::vector<float>& actual,
    const std::vector<float>& expected
) {
    if (
        actual.size() !=
        expected.size()
    ) {
        throw std::runtime_error(
            "maxAbsoluteError: size mismatch"
        );
    }

    double max_error = 0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        if (
            !std::isfinite(actual[i]) ||
            !std::isfinite(expected[i])
        ) {
            throw std::runtime_error(
                "Non-finite value detected"
            );
        }

        const double error =
            std::abs(
                static_cast<double>(
                    actual[i]
                )
                -
                static_cast<double>(
                    expected[i]
                )
            );

        if (
            error >
            max_error
        ) {
            max_error = error;
        }
    }

    return max_error;
}


double meanAbsoluteError(
    const std::vector<float>& actual,
    const std::vector<float>& expected
) {
    if (
        actual.size() !=
        expected.size()
    ) {
        throw std::runtime_error(
            "meanAbsoluteError: size mismatch"
        );
    }

    if (actual.empty()) {
        return 0.0;
    }

    double sum = 0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        if (
            !std::isfinite(actual[i]) ||
            !std::isfinite(expected[i])
        ) {
            throw std::runtime_error(
                "Non-finite value detected"
            );
        }

        sum +=
            std::abs(
                static_cast<double>(
                    actual[i]
                )
                -
                static_cast<double>(
                    expected[i]
                )
            );
    }

    return (
        sum
        /
        static_cast<double>(
            actual.size()
        )
    );
}

}  // namespace


int main() {
    try {
        constexpr std::size_t FRAME_COUNT =
            80;

        constexpr std::size_t LOCAL_DIM =
            84;

        constexpr std::size_t HANDSHAPE_DIM =
            40;

        constexpr double FEATURE_TOLERANCE =
            1e-5;


        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "handshape40/";


        // ====================================================
        // 1. Python input Local84
        //
        // float32 [80, 84]
        // ====================================================

        const std::vector<float> local84 =
            readBinary<float>(
                fixture_dir +
                "input_local84_80x84.bin",

                FRAME_COUNT *
                LOCAL_DIM
            );


        // ====================================================
        // 2. C++ Handshape40
        // ====================================================

        const std::vector<float> actual =
            sign_engine::
            buildTwoHandHandshape40(
                local84
            );


        // ====================================================
        // 3. Python frozen 07g expected
        //
        // float32 [80, 40]
        // ====================================================

        const std::vector<float> expected =
            readBinary<float>(
                fixture_dir +
                "expected_handshape40_80x40.bin",

                FRAME_COUNT *
                HANDSHAPE_DIM
            );


        // ====================================================
        // 4. Shape validation
        // ====================================================

        const std::size_t expected_output_count =
            FRAME_COUNT *
            HANDSHAPE_DIM;

        if (
            actual.size() !=
            expected_output_count
        ) {
            throw std::runtime_error(
                "C++ Handshape40 output size mismatch"
            );
        }


        // ====================================================
        // 5. Numerical comparison
        // ====================================================

        const double max_error =
            maxAbsoluteError(
                actual,
                expected
            );

        const double mean_error =
            meanAbsoluteError(
                actual,
                expected
            );


        // ====================================================
        // Output
        // ====================================================

        std::cout
            << std::fixed
            << std::setprecision(12);


        std::cout
            << "========================================\n";

        std::cout
            << "HANDSHAPE40 REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "input count              : "
            << local84.size()
            << '\n';

        std::cout
            << "actual output count      : "
            << actual.size()
            << '\n';

        std::cout
            << "expected output count    : "
            << expected.size()
            << '\n';

        std::cout
            << "max abs error            : "
            << max_error
            << '\n';

        std::cout
            << "mean abs error           : "
            << mean_error
            << '\n';

        std::cout
            << "tolerance                : "
            << FEATURE_TOLERANCE
            << '\n';


        // ====================================================
        // Validation
        // ====================================================

        if (
            max_error >
            FEATURE_TOLERANCE
        ) {
            std::cerr
                << "\n"
                << "Handshape40 numerical mismatch\n";

            std::cout
                << "\n"
                << "HANDSHAPE40 REGRESSION FAIL\n";

            return 1;
        }


        // ====================================================
        // Final
        // ====================================================

        std::cout
            << "\n"
            << "HANDSHAPE40 REGRESSION PASS\n";

        return 0;
    }
    catch (
        const std::exception& e
    ) {
        std::cerr
            << "HANDSHAPE40 REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}