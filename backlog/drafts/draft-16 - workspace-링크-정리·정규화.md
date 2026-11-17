---
id: DRAFT-16
title: 'workspace: 링크 정리·정규화'
status: Draft
assignee: []
created_date: '2026-11-17T13:00:00Z'
labels:
  - workspace
  - symlink
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
유저 지시(2026-11-17): DRAFT-15(workspace 목록·복원) 후속. 계획 맥락: ~/.claude/plans/happy-honking-bird.md — DRAFT-15 는 링크를 있는 그대로 목록에 담고 status 로 드러내기만 한다. 이 카드는 실제로 정리한다.

## 확인된 불일치(2026-11-17)
- ~/.local/bin 54개 중 일부는 ~/githubs/bin/<cmd> 를, 일부는 ~/githubs/opensource/in-use/<x>/current/bin/<x> 를 직접 가리킨다 → 한 경로(~/githubs/bin 경유)로 통일할지 결정
- PATH 1번째 항목 ~/githubs/omnivim/bin 은 존재하지 않는다(omnivim 은 dev-tools/ 아래)
- ~/.oh-my-zsh/custom/plugins 2개가 current 가 아니라 버전 폴더를 직접 가리킨다
- 워크스페이스 별칭(~/githubs/ebpf-wire-to-code-tracer, freeride/dev-toolchain)을 유지할지

## 할 일(승격 시 AC 로)
정규화 규칙을 정해 links.tsv 에 반영하고 workspace link --force 로 적용, 셸 rc 의 PATH 정리, status 0 확인
<!-- SECTION:DESCRIPTION:END -->
