---
id: m-18
title: "curl HTTPS 강제 하드닝 (SonarCloud S6506)"
---

## Description

SonarCloud S6506이 scripts/install/01_bootstrap_asdf.sh:81의 curl -L 호출(Homebrew 설치 스크립트 다운로드, -L로 리다이렉트 추적)에 대해 'HTTPS should be enforced on HTTP clients following redirects'를 지적함. 조사 결과 --proto '=https' / --proto-redir '=https' / --tlsv1.2 세 플래그가 필요·충분(--proto-default, --ssl-reqd는 무관하다고 결론). 사용자 승인: '3가지 모두 적용' — 실제 코드 curl 호출과, 사용자가 복붙하는 curl-pipe 설치 안내 문서(README/헤더 주석)까지 함께 하드닝한다.
