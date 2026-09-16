#include "feature_v3.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>


namespace sign_engine {

namespace {


// ============================================================
// Finite check
// ============================================================

bool isFinitePoint(
    const Point2f& point
) {
    return (
        std::isfinite(
            static_cast<double>(point.x)
        )
        &&
        std::isfinite(
            static_cast<double>(point.y)
        )
    );
}


// ============================================================
// Hand 전체 zero 여부
// ============================================================

bool isZeroHand(
    const HandLandmarks& hand
) {
    for (const Point2f& point : hand.points) {

        if (
            std::abs(
                static_cast<double>(point.x)
            ) >= FEATURE_V3_EPS
            ||
            std::abs(
                static_cast<double>(point.y)
            ) >= FEATURE_V3_EPS
        ) {
            return false;
        }
    }

    return true;
}


// ============================================================
// Median
//
// np.median 대응
// ============================================================

double median(
    const std::vector<double>& values
) {
    if (values.empty()) {
        return 0.0;
    }

    std::vector<double> sorted =
        values;

    std::sort(
        sorted.begin(),
        sorted.end()
    );

    const std::size_t count =
        sorted.size();

    if (count % 2 == 1) {
        return sorted[
            count / 2
        ];
    }

    return (
        sorted[
            count / 2 - 1
        ]
        +
        sorted[
            count / 2
        ]
    ) / 2.0;
}


// ============================================================
// NumPy np.percentile 기본 linear interpolation
// ============================================================

double percentile(
    const std::vector<double>& values,
    double percentile_value
) {
    if (values.empty()) {
        return 0.0;
    }

    std::vector<double> sorted =
        values;

    std::sort(
        sorted.begin(),
        sorted.end()
    );

    if (percentile_value <= 0.0) {
        return sorted.front();
    }

    if (percentile_value >= 100.0) {
        return sorted.back();
    }

    const double position =
        (
            static_cast<double>(
                sorted.size() - 1
            )
            *
            percentile_value
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
// Frame 수 검증
// ============================================================

void validateSameFrameCount(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence
) {
    if (
        left_sequence != nullptr
        &&
        right_sequence != nullptr
    ) {
        if (
            left_sequence->size()
            !=
            right_sequence->size()
        ) {
            throw std::runtime_error(
                "Left / Right frame count mismatch"
            );
        }
    }
}


// ============================================================
// Frame 수 얻기
// ============================================================

std::size_t getFrameCount(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence
) {
    if (left_sequence != nullptr) {
        return left_sequence->size();
    }

    if (right_sequence != nullptr) {
        return right_sequence->size();
    }

    return 0;
}


// ============================================================
// Zero local sequence
//
// flat [T, 42]
// ============================================================

std::vector<double> makeZeroLocal(
    std::size_t frame_count
) {
    return std::vector<double>(
        frame_count *
        FEATURE_V3_SLOT_DIM,
        0.0
    );
}


// ============================================================
// double -> float
// ============================================================

std::vector<float> toFloatVector(
    const std::vector<double>& values
) {
    std::vector<float> output(
        values.size()
    );

    for (
        std::size_t i = 0;
        i < values.size();
        ++i
    ) {
        output[i] =
            static_cast<float>(
                values[i]
            );
    }

    return output;
}


// ============================================================
// Active / canonical 동일 여부
// ============================================================

bool activeMatchesCanonical(
    ActiveHand active_hand,
    CanonicalHand canonical_hand
) {
    if (
        active_hand == ActiveHand::Left
        &&
        canonical_hand == CanonicalHand::Left
    ) {
        return true;
    }

    if (
        active_hand == ActiveHand::Right
        &&
        canonical_hand == CanonicalHand::Right
    ) {
        return true;
    }

    return false;
}


}  // namespace


// ============================================================
// String helpers
// ============================================================

std::string usageTypeToString(
    UsageType type
) {
    switch (type) {

        case UsageType::Invalid:
            return "invalid";

        case UsageType::OneHand:
            return "one_hand";

        case UsageType::TwoHand:
            return "two_hand";
    }

    return "invalid";
}


std::string activeHandToString(
    ActiveHand hand
) {
    switch (hand) {

        case ActiveHand::None:
            return "NONE";

        case ActiveHand::Left:
            return "LEFT";

        case ActiveHand::Right:
            return "RIGHT";

        case ActiveHand::Both:
            return "BOTH";
    }

    return "NONE";
}


// ============================================================
// Missing sequence
//
// Python:
//
// if sequence is None:
//     return True
//
// if len(sequence) == 0:
//     return True
//
// return all(abs(sequence) < EPS)
// ============================================================

bool isMissingSequence(
    const HandSequence* sequence
) {
    if (sequence == nullptr) {
        return true;
    }

    if (sequence->empty()) {
        return true;
    }

    for (const HandLandmarks& hand : *sequence) {

        for (const Point2f& point : hand.points) {

            if (
                std::abs(
                    static_cast<double>(point.x)
                ) >= FEATURE_V3_EPS
                ||
                std::abs(
                    static_cast<double>(point.y)
                ) >= FEATURE_V3_EPS
            ) {
                return false;
            }
        }
    }

    return true;
}


// ============================================================
// Hand scale
//
// wrist -> landmarks 5,9,13,17
// valid distances mean
// ============================================================

double handScale(
    const HandLandmarks& hand
) {
    for (const Point2f& point : hand.points) {

        if (!isFinitePoint(point)) {
            return 0.0;
        }
    }


    if (isZeroHand(hand)) {
        return 0.0;
    }


    const Point2f& wrist =
        hand.points[0];


    std::vector<double> distances;

    distances.reserve(
        HAND_SCALE_LANDMARK_COUNT
    );


    for (
        const std::size_t index :
        HAND_SCALE_LANDMARKS
    ) {
        const Point2f& point =
            hand.points[index];


        const double dx =
            static_cast<double>(point.x)
            -
            static_cast<double>(wrist.x);

        const double dy =
            static_cast<double>(point.y)
            -
            static_cast<double>(wrist.y);


        const double distance =
            std::sqrt(
                dx * dx +
                dy * dy
            );


        if (
            std::isfinite(distance)
            &&
            distance > FEATURE_V3_EPS
        ) {
            distances.push_back(
                distance
            );
        }
    }


    if (distances.empty()) {
        return 0.0;
    }


    double sum = 0.0;

    for (const double distance : distances) {
        sum += distance;
    }


    return (
        sum /
        static_cast<double>(
            distances.size()
        )
    );
}


// ============================================================
// Single-hand sequence scale
//
// valid frame hand scales median
// ============================================================

double singleHandSequenceScale(
    const HandSequence& hand_sequence
) {
    std::vector<double> scales;

    scales.reserve(
        hand_sequence.size()
    );


    for (
        const HandLandmarks& hand :
        hand_sequence
    ) {
        const double scale =
            handScale(
                hand
            );


        if (
            std::isfinite(scale)
            &&
            scale > FEATURE_V3_EPS
        ) {
            scales.push_back(
                scale
            );
        }
    }


    if (scales.empty()) {
        return 1.0;
    }


    return median(
        scales
    );
}


// ============================================================
// Bilateral sequence scale
//
// left + right 모든 valid frame scale median
// ============================================================

double sequenceScale(
    const HandSequence& left_sequence,
    const HandSequence& right_sequence
) {
    validateSameFrameCount(
        &left_sequence,
        &right_sequence
    );


    std::vector<double> scales;

    scales.reserve(
        left_sequence.size()
        +
        right_sequence.size()
    );


    const HandSequence* sequences[] = {
        &left_sequence,
        &right_sequence
    };


    for (
        const HandSequence* sequence :
        sequences
    ) {
        if (
            sequence == nullptr
            ||
            isMissingSequence(sequence)
        ) {
            continue;
        }


        for (
            const HandLandmarks& hand :
            *sequence
        ) {
            const double scale =
                handScale(
                    hand
                );


            if (
                std::isfinite(scale)
                &&
                scale > FEATURE_V3_EPS
            ) {
                scales.push_back(
                    scale
                );
            }
        }
    }


    if (scales.empty()) {
        return 1.0;
    }


    return median(
        scales
    );
}


// ============================================================
// Local hand
//
// output flat [T,42]
// ============================================================

std::vector<double> makeLocalHand(
    const HandSequence& hand_sequence
) {
    const std::size_t frame_count =
        hand_sequence.size();


    std::vector<double> output(
        frame_count *
        FEATURE_V3_SLOT_DIM,
        0.0
    );


    const double fallback_scale =
        singleHandSequenceScale(
            hand_sequence
        );


    for (
        std::size_t frame_index = 0;
        frame_index < frame_count;
        ++frame_index
    ) {
        const HandLandmarks& hand =
            hand_sequence[
                frame_index
            ];


        // Python:
        // zero frame -> continue
        if (isZeroHand(hand)) {
            continue;
        }


        const Point2f& wrist =
            hand.points[0];


        double scale =
            handScale(
                hand
            );


        if (
            !std::isfinite(scale)
            ||
            scale <= FEATURE_V3_EPS
        ) {
            scale =
                fallback_scale;
        }


        if (
            !std::isfinite(scale)
            ||
            scale <= FEATURE_V3_EPS
        ) {
            scale =
                1.0;
        }


        for (
            std::size_t landmark_index = 0;
            landmark_index < HAND_LANDMARK_COUNT;
            ++landmark_index
        ) {
            const Point2f& point =
                hand.points[
                    landmark_index
                ];


            const double local_x =
                (
                    static_cast<double>(
                        point.x
                    )
                    -
                    static_cast<double>(
                        wrist.x
                    )
                )
                /
                scale;


            const double local_y =
                (
                    static_cast<double>(
                        point.y
                    )
                    -
                    static_cast<double>(
                        wrist.y
                    )
                )
                /
                scale;


            const std::size_t offset =
                frame_index *
                FEATURE_V3_SLOT_DIM
                +
                landmark_index * 2;


            output[
                offset
            ] =
                local_x;

            output[
                offset + 1
            ] =
                local_y;
        }
    }


    return output;
}


// ============================================================
// Motion score
// ============================================================

double calculateHandMotionScore(
    const HandSequence* hand_sequence
) {
    if (hand_sequence == nullptr) {
        return 0.0;
    }


    if (hand_sequence->size() < 2) {
        return 0.0;
    }


    if (isMissingSequence(hand_sequence)) {
        return 0.0;
    }


    const double scale =
        singleHandSequenceScale(
            *hand_sequence
        );


    double total_motion =
        0.0;


    for (
        std::size_t frame = 0;
        frame + 1 < hand_sequence->size();
        ++frame
    ) {
        double frame_motion_sum =
            0.0;


        const HandLandmarks& current =
            (*hand_sequence)[frame];

        const HandLandmarks& next =
            (*hand_sequence)[frame + 1];


        for (
            std::size_t landmark = 0;
            landmark < HAND_LANDMARK_COUNT;
            ++landmark
        ) {
            const double dx =
                static_cast<double>(
                    next.points[landmark].x
                )
                -
                static_cast<double>(
                    current.points[landmark].x
                );

            const double dy =
                static_cast<double>(
                    next.points[landmark].y
                )
                -
                static_cast<double>(
                    current.points[landmark].y
                );


            frame_motion_sum +=
                std::sqrt(
                    dx * dx +
                    dy * dy
                );
        }


        const double frame_motion =
            frame_motion_sum
            /
            static_cast<double>(
                HAND_LANDMARK_COUNT
            );


        const double normalized_motion =
            frame_motion
            /
            (
                scale +
                FEATURE_V3_EPS
            );


        total_motion +=
            normalized_motion;
    }


    return total_motion;
}


// ============================================================
// Hand usage
// ============================================================

HandUsage detectHandUsage(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence,
    double one_hand_ratio_threshold,
    double no_motion_threshold
) {
    validateSameFrameCount(
        left_sequence,
        right_sequence
    );


    const bool left_detected =
        !isMissingSequence(
            left_sequence
        );

    const bool right_detected =
        !isMissingSequence(
            right_sequence
        );


    HandUsage usage;


    usage.detected_mask = {
        left_detected
            ? 1.0f
            : 0.0f,

        right_detected
            ? 1.0f
            : 0.0f
    };


    const double left_score =
        left_detected
        ?
        calculateHandMotionScore(
            left_sequence
        )
        :
        0.0;


    const double right_score =
        right_detected
        ?
        calculateHandMotionScore(
            right_sequence
        )
        :
        0.0;


    usage.left_score =
        left_score;

    usage.right_score =
        right_score;


    // ========================================================
    // No hand
    // ========================================================

    if (
        !left_detected
        &&
        !right_detected
    ) {
        usage.type =
            UsageType::Invalid;

        usage.active_hand =
            ActiveHand::None;

        usage.ratio =
            1.0;

        usage.usage_mask = {
            0.0f,
            0.0f
        };

        return usage;
    }


    // ========================================================
    // LEFT only
    // ========================================================

    if (
        left_detected
        &&
        !right_detected
    ) {
        usage.ratio =
            0.0;


        if (
            left_score <
            no_motion_threshold
        ) {
            usage.type =
                UsageType::Invalid;

            usage.active_hand =
                ActiveHand::None;

            usage.usage_mask = {
                0.0f,
                0.0f
            };
        }
        else {
            usage.type =
                UsageType::OneHand;

            usage.active_hand =
                ActiveHand::Left;

            usage.usage_mask = {
                1.0f,
                0.0f
            };
        }


        return usage;
    }


    // ========================================================
    // RIGHT only
    // ========================================================

    if (
        right_detected
        &&
        !left_detected
    ) {
        usage.ratio =
            0.0;


        if (
            right_score <
            no_motion_threshold
        ) {
            usage.type =
                UsageType::Invalid;

            usage.active_hand =
                ActiveHand::None;

            usage.usage_mask = {
                0.0f,
                0.0f
            };
        }
        else {
            usage.type =
                UsageType::OneHand;

            usage.active_hand =
                ActiveHand::Right;

            usage.usage_mask = {
                1.0f,
                0.0f
            };
        }


        return usage;
    }


    // ========================================================
    // Both hands detected
    // ========================================================

    const double stronger =
        std::max(
            left_score,
            right_score
        );


    const double weaker =
        std::min(
            left_score,
            right_score
        );


    if (
        stronger <
        no_motion_threshold
    ) {
        usage.type =
            UsageType::Invalid;

        usage.active_hand =
            ActiveHand::None;

        usage.ratio =
            1.0;

        usage.usage_mask = {
            0.0f,
            0.0f
        };

        return usage;
    }


    const double ratio =
        weaker
        /
        (
            stronger +
            FEATURE_V3_EPS
        );


    usage.ratio =
        ratio;


    // ========================================================
    // One-hand
    // ========================================================

    if (
        ratio <
        one_hand_ratio_threshold
    ) {
        usage.type =
            UsageType::OneHand;


        if (
            left_score >
            right_score
        ) {
            usage.active_hand =
                ActiveHand::Left;
        }
        else {
            usage.active_hand =
                ActiveHand::Right;
        }


        usage.usage_mask = {
            1.0f,
            0.0f
        };


        return usage;
    }


    // ========================================================
    // Two-hand
    // ========================================================

    usage.type =
        UsageType::TwoHand;

    usage.active_hand =
        ActiveHand::Both;

    usage.usage_mask = {
        1.0f,
        1.0f
    };


    return usage;
}


// ============================================================
// One-hand canonicalization
// ============================================================

std::vector<double> canonicalizeOneHandLocal(
    const std::vector<double>& local_sequence,
    std::size_t frame_count,
    ActiveHand active_hand,
    CanonicalHand canonical_hand
) {
    if (
        local_sequence.size()
        !=
        frame_count *
        FEATURE_V3_SLOT_DIM
    ) {
        throw std::runtime_error(
            "canonicalizeOneHandLocal: size mismatch"
        );
    }


    if (
        active_hand != ActiveHand::Left
        &&
        active_hand != ActiveHand::Right
    ) {
        throw std::runtime_error(
            "canonicalizeOneHandLocal: invalid active hand"
        );
    }


    std::vector<double> output =
        local_sequence;


    if (
        activeMatchesCanonical(
            active_hand,
            canonical_hand
        )
    ) {
        return output;
    }


    // mirror X
    //
    // flat landmark:
    // x,y,x,y,...
    for (
        std::size_t frame = 0;
        frame < frame_count;
        ++frame
    ) {
        for (
            std::size_t landmark = 0;
            landmark < HAND_LANDMARK_COUNT;
            ++landmark
        ) {
            const std::size_t x_index =
                frame *
                FEATURE_V3_SLOT_DIM
                +
                landmark * 2;


            output[
                x_index
            ] *= -1.0;
        }
    }


    return output;
}


// ============================================================
// Pair-relative
// ============================================================

PairRelativeResult makePairRelativeFeatures(
    const HandSequence& left_sequence,
    const HandSequence& right_sequence
) {
    validateSameFrameCount(
        &left_sequence,
        &right_sequence
    );


    const std::size_t frame_count =
        left_sequence.size();


    double scale =
        sequenceScale(
            left_sequence,
            right_sequence
        );


    if (
        !std::isfinite(scale)
        ||
        scale <= FEATURE_V3_EPS
    ) {
        scale =
            1.0;
    }


    PairRelativeResult result;


    result.left.resize(
        frame_count *
        FEATURE_V3_SLOT_DIM
    );


    result.right.resize(
        frame_count *
        FEATURE_V3_SLOT_DIM
    );


    for (
        std::size_t frame = 0;
        frame < frame_count;
        ++frame
    ) {
        const Point2f& left_wrist =
            left_sequence[
                frame
            ].points[0];

        const Point2f& right_wrist =
            right_sequence[
                frame
            ].points[0];


        const double midpoint_x =
            (
                static_cast<double>(
                    left_wrist.x
                )
                +
                static_cast<double>(
                    right_wrist.x
                )
            )
            /
            2.0;


        const double midpoint_y =
            (
                static_cast<double>(
                    left_wrist.y
                )
                +
                static_cast<double>(
                    right_wrist.y
                )
            )
            /
            2.0;


        for (
            std::size_t landmark = 0;
            landmark < HAND_LANDMARK_COUNT;
            ++landmark
        ) {
            const Point2f& left_point =
                left_sequence[
                    frame
                ].points[
                    landmark
                ];


            const Point2f& right_point =
                right_sequence[
                    frame
                ].points[
                    landmark
                ];


            const std::size_t offset =
                frame *
                FEATURE_V3_SLOT_DIM
                +
                landmark * 2;


            result.left[
                offset
            ] =
                (
                    static_cast<double>(
                        left_point.x
                    )
                    -
                    midpoint_x
                )
                /
                scale;


            result.left[
                offset + 1
            ] =
                (
                    static_cast<double>(
                        left_point.y
                    )
                    -
                    midpoint_y
                )
                /
                scale;


            result.right[
                offset
            ] =
                (
                    static_cast<double>(
                        right_point.x
                    )
                    -
                    midpoint_x
                )
                /
                scale;


            result.right[
                offset + 1
            ] =
                (
                    static_cast<double>(
                        right_point.y
                    )
                    -
                    midpoint_y
                )
                /
                scale;
        }
    }


    return result;
}


// ============================================================
// Normalized trajectory
// ============================================================

TrajectoryResult makeNormalizedTrajectory(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence,
    const HandUsage& usage,
    std::size_t anchor_frame_count,
    CanonicalHand canonical_hand
) {
    validateSameFrameCount(
        left_sequence,
        right_sequence
    );


    const std::size_t frame_count =
        getFrameCount(
            left_sequence,
            right_sequence
        );


    TrajectoryResult result;


    result.trajectory.assign(
        frame_count * 2,
        0.0f
    );


    result.scale =
        1.0;


    if (frame_count == 0) {
        return result;
    }


    if (
        usage.type ==
        UsageType::Invalid
    ) {
        return result;
    }


    std::vector<double> reference(
        frame_count * 2
    );


    // ========================================================
    // One-hand active wrist
    // ========================================================

    if (
        usage.type ==
        UsageType::OneHand
    ) {
        const HandSequence* active_sequence =
            nullptr;


        if (
            usage.active_hand ==
            ActiveHand::Left
        ) {
            if (left_sequence == nullptr) {
                throw std::runtime_error(
                    "LEFT active but left sequence missing"
                );
            }

            active_sequence =
                left_sequence;
        }
        else if (
            usage.active_hand ==
            ActiveHand::Right
        ) {
            if (right_sequence == nullptr) {
                throw std::runtime_error(
                    "RIGHT active but right sequence missing"
                );
            }

            active_sequence =
                right_sequence;
        }
        else {
            throw std::runtime_error(
                "One-hand active hand invalid"
            );
        }


        for (
            std::size_t frame = 0;
            frame < frame_count;
            ++frame
        ) {
            const Point2f& wrist =
                (*active_sequence)[
                    frame
                ].points[0];


            reference[
                frame * 2
            ] =
                static_cast<double>(
                    wrist.x
                );


            reference[
                frame * 2 + 1
            ] =
                static_cast<double>(
                    wrist.y
                );
        }
    }


    // ========================================================
    // Two-hand wrist midpoint
    // ========================================================

    else if (
        usage.type ==
        UsageType::TwoHand
    ) {
        if (
            left_sequence == nullptr
            ||
            right_sequence == nullptr
        ) {
            throw std::runtime_error(
                "Two-hand trajectory requires both sequences"
            );
        }


        for (
            std::size_t frame = 0;
            frame < frame_count;
            ++frame
        ) {
            const Point2f& left_wrist =
                (*left_sequence)[
                    frame
                ].points[0];

            const Point2f& right_wrist =
                (*right_sequence)[
                    frame
                ].points[0];


            reference[
                frame * 2
            ] =
                (
                    static_cast<double>(
                        left_wrist.x
                    )
                    +
                    static_cast<double>(
                        right_wrist.x
                    )
                )
                /
                2.0;


            reference[
                frame * 2 + 1
            ] =
                (
                    static_cast<double>(
                        left_wrist.y
                    )
                    +
                    static_cast<double>(
                        right_wrist.y
                    )
                )
                /
                2.0;
        }
    }
    else {
        throw std::runtime_error(
            "Unknown usage type"
        );
    }


    // ========================================================
    // Anchor
    //
    // count =
    // min(max(anchor_frame_count, 1), len(reference))
    // ========================================================

    const std::size_t count =
        std::min(
            std::max<std::size_t>(
                anchor_frame_count,
                1
            ),
            frame_count
        );


    std::vector<double> anchor_x_values;
    std::vector<double> anchor_y_values;


    anchor_x_values.reserve(count);
    anchor_y_values.reserve(count);


    for (
        std::size_t frame = 0;
        frame < count;
        ++frame
    ) {
        anchor_x_values.push_back(
            reference[
                frame * 2
            ]
        );

        anchor_y_values.push_back(
            reference[
                frame * 2 + 1
            ]
        );
    }


    const double anchor_x =
        median(
            anchor_x_values
        );

    const double anchor_y =
        median(
            anchor_y_values
        );


    // ========================================================
    // Centered + radial distance
    // ========================================================

    std::vector<double> centered(
        frame_count * 2
    );

    std::vector<double> radial_distance;

    radial_distance.reserve(
        frame_count
    );


    for (
        std::size_t frame = 0;
        frame < frame_count;
        ++frame
    ) {
        const double x =
            reference[
                frame * 2
            ]
            -
            anchor_x;

        const double y =
            reference[
                frame * 2 + 1
            ]
            -
            anchor_y;


        centered[
            frame * 2
        ] =
            x;

        centered[
            frame * 2 + 1
        ] =
            y;


        radial_distance.push_back(
            std::sqrt(
                x * x +
                y * y
            )
        );
    }


    // ========================================================
    // p95 scale
    // ========================================================

    double trajectory_scale =
        percentile(
            radial_distance,
            95.0
        );


    if (
        !std::isfinite(
            trajectory_scale
        )
        ||
        trajectory_scale <=
        FEATURE_V3_EPS
    ) {
        trajectory_scale =
            1.0;
    }


    result.scale =
        trajectory_scale;


    // ========================================================
    // Normalize
    // ========================================================

    for (
        std::size_t frame = 0;
        frame < frame_count;
        ++frame
    ) {
        double x =
            centered[
                frame * 2
            ]
            /
            trajectory_scale;

        const double y =
            centered[
                frame * 2 + 1
            ]
            /
            trajectory_scale;


        // ====================================================
        // One-hand handedness canonicalization
        // ====================================================

        if (
            usage.type ==
            UsageType::OneHand
        ) {
            if (
                !activeMatchesCanonical(
                    usage.active_hand,
                    canonical_hand
                )
            ) {
                x *= -1.0;
            }
        }


        result.trajectory[
            frame * 2
        ] =
            static_cast<float>(
                x
            );


        result.trajectory[
            frame * 2 + 1
        ] =
            static_cast<float>(
                y
            );
    }


    return result;
}


// ============================================================
// Feature V3
// ============================================================

FeatureV3Result buildHandFeaturesV3(
    const HandSequence* left_sequence,
    const HandSequence* right_sequence,
    const FeatureV3Options& options
) {
    validateSameFrameCount(
        left_sequence,
        right_sequence
    );


    const std::size_t frame_count =
        getFrameCount(
            left_sequence,
            right_sequence
        );


    if (frame_count == 0) {
        throw std::runtime_error(
            "Empty hand sequence"
        );
    }


    FeatureV3Result result;


    result.frame_count =
        frame_count;


    result.canonical_hand =
        options.canonical_hand;


    // ========================================================
    // Usage
    // ========================================================

    result.usage =
        detectHandUsage(
            left_sequence,
            right_sequence,
            options.one_hand_ratio_threshold,
            options.no_motion_threshold
        );


    // ========================================================
    // Invalid
    // ========================================================

    if (
        result.usage.type ==
        UsageType::Invalid
    ) {
        result.valid =
            false;

        return result;
    }


    // ========================================================
    // Physical local
    // ========================================================

    std::vector<double> physical_left_local;
    std::vector<double> physical_right_local;


    if (
        left_sequence != nullptr
        &&
        !isMissingSequence(
            left_sequence
        )
    ) {
        physical_left_local =
            makeLocalHand(
                *left_sequence
            );
    }
    else {
        physical_left_local =
            makeZeroLocal(
                frame_count
            );
    }


    if (
        right_sequence != nullptr
        &&
        !isMissingSequence(
            right_sequence
        )
    ) {
        physical_right_local =
            makeLocalHand(
                *right_sequence
            );
    }
    else {
        physical_right_local =
            makeZeroLocal(
                frame_count
            );
    }


    // ========================================================
    // Model blocks
    // ========================================================

    std::vector<double> slot_a_local;
    std::vector<double> slot_b_local;

    std::vector<double> pair_a;
    std::vector<double> pair_b;


    // ========================================================
    // One-hand
    // ========================================================

    if (
        result.usage.type ==
        UsageType::OneHand
    ) {
        const std::vector<double>* active_local =
            nullptr;


        if (
            result.usage.active_hand ==
            ActiveHand::Left
        ) {
            active_local =
                &physical_left_local;
        }
        else if (
            result.usage.active_hand ==
            ActiveHand::Right
        ) {
            active_local =
                &physical_right_local;
        }
        else {
            throw std::runtime_error(
                "One-hand active hand invalid"
            );
        }


        slot_a_local =
            canonicalizeOneHandLocal(
                *active_local,
                frame_count,
                result.usage.active_hand,
                options.canonical_hand
            );


        slot_b_local =
            makeZeroLocal(
                frame_count
            );


        pair_a =
            makeZeroLocal(
                frame_count
            );


        pair_b =
            makeZeroLocal(
                frame_count
            );


        result.canonicalized =
            !activeMatchesCanonical(
                result.usage.active_hand,
                options.canonical_hand
            );
    }


    // ========================================================
    // Two-hand
    // ========================================================

    else if (
        result.usage.type ==
        UsageType::TwoHand
    ) {
        if (
            left_sequence == nullptr
            ||
            right_sequence == nullptr
        ) {
            throw std::runtime_error(
                "Two-hand feature requires both sequences"
            );
        }


        slot_a_local =
            physical_left_local;


        slot_b_local =
            physical_right_local;


        const PairRelativeResult pair =
            makePairRelativeFeatures(
                *left_sequence,
                *right_sequence
            );


        pair_a =
            pair.left;


        pair_b =
            pair.right;


        result.canonicalized =
            false;
    }
    else {
        throw std::runtime_error(
            "Unknown usage type"
        );
    }


    // ========================================================
    // Trajectory
    // ========================================================

    const TrajectoryResult trajectory_result =
        makeNormalizedTrajectory(
            left_sequence,
            right_sequence,
            result.usage,
            options.anchor_frame_count,
            options.canonical_hand
        );


    // ========================================================
    // Final Feature V3 [T,172]
    // ========================================================

    result.features.assign(
        frame_count *
        FEATURE_V3_DIM,
        0.0f
    );


    for (
        std::size_t frame = 0;
        frame < frame_count;
        ++frame
    ) {
        const std::size_t output_row =
            frame *
            FEATURE_V3_DIM;


        const std::size_t local_row =
            frame *
            FEATURE_V3_SLOT_DIM;


        // ----------------------------------------------------
        // 0:42 SLOT A
        // ----------------------------------------------------

        for (
            std::size_t i = 0;
            i < FEATURE_V3_SLOT_DIM;
            ++i
        ) {
            result.features[
                output_row +
                i
            ] =
                static_cast<float>(
                    slot_a_local[
                        local_row + i
                    ]
                );
        }


        // ----------------------------------------------------
        // 42:84 SLOT B
        // ----------------------------------------------------

        for (
            std::size_t i = 0;
            i < FEATURE_V3_SLOT_DIM;
            ++i
        ) {
            result.features[
                output_row +
                42 +
                i
            ] =
                static_cast<float>(
                    slot_b_local[
                        local_row + i
                    ]
                );
        }


        // ----------------------------------------------------
        // 84:126 Pair A
        // ----------------------------------------------------

        for (
            std::size_t i = 0;
            i < FEATURE_V3_SLOT_DIM;
            ++i
        ) {
            result.features[
                output_row +
                84 +
                i
            ] =
                static_cast<float>(
                    pair_a[
                        local_row + i
                    ]
                );
        }


        // ----------------------------------------------------
        // 126:168 Pair B
        // ----------------------------------------------------

        for (
            std::size_t i = 0;
            i < FEATURE_V3_SLOT_DIM;
            ++i
        ) {
            result.features[
                output_row +
                126 +
                i
            ] =
                static_cast<float>(
                    pair_b[
                        local_row + i
                    ]
                );
        }


        // ----------------------------------------------------
        // 168:170 trajectory
        // ----------------------------------------------------

        result.features[
            output_row +
            168
        ] =
            trajectory_result.trajectory[
                frame * 2
            ];


        result.features[
            output_row +
            169
        ] =
            trajectory_result.trajectory[
                frame * 2 + 1
            ];


        // ----------------------------------------------------
        // 170:172 usage mask
        // ----------------------------------------------------

        result.features[
            output_row +
            170
        ] =
            result.usage.usage_mask[0];


        result.features[
            output_row +
            171
        ] =
            result.usage.usage_mask[1];
    }


    // ========================================================
    // Finite validation
    // ========================================================

    for (
        const float value :
        result.features
    ) {
        if (
            !std::isfinite(
                static_cast<double>(
                    value
                )
            )
        ) {
            throw std::runtime_error(
                "Feature V3 contains NaN or Inf"
            );
        }
    }


    // ========================================================
    // Debug blocks
    // ========================================================

    result.slot_a_local =
        toFloatVector(
            slot_a_local
        );


    result.slot_b_local =
        toFloatVector(
            slot_b_local
        );


    result.pair_a =
        toFloatVector(
            pair_a
        );


    result.pair_b =
        toFloatVector(
            pair_b
        );


    result.trajectory =
        trajectory_result.trajectory;


    result.trajectory_scale =
        trajectory_result.scale;


    result.physical_left_local =
        toFloatVector(
            physical_left_local
        );


    result.physical_right_local =
        toFloatVector(
            physical_right_local
        );


    result.valid =
        true;


    return result;
}


}  // namespace sign_engine