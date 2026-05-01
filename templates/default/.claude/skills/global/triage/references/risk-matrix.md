# References — Risk Matrix (triage skill 상세)

## Size

| 등급 | 정의 |
|---|---|
| S — Patch | 1~2 파일, 한 도메인, 비즈니스 로직 미변경 (오타·색상·문구·작은 옵션) |
| M — Feature | 한 모듈/도메인 내 신규 기능, 1~2일 작업 |
| L — Cross-domain / High-risk | 2개 이상 도메인 OR 결제·주문·정산 등 고위험 도메인 |
| XL — Bootstrap / Refactor | 신규 도메인 추가, P0 리팩토링, 마이그레이션, 1주 이상 |

## Risk (도메인 기반)

`.ax/config.yml`의 `domain_risk` 매트릭스 참조. 매칭 안 되면 `default_risk`.

| 등급 | 의미 |
|---|---|
| L0 | 사용자 영향 미미, 롤백 자유 |
| L1 | 사용자 노출, 캐시 영향 없음 |
| L2 | 노출+캐시 OR 트랜잭션 |
| L3 | 결제·정산·금액 흐름 — 자동 사람 게이트 |

## Size × Risk 매트릭스 — 권장 액션

| Size \ Risk | L0 | L1 | L2 | L3 |
|---|---|---|---|---|
| S | 즉시 | 즉시 + lint | 즉시 + ADR(짧게) | 게이트 + ADR + traffic |
| M | task-machine | + structural | + traffic | 게이트 + ADR + traffic + evaluator |
| L | + ADR | + ADR | + ADR + evaluator | 게이트 + 단계분할 |
| XL | 단계분할 | 단계분할 | 단계분할 | 단계분할 + 게이트 + 단계당 ADR |

## 호출 순서

기본:
```
[/triage] → [persona] → [구현] → [hooks] → [tester] → [evaluator] → [commit]
```

L 이상:
```
[/triage] → [adr-write] → [task-machine] → [도메인 페르소나(들)] → [hooks] → [tester] → [evaluator] → [architect] → [commit]
```

## 안티 패턴

- 모든 작업을 풀 task-machine으로 처리 → 토큰 낭비
- Size만 보고 Risk 무시 → 한 줄 결제 변경이 무방비
- `human_gate=true`인데 대화 안에서 처리 → 머지 직전에 막힘
