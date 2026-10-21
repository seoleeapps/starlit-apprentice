#!/usr/bin/env bash
set -euo pipefail

# version identity는 중앙 artifact authority가 먼저 검증한다.
# 이 검사는 SDK, target API, native alignment와 서명을 같은 파일에서 읽는다.
python3 tools/check_android_release.py \
  --aab "${AAB_PATH:?AAB_PATH required}" \
  --version-name "${ANDROID_VERSION_NAME:?ANDROID_VERSION_NAME required}" \
  --version-code "${ANDROID_VERSION_CODE:?ANDROID_VERSION_CODE required}" \
  --report build/android/release-inspection.json
