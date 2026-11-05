---
id: TASK-153
title: 실행 curl 호출에 HTTPS 강제 플래그 적용 (S6506 실질 수정)
status: Done
assignee: []
created_date: '2026-09-06 01:01'
updated_date: '2026-09-06 01:13'
labels: []
milestone: m-18
dependencies: []
type: task
ordinal: 226000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/install/01_bootstrap_asdf.sh:81의 fetch_verified_homebrew_installer() 안 curl 호출(-fsSL --max-time "$LT_DOWNLOAD_TIMEOUT" -o "$dest" "$HOMEBREW_INSTALL_URL")에 --proto '=https' --proto-redir '=https' --tlsv1.2 세 플래그를 추가한다. 이게 SonarCloud shell:S6506 이슈(componentKeys=coralstay_langtoolchain, 해당 라인)의 직접적인 수정 대상이다. 이 호출은 이미 받은 뒤 HOMEBREW_INSTALL_SHA256과 shasum 비교로 무결성은 검증하지만, 전송 구간 자체가 https로 강제되지 않아 리다이렉트를 통한 프로토콜 다운그레이드 가능성이 있었음. --proto-default/--ssl-reqd는 이 URL이 이미 https 스킴을 명시하고 FTP 관련 옵션이라 불필요하다고 조사로 결론남.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
01_bootstrap_asdf.sh:81의 curl 호출에 --proto '=https' --proto-redir '=https' --tlsv1.2 세 플래그 추가 완료. shellspec sh/bash/dash 216 examples 0 failures(신규 케이스 1건 포함), shellcheck 신규 경고 없음(기존 SC1091/SC3043만 잔존, 둘 다 프로젝트 컨벤션상 허용). spec/bootstrap_asdf_spec.sh의 기존 grep 기반 정적 검증을 curl 호출이 2줄로 나뉜 것에 맞게 수정.
<!-- SECTION:FINAL_SUMMARY:END -->
