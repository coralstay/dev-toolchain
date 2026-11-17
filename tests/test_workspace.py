# ---
# title: test_workspace
# description: scripts/workspace.py의 status·link·bootstrap·capture를 가짜 HOME·루트·로컬 bare 저장소 샌드박스에서 검증하는 테스트
# authors: [coralstay]
# license: AGPL-3.0-only
# status: draft
# task: TASK-176
# created_date: '2026-11-17'
# updated_date: '2026-11-17'
# ---
# TASK-176: workspace 목록(repos.tsv·links.tsv)과 status·link·bootstrap·capture 명령 검증
#
# 실행: uvx --with pytest pytest -q -p no:cacheprovider tests
# 모든 테스트는 tmp_path 안의 가짜 HOME(home/)·githubs 루트(home/githubs/)·목록 폴더(manifest/)만
# 쓴다. 원격은 로컬 bare 저장소(remotes/*.git)의 파일 경로라 네트워크가 필요 없다. capture 의
# 소유자 판정은 WORKSPACE_OWNER_PATTERNS 로 remotes/ 경로 접두사를 소유자로 지정해 흉내 낸다.
# 예외: TASK-177 의 test_committed_links_* 는 샌드박스가 아니라 이 저장소에 커밋된
# workspace/links.tsv 를 읽어 정규화 규칙(R1~R3)을 검사한다(읽기만 한다).

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "workspace.py"
INSTALL = REPO / "install.sh"
# macOS 시스템 python3(3.9). 없는 머신에서는 현재 인터프리터로 대신 돈다.
SYSTEM_PYTHON = "/usr/bin/python3" if os.path.exists("/usr/bin/python3") else sys.executable


class World:
    def __init__(self, tmp_path: Path):
        self.base = tmp_path
        self.home = tmp_path / "home"
        self.root = self.home / "githubs"
        self.remotes = tmp_path / "remotes"
        self.manifest = tmp_path / "manifest"
        for d in (self.home, self.root, self.remotes, self.manifest):
            d.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ)
        for k in ("DRY_RUN", "WORKSPACE_GIT_TIMEOUT", "GIT_DIR", "GIT_WORK_TREE"):
            env.pop(k, None)
        env.update(
            HOME=str(self.home),
            WORKSPACE_ROOT=str(self.root),
            WORKSPACE_MANIFEST_DIR=str(self.manifest),
            WORKSPACE_OWNER_PATTERNS=str(self.remotes) + "/",
            GIT_AUTHOR_NAME="t",
            GIT_AUTHOR_EMAIL="t@example.invalid",
            GIT_COMMITTER_NAME="t",
            GIT_COMMITTER_EMAIL="t@example.invalid",
            GIT_CONFIG_NOSYSTEM="1",
            GIT_TERMINAL_PROMPT="0",
        )
        self.env = env

    def git(self, *args: str, cwd: Path | None = None) -> str:
        r = subprocess.run(
            ["git", *args], cwd=cwd, env=self.env, check=True, capture_output=True, text=True
        )
        return r.stdout.strip()

    def make_remote(self, name: str) -> str:
        src = self.base / "src" / name
        src.mkdir(parents=True)
        self.git("init", "-q", str(src))
        (src / "README").write_text(name + "\n")
        (src / "tool.sh").write_text("#!/bin/sh\necho " + name + "\n")
        self.git("add", ".", cwd=src)
        self.git("commit", "-q", "-m", "init", cwd=src)
        bare = self.remotes / (name + ".git")
        self.git("clone", "-q", "--bare", str(src), str(bare))
        return str(bare)

    def push_new_commit(self, name: str) -> None:
        src = self.base / "src" / name
        (src / "later").write_text("later\n")
        self.git("add", ".", cwd=src)
        self.git("commit", "-q", "-m", "later", cwd=src)
        self.git("push", "-q", str(self.remotes / (name + ".git")), "HEAD", cwd=src)

    def clone(self, url: str, rel: str) -> Path:
        dest = self.root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        self.git("clone", "-q", url, str(dest))
        return dest

    def run(self, *args: str, python: str | None = None, extra_env: dict | None = None):
        env = dict(self.env)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [python or sys.executable, str(SCRIPT), *args],
            check=False,
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
        )

    def symlink(self, link: Path, target: str) -> None:
        link.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(target, link)

    def snapshot(self) -> list:
        out = []
        for base in (self.home, self.manifest):
            for dirpath, dirnames, filenames in os.walk(base):
                dirnames[:] = sorted(d for d in dirnames if d != ".git")
                for n in sorted(dirnames + filenames):
                    p = os.path.join(dirpath, n)
                    if os.path.islink(p):
                        out.append((p, "L", os.readlink(p)))
                    elif os.path.isfile(p):
                        with open(p, "rb") as f:
                            out.append((p, "F", hashlib.sha256(f.read()).hexdigest()))
                    else:
                        out.append((p, "D", ""))
        return out


def build_world(tmp_path: Path) -> World:
    """Standard sandbox: 2 owned repos, 3 githubs links, 2 home links + noise capture must skip."""
    w = World(tmp_path)
    w.url_alpha = w.make_remote("alpha")
    w.url_beta = w.make_remote("beta")
    w.clone(w.url_alpha, "alpha")
    w.clone(w.url_beta, "group/beta")
    w.symlink(w.root / "bin" / "tool", "../alpha/tool.sh")
    w.symlink(w.root / "alias", "group/beta")
    w.symlink(w.root / "group" / "link2", "../alpha")
    w.symlink(w.home / ".local" / "bin" / "tool", str(w.root / "bin" / "tool"))
    w.symlink(w.home / ".tool-versions", str(w.root / "alpha" / "README"))

    # noise that capture must ignore
    oss = w.root / "opensource" / "in-use" / "x"
    oss.mkdir(parents=True)
    w.git("init", "-q", str(oss))
    w.git("remote", "add", "origin", w.url_alpha, cwd=oss)
    w.symlink(w.root / "opensource" / "link", "in-use/x")
    third = w.root / "third"
    third.mkdir()
    w.git("init", "-q", str(third))
    w.git("remote", "add", "origin", "https://example.invalid/someone/third.git", cwd=third)
    deep = w.root / "a" / "b" / "c" / "deep"
    deep.mkdir(parents=True)
    w.git("init", "-q", str(deep))
    w.git("remote", "add", "origin", w.url_alpha, cwd=deep)
    w.symlink(w.root / "group" / "beta" / "deeplink", "README")
    w.symlink(w.home / ".local" / "bin" / "outside", str(w.base / "remotes"))
    w.symlink(w.home / "outside-home", str(w.base))
    return w


def write_manifest(w: World) -> None:
    (w.manifest / "repos.tsv").write_text(
        "# path<TAB>remote_url\n"
        f"alpha\t{w.url_alpha}\n"
        f"group/beta\t{w.url_beta}\n"
    )
    (w.manifest / "links.tsv").write_text(
        "# scope<TAB>link<TAB>target\n"
        "githubs\talias\tgroup/beta\n"
        "githubs\tbin/tool\t../alpha/tool.sh\n"
        "githubs\tgroup/link2\t../alpha\n"
        "home\t.local/bin/tool\t~/githubs/bin/tool\n"
        "home\t.tool-versions\t~/githubs/alpha/README\n"
    )


@pytest.fixture
def world(tmp_path: Path) -> World:
    w = build_world(tmp_path)
    write_manifest(w)
    return w


def data_lines(p: Path) -> list:
    return [ln for ln in p.read_text().splitlines() if ln and not ln.startswith("#")]


def _rm_repo(w):
    shutil.rmtree(w.root / "group" / "beta")


def _wrong_remote(w):
    w.git("remote", "set-url", "origin", "https://example.invalid/x.git", cwd=w.root / "alpha")


def _missing_link(w):
    os.unlink(w.root / "bin" / "tool")


def _wrong_target(w):
    os.unlink(w.root / "bin" / "tool")
    os.symlink("../alpha/README", w.root / "bin" / "tool")


def _not_a_link(w):
    os.unlink(w.root / "bin" / "tool")
    (w.root / "bin" / "tool").write_text("real file\n")


def _dangling(w):
    os.unlink(w.root / "alpha" / "tool.sh")


def _untracked(w):
    os.symlink("../alpha/README", w.root / "bin" / "extra")


# == AC/DoD ==


def test_capture_writes_manifest_format_without_home_path(tmp_path):
    """TASK-176#1 TASK-176#B4 capture writes sorted TSVs with a # header and ~ instead of $HOME."""
    w = build_world(tmp_path)
    r = w.run("capture")
    assert r.returncode == 0, r.stdout + r.stderr
    repos = (w.manifest / "repos.tsv").read_text()
    links = (w.manifest / "links.tsv").read_text()
    assert repos.startswith("#") and links.startswith("#")
    assert data_lines(w.manifest / "repos.tsv") == [
        f"alpha\t{w.url_alpha}",
        f"group/beta\t{w.url_beta}",
    ]
    assert data_lines(w.manifest / "links.tsv") == [
        "githubs\talias\tgroup/beta",
        "githubs\tbin/tool\t../alpha/tool.sh",
        "githubs\tgroup/link2\t../alpha",
        "home\t.local/bin/tool\t~/githubs/bin/tool",
        "home\t.tool-versions\t~/githubs/alpha/README",
    ]
    assert str(w.home) not in repos + links


def test_status_all_ok_exits_zero(world):
    """TASK-176#2 status prints OK rows and exits 0 when the machine matches the manifest."""
    r = world.run("status")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "OK" in r.stdout
    for bad in ("MISSING", "WRONG-", "NOT-A-LINK", "DANGLING", "UNTRACKED"):
        assert bad not in r.stdout


@pytest.mark.parametrize(
    "label,mutate",
    [
        ("MISSING", _rm_repo),
        ("WRONG-REMOTE", _wrong_remote),
        ("MISSING", _missing_link),
        ("WRONG-TARGET", _wrong_target),
        ("NOT-A-LINK", _not_a_link),
        ("DANGLING", _dangling),
        ("UNTRACKED", _untracked),
    ],
)
def test_status_reports_each_drift_class_and_exits_one(world, label, mutate):
    """TASK-176#2 each drift class (repo MISSING/WRONG-REMOTE, link MISSING/WRONG-TARGET/NOT-A-LINK/DANGLING, UNTRACKED) is reported with exit 1."""
    mutate(world)
    r = world.run("status")
    assert r.returncode == 1, r.stdout + r.stderr
    assert label in r.stdout


def test_link_creates_missing_links_and_is_idempotent(world):
    """TASK-176#3 link creates only missing links (with parent dirs) and a second run changes nothing."""
    os.unlink(world.root / "bin" / "tool")
    shutil.rmtree(world.home / ".local")
    r = world.run("link")
    assert r.returncode == 0, r.stdout + r.stderr
    assert os.readlink(world.root / "bin" / "tool") == "../alpha/tool.sh"
    assert os.readlink(world.home / ".local" / "bin" / "tool") == str(world.root / "bin" / "tool")
    before = world.snapshot()
    r2 = world.run("link")
    assert r2.returncode == 0, r2.stdout + r2.stderr
    assert "  + " not in r2.stdout
    assert world.snapshot() == before
    # the untracked 'outside' link was removed with .local; status must be clean now
    assert world.run("status").returncode == 0


@pytest.mark.parametrize("how", ["flag", "flag-after", "env"])
def test_link_dry_run_has_no_side_effects(world, how):
    """TASK-176#3 link --dry-run / DRY_RUN=true prints '  + ' plans and changes nothing."""
    os.unlink(world.root / "bin" / "tool")
    os.unlink(world.home / ".tool-versions")
    before = world.snapshot()
    if how == "flag":
        r = world.run("--dry-run", "link")
    elif how == "flag-after":
        r = world.run("link", "--dry-run")
    else:
        r = world.run("link", extra_env={"DRY_RUN": "true"})
    assert r.returncode == 0, r.stdout + r.stderr
    assert "  + " in r.stdout
    assert world.snapshot() == before


def test_link_never_overwrites_real_file_even_with_force(world):
    """TASK-176#3 TASK-176#B1 link leaves a real file at a link path untouched and exits 1."""
    _not_a_link(world)
    for args in (("link",), ("link", "--force")):
        r = world.run(*args)
        assert r.returncode == 1, r.stdout + r.stderr
        assert "NOT-A-LINK" in r.stdout
        p = world.root / "bin" / "tool"
        assert not os.path.islink(p)
        assert p.read_text() == "real file\n"


def test_link_never_replaces_real_directory(world):
    """TASK-176#3 TASK-176#B1 link leaves a real directory at a link path untouched."""
    os.unlink(world.root / "alias")
    (world.root / "alias").mkdir()
    (world.root / "alias" / "keep").write_text("keep\n")
    r = world.run("link", "--force")
    assert r.returncode == 1
    assert (world.root / "alias" / "keep").read_text() == "keep\n"


def test_link_replaces_wrong_target_only_with_force(world):
    """TASK-176#3 TASK-176#B2 a link with a different target is changed only with --force."""
    _wrong_target(world)
    r = world.run("link")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "WRONG-TARGET" in r.stdout
    assert os.readlink(world.root / "bin" / "tool") == "../alpha/README"
    r = world.run("link", "--force", "--dry-run")
    assert r.returncode == 0, r.stdout + r.stderr
    assert os.readlink(world.root / "bin" / "tool") == "../alpha/README"
    r = world.run("link", "--force")
    assert r.returncode == 0, r.stdout + r.stderr
    assert os.readlink(world.root / "bin" / "tool") == "../alpha/tool.sh"
    assert world.run("status").returncode == 0


def test_bootstrap_clones_only_missing_and_leaves_existing_repo_alone(world):
    """TASK-176#4 TASK-176#B3 bootstrap clones the missing repo, never touches an existing one, then links."""
    _rm_repo(world)
    os.unlink(world.home / ".local" / "bin" / "tool")
    alpha = world.root / "alpha"
    (alpha / "untracked.txt").write_text("mine\n")
    world.push_new_commit("alpha")  # a pull would move HEAD
    head = world.git("rev-parse", "HEAD", cwd=alpha)
    porcelain = world.git("status", "--porcelain", cwd=alpha)
    refs = world.git("for-each-ref", cwd=alpha)

    r = world.run("bootstrap")
    assert r.returncode == 0, r.stdout + r.stderr
    beta = world.root / "group" / "beta"
    assert (beta / ".git").exists()
    assert world.git("remote", "get-url", "origin", cwd=beta) == world.url_beta
    assert world.git("rev-parse", "HEAD", cwd=alpha) == head
    assert world.git("status", "--porcelain", cwd=alpha) == porcelain
    assert world.git("for-each-ref", cwd=alpha) == refs
    assert (alpha / "untracked.txt").read_text() == "mine\n"
    assert os.readlink(world.home / ".local" / "bin" / "tool") == str(world.root / "bin" / "tool")
    assert world.run("status").returncode == 0


def test_bootstrap_does_not_change_wrong_remote(world):
    """TASK-176#4 TASK-176#B3 bootstrap reports WRONG-REMOTE but leaves the remote as it is."""
    _wrong_remote(world)
    r = world.run("bootstrap")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "WRONG-REMOTE" in r.stdout
    url = world.git("remote", "get-url", "origin", cwd=world.root / "alpha")
    assert url == "https://example.invalid/x.git"


def test_bootstrap_dry_run_clones_nothing(world):
    """TASK-176#4 bootstrap --dry-run prints the clone plan and creates nothing."""
    _rm_repo(world)
    before = world.snapshot()
    r = world.run("bootstrap", "--dry-run")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "  + git clone" in r.stdout
    assert world.snapshot() == before


def test_bootstrap_clone_timeout(world, tmp_path):
    """TASK-176#4 a hanging git clone is killed after WORKSPACE_GIT_TIMEOUT and leaves no partial dir."""
    _rm_repo(world)
    real_git = shutil.which("git")
    fake = tmp_path / "fakebin"
    fake.mkdir()
    (fake / "git").write_text(
        '#!/bin/sh\nif [ "$1" = clone ]; then exec sleep 30; fi\nexec "' + real_git + '" "$@"\n'
    )
    os.chmod(fake / "git", 0o755)
    r = world.run(
        "bootstrap",
        extra_env={"WORKSPACE_GIT_TIMEOUT": "1", "PATH": str(fake) + os.pathsep + world.env["PATH"]},
    )
    assert r.returncode == 1, r.stdout + r.stderr
    assert "timeout" in (r.stdout + r.stderr).lower()
    assert not (world.root / "group" / "beta").exists()


def test_capture_is_deterministic(tmp_path):
    """TASK-176#5 TASK-176#B5 capture twice gives byte-identical files, and status is clean right after."""
    w = build_world(tmp_path)
    assert w.run("capture").returncode == 0
    first = {n: (w.manifest / n).read_bytes() for n in ("repos.tsv", "links.tsv")}
    assert w.run("status").returncode == 0
    assert w.run("capture").returncode == 0
    second = {n: (w.manifest / n).read_bytes() for n in ("repos.tsv", "links.tsv")}
    assert first == second


def test_install_sh_dispatches_workspace(world):
    """TASK-176#6 `sh install.sh workspace status` runs workspace.py against the sandbox."""
    r = subprocess.run(
        ["sh", str(INSTALL), "workspace", "status"],
        check=False,
        env=world.env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "OK" in r.stdout
    _missing_link(world)
    r = subprocess.run(
        ["sh", str(INSTALL), "workspace"],
        check=False,
        env=world.env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert r.returncode == 1
    assert "MISSING" in r.stdout


def test_runs_on_system_python(world):
    """TASK-176#2 TASK-176#5 workspace.py runs under the macOS system python3 (3.9)."""
    assert world.run("--help", python=SYSTEM_PYTHON).returncode == 0
    r = world.run("status", python=SYSTEM_PYTHON)
    assert r.returncode == 0, r.stdout + r.stderr
    r = world.run("capture", python=SYSTEM_PYTHON)
    assert r.returncode == 0, r.stdout + r.stderr
    r = world.run("status", python=SYSTEM_PYTHON)
    assert r.returncode == 0, r.stdout + r.stderr


def committed_links() -> list:
    """Rows (scope, link, target) of this repo's committed workspace/links.tsv."""
    return [tuple(ln.split("\t")) for ln in data_lines(REPO / "workspace" / "links.tsv")]


def test_committed_links_local_bin_goes_through_githubs_bin():
    """TASK-177#1 TASK-177#B2 R1: every home .local/bin/<cmd> targets exactly ~/githubs/bin/<cmd>."""
    bad = [
        (link, target)
        for scope, link, target in committed_links()
        if scope == "home"
        and link.startswith(".local/bin/")
        and target != "~/githubs/bin/" + link[len(".local/bin/") :]
    ]
    assert bad == []


def test_committed_links_bin_and_local_bin_have_same_names():
    """TASK-177#1 TASK-177#B2 R2: names under githubs bin/* equal names under home .local/bin/*."""
    rows = committed_links()
    hub = {link[len("bin/") :] for s, link, _ in rows if s == "githubs" and link.startswith("bin/")}
    local = {
        link[len(".local/bin/") :]
        for s, link, _ in rows
        if s == "home" and link.startswith(".local/bin/")
    }
    assert (sorted(local - hub), sorted(hub - local)) == ([], [])


def test_committed_links_opensource_targets_go_through_current():
    """TASK-177#1 TASK-177#B2 R3: a target under opensource/in-use/<name>/ continues with current/."""
    marker = "opensource/in-use/"
    bad = []
    for scope, link, target in committed_links():
        if marker not in target:
            continue
        rest = target.split(marker, 1)[1].split("/")
        if len(rest) < 2 or rest[1] != "current":
            bad.append((scope, link, target))
    assert bad == []


# == Coverage ==


def test_status_is_default_subcommand(world):
    """Running with no subcommand behaves like status."""
    r = world.run()
    assert r.returncode == 0, r.stdout + r.stderr
    assert "OK" in r.stdout


def test_capture_dry_run_writes_nothing(tmp_path):
    """capture --dry-run prints the plan and does not write the manifest files."""
    w = build_world(tmp_path)
    r = w.run("capture", "--dry-run")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "  + " in r.stdout
    assert not (w.manifest / "repos.tsv").exists()


def test_status_without_manifest_fails_cleanly(tmp_path):
    """A missing manifest is an error (exit 2) with a hint, not a traceback."""
    w = build_world(tmp_path)
    r = w.run("status")
    assert r.returncode == 2
    assert "Traceback" not in r.stderr
    assert "capture" in r.stderr
