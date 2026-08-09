---
name: goax
description: "goax 명령 인덱스 — 모든 skill 을 자연어로 부르는 가이드 + 트리거 키워드"
---

goax 의 모든 기능은 **자연어 트리거** 로 호출돼요 (thin wrapper 슬래시 명령들은 폐기 — /goax 인덱스 1개만 유지). 사용자가 `/goax` 만 쳤을 때 다음 인덱스를 보여주세요. 또한 `.ax/state.json` 이 있으면 마지막에 현재 4계층 활성도를 한 줄로 보여주세요.

```
🪝 goax — 자연어로 부르는 skill 인덱스

▸ 설치·진단
  "goax 도입" / "goax 설치"     — up (install or idempotent update)
  "goax 분석" / "goax 마무리"   — onboarding (brownfield 5-step Q1~Q5)
  "진단해줘" / "goax doctor"    — 결손·drift 점검
  "rules 보여줘"                — 룰 통합 인덱스 (Constitution + Spirit + Module)

▸ 작업 분류·구현
  "구현해줘" / "고쳐줘" / "리팩토링" — triage (Size × Risk 30초 분류)
  "spec 만들어줘 — <slug>"           — 새 spec 디렉토리 (tier-aware)
  "tasks 분해"                       — tasks.md 분해
  "구현 시작" / "tasks 실행"         — tasks.md 순차 실행
  "spec 확인"                        — NEEDS CLARIFICATION 게이팅

▸ 결정·회고
  "ADR 작성" / "결정 기록"           — ADR 새 파일
  "실수 기록해줘" / "mistake 박아줘" — mistake 1건 capture
  "실수 회고" / "audit"              — Mistake Loop 심사·룰 승격 후보

▸ Spirit / HUD
  "spirit 점검"                      — frontmatter + 토큰 무결성 검사
  "/hud setup"                       — statusline 활성화

각 트리거는 SKILL.md frontmatter 의 키워드 매칭으로 동작해요. autorouting 이
실패하면 더 구체적인 동의어를 시도하거나 위 인덱스의 키워드를 그대로 사용하세요.

자세히: README.md / .ax/docs/reference/
```
