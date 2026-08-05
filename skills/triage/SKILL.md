---
name: triage
description: "사용자가 새 작업·기능·수정·리팩토링·버그 fix를 요청할 때 가장 먼저 자동 매칭되는 skill. Size × Risk로 30초 안에 분류하고 spirit·룰·페르소나를 자동 주입. 트리거: '구현해줘', '만들어줘', '작업 계획', '어떻게 만들지', '고쳐줘', '추가해줘', '바꿔줘', '리팩토링', '리팩터링', 'fix', '버그', '기능 추가', 'PR 만들어', '작업하자', '/triage', 'classify', 새 대화 첫 메시지에서 작업 의도가 보이면 자동 발동. EnterPlanMode 안에서도 1회 호출 필수."
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

## 0단계 — 의도 인터뷰 (입력이 짧을수록 더 적극적)

> 입력이 짧거나 모호하면 분류 전에 의도 한 가지만 확인해요.
> 표면 요청 (`"PR 만들어"`) 과 진짜 의도 (`"어떤 변경의 어떤 측면을?"`) 가 다를 수 있어요. 짐작으로 분류하면 size·risk 가 틀려서 이후 spec/tasks 가 어긋나요.

### 발동 조건 (셋 중 하나라도)

| 신호 | 검출 방법 | 예시 |
|---|---|---|
| **입력이 짧음** | word count < 5 | "결제 고쳐줘", "리팩토링", "PR 만들어" |
| **동사만 있음** | 명사·도메인·범위 중 2개 이상 누락 | "수정해줘", "정리해줘", "추가해줘" |
| **도메인 매칭 0** | 1.3 단계 `domain_risk` 매핑 결과가 비어있음 | 키워드가 어느 모듈에도 안 걸림 |

```bash
# 발동 체크 — 셋 중 하나라도 true 면 인터뷰 진입
WC=$(echo "$USER_INPUT" | wc -w | tr -d ' ')
SHORT=$([ "$WC" -lt 5 ] && echo 1 || echo 0)
# 동사만/도메인 매칭은 1단계 결과 합쳐서 LLM 이 판단
```

### 인터뷰 룰 (네 가지만 지켜요)

1. **한 번에 한 질문** — 여러 개 한 번에 던지지 않아요. 한 답 받고 다음.
2. **Multiple choice 우선** — 자유 텍스트보다 `[a]/[b]/[c]/[d]` 메뉴. 사용자가 짧게 답하더라도 진짜 의도가 명확해져요.
3. **사용자가 짧을수록 우리가 길어요** — 옵션 본문에 *예시·트레이드오프* 까지 적어요. 사용자 인지 부하를 옵션 쪽에 부담시켜요.
4. **3축으로 좁혀요** — 목적 (Why) / 제약 (Constraints) / 성공기준 (Done). 한 인터뷰 라운드당 한 축만.

### 스킵 조건 (인터뷰 생략 OK)

- 입력에 **도메인 + 동작 + 범위** 셋 다 명시 (예: `"<모듈> 의 <설정/필드> 를 <현재값> → <신규값>"`)
- 사용자가 명시적으로 `/triage --skip-interview` 또는 *"바로 분류해줘"*
- 직전 triage 의 `.ax/current-task.json` 에 의도 이미 기록됨 (같은 task 연속 작업)

### 출력 예 — 짧은 입력 (목적 축 인터뷰)

대상 동사 ("고쳐줘", "추가해줘") 만 있고 *왜·무엇* 이 빠진 케이스. 목적 축 한 가지만 좁혀요.

```
🔬 Triage (입력: "<X> 고쳐줘")

 입력이 짧아서 분류 전에 의도 한 가지만 확인할게요 (0단계).

 ─ 무엇을 고쳐요? ─
 [a] 버그 수정       기존 동작이 의도와 다르게 작동하고 있음
                    → 보통 작은 작업, spec 없이 inline + 테스트
 [b] 동작 변경       동작·정책 자체를 바꾸려는 것
                    → 보통 중~큰 작업, spec + ADR 동반
 [c] 리팩토링       동작은 같고 구조만 정리
                    → 보통 위험 낮음, spec 없이 hooks 만
 [d] 그 외          직접 설명

 ▸ [a] / [b] / [c] / [d] 또는 자유 텍스트
```

### 출력 예 — 표면 동사만 (대상 축 인터뷰)

동작은 있는데 *무엇의* 동작인지 모호한 케이스. 대상 축 한 가지만 좁혀요.

```
🔬 Triage (입력: "<표면 동사>")

 대상이 모호해서 진짜 무엇에 대한 작업인지 한 가지만 확인할게요.

 ─ 무엇에 대한 작업? ─
 [a] 지금 working tree 변경 그대로     현재 미커밋 변경 묶기
 [b] 특정 단위 마무리                   어느 spec/이슈/작업?
 [c] 다른 위치의 변경 수집              어느 브랜치/PR?

 ▸ 한 가지만
```

### 인터뷰 종료 후

답변을 받으면 그 의도를 1단계 (bash 사전 검색) 의 `KEYWORDS` 추출에 합쳐요. 인터뷰 결과는 `.ax/current-task.json` 의 `intent_notes` 객체에 **축별 key** 로 기록해요 (3.5단계) — 0단계 3축은 `why` / `constraints` / `done`. 다음 skill (spec/spec-tasks/...) 과 4단계 역면접이 같은 의도를 재추론·재질문하지 않아요.

### 절대 금지

- 입력이 짧은데 인터뷰 없이 *default 분류* 로 흘려보냄 → values 자기 합리화 신호 *"이건 너무 사소해서 spec 안 만들어도 돼"* 의 triage 버전
- 한 라운드에 2개 이상 질문 (목적 + 제약 동시 묻기) — 사용자 부담 증가, 답변 품질 저하. **0단계 한정 룰** — 4단계 역면접은 체크리스트 성격이라 별도 상한 (최대 5문) 을 따라요
- 자유 텍스트 강요 (`"어떤 의도세요?"`) — multiple choice 가능한 상황에서 free text 는 사용자에 사고 비용 전가

---

## 1단계 — 빠른 사전 검색 (★ 큰 프로젝트 필수)

LLM 분류 전에 **bash로 후보 자료를 좁혀요**. 큰 프로젝트(>1000 파일)일수록 이게 정확도·속도를 결정해요.

### 1.0 MEMORY.md 먼저 — 빠른 회상 인덱스

검색 전에 `.ax/MEMORY.md` 를 재생성하고 **가장 먼저 읽어요**. 현재 작업·CRITICAL/MANDATORY 룰·모듈·최근 ADR·열린 mistakes·spec 을 한 줄 포인터로 담은 작은 인덱스라, 이걸로 "지금 프로젝트에 뭐가 있는지" 를 토큰 싸게 파악한 뒤 키워드를 더 정확히 뽑아요.

```bash
bash .ax/scripts/bash/build-memory.sh --json   # 재생성. 응답 result.mode 로 full/lean 확인
```

그다음 `.ax/MEMORY.md` 본문을 read. 포인터 중 작업과 관련된 항목만 그 `→ 경로` 의 본문을 추가로 read 해요 (index/detail 분리 — 통째로 다 읽지 않아요). 읽는 법:

- **★ 표시** = 현재 작업 domain 에 걸린 ADR/spec/모듈 — **이걸 먼저** 보고 `→ 경로` 본문만 read.
- **`… +N more → <dir>`** = 섹션 예산(8개) 초과분. 더 필요하면 그 `<dir>` 를 glob.
- **lean 모드** (`result.mode=="lean"` · 작은 프로젝트): 모듈/ADR/spec/mistakes 가 `(N) → <dir>` 한 줄로 접혀 있어요. 인덱스가 오버헤드라 일부러 열거를 생략한 거니, 필요하면 그 dir 를 직접 glob 하세요.

토큰 조절 옵션: `--no-preview`(룰 토큰+경로만)·`--lean`(강제 접기)·`--full`(전체 열거). 자세한 건 `build-memory.sh --help`.

### 1.1 작업 키워드 추출

사용자 메시지에서 명사·도메인 단어를 뽑아 변수로:
```bash
KEYWORDS="payment refund settlement" # 예시 (실제는 LLM이 의역)
```

### 1.2 관련 자료 grep — 5초 안에

`.ax/scripts/bash/triage-search.sh` 가 결정론으로 6 군데 (specs / adrs / mistakes / rules / modules / imported) 한 번에 검색해요.

```bash
.ax/scripts/bash/triage-search.sh --keywords "$KEYWORDS" --json
```

출력 JSON — 각 카테고리는 `score`(매칭 줄 수, 내림차순) + `snippets`(매칭 줄 미리보기) 를 가진 객체 배열:
```json
{
 "status": "ok",
 "result": {
   "specs":    [{"path": ".ax/docs/spec/003-refund-flow", "score": 1, "snippets": []}],
   "adrs":     [{"path": ".ax/docs/adr/0007-refund-window.md", "score": 4,
                 "snippets": ["2:환불(refund) 윈도우 30일.", "3:refund 승인은 ledger 확인."]}],
   "mistakes": [{"path": "...", "score": 2, "snippets": ["..."]}],
   "rules":    [{"path": "CLAUDE.md", "score": 1, "snippets": ["..."]}],
   "modules":  [{"path": ".ax/modules/payment/rules.md", "score": 1, "snippets": [], "match": "refund"}],
   "imported": [{"path": "...", "score": 1, "snippets": ["..."]}]
 },
 "next_step": "N개 자료 매칭 (score 내림차순) — snippet 으로 연관성 먼저 확인하고 필요한 것만 본문 read"
}
```

**snippet-first 읽기 (토큰 효율)**: LLM 은 먼저 `snippets` 만 보고 연관성을 판단해요. 스니펫이 실제로 작업과 관련 있을 때만 그 `path` 전체를 read 해서 *Required reading* 에 첨부 — 매칭됐다고 통째로 다 읽지 않아요. `score` 가 높은 항목부터 봐요.

예외 — 본문을 **반드시** read 해야 하는 경우:
- `modules` 매칭(`.ax/modules/<n>/rules.md`): 모듈 도메인 룰은 작업 진입 시 컨텍스트에 들어가야 효력이 있어요. snippet 이 비어 있어도 본문 포함.
- `mistakes` 매칭: 과거에 같은 함정에 빠진 기록이라 snippet 으로 끝내지 말고 본문 확인 (1.2 말미 규칙).

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
| S | 1~2 파일·한 함수, 한 도메인, 비즈니스 로직 미변경 — 30분 안 |
| M | 한 모듈/도메인 내 신규 기능 — 반나절~2일 |
| L | 2개 이상 모듈/도메인 또는 새 추상화 — 1~3일 |
| XL | 새 도메인 추가·아키텍처 변경·마이그레이션 — 1주 이상 |

> Size 는 **규모만** 재요. "결제라서 L" 같은 위험 혼입 금지 — 도메인 위험은 Risk 축이 담당하고, 섞으면 위험이 두 축에 이중 반영돼 매트릭스가 왜곡돼요. (기준표는 `references/risk-matrix.md` 와 동일 — 수정 시 함께.)

### Risk

도메인 위험도 — L0 (영향 미미, e.g. 로그 포맷·UI 텍스트) / L1 (기본 코드 변경) / L2 (도메인 흐름 영향) / L3 (보안·리스크·데이터 손실 가능).

`.ax/config.yml`의 `domain_risk` 매핑 우선. 없으면 `default_risk` (기본 L1).

### 게이팅 매트릭스 (spec tier 포함)

| Size × Risk | 권장 경로 | spec tier | 게이트 |
|---|---|---|---|
| S × L0~L1 | 즉시 작업 | — (불필요) | hooks만 |
| M × L0~L1 | inline fallback | standard (선택) | hooks + lint |
| M × L2 | spec 권장 | **standard** (spec.md + tasks.md) | spec-validate |
| M × L3 | spec + tasks | **standard** | spec-validate + evaluator |
| L × L0~L2 | spec + tasks | **standard** | spec-validate + evaluator |
| L × L3 / XL × * | spec + tasks + research/data-model/quickstart + contracts + ADR | **full** | spec-validate + ADR + 사람 게이트 |

> tier 는 0.1.16부터 **standard / full 2단계** (basic·plan.md 폐기 — 설계 결정은 ADR 로). 결정론 SSOT 는 `tier-from-state.sh` — 이 표와 스크립트 매트릭스가 어긋나면 스크립트가 맞아요.

**핵심**: triage가 size×risk에 따라 *spec tier 권장*을 함께 출력해요. spec-new는 이 tier 결과를 받아 *필요한 파일만* 생성해요. 처음부터 full 세트를 다 깔지 않음.

## 3단계 — 출력 (조건부 메뉴)

분류 결과가 **매트릭스 코너 케이스**(결정 공간 명확) 면 메뉴 출력 X — 권장 1줄. **모호 영역**(결정 공간 진짜 존재) 만 `[a]/[b]/[c]/[d]` 메뉴.

근거: `.ax/docs/reference/confirmation-policy.md` "메뉴 출력 룰" + `triage-matrix.md` 의 friction column.

### 3.1 매트릭스 코너 케이스 — 메뉴 생략

분류가 다음 중 하나면 *권장만 출력*하고 자동 진행 안내:

| 분류 | 출력 |
|---|---|
| S × L0 | "즉시 작업으로 진행해요. 다른 경로 원하면 말씀." |
| S × L1 | "즉시 + lint 로 진행해요. ADR 필요하면 말씀." |
| L × L3 / XL × L3 | "spec + tasks + ADR 풀 패키지로 진행해요. 축소 원하면 `--tier standard` 명시." |
| 나머지 매트릭스 명백 셀 | 권장 1줄만 |

출력 예 (S × L0):
```
🔬 Triage (입력: "<요약>")

 📍 분류  S × L0 — <도메인> 영향 없음 (<짧은 작업 요약>)
 🎯 권장  즉시 작업으로 진행해요. hooks (lint + 변경 파일 테스트) 만 작동.

 ─ 자동 주입 ─────────────────────────────────────
 spirit  values.md, tone.md
 friction  autopilot (`.ax/docs/reference/confirmation-policy.md` C1)

 ▸ 진행할게요. 다른 경로 원하면 말씀.
```

출력 예 (L × L3):
```
🔬 Triage (입력: "<요약>")

 📍 분류  L × L3 — <도메인> <변경 요약> (다중 모듈)
 🎯 권장  spec + tasks + ADR 풀 패키지. evaluator + architect 게이트.

 ─ 사전 검색 결과 ─────────────────────────────────
 관련 spec .ax/docs/spec/<NNN>-<slug>/
 관련 ADR  .ax/docs/adr/<NNNN>-<slug>.md
 매칭 룰  AX:CRITICAL:<NNN>, AX:MANDATORY:<NNN>

 ─ 자동 주입 ─────────────────────────────────────
 friction  per_task (L3 + <매칭 토큰> → 정책 분기 적용)

 ▸ tier=full 로 spec 만들기 시작할게요. 축소 원하면 `--tier standard` 또는 다른 경로 말씀.
```

### 3.2 모호 영역 — 메뉴 출력

분류가 다음에 해당하면 기존 `[a]/[b]/[c]/[d]` 메뉴 유지:

| 분류 | 이유 |
|---|---|
| M × L2 | tier standard / full 둘 다 정당화 가능 (0.1.16 — basic 폐기) |
| L × L1 ~ L2 | ADR 동반 여부가 진짜 결정 |
| 도메인 다중 매칭 | 어느 도메인 우선인지 사용자 결정 필요 |
| domain_risk 미매핑 (default 적용) | 사용자 확인 필요 |

출력 예 (M × L2):
```
🔬 Triage (입력: "<요약>")

 📍 분류
  Size  M (단일 모듈, 1~2일)
  Risk  L2 (<도메인> 매칭)
  도메인  <도메인>

 🎯 권장 경로  tier=standard (spec + tasks)

 ─ 사전 검색 결과 ─────────────────────────────────
 관련 spec ...
 관련 mistakes ...

 ─ 자동 주입 ─────────────────────────────────────
 friction  phase_gate (Phase 경계에서만 사람 확인)

 ─ 다음 단계 ─────────────────────────────────────

 [a] ✓ tier=standard (권장)
  산출물 spec.md + tasks.md (2 파일, 관련 ADR 별도)
  명령 "새 spec 만들어줘 — <slug> --tier standard"

 [b] tier=full 로 확대 (L≥L3 또는 도메인 위험 시 — ADR 동반)
  산출물 + research/data-model/quickstart + contracts/ + ADR

 [c] 현재 분류 의심 — 재분류

 ▸ 답해주세요 [a] / [b] / [c]
```

### 3.3 절대 금지

- 매트릭스 코너 케이스 (S×L0, L×L3 등 명백) 에 메뉴 의례적 출력 — 결정 공간 없는데 묻는 건 사용자 시간 낭비예요
- 단정 결과 (예: "L3 = 무조건 풀패키지") 를 [a]/[b]/[c]/[d] 형태로 펼치기 — 단정을 메뉴로 위장하면 사용자 신뢰 손실
- 모호 영역 분류 결과를 1줄 권장으로 축약 — 모호 영역엔 진짜 결정 공간이 있으니 사용자 선택지를 가둬선 안 돼요

## Workflow

1. 1단계 (bash 검색) → 후보 자료 5초 안에 좁힘
2. 2단계 (Size × Risk) — config.yml + 키워드 매핑
3. 3단계 (출력 + 옵션 제시) — 사용자가 [a]/[b]/[c] 선택
4. **3.5단계 — current-task.json 작성**
5. **4단계 — 역면접 (spec 경로 셀만)** → 답변을 `intent_notes` 에 병합
6. 분류 오차 발견 시 `.ax/mistakes/` 캡처 → 다음 audit에서 룰 승격 검토

## 3.5단계 — current-task.json 작성 

분류 직후 `.ax/current-task.json`에 작업 컨텍스트를 기록해요. spec/spec-tasks/spec-implement/audit 이 이 파일을 *입력*으로 받음 (LLM 재추론 X).

```bash
TASK_ID=$(date -u +%Y-%m-%d)-$(printf '%03d' $((RANDOM % 1000)))
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
INTENT_JSON='{}'   # 0단계 인터뷰 답변 — 축별 객체 (예: '{"why":"버그 수정 — 환불 실패"}'), 스킵 시 {}

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
 | .phase = "triaged"
 | .intent_notes = ((.intent_notes // {}) + $intent)' \
 --argjson intent "$INTENT_JSON" \
 .ax/current-task.json > .ax/current-task.json.tmp \
 && mv .ax/current-task.json.tmp .ax/current-task.json
```

이후 spec-new가 `.ax/scripts/bash/tier-from-state.sh --json`로 tier 자동 결정.

## 4단계 — 역면접 (Reverse Interview)

> 0단계가 "어느 상자에 넣을지"(분류) 를 물었다면, 4단계는 "만들기 전에 놓친 요구사항" 을 캐요.
> 핵심은 명령을 더 받는 게 아니라 **내가 뭘 모르는지** 를 채우는 것 — 규모·실패 모드·경계·성공 기준은 코드에 없어서 물어야만 알아요.

### 발동 조건

**3단계에서 확정된 경로가 spec 경로일 때만** — 게이팅 매트릭스에서 spec 이 권장되는 셀 (M×L2 이상, L×*, XL×*). spec/spec-implement 진입 직전 **1회**.

| 분류 | 역면접 |
|---|---|
| S×* / M×L0~L1 (즉시·inline) | **스킵** — spec 진입이 없어 과잉질문이에요 |
| M×L2 이상, L, XL (spec 경로) | 발동 — spec 만들기 전 1회 |
| L3 (비가역 영역) | **스킵 금지** — 스킵하면 `.ax/mistakes/` 캡처 대상이에요 |

### 진행 룰

1. **질문 축은 [`references/reverse-interview.md`](references/reverse-interview.md)** — 프로젝트에 `.ax/docs/reference/reverse-interview.md` 가 있으면 그쪽이 우선 (도메인 특화 축).
2. **작업과 관련된 축 3~5개만** 골라요. 한 라운드 최대 5문, multiple choice 우선. (0단계의 "한 라운드 1문" 은 0단계 한정 — 역면접은 체크리스트 성격이라 한 라운드에 묶어 물어요.)
3. **낯선 영역이면 blind-pass 먼저** — 처음 만지는 코드베이스/도메인이면 첫 라운드를 질문이 아니라 정찰로 시작해요. AI 가 자주 깨지는 지점·엣지케이스·기존 유사 구현을 먼저 스캔하고, 그 결과에서 나온 구체적 불확실성만 질문으로 변환. 상세는 references 참조.
4. **중복 방지** — `.ax/current-task.json` 의 `intent_notes` 에 이미 key 가 있는 축은 재질문 금지 (0단계 답변 포함):
   ```bash
   jq -r '.intent_notes // {} | keys[]' .ax/current-task.json   # 이미 답한 축
   ```

### 종료 후 — intent_notes 병합

답변을 축별 key 로 `intent_notes` 에 병합해요 (3.5단계와 같은 jq tmp-mv 패턴):

```bash
jq --argjson intent "$REVERSE_INTERVIEW_JSON" \
 '.intent_notes = ((.intent_notes // {}) + $intent)' \
 .ax/current-task.json > .ax/current-task.json.tmp \
 && mv .ax/current-task.json.tmp .ax/current-task.json
```

spec/spec-tasks 는 이 `intent_notes` 를 입력으로 받아 §3 acceptance criteria 와 §7.5 Technical Context 를 채워요 — 재질문·재추론하지 않아요.

### 절대 금지

- 사용자가 이미 답한 축 재질문 — `intent_notes` 를 안 읽었다는 신호예요
- 한 라운드 5개 초과 질문 — 발굴이 아니라 심문이에요
- **L3 인데 역면접 스킵** — 비가역 영역의 요구사항 누락은 되돌릴 수 없어요. 스킵 발견 시 `.ax/mistakes/` 캡처 대상
- S×L0~L1 에 역면접 강행 — 결정 공간 없는 질문은 사용자 시간 낭비 (3.3 과 같은 원칙)
- 코드를 읽으면 알 수 있는 걸 질문 — 정찰 (blind-pass) 로 스스로 채우고, 질문은 코드에 없는 것 (의도·제약·기준) 만

## 상세

- Size × Risk 매트릭스, 도메인 매칭 키워드: [`references/risk-matrix.md`](references/risk-matrix.md)
- spec 게이팅: `spec-validate` skill
- ADR: `adr` skill / `architect` agent

## 절대 금지

- bash 사전 검색 결과를 무시하고 추측만으로 분류 — 기존 spec/ADR 있는 영역인데 LLM 이 다시 추측하면 일관성 깨져요
- 사전 검색에서 "관련 mistakes 있음" 이 나오면 *반드시* 본문 읽고 분류에 반영 — 안 읽으면 과거에 똑같이 깨졌던 함정에 또 빠져요
- L3 도메인을 spec 없이 즉시 작업 권장 — L3 는 비가역 손실 가능 영역, spec/ADR 없는 진행은 게이팅 우회예요
