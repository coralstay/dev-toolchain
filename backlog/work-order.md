<!-- work-order-hash: ab3c8e8918c7dabe4e911de9a9aedfdd8fb6280f655cfc7cba78b1b27b87149c -->
# 작업 순서

`work_order.py`가 backlog/tasks의 의존(`dependencies`)으로 만든 파일이다 — 직접 고치지 말고 다시 생성한다. 같은 단계의 태스크는 병렬로, 단계는 위에서 아래로 순차로 진행한다. Done 태스크와 없는 태스크에 대한 의존은 충족된 것으로 본다.

| 단계 | ID | 제목 |
|---|---|---|
| 1 | TASK-179 | workspace: 저장소별 에이전트 담당 열과 workspace owner 명령 |
