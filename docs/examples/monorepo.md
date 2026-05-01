# Example — Monorepo (multi-app/module)

> 멀티-앱 모노레포에 goax 적용 시 권장 패턴.

## 적용 절차

```bash
cd ~/your-monorepo
goax up [--preset starter]

# 모듈/앱별 sub-CLAUDE.md 생성
for d in apps/*/; do touch "$d/CLAUDE.md"; done

goax doctor
```

## 4계층을 모노레포에 매핑

| Layer | 위치 | 무엇을 담는가 |
|---|---|---|
| 0 Triage | `.ax/skills/global/triage/SKILL.md` | 작업 진입 시 Size × Risk × **어떤 앱** |
| 1 Constitution | `CLAUDE.md` (root) | 모든 앱 공통 비협상 룰 (예: 보호 경로, 빌드 흐름) |
| 2 Module Rules | `apps/<app>/CLAUDE.md` | 그 앱 안에서만 결정되는 룰 (스택 특화 패턴) |
| 3 Spec/ADR | `docs/adr/` | 모노레포 차원의 결정 (모듈 의존 방향, 빌드 시스템 등) |

## .ax/config.yml — 도메인을 앱 단위로

```yaml
domain_risk:
  api: L1            # 백엔드 — 트랜잭션 영향 가능성
  web: L0            # 프론트 — 사용자 직접 영향이지만 롤백 자유
  mobile: L1         # 앱 — OTA로 빠른 롤백, 단 네이티브는 L2
  payment: L3        # 결제 도메인 (어느 앱이든 매칭되면 격상)

commands:
  build: ""
  test: ""
  lint: ""
```

## Sensor 우선순위 — 모노레포 특화

1. **structural-check** — 모듈 의존 방향 위반 자동 검출 (`apps/A`가 `apps/B`를 직접 import 금지 등)
2. **post-edit lint-changed** — 변경 파일의 스택에 따라 분기
3. **pre-commit critical-rule-grep** — 모든 CRITICAL의 정적 패턴 검출

## 안티 패턴

- 한 root CLAUDE.md에 모든 앱 룰 다 적기 → 비대화 + 컨텍스트 낭비
- 앱별 CLAUDE.md를 만들었는데 root와 중복 → Layer 구분 무효
- 모듈 의존 방향을 정의 안 하거나 사람 리뷰에만 의존 → drift 누적
