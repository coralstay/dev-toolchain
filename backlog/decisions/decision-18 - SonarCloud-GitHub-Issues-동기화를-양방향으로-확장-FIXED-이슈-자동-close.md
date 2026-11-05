---
id: decision-18
title: SonarCloud-GitHub Issues 동기화를 양방향으로 확장 (FIXED 이슈 자동 close)
date: '2026-09-06 01:31'
status: accepted
---
## Context

decision-14(2026-09-04)는 SonarCloud → GitHub Issues 발행을 한 방향으로만
정의했다 — "없는 것을 새로 발행"만 다루고, 이미 발행한 뒤 SonarCloud 쪽에서
해결된 이슈를 어떻게 반영할지는 범위 밖이었다.

TASK-153/154(m-18)에서 shell:S6506을 실제로 고치자(curl에
--proto/--proto-redir/--tlsv1.2 하드닝) SonarCloud API가 해당 이슈를
status=CLOSED, resolution=FIXED로 자동 전환했다. 하지만 이미 발행된
GitHub Issue #7은 계속 OPEN으로 남았다 — sonarcloud-issues-to-github.yml이
"resolved=false인 걸 못 찾으면 발행"만 하고, 이미 발행된 이슈가 나중에
resolved=true가 되는 경우는 아예 다루지 않기 때문. 사용자가 이 문제를
직접 확인한 뒤 "워크플로에 자동-닫기 로직 추가"를 선택했다.

## Decision

decision-14의 "SonarCloud → GitHub, 한 방향" 제약을 완화한다 — 단,
**같은 좁은 파이프라인 안에서** SonarCloud 쪽 상태(resolved/unresolved)를
GitHub Issue의 open/closed 상태에 반영하는 것으로 한정한다. decision-9(백로그
태스크 관리는 backlog.md만 씀)의 예외 범위나, "backlog ↔ GitHub Issues
양방향 전환은 안 만든다"는 decision-14의 제약은 그대로 유지된다 — 이번
확장은 SonarCloud 발견물 자체의 생명주기(발견→발행→해결→종료)를 GitHub
Issue 쪽에 정확히 반영하는 것뿐이다.

구체적으로 `sonarcloud-issues-to-github.yml`에 두 번째 단계를 추가한다:
`label:sonarcloud`로 열려 있는 GitHub Issue를 순회 → 본문에서 SonarCloud
이슈 key 추출 → `api/issues/search?issues=<key>`로 현재 상태 재조회 →
CLOSED/RESOLVED면 해결 근거를 코멘트로 남기고 GitHub Issue를 close.

## Consequences

- 기존 "누락된 것 발행" 단계는 그대로 유지 — 이번 확장은 추가되는 두 번째
  단계일 뿐, 첫 번째 단계의 동작을 바꾸지 않는다.
- 트리거는 decision-14가 이미 정한 매일 스케줄(cron)을 그대로 쓴다 —
  close 방향도 "지금 시점 상태를 통째로 동기화"라 워크플로 실행 시점
  경합에서 자유롭고, workflow_run 즉시 트리거를 안 쓰는 이유(인덱스 갱신
  지연, 알림 폭탄)가 close 방향에도 동일하게 적용되므로 그대로 유지한다.
- GitHub Issue 본문에 SonarCloud 이슈 key가 이미 기록되어 있다는 전제가
  깨지면(사람이 본문을 수정하는 등) 매칭이 실패할 수 있다 — 이 경우 안전한
  기본값은 "닫지 않고 넘어간다"(silent skip)이지, 추측으로 닫는 게 아니다.
- GitHub Issue → SonarCloud 방향(예: 사람이 GitHub에서 이슈를 close하면
  SonarCloud 쪽도 resolve 처리)은 여전히 범위 밖이다 — SonarCloud가 "진실의
  원천"이고 GitHub Issue는 그 상태를 비추는 읽기 전용 알림일 뿐이라는
  비대칭을 유지한다.
