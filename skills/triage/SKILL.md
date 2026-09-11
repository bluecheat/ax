---
name: triage
description: "사용자가 새 작업·기능·수정·리팩토링·버그 fix를 요청할 때 가장 먼저 자동 매칭되는 skill. Size × Risk로 30초 안에 분류하고 spirit·룰·페르소나를 자동 주입. 트리거: '구현해줘', '만들어줘', '작업 계획', '어떻게 만들지', '고쳐줘', '추가해줘', '바꿔줘', '리팩토링', '리팩터링', 'fix', '버그', '기능 추가', 'PR 만들어', '작업하자', '/triage', 'classify', 새 대화 첫 메시지에서 작업 의도가 보이면 자동 발동. EnterPlanMode 안에서도 1회 호출 필수."
---

# Triage Skill

> 응급실 트리아지처럼, 들어온 작업을 30초 안에 분류하고 권장 경로를 제시해요.
> 스킬은 **무엇을**(분류·검색·기록·게이팅) 정의하고, **어떻게 물을지**(문장·메뉴 구성)는 모델 판단에 맡겨요.

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 따라요.
**`.ax/spirit/values.md` 또는 `tone.md`가 누락되면 triage 자체가 fail. 작업 시작 자체가 거부됨.**

## 발동 시점

- 사용자가 새 작업을 요청한 첫 메시지
- 사용자가 명시적으로 `/triage <설명>` 호출
- 작업 도중 스코프가 커져서 재분류가 필요할 때
- **`EnterPlanMode` 호출 전·직후 (plan mode 가 triage 를 대체하지 않음)** — plan mode 는 깊은 탐색·승인 게이트, triage 는 분류·spirit 주입. 두 도구가 직교라서 plan mode 안에서도 `Skill goax:triage` 호출 가능·필수. "사용자가 '계획' 단어 썼으니 plan mode 직행" 은 anti-pattern

## 0단계 — 의도 확인 (입력이 짧을수록 더 적극적)

표면 요청(`"PR 만들어"`)과 진짜 의도가 다를 수 있어요. 짐작으로 분류하면 size·risk 가 틀려서 이후 spec/tasks 가 어긋나요 — 짧은 입력을 default 분류로 흘려보내지 않아요.

**확인 발동** (하나라도): 입력이 짧음(단어 < 5) · 동사만 있고 명사/도메인/범위 누락 · 1.3 도메인 매칭 0.
**스킵**: 도메인+동작+범위 셋 다 명시 · 사용자가 "바로 분류해줘" · 직전 `.ax/current-task.json` 에 같은 task 의도 기록됨.

확인 방식은 모델 판단 — 목적(why)/제약(constraints)/성공기준(done) 중 **가장 모호한 한 축만**, multiple choice 로 (`AskUserQuestion` 도구가 있으면 활용). 답변은 축별 key 로 `intent_notes` 에 기록해요 (3.5단계) — 다음 skill 과 4단계 역면접이 재질문하지 않아요.

---

## 1단계 — 빠른 사전 검색 (★ 큰 프로젝트 필수)

LLM 분류 전에 **bash로 후보 자료를 좁혀요**. 큰 프로젝트(>1000 파일)일수록 이게 정확도·속도를 결정해요.

### 1.0 인계 노트 → MEMORY.md — 인계 노트 먼저, 그다음 룰 토큰

검색 전에 두 파일을 순서대로 읽어요. 둘 다 작아요.

**① `.ax/current-task.json` 의 `handoff` — 세션 간 인계 노트.** 결정은 ADR, 진행은 tasks.md, 단계는 current-task.json 의 `phase` 에
있지만 "막힌 것 · 열린 질문 · 이번에 바뀐 공유 이름 · 다음 세션이 처음 할 일" 은 여기에만 있어요. 대화가
압축되면 사라지는 것들이라 파일로 받아요.

```bash
bash .ax/scripts/bash/status-note.sh --show --json   # result.sections.{now,next,open,renamed}
```

- `next` 에 항목이 있고 사용자 요청이 그것과 같으면 → 새 분류 없이 그 작업으로 이어가요 (3.5단계에서 `phase` 유지)
- `open` 에 사용자 결정 대기가 있고 지금 요청이 그 결정에 걸리면 → 0단계 의도 확인에서 **그 질문부터** 물어요
- `renamed` 는 키워드 추출(1.1)에 넣어요 — 옛 이름으로 검색하면 못 찾아요
- `exists:false` 면 그냥 넘어가요 (첫 세션이거나 `zero`·`spec-implement` 가 아직 안 적은 거예요)

**② `.ax/MEMORY.md` — 룰 토큰 인덱스.** 재생성하고 읽어요:

```bash
bash .ax/scripts/bash/build-memory.sh --json   # 재생성. 응답 result.mode 로 full/lean 확인
```

여기서 받는 건 **🔴 CRITICAL / 🟡 MANDATORY 포인터**예요 — 작은 프로젝트(lean 모드)에서도 이건 항상
남아요. 모듈·ADR·spec·mistakes 열거는 본문이 클 때만 펼쳐지고(full), 작으면 `(N) → <dir>` 로 접혀요 —
그땐 dir 를 직접 glob 하는 게 더 싸요. 읽는 법:

- **★ 표시** = 현재 작업 domain 에 걸린 ADR/spec/모듈 — **이걸 먼저** 보고 `→ 경로` 본문만 read.
- **`… +N more → <dir>`** = 섹션 예산(8개) 초과분. 더 필요하면 그 `<dir>` 를 glob.

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

**snippet-first 읽기 (토큰 효율)**: 먼저 `snippets` 만 보고 연관성을 판단해요. 스니펫이 실제로 작업과 관련 있을 때만 그 `path` 전체를 read 해서 *Required reading* 에 첨부 — 매칭됐다고 통째로 다 읽지 않아요. `score` 가 높은 항목부터 봐요.

예외 — 본문을 **반드시** read 해야 하는 경우:
- `modules` 매칭(`.ax/modules/<n>/rules.md`): 모듈 도메인 룰은 작업 진입 시 컨텍스트에 들어가야 효력이 있어요. snippet 이 비어 있어도 본문 포함.
- `mistakes` 매칭: 과거에 같은 함정에 빠진 기록이라 snippet 으로 끝내지 말고 본문 확인.

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
| S × L2 | 즉시 + ADR(짧게) | — (불필요) | hooks + ADR |
| S × L3 | 사람 게이트 + ADR | — (불필요) | 사람 게이트 + ADR |
| M × L0~L1 | inline fallback | standard (선택) | hooks + lint |
| M × L2 | spec 권장 | **standard** (spec.md + tasks.md) | spec-validate |
| M × L3 | spec + tasks | **standard** | spec-validate + evaluator |
| L × L0~L2 | spec + tasks | **standard** | spec-validate + evaluator |
| L × L3 / XL × * | spec + tasks + research/data-model/quickstart + contracts + ADR | **full** | spec-validate + evaluator(필수) + 합의 리뷰(필수, architect·evaluator) + ADR + 사람 게이트 |

> tier 는 **standard / full 2단계** (basic·plan.md 폐기 — 설계 결정은 ADR 로). 결정론 SSOT 는 `tier-from-state.sh` — 이 표와 스크립트 매트릭스가 어긋나면 스크립트가 맞아요.

**핵심**: triage가 size×risk에 따라 *spec tier 권장*을 함께 출력해요. spec 은 이 tier 결과를 받아 *필요한 파일만* 생성해요. 처음부터 full 세트를 다 깔지 않음.

## 3단계 — 출력 (조건부 메뉴)

**결정 공간이 있는 곳에만 물어요.** 근거: `.ax/docs/reference/confirmation-policy.md` "메뉴 출력 룰" + `triage-matrix.md` 의 friction column.

- **매트릭스 코너 케이스** (S×L0, S×L1, L×L3, XL×* 등 결정 공간 명확): 메뉴 없이 분류 + 권장 1줄 + 자동 진행 안내. 단정을 메뉴로 위장하지 않아요.
- **모호 영역** (결정 공간 진짜 존재): 선택지 제시 (`AskUserQuestion` 활용 가능). 모호 영역을 1줄 권장으로 축약해 선택지를 가두지 않아요.

| 모호 영역 | 이유 |
|---|---|
| M × L2 | tier standard / full 둘 다 정당화 가능. `spec-validate` 의 합의 리뷰는 M 에서 **선택**이라 — 켤지도 여기서 같이 물어요 |
| L × L1 ~ L2 | ADR 동반 여부가 진짜 결정 |
| 도메인 다중 매칭 | 어느 도메인 우선인지 사용자 결정 필요 |
| domain_risk 미매핑 (default 적용) | 사용자 확인 필요 |

M×L2 에서 사용자가 합의 리뷰를 켜면 `intent_notes.consensus_review="true"` 로 기록해요 (3.5단계) —
`spec-validate` §2.5 가 `REQ=optional` 일 때 이 값을 읽어 architect·evaluator 리뷰를 자동으로 돌려요.
켜는 주체가 없으면 `--consensus` 는 사용자가 그 단어를 직접 말했을 때만 발동해서 죽은 옵션이 돼요.

출력엔 분류(Size×Risk·도메인)·권장 경로·사전 검색 결과(관련 spec/ADR/mistakes/룰 토큰)·friction 모드를 담아요. 형식 예 (모호 영역):

```
🔬 Triage (입력: "<요약>")

 📍 분류   M × L2 — <도메인> (단일 모듈, 1~2일)
 🎯 권장   tier=standard (spec + tasks)

 사전 검색  관련 spec/ADR/mistakes 경로 + 매칭 룰 토큰
 friction  phase_gate

 [a] tier=standard (권장)  [b] tier=full 확대  [c] 합의 리뷰도 켜기 (architect·evaluator)  [d] 재분류
```

## Workflow

1. 1단계 (bash 검색) → 후보 자료 5초 안에 좁힘
2. 2단계 (Size × Risk) — config.yml + 키워드 매핑
3. 3단계 (출력 + 옵션 제시)
4. **3.5단계 — current-task.json 작성**
5. **4단계 — 역면접 (spec 경로 셀만)** → 답변을 `intent_notes` 에 병합
6. 분류 오차 발견 시 `.ax/mistakes/` 캡처 → 다음 audit에서 룰 승격 검토

## 3.5단계 — current-task.json 작성

분류 직후 `.ax/current-task.json`에 작업 컨텍스트를 기록해요. spec/spec-tasks/spec-implement/audit 이 이 파일을 *입력*으로 받음 (LLM 재추론 X).

```bash
TASK_ID=$(date -u +%Y-%m-%d)-$(printf '%03d' $((RANDOM % 1000)))
INTENT_JSON='{}'   # 0단계 답변 — 축별 객체 (예: '{"why":"버그 수정 — 환불 실패"}'), 스킵 시 {}
                   # M×L2 모호 영역에서 합의 리뷰를 켰으면 '{"consensus_review":"true"}' 도 병합

# update-task.sh 가 락 안에서 in-place 갱신해요 — started_at·updated_at 은 스크립트가 찍고,
# 값 검증(size·risk enum)에 걸리면 아무것도 안 쓰고 exit 1. 인라인 jq 로 쓰지 않아요 (handoff 가 무락에 노출돼요).
bash .ax/scripts/bash/update-task.sh --start --phase triaged \
 --set "task_id=$TASK_ID" --set "description=$DESCRIPTION" \
 --set "size=$SIZE" --set "risk=$RISK" --set "domain=$DOMAIN" \
 --merge-intent "$INTENT_JSON" --json
```

이후 spec 이 `.ax/scripts/bash/tier-from-state.sh --json`로 tier 자동 결정.

## 4단계 — 역면접 (Reverse Interview)

> 0단계가 "어느 상자에 넣을지"(분류) 를 물었다면, 4단계는 "만들기 전에 놓친 요구사항" 을 캐요.
> 규모·실패 모드·경계·성공 기준은 코드에 없어서 물어야만 알아요.

### 발동 조건

| 분류 | 역면접 |
|---|---|
| S/M × L0~L1 (즉시·inline) | **스킵** — spec 진입이 없어 과잉질문이에요 |
| M×L2 이상, L, XL (spec 경로) | 발동 — spec 만들기 전 1회 |
| L3 (모든 Size, 비가역 영역) | **스킵 금지** — Size 불문 발동. 스킵하면 `.ax/mistakes/` 캡처 대상이에요 |

### 진행 룰

1. **질문 축은 [`references/reverse-interview.md`](references/reverse-interview.md)** — 프로젝트에 `.ax/docs/reference/reverse-interview.md` 가 있으면 그쪽이 우선 (도메인 특화 축). 작업과 관련된 축 3~4개, 한 라운드 최대 4문(`AskUserQuestion` 상한), 선택지 2~4개 + multiple choice 우선 — "다른 것" 은 도구가 자동으로 붙여요.
2. **낯선 영역이면 blind-pass 먼저** — 코드를 읽으면 알 수 있는 건 정찰로 스스로 채우고, 질문은 코드에 없는 것(의도·제약·기준)만. 상세는 references 참조.
3. **중복 방지** — `intent_notes` 에 이미 key 가 있는 축은 재질문 금지 (0단계 답변 포함): `jq -r '.intent_notes // {} | keys[]' .ax/current-task.json`

### 종료 후 — intent_notes 병합

```bash
bash .ax/scripts/bash/update-task.sh --merge-intent "$REVERSE_INTERVIEW_JSON" --json   # 기존 키는 새 값이 이겨요
```

spec/spec-tasks 는 이 `intent_notes` 를 입력으로 받아 §3 acceptance criteria 와 §7.5 Technical Context 를 채워요 — 재질문·재추론하지 않아요.

## 상세

- Size × Risk 매트릭스, 도메인 매칭 키워드: [`references/risk-matrix.md`](references/risk-matrix.md)
- spec 게이팅: `spec-validate` skill · ADR: `adr` skill / `architect` agent

## 핵심 불변 (우회 금지)

- **사전 검색 결과를 분류에 반영해요** — 기존 spec/ADR 있는 영역을 추측으로 재분류하면 일관성이 깨져요. mistakes 매칭 시 본문을 읽고 반영해요.
- **L3 는 게이팅을 우회하지 않아요** — spec/ADR 없는 즉시 작업 권장 금지, 역면접 Size 불문 발동.
- **결정 공간에 비례해서 물어요** — 코너 케이스에 의례적 메뉴 금지, 모호 영역에 1줄 축약 금지, 이미 답한 축 재질문 금지.

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- Layer 0 (triage) + 메타데이터

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD·doctor 의 3-way 버전 비교가
이 데이터를 봐요 — triage 가 안 찍으면 `goax_version: null`·`skill_calls: 0` 인 죽은
state 로 남아서 doctor 가 stale 로 오진해요).
```bash
# canonical 갱신 (layer.active, sensors_mode, goax_version, updated_at) — 결정론 스크립트
bash .ax/scripts/bash/update-state.sh

# 메타데이터 (last_skill, skill_calls)만 별도
jq '.last_skill = "triage" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
