# Reference — Confirmation Friction Policy

> 사람 확인을 *데이터로* 결정하는 룰. 무차별 묻기·자동 둘 다 anti-pattern.
> SSOT: 이 문서. spec-implement / triage SKILL.md 가 이 룰을 *입력으로* 받음.

## 왜 이 문서가 필요한가

4계층 권한 위임 모델에서 상위 단계(triage → spec-validate → spec-tasks)가 게이트를 통과시키면 그 결정은 *계약*. 그런데 implement 단계에서 task 단위로 [y/n] 을 또 묻는 건 같은 결정을 N회 재개봉하는 double-gate. 이는 SSOT 원칙(`CONCEPTS.md` §5.4) 과 권한 위임 모델 둘 다 위반.

동시에 무조건 자동 진행도 답이 아님 — spec / ADR 작성 시점에 모르던 결정이 implement 시점에 발생할 수 있고(설계 이탈·task 간 의존 깨짐·도메인 위험 무감각), 메뉴 출력은 *결정 공간 명시화*의 가치가 있음.

이 정책은 둘 사이의 균형을 *goax 기존 변수* 로만 결정.

## 결정 변수

| 변수 | 출처 | 역할 |
|---|---|---|
| `size × risk` | triage 분류 결과 | 1차 friction 강도 |
| `spec_tier` | standard / full | 2차 friction (tier 가 size×risk 흡수) |
| `sensors.mode` | `.ax/config.yml` (warning/fail) | hooks 차단 강도 → LLM 추가 확인 redundancy 결정 |
| `mistake_recurrence` | 같은 카테고리 mistake 누적 | 동적 강화 신호 |
| `enforced_by_coverage` | hook:* + external:* / 전체 | sensor 부재 영역 보완 필요성 |
| `spirit_match` | SP-SEC-* / SP-DATA-* 매칭 여부 | 위험 카테고리 식별 |

## Decision Rules

### Rule C1 — tier 기반 게이트 빈도

| spec_tier | implement 게이트 |
|---|---|
| standard | Phase 경계 1회 (`Phase 1 → Phase 2` 전환 시) |
| full | Phase 경계 + ADR-touching task 단위 |

근거: tier 가 이미 size×risk 를 흡수했으므로 tier 가 friction 의 1차 함수.

### Rule C2 — sensors.mode 와 autopilot

| sensors.mode | tier ≤ standard | tier = full |
|---|---|---|
| `fail` | autopilot (per-task 확인 X) | Phase 경계 |
| `warning` | Phase 경계 | Phase 경계 + ADR-touching |

근거: `fail` 모드는 hooks 가 critical 위반을 자동 차단한다는 *계약 강도*. 계약이 강하면 LLM 추가 확인은 redundant.

### Rule C3 — Mistake 재발 escalation

```
같은 카테고리 mistake ≥ N (config.confirmation.mistake_threshold, 기본 3)
  → 그 카테고리 영향 task 만 [y/n] 강제
처음 작업하는 도메인 (mistakes 0건)
  → autopilot 허용
```

근거: Mistake Loop 가 신호 강도를 제공. evidence-driven friction. 도메인이 안정화되면 자동, 흔들리면 강제.

### Rule C4 — enforced_by coverage

```
영향 룰의 cover_ratio = (hook:* + external:*) / 전체 enforced_by

cover_ratio ≥ 0.8                   → autopilot
cover_ratio < 0.5  + risk ≥ L2      → per-task 확인 강제
```

근거: hooks 가 sensor 역할 못하는 영역만 LLM 확인이 의미 있음. Determinism Boundary(`CONCEPTS.md` §5.6) 의 자연스런 확장.

### Rule C5 — Spirit 카테고리 severity

| Spirit 매칭 | risk | 액션 |
|---|---|---|
| `SP-SEC-*` / `SP-DATA-*` | L3 | mode 불문 사람 게이트 강제 |
| `SP-SEC-*` / `SP-DATA-*` | L2 | Phase 경계 게이트 |
| 기타 (`SP-OPS-*` 등) | * | C1~C4 적용 |

근거: Spirit 룰의 카테고리 자체가 위험 신호. 보안·데이터 영역은 audit 단계에서 사후 교정이 비싸므로 사전 차단이 합리.

## 우선순위 (충돌 시)

```
C5 (L3 + SP-SEC/DATA)   ← 최우선, mode 불문 강제
C3 (mistake recurrence) ← 2순위, 카테고리 단위 강제
C4 (low coverage + L2+) ← 3순위
C1 (tier)               ← 기본값
C2 (sensors.mode)       ← C1 의 modifier
```

## 메뉴 출력 룰 (triage / 일반 skill)

매트릭스 코너 케이스(결정 명확) → 메뉴 X, 권장 1줄 + ▸ 진행:

| 분류 | 출력 |
|---|---|
| S × L0 | "즉시 작업으로 진행. 다른 경로 원하면 말씀." |
| L × L3 | "spec + plan + tasks + ADR 풀 패키지로 진행. 축소 원하면 tier=standard 명시." |
| 기타 명확 | 분류 결과 + 권장만 출력, 메뉴 생략 |

모호 영역(M × L2 등 중간 등급) → `[a]/[b]/[c]/[d]` 메뉴 유지 (결정 공간 시각화).

## 출력 형식 — 살아남은 confirmation 의 정보 밀도

per-task [y/n] 이 사라진 자리, Phase 경계 게이트는 *형식적 [y/n] 이 아닌* 의사결정 컨텍스트 제공:

```
◆  Phase 2 → Phase 3 전환

│  ✓ 완료 — Phase 2 (T007~T012, 6 task)
│   └─ commerce-data 4 파일, port + service + adapter
│
│  📍 다음 — Phase 3 (T013~T015, 3 task)
│   └─ commerce-batch — HandlerRegistry / R-P-W / cron
│
│  📐 적용될 룰 (Phase 2 와 차이)
│   + SP-OPS-002 — chunk size 명시 (Phase 3 신규)
│   + SP-DATA-007 → 그대로 유지
│
│  📂 영향 파일 (예정)
│   commerce-batch/.../HandlerRegistry.kt (신규)
│   commerce-batch/.../DispatchJobConfig.kt (신규)
│   .deploy/commerce/values.yml (cron 추가)
│
└  ▸ 진행 / 변경 사항 있으면 말씀
```

## 절대 금지

- task 단위 [y/n] (Phase 경계가 아닌 곳)
- 매트릭스 코너 케이스에 메뉴 의례적 출력
- C5 우회 (L3 + SP-SEC/DATA 자동화는 거짓 약속 — invariant 위반)
- "사용자가 [y] 만 누른다" 가정 (메뉴는 인지·비판적 사고의 인프라)
- **한 turn 안에 옵션 dispatch (`[a]/[b]/...`) 2회 이상 출력** — 인지 부하 누적. 한 단계 결정 후 다음 옵션 dispatch 가 필요하면 다음 turn 으로 분리.
- **이미 받은 결정을 같은 turn 에서 재제시** — 예: 사용자가 `c2` 선택 후 같은 commit message 출력에서 `[c-split]` 다시 옵션화. 결정 번복 유도 = 사용자 신뢰 훼손.
- **0건 변경 옵션 (`[1] 그대로 유지` 류) confirm 요구** — 비가역 행동이 이미 끝난 상태에서 "그대로 두기" 는 no-op. 묻지 말고 보고만.
- **의례적 trailing prompt** — `"다른 작업 있으면 알려주세요"`, `"추가 원하면 알려주세요"` 류는 매 turn 끝에 자동 삽입 X. 작업 결과만 보고하고 끝.

## Anti-pattern — 도그푸딩에서 발견된 friction 패턴

룰을 글로만 적고 행동에 안 박으면 룰이 거짓말이 돼요. 아래는 실제 도그푸딩 turn 에서 발견된 패턴 — skill 저자가 출력 예시 작성 시 의식적으로 회피해야 해요.

### A1 — Cascade option dispatch (옵션 폭주)

한 task 안에서 단계마다 옵션 dispatch:
```
commit message confirm     [go]/[c-split]/[edit]/[sig]   (4)
commit 후 다음 단계 안내    [push]/[pr]/[alpha]/[phase4] (4)
누락 발견 후 fix 방식       [A1]/[A2]/[A3] + [B]         (4)
fix 실패 후 복구 방식       [1]/[2]/[3]                  (3)
```
한 task 에 15+ 옵션 토큰. 사용자는 매번 키 입력 + 인지 부하.

**올바른 동작**: 첫 옵션 dispatch 후, 다음 단계는 자체 판단으로 진행. 사용자가 abort 하면 멈추고 묻기.

### A2 — Decision repackaging (결정 재포장)

사용자가 이미 한 결정을 같은 turn 에서 다른 옵션으로 재제시. "마지막 기회" 라는 framing 으로 결정 번복 유도.

**올바른 동작**: 한 번 받은 결정은 박제. 사용자가 명시적으로 "다시 결정할게" 라고 해야 재오픈.

### A3 — Trailing dispatch (의례적 마무리)

작업 완료 후 다음 작업 옵션을 자동 dispatch:
```
다음 단계
[push] gt submit
[pr] gh pr create
[alpha] T301
[phase4] 별도 PR
```
대부분 사용자는 자연어로 다음 명령을 직접 함. 옵션 dispatch 는 redundant.

**올바른 동작**: `[결과] ... 끝.` + 다음 명령 받으면 진행. `다른 작업 있으면 알려주세요` 류 trailing 도 금지.

### A4 — Zero-change confirm (0건 변경 confirm)

비가역 행동이 이미 끝난 후 `[1] 그대로 유지` 옵션 제시. 클릭해도 0건 변경.

**올바른 동작**: `[결과] ... (이미 진행됨, 그대로 유지)` 보고만. 사용자가 "원복해줘" 라고 명시할 때만 [revert] 옵션.

## 관련 룰

- `CONCEPTS.md` §5.7 — Confirmation Friction Policy (이 정책의 design rationale)
- `CONCEPTS.md` §5.4 — SDD SSOT 원칙
- `docs/reference/triage-matrix.md` — friction column
- `docs/reference/rule-enforcement.md` — enforced_by schema
- `skills/spec-implement/SKILL.md` — 이 정책의 implementer
- `skills/triage/SKILL.md` — 이 정책의 publisher (메뉴 출력 룰)
