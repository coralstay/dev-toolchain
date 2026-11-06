---
id: TASK-175
title: 'source-header 적용: dev-tools/dev-toolchain'
status: Done
assignee: []
created_date: '2026-10-31T11:08:00Z'
updated_date: '2026-11-06T13:32:00Z'
labels:
  - source-header
  - rollout
dependencies: []
documentation:
  - ~/.claude/plans/giggly-kindling-snowglobe.md
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 배경
source-header 6단계(dev-tools/source-header TASK-3)의 저장소별 적용 카드. 유저 결정(2026-10-31):
~/githubs 아래 내가 짠 코드는 AGPL-3.0-only, 외부 코드·책 예제는 제외, description은 서브에이전트 초안,
README·CHANGELOG는 제외하고 설계 문서는 포함, 기존 저장소의 .githooks에는 source-header 플러그인만 설치.

## 대상 저장소
`~/githubs/dev-tools/dev-toolchain` (순서 그룹: 1-now)

## .source-header.json (초안)
```json
{"include": ["**"], "exclude": ["**/README.md", "**/CHANGELOG.md", "backlog/**", ".opensource/**", "contents/**", "content_data/**"]}
```

## 라이선스 조치
MIT(저작권자 옛 이름) → AGPL-3.0-only로 전환: LICENSE 교체, README 라이선스 표기 수정

## 메모
옛 계정 작성자는 본인으로 확인됨(2026-10-31).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .mailmap(전역 ~/.mailmap과 같은 매핑)을 저장소에 커밋해 다른 클론·CI에서도 authors가 coralstay로 나온다
- [x] #2 라이선스 조치를 마친다: MIT(저작권자 옛 이름) → AGPL-3.0-only로 전환: LICENSE 교체, README 라이선스 표기 수정
- [x] #3 .source-header.json을 확정하고(제외 대상 재확인) source-header init으로 헤더를 넣고, 서브에이전트가 description 초안을 쓴다. source-header lint 오류 0
- [x] #4 규격(source-header README '본문 노트 표식', TASK-23)에 따라 중요한 지점(설치 진입점·버전 고정·다운로드 검증·파괴적 명령 가드 등)의 줄 끝에 '---- N' 표식을 달고 파일 맨 아래 노트 구역에 설명을 쓴다. 번호는 파일마다 1부터 연속, 표식:노트 1:1. 주석·헤더 외 코드 줄은 바뀌지 않는다. 기존 주석의 변환(B4)은 하지 않고 후속 카드로 분리한다(유저 결정 2026-11-06)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 source-header lint . 오류 0 (출력을 Implementation Notes에 첨부)
- [x] #2 저장소의 기존 테스트·빌드가 헤더 추가 후에도 통과
- [x] #3 유저가 description diff를 검토
- [x] #4 표식 번호가 파일마다 1부터 연속이고 표식:노트가 1:1임을 확인한 출력과, git diff에 주석·헤더 외 변경이 없음을 확인한 결과를 Implementation Notes에 첨부했다
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
### Subjective
유저가 ~/githubs 기존 파일 전체에 소스 헤더 적용을 결정했다(2026-10-31). 이 카드는 `dev-tools/dev-toolchain` 담당.

### Objective
TASK-3 조사 결과는 Description 참고. source-header(init/lint/fix/hook)와 git-commit-tool .githooks(GF-148)가 준비됐고, --plugins 옵션은 git-commit-tool 별도 draft에서 추가한다.

### Assessment
헤더는 git에서 유도 가능한 값은 init에 맡기고 description만 서브에이전트가 쓴다. 생성물은 생성기에서 헤더를 넣는다. 커밋은 단계별로 나눠 diff 검토가 쉽게 한다.

### Plan
1. .mailmap 커밋
2. 라이선스 조치 커밋
3. .source-header.json → init → description 초안(서브에이전트) → lint 0 → 커밋(파일이 많으면 디렉터리 단위로 나눔)
4. (해당 시) 생성기 수정
5. .githooks 설치(--plugins source-header) → 실측
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC #2 (2026-10-31): LICENSE를 AGPL-3.0 전문으로 교체, README 배지·License 절 수정(이전 사본은 MIT 유지 안내). docs/shell-style-guide.md는 Google Shell Style Guide 기반 2차 저작물이라 CC BY 3.0 표기를 README에 추가. 작성자 coralstay(old-me@example.com)는 유저 본인으로 확인됨.

2026-11-06 범위 추가(유저 결정): 헤더 적용 뒤 같은 카드에서 본문 노트 표식(AC #5)까지 한다. 계획 6단계 추가 — 표식 커밋: 디렉터리 단위 서브에이전트가 파일을 읽고 중요한 지점에만 줄 끝 '---- N'과 하단 노트를 달고 기존 주석은 B4로 변환한다(헤더 커밋과 분리). 대상 sh 40·yml 1. 셸 스크립트라 접두사와 노트 구역 모두 '#'.

2026-11-06 유저 결정: AC '.githooks 설치(--plugins source-header)'는 후속 draft(source-header DRAFT-7, GF-149 이후)로 분리했다. 이 카드의 AC 번호가 이에 맞춰 당겨졌다(표식 AC 번호 -1).

2026-11-06 AC #4 문구 조정(유저 결정): 기존 주석을 새 포맷으로 옮기는 B4 변환은 이번에 하지 않고 후속 카드로 뺀다. 이유: 파일 42개·전체 9,174줄 중 주석 줄 3,529줄이고 scripts/lib.sh(1,566줄)와 scripts/install/00_select.sh(507줄)에 몰려 있어 별도 작업이 맞다. 기존 주석은 하나도 지우지 않았다.

2026-11-06 구현·검증 기록 (브랜치 task/TASK-175, 커밋 7745505 ffc1350 cdc4487)
- AC #1: .mailmap은 전역 ~/.mailmap과 같다(주석뿐, 매핑 없음).
- AC #2: LICENSE는 AGPL-3.0, README 표기 AGPL-3.0-only(카드에 완료로 이미 체크됨).
- AC #3: .source-header.json은 카드 초안에 CLAUDE.md, .claude/**, docs/shell-style-guide.md(CC BY 3.0 파생이라 AGPL 헤더가 맞지 않음)를 제외 추가. 47개 파일(sh 40, yml 1, docs md 6)에 헤더와 한 줄 description. lint --strict . exit 0(직접 실행).
- AC #4: 셸 40개와 yml 1개에 표식과 하단 노트. 셸 표식 170개의 번호가 연속이고 1:1(직접 확인). 서브에이전트 보고는 yml 8개를 더해 178개.
- DoD #2/#4 증거(직접 실행): bash -n이 셸 40개 모두 통과. shfmt -mn으로 주석을 걷어낸 구조가 main과 모두 같다(차이 0). shellspec 228 examples, 0 failures. 서브에이전트가 처음 줄 이음(\) 줄과 따옴표 여러 줄 문자열에 단 표식 5개를 shfmt 검사로 발견해 옮기거나 지웠고, 최종 결과에는 차이가 없다.
- DoD #3: 유저가 description 286개(8개 저장소) 중 무작위 20개를 샘플 검토하고 '그래도 모두 남겨'라고 결정했다.
- AC '.githooks 설치'는 유저 결정으로 후속 draft(source-header DRAFT-7, GF-149 이후)로 분리했다.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
dev-toolchain 셸 스크립트 40개와 e2e-verify.yml에 source-header 헤더(AGPL-3.0-only, 한 줄 description 47개)와 본문 노트 표식(셸 170, yml 8)을 적용했다. 설계 문서 md 6개에도 헤더를 넣었고 CC BY 파생인 shell-style-guide.md는 제외했다. 검증: lint --strict 0 오류, bash -n 40개 통과, shfmt -mn 구조 차이 0, shellspec 228 examples 0 failures. 기존 주석 변환(B4)은 유저 결정으로 후속 카드로 분리했고 기존 주석은 지우지 않았다. .githooks 설치도 후속 draft로 분리. 커밋 7745505 ffc1350 cdc4487 (브랜치 task/TASK-175).
<!-- SECTION:FINAL_SUMMARY:END -->
