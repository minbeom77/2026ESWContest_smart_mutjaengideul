#include "knn.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>


namespace sign_engine {


// ============================================================
// query와 하나의 reference 사이의 RMSE
//
// Python:
//
// diff = reference - query
// sqrt(mean(diff ** 2))
//
// Python runtime이 float32를 사용하므로
// 여기서도 float 연산을 유지한다.
// ============================================================

float rmseDistance(
    const float* query,
    const float* reference,
    std::size_t element_count
) {
    if (query == nullptr) {
        throw std::runtime_error(
            "rmseDistance: query is null"
        );
    }

    if (reference == nullptr) {
        throw std::runtime_error(
            "rmseDistance: reference is null"
        );
    }

    if (element_count == 0) {
        throw std::runtime_error(
            "rmseDistance: element_count is zero"
        );
    }


    float sum_squared = 0.0f;

    for (std::size_t i = 0; i < element_count; ++i) {

        const float diff =
            reference[i] - query[i];

        sum_squared += diff * diff;
    }


    const float mean_squared =
        sum_squared /
        static_cast<float>(element_count);


    return std::sqrt(mean_squared);
}


// ============================================================
// 특정 class의 K-nearest 평균 score 계산
//
// Python:
//
// indices = np.where(reference_y == class_id)[0]
//
// distances = rmse_distances(
//     query,
//     references[indices]
// )
//
// order = np.argsort(distances)
//
// selected = distances[order[:k]]
//
// nearest_indices = indices[order[:k]]
//
// score = np.mean(selected)
// ============================================================

ClassScore getClassScore(
    const float* query,
    const std::vector<float>& references,
    const std::vector<std::int32_t>& reference_y,
    std::size_t reference_count,
    std::size_t elements_per_reference,
    std::int32_t class_id,
    std::size_t k
) {
    if (query == nullptr) {
        throw std::runtime_error(
            "getClassScore: query is null"
        );
    }

    if (reference_count == 0) {
        throw std::runtime_error(
            "getClassScore: reference_count is zero"
        );
    }

    if (elements_per_reference == 0) {
        throw std::runtime_error(
            "getClassScore: elements_per_reference is zero"
        );
    }

    if (k == 0) {
        throw std::runtime_error(
            "getClassScore: k is zero"
        );
    }


    const std::size_t expected_reference_elements =
        reference_count *
        elements_per_reference;


    if (references.size() != expected_reference_elements) {
        throw std::runtime_error(
            "getClassScore: references size mismatch"
        );
    }


    if (reference_y.size() != reference_count) {
        throw std::runtime_error(
            "getClassScore: reference_y size mismatch"
        );
    }


    std::vector<std::size_t> class_indices;

    class_indices.reserve(reference_count);


    for (std::size_t i = 0; i < reference_count; ++i) {

        if (reference_y[i] == class_id) {
            class_indices.push_back(i);
        }
    }


    if (class_indices.size() < k) {
        throw std::runtime_error(
            "getClassScore: insufficient references for class " +
            std::to_string(class_id)
        );
    }


    std::vector<std::pair<float, std::size_t>> distances;

    distances.reserve(class_indices.size());


    for (const std::size_t reference_index : class_indices) {

        const float* reference_ptr =
            references.data() +
            (
                reference_index *
                elements_per_reference
            );


        const float distance =
            rmseDistance(
                query,
                reference_ptr,
                elements_per_reference
            );


        distances.emplace_back(
            distance,
            reference_index
        );
    }


    std::sort(
        distances.begin(),
        distances.end(),
        [](
            const std::pair<float, std::size_t>& a,
            const std::pair<float, std::size_t>& b
        ) {
            return a.first < b.first;
        }
    );


    ClassScore result;

    result.class_id = class_id;

    result.nearest_indices.reserve(k);
    result.nearest_distances.reserve(k);


    float score_sum = 0.0f;


    for (std::size_t i = 0; i < k; ++i) {

        const float distance =
            distances[i].first;

        const std::size_t reference_index =
            distances[i].second;


        result.nearest_indices.push_back(
            reference_index
        );

        result.nearest_distances.push_back(
            distance
        );


        score_sum += distance;
    }


    result.score =
        score_sum /
        static_cast<float>(k);


    return result;
}


// ============================================================
// candidate class 전체 ranking
// ============================================================

std::vector<ClassScore> rankClasses(
    const float* query,
    const std::vector<float>& references,
    const std::vector<std::int32_t>& reference_y,
    std::size_t reference_count,
    std::size_t elements_per_reference,
    const std::vector<std::int32_t>& candidate_ids,
    std::size_t k
) {
    if (candidate_ids.empty()) {
        throw std::runtime_error(
            "rankClasses: candidate_ids is empty"
        );
    }


    std::vector<ClassScore> ranking;

    ranking.reserve(candidate_ids.size());


    for (const std::int32_t class_id : candidate_ids) {

        ranking.push_back(
            getClassScore(
                query,
                references,
                reference_y,
                reference_count,
                elements_per_reference,
                class_id,
                k
            )
        );
    }


    std::sort(
        ranking.begin(),
        ranking.end(),
        [](
            const ClassScore& a,
            const ClassScore& b
        ) {
            return a.score < b.score;
        }
    );


    return ranking;
}


// ============================================================
// ranking 안에서 특정 class score 찾기
// ============================================================

float scoreFromRanking(
    const std::vector<ClassScore>& ranking,
    std::int32_t class_id
) {
    for (const ClassScore& item : ranking) {

        if (item.class_id == class_id) {
            return item.score;
        }
    }


    throw std::runtime_error(
        "scoreFromRanking: class not found: " +
        std::to_string(class_id)
    );
}


}  // namespace sign_engine