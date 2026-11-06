#!/usr/bin/env sh
# ---
# title: 04_remove_system_deps
# description: 설치 3단계에서 깐 Homebrew 빌드 의존 패키지를 제거하는 제거 4단계 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Removes the Homebrew build-dependency formulas (LT_BUILD_DEPS in lib.sh)
# this tool installed for Python's C extensions — mirrors the install side's
# 03_install_system_deps.sh.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"
# Same reasoning as every brew-touching install phase (see lib.sh): this
# runs as its own process, so `brew` moments-old on PATH in some other
# phase's process isn't guaranteed to be on THIS one's PATH too.
ensure_brew_on_path

step "Phase 4: Removing system build dependencies (Homebrew)"

for pkg in $LT_BUILD_DEPS; do
  # Only try to uninstall what's actually installed — brew would otherwise
  # just error on an already-absent formula. `&>` is a bash-only shorthand
  # for redirecting both stdout and stderr — POSIX only has `>x 2>&1`.
  if brew list "$pkg" >/dev/null 2>&1; then  # ---- 1
    log "Uninstalling $pkg ..."
    # Homebrew refuses to uninstall a formula something else still depends
    # on; treat that refusal as informational, not fatal, since these
    # formulas are commonly shared with other tools on the machine.
    if run brew uninstall "$pkg"; then  # ---- 2
      lt_report removed "Homebrew package: $pkg"
    else
      log "  Skipped $pkg (likely required by another package)."
    fi
  fi
done

# ======== 노트 ========
# 1 설치된 것만 제거
#   설명: 없는 포뮬러에 uninstall하면 brew가 오류를 낸다. &>는 bash 전용이라 POSIX 리다이렉션을 쓴다.
# 2 다른 포뮬러가 의존하면 거부되는 것이 정상
#   설명: 이 포뮬러들은 다른 도구와 공유되는 경우가 많아, 거부는 오류가 아니라 안내로 처리한다.
#   관련: LT_BUILD_DEPS (scripts/lib.sh)
