---
id: m-20
title: "S7688/POSIX sh 유지 근거 문서화"
---

## Description

사용자와의 긴 논의(POSIX sh vs bash, SonarCloud S7688 오탐 처리)를 decision record + docs/ 리서치 문서로 남긴다. 코드 변경 없음, 순수 문서화. 최종 확정된 3가지: (1) POSIX sh 유지, bash 전환 안 함, (2) S7688 규칙은 Quality Profile에서 비활성화하지 않고 계속 활성 유지(회귀 탐지 카나리아), (3) 기존 14+1건은 SonarCloud 쪽은 안 건드리고 GitHub Issue만 사용자가 수동으로 close — 이 SonarCloud=열림/GitHub=닫힘 불일치는 의도적이며 문서화 필요.
