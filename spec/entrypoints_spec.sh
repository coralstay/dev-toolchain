# ---
# title: entrypoints_spec
# description: install.sh와 uninstall.sh가 별개의 진입점으로 유지되는지 못박는 shellspec 회귀 가드
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression guard for TASK-105: install.sh and uninstall.sh are deliberately
# separate, independently curl-able entry points (see readme.md's "코드
# 구조" section) - never bundled into one script that dispatches on a mode
# flag. This locks that decision in so a future edit can't quietly merge
# them back together.
Describe 'install.sh / uninstall.sh entry points (TASK-105)'  # ---- 1
  It 'both exist as separate executable files at the repo root'
    The path './install.sh' should be exist
    The path './uninstall.sh' should be exist
    The file './install.sh' should be executable
    The file './uninstall.sh' should be executable
  End

  It 'install.sh has no code-level (non-comment) reference to'\
' uninstall.sh - not bundled'
    # Comments cross-referencing the sibling file for maintainers are fine
    # and expected (see both files' own header comments) - what this guards
    # against is an actual `sh uninstall.sh` / dispatch-on-mode-flag call.
    When run command sh -c "grep -v '^[[:space:]]*#' install.sh |\
 grep -c uninstall.sh"
    The status should be failure
    The output should eq '0'
  End

  It 'uninstall.sh has no code-level (non-comment) reference to'\
' install.sh - not bundled'
    When run command sh -c "grep -v '^[[:space:]]*#' uninstall.sh |\
 grep -c install.sh"
    The status should be failure
    The output should eq '0'
  End

  It 'each has its own independent curl-fetchable REPO_URL/BRANCH bootstrap'  # ---- 2
    The contents of file './install.sh' should include 'REPO_URL='
    The contents of file './uninstall.sh' should include 'REPO_URL='
  End
End

# ======== 노트 ========
# 1 두 진입점은 합치지 않는다
#   설명: 각각 독립적으로 curl로 받을 수 있어야 하므로 모드 플래그로 분기하는 한 스크립트로 합치는 것을 막는다.
#   관련: TASK-105
# 2 각자 자체 부트스트랩
#   설명: 저장소가 없는 상태에서 실행되므로 lib.sh 공유 없이 REPO_URL/BRANCH를 각자 들고 있어야 한다.
#   관련: install.sh, uninstall.sh
