#!/usr/bin/env sh
# ---
# title: 05_purge_asdf_core
# description: 설치 전 상태 스냅샷을 확인해 asdf 본체와 데이터 디렉터리를 조건부로 삭제하는 제거 5단계 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Removes asdf itself and its data directory. Only ever touches the user's
# *global* ~/.tool-versions — never this repo's own .tool-versions, which is
# a tracked project file, not machine state.
#
# The data-dir deletion below (TASK-124/decision-6) is conditional on the
# install-time snapshot from TASK-123: it never removes a data dir that
# looks like it pre-dates this tool. The `brew uninstall asdf` below is now
# gated the same way (TASK-144 — an earlier version left it ungated, so a
# pre-existing Homebrew-installed asdf with no other dependents got deleted
# for real in UAT even though its data dir/plugins were correctly kept).
# ~/.tool-versions removal below it is still NOT gated — that one is
# machine-wide asdf config this tool itself always writes to, not something
# that can pre-date this tool the way the asdf formula/data dir can.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
. "$SCRIPT_DIR/../lib.sh"
# Same reasoning as every brew-touching install phase (see lib.sh): this
# runs as its own process, so `brew` moments-old on PATH in some other
# phase's process isn't guaranteed to be on THIS one's PATH too.
ensure_brew_on_path

step "Phase 5: Removing asdf core"

if brew list asdf >/dev/null 2>&1; then
  # Same gating as the data dir below: lt_prior_state_get reads the
  # install-time snapshot (TASK-123); only an explicit "false" (asdf was NOT
  # there before this tool ran) clears it for deletion. A missing snapshot
  # (pre-dates this feature, or --dry-run install) is indistinguishable from
  # "don't know" and treated the same as "true" — safe-by-default, same as
  # the data-dir check (TASK-144).
  if [ "$(lt_prior_state_get asdf_preexisting || true)" = "false" ]; then  # ---- 1
    log "Uninstalling asdf (Homebrew) ..."
    if run brew uninstall asdf; then
      lt_report removed "asdf (Homebrew)"
    fi
  else
    log "Skipping brew uninstall asdf — it looks like it existed before" \
      "langtoolchain was installed (or that can't be confirmed from a" \
      "missing snapshot), so it's being left in place rather than risk" \
      "deleting an asdf install this tool didn't create. If you're sure" \
      "it's safe, remove it yourself: brew uninstall asdf"
    lt_report skipped "asdf (Homebrew)"' (looked pre-existing, or'\
' unconfirmed — not removed; see README)'
  fi
fi

# Respect a live ASDF_DATA_DIR override (same fallback ensure_asdf_on_path()
# uses, via lt_asdf_data_dir()) instead of always assuming the default — a
# user who installed with a custom ASDF_DATA_DIR would otherwise have their
# real data directory silently left behind (TASK-70).
TARGET_ASDF_DATA_DIR="$(lt_asdf_data_dir)"  # ---- 2
readonly TARGET_ASDF_DATA_DIR

if [ -d "$TARGET_ASDF_DATA_DIR" ]; then
  # This is where EVERYTHING asdf-managed actually lives: downloads,
  # installs, plugins, and shims all sit under here. Removing it deletes
  # every compiled runtime this tool ever installed — but ALSO anything
  # that was already sitting there before this tool ever ran, if this
  # machine had asdf set up beforehand (m-13/TASK-124). lt_prior_state_get
  # reads the snapshot install wrote before touching anything (TASK-123);
  # only an explicit "false" (this dir did NOT exist pre-install) clears
  # this for deletion.
  #
  # Safe-by-default for every other case (TASK-124.1 AC #2): a MISSING
  # snapshot — installed before this feature existed, or installed via
  # --dry-run, which never writes one — is indistinguishable here from
  # "don't know", so it's treated the same as "true" (pre-existing) rather
  # than assumed safe to wipe.
  if [ "$(lt_prior_state_get asdf_data_dir_preexisting || true)" \
    = "false" ]; then
    log "Removing $TARGET_ASDF_DATA_DIR ..."
    run rm -rf "$TARGET_ASDF_DATA_DIR"  # ---- 3
    lt_report removed \
      "$TARGET_ASDF_DATA_DIR (entire asdf data dir: installs, plugins, shims)"
  else
    log "Skipping $TARGET_ASDF_DATA_DIR — it looks like it existed before" \
      "langtoolchain was installed (or that can't be confirmed from a missing" \
      "snapshot), so it's being left in place rather than risk deleting asdf" \
      "state this tool didn't create. If you're sure it's safe, remove it" \
      "yourself: rm -rf \"$TARGET_ASDF_DATA_DIR\""
    lt_report skipped "$TARGET_ASDF_DATA_DIR"' (looked pre-existing, or'\
' unconfirmed — not removed; see README)'
  fi
fi

if [ -f "$HOME/.tool-versions" ]; then
  # Deliberately $HOME/.tool-versions (the machine-wide default asdf falls
  # back to) — NOT $REPO_ROOT/.tool-versions, which is a file tracked in
  # this git repo and not something an uninstaller should ever delete.
  log "Removing $HOME/.tool-versions ..."
  run rm -f "$HOME/.tool-versions"  # ---- 4
  lt_report removed "$HOME/.tool-versions"
fi

# m-16/TASK-139/decision-8: this is the last phase (main.sh's phase list ends
# here), and the only reader of LT_PRIOR_STATE_FILE is the "true"-vs-"false"
# check above (TASK-124.1) — nothing later in this run reads it again. So
# once every command above this line has succeeded (set -eu killed the
# script already if any of them failed), the snapshot has done its job for
# THIS uninstall and can be cleared, letting the next install re-baseline
# from the machine's actual post-uninstall state instead of staying pinned
# to whatever this machine looked like the very first time langtoolchain
# ever snapshotted it. Guarded the same way
# lt_snapshot_prior_asdf_state() (scripts/lib.sh) guards its own write:
# DRY_RUN never touched real state, so it must not delete the snapshot
# either. A failed/interrupted uninstall (this phase or an earlier one)
# never reaches this line, so decision-6's original concern — a retry
# needing the snapshot still there — is unaffected.
[ "$DRY_RUN" = "true" ] || rm -f "$LT_PRIOR_STATE_FILE"  # ---- 5

# ======== 노트 ========
# 1 brew uninstall asdf도 스냅샷으로 게이트
#   설명: 설치 전부터 있던 Homebrew asdf를 지우지 않는다. 스냅샷을 확인할 수 없으면 건너뛴다.
#   관련: TASK-144, decision-6
# 2 삭제 대상은 실제 데이터 디렉터리
#   설명: ASDF_DATA_DIR 재정의를 존중하고 $HOME/.asdf를 하드코딩하지 않는다.
#   관련: TASK-70, lt_asdf_data_dir (scripts/lib.sh)
# 3 가장 파괴적인 줄
#   설명: 설치 전 스냅샷이 "원래 없었다"고 말할 때만 도달한다. 확인 불가나 이미 있던 경우는 else 분기에서 건너뛴다.
#   관련: TASK-124, decision-6
# 4 전역 ~/.tool-versions만 지운다
#   설명: 저장소 안의 .tool-versions는 추적되는 프로젝트 파일이지 머신 상태가 아니므로 절대 건드리지 않는다.
# 5 마지막 phase에서 스냅샷 삭제
#   설명: 앞의 모든 명령이 set -eu를 통과했을 때만 도달하므로, 중간에 실패한 제거는 재시도에 스냅샷이 남는다. dry-run은 실제 상태를 건드리지 않았으니 지우지 않는다.
#   관련: decision-8, TASK-139
