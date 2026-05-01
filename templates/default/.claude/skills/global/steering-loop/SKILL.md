---
name: steering-loop
description: "Mistake Loop의 진입점 — 작업 중 발견한 실수/피드백을 .ax-first/mistakes/에 캡처하고, 주기적으로 ax-first audit으로 룰 승격 후보 도출. PDF의 Steering Loop 구현. 트리거: '실수', '재발', '같은 문제', '룰 승격', 'audit', '피드백'."
---

# Steering Loop Skill

> "agent 실패 시 코드를 고치지 않고 하네스를 고친다" — Custom Harness Architectures §6

## When to use

1. 캡처 — 작업 중 실수/오해/누락 발견 시
2. 심사 — 주 1회 또는 mistakes 5건 누적 시
3. 승격 — audit 결과를 CLAUDE.md / docs/adr / module CLAUDE.md로 반영

## 캡처 (즉시)

`.ax-first/mistakes/YYYY-MM-DD-NNN-<slug>.md` 생성:

```markdown
---
category: <dependency-direction | secrets-in-code | n+1 | hydration | ...>
severity: <low | medium | high>
detected_by: <claude | reviewer | ci | self>
context_link: <PR URL or commit SHA>
---

# 무엇이 일어났나
# 어디서
# 왜 발생
# 어떻게 막을 수 있나 (사람 리뷰 vs Sensor 자동화)
```

자동 캡처 트리거:
- 같은 hook 5회 fail
- CodeRabbit 코멘트의 동일 카테고리 3회 이상
- 사용자가 "또 그걸…"이라고 표현

## 심사 (`/steering-audit`)

```bash
ax-first audit
```

출력: 카테고리별 발생 빈도, 임계치 초과 항목 → 승격 권고

## 승격 의사결정 표

| 신호 | 승격 대상 | 형식 |
|---|---|---|
| 같은 룰 ≥ 3회 + Sensor 자동화 가능 | CLAUDE.md CRITICAL | 🔴 + hook |
| 같은 룰 ≥ 3회 + 사람 판단 필요 | CLAUDE.md MANDATORY | 🟡 + PR 게이트 |
| 결정 근거 필요 | docs/adr/NNN-*.md | ADR 신설 |
| 한 모듈 한정 | <module>/CLAUDE.md | 모듈 룰 |
| 도메인 정책 변화 | spec/policies/*.md | 정책 갱신 |

## 안티 패턴

- mistakes 작성 후 audit 안 함 → 누적만 됨
- 1회로 즉시 CRITICAL 승격 → 노이즈 ↑
- 코드만 고치고 Sensor 추가 안 함 → 다음 사람 같은 실수
