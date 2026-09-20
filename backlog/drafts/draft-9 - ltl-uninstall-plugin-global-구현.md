---
id: DRAFT-9
title: 'ltl uninstall <plugin> [-global] 구현'
status: Draft
assignee: []
created_date: '2026-09-20 21:41'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
기본은 현재 디렉토리에 로컬로 설정된 부분만 제거, -global 플래그로 글로벌 설정 제거. 런타임 버전 제거는 01_uninstall_runtimes.sh의 uninstall_from_config_file() 패턴을 합성 한 줄 파일로 재사용, 플러그인 자체 제거는 앞 태스크에서 추출한 lt_remove_single_plugin() 사용. acquire_lock/release_lock 필수. m-23/decision-23 소속, lt_remove_single_plugin 추출 태스크에 의존.
<!-- SECTION:DESCRIPTION:END -->
