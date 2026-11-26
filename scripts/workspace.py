#!/usr/bin/env python3
# ---
# title: workspace
# description: ~/githubs 저장소 배치·심볼릭 링크·실행 파일 설치 목록을 목록 파일(workspace/*.tsv)과 비교·복원·기록하는 명령
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# task: TASK-176
# created_date: '2026-11-17'
# updated_date: '2026-11-26'
# ---
# dev-toolchain workspace [status|link|bootstrap|capture] [--dry-run]
# dev-toolchain workspace tools [status|install|capture] [--dry-run]
#
#   status     목록과 지금 머신을 비교해 표로 출력(기본). 어긋남이 있으면 종료 코드 1
#   link       목록에 있는데 없는 링크를 만든다. 대상이 다른 링크는 --force 일 때만 바꾼다
#   bootstrap  없는 저장소만 git clone 한 뒤 link 를 돈다
#   capture    지금 머신을 훑어 workspace/repos.tsv·links.tsv 를 다시 쓴다
#   tools      ~/githubs/bin 명령과 선행 도구의 설치 목록(workspace/tools.tsv, TASK-178):
#              status(기본) 비교, install 빠진 것만 설치, capture bin/* 실체로 다시 쓰기
#
# 표준 라이브러리만 쓰고 macOS 시스템 python3(3.9)에서도 돈다: 새 Mac 에서 asdf 를 깔기 전에
# 워크스페이스부터 복원할 수 있어야 하기 때문이다.
from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
from typing import NamedTuple

# capture 스캔 규칙. 바꾸면 README 의 workspace 절도 함께 고친다.
# - 저장소: 루트 아래 깊이 1..3 의 실제 디렉터리 중 .git 이 있고 origin 이 소유자 접두사로 시작하는 것.
#   심볼릭 링크는 따라가지 않고(링크 너머는 중복), opensource/ 는 .tool-versions(@oss) 몫이라 뺀다.
# - githubs 링크: 루트 깊이 1·2 의 심볼릭 링크(bin/* 포함). 저장소 안으로 더 내려가지 않는다.
# - home 링크: HOME_LINK_DIRS 바로 아래 심볼릭 링크 중 대상이 githubs 루트 안을 가리키는 것.
DEFAULT_OWNER_PATTERNS = ("git@github.com:coralstay/", "https://github.com/coralstay/")
REPO_SCAN_MAX_DEPTH = 3
SCAN_EXCLUDE_TOP = ("opensource",)
SCAN_EXCLUDE_NAMES = (".git", ".venv", "node_modules")
HOME_LINK_DIRS = ("", ".local/bin", ".oh-my-zsh/custom/plugins")
DEFAULT_GIT_TIMEOUT = 300
SCOPES = ("githubs", "home")

REPOS_HEADER = (
    "# workspace/repos.tsv - ~/githubs 아래 저장소 배치 목록 (SSOT, TASK-176)",
    "# 형식: <경로><TAB><원격 URL><TAB><담당>",
    "#   경로: githubs 루트 기준 상대 경로. 경로순 정렬",
    "#   담당(TASK-179): claude(이 저장소들을 맡은 Claude 세션) · antigravity · claude-other(다른 Claude 세션)",
    "#   목록에 없는 경로의 담당 = 그 경로를 품은 가장 가까운 목록 저장소의 담당. 없으면 unknown(유저에게 묻는다)",
    "#   조회: dev-toolchain workspace owner <경로>",
    "# 범위: 깊이 1~3, coralstay 소유 원격만. opensource/ 는 .tool-versions(@oss)가 관리해 뺀다",
    "# 갱신: dev-toolchain workspace capture (손으로 고쳐도 되지만 capture 가 다시 쓴다)",
)
LINKS_HEADER = (
    "# workspace/links.tsv - ~/githubs 워크스페이스가 기대는 심볼릭 링크 목록 (SSOT, TASK-176)",
    "# 형식: <범위><TAB><링크><TAB><대상>",
    "#   범위 githubs: 링크는 githubs 루트 기준 상대 경로 / home: $HOME 기준 상대 경로",
    "#   대상: readlink 값 그대로. 단 $HOME 으로 시작하는 절대 경로는 ~ 로 적는다",
    "# 규칙(TASK-177, tests/test_workspace.py 가 검사):",
    "#   R1 home .local/bin/<명령> 의 대상은 ~/githubs/bin/<같은 이름> (~/githubs/bin 이 유일한 허브)",
    "#   R2 githubs bin/* 와 home .local/bin/* 의 이름 집합이 같다",
    "#   R3 opensource/in-use/<이름>/ 을 가리키는 대상은 버전 폴더가 아니라 current 를 거친다",
    "# 정렬: (범위, 링크)",
    "# 갱신: dev-toolchain workspace capture (손으로 고쳐도 되지만 capture 가 다시 쓴다)",
)

# tools 서브커맨드(TASK-178). 바꾸면 TOOLS_HEADER 와 README 의 '새 Mac 에서 처음부터' 절도 함께 고친다.
TOOL_PROVIDERS = ("brew", "cask", "uv-tool", "oss", "repo", "system", "prereq")
PREREQ_ORDER = ("xcode-clt", "homebrew", "git", "python3", "uv", "java", "claude", "secretive")
PREREQ_METHODS = ("manual", "xcode-clt", "dev-toolchain")  # 그리고 cask:<이름>
PREREQ_CHECKS = ("which", "run", "cask")
BLOCKING_PREREQS = ("xcode-clt", "homebrew")
CHECK_PREFIX = "check: "
BUILD_PREFIX = "build: "
OSS_IN_USE = "opensource/in-use/"
GRADLE_NOTE = "./gradlew installDist"
VENV_NOTE = "uv venv .venv && uv pip install --python .venv -e ."
BREW_SAFE_ENV = {
    "HOMEBREW_NO_INSTALL_UPGRADE": "1",
    "HOMEBREW_NO_INSTALL_CLEANUP": "1",
    "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK": "1",
}
DEFAULT_TOOLS_TIMEOUT = 3600
PROBE_TIMEOUT = 15
TOOLS_HEADER = (
    "# workspace/tools.tsv - ~/githubs/bin 명령과 선행 도구의 설치 목록 (SSOT, TASK-178)",
    "# 형식: <명령><TAB><공급자><TAB><패키지>[<TAB><비고>]",
    "#   brew     Homebrew formula. 패키지 = formula 이름(Cellar 폴더 이름)",
    "#   cask     Homebrew cask. 패키지 = cask 이름",
    "#   uv-tool  uv tool install. 패키지 = 파이썬 패키지 이름",
    "#   oss      dev-toolchain sync(.tool-versions @oss)가 만든다. 패키지 = opensource/in-use/<이름>",
    "#   repo     내 저장소 파일. 패키지 = 저장소 경로(githubs 루트 기준). 비고 'build: <명령>' 은 저장소 안에서 돌릴 빌드",
    "#   system   macOS 기본. 패키지 = 실제 경로. 설치하지 않는다",
    "#   prereq   선행 도구. 명령 = 도구 id, 패키지 = 설치 방법(manual | xcode-clt | dev-toolchain | cask:<이름>),",
    "#            비고 = 확인 방법('check: which <명령>' | 'check: run <명령...>' | 'check: cask <이름>')",
    "#            xcode-clt·homebrew 가 없으면 tools install 은 안내만 하고 멈춘다(sudo·GUI 가 필요해 dev-toolchain install 몫)",
    "# 정렬: prereq 행 먼저(xcode-clt homebrew git python3 uv java claude secretive 순, 그 밖은 이름순), 이어서 명령 이름순",
    "# 갱신: dev-toolchain workspace tools capture (명령 행만 bin/* 실체로 다시 쓰고 prereq 행은 그대로 둔다)",
    "# 새 Mac 에서 처음부터:",
    "#   1. xcode-select --install                          (Xcode Command Line Tools: git·python3)",
    "#   2. curl -fsSL .../dev-toolchain/.../install.sh | sh  (dev-toolchain install: Homebrew·asdf·런타임)",
    "#   3. dev-toolchain workspace bootstrap                (저장소 clone + 링크)",
    "#   4. dev-toolchain sync                               (opensource/in-use)",
    "#   5. dev-toolchain workspace tools install            (brew·cask·uv tool·sync·저장소 빌드·link)",
    "#   6. dev-toolchain workspace status && dev-toolchain workspace tools status",
)


class ManifestError(Exception):
    pass


class Ctx:
    def __init__(self) -> None:
        repo = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
        self.root = os.path.abspath(
            os.environ.get("WORKSPACE_ROOT") or os.path.join(repo, "..", "..")
        )  # ---- 1
        self.home = os.path.abspath(os.environ.get("HOME") or os.path.expanduser("~"))
        self.manifest_dir = os.path.abspath(
            os.environ.get("WORKSPACE_MANIFEST_DIR") or os.path.join(repo, "workspace")
        )
        patterns = os.environ.get("WORKSPACE_OWNER_PATTERNS")
        if patterns:
            self.owner_patterns = tuple(p for p in patterns.split(",") if p)
        else:
            self.owner_patterns = DEFAULT_OWNER_PATTERNS
        self.toolchain_install = os.environ.get("WORKSPACE_TOOLCHAIN_INSTALL") or os.path.join(
            repo, "install.sh"
        )
        self._brew_prefix: str | None = None
        self._brew_prefix_known = False

    @property
    def tools_file(self) -> str:
        return os.path.join(self.manifest_dir, "tools.tsv")

    def brew_prefix(self) -> str | None:
        """Homebrew 접두사(realpath). HOMEBREW_PREFIX, 없으면 'brew --prefix'. Homebrew 가 없으면 None."""
        if not self._brew_prefix_known:
            raw = os.environ.get("HOMEBREW_PREFIX") or ""
            if not raw and shutil.which("brew"):
                try:
                    r = subprocess.run(
                        ["brew", "--prefix"],
                        capture_output=True,
                        text=True,
                        timeout=PROBE_TIMEOUT,
                        check=False,
                    )
                    raw = r.stdout.strip() if r.returncode == 0 else ""
                except (OSError, subprocess.TimeoutExpired):
                    raw = ""
            self._brew_prefix = os.path.realpath(raw) if raw else None  # ---- 2
            self._brew_prefix_known = True
        return self._brew_prefix

    def uv_tool_dir(self) -> str:
        raw = os.environ.get("UV_TOOL_DIR")
        if not raw:
            data = os.environ.get("XDG_DATA_HOME") or os.path.join(self.home, ".local", "share")
            raw = os.path.join(data, "uv", "tools")
        return os.path.realpath(raw)

    @property
    def repos_file(self) -> str:
        return os.path.join(self.manifest_dir, "repos.tsv")

    @property
    def links_file(self) -> str:
        return os.path.join(self.manifest_dir, "links.tsv")

    def base(self, scope: str) -> str:
        return self.root if scope == "githubs" else self.home

    def to_manifest(self, raw: str) -> str:
        if raw == self.home:
            return "~"
        if raw.startswith(self.home + "/"):
            return "~" + raw[len(self.home):]  # ---- 3
        return raw

    def from_manifest(self, target: str) -> str:
        if target == "~":
            return self.home
        if target.startswith("~/"):
            return self.home + target[1:]
        return target


def plan(msg: str) -> None:
    print("  + " + msg)


def read_tsv(path: str, ncols: int, optional: int = 0) -> list:
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        raise ManifestError(f"목록 파일이 없습니다: {path} (먼저 'workspace capture' 로 만드세요)")
    rows = []
    for n, line in enumerate(lines, 1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if not ncols <= len(parts) <= ncols + optional or not all(parts):
            raise ManifestError(f"{path}:{n}: 탭으로 나뉜 값 {ncols}개가 필요합니다: {line!r}")
        rows.append(tuple(parts))
    return rows


OWNERS = ("claude", "antigravity", "claude-other")


def load_repo_rows(ctx: Ctx) -> list:
    rows = read_tsv(ctx.repos_file, 2, optional=1)
    for row in rows:
        if len(row) == 3 and row[2] not in OWNERS:  # ---- 4
            raise ManifestError(f"{ctx.repos_file}: {row[0]} 의 담당 '{row[2]}' 은 {'/'.join(OWNERS)} 중 하나여야 합니다")
    return rows


def load_repos(ctx: Ctx) -> list:
    return [row[:2] for row in load_repo_rows(ctx)]


def load_repo_owners(ctx: Ctx) -> dict:
    return {row[0]: row[2] for row in load_repo_rows(ctx) if len(row) == 3}


def owner_of(ctx: Ctx, path: str) -> str:
    """TASK-179: 경로를 품은 가장 가까운(가장 깊은) 목록 저장소의 담당. 심볼릭 링크를 따라간 실제 경로도 본다."""
    owners = load_repo_owners(ctx)
    raw = path if os.path.isabs(path) else os.path.join(ctx.root, path)
    candidates = {os.path.normpath(raw), os.path.realpath(raw)}
    for rel in sorted(owners, key=lambda r: r.count("/"), reverse=True):  # ---- 5
        base = os.path.join(ctx.root, rel)
        for b in {os.path.normpath(base), os.path.realpath(base)}:
            if any(c == b or c.startswith(b + os.sep) for c in candidates):
                return owners[rel]
    return "unknown"


def cmd_owner(ctx: Ctx, path: str) -> int:
    owner = owner_of(ctx, path)
    print(owner)
    return 1 if owner == "unknown" else 0  # ---- 6


def load_links(ctx: Ctx) -> list:
    rows = read_tsv(ctx.links_file, 3)
    for scope, link, _ in rows:
        if scope not in SCOPES:
            raise ManifestError(f"{ctx.links_file}: 알 수 없는 범위 {scope!r} ({link})")
    return rows


def origin_url(path: str) -> str | None:
    """None: .git 이 없음. '': origin 이 없음."""
    if not os.path.exists(os.path.join(path, ".git")):
        return None
    r = subprocess.run(
        ["git", "-C", path, "remote", "get-url", "origin"],
        capture_output=True,
        text=True,
        check=False,
    )
    return r.stdout.strip() if r.returncode == 0 else ""


def repo_state(ctx: Ctx, rel: str, url: str) -> tuple:
    path = os.path.join(ctx.root, rel)
    if not os.path.lexists(path):
        return "MISSING", ""
    actual = origin_url(path)
    if actual is None:
        return "WRONG-REMOTE", "(git 저장소 아님)"
    if actual != url:
        return "WRONG-REMOTE", actual or "(origin 없음)"
    return "OK", ""


def link_state(ctx: Ctx, scope: str, rel: str, target: str) -> tuple:
    path = os.path.join(ctx.base(scope), rel)
    if not os.path.lexists(path):
        return "MISSING", ""
    if not os.path.islink(path):
        return "NOT-A-LINK", ""
    actual = os.readlink(path)
    if actual != ctx.from_manifest(target):
        return "WRONG-TARGET", ctx.to_manifest(actual)
    if not os.path.exists(path):
        return "DANGLING", ""
    return "OK", ""


def scandir_sorted(path: str) -> list:
    try:
        with os.scandir(path) as it:
            return sorted(it, key=lambda e: e.name)
    except OSError:
        return []


def scan_repos(ctx: Ctx) -> dict:
    found = {}

    def walk(d: str, rel: str, depth: int) -> None:
        for e in scandir_sorted(d):
            if e.name in SCAN_EXCLUDE_NAMES or (depth == 1 and e.name in SCAN_EXCLUDE_TOP):
                continue
            if e.is_symlink() or not e.is_dir(follow_symlinks=False):
                continue
            sub = rel + "/" + e.name if rel else e.name
            url = origin_url(e.path)
            if url and url.startswith(ctx.owner_patterns):
                found[sub] = url
            if depth < REPO_SCAN_MAX_DEPTH:
                walk(e.path, sub, depth + 1)

    walk(ctx.root, "", 1)
    return found


def scan_links(ctx: Ctx) -> dict:
    found = {}
    for e in scandir_sorted(ctx.root):
        if e.name in SCAN_EXCLUDE_NAMES or e.name in SCAN_EXCLUDE_TOP:
            continue
        if e.is_symlink():
            found[("githubs", e.name)] = ctx.to_manifest(os.readlink(e.path))
        elif e.is_dir(follow_symlinks=False):
            for c in scandir_sorted(e.path):
                if c.name not in SCAN_EXCLUDE_NAMES and c.is_symlink():
                    found[("githubs", e.name + "/" + c.name)] = ctx.to_manifest(
                        os.readlink(c.path)
                    )
    roots = {os.path.normpath(ctx.root), os.path.realpath(ctx.root)}
    for sub in HOME_LINK_DIRS:
        d = os.path.join(ctx.home, sub) if sub else ctx.home
        for e in scandir_sorted(d):
            if not e.is_symlink():
                continue
            raw = os.readlink(e.path)
            absolute = os.path.normpath(os.path.join(d, ctx.from_manifest(raw)))
            if any(absolute == r or absolute.startswith(r + "/") for r in roots):
                rel = sub + "/" + e.name if sub else e.name
                found[("home", rel)] = ctx.to_manifest(raw)
    return found


def cmd_status(ctx: Ctx) -> int:
    repos = load_repos(ctx)
    links = load_links(ctx)
    drift = 0
    ok = 0
    owners = load_repo_owners(ctx)
    print(f"[repos] {len(repos)}개  (root: {ctx.to_manifest(ctx.root)})")
    for rel, url in repos:
        state, actual = repo_state(ctx, rel, url)
        extra = f"want {url}  got {actual}" if state == "WRONG-REMOTE" else url
        print(f"  {state:<13} {owners.get(rel, '-'):<12} {rel:<50} {extra}")
        drift += state != "OK"
        ok += state == "OK"
    print(f"[links] {len(links)}개")
    for scope, rel, target in links:
        state, actual = link_state(ctx, scope, rel, target)
        extra = f"want {target}  got {actual}" if state == "WRONG-TARGET" else target
        print(f"  {state:<13} {scope:<8} {rel:<45} -> {extra}")
        drift += state != "OK"
        ok += state == "OK"
    known_repos = {rel for rel, _ in repos}
    known_links = {(s, rel) for s, rel, _ in links}
    extra_repos = sorted((r, u) for r, u in scan_repos(ctx).items() if r not in known_repos)
    extra_links = sorted((k, t) for k, t in scan_links(ctx).items() if k not in known_links)
    print(f"[untracked] {len(extra_repos) + len(extra_links)}개 (목록에 없는 저장소·링크)")
    for rel, url in extra_repos:
        print(f"  {'UNTRACKED':<13} {'repo':<8} {rel:<45} {url}")
    for (scope, rel), target in extra_links:
        print(f"  {'UNTRACKED':<13} {scope:<8} {rel:<45} -> {target}")
    drift += len(extra_repos) + len(extra_links)
    verdict = "일치" if drift == 0 else "어긋남 있음"
    print(f"요약: 정상 {ok}, 어긋남 {drift} -> {verdict}")
    return 0 if drift == 0 else 1


def cmd_link(ctx: Ctx, dry: bool, force: bool) -> int:
    failed = 0
    for scope, rel, target in load_links(ctx):
        state, actual = link_state(ctx, scope, rel, target)
        path = os.path.join(ctx.base(scope), rel)
        want = ctx.from_manifest(target)
        if state == "OK":
            continue
        if state == "DANGLING":
            print(f"  DANGLING      {scope} {rel} -> {target} (링크는 맞음, 대상이 없음)")
            continue
        if state == "NOT-A-LINK":
            print(f"  NOT-A-LINK    {scope} {rel} (실제 파일·폴더라 그대로 둠)")  # ---- 7
            failed += 1
            continue
        try:
            if state == "WRONG-TARGET":
                if not force:
                    print(f"  WRONG-TARGET  {scope} {rel}: want {target} got {actual} (--force 로 교체)")  # ---- 8
                    failed += 1
                    continue
                plan(f"rm {path}")
                if not dry and os.path.islink(path):
                    os.unlink(path)
            parent = os.path.dirname(path)
            if not os.path.isdir(parent):
                plan(f"mkdir -p {parent}")
                if not dry:
                    os.makedirs(parent, exist_ok=True)
            plan(f"ln -s {want} {path}")
            if not dry:
                os.symlink(want, path)
        except OSError as exc:
            print(f"  ERROR         {scope} {rel}: {exc}", file=sys.stderr)
            failed += 1
    if failed:
        print(f"link: {failed}건을 고치지 못했습니다")
    return 1 if failed else 0


def env_timeout(var: str, default: float) -> float:
    raw = os.environ.get(var) or str(default)
    try:
        value = float(raw)
    except ValueError:
        raise ManifestError(f"{var} 이 숫자가 아닙니다: {raw!r}")
    if value <= 0:
        raise ManifestError(f"{var} 은 0보다 커야 합니다: {raw!r}")
    return value


def git_timeout() -> float:
    return env_timeout("WORKSPACE_GIT_TIMEOUT", DEFAULT_GIT_TIMEOUT)


def run_bounded(argv: list, timeout: float, env: dict | None = None, cwd: str | None = None) -> str | None:
    """명령을 돌리고 실패 이유를 돌려준다(성공이면 None). 시간이 넘으면 프로세스 그룹째 죽인다."""
    try:
        proc = subprocess.Popen(argv, env=env, cwd=cwd, start_new_session=True)
    except OSError as exc:
        return f"{argv[0]} 실행 실패: {exc}"
    try:
        rc = proc.wait(timeout=timeout)  # ---- 9
        return None if rc == 0 else f"{argv[0]} 종료 코드 {rc}"
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        return f"timeout: {timeout:g}초 안에 끝나지 않아 중단"


def clone(url: str, dest: str, timeout: float) -> str | None:
    """실패 이유를 돌려준다(성공이면 None). 실패하면 이번에 만든 dest 를 지운다."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    reason = run_bounded(["git", "clone", "--quiet", url, dest], timeout, env=env)
    if reason and os.path.lexists(dest):
        shutil.rmtree(dest, ignore_errors=True)  # ---- 10
    return reason


def cmd_bootstrap(ctx: Ctx, dry: bool) -> int:
    repos = load_repos(ctx)
    timeout = git_timeout()
    failed = 0
    for rel, url in repos:
        state, actual = repo_state(ctx, rel, url)
        if state == "OK":
            continue
        if state == "WRONG-REMOTE":
            print(f"  WRONG-REMOTE  {rel}: want {url} got {actual} (이미 있는 폴더라 그대로 둠)")  # ---- 11
            failed += 1
            continue
        dest = os.path.join(ctx.root, rel)
        plan(f"git clone {url} {dest}")
        if dry:
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        reason = clone(url, dest, timeout)
        if reason:
            print(f"  ERROR         {rel}: {reason}", file=sys.stderr)
            failed += 1
    link_rc = cmd_link(ctx, dry, force=False)
    return 1 if failed or link_rc else 0


def render(header: tuple, rows: list) -> str:
    lines = list(header) + ["\t".join(r) for r in sorted(rows)]  # ---- 12
    return "\n".join(lines) + "\n"


def write_file(path: str, text: str, dry: bool) -> None:
    plan(f"write {path} ({text.count(chr(10))}줄)")
    if dry:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def cmd_capture(ctx: Ctx, dry: bool) -> int:
    repos = scan_repos(ctx)
    links = scan_links(ctx)
    owners = load_repo_owners(ctx) if os.path.exists(ctx.repos_file) else {}
    rows = [(rel, url, owners[rel]) if rel in owners else (rel, url) for rel, url in repos.items()]  # ---- 13
    write_file(ctx.repos_file, render(REPOS_HEADER, rows), dry)
    write_file(
        ctx.links_file, render(LINKS_HEADER, [(s, r, t) for (s, r), t in links.items()]), dry
    )
    by_scope = {s: sum(1 for k in links if k[0] == s) for s in SCOPES}
    print(f"capture: 저장소 {len(repos)}, 링크 githubs {by_scope['githubs']} + home {by_scope['home']}")
    return 0


# ======== tools: ~/githubs/bin 명령과 선행 도구 (TASK-178) ========


class Tool(NamedTuple):
    cmd: str
    provider: str
    package: str
    note: str
    line: str

    @property
    def is_prereq(self) -> bool:
        return self.provider == "prereq"


def parse_check(note: str) -> tuple | None:
    if not note.startswith(CHECK_PREFIX):
        return None
    words = note[len(CHECK_PREFIX):].split()
    if len(words) < 2 or words[0] not in PREREQ_CHECKS:
        return None
    return words[0], words[1:]


def validate_tool(path: str, n: int, t: Tool) -> None:
    where = f"{path}:{n}"
    if t.provider not in TOOL_PROVIDERS:
        raise ManifestError(f"{where}: 알 수 없는 공급자 {t.provider!r} ({t.cmd})")
    if t.is_prereq:
        if parse_check(t.note) is None:
            raise ManifestError(f"{where}: prereq 비고는 'check: which|run|cask <인자>' 여야 합니다: {t.line!r}")
        if t.package not in PREREQ_METHODS and not t.package.startswith("cask:"):
            raise ManifestError(f"{where}: 알 수 없는 설치 방법 {t.package!r} ({t.cmd})")
    elif t.provider == "repo" and t.note and not t.note.startswith(BUILD_PREFIX):
        raise ManifestError(f"{where}: repo 비고는 'build: <명령>' 이어야 합니다: {t.line!r}")


def load_tools(ctx: Ctx) -> list:
    path = ctx.tools_file
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        raise ManifestError(f"목록 파일이 없습니다: {path} (먼저 'workspace tools capture' 로 만드세요)")
    rows = []
    seen = set()
    for n, line in enumerate(lines, 1):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) not in (3, 4) or not all(parts):
            raise ManifestError(f"{path}:{n}: 탭으로 나뉜 값 3~4개가 필요합니다: {line!r}")
        t = Tool(parts[0], parts[1], parts[2], parts[3] if len(parts) == 4 else "", line)
        validate_tool(path, n, t)
        key = (t.is_prereq, t.cmd)
        if key in seen:
            raise ManifestError(f"{path}:{n}: 같은 이름이 두 번 나옵니다: {t.cmd}")
        seen.add(key)
        rows.append(t)
    return rows


def bin_links(ctx: Ctx) -> dict:
    """links.tsv 의 githubs bin/<명령> -> 대상."""
    return {
        link[len("bin/"):]: target
        for scope, link, target in load_links(ctx)
        if scope == "githubs" and link.startswith("bin/")
    }


def under(path: str, base: str | None) -> bool:
    return bool(base) and (path == base or path.startswith(base + "/"))


def parts_below(path: str, base: str) -> list:
    return path[len(base) + 1:].split("/")


def prereq_ok(ctx: Ctx, t: Tool) -> bool:
    kind, args = parse_check(t.note)
    if kind == "which":
        return shutil.which(args[0]) is not None
    if kind == "cask":
        prefix = ctx.brew_prefix()
        return bool(prefix) and os.path.isdir(os.path.join(prefix, "Caskroom", args[0]))
    try:
        r = subprocess.run(
            args,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=PROBE_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0


def prereq_guide(t: Tool) -> str:
    if t.package == "manual":
        return "xcode-select --install 로 Xcode Command Line Tools 를 설치하세요 (GUI 확인이 필요해 직접 하지 않음)"
    if t.package == "xcode-clt":
        return "Xcode Command Line Tools 에 들어 있습니다: xcode-select --install"
    if t.package == "dev-toolchain":
        return "dev-toolchain install (curl ... | sh) 로 설치하세요 (Homebrew·asdf·런타임 담당)"
    return f"brew install --cask {t.package[len('cask:'):]}"


def find_repo(real: str, root: str) -> str | None:
    d = os.path.dirname(real)
    while under(d, root) and d != root:
        if os.path.exists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return None


def build_note(real: str, repo: str) -> str:
    """repo 명령의 빌드 방법을 실체 경로 모양으로 짐작한다. 모르면 ''."""
    def cd(d: str) -> str:
        return "" if d == repo else f"cd {os.path.relpath(d, repo)} && "

    if "/build/install/" in real:
        d = real.split("/build/install/", 1)[0]
        while under(d, repo):
            if any(os.path.exists(os.path.join(d, g)) for g in ("build.gradle.kts", "build.gradle")):
                return BUILD_PREFIX + cd(d) + GRADLE_NOTE
            d = os.path.dirname(d)
    if "/.venv/bin/" in real:
        d = real.split("/.venv/bin/", 1)[0]
        if under(d, repo):
            return BUILD_PREFIX + cd(d) + VENV_NOTE
    return ""


def classify(ctx: Ctx, real: str) -> tuple | None:
    """실체 경로 -> (공급자, 패키지, 버전, 빌드 비고). 분류할 수 없으면 None."""
    prefix = ctx.brew_prefix()
    for provider, sub in (("brew", "Cellar"), ("cask", "Caskroom")):
        base = os.path.join(prefix, sub) if prefix else None
        if under(real, base):
            parts = parts_below(real, base)
            return provider, parts[0], parts[1] if len(parts) > 1 else "", ""
    uv_dir = ctx.uv_tool_dir()
    if under(real, uv_dir):
        return "uv-tool", parts_below(real, uv_dir)[0], "", ""
    root = os.path.realpath(ctx.root)
    oss = os.path.join(root, OSS_IN_USE.rstrip("/"))
    if under(real, oss):
        return "oss", parts_below(real, oss)[0], "", ""
    if under(real, root):
        repo = find_repo(real, root)
        if repo is None:
            return None
        return "repo", os.path.relpath(repo, root), "", build_note(real, repo)
    if under(real, os.path.realpath(ctx.home)):
        return None
    return "system", real, "", ""


def bin_path(ctx: Ctx, t: Tool) -> str:
    return os.path.join(ctx.root, "bin", t.cmd)


def tool_state(ctx: Ctx, t: Tool) -> tuple:
    if t.is_prereq:
        return ("OK" if prereq_ok(ctx, t) else "MISSING"), ""
    path = bin_path(ctx, t)
    if not os.path.exists(path):
        return "MISSING", ""
    real = os.path.realpath(path)
    got = classify(ctx, real)
    if got is None:
        return "WRONG-PROVIDER", f"got (분류 못 함) {ctx.to_manifest(real)}"
    if (got[0], got[1]) != (t.provider, t.package):
        return "WRONG-PROVIDER", f"got {got[0]} {got[1]}"
    return "OK", got[2]


def cmd_tools_status(ctx: Ctx) -> int:
    rows = load_tools(ctx)
    hub = set(bin_links(ctx))
    cmds = [t for t in rows if not t.is_prereq]
    drift = 0
    ok = 0
    print(f"[tools] 선행 도구 {len(rows) - len(cmds)} + 명령 {len(cmds)}  (목록: {ctx.to_manifest(ctx.tools_file)})")
    for t in rows:
        state, detail = tool_state(ctx, t)
        if state == "WRONG-PROVIDER":
            extra = f"want {t.provider} {t.package}  {detail}"
        else:
            extra = f"{t.package} {detail}".rstrip()
        print(f"  {state:<15} {t.provider:<8} {t.cmd:<24} {extra}")
        drift += state != "OK"
        ok += state == "OK"
    names = {t.cmd for t in cmds}
    unlisted = sorted(hub - names)
    extra_rows = sorted(names - hub)
    print(f"[bin 대조] links.tsv githubs bin/* {len(hub)}개 vs tools.tsv 명령 {len(names)}개")  # ---- 14
    for n in unlisted:
        print(f"  {'UNLISTED':<15} {n} (links.tsv 에만 있음)")
    for n in extra_rows:
        print(f"  {'EXTRA':<15} {n} (tools.tsv 에만 있음)")
    drift += len(unlisted) + len(extra_rows)
    verdict = "일치" if drift == 0 else "어긋남 있음"
    print(f"요약: 정상 {ok}, 어긋남 {drift} -> {verdict}")
    return 0 if drift == 0 else 1


class Step(NamedTuple):
    text: str
    argv: list
    env: dict | None = None
    cwd: str | None = None


def plan_install(ctx: Ctx, rows: list, casks: set) -> tuple:
    """빠진 것만 골라 ②~⑥ 단계를 순서대로 만든다. (단계 목록, 실패 수)."""
    prefix = ctx.brew_prefix()
    uv_dir = ctx.uv_tool_dir()
    targets = bin_links(ctx)
    cmds = [t for t in rows if not t.is_prereq]

    def present(t: Tool) -> bool:
        return os.path.exists(bin_path(ctx, t))

    def kept(sub: str, name: str) -> bool:
        return bool(prefix) and os.path.isdir(os.path.join(prefix, sub, name))

    formulas = sorted({t.package for t in cmds if t.provider == "brew" and not kept("Cellar", t.package)})  # ---- 15
    casks = casks | {t.package for t in cmds if t.provider == "cask" and not kept("Caskroom", t.package)}
    uv_tools = sorted(
        {
            t.package
            for t in cmds
            if t.provider == "uv-tool" and not os.path.isdir(os.path.join(uv_dir, t.package))
        }
    )
    need_sync = any(
        not present(t)
        and (t.provider == "oss" or (t.provider in ("brew", "cask") and OSS_IN_USE in targets.get(t.cmd, "")))
        for t in cmds
    )
    brew_env = dict(os.environ, **BREW_SAFE_ENV)
    steps = []  # ---- 16
    if formulas:
        steps.append(Step("brew install --formula " + " ".join(formulas), ["brew", "install", "--formula", *formulas], brew_env))
    if casks:
        names = sorted(casks)
        steps.append(Step("brew install --cask " + " ".join(names), ["brew", "install", "--cask", *names], brew_env))
    for pkg in uv_tools:
        steps.append(Step(f"uv tool install {pkg}", ["uv", "tool", "install", pkg]))
    if need_sync:
        argv = ["sh", ctx.toolchain_install, "sync"]
        steps.append(Step(" ".join(argv), argv))
    failed = 0
    seen = set()
    for t in cmds:
        if t.provider != "repo" or not t.note or present(t):
            continue
        repo_dir = os.path.join(ctx.root, t.package)
        cmd = t.note[len(BUILD_PREFIX):]
        if not os.path.isdir(repo_dir):
            print(f"  MISSING         repo     {t.cmd}: 저장소 {t.package} 가 없습니다 (먼저 'workspace bootstrap')")
            failed += 1
            continue
        if (repo_dir, cmd) not in seen:
            seen.add((repo_dir, cmd))
            steps.append(Step(f"(cd {repo_dir} && {cmd})", ["sh", "-c", cmd], cwd=repo_dir))
    return steps, failed


def cmd_tools_install(ctx: Ctx, dry: bool) -> int:
    rows = load_tools(ctx)
    timeout = env_timeout("WORKSPACE_TOOLS_TIMEOUT", DEFAULT_TOOLS_TIMEOUT)
    missing = [t for t in rows if t.is_prereq and not prereq_ok(ctx, t)]
    blocking = [t for t in missing if t.cmd in BLOCKING_PREREQS]
    if blocking:  # ---- 17
        for t in blocking:
            print(f"  MISSING         prereq   {t.cmd}: {prereq_guide(t)}")
        print("tools install: 선행 도구가 없어 아무것도 하지 않고 멈춥니다. 위 안내대로 설치한 뒤 다시 실행하세요")
        return 1
    failed = 0
    casks = set()
    for t in missing:
        if t.package.startswith("cask:"):
            casks.add(t.package[len("cask:"):])
        else:
            print(f"  MISSING         prereq   {t.cmd}: {prereq_guide(t)}")
            failed += 1
    steps, build_failed = plan_install(ctx, rows, casks)
    failed += build_failed
    if any(s.argv[0] == "brew" for s in steps) and not shutil.which("brew"):
        print("  MISSING         prereq   homebrew: dev-toolchain install (curl ... | sh) 로 설치하세요")
        print("tools install: Homebrew 가 없어 아무것도 하지 않고 멈춥니다")
        return 1
    if not steps and not failed:
        print("tools install: 할 일 없음 (빠진 실행 파일이 없습니다)")
    for s in steps:
        plan(s.text)
        if dry:  # ---- 18
            continue
        reason = run_bounded(s.argv, timeout, env=s.env, cwd=s.cwd)
        if reason:
            print(f"  ERROR         {s.text}: {reason}", file=sys.stderr)
            failed += 1
    link_rc = cmd_link(ctx, dry, force=False)
    return 1 if failed or link_rc else 0


def prereq_sort_key(t: Tool) -> tuple:
    if t.cmd in PREREQ_ORDER:
        return (0, PREREQ_ORDER.index(t.cmd), "")
    return (1, 0, t.cmd)


def cmd_tools_capture(ctx: Ctx, dry: bool) -> int:
    existing = load_tools(ctx) if os.path.exists(ctx.tools_file) else []
    prereqs = sorted((t for t in existing if t.is_prereq), key=prereq_sort_key)
    old = {t.cmd: t for t in existing if not t.is_prereq}
    lines = []
    for e in scandir_sorted(os.path.join(ctx.root, "bin")):
        got = classify(ctx, os.path.realpath(e.path)) if os.path.exists(e.path) else None
        if got is None:
            if e.name in old:
                print(f"  KEEP          {e.name}: 실체를 분류할 수 없어 기존 행을 그대로 둠")
                lines.append(old[e.name].line)
            else:
                print(f"  SKIP          {e.name}: 실체를 분류할 수 없고 기존 행도 없음 (손으로 추가하세요)")
            continue
        provider, package, _, note = got
        prev = old.get(e.name)
        if not note and prev and (prev.provider, prev.package) == (provider, package):
            note = prev.note
        lines.append("\t".join([e.name, provider, package] + ([note] if note else [])))
    body = [t.line for t in prereqs] + lines  # ---- 19
    write_file(ctx.tools_file, "\n".join(list(TOOLS_HEADER) + body) + "\n", dry)
    print(f"capture: 선행 도구 {len(prereqs)}(보존) + 명령 {len(lines)}")
    return 0


def cmd_tools(ctx: Ctx, sub: str, dry: bool) -> int:
    if sub == "install":
        return cmd_tools_install(ctx, dry)
    if sub == "capture":
        return cmd_tools_capture(ctx, dry)
    return cmd_tools_status(ctx)


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--dry-run",
        action="store_true",
        default=argparse.SUPPRESS,
        help="바꾸지 않고 할 일만 '  + ' 줄로 출력 (DRY_RUN=true 와 같음)",
    )
    p = argparse.ArgumentParser(
        prog="dev-toolchain workspace",
        parents=[common],
        description="~/githubs 저장소 배치·심볼릭 링크를 workspace/*.tsv 목록과 맞춘다",
    )
    sub = p.add_subparsers(dest="cmd", metavar="{status,link,bootstrap,capture,owner,tools}")
    sub.add_parser("status", parents=[common], help="목록과 비교해 출력(기본). 어긋나면 종료 1")
    lp = sub.add_parser("link", parents=[common], help="없는 링크 만들기")
    lp.add_argument("--force", action="store_true", help="대상이 다른 링크도 목록대로 바꾼다")
    sub.add_parser("bootstrap", parents=[common], help="없는 저장소 clone 후 link")
    sub.add_parser("capture", parents=[common], help="지금 머신을 목록 파일로 기록")
    op = sub.add_parser("owner", parents=[common], help="경로의 담당 에이전트(claude·antigravity·claude-other, 모르면 unknown·종료 1)")
    op.add_argument("path", help="githubs 루트 기준 상대 경로 또는 절대 경로")
    tp = sub.add_parser(
        "tools",
        parents=[common],
        help="~/githubs/bin 명령과 선행 도구의 설치 목록(workspace/tools.tsv)",
        description="~/githubs/bin 명령과 선행 도구를 workspace/tools.tsv 목록과 비교·설치·기록한다",
    )
    tsub = tp.add_subparsers(dest="tools_cmd", metavar="{status,install,capture}")
    tsub.add_parser("status", parents=[common], help="행마다 OK/MISSING/WRONG-PROVIDER, bin/* 대조(기본). 어긋나면 종료 1")
    tsub.add_parser(
        "install",
        parents=[common],
        help="빠진 것만 설치: prereq 확인 -> brew -> cask -> uv tool -> dev-toolchain sync -> 저장소 빌드 -> link",
    )
    tsub.add_parser("capture", parents=[common], help="bin/* 실체로 명령 행을 다시 쓴다(prereq 행은 보존)")
    return p


def main(argv: list | None = None) -> int:
    args = build_parser().parse_args(argv)  # ---- 20
    dry = bool(getattr(args, "dry_run", False)) or (
        os.environ.get("DRY_RUN", "").strip().lower() in ("1", "true", "yes")
    )
    ctx = Ctx()
    cmd = args.cmd or "status"
    tools_cmd = getattr(args, "tools_cmd", None) or "status"
    if dry and cmd not in ("status", "owner") and not (cmd == "tools" and tools_cmd == "status"):
        print("(dry-run: 아무것도 바꾸지 않습니다)")
    try:
        if cmd == "tools":
            return cmd_tools(ctx, tools_cmd, dry)
        if cmd == "link":
            return cmd_link(ctx, dry, args.force)
        if cmd == "bootstrap":
            return cmd_bootstrap(ctx, dry)
        if cmd == "capture":
            return cmd_capture(ctx, dry)
        if cmd == "owner":
            return cmd_owner(ctx, args.path)
        return cmd_status(ctx)
    except ManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

# ======== 노트 ========
# 1 githubs 루트·HOME·목록 위치 결정
#   설명: 스크립트 실제 위치(심볼릭 링크를 풀어서)의 저장소 두 단계 위를 githubs 루트로 본다. oss_sync.sh 와 같은 가정이다. 테스트는 WORKSPACE_ROOT·WORKSPACE_MANIFEST_DIR·HOME 으로 바꿔 진짜 머신을 건드리지 않는다.
#   관련: scripts/oss_sync.sh (노트 1), tests/test_workspace.py
# 2 Homebrew 위치를 하드코딩하지 않음
#   설명: HOMEBREW_PREFIX 가 있으면 쓰고, 없으면 brew --prefix 로 묻는다. Cellar·Caskroom 경로는 여기서 만든다. arm64·Intel 위치가 다르고 check-hardcoded-paths 린트가 /opt/homebrew 리터럴을 막는다.
#   관련: scripts/lib.sh lt_homebrew_prefix, scripts/lint/check-hardcoded-paths.sh, TASK-178
# 3 목록에 홈 절대 경로를 남기지 않음(TASK-176 B4)
#   설명: $HOME 으로 시작하는 절대 대상은 ~ 로 적고 읽을 때 지금 HOME 으로 되돌린다. 공개 저장소에 /Users/<이름> 이 들어가지 않고, 사용자 이름이 다른 머신에서도 같은 목록을 쓴다.
#   관련: TASK-176 B4
# 4 담당 값 검증(TASK-179)
#   설명: 담당 열은 claude · antigravity · claude-other 중 하나만 쓴다. 오타가 그대로 남으면 owner 가 엉뚱한 답을 내므로 목록 오류로 멈춘다(종료 2).
#   관련: TASK-179, workspace/repos.tsv
# 5 가장 가까운 목록 저장소의 담당(TASK-179 B1·B3)
#   설명: 깊은 저장소부터 보며 경로가 그 저장소이거나 그 아래면 그 담당을 낸다. 저장소가 아닌 폴더(freeride/math 등)는 품은 저장소를 따른다. 별칭 링크는 실제 경로도 함께 봐서 freeride/dev-toolchain 이 dev-tools/dev-toolchain 의 담당으로 풀린다.
#   관련: TASK-179, ~/githubs/freeride/dev-toolchain(별칭)
#   개념: 최장 접두사 일치
# 6 모르면 unknown 과 종료 1(TASK-179 B3)
#   설명: 목록 저장소 밖 경로는 담당을 추측하지 않는다. unknown 을 출력하고 1로 끝나 에이전트가 유저에게 묻게 한다.
#   개념: fail-closed
# 7 실제 파일·폴더는 덮어쓰지 않음(TASK-176 B1)
#   설명: 링크 자리에 진짜 파일·폴더가 있으면 --force 여도 보고만 하고 실패로 센다. 사람이 만든 내용을 잃는 것보다 손으로 정리하게 두는 편이 안전하다.
#   관련: TASK-176 B1
# 8 대상이 다른 링크는 --force 일 때만 교체(TASK-176 B2)
#   설명: 다른 대상은 의도한 로컬 변경일 수 있으므로 기본은 보고만 한다. 교체 직전에 다시 링크인지 확인한 뒤 지운다.
#   관련: TASK-176 B2
# 9 git clone 벽시계 타임아웃
#   설명: DNS·TCP 단계에서 멈춘 clone 은 git 자체로는 끝나지 않는다. WORKSPACE_GIT_TIMEOUT(기본 300초)이 지나면 새 세션으로 띄운 프로세스 그룹 전체를 죽인다.
#   관련: scripts/lib.sh lt_run_with_timeout (같은 문제의식)
#   개념: 프로세스 그룹
# 10 실패한 clone 의 반쯤 만든 폴더 정리
#   설명: MISSING 일 때만 clone 하므로 dest 는 이번 실행이 만든 것이다. 남겨 두면 다음 실행에서 '이미 있는 저장소'로 보여 B3 때문에 영영 손대지 못한다.
# 11 이미 있는 저장소는 건드리지 않음(TASK-176 B3)
#   설명: bootstrap 은 없는 저장소만 clone 한다. 원격이 다른 폴더도 pull·reset·remote 변경 없이 보고만 하고 실패로 센다.
#   관련: TASK-176 B3
# 12 결정적 출력(TASK-176 B5)
#   설명: 행을 정렬하고 머리 주석이 고정이라 같은 머신 상태에서 capture 를 두 번 돌리면 바이트까지 같다. 디렉터리 순회도 이름순이다.
#   관련: TASK-176 B5
# 13 capture 는 담당을 보존(TASK-179 B2)
#   설명: capture 는 경로 · URL 만 머신에서 알아낸다. 담당은 사람이 정한 값이라 기존 행의 값을 그대로 이어 붙인다. 새로 생긴 저장소는 담당 없이(2열) 들어가고 status 에 '-' 로 보인다.
#   관련: TASK-178 의 tools capture 비고 보존(같은 방식)
# 14 bin/* 와 tools.tsv 명령 집합 대조(TASK-178 B2)
#   설명: links.tsv 의 githubs bin/* 이름과 tools.tsv 명령 이름이 같아야 한다. 한쪽에만 있으면 어긋남으로 세어 status 가 1 이 된다. 커밋된 두 목록은 테스트도 같은 규칙으로 검사한다.
#   관련: workspace/links.tsv, workspace/tools.tsv, TASK-178 B2
# 15 빠진 것만 설치, 업그레이드·삭제 없음(TASK-178 B1)
#   설명: Cellar·Caskroom·uv tool 폴더에 이미 있으면 설치 목록에서 뺀다. brew install 은 HOMEBREW_NO_INSTALL_UPGRADE 등으로 이미 있는 의존성을 올리지 않게 하고, upgrade·uninstall 은 어디서도 부르지 않는다.
#   관련: BREW_SAFE_ENV, TASK-178 B1
#   개념: 멱등
# 16 설치 순서
#   설명: brew formula → cask → uv tool → dev-toolchain sync(oss) → 저장소 빌드 → link 순서다. oss 의 일부는 Homebrew 실행 파일을 가리키므로 sync 는 brew 뒤에, link 는 모든 실체가 생긴 뒤에 온다. 같은 공급자는 한 번에 묶어 부른다.
#   관련: scripts/oss_sync.sh populate_ref_bins, TASK-178 AC #3
# 17 Xcode CLT·Homebrew 가 없으면 안내만 하고 멈춤(TASK-178 B3)
#   설명: 둘 다 sudo 나 GUI 확인이 필요해 이 명령이 대신 설치하지 않는다. 설치 방법을 알려 주고 다른 단계는 하나도 실행하지 않은 채 1 로 끝난다. 설치는 dev-toolchain install(curl | sh) 몫이다.
#   관련: BLOCKING_PREREQS, scripts/install/01_bootstrap_asdf.sh, TASK-178 B3
# 18 --dry-run 은 아무것도 실행하지 않음(TASK-178 B4)
#   설명: 계획 줄만 출력하고 외부 명령을 부르지 않는다. 마지막 link 단계도 같은 dry 값을 받는다.
#   관련: TASK-178 B4
# 19 capture 는 prereq 행을 보존(TASK-178 B5)
#   설명: 선행 도구 행은 bin/* 에서 알아낼 수 없어 손으로 적은 것이다. capture 는 명령 행만 다시 쓰고 prereq 행은 고정 순서로 그대로 둔다. 같은 상태에서 두 번 돌리면 바이트까지 같다.
#   관련: PREREQ_ORDER, TASK-178 B5
# 20 진입점: 서브커맨드 해석
#   설명: 서브커맨드가 없으면 status 다. --dry-run 은 서브커맨드 앞뒤 어디에 와도 되고 DRY_RUN=true(설치기와 같은 관례)와 같다. install.sh 가 'workspace' 를 떼고 나머지 인자를 넘긴다. tools 는 status·install·capture 를 가진 하위 그룹이다.
#   관련: install.sh, scripts/lib.sh (DRY_RUN)
