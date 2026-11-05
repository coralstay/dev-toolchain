---
id: TASK-157
title: 'docs/ 리서치 문서 작성: POSIX sh vs bash 실제 사례 조사 기록'
status: Done
assignee: []
created_date: '2026-09-10 01:13'
updated_date: '2026-09-10 01:23'
labels: []
milestone: m-20
dependencies:
  - TASK-156
references:
  - decision-19
type: task
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
사용자가 '나도 조사가 필요할것같다'고 명시적으로 말했으므로, decision-19의 요약이 아니라 사용자 본인이 나중에 더 파고들 수 있는 원자료 형태의 리서치 문서를 docs/ 아래 새로 만든다(기존 docs/download-integrity-techniques.md와 같은 리서치 문서 스타일 — 조사 결과 나열 + 출처 링크 + 이 저장소 적용 여부 평가).

포함해야 할 내용:
- rustup-init.sh 실제 인용문(shebang #!/bin/sh, 'It runs on Unix shells like {a,ba,da,k,z}sh. It uses the common local extension' 등 이번 대화에서 WebFetch로 직접 확인한 원문)과 출처(rustup-init.sh 원본 URL, Rust Forge 문서 URL)
- nvm과의 대비 — curl | bash로 못박아서 셸 불확실성 문제 자체를 회피하는 반대 진영 사례(nvm 저장소 URL)
- Homebrew 공식 설치 스크립트도 같은 이유로 POSIX 계열이라는 점(이 저장소가 이미 체크섬 고정해서 신뢰하는 대상이라는 연결고리)
- oneuptime.com의 판단 기준 인용(오픈소스/통제 불가 환경이면 POSIX, 본인이 통제하는 환경이면 bash 써도 됨)
- set -eu 실증 테스트 스크립트와 실제 실행 결과 원문 그대로(if [[ ... ]]가 dash에서 command not found 나도 -e 예외 대상이라 조용히 거짓 처리되고 스크립트가 끝까지 도는 것 vs [[ ... ]] || exit 1 가드절은 정상 실패하는 것 — 이번 대화에서 dash -c로 직접 실행해서 나온 output 그대로 인용)
- SonarCloud shelldre:S7688 / shell:S6506 규칙의 실제 메타데이터(api/rules/show로 조회한 severity, impact, tags 등)
- 참고 링크 전부: rustup Forge, rustup-init.sh raw URL, nvm GitHub, oneuptime.com POSIX 가이드, checkbashisms 관련 자료

decision-19(TASK-156)가 먼저 존재해야 그 안의 공식 결론을 이 문서에서 인용/링크할 수 있으므로 TASK-156 이후에 작성.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/posix-sh-vs-bash-research.md 작성 완료 - rustup-init.sh 실제 인용문(WebFetch로 원문 확인), nvm과의 대비, oneuptime.com 판단 기준, SonarCloud S7688/S6506 룰 메타데이터(라이브 API로 재검증), set -eu/dash 실증 테스트 결과(if-조건문 vs 가드절 형태의 차이) 전부 원자료 그대로 수록. 사용자가 지적한 SonarCloud 룰 createdAt 날짜(2025-10~11월)는 라이브 API 재조회로 두 차례 재확인 완료 - RSPEC 카탈로그 등록일이라 이 프로젝트의 SonarCloud 도입일(2026-09)보다 이른 게 정상.
<!-- SECTION:FINAL_SUMMARY:END -->
