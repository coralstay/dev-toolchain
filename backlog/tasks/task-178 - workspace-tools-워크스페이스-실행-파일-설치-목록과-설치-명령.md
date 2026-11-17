---
id: TASK-178
title: 'workspace tools: 워크스페이스 실행 파일 설치 목록과 설치 명령'
status: In Progress
assignee: []
created_date: '2026-11-17T14:11:00Z'
updated_date: '2026-11-17T14:30:00Z'
labels:
  - workspace
  - install
dependencies:
  - TASK-177
references:
  - TASK-176
  - TASK-177
  - decision-24
documentation:
  - /Users/flynn_macpro/.claude/plans/dev-toolchain-workspace-tools.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
유저(2026-11-17): 이 프로젝트를 쓰려면 설치해야 하는 실행 파일을 모두 리스트업하고 설치 방법까지 스크립트로 만든다. 업스트림 소스 빌드는 하지 않는다(지금 방향 유지: 진입점 ~/githubs/bin, 실체는 Homebrew 등). 범위는 ~/githubs/bin 명령 54개 + 선행 도구.
계획: ~/.claude/plans/dev-toolchain-workspace-tools.md (승인됨)

## 확인한 사실
- bin 54개 실체: Homebrew formula 31, cask 1(tflint), opensource sync 6(yq·fzf·fzf-tmux·bats·shellspec·backlog), uv tool 1(vulture), 시스템 1(/usr/bin/jq), 내 저장소 15(빌드 필요 2: agent-orchestrator installDist, doctree .venv)
- Homebrew 패키지를 설치하는 곳이 없다: oss_sync.sh populate_ref_bins 는 /opt/homebrew/bin/<x> 가 이미 있을 때만 링크한다 → 새 Mac 에서 bin 절반 이상이 끊긴다
- Xcode CLT·Homebrew·asdf·런타임은 dev-toolchain install 이 맡는다. claude CLI(cask claude-code), Secretive(cask)도 필요하다
- decision-24: 새 코드는 py(표준 라이브러리, 시스템 python3 3.9)

## 범위
- workspace/tools.tsv: 명령<TAB>공급자(brew|cask|uv-tool|oss|repo|system|prereq)<TAB>패키지<TAB>비고(빌드 명령 등)
- dev-toolchain workspace tools status | install [--dry-run] | capture (scripts/workspace.py 확장)
- install 순서: prereq 확인 → brew → cask → uv tool → dev-toolchain sync → 저장소 빌드 → workspace link
- README '새 Mac 에서 처음부터' 절

## 비즈니스 규칙
- B1 (AC #3) install 은 빠진 것만 설치한다. 업그레이드·삭제하지 않는다
- B2 (AC #1) links.tsv 의 githubs bin/* 이름 집합과 tools.tsv 명령 집합이 같다
- B3 (AC #3) sudo·GUI 가 필요한 선행 도구(Xcode CLT, Homebrew)는 안내만 하고 직접 설치하지 않는다
- B4 (AC #3) --dry-run 은 아무 명령도 실행하지 않는다
- B5 (AC #4) capture 는 결정적이고 prereq 행을 지우지 않는다

## 하지 않는 것
업스트림 소스 빌드, 버전 고정(설치된 버전은 status 에 표시만), Linux 지원, 새 Mac 실제 재현
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 workspace/tools.tsv 가 명령 54개 전부와 선행 도구를 공급자·패키지·빌드 방법과 함께 담고, links.tsv bin/* 와 명령 집합이 같음을 검사하는 테스트가 있다(B2)
- [ ] #2 tools status 가 행마다 OK/MISSING/WRONG-PROVIDER 와 bin/* 대조(누락·초과)를 보여 주고 어긋남이 있으면 1, 지금 머신에서 0 이다
- [ ] #3 tools install 이 prereq 확인 → brew → cask → uv tool → dev-toolchain sync → 저장소 빌드 → workspace link 순서로 빠진 것만 설치하고(B1), 선행 도구가 없으면 안내 후 중단하며(B3), --dry-run 은 부작용이 없다(B4)
- [ ] #4 tools capture 가 결정적이고 prereq 행을 보존하며(B5) 지금 머신에서 다시 돌려도 diff 0 이다
- [ ] #5 README 에 '새 Mac 에서 처음부터' 순서와 tools 사용법이 있다
- [ ] #6 pytest 가 가짜 brew/uv/git/dev-toolchain 실행 파일로 위를 샌드박스에서 검증하고 테스트에 <ID>#n·<ID>#Bk 표식이 있다
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 pytest 전체 통과·ruff·/usr/bin/python3 실행·shellspec 회귀 없음·source-header lint 0 출력을 Notes 에 첨부
- [ ] #2 실제 머신 tools status 0 과 tools install --dry-run 이 할 일 없음을 출력한 결과를 첨부
- [ ] #3 새·변경 파일에 헤더·줄 끝 표식·노트가 있다
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### Subjective
유저(2026-11-17): 이 프로젝트를 쓰려면 설치하는 실행 파일을 모두 리스트업하고 설치 방법까지 스크립트로. 업스트림 소스 빌드는 아니고 지금 방향(진입점 ~/githubs/bin, 실체는 Homebrew 등)이 맞다. 범위는 명령 54개 + 선행 도구.

### Objective
- bin 54개 실체 분류: brew 31, cask 1, oss 6, uv-tool 1, system 1, repo 15(빌드 2).
- oss_sync.sh populate_ref_bins 는 Homebrew 를 설치하지 않고 이미 있을 때만 링크한다.
- dev-toolchain install(sh)이 Xcode CLT·Homebrew(체크섬 고정)·asdf·런타임 8종을 맡는다.
- scripts/workspace.py(TASK-176)에 Ctx·plan()·dry-run·capture·status 골격이 있다.

### Assessment
tools.tsv 를 SSOT 로 두고 workspace.py 에 tools 서브커맨드를 더한다. 설치는 빠진 것만, 한 공급자씩 묶어 실행한다. sudo·GUI 가 필요한 선행 도구는 dev-toolchain install 에 맡기고 안내만 한다. capture 는 realpath 로 공급자를 분류한다.

### Plan
1. 테스트 먼저: 가짜 brew/uv/git/dev-toolchain 를 PATH 에 둔 샌드박스로 status·install·capture·B1~B5, 그리고 커밋된 tools.tsv↔links.tsv 집합 일치.
2. workspace.py 에 tools status/install/capture 구현, 헤더·표식·노트.
3. 실제 머신 capture 로 tools.tsv 생성 + prereq 행 손으로 추가 → status 0, install --dry-run 할 일 없음.
4. README '새 Mac 에서 처음부터' 절, 검증, 커밋, PR.
<!-- SECTION:PLAN:END -->
