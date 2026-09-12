#include "c4_gate.hpp"
#include "onehand_classifier.hpp"
#include "runtime_data.hpp"

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
                static_cast<double>(actual[i]) -
                static_cast<double>(expected[i])
            );

        if (error > max_error) {
            max_error = error;
        }
    }

    return max_error;
}

}  // namespace


int main() {
    try {
        constexpr double FEATURE_TOLERANCE =
            1e-5;

        constexpr double SCORE_TOLERANCE =
            1e-5;

        // ====================================================
        // Python verified expectations
        //
        // Full80 Base KNN:
        //   class 7 = 아프다
        //
        // Top2 = {2, 7}
        // -> MID40 applied
        //
        // MID40:
        //   class 2 = 0.06407713890075684
        //   class 7 = 0.07063578814268112
        //
        // Final:
        //   class 2 = 꺼지다
        // ====================================================

        constexpr std::int32_t EXPECTED_BASE_CLASS_ID =
            7;

        constexpr std::int32_t EXPECTED_FINAL_CLASS_ID =
            2;

        constexpr double EXPECTED_MID40_OFF_SCORE =
            0.06407713890075684;

        constexpr double EXPECTED_MID40_HURT_SCORE =
            0.07063578814268112;


        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";

        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/hurt/";


        // ====================================================
        // 1. Runtime data
        // ====================================================

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        // ====================================================
        // 2. Python input fixture
        //
        // [80, 172]
        // ====================================================

        const std::vector<float> input_feature =
            readBinary<float>(
                fixture_dir +
                "input_feature_80x172.bin",

                sign_engine::TARGET_FRAMES *
                sign_engine::FULL_FEATURE_DIM
            );


        // ====================================================
        // 3. Python expected Local84
        //
        // [80, 84]
        // ====================================================

        const std::vector<float> expected_local84 =
            readBinary<float>(
                fixture_dir +
                "expected_local84.bin",

                sign_engine::TARGET_FRAMES *
                sign_engine::LOCAL_FEATURE_DIM
            );


        // ====================================================
        // 4. C++ 172D -> Local84
        // ====================================================

        const std::vector<float> actual_local84 =
            sign_engine::extractLocal84(
                input_feature
            );


        const double local84_error =
            maxAbsoluteError(
                actual_local84,
                expected_local84
            );


        // ====================================================
        // 5. C4 SIGN / NO-SIGN gate
        // ====================================================

        const sign_engine::C4GateResult c4_result =
            sign_engine::classifyOnehandC4Gate(
                input_feature,
                runtime
            );


        // ====================================================
        // 6. One-hand classifier
        //
        // Full80 K3
        // +
        // OFF/HURT MID40 if Top2 == {2, 7}
        // ====================================================

        const sign_engine::OneHandResult result =
            sign_engine::classifyOneHand(
                actual_local84,
                runtime
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
            << "HURT FIXTURE END-TO-END REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "Local84 max abs error : "
            << local84_error
            << '\n';


        std::cout
            << "C4 prediction         : "
            << (
                c4_result.prediction ==
                sign_engine::C4_SIGN_LABEL
                ?
                "SIGN"
                :
                "NO-SIGN"
            )
            << '\n';


        std::cout
            << "C4 d_sign             : "
            << c4_result.d_sign
            << '\n';


        std::cout
            << "C4 d_nosign           : "
            << c4_result.d_nosign
            << '\n';


        std::cout
            << "Base class            : "
            << result.base_id
            << '\n';


        std::cout
            << "Expected base class   : "
            << EXPECTED_BASE_CLASS_ID
            << '\n';


        std::cout
            << "Base margin           : "
            << result.base_margin
            << '\n';


        std::cout
            << "Stage                 : "
            << result.stage
            << '\n';


        std::cout
            << "MID40 applied         : "
            << (
                result.off_hurt_info.applied
                ?
                "YES"
                :
                "NO"
            )
            << '\n';


        if (
            result.off_hurt_info.applied
        ) {
            std::cout
                << "MID40 ranking          : ";

            for (
                const auto& item :
                result.off_hurt_info.ranking
            ) {
                std::cout
                    << item.class_id
                    << "("
                    << item.score
                    << ") ";
            }

            std::cout << '\n';
        }


        std::cout
            << "Final class           : "
            << result.final_id
            << '\n';


        std::cout
            << "Expected final class  : "
            << EXPECTED_FINAL_CLASS_ID
            << '\n';


        // ====================================================
        // Regression validation
        // ====================================================

        bool pass = true;


        // ----------------------------------------------------
        // Local84
        // ----------------------------------------------------

        if (
            local84_error >
            FEATURE_TOLERANCE
        ) {
            std::cerr
                << "Local84 mismatch\n";

            pass = false;
        }


        // ----------------------------------------------------
        // C4
        // ----------------------------------------------------

        if (
            c4_result.prediction !=
            sign_engine::C4_SIGN_LABEL
        ) {
            std::cerr
                << "C4 prediction mismatch\n";

            pass = false;
        }


        // ----------------------------------------------------
        // Base Full80
        //
        // expected = class 7
        // ----------------------------------------------------

        if (
            result.base_id !=
            EXPECTED_BASE_CLASS_ID
        ) {
            std::cerr
                << "Base prediction mismatch\n";

            pass = false;
        }


        // ----------------------------------------------------
        // MID40 must be applied
        // ----------------------------------------------------

        if (
            !result.off_hurt_info.applied
        ) {
            std::cerr
                << "OFF/HURT MID40 was not applied\n";

            pass = false;
        }


        // ----------------------------------------------------
        // Stage
        // ----------------------------------------------------

        if (
            result.stage !=
            "ONEHAND_OFF_HURT_MID40_K3"
        ) {
            std::cerr
                << "Stage mismatch\n";

            pass = false;
        }


        // ----------------------------------------------------
        // MID40 ranking
        //
        // Expected:
        //
        // 1st = class 2
        // 2nd = class 7
        // ----------------------------------------------------

        if (
            result.off_hurt_info.applied
        ) {
            const auto& mid40_ranking =
                result.off_hurt_info.ranking;


            if (
                mid40_ranking.size() != 2
            ) {
                std::cerr
                    << "MID40 ranking size mismatch\n";

                pass = false;
            }
            else {
                if (
                    mid40_ranking[0].class_id !=
                    sign_engine::OFF_ID
                ) {
                    std::cerr
                        << "MID40 rank1 class mismatch\n";

                    pass = false;
                }


                if (
                    mid40_ranking[1].class_id !=
                    sign_engine::HURT_ID
                ) {
                    std::cerr
                        << "MID40 rank2 class mismatch\n";

                    pass = false;
                }


                if (
                    std::abs(
                        static_cast<double>(
                            mid40_ranking[0].score
                        )
                        -
                        EXPECTED_MID40_OFF_SCORE
                    )
                    >
                    SCORE_TOLERANCE
                ) {
                    std::cerr
                        << "MID40 OFF score mismatch\n";

                    pass = false;
                }


                if (
                    std::abs(
                        static_cast<double>(
                            mid40_ranking[1].score
                        )
                        -
                        EXPECTED_MID40_HURT_SCORE
                    )
                    >
                    SCORE_TOLERANCE
                ) {
                    std::cerr
                        << "MID40 HURT score mismatch\n";

                    pass = false;
                }
            }
        }


        // ----------------------------------------------------
        // Final prediction
        //
        // Python 07g current logic:
        // final = class 2
        // ----------------------------------------------------

        if (
            result.final_id !=
            EXPECTED_FINAL_CLASS_ID
        ) {
            std::cerr
                << "Final prediction mismatch\n";

            pass = false;
        }


        // ====================================================
        // Final result
        // ====================================================

        if (!pass) {

            std::cout
                << "\nHURT FIXTURE END-TO-END REGRESSION FAIL\n";

            return 1;
        }


        std::cout
            << "\nHURT FIXTURE END-TO-END REGRESSION PASS\n";

        return 0;
    }
    catch (const std::exception& e) {

        std::cerr
            << "HURT FIXTURE END-TO-END REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}