---
id: DRAFT-8
title: lt_remove_single_plugin() 추출 (02_remove_plugins.sh -> lib.sh)
status: Draft
assignee: []
created_date: '2026-09-20 21:41'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/uninstall/02_remove_plugins.sh의 플러그인별 prior-state 체크 + asdf plugin remove 로직을 lib.sh의 lt_remove_single_plugin(plugin)으로 추출, 기존 phase 스크립트(전체 순회)와 신규 ltl uninstall(단일 플러그인) 양쪽이 공유. m-23/decision-23 소속.
<!-- SECTION:DESCRIPTION:END -->
