#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// Runtime constants
// ============================================================

constexpr std::size_t TARGET_FRAMES = 80;
constexpr std::size_t FULL_FEATURE_DIM = 172;
constexpr std::size_t LOCAL_FEATURE_DIM = 84;
constexpr std::size_t SLOT_DIM = 42;

constexpr std::size_t C4_FEATURE_DIM = 230;

constexpr int KNN_K = 3;
constexpr int C4_K = 3;


// ============================================================
// Runtime reference counts
// ============================================================

constexpr std::size_t TWOHAND_REFERENCE_COUNT = 60;
constexpr std::size_t ONEHAND_REFERENCE_COUNT = 42;

constexpr std::size_t C4_SIGN_REFERENCE_COUNT = 288;
constexpr std::size_t C4_NOSIGN_REFERENCE_COUNT = 308;


// ============================================================
// Runtime data container
// ============================================================

struct RuntimeData {

    // --------------------------------------------------------
    // Two-hand template data
    //
    // shape:
    //   [60, 80, 84]
    //
    // contiguous layout:
    //   reference -> frame -> feature
    // --------------------------------------------------------

    std::vector<float> twohand_local;

    // shape:
    //   [60]
    std::vector<std::int32_t> twohand_class_ids;


    // --------------------------------------------------------
    // One-hand template data
    //
    // shape:
    //   [42, 80, 84]
    // --------------------------------------------------------

    std::vector<float> onehand_local;

    // shape:
    //   [42]
    std::vector<std::int32_t> onehand_class_ids;


    // --------------------------------------------------------
    // C4 SIGN / NO-SIGN data
    // --------------------------------------------------------

    // shape:
    //   [230]
    std::vector<float> c4_mean;

    // shape:
    //   [230]
    std::vector<float> c4_std;

    // shape:
    //   [288, 230]
    std::vector<float> c4_sign;

    // shape:
    //   [308, 230]
    std::vector<float> c4_nosign;
};


// ============================================================
// Binary loader
// ============================================================

RuntimeData loadRuntimeData(
    const std::string& runtime_data_dir
);


// ============================================================
// Validation
// ============================================================

void validateRuntimeData(
    const RuntimeData& data
);


}  // namespace sign_engine