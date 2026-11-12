# ---
# title: set_globals_spec
# description: 06_set_globals.sh의 로컬 스코프 핀 기록과 전역 기본 동작을 검증하는 shellspec 회귀 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# shellcheck shell=bash
# Regression tests for scripts/install/06_set_globals.sh's LOCAL-scope pin
# tracking (TASK-83): pinning locally must record the target directory in
# $ASDF_DATA_DIR/langtoolchain-local-pins so uninstall can find it later
# (see spec/uninstall_runtimes_spec.sh for the read side of this).
Describe 'scripts/install/06_set_globals.sh'
  SCRIPT='./scripts/install/06_set_globals.sh'

  setup() {
    data_dir="$(mktemp -d)/toolchain-data"
    mkdir -p "$data_dir/shims"
    target_dir="$(mktemp -d)"
    config_file="$(mktemp)"
    export ASDF_DATA_DIR="$data_dir"
    export TOOL_VERSIONS_FILE="$config_file"
    pins_file="$data_dir/langtoolchain-local-pins"
    # LT_REPORT_FILE: redirect away from the real $HOME/.langtoolchain-
    # report.log - this spec doesn't override HOME, and the DRY_RUN=false
    # tests below would otherwise have lt_report() write there for real.
    report_file="$(mktemp)"
    export LT_REPORT_FILE="$report_file"
  }
  cleanup() { rm -rf "$(dirname "$data_dir")" "$target_dir" "$config_file" \
    "$report_file"; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  Describe 'local scope'  # ---- 1
    It 'records the target directory in the local-pins file'
      printf '# scope: local %s\npython 3.12.13\n' "$target_dir" \
        > "$config_file"
      export DRY_RUN=false
      Mock asdf
        case "$1" in
          set) exit 0 ;;
          reshim) exit 0 ;;
        esac
      End
      When run "$SCRIPT"
      The output should include 'Pinning versions locally'
      The contents of file "$pins_file" should eq "$target_dir"
    End

    It 'does not record anything under DRY_RUN (nothing was really pinned)'
      printf '# scope: local %s\npython 3.12.13\n' "$target_dir" \
        > "$config_file"
      export DRY_RUN=true
      When run "$SCRIPT"
      The output should include '+ asdf set'
      The path "$pins_file" should not be exist
    End

    It 'does not duplicate the directory when pinned twice'
      printf '# scope: local %s\npython 3.12.13\n' "$target_dir" \
        > "$config_file"
      export DRY_RUN=false
      Mock asdf
        case "$1" in
          set) exit 0 ;;
          reshim) exit 0 ;;
        esac
      End
      "$SCRIPT" >/dev/null
      When run "$SCRIPT"
      The output should include 'Pinning versions locally'
      lines="$(( $(wc -l < "$pins_file") ))"
      The variable lines should eq 1
    End
  End

  Describe 'global scope (default)'
    It 'does not touch the local-pins file at all'
      printf 'python 3.12.13\n' > "$config_file"
      export DRY_RUN=false
      Mock asdf
        case "$1" in
          set) exit 0 ;;
          reshim) exit 0 ;;
        esac
      End
      When run "$SCRIPT"
      The output should include 'Setting global'
      The path "$pins_file" should not be exist
    End
  End
End

# ======== 노트 ========
# 1 로컬 핀 기록 쓰기 쪽
#   설명: 로컬 고정이 $ASDF_DATA_DIR의 핀 파일에 디렉터리를 기록하고, dry-run과 중복은 기록하지 않는지 확인한다.
#   관련: TASK-83, spec/uninstall_runtimes_spec.sh
