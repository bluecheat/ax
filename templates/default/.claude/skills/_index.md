# Skill Index

> Triage가 작업 분류 후 어떤 skill/agent를 호출할지 결정할 때 참조하는 라우팅 표.

## 그룹

| 그룹 | 용도 | 예 |
|---|---|---|
| global/ | 전역 — 모든 작업 진입점 | triage, critical-rules, steering-loop |
| personas/ | 도메인 페르소나 | api-engineer, payment-engineer (자기 프로젝트로 추가) |
| workflows/ | 일상 작업 | commit, deploy, adr-write, skill-audit |
| vendor/ | 외부 빌려온 룰셋 | (자기 프로젝트로 추가) |
| meta/ | skill 자체 도구 | skill-creator, skill-audit |

## 라우팅 매트릭스

| 작업 유형 | size | risk | 호출 순서 |
|---|---|---|---|
| 한 줄 수정 | S | L0~L1 | (직접) → commit |
| 단일 도메인 신규 | M | L0~L1 | persona → tester → commit |
| 단일 도메인 + 고위험 | M | L2~L3 | persona → traffic-engineer → adr-write → tester → evaluator → commit |
| Cross-domain | L | L0~L2 | task-machine → multiple personas → adr-write → evaluator → commit |
| Cross-domain + 결제·주문 | L | L3 | adr-write 먼저 → task-machine → architect 게이트 → tester → evaluator → commit |
| 신규 도메인 부트스트랩 | XL | * | adr-write → 단계 분할 → 단계당 PR |
| 리팩토링 | XL | * | refactorer persona → 단계 분할 → 단계당 ADR |

## 자기 프로젝트에 맞춤화

1. `personas/`에 자기 도메인 페르소나 추가
2. 위 매트릭스에서 task-machine/tester/evaluator 등이 자기 환경에 맞는지 확인
3. vendor 룰셋은 `vendor/`로
