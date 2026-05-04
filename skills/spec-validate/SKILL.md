---
name: spec-validate
description: "spec NEEDS CLARIFICATION 게이팅 — 'spec 확인', 'goax spec check', '스펙 게이트'. 작성된 spec.md에서 'NEEDS CLARIFICATION' 마커를 검출해 진행 가능 여부 판단."
---

# goax spec-validate — NEEDS CLARIFICATION 게이팅

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## SSOT 원칙
spec.md가 single source of truth. **NEEDS CLARIFICATION이 하나라도 남으면** plan/tasks 진행 금지.

## 발동
- "goax spec check"
- "spec NEEDS CLARIFICATION 검사"
- "이 스펙으로 다음 단계 가도 돼?"

## 1. spec 디렉토리 식별

- 사용자가 번호/slug 명시: `goax spec check 005`
- 미명시: 가장 최근 수정된 `.ax/docs/spec/NNN-*/` 자동 선택, 사용자에게 "이 spec 맞아요?" 한 번 확인

## 2. 스캔

```bash
grep -nH "NEEDS CLARIFICATION" .ax/docs/spec/${dir}/*.md
```

## 3. 출력

### 통과 (0건)

```
✓ spec-validate 005-payment-refund-policy-change 통과

 📍 발견 NEEDS CLARIFICATION 0건 (3개 파일 검사: spec.md, plan.md, contracts/api.yaml)
 🎯 결과 plan/tasks 진행 가능

 다음 단계
 plan.md 작성 → tasks.md → 구현
 L3 도메인이라 ADR 동반 권장 — "ADR 0006 작성 도와줘"
```

### 실패 (1건 이상)

```
✗ spec-validate 005-payment-refund-policy-change 보류

 📍 발견 NEEDS CLARIFICATION 3건

  spec.md:42  환불 가능 기간 (7일? 14일?)
  plan.md:18  PG사별 분기 처리 여부
  contracts/api.yaml:31 부분 환불 지원?

 🎯 게이팅 NEEDS CLARIFICATION 모두 해결 후 재검사 필요

 ─ 다음 단계 ──────────────────────────────────────

 [a] ✓ 한 항목씩 같이 해결      [권장]
  제가 각 항목을 보여드리고 사용자 결정·도메인 전문가 확인 받아요.
  결정 후 spec/plan/contracts 본문 자동 갱신 (NEEDS CLARIFICATION 제거).

 [b] 사용자가 직접 편집 후 다시 [check]
  파일 위치만 알려드릴게요. 직접 수정 후 "goax spec check 005" 재실행.

 [c] ⚠ 보류 — 일단 다른 작업으로
  경고: L3 도메인이라 게이팅 통과 없인 plan/tasks 진행 시 후폭풍 큼.

 ▸ 답해주세요 [a] / [b] / [c]
```

## 4. Triage 자동 게이팅 (참고)

`.ax/config.yml`의 `domain_risk`가 L2/L3인 도메인 작업이면, 이 게이트 통과 없이는 `triage` 결과가 "spec 미통과 — 진행 금지"로 변해요. spec-validate가 통과해야 triage 흐름이 풀려요.

## 절대 금지

- NEEDS CLARIFICATION을 임의로 "해결"로 처리 X — 사용자만 결정.
- 통과를 가짜로 만들지 않아요. 실패는 명확히 ✗.

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- current_task.spec_passed

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
jq '.last_skill = "spec-validate" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```

## current-task.json 갱신 

NEEDS CLARIFICATION 통과 시 phase 진행, 미해소 시 blocked_by 기록 → 다음 skill(spec-plan/tasks/implement)이 phase 보고 차단:

```bash
# 통과
jq '.phase = "spec_checked" | .blocked_by = [] | .updated_at = (now | todate)' \
 .ax/current-task.json \
 > .ax/current-task.json.tmp && mv .ax/current-task.json.tmp .ax/current-task.json

# 미해소 — blocked_by에 NEEDS CLARIFICATION 위치 기록
BLOCKED='["spec.md:42","plan.md:18"]'
jq --argjson bb "$BLOCKED" \
 '.phase = "spec_blocked" | .blocked_by = $bb | .updated_at = (now | todate)' \
 .ax/current-task.json > .ax/current-task.json.tmp \
 && mv .ax/current-task.json.tmp .ax/current-task.json
```
