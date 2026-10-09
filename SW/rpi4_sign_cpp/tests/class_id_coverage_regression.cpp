#include "runtime_data.hpp"

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

std::set<std::int32_t> toSet(
    const std::vector<std::int32_t>& values
) {
    return std::set<std::int32_t>(
        values.begin(),
        values.end()
    );
}


void printSet(
    const std::set<std::int32_t>& values
) {
    bool first = true;

    for (const std::int32_t value : values) {
        if (!first) {
            std::cout << ", ";
        }

        std::cout << value;
        first = false;
    }
}


bool sameSet(
    const std::set<std::int32_t>& actual,
    const std::set<std::int32_t>& expected
) {
    return actual == expected;
}

}  // namespace


int main() {
    try {
        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";


        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        const std::set<std::int32_t>
            expected_onehand = {
                2,
                7,
                8,
                10,
                11,
                13,
            };


        const std::set<std::int32_t>
            expected_twohand = {
                0,
                1,
                3,
                4,
                5,
                6,
                9,
                12,
                14,
            };


        const std::set<std::int32_t>
            expected_all = {
                0,
                1,
                2,
                3,
                4,
                5,
                6,
                7,
                8,
                9,
                10,
                11,
                12,
                13,
                14,
            };


        const std::set<std::int32_t>
            actual_onehand =
                toSet(
                    runtime.onehand_class_ids
                );


        const std::set<std::int32_t>
            actual_twohand =
                toSet(
                    runtime.twohand_class_ids
                );


        std::set<std::int32_t>
            actual_all =
                actual_onehand;


        actual_all.insert(
            actual_twohand.begin(),
            actual_twohand.end()
        );


        std::set<std::int32_t>
            overlap;


        std::set_intersection(
            actual_onehand.begin(),
            actual_onehand.end(),
            actual_twohand.begin(),
            actual_twohand.end(),
            std::inserter(
                overlap,
                overlap.begin()
            )
        );


        const bool onehand_count_pass =
            runtime.onehand_class_ids.size()
            ==
            sign_engine::ONEHAND_REFERENCE_COUNT;


        const bool twohand_count_pass =
            runtime.twohand_class_ids.size()
            ==
            sign_engine::TWOHAND_REFERENCE_COUNT;


        const bool onehand_set_pass =
            sameSet(
                actual_onehand,
                expected_onehand
            );


        const bool twohand_set_pass =
            sameSet(
                actual_twohand,
                expected_twohand
            );


        const bool overlap_pass =
            overlap.empty();


        const bool all_classes_pass =
            sameSet(
                actual_all,
                expected_all
            );


        const bool all_pass =
            onehand_count_pass
            &&
            twohand_count_pass
            &&
            onehand_set_pass
            &&
            twohand_set_pass
            &&
            overlap_pass
            &&
            all_classes_pass;


        std::cout
            << "========================================\n";

        std::cout
            << "15-CLASS ID COVERAGE REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "ONE-HAND reference count : "
            << runtime.onehand_class_ids.size()
            << " / expected "
            << sign_engine::ONEHAND_REFERENCE_COUNT
            << " -> "
            << (
                onehand_count_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "ONE-HAND class IDs       : ";

        printSet(
            actual_onehand
        );

        std::cout
            << "\nexpected                 : ";

        printSet(
            expected_onehand
        );

        std::cout
            << "\nresult                   : "
            << (
                onehand_set_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << "\n\n";


        std::cout
            << "TWO-HAND reference count : "
            << runtime.twohand_class_ids.size()
            << " / expected "
            << sign_engine::TWOHAND_REFERENCE_COUNT
            << " -> "
            << (
                twohand_count_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "TWO-HAND class IDs       : ";

        printSet(
            actual_twohand
        );

        std::cout
            << "\nexpected                 : ";

        printSet(
            expected_twohand
        );

        std::cout
            << "\nresult                   : "
            << (
                twohand_set_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << "\n\n";


        std::cout
            << "ONE/TWO overlap          : ";

        if (overlap.empty()) {
            std::cout
                << "NONE";
        }
        else {
            printSet(
                overlap
            );
        }

        std::cout
            << " -> "
            << (
                overlap_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "Combined IDs             : ";

        printSet(
            actual_all
        );

        std::cout
            << '\n';


        std::cout
            << "All classes 0~14         : "
            << (
                all_classes_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "\n========================================\n";


        if (all_pass) {
            std::cout
                << "15-CLASS ID COVERAGE REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "15-CLASS ID COVERAGE REGRESSION FAIL\n";

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