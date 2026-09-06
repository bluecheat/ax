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

### Universal seeds — opt-in 활성화

`_templates/spirit/` 에 universal opt-in 시드가 들어 있어요. plugin 이 자동 적용 X — 사용자가 명시적으로 `rules/` 으로 복사해서 활성화해요:

```bash
cp .ax/_templates/spirit/ops.md .ax/spirit/rules/ops.md
```

현재 제공되는 universal seed:
- `ops.md` — SP-OPS-001~007 (MANDATORY 행동지시 / Generator-Evaluator 분리 / 워닝 무시 금지). 어느 프로젝트나 통하는 universal 행동 룰.

복사 후 본문은 자유롭게 수정 가능해요. 다음 plugin 업데이트 시 시드는 `_templates/` 에만 갱신되니, `rules/` 의 사용자 버전은 보존돼요.

### 새 룰 카테고리 추가
```bash
cp .ax/_templates/spirit/rule.md .ax/spirit/rules/observability.md   # 예: observability
```
→ frontmatter(`category`·`applies_to`·`paths`·`severity`·`enforced_by`)를 채우고 본문에 `## SP-<CAT>-<NNN>: 제목` 헤더로 룰 작성. `audit` 의 룰 승격(3단계)이나 `onboarding` 이 자동으로 만들어주기도 해요.

### 검증
"spirit 점검" 또는 "spirit lint" 라고 말하면 `doctor` 가 이 절만 보고해요 (frontmatter + `## SP-CAT-NNN:` 헤더 형식 + 토큰 중복 검증):
```bash
bash .ax/scripts/bash/spirit-lint.sh --json
```

### 기존 룰 검색
"rules 보여줘" · "CRITICAL 룰만" · "SP-SEC-001 찾아줘" 라고 말하면 `doctor` 가 `rules-index.sh` 출력을 그대로 보여줘요 (Constitution + Spirit + Module 통합 인덱스):
```bash
bash .ax/scripts/bash/rules-index.sh                          # 전체 인덱스
bash .ax/scripts/bash/rules-index.sh --level critical         # CRITICAL 만
bash .ax/scripts/bash/rules-index.sh --source spirit --category security
bash .ax/scripts/bash/rules-index.sh --find SP-SEC-001        # 토큰 정확 매칭
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
```
"goax up" 재실행 (또는 "/up")   # idempotent update — 없는 파일만 채워 넣어요, 기존 customize 는 안 건드려요
```
plugin 컨텍스트 밖에서 직접 복원하려면: `bash scripts/provision.sh --target <프로젝트 경로> --json`.

## 변경 시

`spirit/` 변경은 `protected_paths`에 포함되어 명시적 사용자 승인 필요.
중요한 변경(values 변경 등)은 ADR로도 기록 권장.
