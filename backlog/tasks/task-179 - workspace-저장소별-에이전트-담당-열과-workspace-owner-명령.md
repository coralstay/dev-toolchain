---
id: TASK-179
title: 'workspace: 저장소별 에이전트 담당 열과 workspace owner 명령'
status: To Do
assignee: []
created_date: '2026-11-22T11:20:00Z'
updated_date: '2026-11-22T11:20:00Z'
labels:
  - workspace
  - agents
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
유저 결정(2026-11-22): 저장소를 나눠 갖는다. Claude 는 백로그·훅 규칙 안에서, Antigravity 는 자기 담당 저장소에서 자유롭게 일하고, 남의 담당 저장소는 건드리지 않는다. 지금 분담은 대화·메모리에만 있다 — 두 에이전트가 같은 곳에서 읽을 기록이 필요하다.
- Claude(이 세션): coralstay-software-factory, agent-orchestrator, claude-code-agile-hooks, coding-agent-git-commit-tool, dev-toolchain, source-header, .github-profile, troubleshooting, upkeep
- Antigravity: central-docs-collector, omnivim, freeride(루트), handcrafted-python·cpp·java, databases, coding-style-refactoring-principles, devOps-LifeCycle, doctree (+ freeride 아래 저장소 아닌 폴더 7개)
- 다른 Claude 세션: ebpf-wire-to-code-tracer, toy-project
계획: ~/.claude/plans/agent-repo-split-record.md (승인됨). 후속: agile-hooks(Claude 안내문 한 줄), upkeep(Antigravity 규칙 원본·설치)

## 범위
- workspace/repos.tsv 3번째 열 '담당'(claude · antigravity · claude-other), 헤더에 '경로의 담당 = 그 경로를 품은 가장 가까운 목록 저장소의 담당' 규칙
- scripts/workspace.py: load_repos 가 담당 열을 읽음, capture 가 담당 값 보존, status 에 담당 표시, 새 서브커맨드 workspace owner <경로>

## 비즈니스 규칙
- B1 (AC #1) 담당 SSOT 는 repos.tsv 하나다
- B2 (AC #2) capture 는 담당 값을 지우지 않는다
- B3 (AC #3) 목록에 없는 경로의 담당은 unknown 이다

## 하지 않는 것
훅으로 편집 막기, 안내문 수정(다른 저장소 카드)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 workspace/repos.tsv 의 21행이 모두 3번째 열 담당(claude · antigravity · claude-other)을 가지며 유저가 정한 분담과 일치하고, 헤더에 형식과 '가장 가까운 목록 저장소' 규칙이 있다(B1)
- [ ] #2 workspace capture 가 기존 담당 값을 보존하고(B2), 다시 돌려도 repos.tsv diff 0 이다
- [ ] #3 dev-toolchain workspace owner <경로> 가 상대(githubs 루트 기준)·절대 경로 모두에서 가장 가까운 상위 목록 저장소의 담당을 출력하고, 목록 밖이면 unknown(B3)을 낸다. status 도 담당을 보여 준다
- [ ] #4 tests/test_workspace.py 가 위를 샌드박스와 커밋된 목록으로 검증하고 테스트에 <ID>#n·<ID>#Bk 표식이 있다
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 pytest 전체·ruff·/usr/bin/python3 실행·shellspec 회귀 없음·source-header lint 0 출력을 Notes 에 첨부
- [ ] #2 실제 머신: owner freeride/doctree → antigravity, owner upkeep → claude, owner freeride/math → antigravity, owner /tmp → unknown 출력 첨부
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### Subjective
유저(2026-11-22)가 저장소를 Claude·Antigravity·다른 Claude 세션이 나눠 갖기로 했다. 두 에이전트가 함께 볼 담당 기록이 필요하다. 계획: ~/.claude/plans/agent-repo-split-record.md

### Objective
- workspace/repos.tsv(TASK-176)는 <경로><TAB><원격 URL> 21행, scripts/workspace.py 의 load_repos·render·cmd_capture 가 읽고 쓴다(REPOS_HEADER 상수, capture 는 머리를 상수로 다시 쓴다).
- tools.tsv(TASK-178)는 capture 가 기존 비고를 보존하는 선례가 있다.
- freeride 아래 저장소 아닌 폴더 7개는 repos.tsv 에 없다.

### Assessment
담당을 repos.tsv 의 열로 두면 저장소 목록 SSOT 하나에 모인다. 폴더는 '가장 가까운 상위 목록 저장소' 규칙으로 따로 행 없이 결정한다. 조회는 workspace owner 명령 하나로 안내문들이 가리키게 한다.

### Plan
1. 테스트 먼저: 담당 열 읽기·보존, 상위 저장소 규칙, unknown, 커밋된 목록 21행 일치 — 실패 확인.
2. REPOS_HEADER·load_repos·capture·status·owner 서브커맨드 구현, repos.tsv 에 담당 열 기입.
3. 검증, 실제 머신 owner 출력, 커밋, PR.
<!-- SECTION:PLAN:END -->
