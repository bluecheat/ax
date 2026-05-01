# Concepts — goax의 핵심 개념 사전

> 이 프로젝트는 *AI 에이전트 하네스(harness)*를 위한 작은 프레임워크예요.
> 처음 보는 사람이 5분 안에 "goax가 무엇을 다루는가"를 파악할 수 있도록 핵심 개념을 모았어요.

---

## 0. 한 줄 요약

> **AI 결과 품질 차이는 Model이 아니라 Harness에서 나온다.**
> goax는 그 Harness를 *Guides + Sensors + Loop*로 구조화한 4계층 프레임워크예요.

```
Agent  =  Model(두뇌)  +  Harness(환경)
Harness =  Guides(사전 지시)  +  Sensors(사후 검증)  +  Loop(피드백→하네스 갱신)
```

---

## 1. 4계층 모델 (한 화면)

```
┌──────────────────────────────────────────────────────────┐
│ Layer 0  Triage         /triage 진입 시 Size×Risk 라우팅   │
├──────────────────────────────────────────────────────────┤
│ Layer 1  Constitution    CLAUDE.md — 비협상 룰 (3~5개)     │
├──────────────────────────────────────────────────────────┤
│ Layer 2  Module Rules    <module>/CLAUDE.md — 도메인별 룰 │
├──────────────────────────────────────────────────────────┤
│ Layer 3  Spec / ADR     docs/adr/, spec/                │
└──────────────────────────────────────────────────────────┘
                              ▲
        ┌─────────────────────┴───────────────────────┐
        │ Cross-cut  Mistake Loop                      │
        │  Sensors → mistakes/ → /steering-audit       │
        └─────────────────────────────────────────────┘
                              ▲
        ┌─────────────────────┴───────────────────────┐
        │ Cross-cut  Spirit                            │
        │  .ax/spirit/{values, tone, rules}            │
        │  → 모든 sub-agent의 톤·태도·휴리스틱 공유        │
        └─────────────────────────────────────────────┘
```

자세히: [`docs/concepts.md`](docs/concepts.md)

---

## 2. 14개 핵심 개념 — 빠른 카드

각 개념: **무엇 / 왜 필요한가 / goax에서 어떻게 / 더 자세히**.

### 2.1 Harness (하네스)

- **무엇**: 모델 능력을 결과로 변환하는 환경 — `Guides + Sensors + Loop`
- **왜 필요한가**: 같은 모델이라도 환경(어떤 룰을 보고, 어떤 검증을 거치고, 어떤 실수가 차단되는가)에 따라 결과 품질이 크게 달라져요. 환경을 통제하지 않으면 매번 결과가 들쭉날쭉하고 사람 리뷰가 병목이 돼요
- **goax**: 4계층 + Spirit + Mistake Loop 통합 골격
- **더**: [`docs/concepts.md`](docs/concepts.md)

### 2.2 Guides (사전 지시)

- **무엇**: 작업 *전* 에이전트가 받는 룰·컨벤션·페르소나
- **왜 필요한가**: 작업이 시작된 *후*에 룰을 알려주면 늦어요. 변경이 다 끝난 PR을 거절당하면 비용이 큼. 시작 *전*에 적용 가능한 룰·컨벤션·페르소나를 컨텍스트에 주입해야 해요
- **goax**: `CLAUDE.md`(Layer 1) + `<module>/CLAUDE.md`(Layer 2) + `.claude/skills/personas/<role>/SKILL.md` + `.ax/spirit/`
- **더**: [`docs/concepts.md`](docs/concepts.md)

### 2.3 Sensors (사후 검증)

- **무엇**: 작업 *후* 결과 검증 — 4종류 (Computational / Inferential / Structural / Functional)
- **왜 필요한가**: 사람 리뷰는 시간이 걸리고 누락도 많아요. lint·typecheck 같은 결정론적 검증, 모듈 의존 위반 같은 구조적 검증, "엣지 케이스 누락" 같은 인페런셜 검증을 자동으로 돌리면 같은 실수가 반복되지 않아요
- **goax**:
  - Computational: `.ax/hooks/{pre-bash, pre-edit, post-edit, pre-commit}` — 결정론적
  - Inferential: `.claude/agents/architect.md`, `.claude/agents/evaluator.md` — AI-led
  - Structural: 자기 프로젝트의 의존 분석 스크립트(예: `circular_analysis.py`)를 hooks에 연결
  - Functional: TDD 강제 (자기 프로젝트로 확장)
- **더**: [`docs/reference/critical-rules.md`](docs/reference/critical-rules.md)

### 2.4 Loop / Mistake Loop / Steering Loop

- **무엇**: 실수 발견 시 *코드*가 아니라 *하네스*를 고치는 사이클. 캡처 → 심사 → 룰 승격
- **왜 필요한가**: 같은 실수가 다른 PR에서 반복되는 건 시스템 결함이지 사람 잘못이 아니에요. 코드만 고치면 한 번이지만 환경(룰·sensor)을 고치면 영구적이에요. "agent가 실패하면 코드를 고치지 않고 환경을 고친다"가 핵심
- **goax**: `.ax/mistakes/YYYY-MM-DD-NNN-*.md` 캡처 → `goax audit` → CLAUDE.md / ADR / `spirit/rules/<카테고리>` 승격
- **더**: [`docs/concepts.md`](docs/concepts.md), `.claude/skills/global/steering-loop/`

### 2.5 Layer 0 — Triage

- **무엇**: 작업 진입 시 30초 안에 *Size × Risk*로 분류 + 권장 경로 제시
- **왜 필요한가**: 한 줄 수정과 P0 리팩토링이 같은 진입점을 가지면 안 돼요. 작은 일에 큰 컨텍스트는 토큰 낭비, 큰 일에 작은 컨텍스트는 사고. 진입점에서 30초 만에 구분해서 라우팅해야 해요
- **goax**:
  - CLI: `goax triage "<작업>"`
  - Skill: `.claude/skills/global/triage/SKILL.md`
  - 출력: `size, risk, suggested_path, required_sensors, suggested_persona, spirit_context, human_gate`
- **더**: [`docs/reference/triage-matrix.md`](docs/reference/triage-matrix.md)

### 2.6 Layer 1 — Constitution

- **무엇**: 프로젝트의 *비협상 룰* (3\~5개 핵심 CRITICAL만)
- **왜 필요한가**: 비협상 룰이 명시되지 않으면 같은 실수가 다른 PR에서 반복돼요. CRITICAL은 자동 차단할 수 있게 짧고 검출 가능한 형태로 박아둬야 해요. 길게 늘어놓으면 안 외워지고 무시당해요
- **goax**: `CLAUDE.md` (얇음 — 인덱스 + 핵심 룰만, 나머지는 spirit으로)
- **더**: [`docs/concepts.md`](docs/concepts.md)

### 2.7 Layer 2 — Module Rules

- **무엇**: 모노레포의 각 모듈/앱별 sub-CLAUDE.md
- **왜 필요한가**: 모노레포에서 root CLAUDE.md 한 파일에 모든 모듈 룰이 몰리면 비대해지고 컨텍스트 낭비예요. 모듈 안에서만 결정되는 룰은 그 모듈의 sub-CLAUDE.md에 두면 작업 시 필요한 룰만 컨텍스트에 들어와요
- **goax**: `apps/<app>/CLAUDE.md`, `<module>/CLAUDE.md` — 그 모듈 안에서만 결정되는 룰
- **더**: [`docs/examples/monorepo.md`](docs/examples/monorepo.md)

### 2.8 Layer 3 — Spec / ADR

- **무엇**: 결정 근거 + 거부된 대안 + 도메인 정의
- **왜 필요한가**: ADR이 없으면 *거부된 대안*이 사라져서 미래의 AI나 새 팀원이 그 대안을 다시 제안해요. "왜 X 대신 Y를 채택했나"를 적어두지 않으면 같은 토론을 반복해요. Spec은 "X는 무엇인가"를 코드와 분리해서 사람도 읽도록
- **goax**: `docs/adr/NNN-*.md` (결정 근거) + `docs/spec/feature/NNN-<name>/{spec,plan,tasks,checklists/requirements}.md` (SDD 워크플로우)
  - **CLI**: `goax spec new <name>` / `goax spec check` / `goax spec list`
  - **SSOT**: spec.md를 단일 진실로. plan/tasks가 spec을 *입력*으로 공유
  - **게이팅**: `**NEEDS CLARIFICATION**` 마커 미해소 시 `spec check` fail
  - Triage가 size=L+ 또는 risk=L2+ 분류 시 spec 우선 작성 권장
- **더**: 새 ADR: `.claude/skills/workflows/adr-write/SKILL.md` / SDD: [`docs/spec/_templates/README.md`](docs/spec/_templates/README.md)

### 2.9 Spirit (행동 정체성)

- **무엇**: 모든 sub-agent가 공유하는 *태도·문화·일하는 방식*
- **왜 필요한가**: Persona가 늘어날수록 톤·휴리스틱이 분기돼요. code-reviewer는 단호한데 engineer-generalist는 상냥하면 같은 PR에서 인격 분열. 모든 sub-agent에 *공통 태도*를 자동 주입하면 결과물이 한 팀에서 나온 것처럼 보여요
- **goax**:
  - `.ax/spirit/values.md` — 핵심 가치 (긍정 편향 금지 / 비판적 사고 / 결과→근거→다음 액션 등)
  - `.ax/spirit/tone.md` — `~해요 체` 강제 + 안티패턴
  - `.ax/spirit/rules/<카테고리>.md` — 카테고리별 룰 (security, naming, pr, testing, ...)
  - Triage가 `spirit_context: { values, tone, rules }`로 자동 주입
  - 누락 시 `triage`가 **fail로 차단**
- **더**: [`docs/spirit.md`](docs/spirit.md)

### 2.10 Critical Signal (시그널 포맷)

- **무엇**: 룰 등급을 시각·기계 검출 가능하게 표시
- **왜 필요한가**: 룰을 모두 같은 무게로 적으면 AI가 어느 게 정말 중요한지 몰라요. CRITICAL/MANDATORY/CONVENTION 3등급으로 나누면 자동 차단 / 사람 승인 / 단순 가이드를 명확히 구분할 수 있어요
- **goax**:
  - 🔴 **CRITICAL** — 자동 차단 (Sensors)
  - 🟡 **MANDATORY** — 사람 승인 필요
  - 🔵 **CONVENTION** — 일반 가이드
- **더**: [`docs/reference/critical-rules.md`](docs/reference/critical-rules.md)

### 2.11 Rules Tokens (룰 식별 토큰)

- **무엇**: 모든 룰에 표준 ID — 사람과 grep 둘 다 1초 검색
- **왜 필요한가**: 모노레포에서 룰이 root + 모듈별 + spirit/rules로 분산돼요. "결제 도메인 CRITICAL만"같은 1초 쿼리는 표준 ID 토큰 없이는 불가능. 토큰을 박아두면 사람과 grep 둘 다 빨라져요
- **goax**:
  - Constitution: `<scope>:<LEVEL>:<id>` (예: `AX:CRITICAL:001`, `payment:MANDATORY:003`)
  - Spirit: `SP-<CATEGORY>-<id>` (예: `SP-SEC-001`)
  - CLI: `goax rules`, `goax find <token>`
- **더**: [`docs/reference/rules-tokens.md`](docs/reference/rules-tokens.md)

### 2.12 Persona (역할 페르소나)

- **무엇**: 한 폴더 = 한 의도 — 도메인/역할별 사고법
- **왜 필요한가**: "코드 짜줘"라고만 하면 모델이 일반론으로 답해요. "결제 도메인 전문가가 됐다고 가정하고 멱등성·PG 연동·금액 흐름을 우선시하라"고 명시하면 답이 달라져요. 한 폴더 = 한 의도로 분리하면 트리거 description이 명확해서 매칭 정확도도 올라가요
- **goax**:
  - 기본 4개: `engineer-generalist` / `code-reviewer` / `bug-hunter` / `refactorer`
  - 도메인 추가: `personas/payment-engineer/`, `personas/frontend-engineer/` 등
  - Triage가 `suggested_persona`로 매칭
- **더**: `.claude/skills/personas/`, `.claude/skills/_index.md`

### 2.13 Generator / Evaluator 분리

- **무엇**: 코드를 *쓰는* 세션과 *비평하는* 세션 분리 — self-praise bias 제거
- **왜 필요한가**: 같은 세션에서 자기 결과를 평가하면 "잘 됐어요"라고 답하는 self-praise bias가 있어요. 별도 세션의 evaluator가 docs·spec·ADR만 보고 비평하면 객관성이 회복돼요
- **goax**:
  - Generator: 메인 persona (engineer-generalist, refactorer 등)
  - Evaluator: `.claude/agents/evaluator.md` (별도 sub-agent, docs/spec/ADR만 보고 비평)
  - Architect: `.claude/agents/architect.md` (구조 위반 검토)
- **더**: `.claude/agents/`

### 2.14 Brownfield 도입 (`goax up`)

- **무엇**: 이미 운영 중인 프로젝트에 점진적으로 goax 도입
- **왜 필요한가**: 빈 프로젝트에 goax를 까는 건 쉬워요. 어려운 건 이미 운영 중인 모노레포에 충돌 없이 점진 도입하는 것. 기존 자산(CLAUDE.md / 외부 spec / hooks / AI 리뷰 도구)을 자동 스캔하고 사용자 결정을 받아 단계별로 도입해야 안전해요. 첫날부터 fail 모드로 모든 PR을 막으면 팀 반발로 도입 자체가 실패해요
- **goax**: `goax up` 한 명령으로 4-phase
  - Phase 1 Discover (자동 스캔)
  - Phase 2 Plan (결정 4개 plan-mode)
  - Phase 3 Apply
  - Phase 4 Next
- **더**: [`docs/up.md`](docs/up.md)

---

## 3. Cheat Sheet

### 룰 시그널

```
🔴 **`AX:CRITICAL:001`** 파괴적 명령 차단     ← Constitution (CLAUDE.md)
🟡 **`AX:MANDATORY:002`** 신규 도메인 ADR
🔵 **`AX:CONVENTION:003`** 한국어 commit
```

```
## SP-SEC-001: Secrets는 환경변수      ← Spirit (.ax/spirit/rules/security.md)
## SP-NAMING-001: kebab-case
## SP-PR-002: commit prefix
```

### CLI 빠른 참조

| 명령 | 역할 |
|---|---|
| `goax init [--preset starter]` | Greenfield 신규 설치 |
| `goax up [--dry-run] [--auto a,a,a,a]` | Brownfield 도입 (4-phase) |
| `goax triage "<작업>"` | Size×Risk 분류 + spirit_context 자동 주입 |
| `goax rules [--source spirit\|constitution] [--level critical] [--category security]` | 룰 인덱스/검색 |
| `goax find <token>` | ID로 단일 룰 + 본문 + ADR 링크 |
| `goax spirit [add\|lint\|status]` | Spirit 디렉토리 관리 |
| `goax spec [new\|check\|list]` | **SDD** — Spec-Driven Development (SSOT) |
| `goax audit` | mistakes 심사 + 룰 승격 후보 |
| `goax doctor` | 하네스 상태 진단 (점수) |
| `goax update` | goax 자체 갱신 |

### 디렉토리 한 화면 (v0.5)

```
your-project/
├── CLAUDE.md                       # Layer 1 — 핵심 비협상 룰 3~5개만
├── docs/
│   ├── adr/                        # Architecture Decision Records
│   │   ├── 0000-template.md        # 템플릿
│   │   └── NNNN-*.md               # 실제 ADR
│   └── spec/                       # SDD — Spec-Driven Development
│       ├── _templates/             # 8 템플릿 (spec/plan/tasks/...)
│       └── feature/
│           └── NNN-<name>/         # 피처별 spec 디렉토리
│               ├── spec.md         # SSOT — WHAT/WHY
│               ├── plan.md         # HOW
│               ├── tasks.md        # 작업 분해
│               └── checklists/requirements.md   # 게이팅
├── .claude/                        # Claude Code 표준 위치 (자동 로드)
│   ├── skills/                     # 한 폴더 = 한 의도 패턴 — 한 폴더 = 한 의도
│   │   ├── _index.md
│   │   ├── global/                 # triage, critical-rules, steering-loop
│   │   ├── personas/               # engineer-generalist (default 1) + 사용자 추가
│   │   ├── workflows/              # adr-write
│   │   └── meta/                   # skill-audit, skill-creator
│   ├── agents/                     # sub-agents
│   │   └── evaluator.md            # default 1 (architect는 starter)
│   └── settings.json               # hooks 등록 entry point (.ax/hooks 호출)
└── .ax/                            # goax 자체 자산
    ├── spirit/                     # cross-cutting 행동 정체성
    │   ├── values.md               # 핵심 가치
    │   ├── tone.md                 # 협업 톤 (~해요 체)
    │   └── rules/
    │       ├── _TEMPLATE.md        # 새 카테고리 만들 때 표본
    │       └── <category>.md       # 사용자 add/remove (starter는 7개 예시)
    ├── hooks/                      # Sensors 자동화 (.claude/settings.json이 호출)
    │   ├── pre-bash/               # default: block-destructive
    │   ├── pre-edit/               # default: check-protected-paths
    │   ├── post-edit/              # starter: lint-changed
    │   └── pre-commit/             # default: critical-rule-grep
    ├── mistakes/                   # Mistake Loop 캡처 슬롯
    ├── config.yml                  # domain_risk · sensors mode · commands
    └── version
```

> **`.claude/`** = Claude Code 표준 위치 (자동 로드 — slash command 매칭, sub-agent 인식)
> **`.ax/`** = goax 자체 자산 (Claude Code 표준 외 — spirit, mistakes, hooks 스크립트, config)
> 결정 근거: [`docs/adr/0002-claude-vs-ax-directory-split.md`](docs/adr/0002-claude-vs-ax-directory-split.md)

---

## 4. 학습 경로 — 어떤 순서로 읽으면 좋은가

### 5분 — 무엇인지만 보고 싶을 때

1. 이 파일 §0 + §1 (다이어그램)
2. [README.md](README.md) TL;DR

### 30분 — 적용 결정을 내려야 할 때

1. 이 파일 전체
2. [`docs/concepts.md`](docs/concepts.md) — 깊이 있는 모델 설명
3. [`docs/up.md`](docs/up.md) — Brownfield 도입 가이드
4. [`docs/spirit.md`](docs/spirit.md) — Spirit 작성법

### 1시간 — 실제 도입 + 자기 룰 채우기

1. 위 30분 + 실행:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash
   cd <자기 프로젝트>
   goax up                      # Brownfield면
   goax up --preset starter   # Greenfield면
   goax doctor
   goax triage "<첫 작업>"
   ```
2. [`docs/customization.md`](docs/customization.md) — 자기 프로젝트 맞춤화
3. [`docs/reference/rules-tokens.md`](docs/reference/rules-tokens.md) — 룰 작성 양식
4. [`.ax/spirit/values.md`](templates/default/.ax/spirit/values.md) 검토 — 우리 팀 가치로 교체

### 깊이 더 들어갈 때

- [`docs/reference/critical-rules.md`](docs/reference/critical-rules.md) — 룰 카테고리별 자동화 가능 여부
- [`docs/reference/triage-matrix.md`](docs/reference/triage-matrix.md) — Size×Risk 매트릭스
- [`docs/reference/glossary.md`](docs/reference/glossary.md) — 용어 사전
- [CHANGELOG.md](CHANGELOG.md) — 버전별 변경

---

## 5. 안 다루는 것 (Out of scope)

- **모델 fine-tuning** — goax는 사용 모델에 무관
- **prompt engineering** — *환경*을 다룸 (환경 엔지니어링의 핵심 메시지)
- **에이전트 오케스트레이션 엔진** — task-machine / swarm 같은 건 별도
- **CI/CD 자체** — hooks·sensors는 GitHub Actions 등 외부와 통합 가능하지만 goax가 직접 CI 시스템은 아님

---

## 6. 한 줄로 goax가 무엇이라 답할까

> "어떤 프로젝트든 1분 안에 4계층 하네스(Constitution/Module/Spec/Spirit) + 자동 검증(Sensors) + 실수 반복 차단(Mistake Loop)을 깔아주는 작은 bash 프레임워크. AI 에이전트의 결과 일관성을 *환경* 차원에서 통제해요."

---

## 변경 이력

본 문서는 goax의 핵심 개념을 한 곳에 정리한 마스터 인덱스예요. 개념 추가·재정의 시 동시에 이 파일도 갱신해주세요.

- v0.4 (이번): Brownfield 도입(`goax up`) + Concepts 사전 신설
- v0.3: Spirit 레이어 추가
- v0.2: Personas + 룰 토큰 + rules CLI
- v0.1: 4계층 골격 + Triage + Hooks
