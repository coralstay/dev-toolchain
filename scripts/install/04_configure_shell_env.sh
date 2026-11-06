#!/usr/bin/env sh
# ---
# title: 04_configure_shell_env
# description: asdf 셸 통합과 빌드 플래그 환경변수를 사용자 rc 파일에 기록하는 설치 4단계 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Writes asdf + build-flag shell config into the user's rc file.
#
# Modern Homebrew asdf (v0.16+, the Go rewrite — what `brew install asdf`
# gives you today) is a single binary with no libexec/asdf.sh to source.
# Shell integration is just: put $ASDF_DATA_DIR/shims on PATH. The previous
# version of this tool tried to source that nonexistent file and silently
# did nothing — this replaces that with the two exports asdf actually needs.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"

step "Phase 4: Configuring shell environment"

# Which rc file to edit depends on the user's actual login shell ($SHELL),
# not whatever shell happens to be running this installer.
RC_FILE="$(detect_rc_file)"
readonly RC_FILE
# Make sure the file exists before grep/sed touch it (e.g. a brand new
# machine with no .bash_profile yet).
run touch "$RC_FILE"  # ---- 1
log "Using rc file: $RC_FILE"

# Java home hook — pick the variant matching the detected shell (the
# asdf-java plugin ships both; sourcing the wrong one would just silently
# do nothing in that shell). This choice depends on which rc file we're
# writing to, so it's made here and handed to lib.sh's lt_env_var_defs()
# rather than lib.sh guessing it.
case "$RC_FILE" in
  *"$LT_RC_FILE_ZSH") JAVA_HOOK="set-java-home.zsh" ;;  # ---- 2
  *)                  JAVA_HOOK="set-java-home.bash" ;;
esac

# Every rc-file line this installer manages — search pattern, placement
# (prepend/append), and the line to write — comes from this single shared
# definition (see lib.sh's lt_env_var_defs for why). Which lines prepend
# vs. append is decided there, as data, not by matching text here.
# POSIX sh has no process substitution, so the defs go to a temp file first.
ENV_VAR_DEFS_TMP="$(mktemp)"
readonly ENV_VAR_DEFS_TMP
lt_env_var_defs "$JAVA_HOOK" > "$ENV_VAR_DEFS_TMP"  # ---- 3
while IFS= read -r def; do
  search="${def%%|||*}"
  rest="${def#*|||}"
  placement="${rest%%|||*}"
  line="${rest#*|||}"
  case "$placement" in
    prepend) prepend_env_var "$RC_FILE" "$search" "$line" ;;  # ---- 4
    *)       append_env_var "$RC_FILE" "$search" "$line" ;;
  esac
done < "$ENV_VAR_DEFS_TMP"
rm -f "$ENV_VAR_DEFS_TMP"

# DRY_RUN-aware (found during a UX pass, m-6/TASK-94.3): every write above
# went through append_env_var/prepend_env_var's own DRY_RUN branch (preview
# only, nothing on disk), so saying "written" unconditionally here would
# misreport a no-op preview as a real change.
if [ "$DRY_RUN" = "true" ]; then
  log "(dry-run: nothing was actually written to $RC_FILE)"
else
  log "Shell config written to $RC_FILE."
  lt_report modified "$RC_FILE (added asdf/build-flag lines)"
fi

# ======== 노트 ========
# 1 rc 파일이 없어도 grep/sed가 동작하도록 선생성
#   설명: 새 머신에 .bash_profile이 아직 없을 때를 대비한다. dry-run에서는 run이 출력만 한다.
# 2 쉘별 java 훅 변형 선택
#   설명: asdf-java 플러그인이 zsh/bash 용 훅을 둘 다 제공하고, 잘못된 쪽을 source하면 조용히 아무 일도 안 한다. 어떤 rc 파일에 쓰는지를 아는 이 단계에서 고른다.
# 3 쓸 줄은 lib.sh의 정의를 그대로 사용
#   설명: 패턴·내용은 lt_env_var_defs가 단일 출처이고, 이 스크립트는 |||로 구분된 필드를 풀어 prepend/append만 결정한다. 제거 쪽과 어긋나지 않는다.
#   관련: scripts/lib.sh, scripts/uninstall/03_clean_env_vars.sh
#   개념: SSOT
# 4 brew shellenv는 asdf shim PATH 줄보다 앞에
#   설명: 같은 이름의 Homebrew 포뮬러가 asdf shim을 가리지 않도록 순서를 지킨다.
#   관련: spec/configure_shell_env_spec.sh
