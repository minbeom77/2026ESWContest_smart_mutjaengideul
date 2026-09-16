#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$project_dir/build_host.sh"
"$project_dir/build/vision_photo" "${1:-/app/capture3.jpeg}" "${2:-/app/models}" "${3:-/app/vision_cpp_result_01}"
