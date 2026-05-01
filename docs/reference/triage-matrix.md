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

## 매트릭스 — 권장 액션

| Size \ Risk | L0 | L1 | L2 | L3 |
|---|---|---|---|---|
| **S** | 즉시 | 즉시 + lint | 즉시 + ADR(짧게) | 게이트 + ADR + traffic |
| **M** | task-machine | + structural | + traffic | 게이트 + ADR + traffic + evaluator |
| **L** | + ADR | + ADR | + ADR + evaluator | 게이트 + 단계분할 |
| **XL** | 단계분할 | 단계분할 | 단계분할 | 단계분할 + 게이트 + 단계당 ADR |

## 호출 순서

기본:
```
[/triage] → [persona] → [구현] → [hooks] → [tester] → [evaluator] → [commit]
```

L 이상:
```
[/triage] → [adr-write] → [task-machine] → [도메인 페르소나(들)] → [hooks] → [tester] → [evaluator] → [architect] → [commit]
```
