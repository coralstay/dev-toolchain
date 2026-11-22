---
id: DRAFT-20
title: 'workspace: 저장소별 에이전트 담당 열과 workspace owner 명령'
status: Draft
assignee: []
created_date: '2026-11-22T11:20:00Z'
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
