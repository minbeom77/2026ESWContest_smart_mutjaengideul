#include "temporal_resample.hpp"

#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>


namespace sign_engine {

std::vector<float> temporalResample(
    const std::vector<float>& sequence,
    std::size_t original_frames,
    std::size_t feature_dim,
    std::size_t target_frames
) {
    // ========================================================
    // Python:
    //
    // sequence = np.asarray(
    //     sequence,
    //     dtype=np.float32,
    // )
    //
    // C++ 입력 자체가 float32(vector<float>)이므로
    // 별도 변환 필요 없음.
    // ========================================================


    // ========================================================
    // Shape validation
    // ========================================================

    const std::size_t expected_size =
        original_frames * feature_dim;


    if (sequence.size() != expected_size) {
        throw std::invalid_argument(
            "temporalResample: sequence size mismatch"
        );
    }


    // ========================================================
    // Python:
    //
    // if original_frames < 2:
    //     raise ValueError(...)
    // ========================================================

    if (original_frames < 2) {
        throw std::invalid_argument(
            "temporalResample: original_frames < 2"
        );
    }


    // ========================================================
    // Python:
    //
    // if original_frames == target_frames:
    //     return sequence.copy()
    // ========================================================

    if (original_frames == target_frames) {
        return sequence;
    }


    // ========================================================
    // Python np.linspace allows target_frames == 0.
    //
    // Runtime에서는 80을 사용하지만 함수 의미를
    // 최대한 그대로 유지한다.
    // ========================================================

    if (target_frames == 0) {
        return {};
    }


    std::vector<float> output(
        target_frames * feature_dim,
        0.0f
    );


    // ========================================================
    // target_frames == 1
    //
    // np.linspace(0, 1, 1) -> [0.0]
    // 따라서 np.interp 결과는 첫 번째 프레임 값.
    // ========================================================

    if (target_frames == 1) {

        for (
            std::size_t dim = 0;
            dim < feature_dim;
            ++dim
        ) {
            output[dim] =
                sequence[dim];
        }

        return output;
    }


    // ========================================================
    // Python:
    //
    // old_x = np.linspace(
    //     0.0,
    //     1.0,
    //     original_frames,
    //     dtype=np.float64,
    // )
    //
    // new_x = np.linspace(
    //     0.0,
    //     1.0,
    //     target_frames,
    //     dtype=np.float64,
    // )
    //
    // old_x는 균등 간격이므로:
    //
    // old_x[i] = i / (original_frames - 1)
    //
    // new_x[j] = j / (target_frames - 1)
    //
    // np.interp와 동일하게 double 정밀도로
    // 보간 위치를 계산한다.
    // ========================================================

    const double old_last =
        static_cast<double>(
            original_frames - 1
        );


    const double new_last =
        static_cast<double>(
            target_frames - 1
        );


    // ========================================================
    // Python:
    //
    // for dim in range(feature_dim):
    //
    //     output[:, dim] = np.interp(
    //         new_x,
    //         old_x,
    //         sequence[:, dim],
    //     )
    // ========================================================

    for (
        std::size_t dim = 0;
        dim < feature_dim;
        ++dim
    ) {

        for (
            std::size_t new_frame = 0;
            new_frame < target_frames;
            ++new_frame
        ) {

            // ------------------------------------------------
            // new_x 위치를 old frame 좌표로 변환.
            //
            // new_x =
            //     new_frame / (target_frames - 1)
            //
            // old_position =
            //     new_x * (original_frames - 1)
            // ------------------------------------------------

            const double new_x =
                static_cast<double>(
                    new_frame
                )
                /
                new_last;


            const double old_position =
                new_x * old_last;


            std::size_t lower_frame =
                static_cast<std::size_t>(
                    std::floor(
                        old_position
                    )
                );


            // 마지막 좌표는 정확히 마지막 frame.
            if (
                lower_frame >=
                original_frames - 1
            ) {
                output[
                    new_frame * feature_dim
                    +
                    dim
                ] =
                    sequence[
                        (original_frames - 1)
                        *
                        feature_dim
                        +
                        dim
                    ];

                continue;
            }


            const std::size_t upper_frame =
                lower_frame + 1;


            const double alpha =
                old_position
                -
                static_cast<double>(
                    lower_frame
                );


            const double lower_value =
                static_cast<double>(
                    sequence[
                        lower_frame
                        *
                        feature_dim
                        +
                        dim
                    ]
                );


            const double upper_value =
                static_cast<double>(
                    sequence[
                        upper_frame
                        *
                        feature_dim
                        +
                        dim
                    ]
                );


            // ------------------------------------------------
            // Linear interpolation
            //
            // np.interp 결과는 내부적으로 double이고
            // Python 코드에서는 float32 output 배열에
            // 저장되므로 마지막에 float으로 변환.
            // ------------------------------------------------

            const double interpolated =
                lower_value
                +
                (
                    upper_value
                    -
                    lower_value
                )
                *
                alpha;


            output[
                new_frame * feature_dim
                +
                dim
            ] =
                static_cast<float>(
                    interpolated
                );
        }
    }


    return output;
}


}  // namespace sign_engine