# References — Risk Matrix (triage skill 상세)

## Size

| 등급 | 정의 |
|---|---|
| S — Patch | 1~2 파일·한 함수, 한 도메인, 비즈니스 로직 미변경 — 30분 안 (오타·색상·문구·작은 옵션) |
| M — Feature | 한 모듈/도메인 내 신규 기능 — 반나절~2일 |
| L — Cross-module | 2개 이상 모듈/도메인 또는 새 추상화 — 1~3일 |
| XL — Bootstrap / Refactor | 신규 도메인 추가, P0 리팩토링, 마이그레이션 — 1주 이상 |

> Size 는 **규모만** 잰다. "결제라서 L" 같은 위험 혼입 금지 — 도메인 위험은 Risk 축(`domain_risk`)이
> 담당하고, 섞으면 위험이 두 축에 이중 반영돼 매트릭스가 왜곡된다. (SKILL.md 2단계 표와 동일 — 수정 시 함께.)

## Risk (도메인 기반)

`.ax/config.yml`의 `domain_risk` 매트릭스 참조. 매칭 안 되면 `default_risk`.

| 등급 | 의미 |
|---|---|
| L0 | 사용자 영향 미미, 롤백 자유 |
| L1 | 사용자 노출, 캐시 영향 없음 |
| L2 | 노출+캐시 OR 트랜잭션 |
| L3 | 비가역 손실 가능 — 결제·정산·금액 흐름 등, 자동 사람 게이트 |

## Size × Risk 매트릭스 — 권장 액션

게이팅·tier 의 결정론 SSOT 는 `tier-from-state.sh` (standard / full 2단계). 이 표는 그 위에 게이트를 얹은 요약:

| Size \ Risk | L0 | L1 | L2 | L3 |
|---|---|---|---|---|
| S | 즉시 | 즉시 + lint | 즉시 + ADR(짧게) | 사람 게이트 + ADR |
| M | inline | inline + lint | standard | standard + evaluator |
| L | standard | standard | standard + evaluator | full + 사람 게이트 |
| XL | full + 단계분할 | full + 단계분할 | full + 단계분할 | full + 단계분할 + 단계당 ADR |

## 호출 순서

즉시/inline 경로:
```
[/triage] → [구현] → [hooks] → [commit]
```

spec 경로 (M×L2 이상, L, XL):
```
[/triage] → [spec] → [spec-tasks] → [spec-implement] → [hooks] → [evaluator] → [commit]
```

L3 또는 아키텍처 영향:
```
+ [adr] · [architect] 게이트
```

## 안티 패턴

- 모든 작업을 spec 풀 경로로 처리 → 토큰 낭비 (S×L0~L1 은 즉시 작업이 맞다)
- Size만 보고 Risk 무시 → 한 줄 결제 변경이 무방비
- 사람 게이트 대상(L3)인데 대화 안에서 자체 처리 → 머지 직전에 막힘
