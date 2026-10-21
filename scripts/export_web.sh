#!/usr/bin/env bash
# Godot Web export. 게이트가 낡은 산출물을 재지 않도록 항상 여기서 만든다.
#
# cold export 는 importer 를 돌리지 않아 한국어 폰트와 텍스처가 조용히 pck 에서
# 빠진다(lizard-tycoon 선례). 그래서 export 전에 import 를 먼저 완주시킨다.
set -euo pipefail

project_dir="${1:-.}"
out_dir="${project_dir}/build/web"
godot_bin="${GODOT_BIN:-godot}"

file_size() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

command -v "${godot_bin}" >/dev/null 2>&1 || {
  echo "[export-web] Godot 을 찾지 못했다: ${godot_bin}" >&2; exit 1; }

# 산출물이 소스와 어긋나지 않게 통째로 지운다.
rm -rf "${out_dir}"
mkdir -p "${out_dir}"

log_dir="${project_dir}/build/qa/web-export-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "${log_dir}"
runner="$(dirname "$0")/run_godot.py"
python3 "$runner" --log "${log_dir}/import.log" -- "${godot_bin}" --headless --path "${project_dir}" --import --quit
python3 "$runner" --log "${log_dir}/export.log" -- "${godot_bin}" --headless --path "${project_dir}" --export-release Web "build/web/index.html"

[ -s "${out_dir}/index.pck" ] || { echo "[export-web] index.pck 이 없다" >&2; exit 1; }
[ -s "${out_dir}/index.wasm" ] || { echo "[export-web] index.wasm 이 없다" >&2; exit 1; }

printf "[export-web] 완료 · pck %d KB · wasm %d KB\n" \
  $(( $(file_size "${out_dir}/index.pck") / 1024 )) \
  $(( $(file_size "${out_dir}/index.wasm") / 1024 )) >&2
