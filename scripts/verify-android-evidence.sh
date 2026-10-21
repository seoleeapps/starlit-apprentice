#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
authority="${SEORI_DEVELOPMENT_AUTHORITY_DIR:-$repo_root/.seorilabs-release-authority}"
verifier="$authority/scripts/release/verify-development-evidence.mjs"
[ -f "$verifier" ] || {
  echo "[android-build] 최신 seorilabs/.github checkout과 중앙 검증기가 필요하다." >&2
  exit 1
}
remote_url="$(git -C "$authority" remote get-url origin)"
case "$remote_url" in
  https://github.com/seorilabs/.github|https://github.com/seorilabs/.github.git|git@github.com:seorilabs/.github.git) ;;
  *) echo "[android-build] 중앙 정본 remote가 다르다." >&2; exit 1 ;;
esac
[ -z "$(git -C "$authority" status --porcelain --untracked-files=no)" ] || {
  echo "[android-build] 중앙 정본에 미커밋 변경이 있다." >&2
  exit 1
}
authority_sha="$(git -C "$authority" rev-parse HEAD)"
latest_sha="$(git -C "$authority" ls-remote origin refs/heads/main | cut -f1)"
[ -n "$latest_sha" ] && [ "$authority_sha" = "$latest_sha" ] || {
  echo "[android-build] 중앙 정본이 최신 main과 다르다." >&2
  exit 1
}
candidate="${SEORI_SOURCE_SHA:-$(git rev-parse HEAD)}"
args=(--repo seoleeapps/starlit-apprentice --sha "$candidate" --target google-play --phase before-build)
if [ -n "${SEORI_DEVELOPMENT_EVIDENCE_FILE:-}" ]; then
  args+=(--file "$SEORI_DEVELOPMENT_EVIDENCE_FILE")
elif [ -n "${SEORI_RELEASE_TAG:-}" ]; then
  args+=(--tag "$SEORI_RELEASE_TAG")
fi
node "$verifier" "${args[@]}"
