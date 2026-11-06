#!/usr/bin/env sh
# ---
# title: main
# description: 제거 1~6단계를 각각 별도 프로세스로 순서대로 실행하는 제거 오케스트레이터
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Orchestrator: runs each teardown phase in its own process, in order.
#
# Flags:
#   --dry-run   print what would happen, change nothing
#   --yes       skip the "are you sure?" confirmation
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"

for arg in "$@"; do
  case "$arg" in
    -h|--help|help)
      printf '%s\n' "사용법 (Usage): dev-toolchain-uninstall [--yes] [--dry-run] [-h|--help]"
      printf '%s\n' "  --yes       확인 프롬프트 없이 즉시 제거 실행"
      printf '%s\n' "  --dry-run   실제 변경 없이 제거 예정 항목만 미리보기"
      printf '%s\n' "  -h, --help  이 도움말 출력"
      exit 0
      ;;
  esac
done

# Exclusive lock (TASK-84), shared with install/main.sh, so this can't race
# another uninstall or an install. Must be first, before the confirmation
# prompt even, so nothing below ever runs concurrently with another instance.
acquire_lock  # ---- 1
trap 'release_lock' EXIT
# INT/TERM (TASK-90): separate trap slot from EXIT above — see
# install/main.sh for why registering this doesn't clobber the lock-release
# trap.
trap 'handle_interrupt' INT TERM  # ---- 2

DRY_RUN=false
AUTO_YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes) AUTO_YES=true ;;
    *) printf '%s\n' "Unknown option: $arg" >&2; exit 1 ;;
  esac
done
# Exported so every phase script below (each its own `sh` process) can
# see it via lib.sh.
export DRY_RUN

printf '%s\n' "langtoolchain uninstaller"
printf '%s%s\n' "This will remove asdf, every asdf-managed runtime," \
  " the related Homebrew packages, and the shell config this tool added."

# confirm_uninstall (m-8): extracted so main.sh's own top-level flow reads
# as a named step (see the call right below this function) instead of this
# whole block sitting inline between the intro message and the phase loop.
#######################################
# Ask the user to confirm the uninstall, unless --yes or no tty.
# Globals:
#   AUTO_YES
# Arguments:
#   None
# Outputs:
#   Writes the "Continue? [y/N] > " prompt to STDOUT; on decline, writes
#   "Cancelled." to STDOUT.
# Returns:
#   Does not return on decline — exits with status 1.
#######################################
confirm_uninstall() {
  local interactive=true reply
  # Probe for a controlling terminal first - same technique as
  # install/00_select.sh's own INTERACTIVE check (`true < /dev/tty` either
  # succeeds, or fails with its own stderr suppressed here). Without this,
  # the `read` below would leak a raw "/dev/tty: Device not configured"
  # shell error straight to the user the moment there's no tty at all (CI,
  # or this script piped through something with no terminal) - found
  # during a UX pass (m-6/TASK-97.1).
  { true < /dev/tty; } 2>/dev/null || interactive=false  # ---- 3

  # --yes given, or no tty and no --yes: proceed anyway, the same way
  # 00_select.sh auto-falls-back to --all under those conditions, rather
  # than leaving the user staring at a prompt that can never be answered.
  #
  # `if COND; then return; fi`, not a bare `COND && return` - found the
  # hard way (m-8 refactor regression): under `set -e`, a standalone
  # `A && B` statement where A fails still counts as a failing statement
  # (B never running doesn't save it) and kills the script right there,
  # silently, since `return` swallows the failure before anything gets a
  # chance to report it. Wrapping the same check in an explicit `if`
  # sidesteps this - failing a condition inside `if` is exactly what `if`
  # exists to handle safely under `set -e`.
  if $AUTO_YES; then  # ---- 4
    return
  fi
  if ! $interactive; then
    return
  fi

  printf "Continue? [y/N] > "
  # Read straight from the terminal device, not this script's own stdin —
  # matters when this file itself was piped in via `curl | bash`.
  read -r reply < /dev/tty || reply=""
  case "$reply" in
    y|Y|yes|YES) ;;  # ---- 5
    *) printf '%s\n' "Cancelled."; exit 1 ;;
  esac
}

confirm_uninstall

# Each phase runs as its own `sh` process, independent of the others —
# same reasoning as scripts/install/main.sh. run_phase (not a plain
# `sh "$SCRIPT_DIR/$phase"` call) so the INT/TERM trap above can actually
# interrupt a phase mid-flight — see run_phase's own comment in lib.sh.
for phase in \
  01_uninstall_runtimes.sh \
  02_remove_plugins.sh \
  03_clean_env_vars.sh \
  04_remove_system_deps.sh \
  05_purge_asdf_core.sh  # ---- 6
do
  run_phase "$SCRIPT_DIR/$phase"
done

printf '\n'
# Temporarily allow the validation phase to fail without killing this
# script outright — its exit code is meaningful (0 = clean, 1 = stale
# session state) and we want to report on it ourselves below rather than
# letting `set -e` abort mid-way.
set +e  # ---- 7
sh "$SCRIPT_DIR/06_validate_teardown.sh"
readonly VALIDATION_EXIT_CODE=$?  # ---- 8
set -e

# DRY_RUN-aware (found during a UX pass, m-6/TASK-94.3): under --dry-run,
# 06_validate_teardown.sh above exits 0 via its own dry-run skip path (there
# was nothing to validate, not "validated clean") - without this branch a
# preview-only run would print the same "complete" message as a real one.
if [ "$DRY_RUN" = "true" ]; then
  printf '%s\n' "Dry run complete. Nothing was actually removed or changed."
elif [ "$VALIDATION_EXIT_CODE" -eq 0 ]; then
  printf '%s\n' "Removal complete. Run 'exec \$SHELL' to start a fresh session."
else
  printf '%s\n' "Removal finished, but check the warnings above."
  exit "$VALIDATION_EXIT_CODE"
fi

# ======== 노트 ========
# 1 설치와 같은 잠금을 공유
#   설명: install/main.sh와 같은 LT_LOCK_DIR 잠금을 써서 설치와 제거가 동시에 상태를 바꾸지 못하게 한다.
#   관련: acquire_lock (scripts/lib.sh), TASK-84
# 2 INT/TERM trap은 EXIT와 별도
#   설명: Ctrl-C로 handle_interrupt가 exit 130을 호출하면 EXIT trap이 잠금을 푼다.
#   관련: TASK-90
# 3 터미널 없으면 프롬프트 없이 진행
#   설명: 00_select.sh와 같은 방식의 tty 탐지. 답할 수 없는 프롬프트에서 멈추는 것을 막는다.
#   관련: scripts/install/00_select.sh
# 4 if를 쓰는 이유: set -e와 A && B
#   설명: set -e 아래에서 단독 문장 A && B는 A가 실패하면 스크립트를 조용히 죽인다. 명시적 if는 조건 실패를 안전하게 처리한다(m-8 리팩터링 회귀).
#   개념: set -e 예외 규칙
# 5 확인 응답은 y/yes만 통과
#   설명: 그 밖의 입력은 모두 취소(exit 1)다. 기본값이 N인 파괴적 작업의 안전장치다.
# 6 제거 phase 순서
#   설명: 순서가 곧 의존성이다: 런타임 → 플러그인 → rc 환경변수 → 시스템 의존성 → asdf 본체. 플러그인 제거(02)가 asdf 본체 삭제(05)보다 먼저여야 한다. 06 검증은 아래에서 따로 실행한다.
#   관련: scripts/uninstall/02_remove_plugins.sh, TASK-130
# 7 검증 phase만 실패를 허용
#   설명: 06의 종료 코드(0 깨끗함, 1 세션 상태 잔재)에 의미가 있어 직접 받아 보고한다. 받은 직후 set -e를 복원한다.
#   관련: scripts/uninstall/06_validate_teardown.sh
# 8 검증 종료 코드를 즉시 캡처
#   설명: 다른 명령이 끼면 $?가 바뀌므로 sh 호출 바로 다음 줄에서 읽는다.
