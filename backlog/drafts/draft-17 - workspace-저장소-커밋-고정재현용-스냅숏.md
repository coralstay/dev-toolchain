---
id: DRAFT-17
title: 'workspace: 저장소 커밋 고정(재현용 스냅숏)'
status: Draft
assignee: []
created_date: '2026-11-17T13:00:00Z'
labels:
  - workspace
  - reproducibility
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
유저 지시(2026-11-17): DRAFT-15(workspace 목록·복원) 후속. 계획 맥락: ~/.claude/plans/happy-honking-bird.md — DRAFT-15 의 repos.tsv 는 경로·원격만 담아 bootstrap 이 최신 main 을 받는다. 특정 시점의 워크스페이스 전체를 재현하려면 저장소별 커밋을 고정해야 한다.

## 할 일(승격 시 AC 로)
- repos.tsv 에 커밋(선택) 열 추가, capture --pin 으로 현재 HEAD 기록
- bootstrap 이 고정 커밋이 있으면 그 커밋으로 checkout(이미 있는 저장소는 건드리지 않는 B3 유지)
- status 가 고정 커밋과 HEAD 차이를 보여 준다
<!-- SECTION:DESCRIPTION:END -->
