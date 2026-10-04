#pragma once

#include "knn.hpp"
#include "runtime_data.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>


namespace sign_engine {


// ============================================================
// One-hand constants
// ============================================================

// Final one-hand 6 classes
//
// 2  = 꺼지다
// 7  = 아프다
// 8  = 괜찮다
// 10 = 점등
// 11 = 소등
// 13 = 배고프다

constexpr std::int32_t OFF_ID = 2;
constexpr std::int32_t HURT_ID = 7;

constexpr std::size_t OFF_HURT_MID_START = 20;
constexpr std::size_t OFF_HURT_MID_END = 60;
constexpr std::size_t OFF_HURT_MID_FRAMES =
    OFF_HURT_MID_END -
    OFF_HURT_MID_START;


// ============================================================
// OFF / HURT MID40 information
// ============================================================

struct OffHurtInfo {
    bool applied = false;

    std::vector<ClassScore> ranking;

    float margin = 0.0f;

    std::size_t start =
        OFF_HURT_MID_START;

    std::size_t end =
        OFF_HURT_MID_END;
};


// ============================================================
// One-hand classification result
//
// Python classify_one_hand()의 반환 구조 대응
// ============================================================

struct OneHandResult {
    std::int32_t final_id = -1;

    std::string stage;

    std::vector<ClassScore> ranking;

    float margin = 0.0f;

    std::int32_t base_id = -1;

    std::vector<ClassScore> base_ranking;

    float base_margin = 0.0f;

    OffHurtInfo off_hurt_info;
};


// ============================================================
// Local84 extraction
//
// Python:
//
// local = feature[:, 0:LOCAL_DIM].copy()
//
// input:
//   [80, 172]
//
// output:
//   [80, 84]
// ============================================================

std::vector<float> extractLocal84(
    const std::vector<float>& feature
);


// ============================================================
// Ranking margin
//
// Python:
//
// if len(ranking) < 2:
//     return 0.0
//
// return ranking[1]["score"] - ranking[0]["score"]
// ============================================================

float rankingMargin(
    const std::vector<ClassScore>& ranking
);


// ============================================================
// Final one-hand classifier
//
// Base:
//   Full80 Local84
//   candidates = {2, 7, 8, 10, 11, 13}
//   K = 3
//
// Special:
//   Base Top-2 set == {2, 7}
//
//   -> MID40 frame 20:60
//   -> candidates = {2, 7}
//   -> K = 3
// ============================================================

OneHandResult classifyOneHand(
    const std::vector<float>& local84,
    const RuntimeData& runtime
);


}  // namespace sign_engine