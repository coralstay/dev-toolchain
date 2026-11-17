---
id: decision-24
title: dev-toolchain 을 py 로 전환, curl|sh 진입점만 POSIX sh 유지 - decision-19 의 셸 유지 결정을 뒤집음
date: '2026-11-17T13:30:00Z'
status: accepted
---
## Context

decision-19(2026-09-10)는 "bash 로 전환할지"라는 질문에 POSIX sh 유지로 답했다. 그때 비교한 선택지는 sh 와 bash 뿐이었다.

2026-11-17 유저가 dev-toolchain 전체를 py 로 옮기기로 결정했다("충돌되는 그 결정 새로운 결정으로 바꿔 py 로 한다").
배경:
- 유저의 다른 도구(claude-code-agile-hooks 등)는 유지보수성을 이유로 이미 sh 에서 py 로 옮겼다.
- TASK-176 의 새 명령 `workspace`는 처음부터 py(`scripts/workspace.py`, 표준 라이브러리만, pytest)로 썼다.
- 셸 코드는 `scripts/lib.sh` 약 1,600줄, `oss_sync.sh` 약 400줄과 install/uninstall 단계 스크립트로 커졌다. 테스트는 shellspec 228개다.

decision-19 의 근거 중 "PATH 의 `sh` 가 무엇일지 모르는 환경에 `curl | sh` 로 배포된다"는 점은 py 전환 뒤에도 그대로 남는다.
새 Mac 에는 python3 가 없을 수 있다. Xcode Command Line Tools 가 설치되기 전이면 `/usr/bin/python3` 는 설치를 권하는 대리 실행 파일일 뿐이다.

## Decision

1. **dev-toolchain 의 내부 구현은 py 로 옮긴다.** 새 코드는 py 로 쓰고, 기존 셸 스크립트는 DRAFT-19 를 단계별 카드로 쪼개 옮긴다.
2. **py 코드는 표준 라이브러리만 쓰고 시스템 python3(3.9)에서 돈다.** asdf 로 python 을 설치하기 전 단계에서도 실행되어야 하기 때문이다.
3. **`curl | sh` 원격 설치 진입점(`install.sh`)은 POSIX sh 로 남긴다.** python3 가 쓸 수 있는지 확인되기 전의 부트스트랩 구간도 같은 이유로 sh 로 남긴다. 이 구간에는 decision-19 의 POSIX 규칙(`local` 만 예외, `[[` 금지)이 그대로 적용된다.
4. decision-19 의 SonarCloud `shelldre:S7688` 활성 유지 결정은 바꾸지 않는다. 남는 sh 코드에 대한 회귀 탐지로 계속 쓴다.
5. decision-19 는 status 를 `superseded by decision-24` 로 바꾼다. 위 3·4 항목에 한해서는 근거로 유효하다.

## Consequences

- 단계별 전환 카드는 기존 shellspec 스위트를 블랙박스 회귀 테스트로 먼저 고정한 뒤 옮긴다(DRAFT-19).
- 저장소 CLAUDE.md 의 "순수 POSIX sh 프로젝트" 설명과 docs/shell-style-guide.md 의 적용 범위는 전환이 진행되면서 "sh 로 남는 구간" 기준으로 고친다. 이 decision 만으로는 고치지 않는다.
- 셸과 py 가 섞인 기간에는 검증 명령이 둘이다. sh 쪽은 shellcheck → dash -n → shellspec(sh·dash), py 쪽은 ruff → pytest → `/usr/bin/python3` 실행 확인이다.
- `scripts/lint/check-hardcoded-paths.sh` 규칙은 py 코드에도 적용한다. TASK-176 에서 `scripts/workspace.py` 를 스캔 목록에 넣었다.

