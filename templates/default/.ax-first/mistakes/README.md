# Mistakes — 캡처 슬롯

> AI 에이전트나 사람이 발견한 실수를 즉시 적재하는 디렉토리.
> 7일에 1회 `ax-first audit`로 일괄 심사하고, 같은 카테고리 3회 이상 반복되면 CRITICAL/MANDATORY로 승격.

## 파일 컨벤션

```
.ax-first/mistakes/
└── YYYY-MM-DD-NNN-<short-slug>.md
```

## 파일 템플릿

```markdown
---
category: <one-of: dependency-direction | hydration | n+1 | secrets-in-code | ...>
severity: <low | medium | high>
detected_by: <claude | reviewer | ci | self>
context_link: <PR URL or commit SHA>
---

# 무엇이 일어났나
한 줄 요약.

# 어디서
파일/모듈/도메인.

# 왜 발생
원인 분석.

# 어떻게 막을 수 있나
- 사람 리뷰로 막을 수 있나? (No → Sensor로 자동화 후보)
- 어떤 hook 또는 룰이 막아야 하나?
```

## 처리 후

심사 완료 + Constitution/ADR로 승격된 항목은 `_archive/`로 이동한다.

```
.ax-first/mistakes/
├── _archive/
│   └── YYYY/MM/...
└── (현재 활성 항목)
```
