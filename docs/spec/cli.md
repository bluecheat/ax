# Spec — CLI 인터페이스

goax의 모든 CLI 명령의 input/output·exit code 스펙.

## 공통

| 항목 | 값 |
|---|---|
| 환경변수 | `GOAX_ROOT` (필수, dispatcher가 자동 설정) / `GOAX_LIB` / `GOAX_TEMPLATES` |
| Exit 0 | 성공 |
| Exit 1 | 일반 실패 |
| Exit 2 | 잘못된 인자 |

## 명령별

### `goax init [--preset <name>] [--force]`

- input: 옵션
- 동작: 현재 디렉토리에 default 또는 preset 자산 복사. 기존 파일 보존 (단 `--force`는 덮어쓰기)
- output: stdout으로 진행 로그
- exit: 0 (성공) / 1 (template 누락 등)

### `goax up [--dry-run] [--auto a,a,a,a]`

- input: Brownfield 도입 — interactive 4-phase
- 동작: discover → plan(4 결정) → apply → next
- output: 각 phase별 진행 로그 + adoption-plan.md (Q1:a 시)
- exit: 0 / 사용자 취소 시 0 / discover 실패 시 1

### `goax triage <설명>`

- input: 자유 텍스트 (한국어/영어)
- 동작: `.ax/config.yml` domain_risk와 매칭 → Size×Risk 분류 → spirit_context 첨부
- output (yaml-like):
  ```
  size: S|M|L|XL
  risk: L0|L1|L2|L3
  domain: <매칭 키워드>
  suggested_path: ...
  required_sensors: [...]
  spirit_context:
    values: .ax/spirit/values.md
    tone: .ax/spirit/tone.md
    rules: [...applies_to 매칭...]
  human_gate: true|false
  ```
- exit: 0 (정상) / 1 (spirit MISSING — values.md/tone.md 누락)

### `goax rules [옵션]`

- 옵션: `--level <CRITICAL|MANDATORY|CONVENTION>`, `--scope <name>`, `--source <constitution|spirit>`, `--category <name>`, `--module <path>`, `--json`, `--untokenized`
- 동작: CLAUDE.md + `.ax/spirit/rules/*.md` 스캔
- output: 트리 형식 또는 JSON

### `goax find <token>`

- input: `<scope>:<LEVEL>:<id>` 또는 `SP-<CATEGORY>-<id>`
- 동작: 모든 룰 파일 스캔 → 첫 매칭 본문 + 다음 5줄 + ADR 링크
- exit: 0 / 1 (못 찾음)

### `goax spirit [add|lint|status]`

- `status` (default): values/tone/rules 카운트
- `add <category>`: `_TEMPLATE.md` 복사 + placeholder 치환
- `lint`: frontmatter + ID 일관성 검증
- exit: 0 / 1 (lint 실패)

### `goax audit`

- 동작: `.ax/mistakes/*.md` 카테고리별 누적 카운트 + 임계치 초과 권고

### `goax doctor`

- 동작: 4계층 + spirit + hooks + ADR 결손 검사 + 점수 출력

### `goax update`

- 동작: goax 자체 갱신 (`git fetch + reset --hard origin/main`)
