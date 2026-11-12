#!/usr/bin/env sh
# ---
# title: lib
# description: 설치·제거 단계 스크립트가 공통으로 source하는 부작용 없는 POSIX sh 유틸리티 함수 모음
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# created_date: '2026-11-06'
# updated_date: '2026-11-06'
# ---
# Shared utilities sourced by the phase scripts under scripts/install/ and
# scripts/uninstall/. Pure functions only — sourcing this file has no side
# effects, so any phase script can source it standalone, in any order,
# without depending on another phase script having run first.
#
# Written for POSIX sh (TASK-71/72) — no [[ ]], no arrays, no BASH_REMATCH,
# no other bash-only syntax. `local` is the one non-POSIX-standard
# exception kept deliberately (see TASK-71): it's supported by every real
# POSIX-compliant shell this tool targets (dash included), and dropping it
# would mean every function falls back to polluting the global namespace.

# DRY_RUN is exported by main.sh before it launches each phase script as a
# child process. `:-false` makes this file safe to source on its own too
# (e.g. while testing a single phase by hand) — it just defaults to "do it
# for real".
DRY_RUN="${DRY_RUN:-false}"

# ---- Shared constants ----
# Literal values (paths, filenames, package lists, rc-file search/write
# patterns) that used to be typed independently into multiple phase
# scripts, which let them silently drift out of sync with each other (see
# e.g. the Intel-Mac sqlite PATH bug fixed alongside TASK-61, or the
# BSD-sed java-hook bug fixed by TASK-56). Each entry below is its own
# clearly-separated block so another branch adding one more entry here
# merges cleanly. This section is data only — it holds no control flow,
# and no phase script's own logic is meant to move here.

readonly LT_BUILD_DEPS="openssl@3 readline sqlite3 xz zlib tcl-tk"  # ---- 1

#######################################
# Print Homebrew's install prefix for the current CPU architecture.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes the Homebrew prefix path to STDOUT.
# Returns:
#   None
#######################################
lt_homebrew_prefix() {  # ---- 2
  case "$(uname -m)" in
    arm64) echo "/opt/homebrew" ;;  # Apple Silicon
    *)     echo "/usr/local" ;;     # Intel
  esac
}

# LT_ASDF_DATA_DIR_NAME / LT_ASDF_DATA_DIR_DEFAULT (TASK-62): asdf's own
# default data directory when the caller's environment hasn't set
# ASDF_DATA_DIR — this is where every asdf-managed download, plugin, and
# shim actually lives. Split into a bare directory NAME and the expanded
# DEFAULT path so both shapes are available: scripts doing real filesystem
# work (ensure_asdf_on_path's fallback, uninstall's delete target) want the
# expanded absolute path; a script writing a line into an rc file for a
# *future* shell to evaluate wants the bare name so it can keep `$HOME`
# itself literal (unexpanded) in what gets written, exactly like the
# original code did — resolving $HOME at write time instead would bake in
# whatever $HOME happened to be during install rather than at each future
# shell's own startup.
readonly LT_ASDF_DATA_DIR_NAME=".asdf"
readonly LT_ASDF_DATA_DIR_DEFAULT="$HOME/$LT_ASDF_DATA_DIR_NAME"

#######################################
# Print the effective asdf data directory.
# Globals:
#   ASDF_DATA_DIR
#   LT_ASDF_DATA_DIR_DEFAULT
# Arguments:
#   None
# Outputs:
#   Writes the effective asdf data directory path to STDOUT.
# Returns:
#   None
#######################################
lt_asdf_data_dir() {  # ---- 3
  echo "${ASDF_DATA_DIR:-$LT_ASDF_DATA_DIR_DEFAULT}"
}

# LT_RC_FILE_ZSH / LT_RC_FILE_BASH / LT_RC_FILE_BASH_INTERACTIVE /
# LT_KNOWN_RC_FILES (TASK-66): the rc filenames (bare, relative to $HOME)
# this tool knows how to write into or clean up.
#
# detect_rc_file() (below) picks exactly ONE of these at install time,
# based on the current $SHELL — the installer only ever writes into the rc
# file matching whichever shell is actually running it.
#
# uninstall/03_clean_env_vars.sh instead sweeps ALL of LT_KNOWN_RC_FILES:
# the $SHELL active when uninstall runs isn't necessarily the same one that
# was active when install ran, so it can't assume which single file was
# written to and has to check every rc file this tool has ever been able to
# write. This install-picks-one vs. uninstall-sweeps-all asymmetry is
# intentional, not an oversight.
readonly LT_RC_FILE_ZSH=".zshrc"
# macOS Terminal runs login shells.
readonly LT_RC_FILE_BASH=".bash_profile"
# Never picked by detect_rc_file; swept by uninstall only.
readonly LT_RC_FILE_BASH_INTERACTIVE=".bashrc"
readonly LT_KNOWN_RC_FILES="$LT_RC_FILE_ZSH $LT_RC_FILE_BASH \
$LT_RC_FILE_BASH_INTERACTIVE"

# LT_LOCAL_PINS_FILE_NAME (TASK-83): bare filename, under $ASDF_DATA_DIR, of
# the registry 06_set_globals.sh appends a directory to every time it pins
# versions LOCALLY (never globally) to that directory. 01_uninstall_runtimes.sh
# reads it back so a runtime version only ever pinned inside some project
# directory (never in the global ~/.tool-versions) still gets asdf-uninstalled.
# Deliberately lives under $ASDF_DATA_DIR: 05_purge_asdf_core.sh's `rm -rf
# $ASDF_DATA_DIR` deletes this file too, so there's nothing extra to clean up.
readonly LT_LOCAL_PINS_FILE_NAME="langtoolchain-local-pins"

LT_LOCK_DIR="${LT_LOCK_DIR:-${TMPDIR:-/tmp}/langtoolchain.lock}"  # ---- 4

LT_REPORT_FILE="${LT_REPORT_FILE:-$HOME/.langtoolchain-report.log}"  # ---- 5

# lt_report <action> <detail>: appends one line to LT_REPORT_FILE. Skipped
# under DRY_RUN by design - a preview run didn't actually change anything,
# so it has nothing real to add to the audit trail.
#######################################
# Append one timestamped audit-trail line to LT_REPORT_FILE.
# Globals:
#   DRY_RUN
#   LT_REPORT_FILE
# Arguments:
#   $1: action label
#   $2: detail text
# Outputs:
#   None to STDOUT/STDERR. Appends "<timestamp> [<action>] <detail>" to
#   LT_REPORT_FILE (skipped entirely under DRY_RUN).
# Returns:
#   None
#######################################
lt_report() {
  [ "$DRY_RUN" = "true" ] && return
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" \
    >> "$LT_REPORT_FILE"
}

LT_PRIOR_STATE_FILE="${LT_PRIOR_STATE_FILE:-$HOME/\
.langtoolchain-prior-asdf-state}"  # ---- 6

#######################################
# Snapshot whether asdf/its data dir/plugins pre-existed before this tool.
# Globals:
#   DRY_RUN
#   LT_PRIOR_STATE_FILE
# Arguments:
#   None
# Outputs:
#   None to STDOUT. Writes asdf_preexisting/asdf_data_dir/
#   asdf_data_dir_preexisting/asdf_plugins_preexisting key=value lines to
#   LT_PRIOR_STATE_FILE (skipped under DRY_RUN or if the file already
#   exists).
# Returns:
#   None
#######################################
lt_snapshot_prior_asdf_state() {  # ---- 7
  [ "$DRY_RUN" = "true" ] && return
  [ -f "$LT_PRIOR_STATE_FILE" ] && return

  # `brew list asdf` below needs `brew` resolvable in THIS process - see
  # ensure_brew_on_path's own comment for why that isn't automatic.
  ensure_brew_on_path

  local asdf_preexisting=false data_dir_preexisting=false plugins="" data_dir
  data_dir="$(lt_asdf_data_dir)"

  brew list asdf >/dev/null 2>&1 && asdf_preexisting=true
  [ -d "$data_dir" ] && data_dir_preexisting=true

  # Only attempt to list plugins when the asdf binary is actually
  # resolvable - matches the task's "asdf 자체가 없으면 생략" requirement
  # instead of letting a missing-command error leak into the snapshot.
  if command -v asdf >/dev/null 2>&1; then
    plugins="$(asdf plugin list 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
  fi

  {
    printf 'asdf_preexisting=%s\n' "$asdf_preexisting"
    printf 'asdf_data_dir=%s\n' "$data_dir"
    printf 'asdf_data_dir_preexisting=%s\n' "$data_dir_preexisting"
    printf 'asdf_plugins_preexisting=%s\n' "$plugins"
  } > "$LT_PRIOR_STATE_FILE"
}

# lt_prior_state_get <key>: prints the value for <key> from
# LT_PRIOR_STATE_FILE. Fails (nothing printed, exit 1) when the file
# doesn't exist at all OR has no such key - callers (TASK-124.1) must treat
# that failure as "unknown", never silently coerce it to "false", since an
# absent snapshot is exactly the "installed before this feature existed"
# case decision-6 calls out. Deliberately grep+cut, not `.`/`eval` on the
# file - a plain key=value read doesn't need a full shell eval, and this
# avoids that risk entirely even though this file is only ever written by
# this tool itself.
#######################################
# Print the value for <key> from LT_PRIOR_STATE_FILE.
# Globals:
#   LT_PRIOR_STATE_FILE
# Arguments:
#   $1: key to look up
# Outputs:
#   Writes the value to STDOUT on success; nothing on a miss.
# Returns:
#   None
#######################################
lt_prior_state_get() {
  local key="$1" line
  [ -f "$LT_PRIOR_STATE_FILE" ] || return 1
  line="$(grep "^${key}=" "$LT_PRIOR_STATE_FILE" 2>/dev/null | head -n 1)"
  [ -n "$line" ] || return 1
  printf '%s\n' "${line#*=}"
}

#######################################
# Print the rc-file entries this tool's installer manages, as data lines.
# Globals:
#   LT_ASDF_DATA_DIR_NAME
# Arguments:
#   $1: (optional) java hook filename to embed in the java-hook rc line
# Outputs:
#   Writes one "<search-pattern>|||<placement>|||<line-to-write>" line per
#   rc-file entry to STDOUT.
# Returns:
#   None
#######################################
lt_env_var_defs() {  # ---- 8
  local java_hook_file="${1:-}"
  local homebrew_prefix
  homebrew_prefix="$(lt_homebrew_prefix)"
  printf '%s\n' \
    "brew shellenv|||prepend|||eval \
\"\$($homebrew_prefix/bin/brew shellenv)\"" \
    "export ASDF_DATA_DIR=|||append|||export \
ASDF_DATA_DIR=\"\$HOME/$LT_ASDF_DATA_DIR_NAME\"" \
    "ASDF_DATA_DIR/shims|||append|||export \
PATH=\"\$ASDF_DATA_DIR/shims:\$PATH\"" \
    "set-java-home\.|||append|||. \
\$HOME/$LT_ASDF_DATA_DIR_NAME/plugins/java/$java_hook_file" \
    "opt/sqlite/bin|||append|||export \
PATH=\"$homebrew_prefix/opt/sqlite/bin:\$PATH\"" \
    "LDFLAGS.*openssl|||append|||export LDFLAGS=\"-L\$(brew --prefix \
openssl@3)/lib -L\$(brew --prefix readline)/lib -L\$(brew --prefix \
sqlite3)/lib -L\$(brew --prefix zlib)/lib\"" \
    "CPPFLAGS.*openssl|||append|||export CPPFLAGS=\"-I\$(brew --prefix \
openssl@3)/include -I\$(brew --prefix readline)/include -I\$(brew --prefix \
sqlite3)/include -I\$(brew --prefix zlib)/include\"" \
    "PKG_CONFIG_PATH.*openssl|||append|||export PKG_CONFIG_PATH=\"\$(brew \
--prefix openssl@3)/lib/pkgconfig:\$(brew --prefix \
readline)/lib/pkgconfig:\$(brew --prefix sqlite3)/lib/pkgconfig\""
}

# log <msg>: plain status line to stdout.
#######################################
# Print a plain status line.
# Globals:
#   None
# Arguments:
#   $*: message to print
# Outputs:
#   Writes <msg> to STDOUT.
# Returns:
#   None
#######################################
log()  { printf '%s\n' "$*"; }
# step <msg>: a section header, e.g. "== Phase 3: ... ==", to visually
# separate phases in the console output.
#######################################
# Print a visually separated section header.
# Globals:
#   None
# Arguments:
#   $*: section header text
# Outputs:
#   Writes a blank line then "== <msg> ==" to STDOUT.
# Returns:
#   None
#######################################
step() { printf '\n== %s ==\n' "$*"; }
# die <msg>: print to stderr and exit the whole script immediately.
#######################################
# Print an error message and terminate the script.
# Globals:
#   None
# Arguments:
#   $*: error message
# Outputs:
#   Writes "ERROR: <msg>" to STDERR.
# Returns:
#   Does not return — exits the calling script with status 1.
#######################################
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

#######################################
# Run <cmd...>, or describe it instead when DRY_RUN is set.
# Globals:
#   DRY_RUN
# Arguments:
#   $@: command and arguments to execute
# Outputs:
#   Under DRY_RUN, writes the command line (prefixed "  + ") to STDOUT.
#   Otherwise none of its own — whatever "$@" itself writes passes through.
# Returns:
#   Exit status of "$@" when not under DRY_RUN; 0 under DRY_RUN.
#######################################
run() {  # ---- 9
  # Under --dry-run, print what *would* run (prefixed with "+", like `set -x`)
  # instead of running it.
  if [ "$DRY_RUN" = "true" ]; then
    printf '  + %s\n' "$*"
  else
    # "$@" preserves each argument's word boundaries/quoting exactly as the
    # caller passed them — unlike "$*", this is safe for arguments with
    # spaces.
    "$@"
  fi
}

#######################################
# Run <cmd...>, retrying with exponential backoff on failure.
# Globals:
#   None
# Arguments:
#   $1: max_attempts
#   $2: delay_seconds (doubles after each failed attempt)
#   $3..: cmd and its arguments
# Outputs:
#   Writes "(attempt N/max failed, retrying in ...)" progress lines to
#   STDOUT (via log()) between attempts.
# Returns:
#   0 as soon as <cmd...> succeeds; 1 once <max_attempts> is exhausted.
#######################################
retry() {  # ---- 10
  local max_attempts="$1" delay="$2" attempt=1
  shift 2
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      return 1
    fi
    log "  (attempt $attempt/$max_attempts failed, retrying in ${delay}s...)"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

#######################################
# Run <cmd...> under a hard wall-clock timeout, killing it if it overruns.
# Globals:
#   None
# Arguments:
#   $1: seconds — wall-clock timeout
#   $2..: cmd and its arguments
# Outputs:
#   Writes <cmd...>'s captured STDOUT to this function's STDOUT, and its
#   captured STDERR to this function's STDERR.
# Returns:
#   124 if <cmd...> was killed for exceeding the timeout; otherwise
#   <cmd...>'s own exit status.
#######################################
lt_run_with_timeout() {  # ---- 11
  local secs="$1"
  shift
  local cmd_pid watchdog_pid status timeout_marker stdout_file stderr_file
  timeout_marker="$(mktemp -u)"
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  "$@" >"$stdout_file" 2>"$stderr_file" &
  cmd_pid=$!

  # `kill -0` sends no signal, it only tests whether cmd_pid is still a
  # live process - so a command that finishes before <seconds> is up never
  # gets the marker written for it, and never gets signaled at all.
  (
    sleep "$secs"
    if kill -0 "$cmd_pid" 2>/dev/null; then
      : > "$timeout_marker"
      kill -TERM "$cmd_pid" 2>/dev/null
    fi
  ) &
  watchdog_pid=$!

  status=0
  wait "$cmd_pid" 2>/dev/null || status=$?

  # By the time the wait above returns, the watchdog has either already
  # fired or is now pointless - kill+wait it here so it never outlives this
  # function as an orphaned background job. `|| true` on both: a caller
  # under `set -eu` must not abort on the watchdog's own (expected, ignored)
  # exit status.
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true

  cat "$stdout_file"
  cat "$stderr_file" >&2
  rm -f "$stdout_file" "$stderr_file"

  if [ -f "$timeout_marker" ]; then
    rm -f "$timeout_marker"
    return 124
  fi
  return "$status"
}

# ensure_disk_space <min_gb> (TASK-91): dies with a clear message if the
# filesystem containing $HOME has less than <min_gb> GB free. A best-effort
# up-front check, not a guarantee — a specific runtime's download+compile
# could still fail on genuinely tight disk even after this passes.
# `df -Pk`: POSIX output format (portable across BSD and GNU df) in 1024-byte
# blocks, so dividing by 1024 twice gets whole GB without needing `-g` (a
# GNU-only flag BSD/macOS df doesn't have).
#######################################
# Die with a clear message if $HOME's filesystem has too little free space.
# Globals:
#   HOME
# Arguments:
#   $1: min_gb — minimum free GB required
# Outputs:
#   None on success. On failure, writes an error message to STDERR (via
#   die()).
# Returns:
#   Does not return on failure — exits (via die()) with status 1.
#######################################
ensure_disk_space() {
  local min_gb="$1" available_kb available_gb
  available_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
  available_gb=$((available_kb / 1024 / 1024))
  if [ "$available_gb" -lt "$min_gb" ]; then
    die "Only ${available_gb}GB free on the filesystem containing \$HOME" \
      "(need at least ${min_gb}GB for Homebrew + asdf runtime compiles)." \
      "Free up space and try again."
  fi
}

# LT_CHILD_PID: the currently-running phase child process, if any — set by
# run_phase() below, read by handle_interrupt() so a trapped signal can
# kill it directly instead of leaving it to run to completion untouched.
LT_CHILD_PID=""

#######################################
# Run a phase script as a backgrounded, waited-on child so signals
# interrupt it promptly.
# Globals:
#   LT_CHILD_PID (written)
# Arguments:
#   $1: path to the phase script to run
# Outputs:
#   None of its own — whatever the phase script itself writes passes
#   through.
# Returns:
#   The phase script's own exit status.
#######################################
run_phase() {  # ---- 12
  # Between backgrounding the child and capturing its PID there's a brief
  # window where handle_interrupt has nothing to kill yet: a signal landing
  # exactly there would see an empty LT_CHILD_PID, skip the kill, and still
  # exit 130 — freeing the lock while this phase's child keeps running
  # unsupervised, the very orphan-plus-early-unlock this function exists to
  # prevent. Ignoring INT/TERM for that instant closes the window: POSIX
  # signals aren't queued while ignored, so a signal delivered there is
  # simply dropped rather than deferred — worst case it takes a second
  # Ctrl-C, which beats leaking an orphaned child.
  trap '' INT TERM
  sh "$1" &
  LT_CHILD_PID=$!
  trap 'handle_interrupt' INT TERM
  local status=0
  wait "$LT_CHILD_PID" || status=$?
  LT_CHILD_PID=""
  return "$status"
}

# handle_interrupt (TASK-90): registered via `trap handle_interrupt INT
# TERM` in install/main.sh and uninstall/main.sh, right after acquire_lock.
# Without this, Ctrl-C just kills the script with no explanation of what
# state it's left in. Every phase script this tool runs is safe to re-run
# (each one checks "already present"/"already absent" before acting — see
# design principle 1 in readme.md), so the honest, reassuring answer really
# is "just run it again." Kills LT_CHILD_PID first (see run_phase above) so
# a phase mid-flight actually stops instead of continuing to completion
# untouched. `exit 130` (128+SIGINT, the conventional exit code for Ctrl-C)
# still triggers the separately-registered EXIT trap afterward — INT/TERM
# and EXIT are independent trap slots, so this doesn't clobber the
# lock-release/cleanup trap the way two traps on the SAME signal would.
#######################################
# Handle an INT/TERM signal: kill the running phase child, then exit.
# Globals:
#   LT_CHILD_PID
# Arguments:
#   None
# Outputs:
#   Writes an interrupt notice to STDOUT (via log()).
# Returns:
#   Does not return — exits with status 130.
#######################################
handle_interrupt() {
  if [ -n "$LT_CHILD_PID" ]; then
    kill "$LT_CHILD_PID" 2>/dev/null || true
  fi
  log ""
  log "Interrupted. Anything already finished will be skipped on a" \
    "re-run - just run the same command again to continue."
  exit 130
}

# lt_die_if_lock_held: reads $LT_LOCK_DIR/pid and dies with the "another
# instance is running" message if that PID is still alive. Shared by
# acquire_lock()'s two check points below (the initial mkdir failure and the
# stale-lock reclaim race) so the message/logic can't drift between them.
#######################################
# Die if the PID recorded in the lock directory is still a live process.
# Globals:
#   LT_LOCK_DIR
# Arguments:
#   None
# Outputs:
#   None on success. On failure, writes an error message to STDERR (via
#   die()).
# Returns:
#   Does not return on failure — exits (via die()) with status 1.
#######################################
lt_die_if_lock_held() {
  local holder_pid=""
  [ -f "$LT_LOCK_DIR/pid" ] &&
    holder_pid="$(cat "$LT_LOCK_DIR/pid" 2>/dev/null)"
  if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
    die "Another langtoolchain install/uninstall (pid $holder_pid)" \
      "appears to be running. If you're sure it isn't, remove" \
      "$LT_LOCK_DIR and retry."
  fi
}

#######################################
# Take the exclusive install/uninstall lock at LT_LOCK_DIR.
# Globals:
#   LT_LOCK_DIR
# Arguments:
#   None
# Outputs:
#   None on success (writes $$ into $LT_LOCK_DIR/pid). On failure, writes
#   an error message to STDERR (via die()).
# Returns:
#   Does not return on failure — exits (via die()) with status 1.
#######################################
acquire_lock() {  # ---- 13
  if ! mkdir "$LT_LOCK_DIR" 2>/dev/null; then
    lt_die_if_lock_held
    # Stale lock (holder died before its own release_lock trap could run):
    # reclaim it. Two processes can observe the same stale lock at the same
    # instant and both reach this point — `rm -rf` on an already-removed
    # directory is a silent no-op, so at most one of the two `mkdir`s right
    # after it actually succeeds. The loser re-checks who holds the lock
    # now instead of assuming the worst: if the winner just legitimately
    # took it, that's reported as a real concurrent run, not a mystery
    # "could not acquire" failure.
    rm -rf "$LT_LOCK_DIR" 2>/dev/null
    if ! mkdir "$LT_LOCK_DIR" 2>/dev/null; then
      lt_die_if_lock_held
      die "Could not acquire lock at $LT_LOCK_DIR"
    fi
  fi
  echo $$ > "$LT_LOCK_DIR/pid"
}

# release_lock: removes the lock directory. Safe to call even when no lock
# was ever acquired (e.g. acquire_lock itself just died) — rm -rf on a path
# that doesn't exist is a no-op, not an error.
#######################################
# Remove the lock directory taken by acquire_lock().
# Globals:
#   LT_LOCK_DIR
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   None
#######################################
release_lock() {
  rm -rf "$LT_LOCK_DIR"
}

# repo_root_from <path-to-a-file-inside-scripts/install-or-uninstall>:
# prints the repository root (two directories up from scripts/install/ or
# scripts/uninstall/). Each phase script calls this with its own $0 so it
# can find .tool-versions regardless of the caller's current working
# directory.
#######################################
# Print the repository root, given a path to a file inside scripts/install
# or scripts/uninstall.
# Globals:
#   None
# Arguments:
#   $1: path to a file inside scripts/install or scripts/uninstall
# Outputs:
#   Writes the repository root absolute path to STDOUT.
# Returns:
#   None
#######################################
repo_root_from() {
  # Run in a subshell so the `cd` here doesn't change the calling script's
  # own working directory; `pwd` then prints the absolute, resolved path.
  ( cd "$(dirname "$1")/../.." && pwd )
}

# each_tool <config-file>: reads a .tool-versions-style file and prints
# "plugin version" pairs, one per line — skipping comment lines (starting
# with #) and blank/whitespace-only lines.
#######################################
# Print "plugin version" pairs from a .tool-versions-style file.
# Globals:
#   None
# Arguments:
#   $1: path to the .tool-versions-style config file
# Outputs:
#   Writes one "<plugin> <version>" line per entry to STDOUT.
# Returns:
#   None
#######################################
each_tool() {
  # /^[^# \t]/ matches lines whose first character is neither '#' nor a
  # space/tab, i.e. real plugin lines; $1/$2 are the plugin name and version
  # columns.
  awk '/^[^# \t]/ {print $1, $2}' "$1"
}

# detect_rc_file: prints the shell rc file the installer should edit,
# based on the user's login shell ($SHELL), not the shell currently running
# this script (curl | bash always runs under bash regardless of what the
# user actually uses day to day).
#######################################
# Print the shell rc file the installer should edit.
# Globals:
#   SHELL
#   HOME
#   LT_RC_FILE_ZSH
#   LT_RC_FILE_BASH
# Arguments:
#   None
# Outputs:
#   Writes the chosen rc file's absolute path to STDOUT.
# Returns:
#   None
#######################################
detect_rc_file() {
  case "$(basename "${SHELL:-}")" in
    zsh)  echo "$HOME/$LT_RC_FILE_ZSH" ;;
    bash) echo "$HOME/$LT_RC_FILE_BASH" ;;
    # unknown shell: default to zsh (macOS's own default since Catalina)
    *)    echo "$HOME/$LT_RC_FILE_ZSH" ;;
  esac
}

# append_env_var <rc_file> <search> <line>: appends <line> to <rc_file>,
# unless <rc_file> already contains something matching the grep pattern
# <search> — so re-running the installer never duplicates a line.
#######################################
# Append <line> to <rc_file>, unless <search> already matches something in it.
# Globals:
#   DRY_RUN
# Arguments:
#   $1: rc_file — path to the rc file to edit
#   $2: search — grep pattern that marks the line as already present
#   $3: line — the line to append
# Outputs:
#   Under DRY_RUN, writes a description of the pending write to STDOUT.
#   Otherwise none to STDOUT (appends <line> to <rc_file> on disk when not
#   already present).
# Returns:
#   None
#######################################
append_env_var() {
  local rc_file="$1" search="$2" line="$3"
  if [ "$DRY_RUN" = "true" ]; then
    # Dry-run: describe the write instead of performing it.
    printf '  + append to %s if missing: %s\n' "$rc_file" "$line"
    return
  fi
  # grep -q: no output, just an exit code. 2>/dev/null swallows the "no
  # such file" error the very first time this runs against a fresh rc file
  # (grep failing is also what makes `||` fall through to appending).
  grep -q "$search" "$rc_file" 2>/dev/null ||
    printf '%s\n' "$line" >> "$rc_file"
}

# prepend_env_var <rc_file> <search> <line>: like append_env_var, but
# inserts <line> at the very TOP of the file instead of the bottom.
#
# Order matters for PATH: whichever export runs LAST at shell startup wins
# (each `export PATH="X:$PATH"` prepends X ahead of everything already
# there). `brew shellenv` needs to run before asdf's shim PATH line — not
# after — or a Homebrew formula that happens to share a name with
# something asdf manages (e.g. a `node` formula installed some other way)
# would silently shadow the asdf shim. append_env_var can't guarantee this
# on a machine with a pre-existing rc file, since it only ever adds to the
# bottom; this guarantees first-in-file, and therefore correct priority,
# regardless of what else already lives in the rc file.
#######################################
# Prepend <line> to <rc_file>, unless <search> already matches something in it.
# Globals:
#   DRY_RUN
# Arguments:
#   $1: rc_file — path to the rc file to edit
#   $2: search — grep pattern that marks the line as already present
#   $3: line — the line to prepend
# Outputs:
#   Under DRY_RUN, writes a description of the pending write to STDOUT.
#   Otherwise none to STDOUT (rewrites <rc_file> on disk with <line> at the
#   top, when not already present).
# Returns:
#   None
#######################################
prepend_env_var() {
  local rc_file="$1" search="$2" line="$3"
  if [ "$DRY_RUN" = "true" ]; then
    printf '  + prepend to %s if missing: %s\n' "$rc_file" "$line"
    return
  fi
  grep -q "$search" "$rc_file" 2>/dev/null && return
  local tmp
  tmp="$(mktemp)"
  # New line first, then the file's existing content, all written to a
  # temp file, then swapped into place — `cat` never edits a file in place
  # while also reading from it.
  { printf '%s\n' "$line"; cat "$rc_file"; } > "$tmp"
  mv "$tmp" "$rc_file"
}

# read_scope <config_file>: reads the optional "# scope: ..." first line a
# selection file from 00_select.sh may carry, and prints either "global" or
# "local:<dir>". A config file with no such line (including this repo's own
# .tool-versions, which nothing ever adds this line to) defaults to
# "global" — keeps every phase working unmodified when TOOL_VERSIONS_FILE
# isn't set.
#######################################
# Print the scope ("global" or "local:<dir>") recorded in a config file.
# Globals:
#   None
# Arguments:
#   $1: config_file to read the scope line from
# Outputs:
#   Writes "global" or "local:<dir>" to STDOUT.
# Returns:
#   None
#######################################
read_scope() {
  local config_file="$1" first_line
  first_line="$(head -n 1 "$config_file" 2>/dev/null)"
  case "$first_line" in
    "# scope: local "*) echo "local:${first_line#"# scope: local "}" ;;
    *)                  echo "global" ;;
  esac
}

#######################################
# Export ASDF_DATA_DIR and put its shims directory on PATH for this process.
# Globals:
#   ASDF_DATA_DIR (written)
#   PATH (read, written)
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   None
#######################################
ensure_asdf_on_path() {  # ---- 14
  # Default to asdf's own default data directory if the caller's
  # environment hasn't already set ASDF_DATA_DIR.
  export ASDF_DATA_DIR="$(lt_asdf_data_dir)"
  # Only prepend the shims directory if it isn't already on PATH — colons
  # bracket the check so a partial/substring match (e.g. a differently
  # named sibling directory) can't produce a false positive.
  case ":$PATH:" in
    *":$ASDF_DATA_DIR/shims:"*) ;;                      # already present: no-op
    # not present: prepend it
    *) export PATH="$ASDF_DATA_DIR/shims:$PATH" ;;
  esac
}

#######################################
# Make `brew` callable from this process, even if just installed.
# Globals:
#   PATH (read, written)
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   None
#######################################
ensure_brew_on_path() {  # ---- 15
  if command -v brew >/dev/null 2>&1; then
    return
  fi
  local brew_bin
  brew_bin="$(lt_homebrew_prefix)/bin"
  if [ -x "$brew_bin/brew" ]; then
    export PATH="$brew_bin:$PATH"
  fi
}

#######################################
# Re-export the Homebrew build flags needed to compile against keg-only deps.
# Globals:
#   PATH (written)
#   LDFLAGS (written)
#   CPPFLAGS (written)
#   PKG_CONFIG_PATH (written)
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   None
#######################################
ensure_build_flags() {  # ---- 16
  # `brew --prefix` below needs `brew` itself resolvable first.
  ensure_brew_on_path
  # Declared and assigned separately (not inline inside the export) so a
  # failing `brew --prefix`/`lt_homebrew_prefix` (e.g. the formula somehow
  # isn't actually installed) trips `set -e` here instead of being silently
  # swallowed — `export LDFLAGS="...$(cmd)..."` always "succeeds" as a
  # command even if the command substitution inside it failed, masking the
  # real error and leaving LDFLAGS built from an empty/wrong path.
  local homebrew_prefix openssl_prefix readline_prefix sqlite_prefix
  local zlib_prefix prefixes
  homebrew_prefix="$(lt_homebrew_prefix)"
  export PATH="$homebrew_prefix/opt/sqlite/bin:$PATH"
  # One `brew --prefix` call for all four formulas (each spawns brew's own
  # Ruby interpreter, so four separate calls means four avoidable startups)
  # instead of one call per formula. Order matches the arguments, one prefix
  # per line; `set --` (not `read`, which would eat the last line without a
  # trailing newline) re-splits that into positional params on newlines only,
  # same idiom used for SELECT_OPTS/SED_ARGS elsewhere in this codebase.
  prefixes="$(brew --prefix openssl@3 readline sqlite3 zlib)"
  IFS="
"
  # shellcheck disable=SC2086
  set -- $prefixes
  unset IFS
  openssl_prefix="$1" readline_prefix="$2" sqlite_prefix="$3" zlib_prefix="$4"
  export LDFLAGS="-L$openssl_prefix/lib -L$readline_prefix/lib \
-L$sqlite_prefix/lib -L$zlib_prefix/lib"
  export CPPFLAGS="-I$openssl_prefix/include -I$readline_prefix/include \
-I$sqlite_prefix/include -I$zlib_prefix/include"
  export PKG_CONFIG_PATH="$openssl_prefix/lib/pkgconfig:\
$readline_prefix/lib/pkgconfig:$sqlite_prefix/lib/pkgconfig"
}

# binary_for_plugin <asdf-plugin-name>: prints the primary CLI command that
# plugin installs (e.g. "nodejs" -> "node"). Implemented as a `case`
# instead of an associative array (`declare -A`) because bash 3.2 — the
# actual /bin/bash macOS ships — predates associative arrays entirely, and
# `curl | bash` may run under whatever `bash` is first on the user's PATH.
#######################################
# Print the primary CLI binary an asdf plugin installs.
# Globals:
#   None
# Arguments:
#   $1: asdf plugin name
# Outputs:
#   Writes the binary name to STDOUT.
# Returns:
#   None
#######################################
binary_for_plugin() {
  case "$1" in
    nodejs) echo node ;;
    java)   echo java ;;
    python) echo python ;;
    rust)   echo rustc ;;
    golang) echo go ;;
    # unknown plugin: assume the plugin name IS the binary name
    *)      echo "$1" ;;
  esac
}

# lt_companion_for_plugin <asdf-plugin-name> (m-7/TASK-99; python/uv added
# m-12/TASK-121, decision-5): prints the space-separated companion
# plugin(s) this language commonly needs alongside it - a package/build
# manager the base language plugin does NOT already bundle. nodejs's asdf
# plugin installs a bare Node runtime with only npm, so pnpm is a genuinely
# separate, commonly-wanted install; java's plugin installs only a JDK with
# no build tool at all, so gradle is closer to required than optional for
# real projects; python's plugin installs a bare interpreter with only pip,
# so uv (decision-5: chosen over poetry - single-binary install fits this
# repo's asdf-plugin-per-tool model, and leads poetry in both ecosystem
# adoption and asdf plugin activity as of that decision) fills the same gap
# pnpm/gradle fill for their languages. rust and golang have no entry here
# on purpose, not by omission: asdf-rust bundles cargo and the golang
# plugin's `go` binary already includes modules/build tooling, so there's
# no equivalent "separate package manager" gap to fill for them. Same
# `case` pattern as binary_for_plugin() above, for the same bash-3.2-has-
# no-associative-arrays reason. Empty output means "no companion for this
# plugin" - callers must treat that as a valid, common case, not an error.
#######################################
# Print the companion plugin(s) commonly needed alongside a base plugin.
# Globals:
#   None
# Arguments:
#   $1: asdf plugin name
# Outputs:
#   Writes the companion plugin name to STDOUT, or nothing if this plugin
#   has no companion.
# Returns:
#   None
#######################################
lt_companion_for_plugin() {
  case "$1" in
    nodejs) echo pnpm ;;
    java)   echo gradle ;;
    python) echo uv ;;
    *)      echo "" ;;
  esac
}

# flag_for_binary <binary-name>: prints the flag that binary uses to print
# its own version (they're not all the same — `go version` has no dashes,
# `node -v` is a short flag, `java -version` is a single dash, etc).
#######################################
# Print the flag a binary uses to print its own version.
# Globals:
#   None
# Arguments:
#   $1: binary name
# Outputs:
#   Writes the version flag to STDOUT.
# Returns:
#   None
#######################################
flag_for_binary() {
  case "$1" in
    node)   echo -v ;;
    java)   echo -version ;;
    python) echo --version ;;
    rustc)  echo --version ;;
    go)     echo version ;;
    *)      echo --version ;;   # unknown binary: guess the common long flag
  esac
}

# version_core <version-string>: extracts the first X.Y[.Z] numeric version
# substring (e.g. asdf's "temurin-25.0.2+10.0.LTS" -> "25.0.2"). Prints
# nothing (and fails) if the string has no such pattern (e.g. the alias
# "lts"), so callers can skip a version comparison instead of false-warning.
#
# POSIX sh has no [[ =~ ]]/BASH_REMATCH, so this uses sed instead: strip
# every leading non-digit character (`[^0-9]*`, greedy but unable to eat
# into a digit, so it always stops at the *first* digit run — this is what
# gives leftmost-match behavior, same as the old regex), then capture an
# X.Y or X.Y.Z run and discard everything after it. Plain BRE (no -E), so
# this is portable to both BSD and GNU sed without needing -E.
#######################################
# Extract the first X.Y[.Z] numeric version substring from a string.
# Globals:
#   None
# Arguments:
#   $1: version string to extract from
# Outputs:
#   Writes the extracted X.Y[.Z] substring to STDOUT on success; nothing on
#   no match.
# Returns:
#   None
#######################################
version_core() {
  local result
  result="$(printf '%s\n' "$1" |
    sed -n 's/[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\(\.[0-9][0-9]*\)*\).*/\1/p')"
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
}

# LT_VERSION_FETCH_TIMEOUT (m-12/TASK-119): per-network-call timeout, in
# seconds, for lt_upstream_latest_version()'s curl/git calls below.
# Override-able like LT_LOCK_DIR/LT_REPORT_FILE elsewhere in this file, so
# a test can shrink it instead of waiting out a real timeout.
LT_VERSION_FETCH_TIMEOUT="${LT_VERSION_FETCH_TIMEOUT:-5}"

# LT_PYTHON_TAGS_TIMEOUT (TASK-145.2): the python branch below lists
# cpython's ENTIRE tag history (1000+ tags, final releases mixed with
# pre-releases) via `git ls-remote --tags --refs`, unlike every other
# branch here which fetches a few hundred bytes of JSON for a single
# already-latest value - LT_VERSION_FETCH_TIMEOUT's 5s default is tuned
# for that JSON case and this call routinely exceeds it even on a normal
# connection, so lt_run_with_timeout() kills it and the caller silently
# falls back to a stale static default (the feature never actually
# engages). A server-side refs filter (e.g. `refs/tags/v3.*`) was
# considered instead of a bigger budget, but rejected: it would require
# already knowing the latest major.minor to filter for, which is exactly
# what this call exists to discover - filtering could silently miss a
# new major/minor's tags. Given its own larger budget instead.
# Override-able like LT_VERSION_FETCH_TIMEOUT (test can shrink it), so
# not readonly.
LT_PYTHON_TAGS_TIMEOUT="${LT_PYTHON_TAGS_TIMEOUT:-20}"

# LT_LARGE_LIST_TIMEOUT (TASK-169): same reasoning as LT_PYTHON_TAGS_TIMEOUT
# above, for lt_upstream_version_list()'s pnpm and uv branches specifically.
# Measured live: nodejs's own list JSON is ~331KB, but pnpm's npm-registry
# response is ~1.88MB and uv's GitHub Releases response is ~9.65MB - 4x and
# 23x larger respectively, on the same shared 5s LT_VERSION_FETCH_TIMEOUT
# budget every other (small-payload) branch uses. On an ordinary (not
# fast/low-latency) connection either is a plausible single point of
# failure that then trips the session-wide circuit breaker (decision-17)
# for every plugin asked afterward - which is exactly what made companion
# tools (asked after their parent language) look broken while the parent
# itself resolved fine. Override-able like every other *_TIMEOUT above.
LT_LARGE_LIST_TIMEOUT="${LT_LARGE_LIST_TIMEOUT:-20}"

# lt_adoptium_arch: prints the CPU architecture name Adoptium's API expects
# (used by lt_upstream_latest_version's java case below) - different from
# lt_homebrew_prefix's own uname -m mapping only in spelling ("aarch64" vs
# "arm64"), so this can't just reuse that function.
#######################################
# Print the CPU architecture name Adoptium's API expects.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes the Adoptium architecture name ("aarch64" or "x64") to STDOUT.
# Returns:
#   None
#######################################
lt_adoptium_arch() {
  case "$(uname -m)" in
    arm64) echo aarch64 ;;  # Apple Silicon
    *)     echo x64 ;;      # Intel
  esac
}

# lt_json_field <key> [value_prefix] (m-16/TASK-133): reads a JSON body
# from stdin and prints the string value of the first "<key>": "<value>"
# pair, quotes stripped. Factored out of lt_upstream_latest_version below,
# whose pnpm/gradle/golang/java/uv branches each inlined this same
# grep+head+sed sequence (pnpm/gradle were byte-for-byte identical; golang/
# java were prefix variants) - one place to fix the extraction now instead
# of five.
#
# value_prefix, if given, requires the matched value to literally start
# with it and strips it from the printed result - e.g. go.dev's
# "version":"go1.27.1" needs prefix "go" to yield "1.27.1". Omit it for a
# plain string field (pnpm/gradle/java/uv all pass no prefix here; java's
# own "temurin-" decoration is added by its caller afterward, since that
# prefix goes on the *output* rather than stripping one from the *input* -
# a different operation this helper doesn't need to know about).
#
# Same head -1/sed shape as the original inline code: no match still exits
# 0 with empty output (sed processes zero lines cleanly), matching how
# every existing call site/test already treats a missing field as "nothing
# printed", not a hard failure.
#######################################
# Print the string value of the first "<key>":"<value>" pair in a JSON body.
# Globals:
#   None
# Arguments:
#   $1: key — JSON key name to search for
#   $2: (optional) value_prefix the matched value must start with (also
#       stripped from the printed result)
# Outputs:
#   Reads a JSON body from STDIN. Writes the matched field's value to
#   STDOUT, or nothing if no match.
# Returns:
#   None
#######################################
lt_json_field() {
  local key="$1" prefix="${2:-}"
  grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"${prefix}[^\"]*\"" |
    head -1 |
    sed -E "s/.*\"${prefix}([^\"]*)\"\$/\1/"
}

#######################################
# Fetch a plugin's latest stable version from its official upstream index.
# Globals:
#   LT_VERSION_FETCH_TIMEOUT
#   LT_PYTHON_TAGS_TIMEOUT
# Arguments:
#   $1: asdf plugin name
# Outputs:
#   Writes the fetched version string to STDOUT on success; nothing on
#   failure.
# Returns:
#   None
#######################################
lt_upstream_latest_version() {  # ---- 17
  # No up-front `command -v curl` guard here on purpose: every branch below
  # that needs curl (or git, for python) already chains `|| return 1` onto
  # its own call, which catches a missing binary (exit 127) exactly like
  # any other failure - a shared guard would also incorrectly gate the
  # nodejs branch (which shells out to nothing at all).
  local plugin="$1" body lts_major semver
  case "$plugin" in
    nodejs)
      # asdf-nodejs resolves the "lts" alias itself, fresh, at actual
      # `asdf install nodejs lts` time - a network call here would only
      # ever produce a snapshot that's already stale by the time asdf uses
      # it, so this passes the alias straight through instead of
      # pre-resolving it. (This is also why .tool-versions already carries
      # "lts", not a pinned number, for nodejs.)
      echo lts
      ;;
    pnpm)
      # npm registry - the same place asdf-pnpm's own installer downloads
      # pnpm from.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://registry.npmjs.org/pnpm/latest' 2>/dev/null)" || return 1
      printf '%s\n' "$body" | lt_json_field version
      ;;
    gradle)
      # Gradle's own official "current version" API - a single value, no
      # rc/milestone noise to filter (unlike asdf-gradle's list-all).
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://services.gradle.org/versions/current' 2>/dev/null)" || return 1
      printf '%s\n' "$body" | lt_json_field version
      ;;
    golang)
      # go.dev's official download index - first array entry is the
      # current stable release.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://go.dev/dl/?mode=json' 2>/dev/null)" || return 1
      printf '%s\n' "$body" | lt_json_field version go
      ;;
    rust)
      # Rust's official release channel manifest (TOML) - the [pkg.rust]
      # section's version field specifically, since the file also lists
      # cargo/rustfmt/etc.'s own versions under the same "version" key.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://static.rust-lang.org/dist/channel-rust-stable.toml' \
        2>/dev/null)" || return 1
      printf '%s\n' "$body" |
        awk '/^\[pkg\.rust\]/{f=1; next} f && /^version/{print; exit}' |
        sed -E 's/version = "([0-9.]+).*/\1/'
      ;;
    python)
      # No official JSON index with a working "just the latest" server-side
      # filter (python.org's release API doesn't order/filter the way its
      # own docs suggest - checked directly, see TASK-118.1 notes) - cpython's
      # own tags are the next best official source. Tags mix final releases
      # (vX.Y.Z) with pre-releases (vX.Y.ZaN/bN/rcN); filter down to final
      # releases only, then sort each dotted field numerically (macOS's BSD
      # sort has no -V/version-sort, unlike GNU sort) and take the highest.
      #
      # http.lowSpeedLimit/http.lowSpeedTime only catch a transfer that
      # already started and then stalled - they never engage if the
      # connection blackholes during DNS/TCP/TLS handshake, before any byte
      # has moved (TASK-131.2/decision-10). lt_run_with_timeout (TASK-138.1)
      # wraps the whole call in a hard wall-clock kill so that case can't
      # hang past LT_PYTHON_TAGS_TIMEOUT either - the two guards are kept
      # together rather than one replacing the other, since the lowSpeed*
      # flags cost nothing extra and still cover the "slow, not stalled"
      # case a bit more gracefully (git's own clean abort vs. a SIGTERM).
      # Its own larger LT_PYTHON_TAGS_TIMEOUT budget (TASK-145.2), not the
      # shared LT_VERSION_FETCH_TIMEOUT every other branch above uses -
      # listing cpython's entire tag history is a much bigger call than a
      # few hundred bytes of JSON, and routinely overran the 5s default.
      body="$(lt_run_with_timeout "$LT_PYTHON_TAGS_TIMEOUT" git \
        -c http.lowSpeedLimit=1000 \
        -c http.lowSpeedTime="$LT_PYTHON_TAGS_TIMEOUT" \
        ls-remote --tags --refs https://github.com/python/cpython.git \
        2>/dev/null)" || return 1
      printf '%s\n' "$body" |
        awk '{print $2}' |
        sed -n 's#^refs/tags/v##p' |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
        sort -t. -k1,1n -k2,2n -k3,3n |
        tail -1
      ;;
    java)
      # Two-step Eclipse Adoptium (Temurin) lookup: which major version is
      # the current LTS, then that major's latest GA JDK build for this
      # Mac's own architecture. The "semver" field comes back pre-formatted
      # exactly like asdf-java's own version strings (e.g.
      # "25.0.4+101.0.LTS"), so no reformatting is needed beyond prepending
      # "temurin-". os=mac is hardcoded - this repo is macOS-only.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://api.adoptium.net/v3/info/available_releases' \
        2>/dev/null)" || return 1
      lts_major="$(printf '%s\n' "$body" |
        grep -o '"most_recent_lts"[[:space:]]*:[[:space:]]*[0-9]*' |
        grep -o '[0-9]*$')"
      [ -n "$lts_major" ] || return 1
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" "https://api.adoptium.net/v3/assets/latest/$lts_major/hotspot?vendor=eclipse&os=mac&image_type=jdk&architecture=$(lt_adoptium_arch)" 2>/dev/null)" || return 1
      semver="$(printf '%s\n' "$body" | lt_json_field semver)"
      if [ -n "$semver" ]; then
        printf 'temurin-%s\n' "$semver"
      else
        return 1
      fi
      ;;
    uv)
      # uv (m-12/TASK-121, decision-5's companion pick for python) has no
      # official JSON distribution index of its own (unlike the 7 languages
      # above, each with a dedicated official index/API) - GitHub's Releases
      # API is the fallback decision-4 already set aside for exactly this
      # case.
      #
      # TASK-169: this used to hit /releases/latest directly - a second,
      # independent GitHub API call on top of the /releases?per_page=100
      # list call every normal run already needs (ask_version() resolves
      # both the default and the full list for every plugin). GitHub's
      # unauthenticated rate limit (60 req/hour/IP) is easy to exhaust
      # across a few installs while testing, deterministically reproducing
      # "uv's version list/default never resolves" for up to an hour after.
      # Routing through lt_resolve_version_list() (its cache, not a raw
      # lt_upstream_version_list() call) instead means this is a cache hit
      # - not a second network call - whenever TASK-169's sequential
      # prefetch (00_select.sh) already warmed uv's list moments earlier in
      # the same run, which is the common case now. lt_upstream_version_
      # list()'s uv branch already returns newest-first (lt_github_release_
      # tags' contract), so the first line is exactly "latest".
      body="$(lt_resolve_version_list uv 2>/dev/null)" || return 1
      [ -n "$body" ] || return 1
      printf '%s\n' "$body" | head -1
      ;;
    *)
      # Unknown plugin (e.g. this repo's own custom TOOL_VERSIONS_FILE users
      # could pass one this function has no case for): no source to fetch
      # from, so fail like any other lookup miss - callers fall back to the
      # static default.
      return 1
      ;;
  esac
}

# lt_github_release_tags (m-15/TASK-128.1): reads a GitHub Releases API JSON
# array from STDIN and prints every entry's tag_name, one per line, in the
# array's own order (newest first, since that's how GitHub returns it) -
# but only for entries that are neither a draft nor a prerelease. Factored
# out because rust's and uv's lt_upstream_version_list() branches below
# both need this exact same parse (same "one helper instead of two near-
# duplicates" reasoning lt_json_field above was factored out for).
#
# GitHub's response is pretty-printed with tag_name/draft/prerelease as
# sibling fields inside the same release object (confirmed against a live
# fetch) but not reliably adjacent lines the way gradle's/golang's simpler
# state machines below can assume - so this tracks all three per object
# and only decides once "prerelease" (always the last of the three to
# appear) is seen, rather than deciding on every field like those two.
#######################################
# Print every non-draft, non-prerelease tag_name from a GitHub Releases API
# JSON body.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Reads a GitHub Releases API JSON array from STDIN. Writes one tag_name
#   per line to STDOUT for each non-draft, non-prerelease entry.
# Returns:
#   None
#######################################
lt_github_release_tags() {
  awk '
    /"tag_name"[ \t]*:/ {
      tag = $0
      sub(/.*"tag_name"[ \t]*:[ \t]*"/, "", tag)
      sub(/".*/, "", tag)
      next
    }
    /"draft"[ \t]*:/ {
      draft = $0
      sub(/.*"draft"[ \t]*:[ \t]*/, "", draft)
      sub(/,.*/, "", draft)
      next
    }
    /"prerelease"[ \t]*:/ {
      pre = $0
      sub(/.*"prerelease"[ \t]*:[ \t]*/, "", pre)
      sub(/,.*/, "", pre)
      if (tag != "" && draft == "false" && pre == "false") print tag
      tag = ""; draft = ""; pre = ""
      next
    }
  '
}

# lt_upstream_version_list <plugin> (m-15/TASK-128.1, decision-15): fetches
# EVERY version this plugin's official upstream index/API currently lists
# as installable - not just the single latest one lt_upstream_latest_
# version() above returns. Same "no asdf, no plugin required" property as
# that function (decision-15 confirmed all 8 sources need nothing but curl/
# git and the network, so this is just as safe to call from phase 0), and
# the same case-dispatch plugin set, but deliberately kept as a fully
# separate function rather than a second mode grafted onto
# lt_upstream_latest_version() - that function already ships with TASK-
# 119.3's shellspec coverage and is in real use by lt_resolve_default_
# version() below; growing it with a second concern (one value vs. a list)
# would risk a regression in an already-shipped, tested path for no
# benefit a new function doesn't already give just as well.
#
# Prints one version per line, newest first, on success. Returns 1
# (nothing printed) on any failure - same failure contract as
# lt_upstream_latest_version(): missing curl/git, network/DNS failure,
# non-2xx response, empty/unparseable body. Callers must be ready for a
# failure here exactly like that function's callers already are (see
# TASK-128.3, which layers caching on top, and TASK-129's UI, which falls
# back to the existing default-vs-free-text flow on a miss rather than
# growing a fallback into this layer).
#
# Known gap (decision-15's "닫히지 않는 갭", unchanged here since this
# reuses the exact same sources): every version below is what the
# LANGUAGE ITSELF calls installable, not what this repo's asdf plugin for
# it can actually install today - decision-12 already found those two can
# disagree (an asdf plugin can lag its language's own upstream index).
# This function does not cross-check against `asdf list all` - that
# range-fix (if TASK-129's UI needs one) is out of scope here.
#
# nodejs's branch is the one exception to "same plugin set as
# lt_upstream_latest_version()": that function deliberately fetches
# nothing for nodejs (asdf-nodejs resolves the "lts" alias itself at
# install time - see its comment above), but a "list every version"
# request has no equivalent alias to defer to, so this branch fetches
# nodejs.org's own release index instead - "lts" is not a member of the
# list this returns.
#
# Companion tools (m-15/TASK-128.2 - pnpm/gradle/uv, the ones
# lt_companion_for_plugin() above can return): confirmed each one is
# already just a plugin-name branch in the case below like any language -
# 00_select.sh's own lt_offer_language() already calls lt_resolve_default_
# version() (this function's single-value sibling) on a companion's plain
# plugin name with no special-casing, so this function needs none either.
# TASK-128.2's own description flags that a companion COULD be something
# other than a real asdf plugin (see TASK-99/100) - that's not true for
# any companion that exists today, so there's nothing further to branch
# on here; a future companion that genuinely isn't a plugin would need its
# own case below, same as any other new plugin would.
#######################################
# Fetch every version a plugin's official upstream index/API currently
# lists as installable.
# Globals:
#   LT_VERSION_FETCH_TIMEOUT
#   LT_PYTHON_TAGS_TIMEOUT
# Arguments:
#   $1: asdf plugin name
# Outputs:
#   Writes one version per line (newest first) to STDOUT on success;
#   nothing on failure.
# Returns:
#   None
#######################################
lt_upstream_version_list() {
  # Same no-up-front-`command -v` reasoning as lt_upstream_latest_version()
  # above: every branch below already chains `|| return 1`/`|| continue`
  # onto its own curl/git call, which catches a missing binary exactly
  # like any other failure.
  local plugin="$1" body ltses major semver found
  case "$plugin" in
    nodejs)
      # No "lts" shortcut applies to a full list request (unlike the
      # single-value branch above) - nodejs.org's own official release
      # index is the direct equivalent of every other language's source
      # here, so this is the one plugin whose list branch calls the
      # network even though its default-version branch above never does.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://nodejs.org/dist/index.json' 2>/dev/null)" || return 1
      printf '%s\n' "$body" |
        grep -o '"version":"v[0-9][0-9.]*"' |
        sed -E 's/.*"v([0-9.]*)"/\1/'
      ;;
    pnpm)
      # Sibling "everything ever published" endpoint to the /pnpm/latest
      # single-value branch above: the same npm registry document, just
      # without the /latest suffix. The "install-v1" Accept header asks
      # npm for its abbreviated metadata format - still one full record
      # per version (npm has no lighter "just the version numbers"
      # endpoint), but noticeably smaller than the default full-manifest
      # format for no loss here. grep pulls only clean X.Y.Z keys straight
      # out of the "versions" object, dropping dev/beta/rc/pr channel tags
      # (e.g. "6.23.7-202112041634"), then a numeric sort (macOS's BSD
      # sort has no -V, same reason the python branch below needs one)
      # puts them newest-first regardless of the registry's own publish-
      # order listing. LT_LARGE_LIST_TIMEOUT (TASK-169), not the generic
      # LT_VERSION_FETCH_TIMEOUT every small-payload branch uses - this
      # response runs ~1.88MB, measured live, well past what 5s budgets for.
      body="$(curl -fsS --max-time "$LT_LARGE_LIST_TIMEOUT" \
        -H 'Accept: application/vnd.npm.install-v1+json' \
        'https://registry.npmjs.org/pnpm' 2>/dev/null)" || return 1
      printf '%s\n' "$body" |
        grep -oE '"[0-9]+\.[0-9]+\.[0-9]+":\{"name":"pnpm"' |
        sed -E 's/^"([^"]*)".*/\1/' |
        sort -t. -k1,1nr -k2,2nr -k3,3nr
      ;;
    gradle)
      # Sibling "every known build, including snapshots/RCs/milestones"
      # endpoint to /versions/current above - each entry carries its own
      # snapshot/rcFor/milestoneFor flags, so a genuine GA release is one
      # with snapshot=false and both *For fields empty. "version" is
      # always the first field inside each entry (confirmed against a
      # live fetch), so this walks the pretty-printed JSON line by line
      # and flushes/filters the previous entry each time a new "version"
      # line starts the next one - the same "state machine over one awk
      # pass" shape the rust branch above uses for its TOML sections,
      # since this repo has no jq and RS-as-regex is a gawk extension it
      # can't assume macOS's awk supports.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://services.gradle.org/versions/all' 2>/dev/null)" || return 1
      printf '%s\n' "$body" | awk '
        function flush() {
          if (ver != "" && snap == "false" && rc == "" && ms == "") {
            print ver
          }
        }
        /"version"[ \t]*:/ {
          flush()
          ver = $0
          sub(/.*"version"[ \t]*:[ \t]*"/, "", ver)
          sub(/".*/, "", ver)
          snap = ""; rc = ""; ms = ""
          next
        }
        /"snapshot"[ \t]*:/ {
          snap = $0
          sub(/.*"snapshot"[ \t]*:[ \t]*/, "", snap)
          sub(/,.*/, "", snap)
          next
        }
        /"rcFor"[ \t]*:/ {
          rc = $0
          sub(/.*"rcFor"[ \t]*:[ \t]*"/, "", rc)
          sub(/".*/, "", rc)
          next
        }
        /"milestoneFor"[ \t]*:/ {
          ms = $0
          sub(/.*"milestoneFor"[ \t]*:[ \t]*"/, "", ms)
          sub(/".*/, "", ms)
          next
        }
        END { flush() }
      ' |
        sort -t. -k1,1nr -k2,2nr -k3,3nr
      ;;
    golang)
      # go.dev/dl/?mode=json alone (the single-value branch's own source
      # above) is capped at just the 1-2 CURRENTLY stable releases;
      # &include=all is the sibling switch returning every release this
      # index has ever listed, stable and not. Each top-level release
      # object's own "version"/"stable" fields sit at 2-space indent,
      # while those same two field names also recur once per platform
      # file nested inside that release's "files" array at 4-space indent
      # - the 2-space anchor is what keeps this from picking up those
      # nested duplicates. "version"/"stable" are adjacent lines in every
      # release object (confirmed against a live fetch), so a version is
      # held pending until its matching "stable" line resolves it.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://go.dev/dl/?mode=json&include=all' 2>/dev/null)" ||
        return 1
      printf '%s\n' "$body" | awk '
        /^  "version":/ {
          v = $0
          sub(/^  "version": "go/, "", v)
          sub(/".*/, "", v)
          pending = v
          next
        }
        /^  "stable": true/ {
          if (pending != "") print pending
          pending = ""
          next
        }
        /^  "stable": false/ { pending = ""; next }
      '
      ;;
    rust)
      # rust's single-value branch above reads the official channel
      # manifest, but that TOML only ever names the CURRENT stable
      # version - it has no equivalent of a full history, and decision-15
      # explicitly left the full-list source for this task to pick.
      # static.rust-lang.org's own dist/ prefix has no directory-listing
      # endpoint to enumerate (confirmed via a live request - a bare GET
      # there 416s, it's a raw S3 bucket with no index), so this uses
      # rust-lang/rust's official GitHub Releases instead - the same
      # "GitHub Releases as a stand-in for a missing JSON index" fallback
      # decision-4 already set aside for uv below. tag_name comes back
      # bare (e.g. "1.98.1", no "v" prefix, confirmed all-final/no-
      # prerelease in the most recent 100 via a live fetch), matching this
      # plugin's version format directly - no reformatting needed, same as
      # the single-value branch's [pkg.rust] value.
      #
      # per_page=100 (GitHub's max per page) is one page - a couple of
      # years of releases as of this writing, not literally every version
      # rust has ever shipped back to 1.0. Not paginating further is a
      # deliberate choice, not a shortcut: decision-16's own "lazy,
      # occasional, no exhaustive prefetch" reasoning for this whole
      # feature applies just as well to "don't walk 20+ pages of a
      # personal installer's version picker to reach a decade-old
      # release".
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://api.github.com/repos/rust-lang/rust/releases?per_page=100' \
        2>/dev/null)" || return 1
      printf '%s\n' "$body" | lt_github_release_tags
      ;;
    python)
      # Same cpython tag source as the single-value branch above, but
      # keeping every filtered final-release tag instead of the tail -1
      # that branch takes - a descending numeric sort (BSD sort has no -V,
      # same reasoning as that branch's own comment) puts the newest
      # first.
      body="$(lt_run_with_timeout "$LT_PYTHON_TAGS_TIMEOUT" git \
        -c http.lowSpeedLimit=1000 \
        -c http.lowSpeedTime="$LT_PYTHON_TAGS_TIMEOUT" \
        ls-remote --tags --refs https://github.com/python/cpython.git \
        2>/dev/null)" || return 1
      printf '%s\n' "$body" |
        awk '{print $2}' |
        sed -n 's#^refs/tags/v##p' |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
        sort -t. -k1,1nr -k2,2nr -k3,3nr
      ;;
    java)
      # decision-15: "여러 LTS major 나열" - one entry per currently-
      # supported LTS major (available_lts_releases - e.g. 8/11/17/21/25
      # as of this writing), each resolved to its own latest GA build via
      # the same two-step lookup the single-value branch above uses for
      # just the newest major. The array can come back either pretty-
      # printed (one number per line, confirmed via a live fetch) or as a
      # single compact line, so the digits are pulled with a presence
      # check per line rather than assuming one particular layout.
      #
      # A major with no build for this Mac's own architecture (e.g.
      # Adoptium ships no aarch64 JDK for major 8 as of this writing -
      # confirmed via a live request, x64-only) silently drops out of the
      # list instead of failing the whole call, matching every other
      # branch's "empty/unparseable = skip, not abort" contract. Iterated
      # newest-major-first to match every other branch's newest-first
      # convention (available_lts_releases itself comes back oldest-
      # first) - the classic `sed '1!G;h;$!d'` line-reversal idiom, since
      # macOS has no `tac`.
      body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
        'https://api.adoptium.net/v3/info/available_releases' \
        2>/dev/null)" || return 1
      ltses="$(printf '%s\n' "$body" | awk '
        /"available_lts_releases"/ { grab = 1 }
        grab && /[0-9]/ {
          line = $0
          gsub(/[^0-9]/, " ", line)
          gsub(/^ +| +$/, "", line)
          if (line != "") print line
        }
        grab && /\]/ { exit }
      ')"
      [ -n "$ltses" ] || return 1
      ltses="$(printf '%s\n' "$ltses" | sed '1!G;h;$!d')"
      found=false
      for major in $ltses; do
        body="$(curl -fsS --max-time "$LT_VERSION_FETCH_TIMEOUT" \
          "https://api.adoptium.net/v3/assets/latest/$major/hotspot?vendor=eclipse&os=mac&image_type=jdk&architecture=$(lt_adoptium_arch)" \
          2>/dev/null)" || continue
        semver="$(printf '%s\n' "$body" | lt_json_field semver)"
        # `if`, not `[ -n ... ] && printf` - the latter's own exit status
        # (false whenever a major has no build, e.g. no aarch64 JDK for
        # major 8 as of this writing) would otherwise become this whole
        # function's exit status once it's the last thing the last loop
        # iteration runs, wrongly reporting failure - and would abort a
        # `set -eu` caller mid-loop on the exact same false, per this
        # repo's own POSIX pitfall list (docs/shell-style-guide.md).
        if [ -n "$semver" ]; then
          printf 'temurin-%s\n' "$semver"
          found=true
        fi
      done
      # Every major came back empty/unreachable (e.g. a total Adoptium
      # outage right after the available_releases call above somehow still
      # succeeded) - fail like every other branch's "nothing usable ->
      # return 1" contract instead of silently succeeding with no output.
      [ "$found" = true ] || return 1
      ;;
    uv)
      # GitHub Releases list endpoint - see rust's branch above for why
      # per_page=100 (one page) rather than paginating through this repo's
      # full release history (300+ tags as of this writing). The single-
      # value branch above (lt_upstream_latest_version's uv case) no longer
      # hits its own endpoint (TASK-169) - it calls lt_resolve_version_list,
      # which lands here on a cache miss, so this is now the only place uv's
      # GitHub API budget gets spent. LT_LARGE_LIST_TIMEOUT (TASK-169), not
      # the generic LT_VERSION_FETCH_TIMEOUT - this response runs ~9.65MB,
      # measured live, 23x nodejs's own list JSON.
      body="$(curl -fsS --max-time "$LT_LARGE_LIST_TIMEOUT" \
        'https://api.github.com/repos/astral-sh/uv/releases?per_page=100' \
        2>/dev/null)" || return 1
      printf '%s\n' "$body" | lt_github_release_tags
      ;;
    *)
      # Unknown plugin: no source to fetch from, same as the single-value
      # branch above.
      return 1
      ;;
  esac
}

# LT_VERSION_CACHE_FILE / LT_VERSION_CACHE_TTL (m-12/TASK-119.3): where
# lt_resolve_default_version below remembers a plugin's last successfully
# fetched upstream version, and how long (seconds) that memory stays fresh
# before the next call re-fetches instead of trusting it. Deliberately
# under $HOME directly, like LT_REPORT_FILE - not under $ASDF_DATA_DIR,
# since this cache's whole purpose (avoiding a repeat network round-trip
# across nearby installer runs) has nothing to do with asdf's own state and
# shouldn't be wiped by `05_purge_asdf_core.sh`'s `rm -rf $ASDF_DATA_DIR`.
# Both override-able, same pattern as LT_LOCK_DIR/LT_REPORT_FILE, so a test
# can point this at a scratch file/short TTL instead of touching a real
# $HOME or waiting out a real day. 86400s = 24h: this is a personal,
# occasionally-run installer, not a CI job re-invoked every minute - daily
# freshness is already more current than the static .tool-versions it
# replaces, without re-hitting every upstream API on every single run
# during, say, a single afternoon of repeated installs while testing.
LT_VERSION_CACHE_FILE="${LT_VERSION_CACHE_FILE:-$HOME/\
.langtoolchain-version-cache}"
LT_VERSION_CACHE_TTL="${LT_VERSION_CACHE_TTL:-86400}"

# lt_cached_version_lookup <plugin>: prints <plugin>'s cached version if
# LT_VERSION_CACHE_FILE has a line for it written within the last
# LT_VERSION_CACHE_TTL seconds; fails (nothing printed) on a cache miss -
# no file yet, no line for this plugin, or a line older than the TTL.
# Internal to this file - lt_resolve_default_version below is the only
# caller, and the only supported way to read this cache.
#
# Cache line format: "<plugin>|||<unix-epoch>|||<version>", one per plugin,
# same triple-pipe-delimited shape lt_env_var_defs() above already uses for
# its own multi-field lines (none of these fields can contain "|||").
#######################################
# Print a plugin's cached version if it's still fresh.
# Globals:
#   LT_VERSION_CACHE_FILE
#   LT_VERSION_CACHE_TTL
# Arguments:
#   $1: plugin name
# Outputs:
#   Writes the cached version to STDOUT on a fresh cache hit; nothing on a
#   miss.
# Returns:
#   None
#######################################
lt_cached_version_lookup() {
  local plugin="$1" line ts version now
  [ -f "$LT_VERSION_CACHE_FILE" ] || return 1
  # grep finding nothing here is a normal cache miss, not an error - `|| true`
  # keeps that from tripping callers running under `set -e`.
  line="$(grep "^$plugin|||" "$LT_VERSION_CACHE_FILE" 2>/dev/null |
    tail -1)" || true
  [ -n "$line" ] || return 1
  ts="$(printf '%s\n' "$line" | awk -F'\\|\\|\\|' '{print $2}')"
  version="$(printf '%s\n' "$line" | awk -F'\\|\\|\\|' '{print $3}')"
  [ -n "$version" ] || return 1
  # A non-numeric ts (hand-edited/corrupted cache file - this cache is
  # never written with anything but a real `date +%s` epoch) would make the
  # arithmetic comparison below a hard shell error, not just a false
  # result - reject it as a miss instead of letting that abort the caller.
  case "$ts" in
    '' | *[!0-9]*) return 1 ;;
  esac
  now="$(date +%s)"
  # ts in the future (clock stepped back after a transient forward jump,
  # e.g. NTP correction) would make `now - ts` negative, and a negative
  # value is always "< TTL" - misreading a bogus-future entry as
  # permanently fresh instead of treating it as stale like any other
  # untrustworthy timestamp.
  [ "$ts" -le "$now" ] || return 1
  [ $((now - ts)) -lt "$LT_VERSION_CACHE_TTL" ] || return 1
  printf '%s\n' "$version"
}

# lt_cache_version <plugin> <version>: (over)writes <plugin>'s line in
# LT_VERSION_CACHE_FILE with <version> and the current time, replacing any
# previous line for the same plugin (never appending a stale duplicate).
# Internal to this file, same as lt_cached_version_lookup above.
#######################################
# (Over)write a plugin's cached version line in LT_VERSION_CACHE_FILE.
# Globals:
#   LT_VERSION_CACHE_FILE
# Arguments:
#   $1: plugin name
#   $2: version string to cache
# Outputs:
#   None to STDOUT (rewrites LT_VERSION_CACHE_FILE with the new/updated
#   line).
# Returns:
#   None
#######################################
lt_cache_version() {
  local plugin="$1" version="$2" tmp
  tmp="$(mktemp)"
  if [ -f "$LT_VERSION_CACHE_FILE" ]; then
    # No existing line for this plugin is a normal case (first time it's
    # ever been cached), not an error - `|| true` so `set -e` callers don't
    # abort on grep's "found nothing" exit status.
    grep -v "^$plugin|||" "$LT_VERSION_CACHE_FILE" > "$tmp" 2>/dev/null || true
  else
    : > "$tmp"
  fi
  printf '%s|||%s|||%s\n' "$plugin" "$(date +%s)" "$version" >> "$tmp"
  mv "$tmp" "$LT_VERSION_CACHE_FILE"
}

# lt_resolve_default_version <plugin> <static-default> (m-12/TASK-119.2/
# TASK-119.3, decision-4): the actual call site scripts/install/
# 00_select.sh's ask_version() comment refers to. Order of preference:
#
#   1. a fresh (within LT_VERSION_CACHE_TTL) cached value - no network call
#      at all, so re-running the installer soon after a previous run (e.g.
#      while testing, or a `--local` install right after a global one)
#      doesn't re-hit every upstream API for versions it already just
#      fetched.
#   2. a live lt_upstream_latest_version() lookup - cached for next time on
#      success.
#   3. <static-default> (the .tool-versions value 00_select.sh already has
#      on hand) - whenever both of the above come up empty (offline,
#      rate-limited, timeout, unmapped plugin, or simply no cache yet and
#      the live lookup also failed).
#
# Callers never see an empty default, and a completely offline machine
# behaves exactly as it did before m-12: the static .tool-versions value,
# install proceeds unblocked.
#######################################
# Resolve a plugin's default version: fresh cache, else live fetch, else
# the caller's static default.
# Globals:
#   None
# Arguments:
#   $1: plugin name
#   $2: static_default — fallback version if no cached/live value is found
# Outputs:
#   Writes the resolved version string to STDOUT.
# Returns:
#   None
#######################################
lt_resolve_default_version() {
  local plugin="$1" static_default="$2" cached fetched
  cached="$(lt_cached_version_lookup "$plugin" 2>/dev/null)" || cached=""
  if [ -n "$cached" ]; then
    printf '%s\n' "$cached"
    return 0
  fi
  fetched="$(lt_upstream_latest_version "$plugin" 2>/dev/null)" || fetched=""
  if [ -n "$fetched" ]; then
    lt_cache_version "$plugin" "$fetched"
    printf '%s\n' "$fetched"
    return 0
  fi
  printf '%s\n' "$static_default"
}

# LT_VERSION_LIST_CACHE_FILE / LT_VERSION_LIST_CACHE_TTL (m-15/TASK-128.3,
# decision-16): the list-shaped sibling of LT_VERSION_CACHE_FILE/
# LT_VERSION_CACHE_TTL above - a completely separate file/TTL, not a
# reuse. decision-16 chose separation deliberately: the single-value cache
# above already shipped with TASK-119.3's own tested behavior in real use,
# and folding "sometimes a list" into it would mean a new branch inside an
# already-proven function for every reader/caller to reason about, for a
# concern (caching MANY versions) that a same-shaped-but-separate file/
# pair of functions covers just as well with zero risk to the existing
# path. Same "${VAR:-default}" override pattern as every other LT_* file/
# TTL pair in this file (LT_LOCK_DIR, LT_REPORT_FILE, LT_VERSION_CACHE_FILE
# itself) - not readonly, for the same test-can-override reason documented
# next to those. 86400s TTL default matches LT_VERSION_CACHE_TTL's own
# value today, but decision-16 keeps it a distinct variable rather than
# reusing that one - same reasoning this file already applies to keeping
# LT_VERSION_FETCH_TIMEOUT and LT_PYTHON_TAGS_TIMEOUT separate despite
# both starting from a similar-looking budget: two independently-tunable
# knobs cost nothing extra and avoid one setting silently doing double
# duty for two different callers with potentially different freshness
# needs later.
LT_VERSION_LIST_CACHE_FILE="${LT_VERSION_LIST_CACHE_FILE:-$HOME/\
.langtoolchain-version-list-cache}"
LT_VERSION_LIST_CACHE_TTL="${LT_VERSION_LIST_CACHE_TTL:-86400}"

# lt_cached_version_list_lookup <plugin>: prints <plugin>'s cached version
# list (one version per line, same shape lt_upstream_version_list() itself
# prints) if LT_VERSION_LIST_CACHE_FILE has a line for it written within
# the last LT_VERSION_LIST_CACHE_TTL seconds; fails (nothing printed) on a
# cache miss - no file yet, no line for this plugin, or a line older than
# the TTL. Same structure as lt_cached_version_lookup() above (same clock-
# skew/corrupted-timestamp guards, same reasoning for each), just reading
# from the separate list cache file and splitting the stored comma-joined
# value back into one line per version on a hit.
#
# Cache line format: "<plugin>|||<unix-epoch>|||<v1>,<v2>,<v3>,...", one
# per plugin - same triple-pipe-delimited shape as
# LT_VERSION_CACHE_FILE's own lines above, with the third field a comma-
# joined list instead of a single version (decision-16's own chosen
# format; none of this repo's version strings can contain a literal
# comma, so it's a safe separator for every plugin lt_upstream_version_
# list() supports).
#######################################
# Print a plugin's cached version list if it's still fresh.
# Globals:
#   LT_VERSION_LIST_CACHE_FILE
#   LT_VERSION_LIST_CACHE_TTL
# Arguments:
#   $1: plugin name
# Outputs:
#   Writes the cached version list, one version per line, to STDOUT on a
#   fresh cache hit; nothing on a miss.
# Returns:
#   None
#######################################
lt_cached_version_list_lookup() {
  local plugin="$1" line ts joined now
  [ -f "$LT_VERSION_LIST_CACHE_FILE" ] || return 1
  # grep finding nothing here is a normal cache miss, not an error - `|| true`
  # keeps that from tripping callers running under `set -e`.
  line="$(grep "^$plugin|||" "$LT_VERSION_LIST_CACHE_FILE" 2>/dev/null |
    tail -1)" || true
  [ -n "$line" ] || return 1
  ts="$(printf '%s\n' "$line" | awk -F'\\|\\|\\|' '{print $2}')"
  joined="$(printf '%s\n' "$line" | awk -F'\\|\\|\\|' '{print $3}')"
  [ -n "$joined" ] || return 1
  # A non-numeric ts (hand-edited/corrupted cache file - this cache is
  # never written with anything but a real `date +%s` epoch) would make the
  # arithmetic comparison below a hard shell error, not just a false
  # result - reject it as a miss instead of letting that abort the caller.
  case "$ts" in
    '' | *[!0-9]*) return 1 ;;
  esac
  now="$(date +%s)"
  # ts in the future (clock stepped back after a transient forward jump,
  # e.g. NTP correction) would make `now - ts` negative, and a negative
  # value is always "< TTL" - misreading a bogus-future entry as
  # permanently fresh instead of treating it as stale like any other
  # untrustworthy timestamp.
  [ "$ts" -le "$now" ] || return 1
  [ $((now - ts)) -lt "$LT_VERSION_LIST_CACHE_TTL" ] || return 1
  printf '%s\n' "$joined" | tr ',' '\n'
}

# lt_cache_version_list <plugin> <versions>: (over)writes <plugin>'s line
# in LT_VERSION_LIST_CACHE_FILE with <versions> (one version per line, the
# same shape lt_upstream_version_list() prints - e.g. called as
# `lt_cache_version_list "$plugin" "$(lt_upstream_version_list "$plugin")"`)
# and the current time, replacing any previous line for the same plugin
# (never appending a stale duplicate). Same structure as lt_cache_version()
# above, just joining the newline-separated input into the comma-joined
# third field this cache's line format uses.
#######################################
# (Over)write a plugin's cached version list line in
# LT_VERSION_LIST_CACHE_FILE.
# Globals:
#   LT_VERSION_LIST_CACHE_FILE
# Arguments:
#   $1: plugin name
#   $2: versions — one version per line (e.g. lt_upstream_version_list()'s
#       own output)
# Outputs:
#   None to STDOUT (rewrites LT_VERSION_LIST_CACHE_FILE with the new/
#   updated line).
# Returns:
#   None
#######################################
lt_cache_version_list() {
  local plugin="$1" versions="$2" tmp joined
  joined="$(printf '%s\n' "$versions" | tr '\n' ',' | sed 's/,$//')"
  tmp="$(mktemp)"
  if [ -f "$LT_VERSION_LIST_CACHE_FILE" ]; then
    # No existing line for this plugin is a normal case (first time it's
    # ever been cached), not an error - `|| true` so `set -e` callers don't
    # abort on grep's "found nothing" exit status.
    grep -v "^$plugin|||" "$LT_VERSION_LIST_CACHE_FILE" > "$tmp" \
      2>/dev/null || true
  else
    : > "$tmp"
  fi
  printf '%s|||%s|||%s\n' "$plugin" "$(date +%s)" "$joined" >> "$tmp"
  mv "$tmp" "$LT_VERSION_LIST_CACHE_FILE"
}

# LT_VERSION_LIST_UNREACHABLE_FILE (m-15/TASK-129.2, decision-17): a marker
# file whose mere EXISTENCE (its content is never read) is this whole
# script process's circuit breaker for lt_resolve_version_list() below -
# "some earlier plugin in this run already failed a live list fetch, stop
# trying for the rest of them".
#
# A plain in-memory shell variable cannot do this job here, unlike every
# other "${VAR:-default}" tunable in this file: scripts/install/
# 00_select.sh's ask_version() calls lt_resolve_version_list() through a
# command substitution (`version="$(ask_version ...)"`, needed to capture
# the chosen version off ask_version()'s own STDOUT) for every single
# language the user opts into, and POSIX command substitution always runs
# in its own subshell whose variable assignments never propagate back to
# the caller - a variable tripped inside one call would already have
# evaporated by the time the next call starts, defeating the whole point.
# A file on disk has no such boundary: any subshell can create it, and
# every later subshell (including ones from completely separate command
# substitutions) sees it immediately.
#
# $$ - not mktemp - names the default path: mktemp would create (and need
# cleaning up) a file on every single source of this library, even for
# processes that never call lt_resolve_version_list() at all; $$ is stable
# for the whole script's lifetime (POSIX: a subshell/command substitution
# inherits its parent's $$ unchanged - only a real new process gets a new
# one) and this costs nothing until actually tripped for the first time.
# scripts/install/00_select.sh removes this file from its own EXIT trap
# alongside its other temp files. Overridable like every other LT_* file
# path in this file, so a test can point it at its own scratch path.
LT_VERSION_LIST_UNREACHABLE_FILE="${LT_VERSION_LIST_UNREACHABLE_FILE:-\
${TMPDIR:-/tmp}/langtoolchain-version-list-unreachable.$$}"

#######################################
# Resolve a plugin's full version list: fresh cache, else live fetch.
# Globals:
#   LT_VERSION_LIST_UNREACHABLE_FILE (read, written - see its own comment
#     above for why this is a file and not a variable)
# Arguments:
#   $1: plugin name
# Outputs:
#   Writes the version list, one per line (newest first), to STDOUT on
#   success; nothing on failure.
# Returns:
#   0 on success (cache hit or live fetch); 1 if both missed.
#######################################
lt_resolve_version_list() {  # ---- 18
  local plugin="$1" cached fetched
  cached="$(lt_cached_version_list_lookup "$plugin" 2>/dev/null)" || cached=""
  if [ -n "$cached" ]; then
    printf '%s\n' "$cached"
    return 0
  fi
  # Session circuit breaker (decision-17): see LT_VERSION_LIST_UNREACHABLE_
  # FILE's own comment above for why this has to be a file, not a variable.
  if [ -f "$LT_VERSION_LIST_UNREACHABLE_FILE" ]; then
    return 1
  fi
  fetched="$(lt_upstream_version_list "$plugin" 2>/dev/null)" || fetched=""
  if [ -n "$fetched" ]; then
    lt_cache_version_list "$plugin" "$fetched"
    printf '%s\n' "$fetched"
    return 0
  fi
  : > "$LT_VERSION_LIST_UNREACHABLE_FILE"
  return 1
}

# LT_VERSION_MENU_MAX (m-15/TASK-129.2, decision-17): the most version
# options scripts/install/00_select.sh's ask_version() will ever show in
# one lt_arrow_menu() call, enforced by lt_version_menu_options() below.
# lt_arrow_menu() redraws its whole option block in place on every
# keypress, which only stays legible up to roughly a screen's worth of
# lines - node/java's real upstream catalogs run into the hundreds, so
# without a cap the menu would be unusable long before the list ran out.
# lt_upstream_version_list() already returns its list newest-first by
# contract, so capping to the first N is exactly "show the N most recent
# versions", not a random sample. Not readonly, same override-for-tests
# reasoning as every other plain-global tunable in this file.
LT_VERSION_MENU_MAX=15

# lt_version_menu_options <default> (m-15/TASK-129.2, decision-17): reads a
# version list from STDIN (newest first, e.g. lt_resolve_version_list()'s
# own output) and prints the capped, deduped set of ask_version() menu
# option labels - <default> first (suffixed "(default)"), then up to
# LT_VERSION_MENU_MAX - 1 more versions, skipping any entry equal to
# <default> itself so it's never offered twice.
#
# Always returns 0 regardless of whether the read loop below ran zero,
# some, or LT_VERSION_MENU_MAX - 1 times - a `while ... read` whose last
# evaluation is the failing (EOF) read still exits the whole `while`
# construct at 0 per POSIX (a loop's exit status is that of the last
# *body* run, not the failing controlling command), but this is stated
# explicitly rather than left implicit, since ask_version() calls this
# under `set -eu` and any other outcome here would abort that whole
# script.
#######################################
# Build the capped, deduped list of version-menu option labels.
# Globals:
#   LT_VERSION_MENU_MAX
# Arguments:
#   $1: default — the version to pin as the first, highlighted option
# Inputs:
#   STDIN: versions, one per line, newest-first
# Outputs:
#   Writes one menu option label per line to STDOUT.
# Returns:
#   Always 0.
#######################################
lt_version_menu_options() {
  local default="$1" v count
  printf '%s (default)\n' "$default"
  count=1
  while [ "$count" -lt "$LT_VERSION_MENU_MAX" ] && IFS= read -r v; do
    if [ "$v" != "$default" ]; then
      printf '%s\n' "$v"
      count=$((count + 1))
    fi
  done
  return 0
}

# lt_valid_menu_choice <input> <option-count> (TASK-164): is <input> a valid
# 1-based menu selection? Used by scripts/install/00_select.sh's
# lt_arrow_menu() numbered-prompt fallback (stty -g < /dev/tty failing),
# which reads a whole line via `read -r` (not one raw keypress like the
# normal arrow-mode loop's own digit-shortcut classifier), so a two-digit
# choice like "10" is a normal, expected input there - a `case ... in
# [1-9])` glob only ever matches a single character and silently rejected
# every option past 9 before this existed. Lives here rather than in
# 00_select.sh, same reasoning as lt_resolve_version_list/
# lt_version_menu_options above: no /dev/tty access, so it's unit-testable
# directly instead of only through a subprocess.
#######################################
# Check whether a string is a valid 1-based menu selection.
# Globals:
#   None
# Arguments:
#   $1: input — the raw string to validate
#   $2: n — the valid option count
# Outputs:
#   None
# Returns:
#   0 if <input> is all-digits and within 1..<n>; 1 otherwise
#######################################
lt_valid_menu_choice() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le "$2" ]
}

# lt_nth_arg <n> <arg...> (TASK-165, decision-21): print the n-th (1-based)
# remaining argument. POSIX sh has no arrays, so 00_select.sh's per-language
# back-navigation loop keeps its plugin/version pairs as one flat positional-
# parameter list (via `set --`) and needs random-access-by-index into it to
# support stepping the index backward - a plain `while read` over a stream
# can only move forward. Uses `shift` on this function's own copy of the
# arguments (a function call gets its own positional parameters), so the
# caller's own "$@" is untouched.
#######################################
# Print the n-th (1-based) of the remaining arguments.
# Globals:
#   None
# Arguments:
#   $1: n — 1-based index
#   $2..: the list to index into
# Outputs:
#   The n-th argument, to STDOUT
# Returns:
#   None (undefined output if n is out of range - callers control both
#   sides of this list and keep n in range)
#######################################
lt_nth_arg() {
  local n="$1"
  shift
  while [ "$n" -gt 1 ]; do
    shift
    n=$((n - 1))
  done
  printf '%s\n' "$1"
}

# lt_render_version_table (TASK-168): render an SDKMAN `sdk list`-flavored
# numbered table from lt_version_menu_options()'s output (one option label
# per line on stdin, first line already carrying the " (default)" suffix).
# Used only by 00_select.sh's ask_version() when the terminal can't do
# raw-mode arrow-key input (stty -g failing) - that path replaces typing a
# number with a plain Enter/skip walkthrough (lt_version_walkthrough() in
# 00_select.sh), so this table is purely informational: it lets the user
# see every fetched candidate up front before being walked through them one
# at a time. No /dev/tty access here (plain stdin/stdout), so it's
# unit-testable directly, same reasoning as lt_version_menu_options above.
#######################################
# Render a numbered version table from one label per line on stdin.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   A header row, a separator line, and one numbered row per input line,
#   to STDOUT.
# Returns:
#   None
#######################################
lt_render_version_table() {
  local i=1 line
  printf '  %-4s%s\n' '#' '버전'
  printf '  %-4s%s\n' '---' '----------------'
  while IFS= read -r line; do
    printf '  %-4s%s\n' "$i)" "$line"
    i=$((i + 1))
  done
}

# ======== 노트 ========
# 1 빌드 의존 Homebrew 포뮬러의 단일 출처
#   설명: Python(과 관련 런타임)의 C 확장 컴파일에 필요한 Homebrew 포뮬러 목록. 설치 3단계, 제거 4단계, ensure_build_flags()가 모두 이 값 하나를 읽으므로 양쪽이 어긋나지 않는다.
#   단 ensure_build_flags()는 이 중 openssl/readline/sqlite3/zlib 부분집합만 쓴다(자세한 이유는 노트 16).
#   관련: scripts/install/03_install_system_deps.sh, scripts/uninstall/04_remove_system_deps.sh
#   개념: SSOT
# 2 Homebrew 접두사는 CPU 아키텍처별로 한 곳에서 계산
#   설명: Apple Silicon과 Intel의 Homebrew 경로가 다르다. 각 스크립트가 uname -m case를 다시 쓰다 sqlite PATH 줄이 Intel에서 낡았던 사고(TASK-61)를 막으려고 이 함수만 쓴다.
#   현재 CPU 아키텍처 기준 Homebrew 설치 접두사를 출력하며, brew 바이너리나 keg-only 포뮬러의 bin 디렉터리처럼 Homebrew 기준 경로가 필요한 모든 스크립트는 자체 `uname -m` case를 다시 쓰지 말고 이 함수를 불러 계산한다.
#   그 중복 때문에 sqlite PATH 줄이 Intel Mac에서 Apple Silicon 전용 경로로 낡았다.
#   관련: TASK-61
# 3 실제 asdf 데이터 디렉터리 값만 출력
#   설명: ASDF_DATA_DIR 재정의가 있으면 그것, 없으면 기본 ~/.asdf. PATH를 건드리지 않아 제거 검증처럼 값만 필요한 호출자가 쓴다. 경로를 ".asdf"로 하드코딩하면 린트가 잡는다.
#   ensure_asdf_on_path()에서 분리한 함수다. 그쪽은 값을 export하고 PATH까지 건드리므로, asdf를 PATH에 되돌려 놓으면 안 되는 정리(teardown) 검사처럼 값만 필요한 호출자가 같은 "${ASDF_DATA_DIR:-$LT_ASDF_DATA_DIR_DEFAULT}" 폴백을 다시 쓰지 않게 한다.
#   관련: TASK-65, TASK-70, scripts/lint/check-hardcoded-paths.sh
# 4 mkdir 기반 배타 잠금 경로
#   설명: macOS에 flock이 없고 디렉터리 생성은 원자적이라 mkdir를 잠금 기본형으로 쓴다. 테스트가 경로를 바꿀 수 있게 환경변수로 덮어쓸 수 있다.
#   install/main.sh와 uninstall/main.sh가 잠금 하나를 공유한다. 설치가 다른 설치, 제거, 자기 자신과 동시에 돌 수 없게 하려는 것으로, 모두 같은 asdf/Homebrew 상태를 바꾸기 때문이다.
#   실제 파일시스템에서 디렉터리 생성은 원자적이므로 동시에 `mkdir LT_LOCK_DIR`를 해도 하나만 성공한다.
#   `${LT_LOCK_DIR:-기본값}` 꼴은 아래 ASDF_DATA_DIR와 같은 재정의 패턴이라, 테스트나 특수한 호출자가 acquire_lock 안에 특례를 두지 않고도 실제 공유 경로 대신 다른 곳을 가리킬 수 있다.
#   관련: acquire_lock, TASK-84
#   개념: 원자성
# 5 감사 로그는 $HOME 바로 아래
#   설명: 제거 중 rm -rf $ASDF_DATA_DIR가 감사 기록까지 지우지 않도록 데이터 디렉터리 밖에 둔다.
#   설치/제거가 실제로 바꾼 모든 것(무엇을 어디에 설치·제거·수정했는지)을 사람이 읽을 수 있게 남기는 감사 기록이다.
#   LT_LOCAL_PINS_FILE_NAME과 달리 $ASDF_DATA_DIR가 아니라 $HOME 바로 아래에 둔 것은, 제거 직전·직후에 확인하고 싶을 바로 그 이력을 rm -rf가 지우지 않게 하려는 의도다.
#   LT_LOCK_DIR처럼 재정의할 수 있어 테스트가 실제 $HOME 대신 임시 파일을 가리킬 수 있다.
#   관련: TASK-107, m-10
# 6 설치 전 상태 스냅샷 파일 위치
#   설명: 제거가 삭제 여부를 판단할 때 읽는 파일이라 rm -rf $ASDF_DATA_DIR 대상 밖($HOME)에 둔다. 파싱 전용 key=value 형식.
#   이 도구가 손대기 전에 asdf·데이터 디렉터리·플러그인이 이미 있었는지 기록해, 제거(TASK-124)가 이 도구가 만들지 않은 상태를 지우지 않게 한다.
#   LT_REPORT_FILE에 한 줄 더하는 방식이 아니라 별도 파일로 둔 것은 용도가 달라서다. 그쪽은 사람이 읽는 감사 로그(lt_report의 타임스탬프 줄)이고, 이쪽은 제거가 실제 삭제/건너뜀을 결정하려고 파싱하므로 로그 줄의 자유 서식 "detail" 필드가 아닌 안정적인 파싱 전용 형식(lt_snapshot_prior_asdf_state, lt_prior_state_get 참고)이 필요하다.
#   $ASDF_DATA_DIR가 아니라 $HOME 아래에 두는 이유는 LT_REPORT_FILE과 같다. 제거 중 rm -rf가, 그 rm -rf를 할지 판단하려고 곧 읽을 바로 그 파일을 지우면 안 된다.
#   관련: decision-6, TASK-123, TASK-124, m-13
# 7 스냅샷은 한 번만, 어떤 설치 단계보다 먼저
#   설명: asdf·데이터 디렉터리·플러그인이 이 도구 이전부터 있었는지 기록한다. 이미 파일이 있으면 재실행이므로 덮어쓰지 않는다(덮어쓰면 "이 도구가 손대기 전" 기준선이 오염된다). 호출 순서는 호출자(install/main.sh)가 지킨다.
#   asdf(brew list asdf), 그 데이터 디렉터리(lt_asdf_data_dir), asdf 플러그인이 이미 있었는지를 단순한 `key=value` 줄로 LT_PRIOR_STATE_FILE에 쓴다. 이 파일의 유일한 독자는 사람이 아니라 제거(TASK-124.1)의 조건 로직이라 lt_report() 식 타임스탬프 로그 형식을 쓰지 않는다. 형식 전문은 decision-6.
#   asdf를 설치하거나 데이터 디렉터리를 만들 수 있는 어떤 phase(01_bootstrap_asdf.sh)보다도 먼저 돌아야 하며, 그 순서는 호출자의 책임이다. install/main.sh가 언어 선택 직후 phase 루프가 시작되기 전에 호출한다.
#   쓰기는 한 번뿐이다. LT_PRIOR_STATE_FILE이 이미 있으면 이후 호출은 설치 재실행(Ctrl-C 복구, 언어 추가 등)일 수밖에 없고, 그때는 asdf/데이터 디렉터리에 이 도구가 앞선 실행에서 만든 상태가 들어 있을 수 있다. 그때 덮어쓰면 제거가 의존하는 "이 도구가 손대기 전" 기준선이 오염된다.
#   관련: decision-6, TASK-124.1, scripts/install/main.sh
# 8 rc 파일 줄 정의의 단일 출처
#   설명: 설치(04)는 쓸 줄을, 제거(03)는 지울 패턴을 모두 여기서 읽는다. 두 곳이 따로 패턴을 들고 있다가 어긋난 TASK-56(BSD sed가 java-hook 줄을 못 지움)을 막는다. brew shellenv만 prepend다.
#   lt_env_var_defs [java_hook_file] (TASK-64)는 이 도구의 설치기가 관리하는 rc 파일 항목마다 한 줄씩, "<search-pattern>|||<placement>|||<line-to-write>" 형식(필드에 없는 문자라 삼중 파이프 구분자)으로 출력한다.
#   Bash 3.2에는 연관 배열이 없어 구분자로 나눈 평평한 줄 목록이며, `while IFS= read -r def; do ... done < <(lt_env_var_defs ...)`로 읽는다. 줄에 공백이 있어 each_tool()이 .tool-versions 줄을 읽는 것과 같은 모양에 구분자만 다르게 했다.
#   install/04_configure_shell_env.sh는 각 <line-to-write>를 <search-pattern>으로 가드해 쓰고, <placement>("prepend" 또는 "append")에 따라 prepend_env_var 또는 append_env_var를 부른다. 배치 결정을 호출자가 문자열로 알아보게 하지 않고 여기 데이터로 두므로 패턴과 따로 낡을 수 없다.
#   uninstall/03_clean_env_vars.sh는 <search-pattern> 필드만 쓰며 각각을 `sed -E -e '/pattern/d'` 식으로 바꾼다. 둘 다 이 함수 하나를 읽고 각자 패턴을 다시 쓰지 않는다. 그런 어긋남이 TASK-56의 원인이었다(제거 쪽 패턴 사본이 설치 쪽은 맞출 필요가 없던 GNU 전용 정규식 확장을 써서 BSD sed가 java-hook 줄을 못 지움). 새 rc 줄은 여기에 항목 하나만 더하면 설치와 제거가 자동으로 따라온다.
#   java-hook 줄의 내용은 어느 셸 변형을 쓰는지에 달려 있고(설치만 고른 rc 파일로 안다) 호출자가 $1로 넘긴다. 제거는 search-pattern 필드만 읽고 내용은 안 읽으므로 인자를 넘기지 않는다.
#   "brew shellenv"가 유일한 "prepend" 항목이다. asdf shim PATH 줄보다 앞에 와야 이름이 같은 Homebrew 포뮬러가 asdf shim을 가리지 못한다(prepend_env_var의 주석 참고). 나머지는 모두 append.
#   관련: scripts/install/04_configure_shell_env.sh, scripts/uninstall/03_clean_env_vars.sh, TASK-56, TASK-64
#   개념: SSOT
# 9 변경 명령은 모두 run을 거친다(dry-run 게이트)
#   설명: brew install, asdf install, rm -rf 등 시스템을 바꾸는 명령은 직접 부르지 않고 run으로 감싼다. DRY_RUN이면 출력만 한다. "$@"로 인자 경계를 보존한다.
#   run <cmd...>는 dry-run 게이트다. 실제로 시스템을 바꾸는 모든 명령(brew install, asdf install, rm -rf 등)은 직접 호출하지 않고 이것을 거친다.
# 10 지수 백오프 재시도
#   설명: 일시적 실패만 대상으로 하며 소진되면 실패를 그대로 돌려줘 호출자가 판단한다. run과 겹쳐 쓰면 dry-run에서 첫 호출에 끝난다.
#   retry <max_attempts> <delay_seconds> <cmd...>는 <cmd...>가 실패하면 지연이 매번 두 배가 되는 지수 백오프로 최대 <max_attempts>번까지 시도한다. 다운로드 중 네트워크가 잠깐 끊기는 것 같은 진짜 일시적 실패용이고 실제 오류를 고치는 대용품이 아니다. 그래서 시도를 다 쓰면 `|| true`가 아니라 실패를 그대로 반환해 그 의미를 호출자가 정한다.
#   run()과 겹쳐 쓴다: `retry 3 5 run asdf install "$plugin" "$version"`. DRY_RUN에서는 run()이 출력하고 첫 호출에 성공을 반환하므로 retry 루프도 바로 끝나 dry-run 출력이 반복되지 않는다.
#   관련: TASK-88
# 11 POSIX 프리미티브만으로 만든 벽시계 타임아웃
#   설명: timeout/gtimeout은 Homebrew 이전에 없고 프로세스 그룹 kill은 dash에서 동작하지 않는다. 백그라운드 작업 + wait + 감시 서브셸 구조이며, 출력은 파일로 받아 고아 자식이 호출자의 $(...)를 붙잡지 못하게 한다.
#   lt_run_with_timeout <seconds> <cmd> [args...] (TASK-138.1, decision-10)는 <cmd...>를 <seconds> 안에 끝나지 않으면 죽이는 엄격한 벽시계 타임아웃으로 실행한다.
#   필요한 이유: "이미 시작된 전송이 느려졌을 때" 쓰는 가드(curl --max-time, git의 http.lowSpeedLimit/lowSpeedTime. lt_upstream_latest_version의 python 분기 참고)는 바이트가 오가기 전에 연결이 블랙홀이 되는 경우(DNS/TCP/TLS 핸드셰이크 멈춤)에는 아예 작동하지 않고, decision-10은 curl/git 자체 안에 그에 대한 POSIX 안전 해법이 없음을 확인했다.
#   `timeout(1)`/`gtimeout(1)`도 검토 후 기각했다(decision-10). 둘 다 Homebrew가 GNU coreutils를 깔기 전의 새 Mac에는 없는데, 이 함수는 Homebrew 존재가 보장되기 전인 phase 0에서 돌아야 한다.
#   그래서 이 파일의 다른 곳(run_phase())과 같은 모양의 POSIX sh 프리미티브(백그라운드 작업 + `wait`)로 만들었다. <cmd...>를 백그라운드로 돌리고, <seconds>를 자고 아직 살아 있으면 죽이는 감시(watchdog) 서브셸과 경주시킨다.
#   "죽여야 했는지"는 변수가 아니라 표식 파일로 감시 서브셸 밖에 전한다. 백그라운드 작업은 별도 프로세스라 거기서 설정한 변수는 함께 사라지고, 양쪽이 모두 볼 수 있는 것은 파일뿐이다.
#   <cmd...>의 stdout/stderr는 이 함수의 fd에 바로 잇지 않고 임시 파일로 받았다가 나중에 `cat`한다. 편의가 아니라 의도적이다. <cmd...>가 자기 자식을 띄우고(예: https:// URL의 `git ls-remote`는 `git-remote-https` 헬퍼를 exec해 실제 네트워크 일을 한다) 이 함수가 추적한 PID 하나만 죽이면 그 손자가 고아로 남을 수 있다.
#   프로세스 트리 전체에 신호를 보내는 이식 가능한 방법(작업 제어 프로세스 그룹 kill)은 되지 못했다. `set -m`은 bash가 백그라운드 작업마다 자체 프로세스 그룹을 주게 하지만 dash는 그렇지 않음을 직접 확인했고, `kill -TERM -"$cmd_pid"`는 dash에서 아무 데도 닿지 않은 채 조용히 실패한다. 둘 다에서 돌아야 하는 코드베이스에는 쓸 수 없다.
#   <cmd...>의 출력을 호출자의 `$(...)`로 바로 파이프하면 정확히 그 문제를 만난다. 파이프의 읽기 쪽은 쓰기 끝을 연 모든 프로세스가 끝나야 EOF를 보므로, 같은 fd를 쥔 고아 손자가 남아 있으면 이 함수가 아무리 빨리 포기해도 호출자의 `$(...)`가 고아의 남은 수명 내내 막힌다. 일반 파일은 다른 프로세스가 쓰기용으로 열고 있어도 읽기가 막히지 않으므로, 타임아웃 뒤 고아가 (드물게, 무해하게) 어딘가 백그라운드에서 돌고 있어도 호출자가 걸리지 않는다.
#   대가는 버퍼링이다. 실시간 스트리밍하는 호출자는 <cmd...>가 끝나거나 죽을 때까지 아무것도 못 보지만, 여기 호출 지점은 그게 필요 없고 기존 호출자는 모두 어차피 `$(...)`로 출력을 먼저 전부 캡처한다.
#   관련: decision-10, TASK-138.1, install.sh (같은 아이디어의 인라인 사본), run_phase(), lt_upstream_latest_version
# 12 phase를 백그라운드 + wait로 실행
#   설명: 전경 명령은 끝날 때까지 trap을 지연시켜 Ctrl-C 중 잠금이 풀리지 않는다. wait는 trap 신호에 즉시 반환한다. 종료 상태를 그대로 돌려줘야 set -eu가 실패 phase를 멈춘다.
#   run_phase <script>는 phase 스크립트를 평범한 동기식 `sh "$script"` 호출이 아니라 백그라운드 작업 + `wait`로 실행하고 기다린다(TASK-90).
#   trap이 등록된 신호는 평범한 전경 명령이 끝나길 기다리며 막힌 셸을 깨우지 못하고, POSIX 셸은 그 명령이 스스로 반환한 뒤에야 trap을 처리한다. 컴파일 중인 수 분짜리 `asdf install`이면 Ctrl-C/SIGTERM이 컴파일이 자연히 끝날 때까지 처리되지 않고 잠금도 풀리지 않는다.
#   `wait`는 다르다. POSIX가 trap된 신호가 오는 즉시 일찍 반환함을 명시적으로 보장하므로 trap이 바로 발동한다.
#   이는 코드 검토가 아니라 실제 CI 실패로 발견했다. TASK-32의 "설치 도중 kill 후 재실행" 잡이 "another install appears to be running"으로 실패했는데, main.sh가 아직 자기 SIGTERM을 처리하지 못해 첫 실행의 잠금이 회수되지 않은 채 쥐어져 있었기 때문이다.
#   직계 자식만 대상으로 하고 그 아래 후손(예: `asdf install`의 컴파일러 하위 프로세스)은 건드리지 않는다. 재실행이 의존하는 *잠금* 해제를 빠르게 하는 데는 충분하고, 잠시 남는 더 깊은 고아는 이 프로세스가 관리할 몫이 아니다.
#   phase의 종료 상태를 그대로 반환한다. 끝의 `LT_CHILD_PID=""` 대입이 돌려주는 값(항상 0)이 아니어야 호출자의 `set -eu` 아래에서 실패한 phase가 조용히 성공으로 취급되지 않고 실행을 멈춘다.
#   관련: TASK-90, TASK-32, scripts/install/main.sh
# 13 실행 중 잠금 획득과 stale 잠금 회수
#   설명: mkdir 성공이 곧 획득이다. 이미 있으면 기록된 PID가 살아 있는지(kill -0) 보고, 죽었으면 회수한다. 호출자는 바로 뒤에 trap으로 release_lock을 걸어야 한다.
#   acquire_lock (TASK-84)는 LT_LOCK_DIR에 배타 잠금을 잡아 두 설치/제거가 asdf/Homebrew 상태를 동시에 바꾸지 못하게 한다. `mkdir`은 성공(획득)이거나 디렉터리가 이미 있어 실패(남이 쥠)이거나 둘 중 하나뿐이라 경합이 없다.
#   이미 쥐어져 있으면 그 안에 기록된 PID가 아직 살아 있는지 `kill -0`(POSIX 규정, 신호를 보내지 않음)으로 본다. 살아 있으면 진짜 동시 실행이므로 명확한 메시지로 죽는다. 죽었으면 잠금을 쥔 쪽이 자기 `release_lock` trap이 발동하기 전에 죽거나 kill된 것이므로, 앞으로의 모든 실행을 영구히 막지 않도록 낡은 잠금을 회수한다.
#   호출자는 이것을 부른 직후 `trap 'release_lock' EXIT`(또는 기존 결합 trap에 넣기)를 걸어야 한다.
#   관련: TASK-84, lt_die_if_lock_held
# 14 phase 프로세스마다 asdf를 PATH에 보장
#   설명: main.sh가 각 phase를 별도 프로세스로 실행하므로 앞 phase의 export는 이어지지 않는다. 콜론으로 감싼 case 비교로 이미 있는 경우를 건너뛴다.
#   최신 Homebrew asdf(v0.16+, Go 재작성판)는 source할 libexec/asdf.sh가 없는 단일 바이너리라 셸 통합은 $ASDF_DATA_DIR/shims를 PATH에 넣는 것이 전부다. `asdf`나 asdf shim을 부르는 모든 phase가 맨 먼저 이 함수를 불러, 어느 phase도 앞선 phase가 이 프로세스에 무언가 export해 두었기를 기대하지 않는다(main.sh가 각 phase를 별도 `bash` 자식 프로세스로 돌려 아무것도 자동으로 이어지지 않는다).
#   관련: scripts/install/main.sh
# 15 방금 설치된 brew도 이 프로세스에서 호출 가능하게
#   설명: Homebrew 설치기는 PATH를 고치지 않는다. 다른 프로세스에서 막 설치됐을 수 있어 아키텍처별 고정 경로로 직접 폴백한다.
#   *이* 프로세스에서 `brew`를 부를 수 있게 한다. 방금 *다른* phase의 프로세스가 Homebrew를 설치했을 수 있고, main.sh가 각 phase를 별도 `bash` 자식으로 돌리므로 phase 01의 Homebrew 설치에서 export한 것은 이어지지 않는다.
#   Homebrew 설치기는 PATH를 직접 고치지 않고 사용자가 rc 파일에 손으로 넣을 `eval "$(brew shellenv)"` 줄만 출력하며, 그것은 완전히 새 셸에서만 효과가 있다. 우리 쪽 rc 파일 쓰기(04_configure_shell_env.sh 참고)도 지금 돌고 있는 이 설치에는 도움이 되지 않으므로, Homebrew의 아키텍처별 고정 설치 위치 두 곳으로 직접 폴백한다.
#   관련: TASK-78, scripts/install/04_configure_shell_env.sh
# 16 LDFLAGS 등 빌드 플래그 생성
#   설명: export 안에서 명령 치환을 하면 실패가 가려지므로 변수를 먼저 따로 대입해 set -e가 잡게 한다. brew --prefix는 한 번만 불러 Ruby 기동 비용을 줄인다.
#   Python(과 관련 런타임)이 keg-only openssl/readline/sqlite3/zlib을 상대로 컴파일하는 데 필요한 Homebrew 빌드 플래그를 다시 export한다. Homebrew는 keg-only 포뮬러를 PATH나 컴파일러 기본 검색 경로에 일부러 넣지 않으므로, 이 export가 없으면 `asdf install python ...`이 OpenSSL/SQLite 헤더를 못 찾는다.
#   `asdf install`을 도는 phase는 앞선 phase의 export가 아직 유효하다고 믿지 않고 직접 이 함수를 부른다(별도 자식 프로세스이기 때문).
#   LT_BUILD_DEPS 전체 중 이 넷(openssl, readline, sqlite3, zlib)만 컴파일러/링커 플래그가 필요하다. xz와 tcl-tk는 필요 없어 일부러 뺐다.
#   관련: LT_BUILD_DEPS
# 17 기본 버전은 각 언어 공식 소스에서 직접 조회
#   설명: asdf latest는 플러그인이 이미 추가돼 있어야 해서 phase 0에서 쓸 수 없다. 언어별 공식 배포 인덱스/API를 curl(--max-time)이나 git ls-remote로 부른다. 실패하면 호출자가 정적 값으로 폴백한다.
#   lt_upstream_latest_version <plugin> (m-12/TASK-118, decision-4)는 그 플러그인의 최신 안정 버전을 해당 언어의 공식 배포 인덱스/API에서 직접 가져온다. `asdf latest`/`asdf list all`을 일부러 쓰지 않는 이유는 decision-4에 있다. 그것들은 플러그인이 이미 asdf에 추가돼 있어야 하는데 00_select.sh는 phase 0에서 그것을 보장할 수 없다(scripts/install/00_select.sh의 ask_version() 주석 참고).
#   아래 각 분기는 curl(python은 git)과 네트워크 외에는 필요 없고 asdf도 플러그인도 쓰지 않으므로 phase 0에서 바로 불러도 안전하다.
#   성공하면 버전 문자열을 출력한다. curl 없음, 네트워크/DNS 실패, 2xx 아닌 응답, 빈 본문, 파싱 불가 등 어떤 실패에서든 아무것도 출력하지 않고 1을 반환하므로 호출자는 항상 정적 폴백을 준비해야 한다(실제 호출 지점이 모두 쓰는 함수는 아래 lt_default_version).
#   위의 binary_for_plugin()/lt_companion_for_plugin()과 같은 case 분기 방식이며, 이유도 같다. bash 3.2에는 연관 배열이 없다.
#   관련: decision-4, decision-15, TASK-118, m-12, lt_default_version, binary_for_plugin, lt_companion_for_plugin
# 18 버전 목록: 신선한 캐시, 아니면 실시간 조회
#   설명: 정적 폴백이 없어 전부 실패하면 아무것도 출력하지 않고 1을 반환한다. 처리는 호출자(00_select.sh)가 단일 옵션 메뉴로 한다.
#   lt_resolve_version_list <plugin> (m-15/TASK-129.1, decision-17)은 위 lt_resolve_default_version()의 목록판이다. 신선한 캐시, 아니면 실시간 조회(성공 시 캐시), 아니면 실패.
#   그 함수와 달리 완전히 놓쳐도 정적 값으로 폴백하지 않고 아무것도 출력하지 않은 채 1을 반환한다. .tool-versions에는 플러그인당 버전이 하나뿐이라 폴백할 정적 "전체 목록"이 없으므로, 놓친 처리는 전적으로 호출자의 몫이다.
#   현재 호출자는 scripts/install/00_select.sh의 ask_version() 하나이며, 놓쳤을 때의 처리는 decision-17이 정한다. 이미 구한 자기 기본값 하나만 보여 주는 단일 옵션 메뉴로, 예전의 자유 텍스트 입력 폴백을 대체한다.
#   관련: decision-17, TASK-129.1, m-15, scripts/install/00_select.sh, lt_resolve_default_version
