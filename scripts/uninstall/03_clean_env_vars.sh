#!/usr/bin/env sh
# ---
# title: 03_clean_env_vars
# description: 설치 4단계가 rc 파일에 쓴 줄을 모두 찾아 지우는 제거 3단계 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Strips every line this tool's install phase (04_configure_shell_env.sh)
# may have added, from whichever rc files exist. Sweeps lib.sh's
# LT_KNOWN_RC_FILES (TASK-66) — all rc files this tool ever knows how to
# write into, not just the one detect_rc_file() would pick right now —
# since the install may have happened under a different shell than the one
# running uninstall.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"

step "Phase 3: Cleaning shell environment variables"

for rc_name in $LT_KNOWN_RC_FILES; do  # ---- 1
  rc="$HOME/$rc_name"
  [ -f "$rc" ] || continue   # nothing to clean if this rc file doesn't exist
  log "Cleaning $rc ..."
  if [ "$DRY_RUN" = "true" ]; then
    log "  + remove asdf/build-flag lines (sed -i.bak) from $rc"
    continue
  fi
  # macOS's BSD sed requires an explicit (even if empty) backup suffix
  # argument to -i; '.bak' also means we never destructively edit the rc
  # file without a recovery copy sitting right next to it.
  #
  # -E (extended regex): earlier versions of this script alternated
  # `\(zsh\|bash\)` for the java hook line, which is silently NOT
  # alternation on BSD sed (macOS's stock /usr/bin/sed) without -E — `\|`
  # is a GNU extension to POSIX basic regex. lt_env_var_defs()'s single
  # "set-java-home\." pattern below sidesteps that entirely (it matches
  # either variant without needing alternation), but -E is kept since nothing
  # here depends on BRE-specific behavior either.
  #
  # Each search pattern comes from lib.sh's lt_env_var_defs() (TASK-64) —
  # the same list install/04_configure_shell_env.sh writes from — instead
  # of an independently-typed copy here. `\#pattern#d` (not `/pattern/d`):
  # some patterns (e.g. "opt/sqlite/bin") contain literal `/`, and a custom
  # sed delimiter avoids having to escape those.
  #
  # POSIX sh has neither arrays nor process substitution. lt_env_var_defs()
  # goes to a temp file first; the -e/expression pairs accumulate one per
  # line in SED_ARGS (not space-joined) so a pattern containing a literal
  # space (e.g. "brew shellenv") still becomes exactly one sed argument —
  # `set --` below re-splits only on the newlines, never on the spaces
  # inside a line.
  ENV_DEFS_TMP="$(mktemp)"
  lt_env_var_defs > "$ENV_DEFS_TMP"  # ---- 2
  SED_ARGS=""
  while IFS= read -r def; do
    pattern="${def%%|||*}"
    SED_ARGS="${SED_ARGS}-e
\\#${pattern}#d
"
  done < "$ENV_DEFS_TMP"
  rm -f "$ENV_DEFS_TMP"
  IFS="
"
  # shellcheck disable=SC2086
  set -- $SED_ARGS
  unset IFS
  sed -E -i '.bak' "$@" "$rc"  # ---- 3
  log "  Backup preserved at ${rc}.bak"
  lt_report modified "$rc (removed asdf/build-flag lines, backup: ${rc}.bak)"
done

# ======== 노트 ========
# 1 알려진 rc 파일을 모두 훑는다
#   설명: 설치 때와 다른 쉘로 제거를 실행할 수 있으므로 지금 감지되는 하나가 아니라 이 도구가 쓸 수 있는 모든 rc 파일을 본다.
#   관련: TASK-66, LT_KNOWN_RC_FILES (scripts/lib.sh)
# 2 지울 패턴은 설치 쪽과 같은 정의에서
#   설명: 패턴을 따로 들고 있으면 설치와 어긋난다(TASK-56). 구분자 |||로 나뉜 첫 필드만 쓴다.
#   관련: TASK-56, TASK-64, scripts/lib.sh
#   개념: SSOT
# 3 BSD sed 호환 in-place 편집 + 백업
#   설명: macOS의 sed -i는 확장자 인자가 필수라서 '.bak'을 주며, 덕분에 항상 복구용 사본이 남는다. -E는 GNU 전용 \| 교대 표현에 기대지 않기 위해서다. 구분자 \#는 패턴 속 /를 이스케이프하지 않으려는 선택이다.
#   관련: TASK-56, docs/sed-portability-audit.md
