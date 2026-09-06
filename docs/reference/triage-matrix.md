# Reference — Triage Matrix

## Size

| 등급 | 정의 | 권장 경로 |
|---|---|---|
| S | 1\~2 파일·한 함수, 비즈니스 로직 미변경 — 30분 안 | 즉시 작업 + commit |
| M | 한 모듈/도메인 신규 기능 — 반나절\~2일 | inline 또는 standard tier |
| L | 2개 이상 모듈/도메인 또는 새 추상화 — 1\~3일 | standard tier (+ evaluator/ADR) |
| XL | 신규 도메인 / 리팩토링 / 마이그레이션 — 1주 이상 | full tier + 단계 분할 + 단계당 ADR |

> Size 는 **규모만** 잰다 — 도메인 위험은 Risk 축이 담당. "결제라서 L" 같은 혼입은
> 위험을 두 축에 이중 반영해 매트릭스를 왜곡한다.

## Risk

| 등급 | 의미 | Sensors |
|---|---|---|
| L0 | 사용자 영향 미미, 롤백 자유 | lint + 변경 파일 테스트 |
| L1 | 사용자 노출, 캐시 영향 없음 | + structural-check |
| L2 | 트랜잭션 / 노출 + 캐시 | + integration tag + traffic estimation |
| L3 | 비가역 손실 가능 영역 — 결제·정산, 의료 PHI·EHR, 안전·제어, 회계·장부 무결성, 인증·자격증명 등 | + evaluator 필수(G6) + 사람 게이트(per_task) — architect 는 이 Risk 축이 아니라 **Size 축**(L/XL 필수, M 선택)으로 `spec-validate` §2.5 합의 리뷰가 불러요 |

## 매트릭스 — 권장 액션 + Friction

| Size \ Risk | L0 | L1 | L2 | L3 |
|---|---|---|---|---|
| **S** | 즉시 · autopilot | 즉시+lint · autopilot | 즉시+ADR · phase_gate | 게이트+ADR · per_task |
| **M** | inline · autopilot | inline+lint · phase_gate | standard · phase_gate | standard+evaluator · per_task |
| **L** | standard+evaluator · phase_gate | standard+evaluator · phase_gate | standard+evaluator · phase_gate | full+게이트+evaluator · per_task |
| **XL** | full+단계분할+evaluator · phase_gate | full+단계분할+evaluator · phase_gate | full+단계분할+evaluator · phase_gate | full+단계분할+단계당 ADR+evaluator · per_task |

> 각 셀: `권장 액션 · friction 모드`. friction 의미는 `confirmation-policy.md` 참조.
> - `autopilot` — 메뉴 X, 자동 진행, 실패 시에만 halt
> - `phase_gate` — Phase 경계에서만 사람 확인 (정보 밀도 풍부)
> - `per_task` — task 단위 [y/n] 강제 (L3 우선순위 C5 적용)

## 메뉴 출력 룰 (triage 출력용)

분류가 매트릭스 코너에 닿으면 (결정 공간 명확) 메뉴 X — 권장 1줄 + 진행 안내:

| 분류 | 출력 형식 |
|---|---|
| S × L0 | "즉시 작업으로 진행해요. 다른 경로 원하면 말씀." |
| L × L3 / XL × L3 | "spec + tasks + research/data-model/quickstart + ADR (full tier) 진행. 축소 원하면 `--tier standard` 명시." |
| 기타 명확 (S×L1, M×L0 등) | 권장 1줄만, 메뉴 생략 |

모호 영역에서만 `[a]/[b]/[c]/[d]` 메뉴:

| 분류 | 이유 |
|---|---|
| M × L2 | tier standard / full 둘 다 정당화 가능 |
| L × L1~L2 | ADR 동반 여부가 진짜 결정 |
| 도메인 다중 매칭 | 어느 도메인 우선인지 사용자 결정 필요 |

## 호출 순서

즉시/inline 경로:
```
[/triage] → [구현] → [hooks] → [commit]
```

spec 경로 (M×L2 이상, L, XL):
```
[/triage] → [spec] → [spec-validate] → [spec-tasks] → [lane] → [spec-implement] → [hooks] → [commit]
```

`[spec-validate]` 안에서 Size 축(L·XL 필수, M 은 `--consensus` 선택)이 architect·evaluator 합의
리뷰를 돌려요 — architect 는 Risk(L3) 가 아니라 **Size** 로 트리거돼요. `spec-implement` 완료
직전엔 별도로 evaluator(G6, size L 이상·M×L3 필수)가 한 번 더 봐요.

L3 또는 아키텍처 영향:
```
+ [adr] · 사람 게이트(per_task, task 단위 [y/n])
```

## 관련 룰

- `confirmation-policy.md` — friction 모드의 결정 규칙 SSOT
- `rules-tokens.md` — 룰 토큰 컨벤션
- `rule-enforcement.md` — enforced_by schema
