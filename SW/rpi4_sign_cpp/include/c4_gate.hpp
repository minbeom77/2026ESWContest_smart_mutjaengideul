#pragma once

#include "runtime_data.hpp"

#include <cstddef>
#include <vector>


namespace sign_engine {


// ============================================================
// C4 constants
// ============================================================

constexpr int C4_SIGN_LABEL = 1;
constexpr int C4_NOSIGN_LABEL = 0;


// ============================================================
// C4 inference result
// ============================================================

struct C4GateResult {
    int prediction = C4_NOSIGN_LABEL;

    double d_sign = 0.0;
    double d_nosign = 0.0;

    double margin_nosign_minus_sign = 0.0;
};


// ============================================================
// Local42
//
// input:
//   feature [80, 172]
//
// output:
//   active local hand [80, 42]
//
// Python:
//   energy_a = mean(abs(slot_a))
//   energy_b = mean(abs(slot_b))
//
//   if energy_b > energy_a:
//       return slot_b
//   return slot_a
// ============================================================

std::vector<double> getLocal42(
    const std::vector<float>& feature
);


// ============================================================
// Motion20
//
// input:
//   local42    [80, 42]
//   trajectory [80, 2]
//
// output:
//   [20]
// ============================================================

std::vector<double> buildMotion20(
    const std::vector<double>& local42,
    const std::vector<double>& trajectory
);


// ============================================================
// C4 feature
//
// C4_MOTION_LOCAL230
//
// Motion20 + LocalPhase210
//
// input:
//   feature [80, 172]
//
// output:
//   [230]
// ============================================================

std::vector<double> buildC4Feature(
    const std::vector<float>& feature
);


// ============================================================
// C4 standardization
//
// z = (feature - mean) / std
//
// c4_mean/std are float32 runtime data,
// calculation is performed in double.
// ============================================================

std::vector<double> standardizeC4Feature(
    const std::vector<double>& c4_feature,
    const RuntimeData& runtime
);


// ============================================================
// Frozen C4 nearest K mean Euclidean distance
//
// references:
//   flat float32 array
//
// reference_count × 230
// ============================================================

double c4NearestKMeanDistance(
    const std::vector<double>& vector,
    const std::vector<float>& references,
    std::size_t reference_count,
    std::size_t k
);


// ============================================================
// Frozen one-hand C4 SIGN / NO-SIGN gate
// ============================================================

C4GateResult classifyOnehandC4Gate(
    const std::vector<float>& feature,
    const RuntimeData& runtime
);


}  // namespace sign_engine