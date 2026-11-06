#!/usr/bin/env sh
# ---
# title: 06_validate_teardown
# description: 제거 후 잔재가 남지 않았는지 항목별로 점검하는 제거 6단계 검증 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# No `set -e` — a test runner should evaluate every assertion, not stop at
# the first failure.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"

step "Phase 6: Validating teardown"

# Under --dry-run nothing was actually removed, so every check below would
# report FAIL against a machine that's still fully intact — skip instead.
if [ "${DRY_RUN:-false}" = "true" ]; then  # ---- 1
  log "(dry-run: nothing was actually removed, skipping validation)"
  exit 0
fi

OK=true  # ---- 2

# This script deliberately does NOT call ensure_asdf_on_path() — a teardown
# check has no reason to put asdf back on PATH. That means it can't rely on
# lib.sh to have exported ASDF_DATA_DIR, so (same fix as 07_validate.sh /
# TASK-57) fall back via lt_asdf_data_dir() here instead of a literal, to
# avoid false-FAILing a custom ASDF_DATA_DIR.
ASDF_DATA_DIR="$(lt_asdf_data_dir)"  # ---- 3
readonly ASDF_DATA_DIR

if command -v asdf >/dev/null 2>&1; then
  log "  FAIL: 'asdf' is still resolvable in PATH."
  OK=false
else
  log "  OK:   asdf removed from PATH."
fi

# Colons bracket the check so "$ASDF_DATA_DIR/shims" can't false-positive-match
# a differently named path that merely contains that substring.
case ":$PATH:" in
  *":$ASDF_DATA_DIR/shims:"*)  # ---- 4
    log "  FAIL: \$ASDF_DATA_DIR/shims is still in this session's PATH."
    OK=false
    ;;
  *) log "  OK:   PATH has no asdf shims." ;;
esac

# POSIX [ ] has no glob-pattern matching, so this is a case statement
# instead of [[ -n ... && ... == pat* ]]. An unset/empty JAVA_HOME simply
# won't match the (always non-empty) "$ASDF_DATA_DIR"* pattern, so it
# falls through to the OK branch same as before.
case "${JAVA_HOME:-}" in
  "$ASDF_DATA_DIR"*)  # ---- 5
    log "  FAIL: \$JAVA_HOME still points into \$ASDF_DATA_DIR."
    OK=false
    ;;
  *)
    log "  OK:   JAVA_HOME not pointing at asdf."
    ;;
esac

log ""
if $OK; then  # ---- 6
  log "Validation passed: cleanup complete."
  exit 0
else
  # A still-open shell keeps the OLD PATH/JAVA_HOME cached even after the
  # underlying files are gone — this isn't a real failure, just stale state
  # in the current process's environment.
  log "The FAIL items above are cached state left in this shell session." \
    "Run 'exec \$SHELL' (or open a new terminal) and check again."
  exit 1
fi

# ======== 노트 ========
# 1 dry-run이면 검증 생략
#   설명: 실제로 지운 게 없어 모든 점검이 거짓 실패가 된다.
# 2 모든 점검을 모아 보고
#   설명: set -e 없이 실패를 OK=false로 누적한다.
# 3 판정 기준은 하드코딩된 ".asdf"가 아니라 실제 데이터 디렉터리
#   설명: 사용자 지정 ASDF_DATA_DIR이면 리터럴 비교가 거짓 FAIL을 내거나 잔재를 놓친다.
#   관련: TASK-65, spec/validate_teardown_spec.sh
# 4 PATH 점검(콜론으로 감싼 비교)
#   설명: 현재 셸 세션의 PATH에 shim이 남았는지 본다. 이 FAIL은 캐시된 세션 상태라서 새 셸을 열면 사라진다.
# 5 JAVA_HOME이 asdf 아래를 가리키는지 점검
#   설명: asdf-java 훅이 export한 값이 세션에 남아 있을 수 있다.
# 6 종료 코드가 검증 결과
#   설명: 깨끗하면 0, 세션 상태 잔재면 1. uninstall/main.sh가 이 값을 받아 보고한다.
