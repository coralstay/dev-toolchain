---
id: TASK-177
title: 'workspace: 링크 정리·정규화'
status: To Do
assignee: []
created_date: '2026-11-17T13:00:00Z'
updated_date: '2026-11-17T13:54:00Z'
labels:
  - workspace
  - symlink
dependencies:
  - TASK-176
references:
  - TASK-176
documentation:
  - /Users/flynn_macpro/.claude/plans/happy-honking-bird.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
TASK-176 이 ~/githubs 의 링크 114개를 그대로 workspace/links.tsv 에 담았는데 홈 쪽 규칙이 제각각이다(2026-11-17 확인).
- ~/.local/bin 54개: 12개는 ~/githubs/bin/<cmd> 경유, 39개는 opensource/in-use/<x>/current/bin/<x> 직접, 3개는 저장소 파일 직접(dev-toolchain, dev-toolchain-uninstall, krayctl)
- 집합 불일치: krayctl 은 ~/.local/bin 에만, source-header 는 ~/githubs/bin 에만
- oh-my-zsh 플러그인 2개가 current 가 아니라 버전 폴더(v0.7.1, 0.8.0)를 가리킴
- ~/.zshrc 41·42·57행에 ~/.local/bin PATH 중복(57행이 ~/githubs/bin:~/.local/bin 을 맨 앞에 다시 넣음)
- 이 Claude 세션 PATH 맨 앞의 ~/githubs/omnivim/bin 은 없는 경로이고 rc·설정 어디에도 없다(부모 프로세스의 옛 환경으로 보임)
- 이 세션 PATH 에는 ~/githubs/bin 이 없고 ~/.local/bin 만 있다 → 훅·에이전트는 ~/.local/bin 에 의존
계획: ~/.claude/plans/happy-honking-bird.md (승인됨)

## 유저 결정(2026-11-17)
~/githubs/bin 이 유일한 허브(SSOT), ~/.local/bin 은 전부 ~/githubs/bin/<cmd> 경유. oh-my-zsh 플러그인은 current. 워크스페이스 별칭 2개 유지. 셸 rc PATH 정리 포함.

## 선행 조건
dev-toolchain PR #3(TASK-176) 병합 — workspace/links.tsv 와 scripts/workspace.py 가 그 브랜치에만 있다.

## 비즈니스 규칙
- B1 (AC #2) 정규화 적용은 심볼릭 링크만 바꾼다. 실제 파일·폴더는 건드리지 않는다(TASK-176 B1 재사용)
- B2 (AC #1) ~/.local/bin 의 githubs 링크는 반드시 ~/githubs/bin/<같은 이름> 을 가리킨다
- B3 (AC #3) rc 파일은 고치기 전에 백업하고 최종 PATH 순서를 바꾸지 않는다

## 하지 않는 것
별칭 링크 변경, opensource/ 내부 구조, .zprofile, 저장소 커밋 고정(DRAFT-17)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 links.tsv 가 R1(home .local/bin/<cmd> 의 대상은 ~/githubs/bin/<cmd>)·R2(bin/* 와 .local/bin/* 이름 집합 같음, krayctl·source-header 보충)·R3(opensource 를 가리키는 링크는 current 경유, oh-my-zsh 2개 포함)을 지키고 그 규칙을 검사하는 테스트가 있다(B2)
- [ ] #2 실제 머신에 link --force 로 적용한 뒤 workspace status 가 0 이고 ~/.local/bin 의 모든 명령이 실제 파일로 풀린다. 적용 전 link --dry-run --force 출력에 WRONG-TARGET·MISSING 만 있다(B1)
- [ ] #3 ~/.zshrc 41·42행 중복 PATH 줄을 지웠다. 백업(~/.zshrc.bak-2026-11-17)이 있고 새 대화형 zsh 의 PATH 에 ~/.local/bin 이 한 번만 있으며 다른 항목 순서는 이전과 같다(B3)
- [ ] #4 ~/githubs/omnivim/bin 의 출처 조사 결과(rc·설정 검색, 부모 프로세스 환경, 새 터미널 재확인)가 Notes 에 있다
- [ ] #5 적용 후 capture 를 다시 돌리면 목록 diff 가 0 이다(목록 = 머신)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 pytest 전체 통과(새 규칙 테스트는 목록 수정 전 실패 확인) 출력을 Notes 에 첨부
- [ ] #2 적용 전후 status, link --dry-run --force 출력, 새 zsh PATH 전후 비교를 Notes 에 첨부
- [ ] #3 적용 전 링크 상태(ls -l)를 백업해 되돌릴 수 있다
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### Subjective
유저(2026-11-17)가 DRAFT-16(링크 정리·정규화)을 진행하자고 했고, ~/githubs/bin 단일 허브 + ~/.local/bin 경유, oh-my-zsh current, 별칭 유지, rc PATH 정리 포함으로 결정했다.

### Objective
- links.tsv(TASK-176): home .local/bin 54 = bin 경유 12 + opensource 직접 39 + 저장소 직접 3. krayctl·source-header 집합 불일치. oh-my-zsh 2개 버전 폴더 직접.
- ~/.zshrc 41·42·57행 PATH 중복, .zprofile 13행은 로그인 셸용.
- ~/githubs/omnivim/bin 은 rc·~/.claude/settings 어디에도 없다.
- workspace.py link --force 는 WRONG-TARGET 심볼릭 링크만 바꾸고 실제 파일은 건드리지 않는다(TASK-176 B1·B2).

### Assessment
목록 데이터만 바꾸고 workspace.py link --force 로 적용한다(코드 변경 불필요). 규칙은 커밋된 목록 파일을 읽는 pytest 로 고정해 이후 capture 로 되돌아가지 않게 한다. rc 는 백업 후 중복 2줄만 지운다.

### Plan
1. PR #3 병합 후 main 에서 task/<ID> 브랜치, In Progress.
2. 테스트(R1~R3) 먼저 — 지금 목록에서 실패 확인.
3. links.tsv 수정(머리 주석에 규칙) → 테스트 통과.
4. 링크 상태 백업 → link --dry-run --force 출력을 유저에게 보이고 확인 → link --force → status 0, ~/.local/bin 전 명령 해석 확인.
5. ~/.zshrc 백업 → 41·42행 삭제 → 새 zsh PATH 비교.
6. omnivim/bin 출처 기록, capture 재실행 diff 0, 커밋·PR.
<!-- SECTION:PLAN:END -->
