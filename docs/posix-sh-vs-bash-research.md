# POSIX sh vs bash 리서치 기록 (decision-19)

decision-19("POSIX sh 유지, SonarCloud S7688 규칙은 활성 유지")의 결론만 보면
근거가 압축돼 있어서, 나중에 더 깊이 파볼 사람(본인 포함)을 위해 조사 원자료를
그대로 남겨둔다. 이 문서는 결론이 아니라 **근거 자료 모음**이다 — 결론은
decision-19를 보라.

## 계기: SonarCloud shelldre:S7688

SonarCloud가 이 저장소 전체에서 14건 지적한 룰.

```
key: shelldre:S7688
name: Use "[[" instead of "[" for conditional tests
type: CODE_SMELL, severity: MAJOR
impact: RELIABILITY / HIGH
tags: bash, best-practices, scripting, shell
createdAt: 2025-10-03
```

같이 다룬 `shell:S6506`(이미 TASK-153/154로 실제 수정됨, GitHub Issue #7)도
참고용으로 남긴다:

```
key: shell:S6506
name: HTTPS should be enforced on HTTP clients following redirects
type: VULNERABILITY, severity: MAJOR
impact: SECURITY / MEDIUM
securityStandards: cwe:757
createdAt: 2025-11-25
```

`shelldre:`와 `shell:`은 SonarCloud가 "Shell" 언어에 대해 같이 굴리는
서로 다른 두 룰 저장소(엔진)다 — 둘 다 2025년 하반기에 생성된, 비교적 최근에
확장된 룰셋이다.

## 실제 사례 조사: 누가 어떻게 하고 있나

### rustup — 이 저장소와 가장 비슷한 사례 (POSIX sh 진영)

`rustup-init.sh`(https://raw.githubusercontent.com/rust-lang/rustup/master/rustup-init.sh)를
직접 열어서 확인:

- shebang: `#!/bin/sh`
- 배포 명령: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
  (`bash`가 아니라 `sh`)
- 스크립트 내 주석 원문(WebFetch로 직접 확인):
  > "It runs on Unix shells like {a,ba,da,k,z}sh. It uses the common `local`
  > extension. Note: Most shells limit `local` to 1 var per line, contra bash."
- `local` 키워드가 없는 셸(옛 ksh 일부)을 위한 폴백까지 준비:
  > "Some versions of ksh have no `local` keyword."
- zsh의 기본 word-splitting 비활성화 문제를 `is_zsh() { [ -n "${ZSH_VERSION-}" ]; }`
  같은 셸 감지 함수로 개별 방어.

→ **`local`만 예외로 인정하고 나머지는 순수 POSIX**라는 정책이 이 저장소의
TASK-71 컨벤션과 사실상 동일하다. 언어 툴체인 설치기라는 도메인까지 같아서
가장 직접적으로 참고할 만한 선례다.

참고: https://forge.rust-lang.org/infra/other-installation-methods.html

### Homebrew 공식 설치 스크립트 — 이 저장소가 이미 신뢰하는 대상

이 저장소(`scripts/install/01_bootstrap_asdf.sh`)가 체크섬까지 고정해서
받아오는 Homebrew의 공식 설치 스크립트도 같은 이유로 POSIX 계열을 겨냥한다 —
"어떤 시스템에 배포될지 통제할 수 없는 curl-pipe 진입점"이라는 조건이 이
저장소와 완전히 같기 때문이다.

### nvm — 반대 진영 (bash 강제)

nvm(https://github.com/nvm-sh/nvm)은 정반대 선택을 한다:

- 배포 명령: `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash`
  — **`bash`를 명시적으로 못박음**
- 내부적으로는 POSIX 계열 문법을 많이 쓰지만, 진입점 자체를 "무조건 bash로
  실행되게" 강제해서 "PATH의 `sh`가 뭘 가리킬지 모른다"는 문제 자체를
  없애버린다.

### 판단 기준

oneuptime.com의 POSIX 셸 호환성 가이드
(https://oneuptime.com/blog/post/2026-02-13-posix-shell-compatibility/view)의
정리가 실용적이다:

> If you stick to POSIX features, your script will work with dash, ash, ksh,
> bash, and the native sh on BSD systems, Solaris, and macOS. If your script
> only runs on systems you control ... write it in Bash ... For scripts that
> ship with open-source projects, run in Docker containers with unknown base
> images, or execute in CI pipelines across different runners, POSIX
> compatibility saves hours of debugging.

이 저장소는 공개 저장소이고 `curl | sh`로 불특정 다수의 macOS에 배포되므로
후자(POSIX)에 해당한다는 게 이번 조사의 핵심 결론이다.

## 실증 테스트: `set -eu`로 막을 수 있나?

"strict mode(`set -euo pipefail`)를 걸면 `[[` 미지원 셸에서도 안전하게
막히지 않을까?"라는 질문을 실제로 dash(Debian/Ubuntu 기본 `/bin/sh`,
Homebrew로 macOS에 설치 가능)에 걸어서 검증했다.

**케이스 1 — `[[`가 `if` 조건절에 쓰인 경우 (이 저장소의 실제 관용구 형태):**

```console
$ dash -c '
set -eu
echo "before"
if [[ 1 -eq 1 ]]; then
  echo "true branch"
else
  echo "false branch (wrong!)"
fi
echo "after — script did NOT abort"
'
before
dash: 4: [[: not found
false branch (wrong!)
after — script did NOT abort, exit code will be 0
```

`set -eu`가 걸려 있어도 스크립트가 **죽지 않고 끝까지 정상 종료(`exit 0`)**
됐다. POSIX 표준이 `if`/`while`의 조건절에 쓰인 명령을 `-e`의 즉시종료
대상에서 명시적으로 면제하기 때문이다 — `[[`가 "command not found"(exit 127)
로 실패해도 그건 그냥 "조건이 거짓이었다"로 취급되고, `else` 브랜치가
아무 경고 없이(stderr 한 줄 빼고) 실행된다. `set -o pipefail`을 추가로
시도하면 그것부터 dash가 모르는 옵션이라 별도로 깨진다:

```console
$ dash -c 'set -o pipefail; echo "pipefail ok"'
dash: 1: set: Illegal option -o pipefail
```

**케이스 2 — `[[`가 가드절(`||`) 형태로 쓰인 경우:**

```console
$ dash -c '
set -eu
echo "before"
[[ 1 -eq 1 ]] || { echo "guard failed"; exit 1; }
echo "after — did this print?"
'
before
dash: 4: [[: not found
guard failed
exit code: 1
```

이번엔 정상적으로 즉시 실패했다 — `||`의 오른쪽 명령은 `-e` 면제 대상이
아니기 때문이다.

**결론**: `[[`가 코드베이스의 *어디에* 쓰이느냐에 따라 실패 모드가 완전히
달라진다. `if` 조건문에 쓰이면 (이 저장소의 안전장치 대부분이 이 형태다 —
예: m-13의 prior-state 게이팅) **가장 위험한 "조용히 잘못된 분기로 계속
실행"**이 되고, 가드절(`|| return 1`) 형태면 그나마 안전하게 즉시 실패한다.
`set -eu`/`-o pipefail`은 이 중 어느 쪽도 사전에 통일되게 막아주지 않는다.

## 참고 링크

- [rustup-init.sh (raw)](https://raw.githubusercontent.com/rust-lang/rustup/master/rustup-init.sh)
- [Rust Forge — Other Installation Methods](https://forge.rust-lang.org/infra/other-installation-methods.html)
- [nvm-sh/nvm](https://github.com/nvm-sh/nvm)
- [Writing POSIX-Compatible Shell Scripts for Maximum Portability (oneuptime.com)](https://oneuptime.com/blog/post/2026-02-13-posix-shell-compatibility/view)
- [checkbashisms(1) — Arch manual pages](https://man.archlinux.org/man/checkbashisms.1.en)
- [decision-19](../backlog/decisions/decision-19%20-%20POSIX-sh-유지-SonarCloud-S7688-규칙은-활성-유지-오탐-회귀-탐지용.md) — 이 리서치의 공식 결론
