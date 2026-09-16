#include "c4_gate.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>


namespace sign_engine {

namespace {


// ============================================================
// Mean
// ============================================================

double mean(
    const std::vector<double>& values
) {
    if (values.empty()) {
        return 0.0;
    }

    double sum = 0.0;

    for (const double value : values) {
        sum += value;
    }

    return sum /
           static_cast<double>(values.size());
}


// ============================================================
// Median
//
// NumPy np.median과 동일한 방식
// ============================================================

double median(
    const std::vector<double>& values
) {
    if (values.empty()) {
        return 0.0;
    }

    std::vector<double> sorted = values;

    std::sort(
        sorted.begin(),
        sorted.end()
    );

    const std::size_t n =
        sorted.size();

    if (n % 2 == 1) {
        return sorted[n / 2];
    }

    return (
        sorted[n / 2 - 1] +
        sorted[n / 2]
    ) / 2.0;
}


// ============================================================
// NumPy np.percentile 기본 linear interpolation
//
// position = (N - 1) * percentile / 100
// ============================================================

double percentile(
    const std::vector<double>& values,
    double p
) {
    if (values.empty()) {
        return 0.0;
    }

    if (p <= 0.0) {
        return *std::min_element(
            values.begin(),
            values.end()
        );
    }

    if (p >= 100.0) {
        return *std::max_element(
            values.begin(),
            values.end()
        );
    }

    std::vector<double> sorted = values;

    std::sort(
        sorted.begin(),
        sorted.end()
    );

    const double position =
        (
            static_cast<double>(
                sorted.size() - 1
            )
            *
            p
        )
        /
        100.0;

    const std::size_t lower =
        static_cast<std::size_t>(
            std::floor(position)
        );

    const std::size_t upper =
        static_cast<std::size_t>(
            std::ceil(position)
        );

    if (lower == upper) {
        return sorted[lower];
    }

    const double weight =
        position -
        static_cast<double>(lower);

    return (
        sorted[lower] *
        (1.0 - weight)
        +
        sorted[upper] *
        weight
    );
}


// ============================================================
// NumPy np.std 기본값
//
// ddof = 0
// population standard deviation
// ============================================================

double populationStd(
    const std::vector<double>& values
) {
    if (values.empty()) {
        return 0.0;
    }

    const double m =
        mean(values);

    double squared_sum = 0.0;

    for (const double value : values) {

        const double delta =
            value - m;

        squared_sum +=
            delta * delta;
    }

    const double variance =
        squared_sum /
        static_cast<double>(
            values.size()
        );

    return std::sqrt(
        std::max(
            variance,
            0.0
        )
    );
}


// ============================================================
// Phase means
//
// Python:
//
// edges = np.linspace(
//     0,
//     t,
//     bins + 1,
//     dtype=np.int64
// )
//
// result[i] = mean(array[start:end], axis=0)
//
// 현재 C4에서는:
//   T = 80
//   bins = 5
//
// 따라서:
//   0:16
//   16:32
//   32:48
//   48:64
//   64:80
// ============================================================

std::vector<double> phaseMeans(
    const std::vector<double>& array,
    std::size_t rows,
    std::size_t cols,
    std::size_t bins
) {
    if (rows == 0 ||
        cols == 0 ||
        bins == 0) {

        throw std::runtime_error(
            "phaseMeans: invalid shape"
        );
    }

    if (array.size() != rows * cols) {
        throw std::runtime_error(
            "phaseMeans: array size mismatch"
        );
    }

    std::vector<std::size_t> edges(
        bins + 1
    );

    // np.linspace(0, rows, bins+1, dtype=int64)
    //
    // C4에서는 80 / 5가 정확히 나누어지므로
    // Python과 동일하게 0,16,32,48,64,80이 된다.
    for (std::size_t i = 0; i <= bins; ++i) {

        const double position =
            (
                static_cast<double>(rows) *
                static_cast<double>(i)
            )
            /
            static_cast<double>(bins);

        edges[i] =
            static_cast<std::size_t>(
                position
            );
    }

    std::vector<double> result(
        bins * cols,
        0.0
    );

    for (std::size_t bin = 0; bin < bins; ++bin) {

        const std::size_t start =
            edges[bin];

        const std::size_t end =
            edges[bin + 1];

        if (end <= start) {
            throw std::runtime_error(
                "phaseMeans: phase bin empty"
            );
        }

        const std::size_t count =
            end - start;

        for (std::size_t col = 0; col < cols; ++col) {

            double sum = 0.0;

            for (
                std::size_t row = start;
                row < end;
                ++row
            ) {
                sum +=
                    array[
                        row * cols +
                        col
                    ];
            }

            result[
                bin * cols +
                col
            ] =
                sum /
                static_cast<double>(count);
        }
    }

    return result;
}


// ============================================================
// Extract trajectory [80, 2]
//
// Feature V3:
//   168 = trajectory X
//   169 = trajectory Y
// ============================================================

std::vector<double> getTrajectory(
    const std::vector<float>& feature
) {
    const std::size_t expected_size =
        TARGET_FRAMES *
        FULL_FEATURE_DIM;

    if (feature.size() != expected_size) {
        throw std::runtime_error(
            "getTrajectory: feature size mismatch"
        );
    }

    std::vector<double> trajectory(
        TARGET_FRAMES * 2
    );

    for (
        std::size_t frame = 0;
        frame < TARGET_FRAMES;
        ++frame
    ) {
        trajectory[
            frame * 2
        ] =
            static_cast<double>(
                feature[
                    frame *
                    FULL_FEATURE_DIM +
                    168
                ]
            );

        trajectory[
            frame * 2 + 1
        ] =
            static_cast<double>(
                feature[
                    frame *
                    FULL_FEATURE_DIM +
                    169
                ]
            );
    }

    return trajectory;
}


}  // namespace


// ============================================================
// Local42
//
// Python:
//
// slot_a = sequence[:, 0:42]
// slot_b = sequence[:, 42:84]
//
// energy_a = mean(abs(slot_a))
// energy_b = mean(abs(slot_b))
//
// if energy_b > energy_a:
//     return slot_b
//
// return slot_a
// ============================================================

std::vector<double> getLocal42(
    const std::vector<float>& feature
) {
    const std::size_t expected_size =
        TARGET_FRAMES *
        FULL_FEATURE_DIM;

    if (feature.size() != expected_size) {
        throw std::runtime_error(
            "getLocal42: feature size mismatch"
        );
    }

    double energy_a_sum = 0.0;
    double energy_b_sum = 0.0;


    for (
        std::size_t frame = 0;
        frame < TARGET_FRAMES;
        ++frame
    ) {
        const std::size_t row =
            frame *
            FULL_FEATURE_DIM;

        for (
            std::size_t i = 0;
            i < SLOT_DIM;
            ++i
        ) {
            energy_a_sum +=
                std::abs(
                    static_cast<double>(
                        feature[
                            row + i
                        ]
                    )
                );

            energy_b_sum +=
                std::abs(
                    static_cast<double>(
                        feature[
                            row +
                            SLOT_DIM +
                            i
                        ]
                    )
                );
        }
    }


    const double element_count =
        static_cast<double>(
            TARGET_FRAMES *
            SLOT_DIM
        );


    const double energy_a =
        energy_a_sum /
        element_count;

    const double energy_b =
        energy_b_sum /
        element_count;


    const std::size_t selected_offset =
        (
            energy_b >
            energy_a
        )
        ?
        SLOT_DIM
        :
        0;


    std::vector<double> local42(
        TARGET_FRAMES *
        SLOT_DIM
    );


    for (
        std::size_t frame = 0;
        frame < TARGET_FRAMES;
        ++frame
    ) {
        const std::size_t source_row =
            frame *
            FULL_FEATURE_DIM;

        const std::size_t destination_row =
            frame *
            SLOT_DIM;


        for (
            std::size_t i = 0;
            i < SLOT_DIM;
            ++i
        ) {
            local42[
                destination_row + i
            ] =
                static_cast<double>(
                    feature[
                        source_row +
                        selected_offset +
                        i
                    ]
                );
        }
    }


    return local42;
}


// ============================================================
// Motion20
// ============================================================

std::vector<double> buildMotion20(
    const std::vector<double>& local42,
    const std::vector<double>& trajectory
) {
    if (
        local42.size() !=
        TARGET_FRAMES *
        SLOT_DIM
    ) {
        throw std::runtime_error(
            "buildMotion20: local42 size mismatch"
        );
    }


    if (
        trajectory.size() !=
        TARGET_FRAMES * 2
    ) {
        throw std::runtime_error(
            "buildMotion20: trajectory size mismatch"
        );
    }


    // --------------------------------------------------------
    // Local-frame motion
    //
    // local_delta = np.diff(local42, axis=0)
    // local_speed = np.linalg.norm(local_delta, axis=1)
    // --------------------------------------------------------

    std::vector<double> local_speed;

    local_speed.reserve(
        TARGET_FRAMES - 1
    );


    for (
        std::size_t frame = 0;
        frame + 1 < TARGET_FRAMES;
        ++frame
    ) {
        double squared_sum = 0.0;


        for (
            std::size_t i = 0;
            i < SLOT_DIM;
            ++i
        ) {
            const double current =
                local42[
                    frame *
                    SLOT_DIM +
                    i
                ];

            const double next =
                local42[
                    (frame + 1) *
                    SLOT_DIM +
                    i
                ];

            const double delta =
                next - current;

            squared_sum +=
                delta * delta;
        }


        local_speed.push_back(
            std::sqrt(
                std::max(
                    squared_sum,
                    0.0
                )
            )
        );
    }


    // --------------------------------------------------------
    // Trajectory motion
    //
    // traj_delta = np.diff(trajectory, axis=0)
    // traj_speed = np.linalg.norm(traj_delta, axis=1)
    // --------------------------------------------------------

    std::vector<double> traj_delta(
        (TARGET_FRAMES - 1) * 2
    );

    std::vector<double> traj_speed;

    traj_speed.reserve(
        TARGET_FRAMES - 1
    );


    for (
        std::size_t frame = 0;
        frame + 1 < TARGET_FRAMES;
        ++frame
    ) {
        const double dx =
            trajectory[
                (frame + 1) * 2
            ]
            -
            trajectory[
                frame * 2
            ];

        const double dy =
            trajectory[
                (frame + 1) * 2 + 1
            ]
            -
            trajectory[
                frame * 2 + 1
            ];


        traj_delta[
            frame * 2
        ] = dx;

        traj_delta[
            frame * 2 + 1
        ] = dy;


        traj_speed.push_back(
            std::sqrt(
                dx * dx +
                dy * dy
            )
        );
    }


    // --------------------------------------------------------
    // local_stats = 6
    // --------------------------------------------------------

    const std::vector<double> local_stats = {
        mean(local_speed),
        median(local_speed),
        percentile(local_speed, 75.0),
        percentile(local_speed, 90.0),
        *std::max_element(
            local_speed.begin(),
            local_speed.end()
        ),
        populationStd(local_speed)
    };


    // --------------------------------------------------------
    // traj_stats = 6
    // --------------------------------------------------------

    const std::vector<double> traj_stats = {
        mean(traj_speed),
        median(traj_speed),
        percentile(traj_speed, 75.0),
        percentile(traj_speed, 90.0),
        *std::max_element(
            traj_speed.begin(),
            traj_speed.end()
        ),
        populationStd(traj_speed)
    };


    // --------------------------------------------------------
    // Displacement
    // --------------------------------------------------------

    const double displacement_x =
        trajectory[
            (TARGET_FRAMES - 1) * 2
        ]
        -
        trajectory[0];

    const double displacement_y =
        trajectory[
            (TARGET_FRAMES - 1) * 2 + 1
        ]
        -
        trajectory[1];


    const double displacement =
        std::sqrt(
            displacement_x *
            displacement_x
            +
            displacement_y *
            displacement_y
        );


    // --------------------------------------------------------
    // Path
    // --------------------------------------------------------

    double path = 0.0;

    for (const double speed : traj_speed) {
        path += speed;
    }


    // --------------------------------------------------------
    // Straightness
    //
    // displacement / (path + 1e-8)
    // --------------------------------------------------------

    const double straightness =
        displacement /
        (
            path +
            1e-8
        );


    // --------------------------------------------------------
    // Direction resultant
    //
    // moving = traj_speed > 1e-8
    //
    // unit = traj_delta / traj_speed
    //
    // norm(mean(unit))
    // --------------------------------------------------------

    double direction_sum_x = 0.0;
    double direction_sum_y = 0.0;

    std::size_t moving_count = 0;


    for (
        std::size_t i = 0;
        i < traj_speed.size();
        ++i
    ) {
        const double speed =
            traj_speed[i];


        if (speed > 1e-8) {

            direction_sum_x +=
                traj_delta[
                    i * 2
                ]
                /
                speed;

            direction_sum_y +=
                traj_delta[
                    i * 2 + 1
                ]
                /
                speed;

            ++moving_count;
        }
    }


    double direction_resultant = 0.0;


    if (moving_count > 0) {

        const double mean_x =
            direction_sum_x /
            static_cast<double>(
                moving_count
            );

        const double mean_y =
            direction_sum_y /
            static_cast<double>(
                moving_count
            );


        direction_resultant =
            std::sqrt(
                mean_x * mean_x +
                mean_y * mean_y
            );
    }


    // --------------------------------------------------------
    // Bounding box
    //
    // bbox = max(trajectory) - min(trajectory)
    // --------------------------------------------------------

    double min_x =
        trajectory[0];

    double max_x =
        trajectory[0];

    double min_y =
        trajectory[1];

    double max_y =
        trajectory[1];


    for (
        std::size_t frame = 1;
        frame < TARGET_FRAMES;
        ++frame
    ) {
        const double x =
            trajectory[
                frame * 2
            ];

        const double y =
            trajectory[
                frame * 2 + 1
            ];


        min_x =
            std::min(
                min_x,
                x
            );

        max_x =
            std::max(
                max_x,
                x
            );

        min_y =
            std::min(
                min_y,
                y
            );

        max_y =
            std::max(
                max_y,
                y
            );
    }


    const double bbox_x =
        max_x -
        min_x;

    const double bbox_y =
        max_y -
        min_y;


    // --------------------------------------------------------
    // Start / End speed
    //
    // segment = max(1, len(traj_speed) // 4)
    //
    // len = 79
    // segment = 19
    // --------------------------------------------------------

    const std::size_t segment =
        std::max<std::size_t>(
            1,
            traj_speed.size() / 4
        );


    double start_sum = 0.0;

    for (
        std::size_t i = 0;
        i < segment;
        ++i
    ) {
        start_sum +=
            traj_speed[i];
    }


    const double start_speed =
        start_sum /
        static_cast<double>(
            segment
        );


    double end_sum = 0.0;

    for (
        std::size_t i =
            traj_speed.size() - segment;
        i < traj_speed.size();
        ++i
    ) {
        end_sum +=
            traj_speed[i];
    }


    const double end_speed =
        end_sum /
        static_cast<double>(
            segment
        );


    // --------------------------------------------------------
    // Motion20
    // --------------------------------------------------------

    std::vector<double> result;

    result.reserve(20);


    for (const double value : local_stats) {
        result.push_back(value);
    }


    for (const double value : traj_stats) {
        result.push_back(value);
    }


    result.push_back(
        displacement
    );

    result.push_back(
        path
    );

    result.push_back(
        straightness
    );

    result.push_back(
        direction_resultant
    );

    result.push_back(
        bbox_x
    );

    result.push_back(
        bbox_y
    );

    result.push_back(
        start_speed
    );

    result.push_back(
        end_speed
    );


    if (result.size() != 20) {
        throw std::runtime_error(
            "buildMotion20: output size mismatch"
        );
    }


    return result;
}


// ============================================================
// C4 feature
//
// C4_MOTION_LOCAL230 = Motion20 + LocalPhase210
// ============================================================

std::vector<double> buildC4Feature(
    const std::vector<float>& feature
) {
    const std::size_t expected_size =
        TARGET_FRAMES *
        FULL_FEATURE_DIM;


    if (feature.size() != expected_size) {
        throw std::runtime_error(
            "buildC4Feature: feature size mismatch"
        );
    }


    const std::vector<double> local42 =
        getLocal42(
            feature
        );


    const std::vector<double> trajectory =
        getTrajectory(
            feature
        );


    const std::vector<double> motion20 =
        buildMotion20(
            local42,
            trajectory
        );


    // --------------------------------------------------------
    // Local phase
    //
    // 5 × 42 = 210
    // --------------------------------------------------------

    const std::vector<double> local_phase210 =
        phaseMeans(
            local42,
            TARGET_FRAMES,
            SLOT_DIM,
            5
        );


    if (local_phase210.size() != 210) {
        throw std::runtime_error(
            "buildC4Feature: local phase size mismatch"
        );
    }


    // --------------------------------------------------------
    // Motion20 + LocalPhase210
    // --------------------------------------------------------

    std::vector<double> c4;

    c4.reserve(
        C4_FEATURE_DIM
    );


    c4.insert(
        c4.end(),
        motion20.begin(),
        motion20.end()
    );


    c4.insert(
        c4.end(),
        local_phase210.begin(),
        local_phase210.end()
    );


    if (c4.size() != C4_FEATURE_DIM) {
        throw std::runtime_error(
            "buildC4Feature: C4 size mismatch"
        );
    }


    for (const double value : c4) {

        if (!std::isfinite(value)) {
            throw std::runtime_error(
                "buildC4Feature: NaN or Inf"
            );
        }
    }


    return c4;
}


// ============================================================
// Standardization
//
// Python:
//
// z_feature =
//     (c4 - c4_model["mean"])
//     / c4_model["std"]
// ============================================================

std::vector<double> standardizeC4Feature(
    const std::vector<double>& c4_feature,
    const RuntimeData& runtime
) {
    if (c4_feature.size() != C4_FEATURE_DIM) {
        throw std::runtime_error(
            "standardizeC4Feature: C4 size mismatch"
        );
    }


    if (
        runtime.c4_mean.size() !=
        C4_FEATURE_DIM
    ) {
        throw std::runtime_error(
            "standardizeC4Feature: mean size mismatch"
        );
    }


    if (
        runtime.c4_std.size() !=
        C4_FEATURE_DIM
    ) {
        throw std::runtime_error(
            "standardizeC4Feature: std size mismatch"
        );
    }


    std::vector<double> z(
        C4_FEATURE_DIM
    );


    for (
        std::size_t i = 0;
        i < C4_FEATURE_DIM;
        ++i
    ) {
        const double mean_value =
            static_cast<double>(
                runtime.c4_mean[i]
            );

        const double std_value =
            static_cast<double>(
                runtime.c4_std[i]
            );


        if (std_value == 0.0) {
            throw std::runtime_error(
                "standardizeC4Feature: zero std at index " +
                std::to_string(i)
            );
        }


        z[i] =
            (
                c4_feature[i] -
                mean_value
            )
            /
            std_value;


        if (!std::isfinite(z[i])) {
            throw std::runtime_error(
                "standardizeC4Feature: NaN or Inf"
            );
        }
    }


    return z;
}


// ============================================================
// Frozen C4 nearest K mean Euclidean distance
//
// Python:
//
// delta = references - vector[None, :]
//
// squared = np.sum(delta * delta, axis=1)
//
// nearest_squared = np.partition(
//     squared,
//     kth=k-1
// )[:k]
//
// mean(sqrt(max(nearest_squared, 0)))
// ============================================================

double c4NearestKMeanDistance(
    const std::vector<double>& vector,
    const std::vector<float>& references,
    std::size_t reference_count,
    std::size_t k
) {
    if (vector.size() != C4_FEATURE_DIM) {
        throw std::runtime_error(
            "c4NearestKMeanDistance: vector size mismatch"
        );
    }


    if (
        references.size() !=
        reference_count *
        C4_FEATURE_DIM
    ) {
        throw std::runtime_error(
            "c4NearestKMeanDistance: reference size mismatch"
        );
    }


    if (
        k == 0 ||
        k > reference_count
    ) {
        throw std::runtime_error(
            "c4NearestKMeanDistance: invalid k"
        );
    }


    std::vector<double> squared_distances(
        reference_count
    );


    for (
        std::size_t reference_index = 0;
        reference_index < reference_count;
        ++reference_index
    ) {
        double squared_sum = 0.0;


        const std::size_t offset =
            reference_index *
            C4_FEATURE_DIM;


        for (
            std::size_t i = 0;
            i < C4_FEATURE_DIM;
            ++i
        ) {
            const double reference_value =
                static_cast<double>(
                    references[
                        offset + i
                    ]
                );


            const double delta =
                reference_value -
                vector[i];


            squared_sum +=
                delta *
                delta;
        }


        squared_distances[
            reference_index
        ] =
            squared_sum;
    }


    // np.partition의 목적은 가장 작은 K개를 찾는 것.
    // 평균값만 필요하므로 전체 오름차순 정렬로 동일한 K개를 선택한다.
    std::sort(
        squared_distances.begin(),
        squared_distances.end()
    );


    double sum = 0.0;


    for (
        std::size_t i = 0;
        i < k;
        ++i
    ) {
        sum +=
            std::sqrt(
                std::max(
                    squared_distances[i],
                    0.0
                )
            );
    }


    return sum /
           static_cast<double>(k);
}


// ============================================================
// Frozen one-hand C4 SIGN / NO-SIGN gate
// ============================================================

C4GateResult classifyOnehandC4Gate(
    const std::vector<float>& feature,
    const RuntimeData& runtime
) {
    const std::vector<double> c4 =
        buildC4Feature(
            feature
        );


    const std::vector<double> z_feature =
        standardizeC4Feature(
            c4,
            runtime
        );


    const double d_sign =
        c4NearestKMeanDistance(
            z_feature,
            runtime.c4_sign,
            C4_SIGN_REFERENCE_COUNT,
            C4_K
        );


    const double d_nosign =
        c4NearestKMeanDistance(
            z_feature,
            runtime.c4_nosign,
            C4_NOSIGN_REFERENCE_COUNT,
            C4_K
        );


    const int prediction =
        (
            d_sign <=
            d_nosign
        )
        ?
        C4_SIGN_LABEL
        :
        C4_NOSIGN_LABEL;


    C4GateResult result;

    result.prediction =
        prediction;

    result.d_sign =
        d_sign;

    result.d_nosign =
        d_nosign;

    result.margin_nosign_minus_sign =
        d_nosign -
        d_sign;


    return result;
}


}  // namespace sign_engine