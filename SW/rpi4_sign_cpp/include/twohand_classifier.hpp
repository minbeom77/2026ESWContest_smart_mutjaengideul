#pragma once

#include "knn.hpp"
#include "runtime_data.hpp"

#include <cstdint>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// Final 07g two-hand constants
// ============================================================

constexpr std::int32_t TWOHAND_AIRCON_ID = 0;
constexpr std::int32_t TWOHAND_LOCK_ID = 1;
constexpr std::int32_t TWOHAND_HOT_ID = 3;
constexpr std::int32_t TWOHAND_COLD_ID = 4;
constexpr std::int32_t TWOHAND_RESCUE_ID = 5;
constexpr std::int32_t TWOHAND_SMOKE_ID = 6;
constexpr std::int32_t TWOHAND_THANKS_ID = 9;
constexpr std::int32_t TWOHAND_TEMP_ID = 12;
constexpr std::int32_t TWOHAND_THIRSTY_ID = 14;


constexpr std::size_t TWOHAND_HANDSHAPE_ONE_DIM = 20;
constexpr std::size_t TWOHAND_HANDSHAPE_DIM = 40;

constexpr std::size_t TWOHAND_LAST40_START = 40;
constexpr std::size_t TWOHAND_LAST40_END = 80;

constexpr std::size_t TWOHAND_K = 3;

constexpr float TWOHAND_HOT_RESCUE_THRESHOLD =
    -0.10f;


// ============================================================
// HOT rescue information
// ============================================================

struct HotRescueInfo {
    bool evaluated = false;

    float hot_score = 0.0f;
    float base_hs_score = 0.0f;
    float delta = 0.0f;

    float threshold =
        TWOHAND_HOT_RESCUE_THRESHOLD;

    bool rescued = false;

    std::vector<ClassScore> ranking;
};


// ============================================================
// AIRCON / COLD LAST40 information
// ============================================================

struct AirconColdInfo {
    bool applied = false;

    float margin = 0.0f;

    std::vector<ClassScore> ranking;
};


// ============================================================
// Final two-hand result
// ============================================================

struct TwoHandResult {
    std::int32_t final_id = -1;
    std::int32_t base_id = -1;

    std::string stage;

    float base_margin = 0.0f;

    std::vector<ClassScore> base_ranking;

    HotRescueInfo hot_info;
    AirconColdInfo ac_cold_info;
};


// ============================================================
// Local84 -> two-hand Handshape40
//
// Input:
//     float32 [80,84]
//
// Output:
//     float32 [80,40]
//
// 40D:
//
//     SLOT A descriptor 20
//     SLOT B descriptor 20
// ============================================================

std::vector<float> buildTwoHandHandshape40(
    const std::vector<float>& local84
);


// ============================================================
// Final 07g two-hand classifier
//
// Stage 1:
//     Full80 Local84 K3
//
// Stage 2:
//     HOT handshape rescue
//
// Stage 3:
//     AIRCON / COLD LAST40
// ============================================================

TwoHandResult classifyTwoHand(
    const std::vector<float>& local84,
    const RuntimeData& runtime_data
);


}  // namespace sign_engine