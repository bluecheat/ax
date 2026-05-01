---
name: skill-audit
description: ".claude/skills/ 자체의 품질·중복·누락 정기 점검. Karpathy 패턴: 한 skill = 한 페르소나/의도. 트리거: 'skill 정리', 'skill audit', 'skill 중복', 'skill 추가/삭제'."
---

# Skill Audit Workflow

`.claude/skills/`는 시간이 가면 비대해진다. 분기 1회 audit으로 정리.

## 점검 항목

1. 한 skill = 한 의도? (description 두 줄 이상이면 분리 후보)
2. 트리거 description 명확성 — 키워드 5~10개로 좁혀져 있는가
3. 위치 적정성 — global / personas / workflows / vendor / meta
4. references / scripts 동기화
5. 사용 빈도 — 6개월 미사용 skill 폐기 후보

## 출력 포맷

```markdown
# Skill Audit YYYY-MM-DD

## 통계
- 총 skill: N (그룹별 분포)

## 문제 항목
| Skill | 문제 | 권고 |

## 신규 후보
- mistakes/* 분석에서 도출된 신규 페르소나/워크플로우 후보
```
