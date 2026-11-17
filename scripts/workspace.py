#!/usr/bin/env python3
# ---
# title: workspace
# description: ~/githubs 저장소 배치와 심볼릭 링크를 목록 파일(workspace/*.tsv)과 비교·복원·기록하는 명령
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# task: TASK-176
# created_date: '2026-11-17'
# updated_date: '2026-11-17'
# ---
# dev-toolchain workspace [status|link|bootstrap|capture] [--dry-run]
#
#   status     목록과 지금 머신을 비교해 표로 출력(기본). 어긋남이 있으면 종료 코드 1
#   link       목록에 있는데 없는 링크를 만든다. 대상이 다른 링크는 --force 일 때만 바꾼다
#   bootstrap  없는 저장소만 git clone 한 뒤 link 를 돈다
#   capture    지금 머신을 훑어 workspace/repos.tsv·links.tsv 를 다시 쓴다
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
    "# 형식: <경로><TAB><원격 URL>",
    "#   경로: githubs 루트 기준 상대 경로. 경로순 정렬",
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
            return "~" + raw[len(self.home):]  # ---- 2
        return raw

    def from_manifest(self, target: str) -> str:
        if target == "~":
            return self.home
        if target.startswith("~/"):
            return self.home + target[1:]
        return target


def plan(msg: str) -> None:
    print("  + " + msg)


def read_tsv(path: str, ncols: int) -> list:
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
        if len(parts) != ncols or not all(parts):
            raise ManifestError(f"{path}:{n}: 탭으로 나뉜 값 {ncols}개가 필요합니다: {line!r}")
        rows.append(tuple(parts))
    return rows


def load_repos(ctx: Ctx) -> list:
    return read_tsv(ctx.repos_file, 2)


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
    print(f"[repos] {len(repos)}개  (root: {ctx.to_manifest(ctx.root)})")
    for rel, url in repos:
        state, actual = repo_state(ctx, rel, url)
        extra = f"want {url}  got {actual}" if state == "WRONG-REMOTE" else url
        print(f"  {state:<13} {rel:<50} {extra}")
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
            print(f"  NOT-A-LINK    {scope} {rel} (실제 파일·폴더라 그대로 둠)")  # ---- 3
            failed += 1
            continue
        try:
            if state == "WRONG-TARGET":
                if not force:
                    print(f"  WRONG-TARGET  {scope} {rel}: want {target} got {actual} (--force 로 교체)")  # ---- 4
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


def git_timeout() -> float:
    raw = os.environ.get("WORKSPACE_GIT_TIMEOUT") or str(DEFAULT_GIT_TIMEOUT)
    try:
        value = float(raw)
    except ValueError:
        raise ManifestError(f"WORKSPACE_GIT_TIMEOUT 이 숫자가 아닙니다: {raw!r}")
    if value <= 0:
        raise ManifestError(f"WORKSPACE_GIT_TIMEOUT 은 0보다 커야 합니다: {raw!r}")
    return value


def clone(url: str, dest: str, timeout: float) -> str | None:
    """실패 이유를 돌려준다(성공이면 None). 실패하면 이번에 만든 dest 를 지운다."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    proc = subprocess.Popen(
        ["git", "clone", "--quiet", url, dest], env=env, start_new_session=True
    )
    try:
        rc = proc.wait(timeout=timeout)  # ---- 5
        reason = None if rc == 0 else f"git clone 종료 코드 {rc}"
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        reason = f"timeout: {timeout:g}초 안에 끝나지 않아 중단"
    if reason and os.path.lexists(dest):
        shutil.rmtree(dest, ignore_errors=True)  # ---- 6
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
            print(f"  WRONG-REMOTE  {rel}: want {url} got {actual} (이미 있는 폴더라 그대로 둠)")  # ---- 7
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
    lines = list(header) + ["\t".join(r) for r in sorted(rows)]  # ---- 8
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
    write_file(ctx.repos_file, render(REPOS_HEADER, list(repos.items())), dry)
    write_file(
        ctx.links_file, render(LINKS_HEADER, [(s, r, t) for (s, r), t in links.items()]), dry
    )
    by_scope = {s: sum(1 for k in links if k[0] == s) for s in SCOPES}
    print(f"capture: 저장소 {len(repos)}, 링크 githubs {by_scope['githubs']} + home {by_scope['home']}")
    return 0


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
    sub = p.add_subparsers(dest="cmd", metavar="{status,link,bootstrap,capture}")
    sub.add_parser("status", parents=[common], help="목록과 비교해 출력(기본). 어긋나면 종료 1")
    lp = sub.add_parser("link", parents=[common], help="없는 링크 만들기")
    lp.add_argument("--force", action="store_true", help="대상이 다른 링크도 목록대로 바꾼다")
    sub.add_parser("bootstrap", parents=[common], help="없는 저장소 clone 후 link")
    sub.add_parser("capture", parents=[common], help="지금 머신을 목록 파일로 기록")
    return p


def main(argv: list | None = None) -> int:
    args = build_parser().parse_args(argv)  # ---- 9
    dry = bool(getattr(args, "dry_run", False)) or (
        os.environ.get("DRY_RUN", "").strip().lower() in ("1", "true", "yes")
    )
    ctx = Ctx()
    cmd = args.cmd or "status"
    if dry and cmd != "status":
        print("(dry-run: 아무것도 바꾸지 않습니다)")
    try:
        if cmd == "link":
            return cmd_link(ctx, dry, args.force)
        if cmd == "bootstrap":
            return cmd_bootstrap(ctx, dry)
        if cmd == "capture":
            return cmd_capture(ctx, dry)
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
# 2 목록에 홈 절대 경로를 남기지 않음(B4)
#   설명: $HOME 으로 시작하는 절대 대상은 ~ 로 적고 읽을 때 지금 HOME 으로 되돌린다. 공개 저장소에 /Users/<이름> 이 들어가지 않고, 사용자 이름이 다른 머신에서도 같은 목록을 쓴다.
#   관련: TASK-176 B4
# 3 실제 파일·폴더는 덮어쓰지 않음(B1)
#   설명: 링크 자리에 진짜 파일·폴더가 있으면 --force 여도 보고만 하고 실패로 센다. 사람이 만든 내용을 잃는 것보다 손으로 정리하게 두는 편이 안전하다.
#   관련: TASK-176 B1
# 4 대상이 다른 링크는 --force 일 때만 교체(B2)
#   설명: 다른 대상은 의도한 로컬 변경일 수 있으므로 기본은 보고만 한다. 교체 직전에 다시 링크인지 확인한 뒤 지운다.
#   관련: TASK-176 B2
# 5 git clone 벽시계 타임아웃
#   설명: DNS·TCP 단계에서 멈춘 clone 은 git 자체로는 끝나지 않는다. WORKSPACE_GIT_TIMEOUT(기본 300초)이 지나면 새 세션으로 띄운 프로세스 그룹 전체를 죽인다.
#   관련: scripts/lib.sh lt_run_with_timeout (같은 문제의식)
#   개념: 프로세스 그룹
# 6 실패한 clone 의 반쯤 만든 폴더 정리
#   설명: MISSING 일 때만 clone 하므로 dest 는 이번 실행이 만든 것이다. 남겨 두면 다음 실행에서 '이미 있는 저장소'로 보여 B3 때문에 영영 손대지 못한다.
# 7 이미 있는 저장소는 건드리지 않음(B3)
#   설명: bootstrap 은 없는 저장소만 clone 한다. 원격이 다른 폴더도 pull·reset·remote 변경 없이 보고만 하고 실패로 센다.
#   관련: TASK-176 B3
# 8 결정적 출력(B5)
#   설명: 행을 정렬하고 머리 주석이 고정이라 같은 머신 상태에서 capture 를 두 번 돌리면 바이트까지 같다. 디렉터리 순회도 이름순이다.
#   관련: TASK-176 B5
# 9 진입점: 서브커맨드 해석
#   설명: 서브커맨드가 없으면 status 다. --dry-run 은 서브커맨드 앞뒤 어디에 와도 되고 DRY_RUN=true(설치기와 같은 관례)와 같다. install.sh 가 'workspace' 를 떼고 나머지 인자를 넘긴다.
#   관련: install.sh, scripts/lib.sh (DRY_RUN)
