# Spirit — v0.3 설계 plan

> **상태**: v0.3 plan (확정). 본 구현은 v0.2 push 직후 별도 sprint.
> "팀원이 각자 역할이 달라도 팀의 문화·일하는 방식·컨벤션은 같다."
> goax의 모든 persona/skill/agent도 같은 **Spirit**으로 움직인다.

---

## 1. 정의 (What)

**Spirit** = 여러 sub-agent가 서로 다른 역할(persona)을 맡아 동작하더라도, 그 결과물이 **하나의 일관된 팀에서 나온 것처럼 보이게** 만드는 cross-cutting 행동 가이드.

| 구분 | 무엇을 결정하는가 | 어디에 기록 |
|---|---|---|
| **Constitution** (Layer 1) | "무엇을 해야 하는가" — 핵심 비협상 룰 (3\~5개) | `CLAUDE.md` |
| **Persona / Skill** | "어떻게 일하는가" — 도메인별 사고법 | `.ax/skills/personas/<role>/SKILL.md` |
| **Spirit** | **"어떤 태도로 일하는가"** — 모든 역할 공통 + 그 외 모든 룰 | **`.ax/spirit/`** (신규) |

비유: 회사 사규(CLAUDE.md, 핵심만) + 사풍·문화·세부 가이드(spirit) + 직무별 매뉴얼(persona).

---

## 2. 7개 설계 결정 (확정)

| # | 결정 | 사유 |
|---|---|---|
| 1 | **CLAUDE.md ↔ spirit 중첩** (옵션 C) | 핵심 3\~5 CRITICAL은 root, 나머지는 spirit. 사용자는 새 룰 던지기 편함 + 정말 중요한 건 root에서 즉시 보임 |
| 2 | **1 파일 = 1 카테고리** (옵션 B) | naming.md, security.md, pr.md, testing.md 등. 응집도 ↑, 파일 수 적음 |
| 3 | **spirit/ 직속 values.md, tone.md 별도** (옵션 B) | values·tone은 룰이 아니라 메타라 별도 파일. rules/는 실제 코드/PR 규칙만 |
| 4 | **fail 강제 차단** (옵션 B) | spirit 누락 = 작업 거부. soft warning은 무시되기 쉬움 |
| 5 | 본 문서 v0.3 plan 초석 유지 (옵션 A) | 본 구현 시 보강 |
| 6 | **Triage가 spirit context 자동 주입** (옵션 B) | `/triage` 결과에 `spirit_context: [...]` — persona는 자동으로 받음 |
| 7 | **`goax rules` 통합 + `--source` 필터** (옵션 C) | 통합 인덱스 + 필요 시 출처 필터 |

---

## 3. 디렉토리 구조 (확정)

```
your-project/
├── CLAUDE.md                            # Constitution — 3~5 CRITICAL만 + 4계층 인덱스
└── .ax/
    ├── spirit/                          # ★ v0.3 신규
    │   ├── README.md                    # "이 디렉토리에 룰 파일 던지면 됨" 안내
    │   ├── values.md                    # 핵심 가치 5~7개 (사용자 작성 + 샘플 제공)
    │   ├── tone.md                      # 협업 톤 (사용자 작성 + 샘플 제공)
    │   └── rules/                       # 카테고리별 룰 파일 (사용자 add/remove)
    │       ├── naming.md
    │       ├── security.md
    │       ├── pr.md
    │       ├── testing.md
    │       ├── error-handling.md
    │       └── ...
    ├── skills/, agents/, hooks/, config.yml, mistakes/   # (v0.2 그대로)
    └── ...
```

---

## 4. rules/<category>.md 파일 컨벤션

### Frontmatter

```yaml
---
category: security              # 파일명과 일치
applies_to: [code, pr, commit]  # 어디 단계에서 적용
adr: docs/adr/0012-secrets-handling.md   # (선택) 결정 근거
---
```

### 본문 — 카테고리 안 여러 룰

```markdown
# Security

## SP-SEC-001: Secrets는 환경변수 또는 vault 경유
hardcoded password / api_key / token 금지.

✅ `process.env.API_KEY`
❌ `const KEY = "sk-..."`

## SP-SEC-002: 인증 우회 금지
인증 검사를 주석으로 비활성화하지 않는다 (`// @ts-ignore` 등).

## SP-SEC-003: 입력 검증은 경계에서
모든 외부 입력은 schema validation 후 사용 (zod, valibot 등).
```

### 룰 ID 컨벤션

`SP-<CATEGORY>-<id>` (3자리). 예:
- `SP-SEC-001` security #1
- `SP-PR-003` pr 카테고리 #3
- `SP-NAMING-007`

`goax rules`/`find`가 v0.2 토큰 컨벤션과 동일 형식으로 검색 가능.

---

## 5. spirit/values.md 샘플 (init 시 깔림)

> 사용자 답 #3에서 명시 요청한 항목 박아둠

```markdown
# Values — 모든 sub-agent가 공유하는 핵심 가치

> 이 가치들은 모든 persona/skill/agent에 자동 주입된다.
> 자기 팀에 맞게 추가·삭제·교체.

## 1. 긍정 편향 금지
사용자가 좋아할 답을 하지 않는다. 자기 결과물을 "잘 됐어요"로 마무리하지 않는다.
사용자 의도와 결과의 차이가 있으면 먼저 그 차이부터 명시한다.

## 2. 비판적 사고
요청을 그대로 수행하기 전에 한 단계 의심:
- 이 요청 자체가 옳은가?
- 더 좋은 길이 있는가?
- 사용자가 모르는 위험이 있는가?
의심 결과 다른 길이 더 낫다고 판단되면 즉시 제안한다.

## 3. 결과 → 근거 → 다음 액션
답변 구조는 항상 결과(무엇을 했는가) → 근거(왜) → 다음 액션 순.

## 4. 추측 대신 질문
모르는 것을 추측으로 메우지 않는다. 모호한 지점이 있으면 먼저 질문한다.

## 5. 작은 단위
한 번의 변경 = 한 의도. 리팩토링 + 기능 + fix를 섞지 않는다.

## 6. 자가 점검 우선
작업 종료 직전, 결과를 사용자에게 넘기기 전에 본인이 먼저 검토한다.
"내가 틀렸을 가능성"을 가장 먼저 적는다.
```

---

## 6. spirit/tone.md 샘플 (init 시 깔림)

> 사용자 답 #3에서 명시 요청한 "~해요 체" 박아둠

```markdown
# Tone — 모든 sub-agent의 공통 말투

## 기본 어체
**~해요 체** (해요/이에요/입니다 X). 친근하면서 전문적.

✅ "이 옵션은 hooks에서 자동으로 차단해요."
❌ "이 옵션은 hooks에서 자동으로 차단합니다."
❌ "이 옵션은 hooks에서 자동으로 차단함."

## 코드/명령 인용
백틱으로 감싸고 그 다음에 한국어 설명. 문장 시작은 코드로 가능.

✅ "`goax rules` 로 전체 룰을 볼 수 있어요."

## 거절·제약
거절하거나 제약을 알릴 때도 ~해요 체 + 다음 액션 제시.

✅ "이 sandbox에선 push가 막혀 있어요. 너의 macOS 터미널에서 한 줄 실행해주세요."
❌ "Sandbox에서는 push가 불가능합니다. 직접 실행하세요."

## 자기 검토
자기 결과를 보고할 때 단정하지 않고 의심 여지를 남긴다.

✅ "smoke 통과했지만 macOS 환경에선 다를 수 있어요. 한 번 더 실행해주세요."

## 한국어/영어 혼용
기술 용어는 영어 그대로, 그 외는 한국어. 인용/명령은 백틱.

## 안티 패턴
- "~합니다", "~할 수 있습니다" → 너무 격식
- "~함", "~임" → 너무 짧음/딱딱
- "✨", "🎉" 같은 과한 이모지 → 긍정 편향 신호
- "잘 됐어요!", "완벽해요!" 같은 자가 칭찬 → §1 위반
```

---

## 7. 진입점 강제 (옵션 4-B fail)

### Triage가 자동 주입 (옵션 6-B)

```yaml
# /triage 출력 (v0.3에서 확장)
size: M
risk: L1
domain: api
suggested_persona: engineer-generalist
critical_rules_to_check: [AX:CRITICAL:001, ...]
spirit_context:                              # ★ v0.3 신규
  values: .ax/spirit/values.md               # 항상
  tone: .ax/spirit/tone.md                   # 항상
  rules:                                     # applies_to 매칭된 것만
    - .ax/spirit/rules/naming.md
    - .ax/spirit/rules/error-handling.md
human_gate: false
```

### Spirit 누락 시 작업 차단

```bash
$ goax triage "북마크 정렬 추가"
[goax] ✗ .ax/spirit/ 디렉토리가 비어있음.
            최소 values.md + tone.md 가 필요.
            → goax up --force 또는 spirit/ 직접 작성 후 다시 시도.
```

### `pre-edit/spirit-check.sh` (신규 hook)

변경 파일에 적용되는 spirit rule이 있는데 **위반 패턴** 정규식 매칭되면 staged 차단:

```bash
# spirit/rules/naming.md에서 정의한 패턴
if grep -E '<위반-regex>' "$staged_file"; then
    echo "[spirit] SP-NAMING-002 위반: $staged_file"
    exit 1
fi
```

> 모든 룰에 검출 정규식이 있는 건 아니므로, 정의된 룰만 hook이 처리. 나머지는 inferential evaluator agent가.

---

## 8. CLI (v0.3 신규)

```bash
goax rules                              # CLAUDE.md + spirit/rules/ 통합 인덱스
goax rules --source constitution        # CLAUDE.md만
goax rules --source spirit              # spirit/rules/만
goax rules --category security          # 카테고리 필터

goax spirit                             # spirit/ 상태 요약 (values/tone/rules 카운트)
goax spirit add <category>              # 새 룰 카테고리 파일 템플릿 생성
goax spirit lint                        # rules/* frontmatter + ID 일관성 검증
goax spirit drift                       #  같은 카테고리 mistake 누적 추세
```

---

## 9. v0.2 → v0.3 마이그레이션

**기존 v0.2 사용자가 v0.3으로 갈 때**:

1. `goax update` (goax 자체 갱신)
2. 기존 CLAUDE.md의 일부 CRITICAL/MANDATORY/CONVENTION → spirit/rules/ 카테고리별로 이동
   - 핵심 3\~5개 CRITICAL만 root에 남김
   - `goax spirit migrate` (옵션 — v0.3.1)이 자동 분류 제안
3. `goax init --force --upgrade` — spirit/ 디렉토리 + values.md/tone.md 샘플 추가
4. `goax doctor` 점수 갱신 확인

---

## 10. v0.3 작업 항목 (실제 구현 시)

| # | 항목 | 추정 |
|---|---|---|
| 1 | `templates/default/.ax/spirit/{values.md, tone.md, README.md, rules/}` 신설 + 샘플 6\~8개 카테고리 | 8 파일 |
| 2 | `bin/goax-spirit` 신설 (add/lint/drift 서브 명령) | 1 bin |
| 3 | `lib/rules.sh` 확장 — `--source spirit` 필터 + spirit/rules/ 스캔 | 1 lib edit |
| 4 | `lib/classify.sh` 확장 — output에 `spirit_context` 추가 | 1 lib edit |
| 5 | `bin/goax-init` 갱신 — spirit/ 디렉토리 + 샘플 복사 + spirit 누락 fail | 1 bin edit |
| 6 | `bin/goax-doctor` — spirit 검사 추가 | 1 bin edit |
| 7 | `templates/default/.ax/hooks/pre-edit/spirit-check.sh` 신설 | 1 hook |
| 8 | persona SKILL.md 도입부에 "spirit context는 triage가 자동 주입" 1줄 | 4 persona edit |
| 9 | `templates/default/.ax/skills/global/triage/SKILL.md` 갱신 — output에 spirit_context 명시 | 1 skill edit |
| 10 | `tests/smoke.sh` 7번째 섹션 (spirit 검증) | 1 test edit |
| 11 | `CHANGELOG v0.1.0` | 1 file edit |

총 \~20 파일 변경. 1\~2 round.

---

## 11. 첫 도그푸딩 — `commerce-monorepo` 적용 시 spirit 미리보기

> 이건 stone 본인의 메모리. 코드/문서엔 박지 않음.

`projects/commerce`에 v0.3 적용 시 `.ax/spirit/rules/` 카테고리 후보:

| 카테고리 | 핵심 룰 |
|---|---|
| `architecture.md` | 모듈 의존 방향 (Apps→Adapter→Event→Data→Core→Util), Clean Arch 패키지 |
| `domain.md` | UseCase는 interface, Repository 위치 |
| `migration.md` | DDL 변경 시 V{UTC}__*.sql 동반 |
| `testing.md` | Kotest DescribeSpec + MockK, integration tag 필수 |
| `security.md` | Secrets 차단, 결제 도메인 traffic estimation |
| `pr.md` | 한국어 PR 템플릿, 두 번째 리뷰어 (cross-domain) |
| `commit.md` | type 접두사, 한국어 |

→ commerce-monorepo는 v0.2 push 끝나면 도그푸딩 들어감. 그때 v0.3 spirit 카테고리도 같이 채움.

---

## 참고

- v0.2 release: personas + references + rules CLI + 룰 토큰 (현재 push 대기)
- v0.3 본 구현 시점: v0.2 push 후
- 본 plan은 답 7개 + 샘플 미리보기 확정. 본 구현 시 변경 사항 있으면 ADR로 기록.
