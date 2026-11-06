#!/usr/bin/env sh
# ---
# title: 06_set_globals
# description: 선택한 언어별 버전을 전역 또는 로컬로 고정하고 shim을 재생성하는 설치 6단계 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Binds each selected language to a version and regenerates shims.
# Self-sufficient: ensures asdf is on PATH itself.
#
# Scope (global vs local) comes from the "# scope: ..." line 00_select.sh
# may have written as the first line of the selection file — see
# read_scope() in lib.sh. A config file with no such line (e.g. this
# repo's own .tool-versions, used when running this phase standalone)
# defaults to global, matching the tool's original behavior.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"
ensure_asdf_on_path

REPO_ROOT="$(repo_root_from "$0")"
readonly REPO_ROOT
readonly CONFIG_FILE="${TOOL_VERSIONS_FILE:-$REPO_ROOT/.tool-versions}"
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

step "Phase 6: Setting versions"

SCOPE_INFO="$(read_scope "$CONFIG_FILE")"  # ---- 1
readonly SCOPE_INFO

# POSIX sh has no process substitution, so each_tool's output goes to a
# temp file first — both branches below read from the same one.
EACH_TOOL_TMP="$(mktemp)"
readonly EACH_TOOL_TMP
each_tool "$CONFIG_FILE" > "$EACH_TOOL_TMP"

case "$SCOPE_INFO" in
  local:*)
    readonly TARGET_DIR="${SCOPE_INFO#local:}"
    log "Pinning versions locally in: $TARGET_DIR"
    # fd 3, not stdin — see 02_install_plugins.sh for why.
    while read -r plugin version <&3; do
      log "Setting local $plugin -> $version"
      # Plain `asdf set` (no -u) writes/updates <TARGET_DIR>/.tool-versions
      # instead of the global ~/.tool-versions — subshell so the `cd` here
      # never affects this script's own cwd.
      ( cd "$TARGET_DIR" && run asdf set "$plugin" "$version" )  # ---- 2
      lt_report modified \
        "$plugin -> $version (local, $TARGET_DIR/.tool-versions)"
    done 3< "$EACH_TOOL_TMP"
    # Record this directory (TASK-83) so uninstall/01_uninstall_runtimes.sh
    # can find it later and asdf-uninstall whatever got pinned here — the
    # global ~/.tool-versions never mentions a local-only version, so
    # without this record uninstall has no way to know it exists. Skipped
    # under DRY_RUN: the `run asdf set` calls above didn't really pin
    # anything, so recording the directory here would be a false record.
    # `grep -qxF` dedupes: installing into the same directory twice must
    # not grow this file forever.
    if [ "$DRY_RUN" != "true" ]; then
      readonly LOCAL_PINS_FILE="$ASDF_DATA_DIR/$LT_LOCAL_PINS_FILE_NAME"
      grep -qxF "$TARGET_DIR" "$LOCAL_PINS_FILE" 2>/dev/null \
        || printf '%s\n' "$TARGET_DIR" >> "$LOCAL_PINS_FILE"  # ---- 3
    fi
    ;;
  *)
    # fd 3, not stdin — see 02_install_plugins.sh for why.
    while read -r plugin version <&3; do
      log "Setting global $plugin -> $version"
      # `-u` = user/global scope: writes/updates the plugin's line in
      # $HOME/.tool-versions (NOT this repo's own .tool-versions), so the
      # chosen version applies everywhere on the machine, not just this
      # repo directory.
      run asdf set -u "$plugin" "$version"  # ---- 4
      lt_report modified "$plugin -> $version (global, ~/.tool-versions)"
    done 3< "$EACH_TOOL_TMP"
    ;;
esac
rm -f "$EACH_TOOL_TMP"

# Regenerates every shim under $ASDF_DATA_DIR/shims (node, python, ...).
# Scope-independent: shims are generic dispatchers that resolve the active
# version at invocation time, not something baked in at reshim time.
run asdf reshim  # ---- 5

# ======== 노트 ========
# 1 스코프는 선택 파일 첫 줄에서 읽는다
#   설명: 00_select.sh가 첫 줄에 "# scope: ..."를 쓸 수 있다. 없으면 전역으로 동작해 단독 실행도 원래 동작과 같다.
#   관련: read_scope (scripts/lib.sh)
# 2 로컬 고정은 대상 디렉터리에서 서브셸로
#   설명: asdf set은 현재 디렉터리의 .tool-versions를 바꾸므로 cd를 서브셸에 가둬 호출자 위치를 보존한다.
# 3 로컬 핀 디렉터리 기록(중복 방지)
#   설명: 전역 ~/.tool-versions에는 로컬 전용 버전이 드러나지 않아, 제거가 찾을 수 있게 디렉터리를 기록한다. grep -qxF로 같은 디렉터리를 두 번 쓰지 않으며, dry-run에서는 기록하지 않는다.
#   관련: TASK-83, scripts/uninstall/01_uninstall_runtimes.sh
# 4 전역 고정
#   설명: 전역 스코프는 -u(사용자 홈의 .tool-versions)로 설정한다.
# 5 shim 재생성
#   설명: 모든 고정이 끝난 뒤 한 번만 shim을 다시 만들어 새 버전이 PATH에서 바로 보이게 한다.
