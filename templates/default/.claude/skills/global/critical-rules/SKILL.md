---
name: critical-rules
description: "현재 프로젝트의 CRITICAL/MANDATORY/CONVENTION 룰을 즉시 인용 가능하게 보유. CLAUDE.md를 매번 다시 읽지 않도록 핵심 룰 정리. 트리거: '룰', 'critical', 'mandatory', 코드 리뷰, PR 작성, 작업 시작 직전."
---

# Critical Rules Skill

CLAUDE.md (Layer 1 Constitution)에서 추출한 룰을 작업 흐름 안에서 빠르게 참조.

## When to use

- 코드 작성/수정 직전 — 적용 가능한 CRITICAL 검사
- PR/커밋 직전 — 위반 검출
- `/triage` 결과의 `critical_rules_to_check` 항목을 펼칠 때

## 시그널 포맷

```
🔴 CRITICAL — 자동 차단 (Sensors)
🟡 MANDATORY — 사람 승인
🔵 CONVENTION — 일반 가이드
```

## How

1. 작업 시작 시 `CLAUDE.md`의 `## CRITICAL` 섹션 우선 로드
2. 변경 파일이 어떤 모듈인지 파악 → 해당 모듈의 `<module>/CLAUDE.md`도 함께 로드
3. 위반 가능성:
   - CRITICAL → 작업 중단, 사용자 보고 + 우회 거부
   - MANDATORY → 사용자 승인 요청
   - CONVENTION → 진행하면서 코멘트로 안내

## CLI 연동

```bash
.claude/hooks/pre-commit/critical-rule-grep.sh
```

## 안티 패턴

- 룰을 외워서 적용 → 사용자가 갱신해도 반영 안 됨. CLAUDE.md를 source of truth로
- 모든 룰을 동등 가중치 → CRITICAL 우선
