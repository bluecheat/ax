# Reference — Triage Matrix

## Size

| 등급 | 정의 | 권장 경로 |
|---|---|---|
| S | 1\~2 파일, 비즈니스 로직 미변경 | 즉시 작업 + commit |
| M | 한 도메인 신규 기능, 1\~2일 | task-machine / speckit |
| L | Cross-domain OR 고위험 도메인 | task-machine 5-parallel + ADR |
| XL | 신규 도메인 / 리팩토링 / 마이그레이션 | 단계 분할 + 단계당 ADR |

## Risk

| 등급 | 의미 | Sensors |
|---|---|---|
| L0 | 사용자 영향 미미, 롤백 자유 | lint + 변경 파일 테스트 |
| L1 | 사용자 노출, 캐시 영향 없음 | + structural-check |
| L2 | 트랜잭션 / 노출 + 캐시 | + integration tag + traffic estimation |
| L3 | 결제 / 정산 / 금액 흐름 | + 사람 architect 게이트 (강제) |

## 매트릭스 — 권장 액션 + Friction

| Size \ Risk | L0 | L1 | L2 | L3 |
|---|---|---|---|---|
| **S** | 즉시 · autopilot | 즉시+lint · autopilot | 즉시+ADR · phase_gate | 게이트+ADR+traffic · per_task |
| **M** | task-machine · autopilot | +structural · phase_gate | +traffic · phase_gate | 게이트+ADR+evaluator · per_task |
| **L** | +ADR · phase_gate | +ADR · phase_gate | +ADR+evaluator · phase_gate | 게이트+단계분할 · per_task |
| **XL** | 단계분할 · phase_gate | 단계분할 · phase_gate | 단계분할 · phase_gate | 단계분할+게이트+단계당 ADR · per_task |

> 각 셀: `권장 액션 · friction 모드`. friction 의미는 `confirmation-policy.md` 참조.
> - `autopilot` — 메뉴 X, 자동 진행, 실패 시에만 halt
> - `phase_gate` — Phase 경계에서만 사람 확인 (정보 밀도 풍부)
> - `per_task` — task 단위 [y/n] 강제 (L3 우선순위 C5 적용)

## 메뉴 출력 룰 (triage 출력용)

분류가 매트릭스 코너에 닿으면 (결정 공간 명확) 메뉴 X — 권장 1줄 + 진행 안내:

| 분류 | 출력 형식 |
|---|---|
| S × L0 | "즉시 작업으로 진행해요. 다른 경로 원하면 말씀." |
| L × L3 / XL × L3 | "spec+plan+tasks+ADR 풀 패키지 진행. 축소 원하면 `--tier standard` 명시." |
| 기타 명확 (S×L1, M×L0 등) | 권장 1줄만, 메뉴 생략 |

모호 영역에서만 `[a]/[b]/[c]/[d]` 메뉴:

| 분류 | 이유 |
|---|---|
| M × L2 | tier basic / standard 둘 다 정당화 가능 |
| L × L1~L2 | ADR 동반 여부가 진짜 결정 |
| 도메인 다중 매칭 | 어느 도메인 우선인지 사용자 결정 필요 |

## 호출 순서

기본:
```
[/triage] → [persona] → [구현] → [hooks] → [tester] → [evaluator] → [commit]
```

L 이상:
```
[/triage] → [adr-write] → [task-machine] → [도메인 페르소나(들)] → [hooks] → [tester] → [evaluator] → [architect] → [commit]
```

## 관련 룰

- `confirmation-policy.md` — friction 모드의 결정 규칙 SSOT
- `rules-tokens.md` — 룰 토큰 컨벤션
- `rule-enforcement.md` — enforced_by schema
