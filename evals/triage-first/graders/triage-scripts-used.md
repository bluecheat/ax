---
type: tool_used
tool: Bash
input_match: "triage-search\\.sh|update-task\\.sh|update-state\\.sh --skill triage"
arm: with-only
---

triage 가 산문이 아니라 자기 스크립트(triage-search.sh · update-task.sh --start · update-state.sh --skill triage)로
분류 컨텍스트를 검색하고 current-task.json 에 결과를 적었는가 — 플러그인 발동 지표예요 (with-without 에선 점수에서
빠져요). triage-skill-called 가 pass 인데 이게 fail 이면 SKILL.md 가 로드됐지만 결정론 층까지는 안 내려간 거예요.
