# .ax/spirit/

> 모든 sub-agent가 공유하는 **태도·문화·일하는 방식**.
> Constitution(`CLAUDE.md`)이 "무엇을 하면 안 되나"라면, spirit은 "어떻게 일하나".

## 구조

```
.ax/spirit/
├── values.md         # 핵심 가치 5~7개 (메타)
├── tone.md           # 협업 톤 — 말투·답변 구조 (메타)
└── rules/            # 카테고리별 실제 룰 (사용자가 add/remove)
    ├── security.md
    ├── naming.md
    ├── pr.md
    ├── testing.md
    └── ...
```

## 사용자 워크플로우

### 새 룰 카테고리 추가
```bash
goax spirit add <category>     # 예: goax spirit add observability
```
→ `rules/observability.md` 템플릿이 생성됨. 본문에 룰 작성.

### 검증
```bash
goax spirit lint               # frontmatter + ID 일관성 검증
goax spirit                    # values/tone/rules 카운트 요약
```

### 기존 룰 검색 (rules CLI 통합)
```bash
goax rules                              # CLAUDE.md + spirit/rules/ 통합
goax rules --source spirit              # spirit/rules/만
goax rules --category security          # 카테고리 필터
goax find SP-SEC-001                    # 특정 룰
```

## Triage가 자동 주입

`/triage` 또는 `goax triage` 실행 시 `spirit_context`로 자동 첨부:
```yaml
spirit_context:
  values: .ax/spirit/values.md       # 항상
  tone: .ax/spirit/tone.md           # 항상
  rules:                             # applies_to 매칭된 것만
    - .ax/spirit/rules/security.md
    - .ax/spirit/rules/error-handling.md
```

→ persona는 받은 spirit_context를 작업 컨텍스트에 포함.

## 강제 차단

`.ax/spirit/values.md` 또는 `tone.md` 누락 시 `goax triage`가 **fail**.
다음으로 복구:
```bash
goax up --force      # spirit 디렉토리 + 샘플 복원
```

## 변경 시

`spirit/` 변경은 `protected_paths`에 포함되어 명시적 사용자 승인 필요.
중요한 변경(values 변경 등)은 ADR로도 기록 권장.
