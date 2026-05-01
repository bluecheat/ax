# References — Promotion Matrix (steering-loop 상세)

## 승격 의사결정 표

| 신호 | 승격 대상 | 형식 |
|---|---|---|
| 같은 룰 ≥ 3회 + Sensor 자동화 가능 | CLAUDE.md CRITICAL | 🔴 + hook |
| 같은 룰 ≥ 3회 + 사람 판단 필요 | CLAUDE.md MANDATORY | 🟡 + PR 게이트 |
| 결정 근거 필요 | docs/adr/NNN-*.md | ADR 신설 |
| 한 모듈 한정 | <module>/CLAUDE.md | 모듈 룰 |
| 도메인 정책 변화 | spec/policies/*.md | 정책 갱신 |
| 스킬 부재로 발생 | .ax/skills/personas/<role>/ | 신규 persona |

## 승격 후 처리

- mistakes 파일 → `.ax/mistakes/_archive/YYYY/MM/`
- CLAUDE.md/ADR 변경은 반드시 PR (squash 머지 X)
- 룰 토큰 ID 발급 — `<scope>:<LEVEL>:<id>` (rules-tokens.md 참조)

## 임계치 튜닝

`.ax/config.yml`의 `mistake_loop.promotion_threshold` (기본 3).
- 너무 작음 → 노이즈
- 너무 큼 → 같은 실수가 굳어짐
- 6개월 운영 후 audit 결과로 튜닝
