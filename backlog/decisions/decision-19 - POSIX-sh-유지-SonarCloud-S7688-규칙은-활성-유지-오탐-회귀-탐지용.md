---
id: decision-19
title: 'POSIX sh 유지, SonarCloud S7688 규칙은 활성 유지 (오탐 회귀 탐지용)'
date: '2026-09-10 01:13'
status: accepted
---
## Context

SonarCloud가 `shelldre:S7688`("Use `[[` instead of `[` for conditional
tests")을 이 저장소 전체에서 14건 지적했다. 이 룰은 `bash` 태그가 붙어 있고
`[[`(bash 확장, POSIX sh엔 없음) 사용을 권장한다 — 이 저장소가 TASK-71에서
POSIX sh(`local`만 예외로 인정)를 명시적으로 채택했으므로 명백한 오탐이다.

사용자가 "이 참에 bash로 전환할지 고민된다"고 문제 제기해서, POSIX sh를 계속
유지할 근거가 아직도 유효한지 다시 검증했다:

1. **`sh`가 항상 bash라는 보장이 없다.** 이 저장소의 실제 진입점
   (`install.sh`/`uninstall.sh`의 `#!/usr/bin/env sh`, 그리고 README가
   안내하는 `curl -fsSL ... | sh`)은 전부 **PATH에 잡히는 `sh`**에 의존한다.
   이 세션에서 실측한 개발자 macOS 환경에서는 `/bin/sh`가 bash 3.2를 posix
   모드로 돌리는 것이라 `[[`가 실제로 동작하지만, 이건 `/bin/sh`를 직접
   호출했을 때 얘기지 `sh`가 PATH 어디서 잡힐지까지 보장하진 않는다 — 배포
   대상이 넓어지면 이 통제권 자체가 없어진다.
2. **애플의 전례.** 애플은 GPLv3 문제로 bash를 3.2에 동결해뒀고, 과거 여러
   GNU 도구를 자기 것으로 교체해왔다(대화형 기본 셸을 zsh로 바꾼 것 등).
   `/bin/sh`가 미래에 진짜 최소 POSIX 셸로 바뀔 가능성은 개인 스크립트라면
   "나만 고치면 되는" 문제지만, 배포된 설치기는 사용자 수만큼 조용히 broken
   설치가 퍼지는 문제가 된다.
3. **`set -eu`(`-o pipefail` 포함)로는 이 문제를 못 막는다 — 실제로 dash에서
   검증함.** `if [[ ... ]]; then ... fi` 형태는 POSIX 표준상 `-e`의 즉시종료
   대상에서 면제되는 위치(if/while의 조건절)라서, dash가 `[[`를
   "command not found"(exit 127)로 처리해도 스크립트가 죽지 않고 그 조건을
   조용히 "거짓"으로 취급한 채 **끝까지 정상 종료(`exit 0`)**된다:
   ```
   $ dash -c '
   set -eu
   echo "before"
   if [[ 1 -eq 1 ]]; then echo "true branch"; else echo "false branch (wrong!)"; fi
   echo "after — script did NOT abort"
   '
   before
   dash: 4: [[: not found
   false branch (wrong!)
   after — script did NOT abort, exit code will be 0
   ```
   반대로 가드절 형태(`[[ ... ]] || { ... exit 1; }`)는 `-e` 면제 대상이
   아니라서 정상적으로 즉시 실패한다(`dash: [[: not found` → 명시적
   `exit 1`). 즉 `[[`가 코드베이스 어디에 있느냐에 따라 "죽지도 않고 안전
   장치가 조용히 무력화"되는 게 제일 위험한 실패 모드이고, `-o pipefail`은
   애초에 dash가 모르는 옵션이라(`Illegal option -o pipefail`) 시도하는
   것만으로 별도의 호환성 문제가 된다. 또한 이 프로젝트의 m-13 안전장치들
   (prior-state 게이팅 등)이 정확히 `if` 조건으로 짜여 있어서, `[[`가 여기
   섞여 들어가면 "안전장치가 조용히 항상 거짓으로 평가"되는 최악의 시나리오가
   가능하다.
4. **실제 사례 조사.** 이 저장소와 가장 비슷한 도구(언어 툴체인 설치기)인
   rustup의 `rustup-init.sh`를 직접 열어봤다:
   - shebang이 `#!/bin/sh`, 배포 명령도 `curl ... | sh`(bash 아님)
   - 스크립트 내 주석 원문: *"It runs on Unix shells like {a,ba,da,k,z}sh.
     It uses the common `local` extension."* — **`local`만 예외로 인정**하고
     나머지는 순수 POSIX. 이 저장소의 TASK-71 정책과 거의 동일하다.
   - 이 저장소가 이미 체크섬까지 고정해서 신뢰하는 Homebrew 공식 설치
     스크립트도 같은 이유로 POSIX 계열을 겨냥한다.
   - 반대 사례: nvm은 `curl -o- ... | bash`로 **`bash`를 명시적으로 못박아서**
     "PATH의 `sh`가 뭘 가리킬지 모른다"는 문제 자체를 회피한다 — 대신 배포
     방식으로 bash를 강제하는 비용을 짐. oneuptime.com의 정리: "오픈소스로
     배포되거나 어떤 환경에서 돌지 통제 불가능하면 POSIX가 시간을 아껴주고,
     본인이 통제하는 환경에서만 돈다면 bash 써도 된다." 이 저장소는 명백히
     전자(공개 저장소, `curl \| sh`로 불특정 다수 macOS에 배포)에 해당한다.

## Decision

**POSIX sh를 그대로 유지한다.** bash로 전환하지 않는다 — 위 근거(특히 3번,
안전장치가 조용히 무력화될 수 있다는 실증 결과)가 여전히 유효하고, 가장
비슷한 실제 사례(rustup)가 동일한 정책을 쓰고 있다는 것도 확인했다.

**SonarCloud `shelldre:S7688` 룰은 Quality Profile에서 비활성화하지 않고
계속 활성 상태로 둔다.** 오탐인 건 맞지만, 사용자 결정: "아니 S7688은
오탐이라도 탐지하는걸로하자" — 규칙을 꺼버리면 앞으로 누군가 실수로(또는
IDE 자동완성으로) `[[`를 코드베이스에 넣어도 아무도 모르게 된다. 규칙을
켜둔 채로 두면 m-14의 `check-hardcoded-paths.sh` 린트와 같은 성격의 **회귀
탐지 카나리아**로 계속 작동한다 — 오탐인 걸 알면서도 "이 프로젝트에 진짜
bash 문법이 섞여 들어오는지" 감시하는 용도로 의도적으로 남겨두는 것이다.

**기존 오탐 14건(S7688) + 이미 고친 1건(S6506, GitHub Issue #7)은
SonarCloud 쪽을 전혀 건드리지 않고 GitHub Issue만 사용자가 수동으로 close
처리했다.** 2026-09-10 기준 실측 상태:
- SonarCloud API(`api/issues/search?...&resolved=false&rules=shelldre:S7688`):
  여전히 14건 `resolved=false`(미해결) — 의도적으로 그대로 둠.
- GitHub Issues #2~6, #8~16(S7688) + #7(S6506): 전부 `CLOSED` — 사용자가
  SonarCloud API/UI는 전혀 거치지 않고 GitHub에서 직접 닫음.

## Consequences

- **SonarCloud=미해결 / GitHub=닫힘이라는 불일치는 의도적이며 영구적으로
  남는다.** decision-18의 자동 동기화 파이프라인(TASK-155)이 이 14건을
  나중에 재발행하거나 잘못 재처리하지 않는 이유를 명시해둔다: "발행" step은
  `gh issue list --state all`로 이미 존재하는 이슈를 확인하므로(닫힌 것도
  포함) 중복 재발행하지 않고, "close" step은 `--state open`만 순회하므로
  이미 닫힌 이슈는 애초에 처리 대상이 아니다. 즉 아무 자동화도 이 14건을
  건드리지 않는 안정적인 최종 상태다.
- 이 불일치를 보고 "SonarCloud 쪽 상태가 왜 안 맞냐"고 나중에 누군가 고치려
  들 수 있다 — 이 decision이 그 질문에 대한 답이다. **고칠 필요 없음.**
- S7688 룰이 계속 켜져 있으므로, 향후 이 저장소에 실수로 `[[`가 들어오면
  SonarCloud가 새 이슈로 잡고 decision-14/18 파이프라인이 새 GitHub Issue를
  발행한다 — 이게 의도된 동작이다(리뷰 시 "왜 또 S7688이 떴지"라고 놀랄
  필요 없이, 대신 그 PR의 `[[` 사용 자체를 되돌리는 게 맞는 대응이다).
- 상세 리서치 원자료(rustup 인용문 전체, dash 실증 테스트, 출처 링크)는
  `docs/posix-sh-vs-bash-research.md`에 별도 정리한다(TASK-157) — 이
  decision은 결론만, 그 문서는 근거 원자료를 담는다.
