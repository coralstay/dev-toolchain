---
id: DRAFT-4
title: 뒤로가기 + non-raw 터미널 폴백 조합 검증
status: Draft
assignee: []
created_date: '2026-09-20 11:33'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-165(뒤로가기)와 TASK-168(non-raw 터미널 표+Enter/스킵)이 각각은 expect로 검증됐지만 둘의 조합(non-raw 환경에서 언어를 뒤로 돌아가기)은 테스트된 적 없음. expect+가짜 stty로 실제 재현해서 확인, 버그 발견 시 그때 수정 범위 결정.
<!-- SECTION:DESCRIPTION:END -->
