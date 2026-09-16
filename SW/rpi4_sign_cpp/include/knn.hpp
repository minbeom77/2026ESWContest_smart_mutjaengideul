#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>


namespace sign_engine {

struct ClassScore {
    std::int32_t class_id = -1;

    float score = 0.0f;

    std::vector<std::size_t> nearest_indices;
    std::vector<float> nearest_distances;
};


// query와 하나의 reference 사이의 RMSE
float rmseDistance(
    const float* query,
    const float* reference,
    std::size_t element_count
);


// 특정 class의 K-nearest 평균 score 계산
ClassScore getClassScore(
    const float* query,
    const std::vector<float>& references,
    const std::vector<std::int32_t>& reference_y,
    std::size_t reference_count,
    std::size_t elements_per_reference,
    std::int32_t class_id,
    std::size_t k
);


// candidate class들을 score 순으로 정렬
std::vector<ClassScore> rankClasses(
    const float* query,
    const std::vector<float>& references,
    const std::vector<std::int32_t>& reference_y,
    std::size_t reference_count,
    std::size_t elements_per_reference,
    const std::vector<std::int32_t>& candidate_ids,
    std::size_t k
);


// ranking 안에서 특정 class의 score 찾기
float scoreFromRanking(
    const std::vector<ClassScore>& ranking,
    std::int32_t class_id
);


}  // namespace sign_engine