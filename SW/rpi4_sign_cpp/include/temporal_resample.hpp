#pragma once

#include <cstddef>
#include <vector>


namespace sign_engine {

constexpr std::size_t TEMPORAL_TARGET_FRAMES = 80;


/**
 * Python 06j temporal_resample() equivalent.
 *
 * Input layout:
 *   [original_frames, feature_dim]
 *
 * flattened row-major:
 *   frame0_dim0, frame0_dim1, ...
 *
 * Output layout:
 *   [target_frames, feature_dim]
 *
 * float32 output.
 */
std::vector<float> temporalResample(
    const std::vector<float>& sequence,
    std::size_t original_frames,
    std::size_t feature_dim,
    std::size_t target_frames =
        TEMPORAL_TARGET_FRAMES
);


}  // namespace sign_engine