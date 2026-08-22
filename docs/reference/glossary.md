# Glossary

| 용어 | 정의 |
|---|---|
| **Harness** | AI 에이전트의 환경. Guides + Sensors + Loop의 합집합. Model의 능력을 결과로 변환하는 깔때기 |
| **Guides** | 작업 *전* 에이전트에게 주어지는 지시. CLAUDE.md, skill, persona, ADR |
| **Sensors** | 작업 *후* 결과를 검증. linter / structural test / 인페런셜 리뷰 |
| **Loop** | Steering Loop — 실수 발견 시 코드를 고치지 않고 Harness를 고치는 사이클 |
| **Triage** | 작업 진입 시 Size×Risk 분류. 어떤 컨텍스트와 게이트가 필요한지 결정 |
| **Constitution** | Layer 1 비협상 룰. CLAUDE.md |
| **CRITICAL / MANDATORY / CONVENTION** | 룰 등급. 자동 차단 / 사람 승인 / 일반 가이드 |
| **ADR** | Architecture Decision Record. *왜* 이 결정이고 *무엇을* 거부했는가 |
| **Spec / Policy** | 도메인 정의 / 비즈니스 정책 |
| **Persona** | 도메인 전문가 skill (예: payment-engineer) |
| **Generator / Evaluator** | Anthropic 모델 운영 사례에서 인용된 self-praise bias 제거 패턴 (하네스 엔지니어링 모델 Generator/Evaluator 분리). 코드를 쓰는 세션 ≠ 평가하는 세션 |
| **Computational sensor** | 결정론적·빠름 — linter, typecheck |
| **Inferential sensor** | AI-led 깊은 평가 — agent, CodeRabbit |
| **Structural test** | 레이어/모듈 의존 방향 위반 자동 검출 |
| **Circuit Breaker** | 무한 루프 차단 — 같은 명령 N회 실패 시 정지 |
| **Mistake Loop** | `.ax/mistakes/` 캡처 → audit → 룰 승격 |
| **Invariant I1~I6** | 룰 라벨 ↔ 차단 메커니즘 계약의 불변량. `rule-enforcement.md` 가 SSOT, `check-rule-enforcement.sh` 가 검증 |
| **Sensors liveness** | Sensors 장치가 실제로 차단 가능한 상태인지 — mode·git hook·grep 패턴의 생사 (C1~C4, `check-sensor-liveness.sh`) |
| **거짓 약속** | 🔴 라벨이 자동 차단을 약속하지만 실제 차단 장치(트리거·훅)가 없는 상태. I1·I5·I6 가 잡는 대상 |
| **Preset** | goax init의 옵션 — default, ax 등. 기본 위에 overlay |
