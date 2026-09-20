---
id: DRAFT-5
title: ~/.local/share/langtoolchain + ~/.local/bin/ltl 채우기
status: Draft
assignee: []
created_date: '2026-09-20 21:41'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
scripts/install/main.sh가 phase 07 이후(install.sh의 self-clone 임시디렉토리 EXIT trap이 지우기 전) ~/.local/share/langtoolchain/(scripts/lib.sh + install/ + uninstall/ + .tool-versions 미러 복사본)과 ~/.local/bin/ltl(디스패처, 다음 태스크에서 내용 채움)을 생성. 버전 마커 파일(.version, 커밋 SHA 또는 날짜)도 기록. 이미 존재하는 ~/.local/bin/ltl이 우리 게 아닌 것 같으면 조용히 덮어쓰지 않고 경고. m-23/decision-23 소속.
<!-- SECTION:DESCRIPTION:END -->
