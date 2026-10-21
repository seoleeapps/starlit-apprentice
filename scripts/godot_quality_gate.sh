#!/usr/bin/env bash
set -euo pipefail
project="."
smoke_scene=""
godot_bin="${GODOT_BIN:-godot}"
run_import=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) project="${2:?missing project}"; shift 2 ;;
    --smoke-scene) smoke_scene="${2:?missing smoke scene}"; shift 2 ;;
    --godot-bin) godot_bin="${2:?missing godot binary}"; shift 2 ;;
    --skip-import) run_import=0; shift ;;
    -h|--help)
      echo 'godot_quality_gate.sh [--project PATH] [--smoke-scene RES://SCENE] [--godot-bin PATH] [--skip-import]'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_dir="${GODOT_QUALITY_GATE_LOG_DIR:-${project}/build/qa/quality-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "${log_dir}"
run_check() {
  local label="$1"; shift
  python3 "${script_dir}/run_godot.py" --log "${log_dir}/${label}.log" -- "$@"
}
if [ "${run_import}" -eq 1 ]; then
  # 첫 import의 오류도 즉시 실패시킨다. 예열로 오류를 숨기지 않는다.
  run_check import "${godot_bin}" --headless --path "${project}" --import --quit
fi
run_check compile "${godot_bin}" --headless --path "${project}" --quit
if [ -n "${smoke_scene}" ]; then
  run_check smoke "${godot_bin}" --headless --path "${project}" "${smoke_scene}"
fi
