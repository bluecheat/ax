---
type: file_exists
path: ".ax/.session/*/injected/spirit_*security*"
arm: with-only
---

`pre-edit/spirit-rules-inject.sh` 가 실제로 돌았는가 — `goax_inject_fresh` 가 남기는 세션 dedupe 마커예요. 플러그인
발동 지표라 with-without 에선 점수에서 빠져요. 이게 fail 인데 rule-respected 가 pass 면 모델이 룰 파일을 스스로 찾아
읽은 거라 Δ 를 hook 의 공으로 볼 수 없어요. (PreToolUse `additionalContext` 는 trace 에 안 남아서 `regex: trace` 로는 못 재요.)
