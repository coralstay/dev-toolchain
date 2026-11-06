#!/usr/bin/env sh
# ---
# title: uninstall
# description: curl로 받아 실행하는 한 줄 제거 진입점으로, scripts/uninstall/main.sh에 위임하는 스크립트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# langtoolchain — one-line uninstaller
#
#   curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
#     https://raw.githubusercontent.com/coralstay/langtoolchain/main/uninstall.sh | sh
#
# Thin entry point — real logic lives in scripts/uninstall/*.sh. See
# install.sh (its sibling) for a more detailed line-by-line explanation of
# this local-clone-vs-curl dispatch — the two are intentionally identical
# in structure.
set -eu

# NOTE: kept in sync by hand with install.sh's copy of these same two
# lines — see install.sh for why this can't source lib.sh instead. If you
# change the defaults here, change install.sh too.
#
# Pinned to a specific commit, not a floating branch name (TASK-117.1,
# decision-1) — see install.sh's copy of this comment for the full
# reasoning. Keep this in sync with install.sh's BRANCH default by hand.
#
# LANGTOOLCHAIN_REPO_URL / LANGTOOLCHAIN_BRANCH (TASK-117.6): same opt-in
# override as install.sh — see its copy of this comment for the reasoning.
readonly REPO_URL="${LANGTOOLCHAIN_REPO_URL:-https://github.com/coralstay/dev-toolchain.git}"
readonly BRANCH="${LANGTOOLCHAIN_BRANCH:-108188739d7cf493981a1cdb89789612d2790b5a}"  # ---- 1

# $0, not ${BASH_SOURCE[0]:-} (POSIX sh has no BASH_SOURCE) — see
# install.sh for why the -f check below is what actually does the real/
# piped-stdin discrimination, verified empirically there.
SELF_PATH="$0"
if [ -n "$SELF_PATH" ] && { [ -f "$SELF_PATH" ] || [ -h "$SELF_PATH" ]; }; then  # ---- 2
  while [ -h "$SELF_PATH" ]; do
    _LINK_DIR="$(cd -P "$(dirname "$SELF_PATH")" && pwd)"
    SELF_PATH="$(readlink "$SELF_PATH")"
    case "$SELF_PATH" in
      /*) ;;
      *) SELF_PATH="$_LINK_DIR/$SELF_PATH" ;;
    esac
  done
  SELF_DIR="$(cd -P "$(dirname "$SELF_PATH")" && pwd)"
  readonly SELF_DIR
fi
readonly SELF_PATH

if [ -n "${SELF_DIR:-}" ] && [ -d "$SELF_DIR/scripts/uninstall" ]; then
  # Local clone: run in place, no network needed.
  exec sh "$SELF_DIR/scripts/uninstall/main.sh" "$@"  # ---- 3
fi

# `curl | sh`: no local checkout exists, so fetch a throwaway one.
command -v git >/dev/null 2>&1 || {
  printf '%s%s\n' "ERROR: git is required for the one-line uninstaller " \
    "(macOS ships it with Xcode Command Line Tools)." >&2
  exit 1
}

# See install.sh's copy of this check for the reasoning — only fires once
# we're actually about to fetch over the network.
if [ -n "${LANGTOOLCHAIN_REPO_URL:-}" ] ||
   [ -n "${LANGTOOLCHAIN_BRANCH:-}" ]; then
  printf '%s%s%s%s\n' "WARNING: LANGTOOLCHAIN_REPO_URL/LANGTOOLCHAIN_BRANCH " \
    "override detected (REPO_URL=$REPO_URL, BRANCH=$BRANCH) — this source " \
    "has not been reviewed or pinned by this tool. Only use this to test " \
    "your own fork/branch." >&2
fi

# Deliberately NOT `exec`d below — see install.sh for why: exec replaces
# this process image outright, which skips the trap on the successful
# path entirely (only fires on an early failure before we get here).
WORKDIR="$(mktemp -d)"
readonly WORKDIR
trap 'rm -rf "$WORKDIR"' EXIT  # ---- 4

# CLONE_FETCH_TIMEOUT / clone_fetch_with_timeout (TASK-145.3): see
# install.sh's copy of these for the full reasoning — a small inline
# duplicate of lt_run_with_timeout()'s (scripts/lib.sh, TASK-138.1)
# wall-clock-kill idea, since this file can't source lib.sh (no repo on
# disk yet) or rely on timeout(1)/gtimeout(1) (pre-Homebrew, decision-10)
# either. `git fetch` alone has no wall-clock cap against a DNS/TCP/TLS
# handshake blackhole (decision-10). Simpler than lt_run_with_timeout()
# though: no stdout/stderr tempfile capture, since every caller here
# already discards clone_pinned()'s output wholesale (`>/dev/null 2>&1`
# in the retry loop below).
readonly CLONE_FETCH_TIMEOUT="${LANGTOOLCHAIN_CLONE_TIMEOUT:-30}"  # ---- 5

#######################################
# Run `git fetch --depth 1 origin <ref>` under a hard wall-clock timeout.
# Globals:
#   CLONE_FETCH_TIMEOUT
# Arguments:
#   $1: ref — commit SHA, tag, or branch name to fetch
# Outputs:
#   git's own (-q-quieted) output, same as any other step in clone_pinned().
# Returns:
#   124 if the fetch was killed for exceeding CLONE_FETCH_TIMEOUT;
#   otherwise git fetch's own exit status.
#######################################
clone_fetch_with_timeout() {
  local ref="$1" fetch_pid watchdog_pid status timeout_marker
  timeout_marker="$(mktemp -u)"
  git fetch -q --depth 1 origin "$ref" &
  fetch_pid=$!
  (
    sleep "$CLONE_FETCH_TIMEOUT"
    if kill -0 "$fetch_pid" 2>/dev/null; then
      : > "$timeout_marker"
      kill -TERM "$fetch_pid" 2>/dev/null
    fi
  ) &
  watchdog_pid=$!
  status=0
  wait "$fetch_pid" || status=$?
  kill "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  if [ -f "$timeout_marker" ]; then
    rm -f "$timeout_marker"
    return 124
  fi
  rm -f "$timeout_marker"
  return "$status"
}

# clone_pinned <ref>: see install.sh's copy of this function for the full
# reasoning (fetches exactly <ref> — SHA, tag, or branch name — instead of
# trusting whatever a branch currently points to; `git clone --branch`
# can't reliably target an arbitrary commit SHA the way `fetch <ref>` can).
#######################################
# Clone exactly <ref> (SHA/tag/branch) into $WORKDIR/langtoolchain.
# Globals:
#   WORKDIR
#   REPO_URL
# Arguments:
#   $1: ref — commit SHA, tag, or branch name to fetch and check out
# Outputs:
#   None of its own — git's own (-q-quieted) output passes through unless
#   the caller redirects it (the retry loop below sends it to /dev/null).
# Returns:
#   0 if every git step succeeds; non-zero (the subshell's status) if any
#   step in the init/remote/fetch/checkout chain fails (including 124 if
#   the fetch step specifically timed out).
#######################################
clone_pinned() {
  rm -rf "$WORKDIR/langtoolchain"
  mkdir -p "$WORKDIR/langtoolchain"
  (
    cd "$WORKDIR/langtoolchain" &&
    git init -q &&
    git remote add origin "$REPO_URL" &&
    clone_fetch_with_timeout "$1" &&
    git checkout -q FETCH_HEAD  # ---- 6
  )
}

# Retries a transient clone failure a few times before giving up (TASK-88)
# — see install.sh for why this is an inline duplicate of lib.sh's retry()
# rather than a shared call.
CLONE_ATTEMPT=1
until clone_pinned "$BRANCH" >/dev/null 2>&1; do  # ---- 7
  if [ "$CLONE_ATTEMPT" -ge 3 ]; then
    printf '%s\n' "ERROR: git clone failed after $CLONE_ATTEMPT attempts." >&2
    exit 1
  fi
  printf '%s\n' "git clone failed (attempt $CLONE_ATTEMPT/3) — retrying..." >&2
  # No explicit rm -rf here — clone_pinned() removes $WORKDIR/langtoolchain
  # itself at the start of every attempt, including the next one this loop
  # triggers.
  sleep $((CLONE_ATTEMPT * 5))
  CLONE_ATTEMPT=$((CLONE_ATTEMPT + 1))
done
sh "$WORKDIR/langtoolchain/scripts/uninstall/main.sh" "$@"  # ---- 8
exit $?

# ======== 노트 ========
# 1 실행할 커밋 SHA를 상수로 고정
#   설명: curl|sh가 부동 브랜치(main)가 아니라 특정 커밋을 실행하도록 BRANCH 기본값을 SHA로 못 박는다. 브랜치 드리프트·강제 푸시된 나쁜 커밋을 막고, 매 실행이 재현·감사 가능하다. 갱신은 사람이 직접 한다(origin/main의 SHA를 붙여 넣기). install.sh와 uninstall.sh의 값이 같아야 한다.
#   관련: decision-1, TASK-117.1, docs/download-integrity-techniques.md, install.sh
#   개념: 핀(pin), 재현성
# 2 로컬 클론 실행과 curl|sh 실행 판별
#   설명: POSIX sh에는 BASH_SOURCE가 없고 curl|sh에서도 $0이 비지 않는다. $0이 실제 존재하는 파일인지(-f/-h)로 구분한다. 심볼릭 링크는 끝까지 따라가 SELF_DIR을 구한다.
#   관련: scripts/uninstall/main.sh
# 3 로컬 클론이면 네트워크 없이 바로 위임
#   설명: 이미 디스크에 저장소가 있으면 그것을 그대로 쓴다. exec로 프로세스를 대체해 남는 셸이 없다.
# 4 임시 디렉터리 정리 trap
#   설명: 성공·오류·Ctrl-C 어느 경로로 끝나도 임시 clone을 지운다. 그래서 아래 마지막 호출은 exec가 아니라 일반 호출이어야 한다(exec는 셸 종료 절차를 건너뛰어 trap이 실행되지 않는다).
# 5 git fetch 벽시계 타임아웃
#   설명: DNS·TCP·TLS 블랙홀로 git fetch가 무기한 멈추는 것을 막는 상한(초). 저장소가 아직 없어 lib.sh를 source할 수 없고 timeout(1)도 Homebrew 이전엔 없어 인라인으로 구현한다.
#   관련: decision-10, TASK-145.3, scripts/lib.sh (lt_run_with_timeout)
# 6 SHA 고정 가져오기 관용구의 마지막 단계
#   설명: init, remote add, fetch <ref>, checkout FETCH_HEAD 순서는 SHA·태그·브랜치를 똑같이 다룬다. git clone --branch는 임의 SHA를 안정적으로 받지 못한다. 순서가 바뀌면 핀이 깨진다.
#   관련: TASK-117.1
# 7 clone 재시도 루프
#   설명: 일시적 네트워크 오류를 최대 3회 재시도하고 5초 단위로 늘려 쉰다. 출력은 버리고 실패 시에만 안내한다. lib.sh의 retry()를 쓸 수 없어 인라인이다.
#   관련: TASK-88
# 8 exec 없이 호출하는 이유
#   설명: trap EXIT가 실행되도록 exec를 쓰지 않고, 바로 아래 exit $?로 종료 코드를 그대로 전달한다.
