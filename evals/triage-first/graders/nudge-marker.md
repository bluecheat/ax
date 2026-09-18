---
type: file_exists
path: ".ax/.triage-nudged"
arm: with-only
---

`user-prompt/triage-nudge.sh` (UserPromptSubmit) 가 실제로 돌아 구현 의도를 감지했는가 — nudge 를 밀어 넣을 때 남기는
세션 마커예요. 플러그인 발동 지표라 with-without 에선 점수에서 빠져요. 이게 fail 인데 triage-invoked 가 pass 면
모델이 AGENTS.md 의 META 룰을 스스로 읽고 따른 거라 Δ 를 hook 의 공으로 볼 수 없어요. (UserPromptSubmit stdout 은
trace 에 사용자 메시지로 섞여 `regex: trace` 로는 hook 과 프롬프트를 못 가르고, 마커는 hook 만 찍어요.)
