# Example — Single Application

> 단일 앱(웹 서비스, CLI, 모바일 단독 앱 등)에 goax 적용.

## 적용 절차

```bash
cd ~/your-app
goax up [--preset starter]
goax doctor
```

## 4계층 매핑 (단일 앱)

| Layer | 위치 | 무엇을 담는가 |
|---|---|---|
| 0 Triage | `.ax/skills/global/triage/SKILL.md` | 작업 진입 시 Size × Risk |
| 1 Constitution | `CLAUDE.md` | 비협상 룰 — 단일 앱이라 Layer 2 없이 여기에 모음 |
| 2 Module Rules | (생략 또는 디렉토리 단위로 가벼운 분리) | 큰 앱이면 `src/<area>/CLAUDE.md`로 분리 가능 |
| 3 Spec/ADR | `docs/adr/` | 결정 근거 |

## .ax/config.yml — 도메인을 기능 단위로

```yaml
domain_risk:
  auth: L2            # 인증·세션 — 보안 영향
  billing: L3         # 결제 — 금액 흐름
  notification: L1    # 알림 — 사용자 영향
  search: L0          # 검색 — 롤백 자유

commands:
  build: ""
  test: ""
  lint: ""
```

## Sensor 우선순위 — 단일 앱 특화

1. **post-edit lint-changed** — 변경 파일 즉시 lint
2. **pre-commit critical-rule-grep** — 보안/secrets 패턴 정적 검출
3. **pre-bash block-destructive** — 파괴적 명령 차단

## 안티 패턴

- CLAUDE.md를 README처럼 사용 → 비협상 룰이 묻힘
- domain_risk 정의 안 하면 모든 작업이 default_risk로 같은 트랙
