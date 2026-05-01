---
name: skill-creator
description: "새 persona / workflow / meta skill 만들 때 frontmatter 표준 + 트리거 작성법 + 그룹 선택 가이드. 트리거: '새 skill', 'skill 추가', 'create skill', 'new persona', '페르소나 만들기'."
---

# Skill Creator (meta)

> 새 skill을 만들 때 한 폴더 = 한 의도 패턴(한 폴더 = 한 의도, 트리거-first description, references 분리)을 지키도록 안내.

## When to use

- 사용자가 "X 페르소나 만들어줘" 요청
- mistakes audit 결과 특정 카테고리가 반복 → 신규 persona 후보
- workflow 자동화 — 반복되는 명령 시퀀스를 skill로

## 그룹 선택

| 의도 | 그룹 | 예 |
|---|---|---|
| 도메인/역할 페르소나 | `personas/` | code-reviewer, payment-engineer |
| 일상 작업 절차 | `workflows/` | adr-write, commit, deploy |
| 진입점 / 항상 활성 | `global/` | triage, critical-rules, steering-loop |
| skill 자체를 다루는 도구 | `meta/` | skill-creator, skill-audit |
| 외부에서 빌려온 룰셋 | `vendor/` | (skills-lock.json 관리) |

## SKILL.md 프론트매터 표준

```yaml
---
name: <kebab-case>
description: "한 줄 요약 (의도). 트리거: '키워드1', '키워드2', '...' (5~10개)."
---
```

**description 작성 규칙**:
- 첫 문장: 한 줄 의도 요약
- "트리거: " 뒤에 5\~10개 키워드 — 한국어/영어 혼합 OK
- 다른 skill과 트리거 중복 검사

## SKILL.md 본문 표준

```markdown
# <이름>

> 한 줄 핵심 명제

## When to use
- (트리거 시나리오 3~5개)

## Workflow / Output / Checklist
- (실제 작업 가이드)

## When NOT to use
- (다른 skill로 위임할 케이스)

## 안티 패턴
- (자주 빠지는 함정)
```

## references/ 분리 기준

- SKILL.md가 100줄 넘어가면 references/ 분리 후보
- 매트릭스/표/긴 예시는 references/<topic>.md
- SKILL.md는 트리거+Workflow에 집중

## scripts/ 추가 (선택)

skill에 helper script가 필요하면 `<skill>/scripts/<name>.{sh,py}` 추가. SKILL.md에서 호출 방법 명시.

## 검증

새 skill 추가 후:

```bash
goax doctor
# (skill 자체에 대한 audit이 필요하면)
# goax audit --skill <name>   (v0.3 예정)
```

## 안티 패턴

- description에 트리거 키워드 누락 → 매칭률 ↓
- 한 SKILL.md에 여러 의도 → 라우팅 혼란
- references/ 없이 200줄 SKILL.md → 매번 풀 텍스트 컨텍스트 소비
- 다른 skill과 트리거 키워드 중복 → 우선순위 모호
