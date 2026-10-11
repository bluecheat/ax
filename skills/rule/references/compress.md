# 압축 모드

룰 파일이 길어져 세션마다 실리는 양이 기준을 넘었을 때, 규범은 그대로 두고 글만 줄여요.
이 모드는 룰을 지우거나 합치지 않아요. 룰을 지우거나 합치려면 사용자가 따로 정하고 새로 쓰기 모드로 가요.

## 1. 얼마나 실리는지 재기

```bash
BUDGET=$(bash .ax/scripts/bash/rules-budget.sh --json)
printf '%s\n' "$BUDGET" | jq '.result | {always, edit, over_budget}'
```

| 값 | 뜻 | 기준 |
|---|---|---|
| `always` | 세션 시작부터 실리는 CLAUDE.md · AGENTS.md · import 파일 | 300줄 또는 16KB (goax 기본 설치가 약 220줄 · 11.5KB) |
| `files[]` | 룰 파일마다 줄 · 바이트 · SP 수 · 펜스 비율 | 150줄 또는 8KB, 펜스 30% |
| `edit` | 파일 하나를 고치기 전에 Read 해야 하는 룰 바이트 (p50 · p90 · max) | p90 24KB |

이 skill 은 `over_budget[]` 를 표로 보여주고, 줄일 파일을 사용자와 정해요. 기본은 `over_budget` 에 나온 파일 전부예요.
`always` 가 넘으면 import 된 룰 파일(`@.ax/spirit/rules/…`)이 원인인지 봐요. import 된 룰은 편집 때 주입되는 룰로 바꿀 수 있어요 (import 줄을 지우고 `paths:` 를 채워요). 이 변경은 AGENTS.md 를 고치는 일이라 사용자 확인을 따로 받아요.

## 2. 사본 잡기

```bash
bash .ax/scripts/bash/rules-compress.sh --snapshot --json .ax/spirit/rules/<a>.md .ax/spirit/rules/<b>.md
```

사본은 `.ax/.rules-snapshot/` 에 있어요 (gitignore 대상). 백업 파일은 만들지 않아요. 되돌리기는 git 이에요.

## 3. 줄이기

파일마다 먼저 지적을 봐요.

```bash
bash .ax/scripts/bash/rule-lint.sh --json .ax/spirit/rules/<a>.md | jq -r '.result.findings[] | "\(.line) [\(.kind)] \(.id) \(.text)"'
```

룰 블록마다 아래 순서로 고쳐요. 한 번에 한 파일씩 Edit 해요.

| 지적 | 고치는 방법 |
|---|---|
| `trace` (날짜 · 해시 · PR 번호 · 세션 경위) | 문장을 지워요. 근거가 꼭 필요하면 `이유:` 한 줄로 바꿔요 |
| `adr` (ADR 결정 서술 문단) | 문단을 지우고 `<!-- adr: … -->` 한 줄을 남겨요. ADR 파일이 없으면 지우기 전에 사용자에게 물어요 |
| `length` · `examples` (본문 8줄 초과, 예시 여러 쌍, 긴 펜스) | 검출 패턴이 없는 룰: 규범 1–3줄과 ❌/✅ 한 쌍만 남기고, 나머지 예시는 `.ax/spirit/references/<category>.md` 의 `## SP-…` 절로 옮겨요. 룰에는 `자세한 예: .ax/spirit/references/<category>.md` 한 줄을 남겨요. 검출 패턴이 있는 룰: ❌/✅ 는 프로브가 쓰므로 그대로 두고, 규범 문장과 설명만 줄여요. 남은 지적은 보고에 "프로브용 예시" 로 적어요 |
| `metaphor` · `dots` | 비유를 사실 문장으로 바꾸고, `·` 나열은 표나 목록으로 바꿔요 |
| `marker` (검출 패턴에 한글 문장) | 패턴은 바꾸지 않아요. 사용자에게 "산문 패턴이라 아무것도 막지 않아요" 라고 알리고, 고치는 일은 새로 쓰기 모드로 넘겨요 |
| `harness` (goax 에이전트·게이트 지시) | 그대로 두고 사용자에게 goax 이슈 후보로 알려요 |

바꾸면 안 되는 것 — `--verify` 가 확인해요:

- SP ID 와 순서, frontmatter 전체 (`paths`, `severity`, `enforced_by` 포함)
- `<!-- 검출 패턴: … -->` 줄과, 검출 패턴이 있는 룰의 ❌/✅ 예시
- `<!-- adr: … -->` 링크

제목은 바꿀 수 있지만, 바꾼 제목은 `--verify` 가 warnings 로 돌려줘요. 이 skill 은 바뀐 제목을 사용자에게 보여줘요.

`.ax/spirit/references/<category>.md` 는 편집 때 주입되지 않고 Read 게이트도 걸지 않아요. 룰이 이 파일을 링크하면, 모델은 필요할 때만 Read 해요.
새로 만들 때 첫 줄은 `# <category> 룰 예시 — 규범은 .ax/spirit/rules/<file>.md` 예요.

## 4. 확인

```bash
VERIFY=$(bash .ax/scripts/bash/rules-compress.sh --verify --json)
printf '%s\n' "$VERIFY" | jq '{status, errors, warnings, saved: .result.saved_bytes}'
```

- `status: error` 면 `errors[]` 가 가리키는 곳을 사본(`.ax/.rules-snapshot/<경로>`)과 비교해 되돌려요. 다시 `--verify` 해요.
- `status: ok` 면 `rule-lint` 를 다시 돌려 지적 수가 줄었는지 보고, `rules-budget.sh` 를 다시 돌려 전후를 비교해요.

## 5. 사용자 확인

이 skill 은 파일별 전후 바이트, 남은 지적 수, `git diff --stat` 을 보여주고 Y/n 을 받아요.

- Y: `bash .ax/scripts/bash/rules-compress.sh --clear --json` 으로 사본을 지워요. 커밋은 사용자가 정해요.
- n: `git checkout -- <파일>` 로 되돌리고 (references 파일을 새로 만들었으면 그것도 지워요) 사본을 지워요.

보고 예:

```
✅ 룰 파일 3개 압축 — 41,395B → 22,870B (−18,525B)
📂 예시 이동: .ax/spirit/references/data.md (SP-DATA-003 · 007 · 011)
❗ 남은 지적: marker 2건 (SP-CHAT-001 · SP-SLACK-002) — 산문 패턴이라 새로 쓰기 모드로 고쳐요
```
