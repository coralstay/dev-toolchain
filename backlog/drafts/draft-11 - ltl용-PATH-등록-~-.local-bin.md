---
id: DRAFT-11
title: ltl용 PATH 등록 (~/.local/bin)
status: Draft
assignee: []
created_date: '2026-09-20 21:41'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lt_env_var_defs()에 export PATH="$HOME/.local/bin:$PATH" 항목 추가, 기존 detect_rc_file()/append_env_var() 그대로 재사용(새 셸 감지 로직 없음). m-23/decision-23 소속.
<!-- SECTION:DESCRIPTION:END -->
