# ---
# title: main_entrypoints_spec
# description: install/uninstall main.sh의 플래그 검증 동작을 확인하는 shellspec 회귀 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression tests for scripts/install/main.sh and scripts/uninstall/
# main.sh - previously untested (see git history: no main_spec.sh ever
# existed). Most of what these orchestrators do (acquire_lock -> 00_select.sh
# -> run_phase over real asdf/brew-touching phases) can't be exercised
# locally without a real asdf/Homebrew stack, per this repo's own
# test-safety convention (see e.g. bootstrap_asdf_spec.sh's header comment).
#
# The unknown-flag rejection path is the one exception: it's reached right
# after acquire_lock (LT_LOCK_DIR overridden below to a scratch dir, so this
# never touches the real shared lock) and exits before anything else runs -
# no 00_select.sh, no phases, no brew/asdf. Entered via the root install.sh/
# uninstall.sh entry points (not scripts/install/main.sh directly), so this
# also exercises install.sh's/uninstall.sh's own "local clone detected ->
# exec straight into main.sh" dispatch, itself never directly tested before.
Describe 'install.sh -> scripts/install/main.sh (flag validation)'  # ---- 1
  SCRIPT='./install.sh'

  setup() {
    lock_dir="$(mktemp -d)/lt-test.lock"
    export LT_LOCK_DIR="$lock_dir"
  }
  cleanup() { rm -rf "$(dirname "$lock_dir")"; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'rejects an unknown flag with a clear message and exits 1'
    When run "$SCRIPT" --bogus-flag
    The status should be failure
    The error should include 'Unknown option: --bogus-flag'
  End

  It 'releases the lock even when rejecting an unknown flag (EXIT'\
' trap still fires)'
    "$SCRIPT" --bogus-flag 2>/dev/null || true
    When call true
    The path "$lock_dir" should not be exist
  End
End

Describe 'uninstall.sh -> scripts/uninstall/main.sh (flag validation)'  # ---- 2
  SCRIPT='./uninstall.sh'

  setup() {
    lock_dir="$(mktemp -d)/lt-test.lock"
    export LT_LOCK_DIR="$lock_dir"
  }
  cleanup() { rm -rf "$(dirname "$lock_dir")"; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'rejects an unknown flag with a clear message and exits 1'
    When run "$SCRIPT" --bogus-flag
    The status should be failure
    The error should include 'Unknown option: --bogus-flag'
  End

  It 'releases the lock even when rejecting an unknown flag (EXIT'\
' trap still fires)'
    "$SCRIPT" --bogus-flag 2>/dev/null || true
    When call true
    The path "$lock_dir" should not be exist
  End
End

# ======== 노트 ========
# 1 알 수 없는 플래그 검증
#   설명: 실제 phase는 대화형·파괴적이라 시험할 수 없으므로 플래그 검증과 잠금 해제까지만 확인한다.
#   관련: scripts/install/main.sh
# 2 제거 쪽 같은 검증
#   설명: install과 같은 보장을 제거 오케스트레이터에서도 확인한다.
#   관련: scripts/uninstall/main.sh
