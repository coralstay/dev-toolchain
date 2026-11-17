---
id: DRAFT-19
title: dev-toolchain 전체를 py 로 옮긴다(install.sh 진입점만 sh 유지)
status: Draft
assignee: []
created_date: '2026-11-17T13:00:00Z'
labels:
  - python
  - migration
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
유저 지시(2026-11-17): dev-toolchain 전체를 py 로 바꾼다. 새 명령 workspace 는 DRAFT-15 에서 이미 py 로 쓴다.

## 범위(조사 필요)
- scripts/oss_sync.sh(약 400줄), scripts/lib.sh(약 1,600줄), scripts/install/00~07·main.sh, scripts/uninstall/01~06·main.sh, scripts/lint/check-hardcoded-paths.sh, uninstall.sh
- 테스트: spec/*.sh(shellspec 19개, 228 예제) → pytest 로 옮기거나 블랙박스 회귀로 유지
- .github/workflows/e2e-verify.yml 의 lint 잡

## 제약
- install.sh(curl | bash 원격 설치 진입점)는 python 이 없을 수 있는 새 Mac 에서 먼저 돌아야 하므로 sh 로 남긴다. asdf·python 설치 전 단계(00~01 등)도 같은 이유로 sh 유지 여부를 판단해야 한다
- 시스템 python3(3.9)·표준 라이브러리만으로 동작해야 하는 구간과 asdf python 3.12 이후 구간을 나눈다
- 기존 동작(DRY_RUN, 멱등, 타임아웃, rc 편집)을 회귀 없이 유지

## 진행 방식(승격 전에 정할 것)
크기가 커서 단계별 카드로 쪼갠다(예: oss_sync → lib → uninstall → install). 각 단계는 기존 shellspec 을 블랙박스 회귀 테스트로 먼저 고정한 뒤 옮긴다
<!-- SECTION:DESCRIPTION:END -->
