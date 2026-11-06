#!/usr/bin/env sh
# ---
# title: 02_install_plugins
# description: 선택한 언어마다 asdf 플러그인을 추가하는 설치 2단계 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Adds the asdf plugin for each selected language. Ensures asdf/shims are on
# PATH itself — does not rely on phase 01 having exported anything into
# this process, since main.sh runs every phase as its own child process.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"
# See lib.sh: exports ASDF_DATA_DIR and prepends its shims dir to PATH for
# THIS process, since nothing upstream is guaranteed to have done it yet.
ensure_asdf_on_path

REPO_ROOT="$(repo_root_from "$0")"
readonly REPO_ROOT
# TOOL_VERSIONS_FILE is set by main.sh to whatever 00_select.sh produced
# (the user's picks); fall back to the repo's own .tool-versions when this
# script is run standalone, outside the normal orchestrated flow.
readonly CONFIG_FILE="${TOOL_VERSIONS_FILE:-$REPO_ROOT/.tool-versions}"
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

step "Phase 2: Installing asdf plugins"

# LT_PLUGIN_TIMEOUT (TASK-145.4): wall-clock timeout, in seconds, for each
# `asdf plugin add`/`asdf plugin update --all` call below. Both shell out
# to `git clone`/`git fetch` internally with no timeout of their own -
# exposed to the same DNS/TCP/TLS-handshake blackhole
# lt_run_with_timeout() (TASK-138.1) exists to close, and without it a
# single stuck plugin repo would hang forever instead of letting retry
# (TASK-88) actually get its intended extra attempts. Its own budget, not
# LT_VERSION_FETCH_TIMEOUT (lib.sh, tuned for a few hundred bytes of
# JSON) - a plugin's git clone is a much bigger call. Override-able like
# LT_VERSION_FETCH_TIMEOUT, so not readonly.
LT_PLUGIN_TIMEOUT="${LT_PLUGIN_TIMEOUT:-30}"  # ---- 1

# Refresh every already-installed plugin's own git checkout. retry
# (TASK-88): worth a couple of attempts before giving up on a network blip.
# `|| true`: a stale/unreachable plugin repo shouldn't abort the whole
# install even after retries are exhausted.
retry 3 5 run lt_run_with_timeout "$LT_PLUGIN_TIMEOUT" \
  asdf plugin update --all || true  # ---- 2

# Capture once, up front, instead of piping straight into `grep -q` inside
# the loop: grep -q closes the pipe as soon as it matches, which can
# SIGPIPE `asdf` mid-write and make the pipeline report failure even
# though grep found what it was looking for — intermittently misreporting
# an installed plugin as missing. A plain variable has no pipe to race.
# (`|| true`: an empty plugin list, e.g. right after installing asdf for
# the first time, is not an error.)
existing_plugins="$(asdf plugin list 2>/dev/null || true)"

# fd 3, not stdin: keeps this loop's own `read` isolated from anything a
# future edit to the loop body might do with stdin. POSIX sh has no
# process substitution, so each_tool's output goes to a temp file first.
# FAILED (TASK-89): collects plugins that failed to add instead of dying
# immediately on the first one — mirrors uninstall/02_remove_plugins.sh's
# own `|| true` per-item pattern, so one unreachable plugin repo doesn't
# stop every OTHER selected language from even being attempted. Checked
# once after the loop, not per-iteration, so every language gets a shot
# before this script decides whether to fail overall.
FAILED=""
EACH_TOOL_TMP="$(mktemp)"
readonly EACH_TOOL_TMP
each_tool "$CONFIG_FILE" > "$EACH_TOOL_TMP"
while read -r plugin version <&3; do  # ---- 3
  # -x: exact whole-line match, so "python" doesn't accidentally match a
  # plugin named e.g. "python-build".
  if printf '%s\n' "$existing_plugins" | grep -qx "$plugin"; then  # ---- 4
    log "Plugin already present: $plugin"
  else
    log "Adding plugin: $plugin"
    if retry 3 5 run lt_run_with_timeout "$LT_PLUGIN_TIMEOUT" \
      asdf plugin add "$plugin"; then
      lt_report installed "asdf plugin: $plugin"
    else
      log "  FAILED: $plugin (continuing with remaining languages)"
      FAILED="${FAILED}${FAILED:+ }$plugin"  # ---- 5
    fi
  fi
done 3< "$EACH_TOOL_TMP"
rm -f "$EACH_TOOL_TMP"

[ -z "$FAILED" ] || die "Failed to add plugin(s): $FAILED"

# ======== 노트 ========
# 1 플러그인 git 호출 타임아웃
#   설명: asdf plugin add/update는 내부에서 git clone/fetch를 하고 자체 시간 제한이 없다. 멈춘 저장소 하나가 전체를 막지 않도록 벽시계 상한을 둔다.
#   관련: TASK-145.4, lt_run_with_timeout (scripts/lib.sh)
# 2 플러그인 갱신 실패는 무시
#   설명: 오래됐거나 닿지 않는 플러그인 저장소 때문에 전체 설치를 중단하지 않는다.
#   관련: TASK-88
# 3 fd 3으로 읽는 루프
#   설명: 루프 본문이 stdin을 쓰더라도 read가 영향을 받지 않도록 fd 3에서 읽는다. POSIX sh에는 프로세스 치환이 없어 each_tool 출력을 임시 파일에 먼저 담는다.
# 4 플러그인 존재 여부는 줄 전체 일치로 판정
#   설명: python이 python-build 같은 접두사 일치에 속아 설치된 것으로 오판하지 않게 -x를 쓴다.
#   관련: spec/install_plugins_spec.sh
# 5 실패를 모아 두고 끝에서 판정
#   설명: 플러그인 하나가 실패해도 나머지 언어는 계속 시도한다. 루프 뒤 한 번만 die로 전체 실패를 알린다.
#   관련: TASK-89
