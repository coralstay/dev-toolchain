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


# ---- TASK-178: workspace tools 샌드박스 ----
# 가짜 brew·uv·git·xcode-select·claude 를 fakebin/ 에, 가짜 dev-toolchain install.sh 를 toolchain/ 에 둔다.
# PATH 는 fakebin:/bin 뿐이라 진짜 Homebrew·uv·git 은 보이지 않는다. 가짜들은 받은 인자를 calls.log 에,
# brew 는 HOMEBREW_NO_* 환경 변수를 brew-env.log 에 적는다. Homebrew 접두사는 HOMEBREW_PREFIX=brew/ 다.

PREREQ_ROWS = [
    "xcode-clt\tprereq\tmanual\tcheck: run xcode-select -p",
    "homebrew\tprereq\tdev-toolchain\tcheck: which brew",
    "git\tprereq\txcode-clt\tcheck: which git",
    "uv\tprereq\tdev-toolchain\tcheck: which uv",
    "claude\tprereq\tcask:claude-code\tcheck: which claude",
    "secretive\tprereq\tcask:secretive\tcheck: cask secretive",
]
VENV_NOTE = "build: uv venv .venv && uv pip install --python .venv -e ."


def _exe(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\n" + body)
    os.chmod(path, 0o755)


class ToolsWorld:
    """One command per provider: rg(brew) tflint(cask) yq(oss) vulture(uv-tool) jq(system) tool·ao·dt(repo)."""

    def __init__(self, tmp_path: Path):
        b = Path(os.path.realpath(tmp_path))  # capture/status compare realpaths (/var -> /private/var)
        self.base = b
        self.home = b / "home"
        self.root = self.home / "githubs"
        self.manifest = b / "manifest"
        self.prefix = b / "brew"
        self.fakebin = b / "fakebin"
        self.log = b / "calls.log"
        self.brew_env = b / "brew-env.log"
        self.toolchain = b / "toolchain" / "install.sh"
        self.jq = b / "sys" / "jq"
        for d in (self.home, self.root, self.manifest, self.prefix, self.fakebin):
            d.mkdir(parents=True, exist_ok=True)
        log = 'printf "%s\\n" "${0##*/} $*" >> "$TOOLS_LOG"\n'
        _exe(
            self.fakebin / "brew",
            log + 'printf "%s %s %s\\n" "${HOMEBREW_NO_INSTALL_UPGRADE:-}" '
            '"${HOMEBREW_NO_INSTALL_CLEANUP:-}" "${HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:-}"'
            ' >> "$TOOLS_BREW_ENV"\n',
        )
        _exe(self.fakebin / "uv", log)
        _exe(self.fakebin / "git", log)
        _exe(self.fakebin / "claude", log)
        _exe(self.fakebin / "xcode-select", 'exit "${FAKE_XCODE_RC:-0}"\n')
        _exe(self.toolchain, 'printf "%s\\n" "dev-toolchain $*" >> "$TOOLS_LOG"\n')
        env = dict(os.environ)
        for k in list(env):
            if k.startswith(("HOMEBREW_", "UV_", "WORKSPACE_")) or k in ("DRY_RUN", "XDG_DATA_HOME"):
                env.pop(k)
        env.update(
            HOME=str(self.home),
            PATH=str(self.fakebin) + os.pathsep + "/bin",
            WORKSPACE_ROOT=str(self.root),
            WORKSPACE_MANIFEST_DIR=str(self.manifest),
            WORKSPACE_TOOLCHAIN_INSTALL=str(self.toolchain),
            HOMEBREW_PREFIX=str(self.prefix),
            TOOLS_LOG=str(self.log),
            TOOLS_BREW_ENV=str(self.brew_env),
        )
        self.env = env
        self._build_machine()
        self.write_manifest()

    def _file(self, path: Path, text: str = "x\n") -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def _ln(self, link: Path, target: str) -> None:
        link.parent.mkdir(parents=True, exist_ok=True)
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink(target, link)

    def _build_machine(self) -> None:
        p, r = self.prefix, self.root
        # brew formula, reached the real way: bin -> opensource/in-use/<x>/current/bin -> prefix/bin -> Cellar
        self._file(p / "Cellar" / "ripgrep" / "15.0" / "bin" / "rg")
        self._ln(p / "bin" / "rg", "../Cellar/ripgrep/15.0/bin/rg")
        self._ln(r / "opensource" / "in-use" / "ripgrep" / "current", "v15")
        self._ln(r / "opensource" / "in-use" / "ripgrep" / "v15" / "bin" / "rg", str(p / "bin" / "rg"))
        self._ln(r / "bin" / "rg", "../opensource/in-use/ripgrep/current/bin/rg")
        # cask
        self._file(p / "Caskroom" / "tflint" / "0.6" / "tflint")
        self._ln(r / "bin" / "tflint", str(p / "Caskroom" / "tflint" / "0.6" / "tflint"))
        (p / "Caskroom" / "secretive" / "2.4").mkdir(parents=True)
        # oss (dev-toolchain sync output)
        self._file(r / "opensource" / "in-use" / "yq" / "v4" / "bin" / "yq")
        self._ln(r / "opensource" / "in-use" / "yq" / "current", "v4")
        self._ln(r / "bin" / "yq", "../opensource/in-use/yq/current/bin/yq")
        # uv tool
        uvbin = self.home / ".local" / "share" / "uv" / "tools" / "vulture" / "bin" / "vulture"
        self._file(uvbin)
        self._ln(r / "bin" / "vulture", str(uvbin))
        # system
        self._file(self.jq)
        self._ln(r / "bin" / "jq", str(self.jq))
        # repos: plain script, gradle installDist, python .venv
        (r / "dev" / "tool" / ".git").mkdir(parents=True)
        self._file(r / "dev" / "tool" / "tool.sh")
        self._ln(r / "bin" / "tool", "../dev/tool/tool.sh")
        ao = r / "fac" / "ao"
        (ao / ".git").mkdir(parents=True)
        self._file(ao / "build.gradle.kts")
        _exe(
            ao / "gradlew",
            'printf "%s\\n" "gradlew $* @ $(pwd -P)" >> "$TOOLS_LOG"\n'
            "mkdir -p build/install/ao/bin && : > build/install/ao/bin/ao\n",
        )
        self._file(ao / "build" / "install" / "ao" / "bin" / "ao")
        self._ln(r / "bin" / "ao", "../fac/ao/build/install/ao/bin/ao")
        dt = r / "free" / "dt"
        (dt / ".git").mkdir(parents=True)
        self._file(dt / "pyproject.toml")
        self._file(dt / ".venv" / "bin" / "dt")
        self._ln(r / "bin" / "dt", "../free/dt/.venv/bin/dt")

    def command_rows(self) -> list:
        return [
            "ao\trepo\tfac/ao\tbuild: ./gradlew installDist",
            f"dt\trepo\tfree/dt\t{VENV_NOTE}",
            f"jq\tsystem\t{self.jq}",
            "rg\tbrew\tripgrep",
            "tflint\tcask\ttflint",
            "tool\trepo\tdev/tool",
            "vulture\tuv-tool\tvulture",
            "yq\toss\tyq",
        ]

    def write_manifest(self, extra_rows: tuple = ()) -> None:
        rows = PREREQ_ROWS + self.command_rows() + list(extra_rows)
        (self.manifest / "tools.tsv").write_text("# test tools\n" + "\n".join(rows) + "\n")
        links = []
        for e in sorted(os.listdir(self.root / "bin")):
            links.append(f"githubs\tbin/{e}\t{os.readlink(self.root / 'bin' / e)}")
        (self.manifest / "links.tsv").write_text("# test links\n" + "\n".join(links) + "\n")

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

    def calls(self) -> list:
        return self.log.read_text().splitlines() if self.log.exists() else []

    def snapshot(self) -> list:
        out = []
        for base in (self.home, self.manifest, self.prefix):
            for dirpath, dirnames, filenames in os.walk(base):
                dirnames.sort()
                for n in sorted(dirnames + filenames):
                    p = os.path.join(dirpath, n)
                    kind = "L" if os.path.islink(p) else ("F" if os.path.isfile(p) else "D")
                    out.append((p, kind, os.readlink(p) if kind == "L" else ""))
        return out

    def break_everything(self) -> None:
        """Make one item of every install step missing (plus an extra missing brew row 'bat')."""
        shutil.rmtree(self.prefix / "Cellar" / "ripgrep")  # brew: rg dangles through in-use
        shutil.rmtree(self.prefix / "Caskroom" / "tflint")  # cask
        shutil.rmtree(self.prefix / "Caskroom" / "secretive")  # prereq cask
        os.unlink(self.fakebin / "claude")  # prereq cask claude-code
        shutil.rmtree(self.home / ".local" / "share" / "uv" / "tools" / "vulture")  # uv tool
        shutil.rmtree(self.root / "opensource" / "in-use" / "yq" / "v4")  # oss
        shutil.rmtree(self.root / "fac" / "ao" / "build")  # repo build
        os.unlink(self.root / "bin" / "tool")  # plain missing link -> link step
        rows = self.command_rows() + ["bat\tbrew\tbat"]
        (self.manifest / "tools.tsv").write_text("\n".join(PREREQ_ROWS + sorted(rows)) + "\n")
        with open(self.manifest / "links.tsv", "a") as f:
            f.write("githubs\tbin/bat\t../opensource/in-use/bat/current/bin/bat\n")


@pytest.fixture
def tools(tmp_path: Path) -> ToolsWorld:
    return ToolsWorld(tmp_path)


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


TOOL_PROVIDERS = {"brew", "cask", "uv-tool", "oss", "repo", "system", "prereq"}


def committed_tools() -> list:
    """Rows of this repo's committed workspace/tools.tsv (3 or 4 columns)."""
    return [tuple(ln.split("\t")) for ln in data_lines(REPO / "workspace" / "tools.tsv")]


def test_committed_tools_cover_exactly_the_bin_commands():
    """TASK-178#1 TASK-178#B2 the command rows of tools.tsv and links.tsv githubs bin/* have the same names."""
    hub = {link[len("bin/") :] for s, link, _ in committed_links() if s == "githubs" and link.startswith("bin/")}
    cmds = [r[0] for r in committed_tools() if r[1] != "prereq"]
    assert len(cmds) == len(set(cmds))
    assert (sorted(hub - set(cmds)), sorted(set(cmds) - hub)) == ([], [])


def test_committed_tools_rows_are_well_formed():
    """TASK-178#1 every row has a valid provider and package; prereqs carry a check, builds a 'build:' note."""
    rows = committed_tools()
    assert rows
    for row in rows:
        assert len(row) in (3, 4) and all(row), row
        assert row[1] in TOOL_PROVIDERS, row
        if row[1] == "prereq":
            assert row[3].startswith("check: "), row
        elif len(row) == 4 and row[1] == "repo":
            assert row[3].startswith("build: "), row
    prereqs = {r[0] for r in rows if r[1] == "prereq"}
    assert {"xcode-clt", "homebrew", "claude", "secretive"} <= prereqs
    # deterministic order: prereq rows first, command rows sorted by name
    kinds = [r[1] == "prereq" for r in rows]
    assert kinds == sorted(kinds, reverse=True)
    names = [r[0] for r in rows if r[1] != "prereq"]
    assert names == sorted(names)


def test_tools_status_all_ok_exits_zero(tools):
    """TASK-178#2 tools status prints OK for every row (with the brew version) and exits 0."""
    r = tools.run("tools", "status")
    assert r.returncode == 0, r.stdout + r.stderr
    for bad in ("MISSING", "WRONG-PROVIDER", "UNLISTED", "EXTRA"):
        assert bad not in r.stdout
    rg = [ln for ln in r.stdout.splitlines() if " rg " in ln]
    assert rg and "OK" in rg[0] and "15.0" in rg[0]
    assert r.stdout.count("OK") >= len(PREREQ_ROWS) + len(tools.command_rows())


def _tools_missing_cmd(t):
    shutil.rmtree(t.prefix / "Cellar" / "ripgrep")


def _tools_missing_prereq(t):
    os.unlink(t.fakebin / "claude")


def _tools_missing_cask_prereq(t):
    shutil.rmtree(t.prefix / "Caskroom" / "secretive")


def _tools_wrong_provider(t):
    os.unlink(t.root / "bin" / "rg")
    os.symlink(str(t.home / ".local" / "share" / "uv" / "tools" / "vulture" / "bin" / "vulture"), t.root / "bin" / "rg")


def _tools_unlisted(t):
    with open(t.manifest / "links.tsv", "a") as f:
        f.write("githubs\tbin/newcmd\t../dev/tool/tool.sh\n")


def _tools_extra(t):
    with open(t.manifest / "tools.tsv", "a") as f:
        f.write("zz\tbrew\tzz\n")


@pytest.mark.parametrize(
    "label,mutate",
    [
        ("MISSING", _tools_missing_cmd),
        ("MISSING", _tools_missing_prereq),
        ("MISSING", _tools_missing_cask_prereq),
        ("WRONG-PROVIDER", _tools_wrong_provider),
        ("UNLISTED", _tools_unlisted),
        ("EXTRA", _tools_extra),
    ],
)
def test_tools_status_reports_each_drift_and_exits_one(tools, label, mutate):
    """TASK-178#2 TASK-178#B2 MISSING / WRONG-PROVIDER rows and bin/* drift (UNLISTED, EXTRA) give exit 1."""
    mutate(tools)
    r = tools.run("tools", "status")
    assert r.returncode == 1, r.stdout + r.stderr
    assert label in r.stdout


def test_tools_install_runs_steps_in_order_for_missing_only(tools):
    """TASK-178#3 TASK-178#B1 install: brew -> cask -> uv tool -> sync -> repo build -> link, only what is missing."""
    tools.break_everything()
    r = tools.run("tools", "install")
    assert r.returncode == 0, r.stdout + r.stderr
    ao = os.path.realpath(tools.root / "fac" / "ao")
    assert tools.calls() == [
        "brew install --formula bat ripgrep",
        "brew install --cask claude-code secretive tflint",
        "uv tool install vulture",
        "dev-toolchain sync",
        f"gradlew installDist @ {ao}",
    ]
    # B1: brew install never upgrades or cleans up what is already there
    assert tools.brew_env.read_text().splitlines() == ["1 1 1", "1 1 1"]
    # link step ran last and restored the missing link
    assert os.readlink(tools.root / "bin" / "tool") == "../dev/tool/tool.sh"
    assert os.readlink(tools.root / "bin" / "bat") == "../opensource/in-use/bat/current/bin/bat"


def test_tools_install_never_upgrades_or_uninstalls(tools):
    """TASK-178#3 TASK-178#B1 nothing missing -> no external call at all; no run ever says upgrade/uninstall."""
    r = tools.run("tools", "install")
    assert r.returncode == 0, r.stdout + r.stderr
    assert tools.calls() == []
    assert "할 일 없음" in r.stdout
    tools.break_everything()
    assert tools.run("tools", "install").returncode == 0
    for call in tools.calls():
        for word in ("upgrade", "uninstall", "remove", "cleanup", "reinstall"):
            assert word not in call.split(), call


@pytest.mark.parametrize("which", ["xcode", "homebrew"])
def test_tools_install_stops_with_guidance_when_xcode_or_homebrew_missing(tools, which):
    """TASK-178#3 TASK-178#B3 missing Xcode CLT / Homebrew -> guidance, non-zero exit, nothing run or changed."""
    tools.break_everything()
    extra = {}
    if which == "xcode":
        extra["FAKE_XCODE_RC"] = "2"
        hint = "xcode-select --install"
    else:
        os.unlink(tools.fakebin / "brew")
        hint = "dev-toolchain install"
    before = tools.snapshot()
    r = tools.run("tools", "install", extra_env=extra)
    assert r.returncode != 0
    assert hint in r.stdout + r.stderr
    assert tools.calls() == []
    assert tools.snapshot() == before


@pytest.mark.parametrize("how", ["flag", "flag-after", "env"])
def test_tools_install_dry_run_runs_nothing(tools, how):
    """TASK-178#3 TASK-178#B4 --dry-run / DRY_RUN=true prints every planned step and executes none of them."""
    tools.break_everything()
    before = tools.snapshot()
    if how == "flag":
        r = tools.run("--dry-run", "tools", "install")
    elif how == "flag-after":
        r = tools.run("tools", "install", "--dry-run")
    else:
        r = tools.run("tools", "install", extra_env={"DRY_RUN": "true"})
    assert r.returncode == 0, r.stdout + r.stderr
    assert tools.calls() == []
    assert tools.snapshot() == before
    out = r.stdout
    plans = [
        "  + brew install --formula bat ripgrep",
        "  + brew install --cask claude-code secretive tflint",
        "  + uv tool install vulture",
        "  + sh " + str(tools.toolchain) + " sync",
        "./gradlew installDist",
        "  + ln -s ../dev/tool/tool.sh",
    ]
    pos = [out.find(p) for p in plans]
    assert -1 not in pos, out
    assert pos == sorted(pos), out


def test_tools_capture_is_deterministic_and_keeps_prereq_rows(tools):
    """TASK-178#4 TASK-178#B5 capture classifies bin/* by realpath, keeps prereq rows verbatim, and is byte-stable."""
    odd = "zz-custom\tprereq\tdev-toolchain\tcheck: which   uv   (손으로 쓴 행)"
    stale = "gone\tbrew\tgone"
    shuffled = [PREREQ_ROWS[3], odd, *PREREQ_ROWS[:3], *PREREQ_ROWS[4:], stale]
    (tools.manifest / "tools.tsv").write_text("\n".join(shuffled) + "\n")
    r = tools.run("tools", "capture")
    assert r.returncode == 0, r.stdout + r.stderr
    path = tools.manifest / "tools.tsv"
    first = path.read_bytes()
    assert first.startswith(b"#")
    assert data_lines(path) == PREREQ_ROWS + [odd] + tools.command_rows()
    assert str(tools.home) not in path.read_text().replace(str(tools.jq), "")
    assert tools.run("tools", "capture").returncode == 0
    assert path.read_bytes() == first
    assert tools.run("tools", "status").returncode == 0


def test_install_sh_dispatches_workspace_tools(tools):
    """TASK-178#2 `sh install.sh workspace tools status` reaches the tools subcommand."""
    r = subprocess.run(
        ["sh", str(INSTALL), "workspace", "tools", "status"],
        check=False,
        env=dict(tools.env, PATH=tools.env["PATH"] + os.pathsep + os.path.dirname(SYSTEM_PYTHON)),
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert r.returncode == 0, r.stdout + r.stderr
    assert "OK" in r.stdout


def test_tools_run_on_system_python(tools):
    """TASK-178#6 tools --help / status / capture / install --dry-run run under the macOS system python3 (3.9)."""
    for args in (("tools", "--help"), ("tools", "status"), ("tools", "capture"), ("tools", "install", "--dry-run")):
        r = tools.run(*args, python=SYSTEM_PYTHON)
        assert r.returncode == 0, (args, r.stdout + r.stderr)


# TASK-179: 저장소별 에이전트 담당(repos.tsv 3번째 열)과 workspace owner
# 유저 결정(2026-11-22)의 분담표. 커밋된 workspace/repos.tsv 가 이 표와 같아야 한다.
OWNERS = {
    ".github-profile": "claude",
    "coralstay-software-factory": "claude",
    "coralstay-software-factory/components/agent-orchestrator": "claude",
    "coralstay-software-factory/components/claude-code-agile-hooks": "claude",
    "coralstay-software-factory/components/coding-agent-git-commit-tool": "claude",
    "dev-tools/central-docs-collector": "antigravity",
    "dev-tools/dev-toolchain": "claude",
    "dev-tools/ebpf-wire-to-code-tracer": "claude-other",
    "dev-tools/omnivim": "antigravity",
    "dev-tools/source-header": "claude",
    "freeride": "antigravity",
    "freeride/coding-style-refactoring-principles": "antigravity",
    "freeride/databases": "antigravity",
    "freeride/devOps-LifeCycle": "antigravity",
    "freeride/doctree": "antigravity",
    "freeride/handcrafted-cpp": "antigravity",
    "freeride/handcrafted-java": "antigravity",
    "freeride/handcrafted-python": "antigravity",
    "toy-project/react-next-spring-postgresql-terraform-aws": "claude-other",
    "troubleshooting": "claude",
    "upkeep": "claude",
}


def write_owned_manifest(w: World) -> None:
    (w.manifest / "repos.tsv").write_text(
        "# path<TAB>remote_url<TAB>owner\n"
        f"alpha\t{w.url_alpha}\tclaude\n"
        f"group/beta\t{w.url_beta}\tantigravity\n"
    )


def test_committed_repos_have_the_agreed_owner():
    """TASK-179#1 TASK-179#B1 every committed repos.tsv row has an owner column equal to the user's split, and the header states the nearest-repo rule."""
    text = (REPO / "workspace" / "repos.tsv").read_text()
    rows = [ln.split("\t") for ln in text.splitlines() if ln and not ln.startswith("#")]
    assert {r[0]: r[2] for r in rows} == OWNERS
    assert all(len(r) == 3 for r in rows)
    assert "가장 가까운" in text


def test_capture_keeps_owner_values(world):
    """TASK-179#2 TASK-179#B2 capture rewrites paths/URLs from the machine but keeps each repo's owner; a second capture is byte-identical."""
    write_owned_manifest(world)
    assert world.run("capture").returncode == 0
    first = (world.manifest / "repos.tsv").read_text()
    assert f"alpha\t{world.url_alpha}\tclaude" in first
    assert f"group/beta\t{world.url_beta}\tantigravity" in first
    assert world.run("capture").returncode == 0
    assert (world.manifest / "repos.tsv").read_text() == first


@pytest.mark.parametrize(
    "path, owner",
    [
        ("alpha", "claude"),
        ("alpha/tool.sh", "claude"),
        ("group/beta/sub/file", "antigravity"),
        ("alias", "antigravity"),
    ],
)
def test_owner_resolves_nearest_listed_repo(world, path, owner):
    """TASK-179#3 relative paths resolve against the githubs root to the nearest listed repo, following symlinks (alias -> group/beta)."""
    write_owned_manifest(world)
    r = world.run("owner", path)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.strip() == owner


def test_owner_accepts_absolute_paths(world):
    """TASK-179#3 absolute paths work too."""
    write_owned_manifest(world)
    r = world.run("owner", str(world.root / "group" / "beta"))
    assert (r.returncode, r.stdout.strip()) == (0, "antigravity")


@pytest.mark.parametrize("path", ["group", "nowhere/at/all", "/"])
def test_owner_outside_listed_repos_is_unknown(world, path):
    """TASK-179#3 TASK-179#B3 a path no listed repo contains is 'unknown' with exit 1, so the agent asks the user."""
    write_owned_manifest(world)
    r = world.run("owner", path)
    assert (r.returncode, r.stdout.strip()) == (1, "unknown")


def test_status_shows_owner(world):
    """TASK-179#3 status prints each repo's owner."""
    write_owned_manifest(world)
    r = world.run("status")
    assert "claude" in r.stdout and "antigravity" in r.stdout


def test_owner_values_are_validated(world):
    """TASK-179#4 an owner outside claude/antigravity/claude-other is a manifest error (exit 2)."""
    (world.manifest / "repos.tsv").write_text(f"alpha\t{world.url_alpha}\tsomeone\n")
    r = world.run("owner", "alpha")
    assert r.returncode == 2
    assert "담당" in r.stdout + r.stderr


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


def test_tools_default_subcommand_is_status(tools):
    """`workspace tools` with no subcommand behaves like `tools status`."""
    r = tools.run("tools")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "OK" in r.stdout


def test_tools_invalid_provider_fails_cleanly(tools):
    """An unknown provider in tools.tsv is a manifest error (exit 2), not a traceback."""
    tools.write_manifest(extra_rows=("bad\tnpm\tbad",))
    r = tools.run("tools", "status")
    assert r.returncode == 2
    assert "Traceback" not in r.stderr
    assert "npm" in r.stderr


def test_tools_capture_keeps_row_of_unresolvable_command(tools):
    """capture keeps the existing row of a command whose link does not resolve, and skips (warns) an unknown one."""
    shutil.rmtree(tools.prefix / "Cellar" / "ripgrep")
    os.symlink("../nowhere", tools.root / "bin" / "ghost")
    r = tools.run("tools", "capture")
    assert r.returncode == 0, r.stdout + r.stderr
    rows = data_lines(tools.manifest / "tools.tsv")
    assert "rg\tbrew\tripgrep" in rows
    assert not any(row.startswith("ghost\t") for row in rows)
    assert "ghost" in r.stdout + r.stderr


def test_tools_install_step_timeout(tools):
    """A hanging install command is killed after WORKSPACE_TOOLS_TIMEOUT and the run exits 1."""
    shutil.rmtree(tools.home / ".local" / "share" / "uv" / "tools" / "vulture")
    _exe(tools.fakebin / "uv", "exec sleep 30\n")
    r = tools.run("tools", "install", extra_env={"WORKSPACE_TOOLS_TIMEOUT": "1"})
    assert r.returncode == 1, r.stdout + r.stderr
    assert "timeout" in (r.stdout + r.stderr).lower()


def test_tools_build_skipped_when_repo_missing(tools):
    """A repo build whose repository is not cloned yet is reported (run bootstrap first), not attempted."""
    shutil.rmtree(tools.root / "fac")
    r = tools.run("tools", "install")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "bootstrap" in r.stdout + r.stderr
    assert tools.calls() == []
