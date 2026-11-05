---
id: TASK-155
title: sonarcloud-issues-to-github.yml에 FIXED 이슈 자동-close step 추가
status: Done
assignee: []
created_date: '2026-09-06 01:32'
updated_date: '2026-09-06 01:42'
labels: []
milestone: m-19
dependencies: []
references:
  - decision-18
  - .github/workflows/sonarcloud-issues-to-github.yml
type: task
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
decision-18 구현 스토리. 기존 '발행' step(label:sonarcloud로 이미 있음)은 그대로 두고, 그 다음에 'close 처리' step을 추가한다. 대상: 방금 확인된 GitHub Issue #7(S6506, SonarCloud에서는 이미 status=CLOSED/resolution=FIXED)이 실제 성공 기준 — 이 이슈가 자동으로 close되면 구현이 맞다는 증거다.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
decision-18 구현 완료. .github/workflows/sonarcloud-issues-to-github.yml의 sync job에 두 번째 step 'Close GitHub Issues whose SonarCloud issue is resolved' 추가 - 기존 발행 step(첫 번째 step)은 완전히 그대로 유지. 새 step: label:sonarcloud로 열린 이슈 순회 -> 본문에서 SonarCloud 이슈 key 추출(추출 실패 시 조용히 skip) -> api/issues/search?issues=<key> 재조회 -> status==CLOSED면 근거 코멘트 남기고 close, 개별 이슈 실패는 continue로 나머지 처리에 영향 없음. shellcheck -s sh + actionlint로 신규 코드에 새 경고 없음 확인(기존에도 있던 SC2016 info 경고 패턴과 동일 - house style). e2e 증거(TASK-155.3): 임시 브랜치 e2e-test-task-155로 push 후 gh workflow run --ref e2e-test-task-155 트리거, run id 34004500975 성공 완료, 실제 GitHub Issue #7이 OPEN -> CLOSED로 전환되고 SonarCloud status/resolution/key를 인용한 코멘트가 자동으로 달린 것을 gh issue view 7 / gh api .../comments로 직접 확인함. task/TASK-155 브랜치는 병합 준비 완료 상태로 남겨둠(coordinator가 병합).
<!-- SECTION:FINAL_SUMMARY:END -->
