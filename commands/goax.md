---
name: goax
description: "goax 명령 인덱스 — 모든 slash command + 자연어 트리거 한눈에"
---

goax plugin의 모든 slash command를 보여주세요. 각 명령의 한 줄 설명과 자연어 별칭을 포함해서 다음 형식으로:

```
🪝 goax — 명령 인덱스

  /doctor          결손 진단 + _templates drift     ↔ "진단해줘"
  /rules           룰 통합 인덱스                    ↔ "rules 보여줘"

  /spec        새 spec 디렉토리 (tier-aware)    ↔ "spec 만들어줘 — <slug>"
  /spec-plan       기존 spec에 plan.md 추가         ↔ "plan 추가"
  /spec-tasks      plan 기반 tasks.md 분해          ↔ "tasks 분해"
  /spec-implement  tasks.md 순차 실행               ↔ "구현 시작"
  /spec-validate      NEEDS CLARIFICATION 게이팅       ↔ "spec 확인"

  /audit           Mistake Loop (캡처·심사·승격)    ↔ "audit", "또 그걸"

  자세히: README.md / docs/skill-routing.md
```

또한 `.ax/state.json`이 있으면 현재 4계층 활성도를 한 줄로 보여주세요.

자연어 트리거로만 부르는 작업도 안내:
- "goax 도입해줘" → up (install or update)
- "goax 마무리" → onboarding
- "spirit 점검" → spirit-check
- "ADR 작성" → adr-write
- "<작업> 계획 세워줘" → triage
- HUD: "/hud setup" 또는 "statusline 활성화"
