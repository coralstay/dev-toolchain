# ---
# title: clean_env_vars_spec
# description: 04가 쓴 모든 rc 줄을 03_clean_env_vars.sh가 지울 수 있는지 검증하는 shellspec 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression tests for scripts/uninstall/03_clean_env_vars.sh (TASK-64):
# every line 04_configure_shell_env.sh writes must be removable by this
# script's sed patterns, since both now derive from lib.sh's shared
# lt_env_var_defs() instead of two independently-typed pattern lists. This
# is exactly the bug class TASK-56 was (java hook line surviving uninstall
# because uninstall's own copy of the pattern didn't match) - a full
# install-then-uninstall round trip is the most direct way to catch it
# recurring.
Describe 'scripts/uninstall/03_clean_env_vars.sh'  # ---- 1
  INSTALL_SCRIPT='./scripts/install/04_configure_shell_env.sh'
  CLEAN_SCRIPT='./scripts/uninstall/03_clean_env_vars.sh'

  setup() {
    fake_home="$(mktemp -d)"
  }
  cleanup() { rm -rf "$fake_home"; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'removes every line the install phase wrote, leaving the rc file empty'
    HOME="$fake_home" SHELL=/bin/zsh DRY_RUN=false "$INSTALL_SCRIPT" > /dev/null
    rc_file="$fake_home/.zshrc"
    written_lines=$(( $(wc -l < "$rc_file") ))

    export HOME="$fake_home" DRY_RUN=false
    When run "$CLEAN_SCRIPT"
    The output should include 'Cleaning'
    The variable written_lines should not eq 0
    remaining=$(( $(wc -l < "$rc_file") ))
    The variable remaining should eq 0
  End

  It 'is idempotent - cleaning an already-clean rc file is a no-op'  # ---- 2
    HOME="$fake_home" SHELL=/bin/zsh DRY_RUN=false "$INSTALL_SCRIPT" > /dev/null
    rc_file="$fake_home/.zshrc"
    HOME="$fake_home" DRY_RUN=false "$CLEAN_SCRIPT" > /dev/null
    export HOME="$fake_home" DRY_RUN=false
    When run "$CLEAN_SCRIPT"
    The output should include 'Cleaning'
    The status should be success
    remaining=$(( $(wc -l < "$rc_file") ))
    The variable remaining should eq 0
  End

  It 'leaves unrelated pre-existing rc file content untouched'  # ---- 3
    mkdir -p "$fake_home"
    printf 'export MY_OWN_TOOL_PATH="/some/other/tool"\n' > "$fake_home/.zshrc"
    HOME="$fake_home" SHELL=/bin/zsh DRY_RUN=false "$INSTALL_SCRIPT" > /dev/null
    export HOME="$fake_home" DRY_RUN=false
    When run "$CLEAN_SCRIPT"
    The output should include 'Cleaning'
    The contents of file "$fake_home/.zshrc" should include 'MY_OWN_TOOL_PATH'
    The contents of file "$fake_home/.zshrc" should not include 'ASDF_DATA_DIR'
  End

  It 'skips DRY_RUN without modifying the rc file'
    HOME="$fake_home" SHELL=/bin/zsh DRY_RUN=false "$INSTALL_SCRIPT" > /dev/null
    rc_file="$fake_home/.zshrc"
    before="$(cat "$rc_file")"
    export HOME="$fake_home" DRY_RUN=true
    When run "$CLEAN_SCRIPT"
    The output should include 'remove asdf/build-flag lines'
    after="$(cat "$rc_file")"
    The variable after should eq "$before"
  End
End

# ======== 노트 ========
# 1 설치가 쓴 줄은 제거가 모두 지운다
#   설명: 04가 쓰는 모든 줄이 03의 sed 패턴으로 지워져야 한다. 둘이 같은 정의에서 파생되므로 어긋나면 이 테스트가 먼저 깨진다.
#   관련: TASK-64, scripts/lib.sh (lt_env_var_defs)
# 2 멱등성
#   설명: 이미 깨끗한 rc 파일에 다시 실행해도 변화가 없어야 한다.
# 3 무관한 사용자 설정은 보존
#   설명: 패턴이 너무 넓으면 사용자의 다른 rc 줄을 지운다. 그 회귀를 막는다.
