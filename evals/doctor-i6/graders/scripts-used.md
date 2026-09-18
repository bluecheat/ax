---
type: tool_used
tool: Bash
input_match: "check-rule-enforcement\\.sh|doctor-scan\\.sh|check-sensor-liveness\\.sh"
arm: with-only
---

doctor 가 손 진단이 아니라 자기 스크립트(I6 는 check-rule-enforcement.sh, C3 는 check-sensor-liveness.sh)로
판정했는가 — 플러그인 발동 지표예요 (with-without 에선 점수에서 빠져요). 이게 fail 인데 i6-reported 가 pass 면
모델이 파일을 읽고 추론으로 맞힌 거라, 결정론 층이 아니라 프로즈를 잰 거예요.
