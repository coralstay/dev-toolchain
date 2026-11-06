# ---
# title: bootstrap_asdf_spec
# description: 01_bootstrap_asdf.sh의 Homebrew·asdf 설치 경로를 mock으로 검증하는 shellspec 회귀 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression tests for scripts/install/01_bootstrap_asdf.sh.
#
# SAFETY: `brew`/`asdf` are always Mocked in every test here, never left to
# resolve for real - this dev machine has real Homebrew and real asdf
# installed. Relying on PATH restriction alone is NOT enough (see TASK-81:
# ensure_brew_on_path() re-adds Homebrew's fixed install prefix regardless
# of what PATH already contains, once a real near-miss actually fired
# `brew uninstall asdf` against this exact machine). Mock wins the PATH
# lookup regardless, so it's what actually keeps this file safe to run.
#
# The "Homebrew/asdf is genuinely absent, so install it for real" branches
# aren't covered here. Simulating "genuinely absent" requires restricting
# PATH so `command -v` truly fails - but empirically, restricting PATH
# ahead of a `Mock` declaration in this shellspec version prevents Mock's
# own scratch-dir prepend from taking effect at all (confirmed by hand:
# `PATH=<restricted>; export PATH` before `Mock brew` left PATH as exactly
# the restricted value with no mock dir prepended, so the real system
# binaries would've been the ones actually found - not safe to rely on for
# a file that can run `brew`/`asdf` for real). Both branches are already
# covered by e2e-verify.yml's `no-homebrew-bootstrap` job (TASK-20) and the
# `full-cycle` job's very first run, on real, disposable CI hardware where
# nothing is pre-installed - a strictly safer way to exercise "not found"
# than fighting this dev machine's real installs locally.
Describe 'scripts/install/01_bootstrap_asdf.sh'  # ---- 1
  SCRIPT='./scripts/install/01_bootstrap_asdf.sh'

  setup() { export DRY_RUN=true; }
  BeforeEach 'setup'

  It 'reports Homebrew and asdf already present without reinstalling either'
    Mock brew
      echo '/mock/bin/brew'
    End
    Mock asdf
      case "$1" in
        version) echo '0.20.0' ;;
      esac
    End
    When run "$SCRIPT"
    The output should include 'Homebrew found'
    The output should include 'asdf already installed'
    The output should not include 'brew install asdf'
  End

  It 'fails clearly on a non-macOS uname (this installer is macOS-only)'  # ---- 2
    Mock uname
      echo 'Linux'
    End
    When run "$SCRIPT"
    The status should be failure
    The output should include 'Phase 1'
    The error should include 'only supports macOS'
  End

  Describe 'fetch_verified_homebrew_installer() curl call (TASK-131.1)'  # ---- 3
    # A dynamic Mock-based test (calling fetch_verified_homebrew_installer()
    # directly with curl Mocked to simulate a timeout) was attempted first,
    # the same way spec/lib_spec.sh's retry() tests call a lib.sh function
    # directly. It doesn't work here: 01_bootstrap_asdf.sh locates its own
    # sibling lib.sh via `dirname "$0"`, which only resolves correctly when
    # the file is *executed* as its own process (`When run`, where the
    # shell sets $0 to the script path) - sourcing it with `.` leaves $0 as
    # shellspec's own, so SCRIPT_DIR resolves to the wrong directory and
    # lib.sh never actually loads (LT_DOWNLOAD_TIMEOUT itself is declared
    # in this file, not lib.sh, but the same sibling-source limitation
    # still applies to a `When call` test here).
    # And reaching this function through a real `When run` requires brew to
    # be genuinely absent from PATH, which - per this file's header comment
    # above - Mock can't simulate (it only adds a fake command to PATH, it
    # can't remove the real one), and restricting PATH by hand breaks
    # Mock's own prepend in this shellspec version. So this checks the
    # fetch call's source line directly instead: same intent (confirm the
    # Homebrew installer fetch has a hard timeout like every other
    # network call in this diff), a static assertion instead of a dynamic
    # one.
    It 'passes --max-time LT_DOWNLOAD_TIMEOUT to the installer'\
' fetch, like every other curl call in this file'
      fetch_line="$(grep -A1 'curl -fsSL' "$SCRIPT" |
        grep 'HOMEBREW_INSTALL_URL')"
      When call echo "$fetch_line"
      The output should include '--max-time'
      The output should include 'LT_DOWNLOAD_TIMEOUT'
    End

    It 'enforces HTTPS on the installer fetch, including across redirects'\
' (SonarCloud S6506)'
      fetch_block="$(awk '/curl -fsSL/{print; getline; print}' "$SCRIPT")"
      When call echo "$fetch_block"
      The output should include "--proto '=https'"
      The output should include "--proto-redir '=https'"
      The output should include '--tlsv1.2'
    End
  End
End

# ======== 노트 ========
# 1 brew/asdf는 항상 Mock
#   설명: 이 개발 머신에는 진짜 Homebrew와 asdf가 있다. PATH 제한만으로는 ensure_brew_on_path()가 고정 접두사를 다시 넣어 실제 brew uninstall asdf가 실행될 뻔했다. Mock이 PATH 조회에서 이기게 해야 안전하다.
#   관련: TASK-81
# 2 macOS 전용 가드 시험
#   설명: uname이 Darwin이 아니면 분명한 메시지로 실패하는지 본다.
#   관련: scripts/install/01_bootstrap_asdf.sh
# 3 다운로드 호출을 정적으로 검증
#   설명: 실제 네트워크 호출 없이 스크립트 본문의 curl 줄이 HTTPS 강제와 --max-time을 포함하는지 문자열로 확인한다.
#   관련: TASK-131.1, m-18
