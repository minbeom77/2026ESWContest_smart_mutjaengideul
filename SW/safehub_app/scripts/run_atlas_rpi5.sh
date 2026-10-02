#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."

flutter="/opt/flutter-elinux-atlas/flutter/bin/flutter"
atlas="/opt/flutter-elinux-atlas/bin/flutter-atlas"

for executable in "$flutter" "$atlas"; do
  if [[ ! -x "$executable" ]]; then
    printf '실행 도구를 찾을 수 없습니다: %s\nAtlas 개발 컨테이너에서 실행하세요.\n' "$executable" >&2
    exit 1
  fi
done

mqtt_broker="${MQTT_BROKER:-192.168.0.38}"
mqtt_port="${MQTT_PORT:-1883}"
camera_host="${CAMERA_HOST:-192.168.0.5}"
camera_port="${CAMERA_PORT:-5000}"
stt_url="${STT_SERVER_URL:-http://192.168.0.38:8000}"
tts_url="${TTS_SERVER_URL:-http://192.168.0.38:8000}"
disaster_url="${DISASTER_API_URL:-https://www.safetydata.go.kr/V2/api/DSSP-IF-00247}"

read -r -s -p "DISASTER API KEY: " api_key
printf '\n'
trap 'unset api_key' EXIT

if [[ -z "$api_key" ]]; then
  printf 'API 키가 비어 있습니다.\n' >&2
  exit 1
fi

printf 'MQTT: %s:%s\n카메라: %s:%s\nSTT: %s\nTTS: %s\n' \
  "$mqtt_broker" "$mqtt_port" "$camera_host" "$camera_port" \
  "$stt_url" "$tts_url"

# CLEAN_BUILD=1일 때만 기존 빌드 결과를 정리한다.
if [[ "${CLEAN_BUILD:-0}" == "1" ]]; then
  "$flutter" clean
fi

"$flutter" pub get

"$atlas" run \
  -d atlas_rpi5 \
  --release \
  --dart-define="MQTT_BROKER=$mqtt_broker" \
  --dart-define="MQTT_PORT=$mqtt_port" \
  --dart-define="CAMERA_HOST=$camera_host" \
  --dart-define="CAMERA_PORT=$camera_port" \
  --dart-define="DISASTER_API_URL=$disaster_url" \
  --dart-define="DISASTER_API_KEY=$api_key" \
  --dart-define="STT_SERVER_URL=$stt_url" \
  --dart-define="TTS_SERVER_URL=$tts_url"
