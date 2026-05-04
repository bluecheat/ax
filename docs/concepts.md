# Concepts — goax가 적용하는 모델

> 실전 운영 경험에서 추출한 패턴.

---

## 핵심 공식

```
Agent  = Model(두뇌)  +  Harness(환경)
Harness = Guides(사전 지시) + Sensors(사후 검증) + Loop(피드백→하네스 갱신)
```

- **Model** — Claude/GPT 같은 LLM의 raw 능력. 우리가 통제 못 함.
- **Harness** — 우리가 만드는 모든 것. 에이전트가 무엇을 보고 무엇을 검증받고 어떻게 수정되는지.

> **명제**: "AI 결과 품질 차이는 Model이 아니라 Harness에서 나온다."

---

## 4계층 구조

goax가 어떤 프로젝트에든 깔아주는 골격.

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 0  Triage     /triage 진입 시 Size×Risk 라우팅          │
├─────────────────────────────────────────────────────────────┤
│ Layer 1  Constitution    CLAUDE.md — 비협상 룰                │
├─────────────────────────────────────────────────────────────┤
│ Layer 2  Module Rules    <module>/CLAUDE.md — 도메인별 룰     │
├─────────────────────────────────────────────────────────────┤
│ Layer 3  Spec / ADR     docs/adr/, spec/                    │
└─────────────────────────────────────────────────────────────┘
                                ↑
            ┌───────────────────┴───────────────────┐
            │ Cross-cut  Mistake Loop                │
            │  Sensors → mistakes/ → /steering-audit │
            └───────────────────────────────────────┘
```

### Layer 0 — Triage

- **왜**: 한 줄 수정과 P0 리팩토링이 같은 진입점을 가지면 안 된다.
- **무엇**: `/triage <설명>` 호출 시 30초 안에 Size(S/M/L/XL) × Risk(L0\~L3) 분류 + 권장 경로/sensors/사람 게이트 출력.
- **어디**: `.ax/skills/global/triage/SKILL.md` + CLI `goax triage`.

### Layer 1 — Constitution

- **왜**: 비협상 룰이 명시되지 않으면 같은 실수가 다른 PR에서 반복된다.
- **무엇**: `CLAUDE.md` — Architecture 룰, Prohibited 명령, API 사용 제약을 9 CRITICAL / 3 MANDATORY / N CONVENTION으로 분류.
- **시그널**: `🔴 CRITICAL` (자동 차단) / `🟡 MANDATORY` (사람 승인) / `🔵 CONVENTION` (가이드).

### Layer 2 — Module Rules

- **왜**: Constitution 한 파일에 모든 모듈 룰이 몰리면 비대화 + 컨텍스트 낭비.
- **무엇**: 모노레포의 각 모듈/앱마다 `<module>/CLAUDE.md`를 두고 그 모듈 안에서만 결정되는 룰 명시.

### Layer 3 — Spec / ADR

- **왜**: ADR가 *context drift* 방지의 핵심이에요. 거부된 패턴을 적어두지 않으면 미래의 AI가 그 대안을 다시 제안해요.
- **무엇**: `docs/adr/NNN-*.md` (결정·검토대안·결과). 도메인 정의는 `spec/<domain>.md` 또는 별도 spec 프로젝트.

### Cross-cut — Mistake Loop

- **왜**: agent 실패 시 코드를 고치면 1번이지만 하네스(룰·sensor)를 고치면 영구적이에요. 같은 실수가 다른 PR에서 반복되는 건 시스템 결함이라 환경을 고쳐야 해결돼요.
- **무엇**:
  1. 캡처 — `.ax/mistakes/YYYY-MM-DD-NNN-<slug>.md`
  2. 심사 — `goax audit` (주 1회 또는 5건 누적 시)
  3. 승격 — Constitution / ADR / module CLAUDE / Sensor 추가

---

## Sensors 분류

| 종류 | 무엇 | goax의 기본 |
|---|---|---|
| Computational | 결정론적·빠름 — linter, typecheck, 정적 검출 | `.ax/hooks/`의 4종 |
| Inferential | AI-led 깊은 평가 — 아키텍처 적합성 | `architect`, `evaluator` agent + 외부 CodeRabbit |
| Structural | 레이어/모듈 의존 위반 자동 검출 | 자기 프로젝트 의존 분석 스크립트를 hooks에 연결 |
| Functional | TDD 강제 — 테스트 없는 구현 차단 | (자기 프로젝트로 확장) |

---

## 한 폴더 = 한 의도 패턴

`.ax/skills/`는 **한 폴더 = 한 페르소나/의도** 단위로 구성.

```
.ax/skills/
├── global/         # 모든 작업 진입점
├── personas/       # 도메인 페르소나 (api-engineer, payment-engineer)
├── workflows/      # 일상 작업 (commit, deploy, adr-write)
├── vendor/         # 외부 빌려온 룰셋
└── meta/           # skill 자체 도구
```

각 SKILL.md의 `description` 필드는 **트리거 키워드 5\~10개**를 포함해야 매칭 정확도가 올라간다.

---

## Generator / Evaluator 분리

self-praise bias 제거 모델.

- **Generator** — 코드를 쓰는 메인 세션. 자기 결과를 평가할 때 편향됨.
- **Evaluator** — 별도 세션, **docs/spec/ADR만 보고** 변경에 비평. goax의 `evaluator` agent.
- **Harness** — 결정론적 sensor (linter, structural test). agent가 아니라 스크립트.

---

## 왜 이 모델이 다른 모델보다 나은가

- **PRD-first / Speckit** — 요구사항 정의는 잘하지만 *비협상 룰*과 *실수 반복 차단*이 약함.
- **Cursor rules / .cursorrules** — Layer 1만 있고 Triage·Sensors·Loop가 없음.
- **AI 코드 리뷰 단독 (CodeRabbit 등)** — 사후 검증만, 사전 가이드 없음.
- **goax** — 4계층 + Loop가 한 골격에 들어가 있어서 **하나만 빠지면 알 수 있음** (`goax doctor`).

---

## 추가 자료

- 모노레포 사례: [examples/monorepo.md](examples/monorepo.md)
- 단일 앱 사례: [examples/single-app.md](examples/single-app.md)
