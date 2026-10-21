#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="${PROJECT_DIR:-$(cd "${script_dir}/.." && pwd)}"
godot_bin="${GODOT_BIN:-godot}"
log_dir="${GODOT_TEST_LOG_DIR:-${project_dir}/build/qa/regression-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "${log_dir}"
run_godot() {
  local label="$1"; shift
  echo "[test-all] ${label}" >&2
  python3 "${script_dir}/run_godot.py" --log "${log_dir}/${label}.log" -- "$@"
}
python3 -m unittest discover -s "${script_dir}/tests" -p 'test_*.py' -v
run_godot import "${godot_bin}" --headless --path "${project_dir}" --import --quit
for runner in core_test endings_lint balance simulation localization rating_content native_ad_adapter test save_load audio layout_probe; do
  script="${runner}_runner"
  case "${runner}" in layout_probe) script="${runner}" ;; esac
  run_godot "${runner}" "${godot_bin}" --headless --path "${project_dir}" --resolution 720x1280 --script "res://tests/${script}.gd"
done
for locale in ko en; do
  run_godot "e2e-${locale}" "${godot_bin}" --headless --path "${project_dir}" --script res://tools/e2e/journey.gd -- --out "${log_dir}/e2e-${locale}" --locale "${locale}"
  python3 "${project_dir}/tools/e2e/check_e2e_coverage.py" --inventory "${project_dir}/docs/qa/feature-inventory.json" --journey "${log_dir}/e2e-${locale}/journey.json"
done
echo "[test-all] 전체 통과. 로그: ${log_dir}" >&2
