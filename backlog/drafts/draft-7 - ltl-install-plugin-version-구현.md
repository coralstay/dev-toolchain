---
id: DRAFT-7
title: 'ltl install <plugin> [version] 구현'
status: Draft
assignee: []
created_date: '2026-09-20 21:41'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
합성 한 줄짜리 selection 파일을 만들어 phase 01~07(00_select.sh만 스킵)에 위임 - each_tool()이 이미 줄 개수 무관하게 동작해서 phase 스크립트 수정 불필요. acquire_lock/release_lock 필수. 버전 없이 호출 시 companion(pnpm 등)도 자동 제안(대화형 피커와 동일 동작, 사용자 확정). -global/--local[=DIR]/--yes 플래그. m-23/decision-23 소속.
<!-- SECTION:DESCRIPTION:END -->
