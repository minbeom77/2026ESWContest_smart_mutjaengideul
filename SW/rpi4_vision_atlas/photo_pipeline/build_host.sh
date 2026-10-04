#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ort_root="${ORT_ROOT:-/app/onnxruntime-host-1.29.0}"
opencv_prefix="${OPENCV_PREFIX:-/usr}"
mkdir -p "$project_dir/build"
g++ -std=c++17 -O2 -ffp-contract=off -Wall -Wextra -pedantic \
  -I"$ort_root/include" -I"$opencv_prefix/include/opencv4" \
  "$project_dir/vision_photo.cpp" \
  -L"$ort_root/lib" -Wl,-rpath,"$ort_root/lib" \
  -L"$opencv_prefix/lib/x86_64-linux-gnu" \
  -Wl,-rpath,"$opencv_prefix/lib/x86_64-linux-gnu" \
  -lonnxruntime -lopencv_imgcodecs -lopencv_imgproc -lopencv_core \
  -o "$project_dir/build/vision_photo"
printf 'Built: %s\n' "$project_dir/build/vision_photo"
