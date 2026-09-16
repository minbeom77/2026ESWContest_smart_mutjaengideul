#include "knn.hpp"
#include "runtime_data.hpp"

#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

std::vector<float> readFloat32Binary(
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
        expected_count * sizeof(float);

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

    std::vector<float> data(
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


struct ExpectedClassScore {
    std::int32_t class_id;
    float score;
};


bool nearlyEqual(
    float a,
    float b,
    float tolerance
) {
    return std::fabs(a - b) <= tolerance;
}

}  // namespace


int main() {
    try {
        constexpr float TOLERANCE = 1e-5f;

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";

        const std::string fixture_path =
            "SW/rpi4_sign_cpp/tests/fixtures/hurt/"
            "expected_local84.bin";


        // ====================================================
        // Runtime data
        // ====================================================

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        // ====================================================
        // Python fixture:
        // expected_local84 = [80, 84]
        // ====================================================

        const std::vector<float> query =
            readFloat32Binary(
                fixture_path,
                sign_engine::TARGET_FRAMES *
                sign_engine::LOCAL_FEATURE_DIM
            );


        // ====================================================
        // Final one-hand 6 classes
        //
        // 2  = 꺼지다
        // 7  = 아프다
        // 8  = 괜찮다
        // 10 = 점등
        // 11 = 소등
        // 13 = 배고프다
        // ====================================================

        const std::vector<std::int32_t> candidate_ids = {
            2,
            7,
            8,
            10,
            11,
            13
        };


        const std::vector<sign_engine::ClassScore> ranking =
            sign_engine::rankClasses(
                query.data(),
                runtime.onehand_local,
                runtime.onehand_class_ids,
                sign_engine::ONEHAND_REFERENCE_COUNT,
                sign_engine::TARGET_FRAMES *
                sign_engine::LOCAL_FEATURE_DIM,
                candidate_ids,
                sign_engine::KNN_K
            );


        // ====================================================
        // Python expected ranking
        // ====================================================

        const std::vector<ExpectedClassScore> expected = {
            {7,  0.12435222417116165f},
            {2,  0.13394735753536224f},
            {8,  0.3671034276485443f},
            {13, 0.5376037955284119f},
            {10, 0.6071288585662842f},
            {11, 0.6781153678894043f}
        };


        if (ranking.size() != expected.size()) {
            throw std::runtime_error(
                "Ranking size mismatch"
            );
        }


        std::cout
            << std::fixed
            << std::setprecision(9);


        bool pass = true;


        std::cout << "=== C++ KNN ranking ===\n";


        for (std::size_t i = 0; i < ranking.size(); ++i) {

            const auto& actual =
                ranking[i];

            const auto& target =
                expected[i];


            std::cout
                << (i + 1)
                << ". class="
                << actual.class_id
                << " score="
                << actual.score
                << '\n';


            std::cout
                << "   nearest indices: ";

            for (
                std::size_t j = 0;
                j < actual.nearest_indices.size();
                ++j
            ) {
                std::cout
                    << actual.nearest_indices[j];

                if (
                    j + 1 <
                    actual.nearest_indices.size()
                ) {
                    std::cout << ", ";
                }
            }

            std::cout << '\n';


            std::cout
                << "   nearest distances: ";

            for (
                std::size_t j = 0;
                j < actual.nearest_distances.size();
                ++j
            ) {
                std::cout
                    << actual.nearest_distances[j];

                if (
                    j + 1 <
                    actual.nearest_distances.size()
                ) {
                    std::cout << ", ";
                }
            }

            std::cout << '\n';


            if (
                actual.class_id !=
                target.class_id
            ) {
                std::cerr
                    << "Class mismatch at rank "
                    << i
                    << '\n';

                pass = false;
            }


            if (!nearlyEqual(
                    actual.score,
                    target.score,
                    TOLERANCE
                )) {

                std::cerr
                    << "Score mismatch for class "
                    << actual.class_id
                    << ": expected "
                    << target.score
                    << ", got "
                    << actual.score
                    << '\n';

                pass = false;
            }
        }


        // ====================================================
        // Final prediction
        // ====================================================

        if (
            ranking.empty() ||
            ranking[0].class_id != 7
        ) {
            std::cerr
                << "Final prediction mismatch\n";

            pass = false;
        }


        if (!pass) {
            std::cout
                << "\nKNN HURT REGRESSION FAIL\n";

            return 1;
        }


        std::cout
            << "\nKNN HURT REGRESSION PASS\n";

        return 0;
    }
    catch (const std::exception& e) {

        std::cerr
            << "KNN HURT REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}