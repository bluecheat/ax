# Concepts — goax 설계 사상

> *왜* 이런 프레임워크를 만들었는가, *무엇을* 해결하려 하는가, *어떤* 철학을 따르는가.
> 설치·CLI 같은 *액션* 정보는 [`README.md`](README.md)에 있어요. 본 문서는 *왜·무엇·어떻게*만 다뤄요.

---

## Abstract

같은 모델로 같은 작업을 시켜도 결과가 매번 달라요. 사람들은 흔히 이걸 "모델이 부족해서"라고 진단해요. **goax의 진단은 다릅니다 — 모델이 아니라 *환경*이 문제예요.** AI 에이전트는 단독으로 일하지 않아요. 보는 룰, 받는 컨텍스트, 거치는 검증, 누적된 실수의 학습 — 이 **하네스(Harness)** 전체가 결과를 결정해요.

goax는 그 하네스를 **4계층(Layer 0~3) + 2 Cross-cut(Spirit · Mistake Loop)** 구조로 명시화한 프레임워크예요. 어떤 프로젝트에든 1분 안에 동일한 환경을 깔아주고, 결정론적인 부분은 스크립트가, 판단·인터랙션은 LLM이 담당하도록 책임을 분리해요. **AI 에이전트의 결과 일관성을 *환경 엔지니어링*으로 통제한다** — 이게 한 줄 명제예요.

---

## 1. Problem Statement — 무엇이 문제인가

### 1.1 결과 일관성의 결손

같은 사용자가 같은 코드베이스에서 같은 모델에게 같은 요청을 보내도, 결과는 매번 다른 모양이 돼요:

- 어떤 응답은 룰을 잘 따르고, 어떤 응답은 무시해요
- 어떤 작업은 spec을 먼저 쓰고, 어떤 작업은 바로 코드를 짜요
- 같은 실수를 다른 PR에서 반복해요
- 코드 리뷰 코멘트가 같은 패턴으로 누적돼요

이건 모델의 *능력 부족*이 아니라 **환경의 *통제 부족***이에요. 매번 다른 룰이 매번 다른 순서로 컨텍스트에 들어가면, 같은 모델이라도 다른 답을 내요.

### 1.2 잘못된 진단 — "프롬프트 엔지니어링"

흔한 처방은 "프롬프트를 더 잘 쓰기"예요. 그런데 이건 한 *세션* 단위 처방이에요:

- 다음 세션에선 다시 0부터 시작
- 팀이 공유하지 못함 (개인 노하우)
- 프로젝트가 자라도 룰이 누적되지 않음
- "잘 짜인 프롬프트" 자체가 사람 리뷰 병목

프롬프트는 *단발성 입력*이고, 우리가 필요한 건 *영속하는 환경*이에요.

### 1.3 또 다른 잘못된 진단 — "더 큰 모델" (그리고 절반의 진실)

"더 큰 모델 쓰면 해결" 가설은 **절반만** 맞아요. frontier 모델은 환경의 한 부분 — *행동 지시(Guides)* — 를 실제로 흡수했어요. Claude Code 팀이 신형 frontier 모델 출시에 맞춰 자사 시스템 프롬프트의 약 80%를 삭제했고 성능이 오히려 유지·개선된 것이 대표 사례예요. 구세대 모델의 결함을 교정하던 지시가 신세대 모델엔 족쇄가 돼요.

하지만 모델이 흡수하지 **못하는** 것이 남아요:

- **검증(Sensors)** — 모델이 좋아져도 "룰을 따랐는지"의 증명은 결정론이 담당해요. 파괴 명령 차단·룰 grep·secrets 검사는 프롬프트가 아니라 hook 이어야 우회가 안 돼요
- **프로젝트 고유 지식** — 도메인 위험도, 결정 근거(ADR), 이 팀이 실제로 깨졌던 함정(mistakes)은 어떤 모델의 사전학습에도 없어요
- **축적(Loop)** — 실수를 코드가 아니라 환경에 반영하는 사이클은 모델 밖의 구조예요

> 정련된 명제: **환경 엔지니어링의 무게중심은 모델 세대에 따라 Guides → Sensors + Loop 로 이동해요.** 행동 지시는 모델 릴리즈마다 재베이스라인(지우고, 실패가 관찰될 때만 ablation 으로 복원)하고, 투자는 결정론과 프로젝트 지식에 집중해요. goax 의 `model_tier` (config.yml) 가 이 분기를 담당해요.

### 1.4 해결 가설

> AI 에이전트의 결과 일관성은 **환경 통제 깊이**의 함수예요.
> 같은 모델 + 잘 통제된 환경 > 더 큰 모델 + 통제 안 된 환경.

goax는 이 가설을 **하네스 구조화**로 검증하려는 프레임워크예요.

---

## 2. Harness — 이론적 토대

### 2.1 정의

**Agent = Model + Harness**

- **Model**: 두뇌. 우리는 못 바꿔요. (상수)
- **Harness**: 환경. 우리가 통제하는 모든 것. (변수)

Harness를 더 분해하면:

**Harness = Guides + Sensors + Loop**

| 컴포넌트 | 시점 | 역할 |
|---|---|---|
| **Guides** | 작업 *전* | 룰·컨벤션·페르소나·도메인 정의를 컨텍스트에 주입 |
| **Sensors** | 작업 *후* | 결과 검증 — lint, type, 의존성, 룰 위반 탐지 |
| **Loop** | 검증 *후* | 발견된 실수를 *코드*가 아니라 *환경*에 반영해 다음 사이클에서 차단 |

### 2.2 왜 이 3분해인가

- **Guides 없이**는 매번 추측에서 시작 → 일관성 0
- **Sensors 없이**는 룰을 줘도 따랐는지 검증 못함 → 룰이 장식
- **Loop 없이**는 같은 실수가 무한 반복 → 환경이 진화 안 함

세 컴포넌트는 **닫힌 사이클**이에요. 어느 하나 빠지면 나머지가 무력화돼요.

### 2.3 기존 접근의 위치

| 접근 | Guides | Sensors | Loop |
|---|---|---|---|
| 프롬프트 엔지니어링 | ◐ (단발) | ✗ | ✗ |
| Fine-tuning | ◐ (모델 안에 박힘 — 갱신 어려움) | ✗ | ✗ |
| Linter / CI | ✗ | ◯ | ✗ |
| 코드 리뷰 | ✗ | ◯ (사람) | ◐ (구두) |
| **goax** | ◯ | ◯ | ◯ |

기존 도구들은 *부분 솔루션*이에요. goax는 셋을 *통합한 환경 엔지니어링 프레임워크*예요.

---

## 3. 4-Layer Architecture — 왜 4개인가

### 3.1 분해 원칙

룰을 한 곳에 다 쌓으면:
- 컨텍스트 윈도우 폭주 (모노레포에서 10MB+)
- 어느 룰이 *비협상*인지 *권장*인지 모호
- 모듈별 룰과 전역 룰이 섞여서 검색 어려움
- 결정 근거가 룰과 분리 안 되어 "왜?"에 답 못함

이를 해결하려면 **통제 강도**와 **스코프**를 축으로 나눠야 해요. goax는 4축으로 분해했어요.

### 3.2 Layer 0 — Triage (작업 진입 분류)

**무엇**: 작업이 들어올 때 *Size × Risk*로 30초 안에 분류 + 권장 경로 결정.

**왜 필요한가**: 한 줄 수정과 P0 리팩토링이 같은 진입점을 가지면 안 돼요. 작은 일에 큰 컨텍스트는 토큰 낭비, 큰 일에 작은 컨텍스트는 사고. 진입점에서 30초 만에 라우팅해야 해요.

**구현**: `triage` skill — 사용자 메시지에서 도메인 키워드 추출 → `.ax/config.yml` 매핑 → tier 권장 → spirit·룰·페르소나 자동 주입.

### 3.3 Layer 1 — Constitution (비협상 룰)

**무엇**: 프로젝트의 비협상 룰 3~5개. CRITICAL 위주.

**왜 필요한가**: 비협상 룰이 명시되지 않으면 같은 실수가 다른 PR에서 반복돼요. CRITICAL은 자동 차단 가능한 형태로 짧고 검출 가능하게 박아둬야 해요. 길게 늘어놓으면 안 외워지고 무시당해요.

**구현**: `CLAUDE.md` (root) — 얇음. 인덱스 + 핵심 CRITICAL만. 나머지는 Spirit으로 위임.

### 3.4 Layer 2 — Module Rules (스코프 룰)

**무엇**: 모노레포 모듈별 sub-CLAUDE.md.

**왜 필요한가**: 모노레포에서 root CLAUDE.md 한 파일에 모든 모듈 룰이 몰리면 비대해지고 컨텍스트 낭비. 모듈 안에서만 결정되는 룰은 그 모듈의 sub-CLAUDE.md에 두면 작업 시 *필요한 룰만* 컨텍스트에 들어와요.

**구현**: `.ax/modules/<name>/rules.md` — keywords frontmatter 로 triage 가 자동 grep 매칭해요. (모듈 자체 `<module>/CLAUDE.md` 를 병행 컨벤션으로 둘 수도 있지만, goax 가 깔아주는 메커니즘은 `.ax/modules/<name>/rules.md` 예요.)

### 3.5 Layer 3 — Spec / ADR (결정 근거 + 도메인 정의)

**무엇**: 결정 근거(ADR) + 거부된 대안 + 도메인 정의(Spec).

**왜 필요한가**:
- ADR이 없으면 *거부된 대안*이 사라져서 미래의 AI나 새 팀원이 그 대안을 다시 제안해요. 같은 토론을 반복해요.
- Spec이 없으면 "X는 무엇인가"를 코드에서 역공학해야 해요. 사람도 AI도 비효율.

**구현**: `.ax/docs/adr/NNNN-*.md` (결정) + `.ax/docs/spec/NNN-<name>/` (SDD 워크플로우 디렉토리). `NEEDS CLARIFICATION` 마커로 게이팅.

### 3.6 왜 4개인가 (3개나 5개로는 왜 안 되는가)

- **Layer 0(triage)이 빠지면**: 모든 작업이 동일 진입점 → 작은 일에도 큰 컨텍스트 로드 → 토큰 낭비 + 사용자 피로
- **Layer 1(Constitution)이 빠지면**: 프로젝트 전역 비협상 룰 자리가 없음 → CRITICAL이 다른 룰과 섞여 무시당함
- **Layer 2(Module)가 빠지면**: 모노레포에서 모든 룰이 root에 → 컨텍스트 폭주
- **Layer 3(Spec/ADR)이 빠지면**: 결정 근거 휘발 → 같은 토론 반복

각 layer는 *다른 통제 강도*와 *다른 스코프*를 담당해요. 합치거나 빼면 책임 충돌이 생겨요.

> 솔직히 말하면: **Layer 0(triage)는 엄밀히 "계층"이라기보단 "디스패처"**예요. 다른 layer가 정보를 *저장*하는 데 비해 triage는 정보를 *분류*하니까요. 그래도 "4계층"이라는 명명은 진입 시점의 명시적 단계를 강조하기 위한 의도적 선택이에요.

---

## 4. Cross-cutting Layers — 왜 따로인가

4계층은 정적이에요. 살아있는 환경엔 *횡단하는* 두 축이 더 필요해요.

### 4.1 Spirit — 행동 정체성

**무엇**: 모든 sub-agent가 공유하는 *태도·문화·일하는 방식*.

**왜 필요한가**: 페르소나가 늘어날수록 톤·휴리스틱이 분기돼요. `code-reviewer`는 단호한데 `engineer-generalist`는 상냥하면 같은 PR에서 인격 분열. 모든 sub-agent에 *공통 태도*를 자동 주입하면 결과물이 한 팀에서 나온 것처럼 보여요.

#### 4.1.1 철학 — Spirit이 *문화의 인격화*인 이유

사람 팀에선 "팀 문화"가 글로 쓰여 있지 않아도 모두가 공유해요. 새 팀원이 한 달이면 흡수해요. AI 팀엔 그게 자동으로 안 일어나요. 매 sub-agent가 매번 처음 들어오는 신입처럼 행동해요.

Spirit은 그 **흡수 과정을 명시화**해요:
- `values.md` — 가치관 (작은 단위, 안전 우선, 팀 고유 가치 — lean 기본; frontier 모델 기본 행동과 중복되는 항목은 `_templates/spirit/behavioral-baseline.md` opt-in)
- `tone.md` — 어체 (`~해요` 체)
- `rules/<카테고리>.md` — 카테고리별 휴리스틱

매 skill이 시작 전 이 파일들을 명시 로드해요. 결과적으로 *모든 sub-agent가 같은 인격을 공유*해요.

#### 4.1.2 왜 Persona와 분리하나

| | Persona | Spirit |
|---|---|---|
| 단위 | 한 역할 (code-reviewer, payment-engineer) | 모든 역할 공통 |
| 빈도 | 작업 종류 따라 다름 | 항상 |
| 변화 | 도메인 추가 시 늘어남 | 거의 안 바뀜 |
| 본질 | *무엇*을 하는가 | *어떻게* 하는가 |

Persona가 *역할*이라면 Spirit은 *인격*이에요. 역할이 바뀌어도 인격은 같아야 해요.

### 4.2 Mistake Loop — 학습 사이클

**무엇**: 실수 발견 시 *코드*가 아니라 *하네스*를 고치는 사이클. 캡처 → 심사 → 룰 승격.

**왜 필요한가**: 같은 실수가 다른 PR에서 반복되는 건 시스템 결함이지 사람 잘못이 아니에요. 코드만 고치면 한 번이지만 환경(룰·sensor)을 고치면 영구적이에요.

#### 4.2.1 핵심 원칙

> **agent가 실패하면 코드를 고치지 않고 환경을 고친다.**

흔한 반사작용은 "이번엔 코드를 고쳤으니 됐다"예요. 그런데 다음 PR, 다음 사람, 다음 모델이 같은 실수를 반복해요. 진짜 해결은:

1. **캡처**: `.ax/mistakes/YYYY-MM-DD-NNN-*.md`에 사례 기록
2. **심사**: 주기적 audit으로 카테고리 분포 + 빈도 조사
3. **승격**: N회 이상 반복된 카테고리 → CLAUDE.md / spirit/rules / Sensor 패턴으로 추가

#### 4.2.2 한계 — 자기참조 위험

이 루프는 **LLM이 만든 룰을 LLM이 따르고 LLM이 위반을 감지**하는 자기참조 구조예요. 객관성을 어떻게 확보할까요?

- 결정론적 sensor(bash hooks)가 가능한 한 많은 검증을 담당 → LLM 판단 의존 줄임
- Generator/Evaluator 분리(§5.3)로 self-praise bias 제거
- 사람이 audit 결과를 *최종 승인*해야 룰 승격 (자동 승격 X)

완전한 객관성은 불가능. 그래도 *명시화된 닫힌 루프*가 *암묵적 무한 반복*보다 나아요.

---

## 5. Engineering Principles — 구체적 설계 결정

### 5.1 Critical Signal — 시그널 포맷

룰을 모두 같은 무게로 적으면 AI가 어느 게 정말 중요한지 몰라요. 3등급 시그널:

```
🔴 CRITICAL    자동 차단 (Sensors가 막음, 우회 불가)
🟡 MANDATORY   사람 게이트 (명시적 승인 필요)
🔵 CONVENTION  가이드 (권장, 차단 X)
```

이렇게 나누면 자동 차단 / 사람 승인 / 단순 안내를 명확히 구분할 수 있어요. *시각*과 *기계 검출* 모두 가능해야 한다는 게 핵심.

### 5.2 Rules Tokens — 식별 가능한 룰 ID

모노레포에서 룰이 root + 모듈별 + spirit에 분산돼요. "결제 도메인 CRITICAL만"같은 1초 쿼리는 표준 토큰 없이는 불가능. 토큰을 박아두면 사람과 grep 둘 다 빨라져요.

```
Constitution:  <scope>:<LEVEL>:<id>     (예: AX:CRITICAL:001, payment:MANDATORY:003)
Spirit:        SP-<CATEGORY>-<id>       (예: SP-SEC-001)
```

### 5.3 Generator / Evaluator 분리

**문제**: 같은 세션에서 자기 결과를 평가하면 "잘 됐어요"라고 답하는 self-praise bias가 있어요.

**해결**: 코드를 *쓰는* 세션과 *비평하는* 세션을 분리해요.

- Generator: 메인 persona (engineer-generalist, refactorer 등)
- Evaluator: 별도 sub-agent (`agents/evaluator.md`) — docs/spec/ADR만 보고 비평

**어디서 성립하나**: `spec-implement` §8 이 task 0건 남은 시점에 evaluator 를 새 컨텍스트로 띄우고
(대화를 넘기지 않고 spec·ADR·diff 만), evaluator 가 `<spec>/review.md` 첫 줄에 `verdict:` 를 직접
써요. `tasks-gate.sh` G6 이 그 줄을 읽어 완료를 판정해요 — size L 이상 · M×L3 은 필수. 평가 기록을
구현 세션이 쓰지 않는 것, 그게 분리의 실체예요. 같은 이유로 병렬 레인의 완료도 레인의 자기보고가
아니라 코디네이터가 원장(`lanes-dispatch.sh`)에 `보고:` 를 찍고 검증 명령을 다시 돌린 뒤예요 (G5).

같은 분리가 **계획 시점**에도 있어요 — `spec-validate` 가 명료성 게이트를 통과한 spec 에 대해 architect → evaluator 를
새 컨텍스트로 **순차·독립**(서로 파일을 안 봄)으로 띄우고, 각자 `review-spec.<역할>.md` 첫 줄에 `verdict:` 와 sha 를 써요.
`spec-review.sh` 가 둘을 집계해요 — size L/XL 필수, M 선택. OMC ralplan 의 구조에 파일 verdict 와 결정적 사전 게이트를 얹은 거예요.

### 5.4 SDD — Spec-Driven Development

**왜**: 코드는 *어떻게*를 말하지만 *무엇*과 *왜*를 말하지 않아요. Spec과 ADR이 그 자리를 채워요.

**산출물 (tier-aware)**:
- `spec.md` — What/Why + 수용 기준 + Technical Context (§7.5 — 스택·영향 모듈·적용 룰·진입 ADR). NEEDS CLARIFICATION 마커로 모호함 표시.
- `tasks.md` — dependency-ordered 체크리스트 (`[P]` 병렬 마커). spec 의 acceptance 와 1:1 매핑.
- `research/data-model/quickstart/contracts` — full tier 부가 산출물.
- ADR (`.ax/docs/adr/NNNN-*.md`) — 설계 결정·트레이드오프·거부된 대안 기록 (full tier 정규).

**SSOT 원칙**: spec.md 가 단일 진실. tasks 가 spec 을 *입력*으로 받음. 설계 결정의 *근거* 는 ADR 이 단독 소유 (plan.md 는 폐기됐어요).
**게이팅**: NEEDS CLARIFICATION · placeholder `<...>` · 빈 필수 섹션 어느 하나라도 남으면 다음 단계 차단 (`check-spec-clarity.sh`).

### 5.5 Tier-aware Spec — Over-engineering 방지

**문제**: 한 줄 수정에 spec / tasks / research / data-model / contracts / quickstart 다 만들면 의식(ritual) 이 돼요.

**해결**: triage 결과(size × risk)로 *딱 필요한 만큼* — 2 단계로 슬림화:

| Tier | 산출물 | 적용 |
|---|---|---|
| standard | spec.md + tasks.md (2) | S/M/L × L0~L2 |
| full | + research/data-model/quickstart + contracts/ + ADR | L × L3 / XL |

빠른 길과 점진 길 둘 다 제공:
- **빠른**: `/spec --tier full` (한 명령)
- **점진**: `--tier standard` → 필요시 `add-spec-files.sh --add research,data-model,...` → ADR 별도

### 5.6 Scripts vs LLM — 결정론과 판단의 분리

**문제**: SKILL.md에 bash 인라인 코드를 박으면 LLM이 매번 재해석해요. 같은 작업이 매번 다르게 실행될 위험.

**해결**: 결정론적인 부분(파일 생성·번호·sha·검색·정규화)을 `.ax/scripts/bash/`로 분리. SKILL.md는 thin wrapper:

```bash
# 옛날: SKILL.md 본문에 bash 인라인 (LLM이 매번 재해석)
NEXT=$(ls .ax/docs/spec/[0-9][0-9][0-9]-* | sed 's|.*/||' | awk -F- '{print $1}' | sort -n | tail -1)
NEXT=$(printf "%03d" $((10#${NEXT:-0} + 1)))

# 지금: 스크립트 위임 (결정론 보장)
NEXT=$(bash .ax/scripts/bash/next-spec-num.sh --json | jq -r '.result.next')
```

스크립트 표준:
- `--json --dry-run --help` 옵션
- stderr `[goax]` prefix
- exit code: 0 ok, 1 error, 2 skipped (graceful degradation)

이 분리는 spec-kit의 디자인 패턴에서 영감을 받았어요. **결정론은 스크립트가, 판단은 LLM이.**

### 5.7 Confirmation Friction Policy — 사람 확인은 데이터로 결정

**문제**: 4계층 권한 위임 모델에서 상위 단계(triage → spec-validate → spec-tasks)가 게이트를 통과시키면 그 결정은 *계약*. 그런데 implement 단계에서 task 단위로 [y/n] 을 반복 묻는 건 같은 결정을 N회 재개봉하는 *double-gate*. 이는 SSOT 원칙(§5.4) 과 권한 위임 모델 둘 다 위반해요.

동시에 무조건 자동 진행도 답이 아니에요. spec / ADR 작성 시점에 모르던 결정이 implement 시점에 발생할 수 있고(설계 이탈·task 간 의존 깨짐·도메인 위험 무감각), 메뉴 출력은 *결정 공간 명시화* 의 가치가 있어요.

**해결**: confirmation 강도를 *데이터 함수* 로 결정해요. 무차별 묻기·무차별 자동 둘 다 anti-pattern.

5개 결정 변수(이미 goax 안에 존재):

| 변수 | 출처 | 역할 |
|---|---|---|
| size × risk | triage 분류 | 1차 friction 강도 |
| spec_tier | standard / full | tier 가 size×risk 흡수 |
| sensors.mode | warning / fail | hooks 차단 강도 → LLM 추가 확인 redundancy |
| mistake recurrence | 같은 카테고리 누적 | 동적 강화 신호 |
| Spirit 매칭 | SP-SEC-* / SP-DATA-* | 위험 카테고리 식별 |

이 변수들로 5개 Decision Rules(C1~C5) 를 구성. 자세한 의사결정 매트릭스는 `.ax/docs/reference/confirmation-policy.md`.

**핵심 원칙 3가지**:

1. **Phase Boundary Gate** — 사람 확인은 phase 전환점(triage → spec, spec → tasks, Phase 1 → Phase 2)에서만. phase 내 진행은 Spirit + Sensors 가 통제. 같은 layer 내 반복 게이트는 계층 설계 위반.
2. **Signal-Grade Proportionality** — 확인 강도는 시그널 등급에 비례. CRITICAL 접촉 task 만 halt, MANDATORY 는 phase 경계에서, CONVENTION 은 자동 진행. 3등급 시그널 체계(§5.1) 를 implement 단계에도 적용.
3. **Mistake-as-Signal** — confirmation 을 줄이면 LLM 판단 오류가 mistakes 에 누적되고, 이게 환경 강화로 이어져요. "환경을 고친다"(§4.2) 의 자연스런 귀결. confirmation 의 *사전 차단* 과 Mistake Loop 의 *사후 교정* 은 역할 분담.

**왜 외부 도구 패턴(Aider --yes, Cursor YOLO) 을 그대로 가져오면 안 되는가**: 그 도구들은 *zero-governance + 단일 세션* 컨텍스트. goax 는 *4계층 + 2 cross-cut 거버넌스* 를 깔아주는 컨텍스트. 두 컨텍스트의 confirmation 의미가 다르므로 패턴만 복사하면 mismatch. **goax 의 답은 "묻기 vs 자동" 이분법이 아니라 "어떤 데이터에 근거해 어느 강도로 묻는가"**.

**보호장치 (critic 입장 흡수)**:
- Default = `phase_gate` (supervised). `autopilot` 은 사용자가 의식적으로 선언해야 발동.
- L3 도메인은 mode 불문 task 게이트 강제 (`l3_override`).
- Phase 경계 confirmation 은 *형식적 [y/n] 이 아닌* 의사결정 컨텍스트 (이전 결과 + 다음 파일 + 룰 delta) 출력.

---

## 6. Brownfield Adoption — 점진 도입의 어려움

### 6.1 문제

빈 프로젝트에 goax를 까는 건 쉬워요. 어려운 건 **이미 운영 중인 모노레포에 충돌 없이 점진 도입**하는 것:

- 첫날부터 fail 모드로 모든 PR을 막으면 팀 반발 → 도입 자체 실패
- 기존 자산(CLAUDE.md, 외부 spec, hooks, AI 리뷰 도구) 무시하면 중복
- 도메인 위험도를 추측만으로 박으면 잘못된 게이팅

### 6.2 해결 — LLM에 위임

기존엔 bash 휴리스틱(정규식 도메인 추정, Q1~Q4 인터랙티브)을 시도했지만, 모듈 의존을 못 읽고 도메인 noise(`ad`, `ba` 같은 짧은 prefix)만 만들어요.

지금은 **onboarding skill**이 코드를 직접 읽고 사용자와 대화하며 진행해요:
1. 모듈 구조·도메인을 LLM이 코드 직접 확인
2. 도메인 위험도(L0~L3) 사용자와 함께 매핑
3. CLAUDE.md 룰을 카테고리로 분류
4. 외부 spec 흡수 여부 결정
5. 4계층 활성화 + 첫 ADR 자동 작성

**원칙**: 첫날은 `mode: warning` (경고만), 데이터 모인 후 카테고리별로 `fail`로 점진 승격.

---

## 7. Anti-patterns & Limitations

### 7.1 Out of Scope

- **모델 fine-tuning** — goax는 사용 모델에 무관
- **prompt engineering 기법** — goax는 *환경 엔지니어링*, 프롬프트 자체는 다루지 않아요
- **agent 오케스트레이션 엔진** — task-machine, swarm 같은 건 별도 도구 (예: omc)
- **CI/CD 자체** — hooks·sensors는 GitHub Actions 등과 통합 가능하지만 goax가 직접 CI 시스템은 아님

### 7.2 흔한 함정

| 함정 | 결과 |
|---|---|
| 첫날부터 fail 모드로 PR 차단 | 팀 반발 → 도입 실패 |
| 도메인 위험도 추측 박기 | 잘못된 게이팅 → 신뢰 손상 |
| 외부 spec 무리한 흡수 | 다른 팀 워크플로우 깨짐 |
| 모든 mistake를 1회만 보고 즉시 CRITICAL 승격 | 룰 인플레이션 → CLAUDE.md 비대화 |

### 7.3 인정하는 한계

- **행동 스캐폴딩의 감가상각** — 행동 지시(가치·의례·절차 스크립트)는 모델 세대가 오를수록 기본값과 중복되고, 중복 지시는 호출마다 토큰 비용 + 상충 위험이에요. goax 는 lean 을 기본으로 하고(`model_tier: frontier`), 지시 복원은 재발 관찰 + 항목 단위 ablation 으로만 해요. 이 감가상각은 Sensors·Loop 엔 적용되지 않아요 — 결정론은 모델과 무관하게 유효해요.
- **Spirit의 자동 주입**은 LLM이 SKILL.md 본문을 *읽고 자발적으로* values.md를 여는 데 의존해요. deterministic injection은 후속 과제.
- **Mistake Loop의 객관성**은 사람 audit 승인에 의존해요. 자동화 한계 명시.
- **단일 OS** — bash hooks/scripts라 Linux/macOS만. Windows는 미지원.
- **한국어 ~해요 체** — 사용자 풀 제한 요인이지만, *일관된 인격* 유지를 위한 의도적 선택.

---

## 8. Comparison with Related Work

| 도구 | 위치 | goax와의 차이 |
|---|---|---|
| **prompt engineering** 기법서 | 단발성 입력 최적화 | goax는 영속하는 환경 엔지니어링 |
| **CLAUDE.md** (Claude Code 표준) | 단일 root 룰 파일 | goax는 4계층 + Cross-cut으로 구조화 |
| **speckit** (GitHub) | SDD 명령 분리 (specify/plan/tasks/implement) + scripts 분리 | goax도 명령 분리 채택 (점진 길) + tier-aware로 over-engineering 방지 |
| **BMad-Method** | Persona / Rules / Workflow / Artifacts 4층 | 분류 축이 다름 (역할 기반 vs 통제 강도 기반) |
| **omc** (oh-my-claudecode) | 실행 엔진 (autopilot/ultrawork/team) | goax는 실행 *전 환경 세팅*. 보완재 |
| **Linter / CI** | 결정론 검증만 | goax는 Guides + Sensors + Loop 통합 |

goax의 *고유 기여*는 두 가지예요:
1. **Mistake Loop** — "코드 대신 환경을 고친다"는 명시적 피드백 사이클 (다른 도구에 없음)
2. **Spirit Cross-cut** — 모든 sub-agent의 인격 통합 (분산된 persona의 톤 분기 해결)

---

## 9. 한 줄로 요약하면

> **어떤 프로젝트든 1분 안에 4계층 하네스(Triage / Constitution / Module / Spec) + 2 cross-cut(Spirit / Mistake Loop)을 깔아주는 Claude Code Plugin. AI 에이전트의 결과 일관성을 *환경*으로 통제해요.**

---

## 10. 더 읽기

- [`README.md`](README.md) — 설치·명령·디렉토리 트리 (액션 정보)
- [`docs/sdd.md`](docs/sdd.md) — Spec-Driven Development 상세
- [`docs/spirit.md`](docs/spirit.md) — Spirit 운영 가이드
- [`docs/skill-routing.md`](docs/skill-routing.md) — skill 라우팅 매트릭스
- [`docs/up.md`](docs/up.md) — Brownfield 도입 흐름
- [`changelog/0.1.0.md`](changelog/0.1.0.md) "Design decisions" 섹션 — 결정 기록·거부된 대안 (옛 docs/adr/ 통합)
- [`templates/default/.ax/scripts/bash/README.md`](templates/default/.ax/scripts/bash/README.md) — 결정론 도구 19개 표준
