---
id: DRAFT-15
title: 'workspace: 저장소 배치·심볼릭 링크를 목록 파일(SSOT)로 관리하고 복원한다'
status: Draft
assignee: []
created_date: '2026-11-17T12:55:00Z'
labels:
  - workspace
  - symlink
  - ssot
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
유저 결정(2026-11-17): ~/githubs 의 저장소 배치(경로→원격)와 심볼릭 링크 약 113개(~/githubs/bin 53, 워크스페이스 별칭 3, 홈 57)를 목록 파일로 dev-toolchain 에 담고(방식 A), 복원 명령이 실체를 만든다. 오픈소스는 이미 .tool-versions(@oss)+oss_sync 가 관리하므로 범위 밖. 테스트도 작성한다.
계획: ~/.claude/plans/happy-honking-bird.md (승인됨)

## 범위
- workspace/repos.tsv (경로<TAB>원격 URL), workspace/links.tsv (범위 githubs|home<TAB>링크<TAB>대상, $HOME 은 ~ 로 표기)
- scripts/workspace.sh: status(기본) / link [--force] / bootstrap / capture, DRY_RUN 지원(lib.sh run), git clone 은 lt_run_with_timeout
- install.sh 위임 목록에 workspace 추가, help·README·check-hardcoded-paths 스캔 목록 갱신
- spec/workspace_spec.sh: 가짜 HOME·가짜 루트·로컬 bare 저장소로 네트워크 없이 검증

## 비즈니스 규칙
- B1 (AC #3) link 는 실제 파일·폴더를 절대 덮어쓰지 않는다(NOT-A-LINK 는 보고만)
- B2 (AC #3) 대상이 다른 링크는 --force 없이는 바꾸지 않는다
- B3 (AC #4) bootstrap 은 이미 있는 저장소 폴더를 건드리지 않는다(pull·reset·remote 변경 없음)
- B4 (AC #1) 목록에 홈 절대 경로(/Users/<이름>)가 들어가지 않는다
- B5 (AC #5) capture 는 결정적이다 — 같은 상태에서 두 번 돌리면 diff 0

## AC(승격 시 등록)
1. repos.tsv·links.tsv 가 지금 머신을 그대로 담는다(저장소 21, 링크 약 113). 형식 설명이 파일 머리 주석에 있다
2. status 가 상태 분류(OK/MISSING/WRONG-REMOTE, OK/MISSING/WRONG-TARGET/NOT-A-LINK/DANGLING, UNTRACKED)와 종료 코드(어긋남 있으면 1)를 지키고 지금 머신에서 0 이다
3. link 가 없는 링크만 만들고 멱등이며 DRY_RUN 이면 부작용이 없다(B1·B2)
4. bootstrap 이 없는 저장소만 clone 한 뒤 링크를 만든다(B3)
5. capture 가 결정적이고 지금 머신에서 다시 돌려도 목록 diff 가 0 이다(B4·B5)
6. dev-toolchain workspace … 로 호출되고 help·README(오픈소스 절 옆 새 절 + CLI 사용법 + 구조 표)가 갱신된다
7. spec/workspace_spec.sh 가 위를 샌드박스에서 검증하고 테스트 이름에 TASK-N#n·TASK-N#Bk 표식이 있다

## DoD(승격 시 등록)
shellcheck -s sh → dash -n → shellspec + shellspec --shell dash 전체 통과(기존 포함), check-hardcoded-paths 통과, source-header lint --strict 0, 새 스크립트에 헤더·표식·노트, 실제 머신 status 0 출력 첨부

## 하지 않는 것
링크 정리·정규화(~/.local/bin 의 불일치, PATH 의 없는 ~/githubs/omnivim/bin 등은 status 로 드러내기만), 저장소 커밋 고정, CI 에 shellspec 추가, 루트 README 트리 수정

## 알고 가는 것
공개 저장소(dev-toolchain)에 비공개 저장소 9개의 이름·URL 이 목록으로 공개된다
<!-- SECTION:DESCRIPTION:END -->
