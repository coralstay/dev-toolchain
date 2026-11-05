---
id: DRAFT-3
title: 핀 갱신 정책 결정 - 코드 변경 없는 커밋은 갱신 대상 제외
status: Draft
assignee: []
created_date: '2026-09-20 11:33'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-167/170/174에서 반복 확인된 패턴: 태스크 Done 전환 커밋(backlog 메타데이터만 변경, 코드 변경 없음)이 매번 핀을 다시 스테일하게 만들어 자기 꼬리를 무는 구조. decision으로 '코드/스크립트 실질 변경이 있는 병합에만 핀을 갱신하고, backlog 메타데이터 전용 커밋은 갱신 대상에서 제외한다'는 정책을 명문화.
<!-- SECTION:DESCRIPTION:END -->
