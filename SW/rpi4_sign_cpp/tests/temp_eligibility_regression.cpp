#include "sign_classifier.hpp"

#include <cstddef>
#include <iostream>


namespace {


// ============================================================
// Test helper
// ============================================================

bool runCase(
    const char* name,
    bool original_one_hand,
    bool c4_is_nosign,
    std::size_t total_frames,
    std::size_t both_count,
    bool expected
) {
    sign_engine::RecordingStats stats;

    stats.total_frames =
        total_frames;

    stats.both_count =
        both_count;

    stats.both_ratio =
        static_cast<double>(
            both_count
        )
        /
        static_cast<double>(
            total_frames
        );


    const bool actual =
        sign_engine::isTempOverlapRescueEligible(
            original_one_hand,
            c4_is_nosign,
            stats
        );


    std::cout
        << name
        << " : "
        << actual
        << " / expected "
        << expected
        << '\n';


    return actual == expected;
}


}  // namespace


int main() {
    std::cout
        << "========================================\n";

    std::cout
        << "TEMP ELIGIBILITY REGRESSION\n";

    std::cout
        << "========================================\n\n";


    bool pass =
        true;


    // ========================================================
    // Exact boundary:
    //
    // both_count = 15
    // total       = 75
    // ratio       = 0.20 exactly
    //
    // Must be eligible.
    // ========================================================

    pass =
        runCase(
            "exact boundary",
            true,
            true,
            75,
            15,
            true
        )
        &&
        pass;


    // ========================================================
    // Ratio below 0.20
    //
    // 15 / 76 = 0.197368...
    //
    // Frame count condition passes,
    // ratio condition fails.
    // ========================================================

    pass =
        runCase(
            "ratio below",
            true,
            true,
            76,
            15,
            false
        )
        &&
        pass;


    // ========================================================
    // both_count below 15
    //
    // Ratio is high enough:
    // 14 / 20 = 0.70
    //
    // But frame-count guard must fail.
    // ========================================================

    pass =
        runCase(
            "count below",
            true,
            true,
            20,
            14,
            false
        )
        &&
        pass;


    // ========================================================
    // Original routing is NOT one-hand
    // ========================================================

    pass =
        runCase(
            "not one-hand",
            false,
            true,
            20,
            15,
            false
        )
        &&
        pass;


    // ========================================================
    // C4 is SIGN, not NO-SIGN
    // ========================================================

    pass =
        runCase(
            "C4 SIGN",
            true,
            false,
            20,
            15,
            false
        )
        &&
        pass;


    // ========================================================
    // Clearly eligible
    // ========================================================

    pass =
        runCase(
            "normal eligible",
            true,
            true,
            40,
            20,
            true
        )
        &&
        pass;


    std::cout
        << '\n';

    std::cout
        << "threshold ratio : "
        << sign_engine::TEMP_OVERLAP_BOTH_RATIO_THRESHOLD
        << '\n';

    std::cout
        << "minimum BOTH    : "
        << sign_engine::TEMP_OVERLAP_MIN_BOTH_FRAMES
        << '\n';


    std::cout
        << '\n'
        << "========================================\n";


    if (
        pass
    ) {
        std::cout
            << "TEMP ELIGIBILITY REGRESSION PASS\n";

        std::cout
            << "========================================\n";

        return 0;
    }


    std::cout
        << "TEMP ELIGIBILITY REGRESSION FAIL\n";

    std::cout
        << "========================================\n";

    return 1;
}