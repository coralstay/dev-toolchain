# ---
# title: remove_system_deps_spec
# description: 04_remove_system_deps.sh의 brew 제거·정리 동작을 mock으로 검증하는 shellspec 회귀 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression tests for scripts/uninstall/04_remove_system_deps.sh (also the
# file at the center of TASK-78: missing ensure_brew_on_path caused brew
# cleanup to silently no-op when brew wasn't already on this process's
# PATH). `brew` is always Mocked here - never left to resolve for real, per
# the TASK-81 lesson (PATH restriction alone isn't a safe enough guard,
# since ensure_brew_on_path re-adds Homebrew's fixed prefix regardless).
Describe 'scripts/uninstall/04_remove_system_deps.sh'
  SCRIPT='./scripts/uninstall/04_remove_system_deps.sh'

  setup() {
    # LT_REPORT_FILE: redirect away from the real $HOME/.langtoolchain-
    # report.log - this spec doesn't override HOME, and DRY_RUN=false here
    # means lt_report() would otherwise write there for real.
    report_file="$(mktemp)"
    export DRY_RUN=false LT_REPORT_FILE="$report_file"
  }
  cleanup() { rm -f "$report_file"; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'uninstalls every installed LT_BUILD_DEPS formula'
    Mock brew
      case "$1 $2" in
        "list openssl@3") exit 0 ;;
        "list readline") exit 0 ;;
        "list sqlite3") exit 0 ;;
        "list xz") exit 0 ;;
        "list zlib") exit 0 ;;
        "list tcl-tk") exit 0 ;;
        "uninstall openssl@3") echo "UNINSTALLED: $2" ;;
        "uninstall readline") echo "UNINSTALLED: $2" ;;
        "uninstall sqlite3") echo "UNINSTALLED: $2" ;;
        "uninstall xz") echo "UNINSTALLED: $2" ;;
        "uninstall zlib") echo "UNINSTALLED: $2" ;;
        "uninstall tcl-tk") echo "UNINSTALLED: $2" ;;
      esac
    End
    When run "$SCRIPT"
    The output should include 'UNINSTALLED: openssl@3'
    The output should include 'UNINSTALLED: tcl-tk'
  End

  It 'skips a formula that is not installed, without erroring'
    Mock brew
      case "$1 $2" in
        "list openssl@3") exit 1 ;;
        "list readline") exit 1 ;;
        "list sqlite3") exit 1 ;;
        "list xz") exit 1 ;;
        "list zlib") exit 1 ;;
        "list tcl-tk") exit 1 ;;
        uninstall*) echo "UNEXPECTED UNINSTALL: $2" ;;
      esac
    End
    When run "$SCRIPT"
    The status should be success
    The output should not include 'UNEXPECTED'
  End

  It 'treats "required by another package" as informational, not fatal'  # ---- 1
    Mock brew
      case "$1 $2" in
        "list openssl@3") exit 0 ;;
        "list readline") exit 1 ;;
        "list sqlite3") exit 1 ;;
        "list xz") exit 1 ;;
        "list zlib") exit 1 ;;
        "list tcl-tk") exit 1 ;;
        "uninstall openssl@3") exit 1 ;;
      esac
    End
    When run "$SCRIPT"
    The status should be success
    The output should include 'Skipped openssl@3'
  End
End

# ======== 노트 ========
# 1 의존 거부는 치명적이지 않음
#   설명: 다른 포뮬러가 의존해 brew가 제거를 거부해도 phase가 계속되어야 한다.
#   관련: scripts/uninstall/04_remove_system_deps.sh
