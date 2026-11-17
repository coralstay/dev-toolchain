---
id: TASK-176
title: 'workspace: 저장소 배치·심볼릭 링크를 목록 파일(SSOT)로 관리하고 복원한다'
status: In Progress
assignee: []
created_date: '2026-11-17T12:55:00Z'
updated_date: '2026-11-17T13:25:00Z'
labels:
  - workspace
  - symlink
  - ssot
dependencies: []
documentation:
  - /Users/flynn_macpro/.claude/plans/happy-honking-bird.md
  - README.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
유저 결정(2026-11-17): ~/githubs 의 저장소 배치(경로→원격)와 심볼릭 링크 약 113개(~/githubs/bin 53, 워크스페이스 별칭 3, 홈 57)를 목록 파일로 dev-toolchain 에 담고(방식 A), 복원 명령이 실체를 만든다. 오픈소스는 이미 .tool-versions(@oss)+oss_sync 가 관리하므로 범위 밖. 테스트도 작성한다.
유저 결정(같은 날): dev-toolchain 은 전체를 py 로 옮긴다(별도 draft). 그래서 이 카드의 새 명령은 처음부터 py 로 쓴다.
계획: ~/.claude/plans/happy-honking-bird.md (승인됨, 구현 언어만 sh→py 로 바뀜)

## 범위
- workspace/repos.tsv (경로<TAB>원격 URL), workspace/links.tsv (범위 githubs|home<TAB>링크<TAB>대상, $HOME 은 ~ 로 표기)
- scripts/workspace.py (표준 라이브러리만, 시스템 python3 3.9 에서도 동작): status(기본) / link [--force] / bootstrap / capture, --dry-run 과 DRY_RUN=true 지원, git clone 타임아웃
- install.sh 위임 목록에 workspace 추가(exec python3 scripts/workspace.py), help·README 갱신
- tests/test_workspace.py (pytest): 가짜 HOME·가짜 루트(tmp_path)·로컬 bare 저장소로 네트워크 없이 검증

## 비즈니스 규칙
- B1 (AC #3) link 는 실제 파일·폴더를 절대 덮어쓰지 않는다(NOT-A-LINK 는 보고만)
- B2 (AC #3) 대상이 다른 링크는 --force 없이는 바꾸지 않는다
- B3 (AC #4) bootstrap 은 이미 있는 저장소 폴더를 건드리지 않는다(pull·reset·remote 변경 없음)
- B4 (AC #1) 목록에 홈 절대 경로(/Users/<이름>)가 들어가지 않는다
- B5 (AC #5) capture 는 결정적이다 — 같은 상태에서 두 번 돌리면 diff 0

## 하지 않는 것
기존 sh 스크립트의 py 전환(별도 draft), 링크 정리·정규화, 저장소 커밋 고정, 루트 README 트리 수정(각각 별도 draft), CI 에 테스트 추가

## 알고 가는 것
공개 저장소(dev-toolchain)에 비공개 저장소 9개의 이름·URL 이 목록으로 공개된다
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 repos.tsv·links.tsv 가 지금 머신을 그대로 담는다(저장소 21, 링크 약 113). 형식 설명이 파일 머리 주석에 있고 홈 절대 경로가 없다(B4)
- [ ] #2 status 가 상태 분류(저장소 OK/MISSING/WRONG-REMOTE, 링크 OK/MISSING/WRONG-TARGET/NOT-A-LINK/DANGLING, 목록 밖 UNTRACKED)와 종료 코드(어긋남 있으면 1)를 지키고 지금 머신에서 0 이다
- [x] #3 link 가 없는 링크만 만들고 멱등이며 --dry-run 이면 부작용이 없다. 실제 파일·폴더는 덮어쓰지 않고(B1) 대상이 다른 링크는 --force 일 때만 바꾼다(B2)
- [x] #4 bootstrap 이 없는 저장소만 clone 한 뒤 링크를 만들고, 이미 있는 저장소 폴더는 건드리지 않는다(B3)
- [x] #5 capture 가 결정적이고(B5) 지금 머신에서 다시 돌려도 목록 diff 가 0 이다
- [x] #6 dev-toolchain workspace … 로 호출되고 help·README(오픈소스 절 옆 새 절 + CLI 사용법 + 구조 표)가 갱신된다
- [x] #7 tests/test_workspace.py 가 위를 샌드박스(tmp_path 가짜 HOME·루트, 로컬 bare 저장소, 네트워크 없음)에서 검증하고 테스트 이름에 <ID>#n·<ID>#Bk 표식이 있다
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 pytest 전체 통과와 기존 shellspec(sh·dash) 회귀 없음 출력을 Notes 에 첨부
- [x] #2 ruff check 통과, 시스템 python3(3.9)로 workspace.py --help 실행 확인, source-header lint --strict 0
- [x] #3 새 파일에 헤더·줄 끝 표식·하단 노트가 있다
- [ ] #4 실제 머신에서 status 종료 0 과 capture 후 git diff --exit-code workspace/ 0 출력을 첨부
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### Subjective
유저(2026-11-17)가 ~/githubs 의 저장소 배치와 심볼릭 링크를 GitHub 저장소에 표현할 방법으로 방식 A(목록 파일 SSOT + 복원 명령)를 골랐고 테스트도 작성하자고 했다. 이어서 dev-toolchain 전체를 py 로 옮기기로 해 이 명령은 처음부터 py 로 쓴다. 계획: ~/.claude/plans/happy-honking-bird.md

### Objective
- 오픈소스는 .tool-versions(@oss) + scripts/oss_sync.sh 가 이미 관리한다. install.sh:80-85 가 status/current/project/sync/help 를 oss_sync.sh 로 위임한다.
- 기록 없는 링크: ~/githubs/bin 53, 워크스페이스 별칭 3(ebpf, freeride/dev-toolchain, README.md), 홈 57(~/.local/bin 54, ~/.tool-versions, oh-my-zsh 플러그인 2). 저장소 21개.
- 이 머신의 python3 는 asdf 3.12, 시스템 /usr/bin/python3 는 3.9. 새 Mac 에서 asdf 설치 전에도 돌려면 3.9 호환·표준 라이브러리만 써야 한다.
- 이 저장소에 아직 py 코드·pytest 설정이 없다(테스트는 shellspec). source-header 저장소는 uvx --with pytest 로 테스트한다.

### Assessment
목록 파일은 TSV 두 개(repos, links). scripts/workspace.py 가 argparse 서브커맨드 status/link/bootstrap/capture 를 맡는다. 경로·HOME·목록 위치는 환경변수(WORKSPACE_ROOT, WORKSPACE_MANIFEST_DIR, HOME)로 덮어써 테스트한다. 테스트는 원격 대신 로컬 bare 저장소를 써 네트워크 없이 돌린다. 기존 sh 의 py 전환·링크 정리·커밋 고정·루트 README 는 후속 draft 로 분리한다.

### Plan
1. 테스트 먼저: tests/test_workspace.py 에 AC #1~#5 와 B1~B5 를 표식과 함께 쓴다(실패 확인). .claude-code-agile-hooks.json 에 testCommand 는 유저 확인 없이 추가하지 않는다.
2. scripts/workspace.py 구현(status → link → bootstrap → capture), 헤더·표식·노트.
3. install.sh 위임 목록·oss_sync.sh help/노트 갱신, README 절 추가.
4. 실제 머신에서 capture 로 workspace/*.tsv 생성 → status 0 확인.
5. 전체 검증(pytest, ruff, 시스템 python3, shellspec 회귀, lint) 후 Notes 첨부, PR.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 2026-11-17 구현·검증 (서브에이전트 구현, 아래는 내가 직접 다시 돌린 결과)
- 커밋: 004cc68(테스트) → 198603b(workspace.py, install.sh 위임, oss_sync help·노트, lint 스캔 목록) → 1796808(목록 데이터) → f8c2ac6(README)
- 테스트 먼저: 구현 전 26 failed → 구현 후 pytest 26 passed. 표식 TASK-176#1~#6, #B1~#B5 모두 있음
- 회귀: shellspec 228 examples 0 failures(sh), 228 0 failures(--shell dash)
- ruff check 통과, /usr/bin/python3(3.9.6) workspace.py --help 동작, sh -n install.sh 통과, check-hardcoded-paths OK(workspace.py 를 스캔 목록에 추가), source-header lint --strict rc=0, 표식 9·노트 9
- 실제 머신 capture: 저장소 21, 링크 114(githubs 57 = bin 54 + 별칭 3, home 57). 목록에 /Users/ 0건. 두 번째 capture 체크섬 동일(B5)
- 실제 머신 status: 정상 133, 어긋남 2, UNTRACKED 0 → rc=1. 어긋남은 DANGLING 2건: bin/agent-orchestrator → coralstay-software-factory/components/agent-orchestrator/build/install/agent-orchestrator/bin/agent-orchestrator(빌드 산출물 없음, 이번 변경 전부터 끊김)과 이를 가리키는 ~/.local/bin/agent-orchestrator. 유저 결정 대기
- link --dry-run · bootstrap --dry-run: 실행할 작업 0(위 2건만 보고). 실제 머신에 link/bootstrap 실행 안 함
- 구현 선택: 테스트용 WORKSPACE_OWNER_PATTERNS, UNTRACKED 는 저장소에도 적용, link 는 DANGLING 을 실패로 세지 않음(status 는 어긋남으로 셈), clone 실패·시간 초과 시 이번에 만든 폴더만 지움, 목록 없으면 status rc=2
<!-- SECTION:NOTES:END -->
