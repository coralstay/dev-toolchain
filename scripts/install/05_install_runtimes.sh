#!/usr/bin/env sh
# ---
# title: 05_install_runtimes
# description: 선택한 언어 런타임을 asdf로 설치하고 일부 실패도 격리하는 설치 5단계 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# The slow part: compiles/installs each selected language runtime via asdf.
# Ensures asdf/shims + build flags itself instead of trusting phase 04's rc
# file edits to already be sourced into this process.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"
# `asdf install` needs `asdf` itself on PATH ...
ensure_asdf_on_path
# ... and Python specifically needs these to find OpenSSL/SQLite/zlib
# while compiling — phase 04 wrote them into the rc file for *future*
# shells, but this process needs them right now.
ensure_build_flags  # ---- 1

REPO_ROOT="$(repo_root_from "$0")"
readonly REPO_ROOT
readonly CONFIG_FILE="${TOOL_VERSIONS_FILE:-$REPO_ROOT/.tool-versions}"
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

step "Phase 5: Installing language runtimes (this can take a while)"

# fd 3, not stdin — see 02_install_plugins.sh for why. POSIX sh has no
# process substitution, so each_tool's output goes to a temp file first.
# FAILED (TASK-89): collects languages that failed to install instead of
# dying immediately on the first one, so one bad build doesn't stop every
# OTHER selected language from even being attempted — mirrors
# uninstall/01_uninstall_runtimes.sh's own `|| true` per-item pattern.
# Checked once after the loop: if anything failed, this phase itself must
# still fail (die() below) rather than let 06_set_globals.sh go on to
# `asdf set` a version that was never actually installed.
FAILED=""
EACH_TOOL_TMP="$(mktemp)"
readonly EACH_TOOL_TMP
each_tool "$CONFIG_FILE" > "$EACH_TOOL_TMP"
while read -r plugin version <&3; do
  log "Installing $plugin $version ..."
  # This is the actual compile/download step — by far the slowest part of
  # the whole installer. `run` still respects --dry-run. retry (TASK-88):
  # this is the single most network/time-intensive step in the whole
  # installer, so it's the one most worth retrying automatically.
  if retry 3 5 run asdf install "$plugin" "$version"; then  # ---- 2
    lt_report installed "$plugin $version (asdf)"
  else
    log "  FAILED: $plugin $version (continuing with remaining languages)"
    FAILED="${FAILED}${FAILED:+, }$plugin $version"  # ---- 3
  fi
done 3< "$EACH_TOOL_TMP"
rm -f "$EACH_TOOL_TMP"

[ -z "$FAILED" ] || die "One or more runtimes failed to install:" \
  "$FAILED. Re-run to retry just the missing ones" \
  "(asdf skips what's already installed)." \
  "If a failure keeps recurring, the asdf plugin may not support that" \
  "version yet (decision-12) - check with 'asdf list all <plugin>' and" \
  "pin an older version in .tool-versions if needed."  # ---- 4

# ======== 노트 ========
# 1 컴파일 직전에 빌드 플래그를 직접 준비
#   설명: 04단계가 쓴 rc 파일이 이 프로세스에 반영됐다고 믿지 않고 LDFLAGS 등을 여기서 export한다.
#   관련: ensure_build_flags (scripts/lib.sh)
# 2 런타임 설치(느린 컴파일 구간)
#   설명: 시간이 오래 걸리는 핵심 단계. 일시 오류만 재시도하고 실제 오류는 실패로 기록한다.
#   관련: TASK-88
# 3 부분 실패 격리
#   설명: 한 언어가 실패해도 다른 언어를 계속 시도한다. 루프 뒤 die로 phase 전체는 실패시켜 06단계가 설치되지 않은 버전을 고정하는 일을 막는다.
#   관련: TASK-89, spec/install_runtimes_spec.sh
# 4 실패한 phase는 반드시 비정상 종료
#   설명: 실패 메시지는 재실행 시 이미 설치된 것은 건너뜀을 안내하고, 플러그인이 해당 버전을 지원하지 않을 가능성을 알린다.
#   관련: decision-12
