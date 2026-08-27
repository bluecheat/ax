---
name: spec
description: "새 spec 디렉토리 생성 — 'spec 만들어줘', 'goax spec new <slug>', '스펙 작성 시작'. .ax/docs/spec/NNN-<slug>/ 에 size×risk에 맞는 tier(standard/full)만큼만 SDD 산출물 생성. plan.md 폐기 — 설계 결정은 ADR 로. tier override: '--tier standard|full' 또는 자연어 '간단/풀패키지'. 결정론은 .ax/scripts/bash/ 위임. 슬래시로도 호출 가능: '/spec'."
---

# goax spec — 새 SDD 디렉토리 (tier-aware, script-backed)

> 별칭: `spec-new` (예: "goax spec new <slug>") — 같은 skill.

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동
- "spec 만들어줘 — payment-refund"
- "goax spec new payment-refund"
- "결제 환불 spec(스펙) 작성하자"

## 핵심 원칙 — tier-aware + script-backed

> 처음부터 spec / tasks / research / data-model / contracts / quickstart / checklists 다 만들지 않아요.
> triage의 size×risk 결과로 **딱 필요한 만큼**만 만들고, 결정론적 부분(번호·디렉토리·cp)은 `.ax/scripts/bash/`에 위임.

### Tier 매트릭스 (2 단계)

| Tier | 산출물 | 적용 size×risk |
|---|---|---|
| **standard** | `spec.md` + `tasks.md` (2) | S/M/L × L0~L2 및 M×L3 |
| **full** | + `research.md` + `data-model.md` + `quickstart.md` + `contracts/` + ADR | L × L3 / XL × * |

> `plan.md` 폐기 — 설계 결정·아키텍처·트레이드오프는 ADR (`.ax/docs/adr/NNNN-*.md`) 로 기록.
> spec.md §7.5 Technical Context (스택·영향 모듈·적용 룰·진입 ADR) 가 *기술 컨텍스트* 자리예요.
> `basic` tier 폐기 — standard 가 최소 단위.

**Lazy 생성** — tier 와 무관, 필요 시 명시 추가:
```bash
add-spec-files.sh --spec <NNN-slug> --add checklists      # checklists/requirements.md
add-spec-files.sh --spec <NNN-slug> --add contracts       # contracts/{api.yaml, events.md}
```

자연어 매핑:
- "스펙만", "간단", "tasks까지" → `--tier standard`
- "풀패키지", "전부", "다 만들어" → `--tier full`
- 명시 없음 → `tier-from-state.sh`가 current-task.json 보고 자동 결정

## 1. 분석 — 스크립트로 위임

### 1.1 slug 결정
사용자가 명시 → 그대로. 안 하면 작업 설명에서 LLM이 의역해 영문 kebab-case 도출, 검증은 `slug-from-text.sh`로:

```bash
SLUG_RESULT=$(bash .ax/scripts/bash/slug-from-text.sh --json "payment refund policy change")
SLUG=$(echo "$SLUG_RESULT" | jq -r '.result.slug')
```

### 1.2 중복·관련 자료 확인 — `triage-search.sh` 위임

```bash
# 정확 슬러그는 바로 판정
ls -d .ax/docs/spec/*-${SLUG} 2>/dev/null

# 같은 도메인 자료 — 동의어 확장 + 본문 랭킹 + 스니펫을 한 번에.
# 도메인어 2~4개. **한글 그대로 넣으세요** (본문이 한국어면 한글이 제일 잘 맞아요).
KEYWORDS="환불 정산 refund"
SEARCH=$(bash .ax/scripts/bash/triage-search.sh --keywords "$KEYWORDS" --json)
echo "$SEARCH" | jq -r '.result.specs[] | "spec \(.score)\t\(.path)"'
echo "$SEARCH" | jq -r '.result.adrs[]  | "adr  \(.score)\t\(.path)"'
```

직접 `grep` 하지 마세요 — 슬러그엔 없고 본문에만 있는 spec 을 놓쳐요.
`snippets` 로 연관성을 먼저 판단하고, 정말 관련 있는 것만 본문을 Read 하세요.

발견 시 사용자에게 알림: "기존 spec 003-payment-coupon-stack 과 관련 있어 보여요. 새 spec 으로 갈까요, 003 에 추가 (`/spec-tasks 003` 또는 ADR 신규) 할까요?"

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
📐 spec (생성 대상)

 📍 발견
  slug   payment-refund-policy-change
  번호   005 (이전 가장 큰 번호: 004)
  도메인 매칭 payment → L3 (config.yml)
  tier 권장 full (이유: L × L3 — full SDD + ADR)

 🎯 목표 .ax/docs/spec/005-payment-refund-policy-change/

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ tier=full (권장 — L×L3)     [권장]
  산출물 5 파일 + ADR — spec/tasks/research/data-model/quickstart + docs/adr/NNNN-*.md

 [b] tier=standard (2 파일 — spec/tasks)
  설계 결정은 별도 ADR 로 기록. 나중에 research/data-model 등은 add-spec-files.sh 로 점진 추가.

 [c] 다른 slug 로 / 취소

 ▸ 답해주세요 [a] / [b] / [c]
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
✓ spec 005-payment-refund-policy-change 생성 (tier=full, 5 파일 + ADR 권장)
✓ current-task.json 갱신: phase=spec, spec_id=005

📍 다음 단계
 1. spec.md 작성 — 문제 정의 + NEEDS CLARIFICATION 명시 + §7.5 Technical Context
 2. "/spec-validate" — 게이팅 통과 (NEEDS / placeholder / 빈 섹션)
 3. "/spec-tasks" → "/spec-implement"
 4. (L3 도메인이라) "/adr 작성" 권장 — 설계 결정 기록
```

## 5. `--add` 옵션 — 점진 확장

기존 spec 에 tasks/research 추가:
```
"spec 005에 tasks 추가해줘"
```

→ 명시적 명령 `/spec-tasks` 사용 권장 (단계별 가이드 제공).
또는 직접 `add-spec-files.sh`:
```bash
bash .ax/scripts/bash/add-spec-files.sh --json --spec 005-payment-refund --add tasks
```

> `--add plan` 은 폐기됐어요 — 설계 결정은 `/adr` 로.

## 절대 금지

- 사용자 동의 없이 기존 spec 디렉토리 덮어쓰지 않아요.
- spec.md 본문을 자동 채우지 않아요. 사용자가 도메인을 알아요.
- 처음부터 5 파일 다 깔지 않아요 — 항상 tier-aware
- 결정론 부분(번호·sha·cp)을 LLM이 직접 처리 X — 스크립트 위임
- slug 추출이 모호하면 `[c]` 옵션으로 사용자에게 명시 요청.
- `tier=basic` 사용자가 명시해도 거부 — 폐기된 tier. standard 권유.
- `plan.md` 작성 가이드 X — 설계 결정은 ADR 로 위임.

## state.json 갱신

```bash
jq '.last_skill = "spec" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
