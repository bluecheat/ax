# Example — commerce 적용

> Kotlin/Spring Boot 멀티모듈 (1700만 active users) 에 ax-first 적용 사례.

## 기존 자산

- `projects/commerce/CLAUDE.md` 73줄 (얇음)
- `.claude/skills/` 4개 (commerce-developer-alpha, task-machine, skill-creator)
- `.claude/agents/commerce-tester.md`
- `.serena/`, `.omc/`, `dependencies/` 분석 스크립트
- 별도 프로젝트 `projects/commerce-spec/{adr,specs,policies,docs}` ← Layer 3 인프라 이미 보유

## 적용 절차

```bash
cd commerce-monorepo/projects/commerce
ax-first init --preset ax    # 9 CRITICAL이 CLAUDE.md에 추가됨

# 결정: commerce-spec을 projects/commerce/spec/로 통합
git mv ../commerce-spec/{adr,specs,policies,docs} ./spec/

ax-first doctor
```

## 맞춤화

`.ax-first/config.yml`:

```yaml
domain_risk:
  payment: L3
  결제: L3
  settlement: L2
  정산: L2
  order: L2
  주문: L2
  product: L1
  상품: L1
  store: L1
  ad: L1
  bookmark: L0
  util: L0
  infra: L0

commands:
  build: "./gradlew build"
  test: "./gradlew test"
  lint: "./gradlew ktlintCheck"
sensors:
  mode: warning
  protected_paths:
    - CLAUDE.md
    - .ax-first/
    - build-logic/
    - .deploy/
    - spec/
```

## 11개 모듈 CLAUDE.md

```bash
for m in commerce-core commerce-data commerce-event \
         commerce-rest commerce-graphql-next \
         commerce-batch commerce-worker commerce-admin \
         commerce-infra commerce-test commerce-util; do
  touch "$m/CLAUDE.md"
done
```

`commerce-core/CLAUDE.md`:

```markdown
# commerce-core — Module Rules

## 🔴 CRITICAL
- Clean Architecture 패키지: application/{port/in,port/out,service}, domain/{model,event}, dto, exception
- UseCase는 interface, 구현은 application/service
- Repository는 application/port/out/ 외부에 위치 금지
- Domain 모델 100% val (Rich Domain)

## 🔵 CONVENTION
- Actor 기반 Service 그루핑 (Customer, Seller, Admin 등)
```

## Sensors — circular_analysis.py 연결

```yaml
# .github/workflows/structural-check.yml
- name: Module dependency check
  run: python projects/commerce/dependencies/circular_analysis.py
  continue-on-error: true   # warning-only (Phase 1~2)
```

## Triage 출력 예시

```bash
$ ax-first triage "주문 환불 윈도우 7→14일"
🔍 ax-first triage
  size:    L
  risk:    L2
  domain:  order 주문
  path:    task-machine 5-parallel + 도메인 페르소나 + ADR 강제
  sensors: ktlint, eslint, tsc, structural-check, integration tag, traffic estimation
  human gate: true

권장 다음 단계:
  → /adr-write 로 ADR 초안 → task-machine 5-parallel → /evaluator.

  ⚠ MANDATORY: 사람 architect 승인 필요한 작업
```

## 풀 플랜 문서

`/Users/stone/Documents/Claude/Projects/AX 플랫폼/commerce-harness-plan.md`
`/Users/stone/Documents/Claude/Projects/AX 플랫폼/commerce-harness-1pager.md`
