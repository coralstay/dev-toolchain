# ---
# title: validate_teardown_spec
# description: 06_validate_teardown.sh가 사용자 지정 ASDF_DATA_DIR을 기준으로 판정하는지 검증하는 shellspec 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression tests for scripts/uninstall/06_validate_teardown.sh (TASK-65),
# the uninstall-side counterpart of the 07_validate.sh fix from TASK-57: the
# PATH/JAVA_HOME checks must judge against $ASDF_DATA_DIR, not a hardcoded
# ".asdf" literal, or a custom ASDF_DATA_DIR user gets a false FAIL/misses a
# real leftover. See spec/validate_spec.sh for the install-side sibling.
Describe 'scripts/uninstall/06_validate_teardown.sh'
  SCRIPT='./scripts/uninstall/06_validate_teardown.sh'

  setup() {
    data_dir="$(mktemp -d)/toolchain-data"
    mkdir -p "$data_dir"
    # A PATH with nothing asdf-related on it — the "cleanly torn down" case.
    clean_path="/usr/bin:/bin:/usr/sbin:/sbin"
  }
  cleanup() {
    rm -rf "$(dirname "$data_dir")"
  }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'PATH check (custom ASDF_DATA_DIR)'  # ---- 1
    It 'reports OK when a clean PATH holds no leftover shims for a'\
' custom ASDF_DATA_DIR'
      export ASDF_DATA_DIR="$data_dir" PATH="$clean_path" DRY_RUN=false
      unset -v JAVA_HOME
      When run "$SCRIPT"
      The output should include 'OK:   PATH has no asdf shims.'
      The output should not include 'FAIL'
    End

    It 'reports FAIL when the custom ASDF_DATA_DIR shims path is still on PATH'
      export ASDF_DATA_DIR="$data_dir" PATH="$data_dir/shims:$clean_path" \
        DRY_RUN=false
      unset -v JAVA_HOME
      When run "$SCRIPT"
      The output should include 'FAIL: $ASDF_DATA_DIR/shims is still'\
' in this session'"'"'s PATH.'
      The status should be failure
    End
  End

  Describe 'JAVA_HOME check (custom ASDF_DATA_DIR)'
    It 'reports OK when JAVA_HOME does not point into the custom ASDF_DATA_DIR'
      export ASDF_DATA_DIR="$data_dir" PATH="$clean_path" \
        JAVA_HOME="/usr/lib/jvm/system-java" DRY_RUN=false
      When run "$SCRIPT"
      The output should include 'OK:   JAVA_HOME not pointing at asdf.'
    End

    It 'reports FAIL when JAVA_HOME still points into the custom ASDF_DATA_DIR'
      export ASDF_DATA_DIR="$data_dir" PATH="$clean_path" \
        JAVA_HOME="$data_dir/installs/java/21.0.0" DRY_RUN=false
      When run "$SCRIPT"
      The output should include 'FAIL:'\
' $JAVA_HOME still points into $ASDF_DATA_DIR.'
      The status should be failure
    End
  End

  Describe 'ASDF_DATA_DIR unset (falls back to lib.sh default)'
    It 'still detects a leftover shim under $HOME/.asdf when'\
' ASDF_DATA_DIR is unset'
      fake_home="$(mktemp -d)"
      mkdir -p "$fake_home/.asdf/shims"
      export HOME="$fake_home" PATH="$fake_home/.asdf/shims:$clean_path" \
        DRY_RUN=false
      unset -v ASDF_DATA_DIR JAVA_HOME
      When run "$SCRIPT"
      The output should include "FAIL: \$ASDF_DATA_DIR/shims is still in \
this session's PATH."
      The status should be failure
      rm -rf "$fake_home"
    End
  End

  Describe 'DRY_RUN=true'  # ---- 2
    It 'skips all validation instead of reporting false failures'
      export ASDF_DATA_DIR="$data_dir" PATH="$data_dir/shims:$clean_path" \
        DRY_RUN=true
      When run "$SCRIPT"
      The output should include '(dry-run: nothing was actually removed,'\
' skipping validation)'
      The output should not include 'FAIL'
      The status should be success
    End
  End
End

# ======== 노트 ========
# 1 사용자 지정 ASDF_DATA_DIR 기준 판정
#   설명: 하드코딩된 ".asdf" 리터럴이면 거짓 FAIL이나 누락이 생긴다.
#   관련: TASK-65
# 2 dry-run이면 검증 생략
#   설명: 실제로 지운 게 없으니 거짓 실패를 보고하지 않아야 한다.
