---
name: triage
description: "사용자가 새 작업·기능·수정·리팩토링·버그 fix를 요청할 때 가장 먼저 자동 매칭되는 skill. Size × Risk로 30초 안에 분류하고 spirit·룰·페르소나를 자동 주입. 트리거: '구현해줘', '만들어줘', '작업 계획', '어떻게 만들지', '고쳐줘', '추가해줘', '바꿔줘', '리팩토링', '리팩터링', 'fix', '버그', '기능 추가', 'PR 만들어', '작업하자', '/triage', 'classify', 새 대화 첫 메시지에서 작업 의도가 보이면 자동 발동. **EnterPlanMode 호출 전·직후에도 1회 필수** — plan mode 와 triage 는 직교 (다른 축). plan mode 의 도구 제약이 Skill 호출을 막지 않음."
---

# Triage Skill

> 응급실 트리아지처럼, 들어온 작업을 30초 안에 분류하고 권장 경로를 제시해요.

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 따라요.
**`.ax/spirit/values.md` 또는 `tone.md`가 누락되면 triage 자체가 fail. 작업 시작 자체가 거부됨.

## 발동 시점

- 사용자가 새 작업을 요청한 첫 메시지
- 사용자가 명시적으로 `/triage <설명>` 호출
- 작업 도중 스코프가 커져서 재분류가 필요할 때
- **`EnterPlanMode` 호출 전·직후 (plan mode 가 triage 를 대체하지 않음)** — plan mode 는 깊은 탐색·승인 게이트, triage 는 분류·spirit 주입. 두 도구가 직교라서 plan mode 안에서도 `Skill goax:triage` 호출 가능·필수. "사용자가 '계획' 단어 썼으니 plan mode 직행" 은 anti-pattern

## 1단계 — 빠른 사전 검색 (★ 큰 프로젝트 필수)

LLM 분류 전에 **bash로 후보 자료를 좁혀요**. 큰 프로젝트(>1000 파일)일수록 이게 정확도·속도를 결정해요.

### 1.1 작업 키워드 추출

사용자 메시지에서 명사·도메인 단어를 뽑아 변수로:
```bash
KEYWORDS="payment refund settlement" # 예시 (실제는 LLM이 의역)
```

### 1.2 관련 자료 grep — 5초 안에

```bash
# 기존 spec 후보 (같은 도메인 작업이 이미 있나)
find .ax/docs/spec -maxdepth 2 -type d 2>/dev/null \
 | grep -iE "($KEYWORDS)" | head -10

# 관련 ADR (이미 결정된 게 있나)
grep -rilE "($KEYWORDS)" .ax/docs/adr 2>/dev/null

# 관련 mistakes (과거 같은 영역에서 실수 있었나)
grep -rilE "($KEYWORDS)" .ax/mistakes 2>/dev/null

# Constitution / Spirit 룰 매칭
grep -inE "($KEYWORDS)" CLAUDE.md .ax/spirit/rules/*.md 2>/dev/null

# Module 룰 매칭 — Layer 2 (.ax/modules/*/rules.md frontmatter keywords)
# zsh/bash 호환을 위해 word splitting 대신 alternation 사용
ALT=$(echo "$KEYWORDS" | tr -s ' ' '|' | sed 's/^|//;s/|$//')
for module_dir in .ax/modules/*/; do
    [ -d "$module_dir" ] || continue
    [ -f "${module_dir}rules.md" ] || continue
    KW_LINE=$(grep -E '^keywords:' "${module_dir}rules.md" 2>/dev/null | head -1)
    [ -z "$KW_LINE" ] && continue
    [ -z "$ALT" ] && continue
    # 단어 경계: keywords 배열의 [, ], `,`, ` ` 가 키워드 양옆에 있어야 매칭
    # → "ad"가 "payment" 안에 있어도 false positive 안 남
    MATCHED=$(echo "$KW_LINE" | grep -oiE "(\[|, )(${ALT})(\]|,| )" 2>/dev/null \
              | head -1 | tr -d '[],| ')
    [ -n "$MATCHED" ] && echo "→ ${module_dir}rules.md (matched: $MATCHED)"
done

# 외부 spec 흡수본도 검색
grep -rilE "($KEYWORDS)" .ax/docs/spec/imported 2>/dev/null
```

발견된 자료는 분류 결과에 *Required reading*으로 첨부해요.
**`.ax/modules/<n>/rules.md`가 매칭되면 분류 결과의 *Required reading*에 반드시 포함** — 모듈 도메인 룰은 작업 진입 시 컨텍스트에 들어가야 효력 있어요.

### 1.3 도메인 위험도 매칭

```bash
# config.yml의 domain_risk 매트릭스
grep -E "^[[:space:]]+($KEYWORDS):" .ax/config.yml \
 | awk -F: '{print $1, $2}' | sed 's/^[[:space:]]*//'
```

매칭이 없으면 `default_risk` (기본 L1) 사용.

## 2단계 — Size × Risk 분류

### Size 추정

| Size | 기준 |
|---|---|
| S | 한 파일·한 함수, 30분 안 |
| M | 1~2 모듈, 반나절 안 |
| L | 다중 모듈 또는 새 추상화, 1~3일 |
| XL | 새 도메인·새 모듈·아키텍처 변경, 1주 이상 |

### Risk

`.ax/config.yml`의 `domain_risk` 매핑 우선. 없으면 `default_risk`.

### 게이팅 매트릭스 (spec tier 포함)

| Size × Risk | 권장 경로 | spec tier | 게이트 |
|---|---|---|---|
| S × L0~L1 | 즉시 작업 | — (불필요) | hooks만 |
| M × L0~L1 | inline fallback | basic (spec.md만, 선택) | hooks + lint |
| M × L2 | spec 권장 | **basic** (spec.md + README) | spec-validate |
| M × L3 | spec + plan | **standard** (spec + plan + tasks) | spec-validate + evaluator |
| L × L0~L2 | spec + plan + tasks | **standard** | spec-validate + evaluator |
| L × L3 / XL × * | spec + plan + tasks + research/data-model/contracts + ADR | **full** (9 파일) | spec-validate + ADR + 사람 게이트 |

**핵심**: triage가 size×risk에 따라 *spec tier 권장*을 함께 출력해요. spec-new는 이 tier 결과를 받아 *필요한 파일만* 생성해요. 처음부터 9개 다 깔지 않음.

## 3단계 — 출력

```
🔬 Triage (입력: "<요약>")

 📍 분류
  Size  L (다중 모듈, 2~3일 추정)
  Risk  L3 (payment 도메인 매칭 — config.yml)
  도메인  payment

 🎯 권장 경로 spec + ADR 동반, architect 게이트, evaluator 검토

 ─ 사전 검색 결과 ─────────────────────────────────

 관련 spec .ax/docs/spec/003-payment-coupon-stack/ (참고)
 관련 ADR  .ax/docs/adr/0002-pg-multi-provider.md
 관련 mistakes .ax/mistakes/2026-04-15-002-pg-key-leak.md (3주 전)
 매칭 룰  AX:CRITICAL:003 (시크릿 hardcode 금지)
    AX:MANDATORY:001 (PG 변경 시 ADR 필수)

 ─ 자동 주입 ─────────────────────────────────────

 spirit  values.md, tone.md, rules/{security, data}.md
 persona  payment-engineer (도메인 매칭 시) | inline fallback
     → Layer 1 + 모듈 CLAUDE.md 우선 로드
     → 변경 1~2 파일이면 즉시 작업, 그 이상 task 분해
     → commit 메시지: 한국어 + type 접두사 (feat/fix/refactor/docs)
 agent  evaluator (PR 직전), architect (설계 결정 시)

 ─ 다음 단계 ─────────────────────────────────────

 [a] ✓ spec 작성부터 시작 (tier=full)    [권장 — L×L3]
  명령 "새 spec 만들어줘 — payment-refund-window-extension --tier full"
  산출물 spec.md + plan.md + tasks.md
    + research.md + data-model.md
    + contracts/{api,events} + quickstart.md
    + checklists/requirements.md + README.md (9개)
  다음 spec.md 작성 → spec-validate 통과 → ADR 동반 → 구현

 [b] tier 다운그레이드 — standard (4개) 또는 basic (2개)
  이유 L3 도메인이지만 변경 범위가 좁다고 판단 시
  명령 "--tier standard" 또는 "--tier basic"
  권장 L3는 standard 이상 권장, basic은 안티패턴 경고

 [c] ADR 먼저 (architecture 결정이 큰 경우)
  명령 "ADR 0006 작성해줘 — payment-refund-strategy"

 [d] 현재 분류 의심 — 재분류 요청

 ▸ 답해주세요 [a] / [b] (tier 같이) / [c] / [d]
```

## Workflow

1. 1단계 (bash 검색) → 후보 자료 5초 안에 좁힘
2. 2단계 (Size × Risk) — config.yml + 키워드 매핑
3. 3단계 (출력 + 옵션 제시) — 사용자가 [a]/[b]/[c] 선택
4. **3.5단계 — current-task.json 작성**
5. 분류 오차 발견 시 `.ax/mistakes/` 캡처 → 다음 audit에서 룰 승격 검토

## 3.5단계 — current-task.json 작성 

분류 직후 `.ax/current-task.json`에 작업 컨텍스트를 기록해요. spec-new/spec-plan/spec-tasks/audit이 이 파일을 *입력*으로 받음 (LLM 재추론 X).

```bash
TASK_ID=$(date -u +%Y-%m-%d)-$(printf '%03d' $((RANDOM % 1000)))
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq --arg id "$TASK_ID" \
 --arg desc "$DESCRIPTION" \
 --arg size "$SIZE" \
 --arg risk "$RISK" \
 --arg domain "$DOMAIN" \
 --arg now "$NOW" \
 '.task_id = $id
 | .description = $desc
 | .size = $size
 | .risk = $risk
 | .domain = $domain
 | .started_at = $now
 | .phase = "triaged"' \
 .ax/current-task.json > .ax/current-task.json.tmp \
 && mv .ax/current-task.json.tmp .ax/current-task.json
```

이후 spec-new가 `.ax/scripts/bash/tier-from-state.sh --json`로 tier 자동 결정.

## 상세

- Size × Risk 매트릭스, 도메인 매칭 키워드: [`references/risk-matrix.md`](references/risk-matrix.md)
- spec 게이팅: `spec-validate` skill
- ADR: `adr` skill / `architect` agent

## 절대 금지

- bash 사전 검색 결과를 무시하고 추측만으로 분류 X
- 사전 검색에서 "관련 mistakes 있음"이 나오면 *반드시* 본문 읽고 분류에 반영
- L3 도메인을 spec 없이 즉시 작업 권장 X (게이팅 우회 X)
