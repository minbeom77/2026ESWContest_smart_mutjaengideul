#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/vision_photo_rpi4"
FIXTURE="$ROOT/fixture"
MODELS="$ROOT/models"
OUTPUT="${1:-$ROOT/result_$(date +%Y%m%d_%H%M%S)}"

echo "Architecture: $(uname -m)"
[[ "$(uname -m)" == "aarch64" ]] || {
    echo "ERROR: ARM64 RPi4에서 실행해야 합니다."
    exit 1
}

for path in \
    "$BIN" \
    "$FIXTURE/image_bgr_u8.bin" \
    "$FIXTURE/image_wh_i32.bin" \
    "$MODELS/palm_detection_mediapipe_2023feb.onnx" \
    "$MODELS/handpose_estimation_mediapipe_2023feb.onnx"
do
    [[ -e "$path" ]] || {
        echo "ERROR: missing $path"
        exit 1
    }
done

echo "Checking shared libraries..."
if ldd "$BIN" | grep -q "not found"; then
    ldd "$BIN"
    echo "ERROR: 필요한 공유 라이브러리가 없습니다."
    exit 1
fi

ldd "$BIN"
chmod +x "$BIN"
"$BIN" "$FIXTURE" "$MODELS" "$OUTPUT"

echo "SUCCESS: $OUTPUT"
