---
name: spec
description: "새 spec 디렉토리 생성 — 'spec 만들어줘', 'goax spec new <slug>', '스펙 작성 시작'. .ax/docs/spec/NNN-<slug>/ 에 size×risk에 맞는 tier(basic/standard/full)만큼만 SDD 산출물 생성. 처음부터 9 파일 다 깔지 않아요. tier override: '--tier basic|standard|full' 또는 자연어 '스펙만/플랜까지/풀패키지'. 결정론은 .ax/scripts/bash/ 위임."
---

# goax spec-new — 새 SDD 디렉토리 (tier-aware, script-backed)

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동
- "spec 만들어줘 — payment-refund"
- "goax spec new payment-refund"
- "결제 환불 spec 작성하자"
- triage가 [a] 옵션으로 위임

## 핵심 원칙 — tier-aware + script-backed

> 처음부터 spec.md / plan.md / tasks.md / research / data-model / contracts / quickstart / checklists 9개 파일을 *전부* 만들지 않아요.
> triage의 size×risk 결과로 **딱 필요한 만큼**만 만들고, 결정론적 부분(번호·디렉토리·cp)은 `.ax/scripts/bash/`에 위임.

### Tier 매트릭스

| Tier | 산출물 | 적용 size×risk |
|---|---|---|
| **basic** | `spec.md` + `README.md` (2) | S/M × L0~L1 |
| **standard** | + `plan.md` + `tasks.md` (4) | M × L2~L3 / L × L0~L2 |
| **full** | + `research.md` + `data-model.md` + `contracts/*` + `quickstart.md` + `checklists/requirements.md` (9) | L × L3 / XL × * |

자연어 매핑:
- "spec만", "스펙만 만들어줘" → `--tier basic`
- "plan까지", "tasks까지" → `--tier standard`
- "풀패키지", "전부", "다 만들어" → `--tier full`
- 명시 없음 → `tier-from-state.sh`가 current-task.json 보고 자동 결정

## 1. 분석 — 스크립트로 위임

### 1.1 slug 결정
사용자가 명시 → 그대로. 안 하면 작업 설명에서 LLM이 의역해 영문 kebab-case 도출, 검증은 `slug-from-text.sh`로:

```bash
SLUG_RESULT=$(bash .ax/scripts/bash/slug-from-text.sh --json "payment refund policy change")
SLUG=$(echo "$SLUG_RESULT" | jq -r '.result.slug')
```

### 1.2 중복 확인 — bash로 빠르게

```bash
# 정확 슬러그
ls -d .ax/docs/spec/*-${SLUG} 2>/dev/null

# 도메인 키워드로 유사 spec
KEYWORDS="payment refund"
find .ax/docs/spec -maxdepth 2 -type d 2>/dev/null | grep -iE "($KEYWORDS)"
grep -lE "($KEYWORDS)" .ax/docs/spec/*/spec.md 2>/dev/null
grep -lE "($KEYWORDS)" .ax/docs/spec/imported/*/* 2>/dev/null
```

발견 시 사용자에게 알림: "기존 spec 003-payment-coupon-stack과 관련 있어 보여요. 새 spec으로 갈까요, 003에 추가(`/spec-plan 003`)할까요?"

### 1.3 다음 번호 계산 — `next-spec-num.sh`

```bash
NEXT=$(bash .ax/scripts/bash/next-spec-num.sh --json | jq -r '.result.next')
# 또는 텍스트만: NEXT=$(bash .ax/scripts/bash/next-spec-num.sh)
```

### 1.4 Tier 결정 — `tier-from-state.sh`

```bash
TIER_RESULT=$(bash .ax/scripts/bash/tier-from-state.sh --json)
TIER=$(echo "$TIER_RESULT" | jq -r '.result.tier')
REASON=$(echo "$TIER_RESULT" | jq -r '.result.reason')
```

사용자가 `--tier` 명시했으면 override:
```bash
TIER_RESULT=$(bash .ax/scripts/bash/tier-from-state.sh --json --size L --risk L3)
```

## 2. 출력 (옵션 제시)

```
📐 spec-new (생성 대상)

 📍 발견
  slug   payment-refund-policy-change
  번호   005 (이전 가장 큰 번호: 004)
  도메인 매칭 payment → L3 (config.yml)
  tier 권장 full (이유: L × L3 — full SDD + ADR)

 🎯 목표 .ax/docs/spec/005-payment-refund-policy-change/

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ tier=full (권장 — L×L3)     [권장]
  산출물 9 파일 — spec/plan/tasks/research/data-model/contracts/.../README

 [b] tier=standard (4 파일 — spec/plan/tasks/README)

 [c] tier=basic (2 파일 — spec/README)
  나중에 "/spec-plan" 으로 plan 추가 가능

 [d] 다른 slug로 / 취소

 ▸ 답해주세요 [a] / [b] / [c] / [d]
```

## 3. 적용 — `init-spec-dir.sh` 호출

```bash
RESULT=$(bash .ax/scripts/bash/init-spec-dir.sh \
   --json --tier "$TIER" --slug "$SLUG")

# 검증
STATUS=$(echo "$RESULT" | jq -r '.status')
if [ "$STATUS" != "ok" ]; then
 echo "$RESULT" | jq -r '.errors | join("\n")'
 exit 1
fi

SPEC_DIR=$(echo "$RESULT" | jq -r '.result.spec_dir')
SPEC_ID=$(echo "$RESULT" | jq -r '.result.spec_id')
FILES=$(echo "$RESULT" | jq -r '.result.files | join(", ")')
NEXT_STEP=$(echo "$RESULT" | jq -r '.next_step')
```

`init-spec-dir.sh`가 알아서:
- 디렉토리 생성
- tier별 selective cp (`_templates/`에서)
- `.tier` 메모 작성

## 3.5. current-task.json 갱신

```bash
jq --arg id "$SPEC_ID" \
 --arg dir "$SPEC_DIR" \
 --arg tier "$TIER" \
 '.spec_id = $id | .spec_dir = $dir | .spec_tier = $tier
  | .phase = "spec"
  | .updated_at = (now | todate)' \
 .ax/current-task.json > .ax/current-task.json.tmp \
 && mv .ax/current-task.json.tmp .ax/current-task.json
```

## 4. ✓ 메시지

```
✓ spec 005-payment-refund-policy-change 생성 (tier=full, 9 파일)
✓ current-task.json 갱신: phase=spec, spec_id=005

📍 다음 단계
 1. spec.md 작성 — 문제 정의 + NEEDS CLARIFICATION 명시
 2. "/spec-validate" — 게이팅 통과
 3. "/spec-plan" → "/spec-tasks" → "/spec-implement"
 4. (L3 도메인이라) "/adr 작성" 권장
```

## 5. `--add` 옵션 — 점진 확장

기존 spec에 plan/tasks/research 추가:
```
"spec 005에 plan 추가해줘"
```

→ 명시적 명령 `/spec-plan` 사용 권장 (단계별 가이드 제공).
또는 직접 `add-spec-files.sh`:
```bash
bash .ax/scripts/bash/add-spec-files.sh --json --spec 005-payment-refund --add plan,tasks
```

## 절대 금지

- 사용자 동의 없이 기존 spec 디렉토리 덮어쓰지 않아요.
- spec.md 본문을 자동 채우지 않아요. 사용자가 도메인을 알아요.
- 처음부터 9 파일 다 깔지 않아요 — 항상 tier-aware
- 결정론 부분(번호·sha·cp)을 LLM이 직접 처리 X — 스크립트 위임
- slug 추출이 모호하면 `[d]` 옵션으로 사용자에게 명시 요청.

## state.json 갱신

```bash
jq '.last_skill = "spec" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
