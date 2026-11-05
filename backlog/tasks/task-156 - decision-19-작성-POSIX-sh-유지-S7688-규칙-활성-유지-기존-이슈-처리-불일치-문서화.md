---
id: TASK-156
title: 'decision-19 작성: POSIX sh 유지 + S7688 규칙 활성 유지 + 기존 이슈 처리 불일치 문서화'
status: Done
assignee: []
created_date: '2026-09-10 01:13'
updated_date: '2026-09-10 01:15'
labels: []
milestone: m-20
dependencies: []
references:
  - decision-13
  - decision-14
  - decision-18
type: task
ordinal: 232000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
backlog decision create로 decision-19 스캐폴딩 생성 후(CLI가 title/status만 지원하므로 본문은 파일 직접 편집 — decision-14/18도 이 방식으로 작성됨, backlog/ 파일 직접 편집 금지 규칙은 task/milestone에 적용되는 것이고 decision은 CLI 자체가 본문 편집을 지원 안 해서 예외), 다음 3가지를 Context/Decision/Consequences로 기록:
1) POSIX sh 유지 근거 — curl|sh의 PATH 의존성(배포 시 sh 정체 통제 불가), 애플의 bash 3.2 동결/GNU 도구 제거 전례, set -eu가 dash의 [[ 실패를 못 막는다는 실증 결과(if-조건문은 POSIX -e 예외 대상이라 조용히 거짓 처리 후 계속 실행 vs 가드절 || 형태는 정상 실패 — 둘 다 dash로 직접 검증함), rustup-init.sh 실제 인용(local만 예외 인정하는 정책이 TASK-71과 거의 동일), Homebrew 설치 스크립트도 같은 이유로 POSIX 계열.
2) S7688 규칙을 Quality Profile에서 비활성화하지 않고 활성 유지하기로 한 결정 — 오탐이어도 향후 실수로 [[가 들어오는 걸 잡는 회귀 탐지 카나리아 역할(m-14 check-hardcoded-paths.sh 린트와 같은 성격). 사용자가 처음엔 Won't Fix+규칙비활성화를 검토하다가 '아니 S7688은 오탐이라도 탐지하는걸로하자'로 최종 결정.
3) 기존 14건(S7688) + 이미 고친 1건(S6506, 이슈 #7)의 최종 처리 상태 기록 — 사용자가 SonarCloud는 전혀 안 건드리고 GitHub Issue만 수동으로 close함('아니 아무것도 안건들고 그냥 깃헙이슈에서 닫아놓음'). 그 결과 SonarCloud API로 재확인한 실측치: shelldre:S7688 14건이 resolved=false로 여전히 열려 있고, 대응 GitHub Issue 14개+#7은 전부 CLOSED. 이 불일치(SonarCloud=열림/GitHub=닫힘)는 의도적 — decision-18의 자동 동기화 파이프라인(TASK-155)이 이후에도 이 14건을 재발행하거나 잘못 건드리지 않는 이유(발행 step은 --state all로 기존 존재 확인, close step은 --state open만 순회)까지 명시해서, 나중에 이 불일치를 보고 헷갈려서 '고치려는' 사람이 없게 한다.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
decision-19 작성 완료 - POSIX sh 유지, SonarCloud shelldre:S7688 룰은 Quality Profile 비활성화 안 하고 활성 유지(회귀 탐지 카나리아), 기존 14건(S7688)+1건(S6506, 이슈#7)은 SonarCloud 쪽 안 건드리고 GitHub Issue만 사용자가 수동 close한 의도적 불일치 상태를 실측치(2026-09-10 기준 SonarCloud API: 14건 resolved=false, GitHub: 전부 CLOSED)와 함께 기록. decision-13/14/18, TASK-71 상호 참조.
<!-- SECTION:FINAL_SUMMARY:END -->
