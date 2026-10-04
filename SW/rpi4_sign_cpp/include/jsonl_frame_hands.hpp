#pragma once

#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>

#include "sign_types.hpp"

namespace sign_engine {

// Python reference:
//   SW/rpi4_vision_atlas/frame_hands_adapter.py
//
// C++ vision JSON/JSONL -> RecordingFrames 변환 중 입력 계약 위반을
// 나타내는 예외다.
class JsonlFrameHandsError : public std::runtime_error {
public:
    explicit JsonlFrameHandsError(const std::string& message)
        : std::runtime_error(message) {}
};

// JSON/JSONL -> RecordingFrames 변환 과정의 진단 정보.
// 실제 분류 입력은 frames이며, 이 구조체의 나머지 값들은
// Python adapter와의 parity 확인에 사용한다.
struct JsonlRecordingResult {
    RecordingFrames frames;

    std::size_t document_count = 0;
    std::size_t maximum_hands_per_frame = 0;

    bool has_sequence_signature = false;
    bool mirror_input = false;
    int image_width = 0;
    int image_height = 0;

    // recording 전체에서 모든 frame이 최대 한 손이었을 때
    // Python reference의 median-handedness stabilization이 적용된다.
    bool used_single_hand_stabilization = false;

    // stabilization이 실제로 적용되고 손 관측이 하나 이상 있었을 때만
    // has_median_handedness가 true다.
    bool has_median_handedness = false;
    double median_handedness_raw = 0.0;

    // "", "LEFT", "RIGHT" 중 하나.
    std::string stabilized_physical_hand;
};

// 하나 이상의 JSON 또는 JSONL 파일을 입력 순서대로 읽어
// Python frame_hands_adapter.py의 load_recording_frames()와 동일한
// RecordingFrames를 생성한다.
//
// 핵심 semantics:
//   - handedness_raw > 0.5  -> model RIGHT -> physical LEFT
//   - handedness_raw <= 0.5 -> model LEFT  -> physical RIGHT
//   - landmarks_xy는 pixel 좌표를 그대로 float32 Point2f에 저장
//   - single-hand recording은 전체 handedness_raw median으로 side 고정
//   - multi-hand recording은 physical slot별 최고 confidence 선택
//   - confidence tie는 먼저 등장한 detection 유지
//   - 손이 없는 frame은 최종 RecordingFrames에서 제외
//   - recording 도중 mirror_input/image_size_wh 변경은 오류
JsonlRecordingResult loadRecordingFramesFromJson(
    const std::vector<std::string>& json_or_jsonl_paths
);

}  // namespace sign_engine