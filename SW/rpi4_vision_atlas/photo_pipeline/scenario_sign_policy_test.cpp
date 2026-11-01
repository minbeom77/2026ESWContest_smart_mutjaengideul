#include "scenario_sign_policy.hpp"

#include <array>
#include <iostream>
#include <limits>

int main() {
    // The deployed classifier IDs are sparse; they must not be renumbered 0..4.
    const std::array<bool, 16> expected{{
        true, false, false, false, false, true, false, true,
        true, false, false, false, false, false, false, true,
    }};
    for (int id = 0; id < static_cast<int>(expected.size()); ++id) {
        if (vision_runtime::isScenarioSign(id) != expected[id]) {
            std::cerr << "Unexpected publish policy for classifier ID " << id << '\n';
            return 1;
        }
    }
    for (const int id : {-1, 16, 100, std::numeric_limits<int>::min(),
                         std::numeric_limits<int>::max()}) {
        if (vision_runtime::isScenarioSign(id)) {
            std::cerr << "Unknown classifier ID was allowed: " << id << '\n';
            return 1;
        }
    }
    std::cout << "PASS: only the five scenario sign IDs may be published\n";
}

