#include "temporal_resample.hpp"

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
            static_cast<std::streamsize>(
                expected_bytes
            )
        )) {

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
    if (actual.size() != expected.size()) {
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
        const double error =
            std::abs(
                static_cast<double>(actual[i])
                -
                static_cast<double>(expected[i])
            );

        if (error > max_error) {
            max_error = error;
        }
    }

    return max_error;
}


double meanAbsoluteError(
    const std::vector<float>& actual,
    const std::vector<float>& expected
) {
    if (actual.size() != expected.size()) {
        throw std::runtime_error(
            "meanAbsoluteError: size mismatch"
        );
    }

    if (actual.empty()) {
        return 0.0;
    }

    double total = 0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        total += std::abs(
            static_cast<double>(actual[i])
            -
            static_cast<double>(expected[i])
        );
    }

    return (
        total /
        static_cast<double>(actual.size())
    );
}

}  // namespace


int main() {
    try {
        constexpr std::size_t ORIGINAL_FRAMES = 37;
        constexpr std::size_t TARGET_FRAMES = 80;
        constexpr std::size_t FEATURE_DIM = 172;

        constexpr double TOLERANCE = 1e-6;


        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "temporal_resample/";


        // ====================================================
        // 1. Python input
        //
        // float32 [37,172]
        // ====================================================

        const std::vector<float> input =
            readBinary<float>(
                fixture_dir +
                "input_37x172.bin",

                ORIGINAL_FRAMES *
                FEATURE_DIM
            );


        // ====================================================
        // 2. Python expected
        //
        // float32 [80,172]
        // ====================================================

        const std::vector<float> expected =
            readBinary<float>(
                fixture_dir +
                "expected_80x172.bin",

                TARGET_FRAMES *
                FEATURE_DIM
            );


        // ====================================================
        // 3. C++ temporal resample
        // ====================================================

        const std::vector<float> actual =
            sign_engine::temporalResample(
                input,
                ORIGINAL_FRAMES,
                FEATURE_DIM,
                TARGET_FRAMES
            );


        // ====================================================
        // 4. Numerical comparison
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
            << "TEMPORAL RESAMPLE REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "input frames         : "
            << ORIGINAL_FRAMES
            << '\n';


        std::cout
            << "target frames        : "
            << TARGET_FRAMES
            << '\n';


        std::cout
            << "feature dim          : "
            << FEATURE_DIM
            << '\n';


        std::cout
            << "output size          : "
            << actual.size()
            << '\n';


        std::cout
            << "expected output size : "
            << expected.size()
            << '\n';


        std::cout
            << "max abs error        : "
            << max_error
            << '\n';


        std::cout
            << "mean abs error       : "
            << mean_error
            << '\n';


        // ====================================================
        // Validation
        // ====================================================

        bool pass = true;


        if (
            actual.size()
            !=
            expected.size()
        ) {
            std::cerr
                << "Output size mismatch\n";

            pass = false;
        }


        if (
            max_error >
            TOLERANCE
        ) {
            std::cerr
                << "Temporal resample numerical mismatch\n";

            pass = false;
        }


        // ====================================================
        // Final
        // ====================================================

        if (!pass) {

            std::cout
                << "\nTEMPORAL RESAMPLE REGRESSION FAIL\n";

            return 1;
        }


        std::cout
            << "\nTEMPORAL RESAMPLE REGRESSION PASS\n";

        return 0;
    }
    catch (const std::exception& e) {

        std::cerr
            << "TEMPORAL RESAMPLE REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}