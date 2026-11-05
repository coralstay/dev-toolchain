---
id: m-19
title: "SonarCloud-GitHub Issues 동기화 양방향화 (decision-18)"
---

## Description

decision-18 구현. sonarcloud-issues-to-github.yml(decision-14로 만든 워크플로)이 현재 '누락된 것 발행'만 하고 '해결된 것 close'는 안 함 — TASK-153/154에서 S6506을 실제로 고쳤더니 SonarCloud는 FIXED로 닫혔는데 GitHub Issue #7은 계속 OPEN으로 남는 걸 사용자가 직접 발견. 워크플로에 두 번째 step(열린 sonarcloud 라벨 이슈 순회 -> 본문에서 key 추출 -> SonarCloud 재조회 -> CLOSED/RESOLVED면 close)을 추가한다.
