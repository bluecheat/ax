---
name: spec-plan
description: "기존 spec에 plan.md 추가 + 작성 가이드 — '/spec-plan', 'spec에 plan 추가', 'plan 작성', 'design 단계', '기술 설계'. .ax/current-task.json의 spec_id 사용. add-spec-files.sh로 selective cp."
---

# spec-plan — plan.md 단계

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거
- `/spec-plan`
- "spec 005에 plan 추가해줘"
- "plan.md 작성하자"
- "기술 설계 단계로"

## 1. spec_id 결정

순서:
1. `.ax/current-task.json` 의 `spec_id` 우선
2. 사용자가 `/spec-plan 005` 처럼 명시했으면 그대로
3. 둘 다 없으면 사용자에게 물어요 (`{"spec_id":"005-payment-refund"}` 형태)

```bash
SPEC=$(jq -r '.spec_id + "-" + (.spec_dir | split("/") | .[-1] | split("-") | .[1:] | join("-"))' \
  .ax/current-task.json 2>/dev/null || echo "")
# 또는 spec_dir 마지막 디렉토리만
SPEC=$(jq -r '.spec_dir | split("/") | .[-1]' .ax/current-task.json 2>/dev/null || echo "")
```

## 2. 파일 추가 — add-spec-files.sh 호출

```bash
RESULT=$(bash .ax/scripts/bash/add-spec-files.sh --json --spec "$SPEC" --add plan)
# 결과 JSON 파싱
ADDED=$(echo "$RESULT" | jq -r '.result.added | join(", ")')
NEW_TIER=$(echo "$RESULT" | jq -r '.result.new_tier')
```

이미 plan.md가 있으면 `skipped`로 보고하고 작성 가이드만 출력.

## 3. plan.md 작성 가이드

사용자에게 다음 구조로 채우라고 안내:

```markdown
# Implementation Plan: <feature>

## Technical Context
- Tech stack
- Dependencies
- Project structure (영향 받는 모듈/디렉토리)

## Design Decisions
- 핵심 결정 (검토된 대안 포함)
- ADR이 필요한 결정은 별도 ADR 권장

## Architecture
- Component 다이어그램 (필요시)
- Data flow

## File Structure
- 추가/수정될 파일 목록
- 파일 간 의존

## Trade-offs
- 선택한 길의 비용·장점
- 거부한 대안과 이유

## Out of scope
- 이 plan에서 다루지 않는 것
```

각 섹션 채울 때 spec.md를 *입력*으로 받아요. spec.md의 NEEDS CLARIFICATION이 미해결이면 plan 작성 전에 spec-validate 먼저.

## 4. current-task.json 갱신

```bash
jq '.phase = "plan" | .updated_at = (now | todate)' .ax/current-task.json \
 > .ax/current-task.json.tmp && mv .ax/current-task.json.tmp .ax/current-task.json
```

## 5. 출력

```
📐 spec-plan (spec 005-payment-refund-policy-change)

 ✓ plan.md 추가 (tier: basic → standard)
 ✓ phase 갱신: spec → plan

 📍 다음
  1. plan.md 작성 — 위 6 섹션
  2. ADR 필요한 결정 있으면 "/adr 작성"
  3. tasks 단계로: "/spec-tasks"
```

## 절대 금지

- spec.md 없거나 비어 있을 때 plan 작성 — 먼저 spec 작성 권유
- spec.md의 NEEDS CLARIFICATION 무시 — 먼저 spec-validate 통과
- 자동으로 plan 본문 채우기 — 사용자가 도메인을 알아요. 가이드만

## state.json 갱신

```bash
jq '.last_skill = "spec-plan" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
