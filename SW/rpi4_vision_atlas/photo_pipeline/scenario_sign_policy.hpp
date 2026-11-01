#pragma once

namespace vision_runtime {

// Keep the classifier's original IDs; other classes remain recognition references.
constexpr bool isScenarioSign(int class_id) {
    switch (class_id) {
    case 0:   // 에어컨
    case 5:   // 구조
    case 7:   // 아프다
    case 8:   // 괜찮다
    case 15:  // 쓰러지다
        return true;
    default:
        return false;
    }
}

}  // namespace vision_runtime

