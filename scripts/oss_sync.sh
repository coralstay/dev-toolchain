#!/usr/bin/env sh
# ==============================================================================
# dev-toolchain (oss_sync.sh): Global + Local (.tool-versions) Manager
#
# Hierarchy:
#   1. Global SSOT: ~/githubs/dev-tools/dev-toolchain/.tool-versions
#   2. Local Override: <project>/.tool-versions
#
# Open-Source Container Layout (opensource/in-use/<name>/):
#   ├── upstream/               # Upstream git clone
#   ├── bundles/<ref>.bundle    # Immutable git bundle archive for <ref>
#   ├── <ref>/                  # Materialized version directory (symlink target)
#   └── current -> <ref>        # Active global default symlink
#
# Project Open-Source Symlinks (<project>/.opensource/<name>):
#   <project>/.opensource/<name> -> ~/githubs/opensource/in-use/<name>/<ref>
# ==============================================================================
set -eu

SOURCE="$0"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;
    *) SOURCE="$DIR/$SOURCE" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GITHUBS_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
GLOBAL_FILE="${TOOL_VERSIONS_FILE:-$REPO_ROOT/.tool-versions}"
OPENSOURCE_DIR="$GITHUBS_ROOT/opensource"

[ -f "$GLOBAL_FILE" ] || {
  echo "ERROR: Global .tool-versions not found: $GLOBAL_FILE" >&2
  exit 1
}

each_lang() {
  awk '/^[^# \t]/ {print $1, $2}' "$1"
}

each_oss() {
  awk '/^# @oss / {print $3, $4, $5, $6}' "$1"
}

find_local_files() {
  for d in \
    "$GITHUBS_ROOT/dev-tools"/* \
    "$GITHUBS_ROOT/freeride"/* \
    "$GITHUBS_ROOT/coralstay-software-factory/components"/* \
    "$GITHUBS_ROOT/toy-project"/*; do
    [ -d "$d" ] || continue
    [ -L "$d" ] && continue
    [ -f "$d/.tool-versions" ] || continue
    [ "$d/.tool-versions" = "$GLOBAL_FILE" ] && continue
    echo "$d/.tool-versions"
  done | sort
}

populate_ref_bins() {
  base="$1"
  ref="$2"
  name="$(basename "$base")"

  if [ -d "$base/upstream/bin" ]; then
    mkdir -p "$base/$ref/bin"
    for item in "$base/upstream/bin"/*; do
      [ -e "$item" ] || [ -L "$item" ] || continue
      bname="$(basename "$item")"
      if [ ! -e "$base/$ref/bin/$bname" ] && [ ! -L "$base/$ref/bin/$bname" ]; then
        if [ -L "$item" ]; then
          target="$(readlink "$item")"
          case "$target" in
            /*) ln -sfn "$target" "$base/$ref/bin/$bname" ;;
            *) cp -R "$item" "$base/$ref/bin/$bname" ;;
          esac
        else
          cp -R "$item" "$base/$ref/bin/$bname"
        fi
      fi
    done
  fi

  if [ "$name" = "tmuxinator" ] && [ -x "/opt/homebrew/bin/tmuxinator" ]; then
    mkdir -p "$base/$ref/bin"
    ln -sfn "/opt/homebrew/bin/tmuxinator" "$base/$ref/bin/tmuxinator"
  fi

  if [ "$name" = "checkov" ] && [ -x "/opt/homebrew/bin/checkov" ]; then
    mkdir -p "$base/$ref/bin"
    ln -sfn "/opt/homebrew/bin/checkov" "$base/$ref/bin/checkov"
  fi

  # Fallback: if <ref>/bin is still empty for a Homebrew-installed CLI tool
  # (e.g. after a fresh clone of upstream/), link from /opt/homebrew/bin.
  brew_cmd=""
  case "$name" in
    neovim)   brew_cmd="nvim" ;;
    ripgrep)  brew_cmd="rg" ;;
    tlrc)     brew_cmd="tldr" ;;
    vim|tmux|bat|gh|btop|tig|tokei|jq|yq|shellcheck|shfmt|actionlint|hyperfine|ruff|vulture|sqlfluff|terraform|tflint|terraform-docs|trivy|gitleaks|infracost|conftest|kubeconform|k3d|k6|podman|docker-compose)
      brew_cmd="$name"
      ;;
  esac
  if [ -n "$brew_cmd" ] && [ ! -e "$base/$ref/bin/$brew_cmd" ] && [ -x "/opt/homebrew/bin/$brew_cmd" ]; then
    mkdir -p "$base/$ref/bin"
    ln -sfn "/opt/homebrew/bin/$brew_cmd" "$base/$ref/bin/$brew_cmd"
  fi

  if [ "$name" = "Backlog.md" ]; then
    if [ -d "$base/upstream/dist" ] && [ ! -e "$base/$ref/dist" ]; then
      ln -sfn "../upstream/dist" "$base/$ref/dist"
    fi
    if [ -d "$base/upstream/node_modules" ] && [ ! -e "$base/$ref/node_modules" ]; then
      ln -sfn "../upstream/node_modules" "$base/$ref/node_modules"
    fi
  fi
  return 0
}

materialize_ref() {
  base="$1"
  ref="$2"
  mkdir -p "$base/bundles"
  if [ -f "$base/bundles/${ref}.bundle" ] && [ -d "$base/$ref" ]; then
    populate_ref_bins "$base" "$ref"
    return 0
  fi

  target_commit="HEAD"
  case "$ref" in
    main|master|trunk|0.29.0-dev)
      target_commit="HEAD"
      ;;
    *)
      if git -C "$base/upstream" rev-parse -q --verify "refs/tags/$ref" >/dev/null 2>&1; then
        target_commit="refs/tags/$ref"
      elif git -C "$base/upstream" fetch --depth 1 --quiet origin "refs/tags/$ref:refs/tags/$ref" 2>/dev/null; then
        target_commit="refs/tags/$ref"
      elif git -C "$base/upstream" fetch --depth 1 --quiet origin "refs/tags/v$ref:refs/tags/v$ref" 2>/dev/null; then
        target_commit="refs/tags/v$ref"
      else
        target_commit="HEAD"
      fi
      ;;
  esac

  if [ ! -f "$base/bundles/${ref}.bundle" ]; then
    git -C "$base/upstream" bundle create "$base/bundles/${ref}.bundle" "$target_commit" >/dev/null 2>&1
  fi
  if [ ! -d "$base/$ref" ]; then
    git -C "$base/upstream" worktree add --quiet --detach "$base/$ref" "$target_commit" 2>/dev/null || \
    git -C "$base/upstream" worktree add --force --quiet --detach "$base/$ref" "$target_commit"
  fi
  populate_ref_bins "$base" "$ref"
}

cleanup_stale_branch_refs() {
  base="$1"
  active_ref="$2"
  case "$active_ref" in
    main|master|trunk) return 0 ;;
  esac
  for old_ref in main master trunk; do
    if [ -d "$base/$old_ref" ]; then
      git -C "$base/upstream" worktree remove --force "$base/$old_ref" 2>/dev/null || rm -rf "${base:?}/${old_ref:?}"
    fi
    rm -f "$base/bundles/${old_ref}.bundle"
  done
}

ensure_git_exclude() {
  proj_dir="$1"
  pattern="$2"
  exclude_file="$proj_dir/.git/info/exclude"
  if [ -d "$proj_dir/.git/info" ]; then
    if ! grep -qxF "$pattern" "$exclude_file" 2>/dev/null; then
      echo "$pattern" >> "$exclude_file"
    fi
  fi
}

cmd_status() {
  echo "========================================================"
  echo " [Global SSOT] $GLOBAL_FILE"
  echo "========================================================"
  echo ""
  echo "[1] Global Language Runtimes (asdf)"
  each_lang "$GLOBAL_FILE" | while read -r lang ver; do
    printf "  %-12s : %s\n" "$lang" "$ver"
  done

  echo ""
  echo "[2] Global Open-Source Catalog (@oss)"
  each_oss "$GLOBAL_FILE" | while read -r domain name ref url; do
    if [ "$domain" = "study" ]; then
      dir="$OPENSOURCE_DIR/to-study/$name"
    else
      dir="$OPENSOURCE_DIR/in-use/$name"
    fi
    state="MISSING"
    if [ -d "$dir/upstream/.git" ] && [ -f "$dir/bundles/${ref}.bundle" ] && [ -d "$dir/$ref" ]; then
      state="OK:bundle+ref"
    elif [ -d "$dir/upstream/.git" ] || [ -d "$dir/.git" ]; then
      state="PARTIAL"
    fi
    printf "  [%-6s] %-24s %-12s (%s)\n" "$domain" "$name" "$ref" "$state"
  done

  echo ""
  echo "[3] Local Project Overrides (<project>/.tool-versions & .opensource/)"
  find_local_files | while read -r f; do
    rel="${f#"$GITHUBS_ROOT"/}"
    proj="${rel%/.tool-versions}"
    echo "  * $proj"
    each_lang "$f" | while read -r l v; do
      printf "      [lang] %-22s : %s\n" "$l" "$v"
    done
    each_oss "$f" | while read -r d n r _; do
      printf "      [oss:%-5s] %-17s : %s\n" "$d" "$n" "$r"
    done
  done
}

cmd_current() {
  if [ -f "$PWD/.tool-versions" ] && [ "$PWD/.tool-versions" != "$GLOBAL_FILE" ]; then
    echo "=== Local .tool-versions ($PWD/.tool-versions) ==="
    cat "$PWD/.tool-versions"
  else
    echo "=== No local .tool-versions in $PWD (inheriting Global SSOT) ==="
    each_lang "$GLOBAL_FILE"
  fi
}

cmd_project() {
  filter="${1:-}"
  if [ -z "$filter" ]; then
    echo "Usage: dev-toolchain project <project-name>" >&2
    exit 1
  fi
  find_local_files | grep -i "$filter" | while read -r f; do
    rel="${f#"$GITHUBS_ROOT"/}"
    echo "=== ${rel%/.tool-versions} ($rel) ==="
    cat "$f"
    echo ""
  done
}

cmd_sync() {
  mkdir -p "$OPENSOURCE_DIR/in-use" "$OPENSOURCE_DIR/to-study"
  echo "==> Syncing global @oss repositories & bundles from $GLOBAL_FILE ..."
  each_oss "$GLOBAL_FILE" | while read -r domain name ref url; do
    if [ "$domain" = "study" ]; then
      base="$OPENSOURCE_DIR/to-study/$name"
    else
      base="$OPENSOURCE_DIR/in-use/$name"
    fi
    mkdir -p "$base/bundles"
    if [ ! -d "$base/upstream/.git" ]; then
      echo "  [CLONE]  $name -> $base/upstream"
      git clone --depth 1 --quiet "$url" "$base/upstream"
    fi
    materialize_ref "$base" "$ref"
    cleanup_stale_branch_refs "$base" "$ref"
    ln -sfn "$ref" "$base/current"
    if [ -d "$base/$ref/bin" ]; then
      ln -sfn "current/bin" "$base/bin"
    fi
    if [ -d "$base/$ref/dist" ]; then
      ln -sfn "current/dist" "$base/dist"
    fi
    echo "  [OK]     $name (bundles/${ref}.bundle + ${ref}/)"
  done

  echo "==> Syncing project-specific @oss refs & .opensource/<name> symlinks ..."
  find_local_files | while read -r f; do
    proj_dir="$(dirname "$f")"
    rel_proj="${proj_dir#"$GITHUBS_ROOT"/}"
    has_oss="$(each_oss "$f" | wc -l | tr -d ' ')"
    if [ "$has_oss" -gt 0 ]; then
      mkdir -p "$proj_dir/.opensource"
      ensure_git_exclude "$proj_dir" ".opensource/"
    fi
    each_oss "$f" | while read -r domain name ref _; do
      if [ "$domain" = "study" ]; then
        base="$OPENSOURCE_DIR/to-study/$name"
      else
        base="$OPENSOURCE_DIR/in-use/$name"
      fi
      if [ -d "$base/upstream/.git" ]; then
        materialize_ref "$base" "$ref"
        ln -sfn "$base/$ref" "$proj_dir/.opensource/$name"
        echo "  [LINK]   $rel_proj/.opensource/$name -> opensource/$(basename "$(dirname "$base")")/$name/$ref"
      fi
    done
  done
}

cmd_help() {
  cat <<'EOF'
==============================================================================
 🧰 dev-toolchain — macOS 언어 런타임(asdf) & 오픈소스(@oss) 통합 버전 매니저
==============================================================================

사용법 (Usage):
  dev-toolchain [명령어 또는 설치 플래그]

1. 오픈소스(@oss) & 언어(.tool-versions) 조회·동기화 명령어:
  dev-toolchain status           글로벌 SSOT(.tool-versions)의 언어 8종,
                                 오픈소스 48종(@oss), 프로젝트별 로컬 규칙 전체 출력
  dev-toolchain current          현재 디렉터리($PWD)에 적용되는 로컬 .tool-versions 확인
  dev-toolchain project <이름>   이름이 일치하는 프로젝트의 로컬 .tool-versions 조회
  dev-toolchain sync             글로벌/로컬 .tool-versions의 @oss 목록 기준으로
                                 upstream/ 클론, bundles/<태그>.bundle, <태그>/ 폴더 및
                                 프로젝트별 .opensource/<이름> 심볼릭 링크 일괄 동기화
  dev-toolchain help (--help)    이 도움말 출력

2. 언어 런타임(asdf) 부트스트랩 & 설치 명령어:
  dev-toolchain                  대화형 언어/버전 선택 설치기 실행
  dev-toolchain --all --yes      선택 화면 없이 기본 언어/버전 일괄 설치
  dev-toolchain --dry-run        실제 변경 없이 설치 예정 동작만 미리보기
  dev-toolchain --local[=<dir>]  전역(~/.tool-versions) 대신 로컬 디렉터리에만 버전 고정

3. 제거 명령어:
  dev-toolchain-uninstall [--yes] [--dry-run]
                                 dev-toolchain이 설치한 런타임·플러그인·셸 설정 복원

4. 오픈소스 디렉터리 구조 (opensource/in-use/<이름>/):
  ├── upstream/                  원본 git clone (fetch/업데이트 모체)
  ├── bundles/<버전>.bundle      특정 버전 영구 박제용 git bundle 아카이브
  ├── <버전>/                    다른 프로젝트가 심볼릭 링크로 참조하는 버전별 폴더
  └── current -> <버전>          전역 기본 버전 심볼릭 링크
==============================================================================
EOF
}

case "${1:-status}" in
  status|--status)
    cmd_status
    ;;
  current|--current)
    cmd_current
    ;;
  project|--project)
    shift
    cmd_project "${1:-}"
    ;;
  sync|--sync)
    cmd_sync
    ;;
  help|--help|-h)
    cmd_help
    ;;
  *)
    cmd_help >&2
    exit 1
    ;;
esac
