# ---
# title: install_system_deps_spec
# description: 03_install_system_deps.sh의 brew 호출을 mock으로 검증하는 shellspec 회귀 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression tests for scripts/install/03_install_system_deps.sh.
# `brew` is always Mocked - see spec/bootstrap_asdf_spec.sh for why PATH
# restriction alone isn't a safe enough guard on its own (TASK-81).
Describe 'scripts/install/03_install_system_deps.sh'
  SCRIPT='./scripts/install/03_install_system_deps.sh'

  It 'installs the full LT_BUILD_DEPS list in one brew call'  # ---- 1
    # LT_REPORT_FILE: redirect away from the real $HOME/.langtoolchain-
    # report.log - this spec doesn't override HOME, and DRY_RUN=false here
    # means lt_report() would otherwise write there for real.
    report_file="$(mktemp)"
    export DRY_RUN=false LT_REPORT_FILE="$report_file"
    Mock brew
      case "$1" in
        install) echo "MOCK: brew install $*" ;;
        *) echo '/mock/bin/brew' ;;
      esac
    End
    When run "$SCRIPT"
    The output should include 'MOCK: brew install install openssl@3 readline'\
' sqlite3 xz zlib tcl-tk'
    rm -f "$report_file"
  End

  It 'only previews under DRY_RUN, never calling brew for real'
    export DRY_RUN=true
    Mock brew
      echo 'UNEXPECTED: brew was actually invoked'
    End
    When run "$SCRIPT"
    The output should include '+ brew install openssl@3 readline sqlite3 xz'\
' zlib tcl-tk'
    The output should not include 'UNEXPECTED'
  End
End

# ======== 노트 ========
# 1 brew는 한 번만 호출
#   설명: 포뮬러 목록을 한 번의 brew install로 넘긴다. brew는 항상 Mock이다.
#   관련: TASK-81, LT_BUILD_DEPS
