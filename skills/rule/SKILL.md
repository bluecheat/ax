---
name: rule
description: "룰을 새로 쓰거나, mistake 를 룰로 바꾸거나, 길어진 룰 파일을 줄일 때 써요. 트리거: '/rule', '룰로 만들어', '룰 추가', '이거 룰로 박아', 'mistake 를 룰로', 'SP 추가', '룰 압축', '룰이 길어', '룰 정리'. 안 쓰는 경우: 쌓인 실수의 회고·패턴 찾기·승격 후보 고르기(audit), 실수 1건 기록(mistake), 룰이 걸려 있는지·주입되는지 점검(doctor)."
---

# Rule Skill

룰 하나를 고정 틀로 쓰고, 길어진 룰 파일을 줄여요. 룰을 쓰는 길(audit 승격, onboarding 시드, 세션 안 요청)은 모두 이 skill 을 거쳐요.

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 를 따라요. 두 파일이 없으면 이 skill 은 시작하지 않고 `/up` 을 안내해요.
글쓰기 기준은 `.ax/docs/reference/writing-for-agents.md` 예요. 이 skill 이 쓰는 룰 본문과 사용자에게 보이는 문장 모두 그 기준을 따라요.

## 모드 고르기

| 사용자 요청 | 모드 |
|---|---|
| "이거 룰로 만들어", "SP 추가", 자유 문장으로 규칙을 말함 | 새로 쓰기 (§1–§7) |
| "mistake 를 룰로", mistake 파일 경로를 줌, audit §4 가 넘김 | mistake → 룰 (§1–§8) |
| "룰 압축", "룰이 길어", "룰 정리", doctor 가 예산 초과를 알림 | 압축 (`references/compress.md`) |

## 1. 사실 모으기 — `rule-draft.sh`

```bash
DRAFT=$(bash .ax/scripts/bash/rule-draft.sh --json --category "$CATEGORY" --title "$TITLE_DRAFT")
# mistake → 룰이면:
DRAFT=$(bash .ax/scripts/bash/rule-draft.sh --json --from-mistake .ax/mistakes/<파일>.md [<파일>…])
printf '%s\n' "$DRAFT" | jq '.result'
```

카테고리를 모르면, 이 skill 은 `ls .ax/spirit/rules/` 결과를 보여주고 사용자에게 고르게 해요.
`result` 에서 쓰는 값:

| 필드 | 쓰는 곳 |
|---|---|
| `target.file` · `target.exists` | 룰을 넣을 파일. `exists:false` 면 §4 에서 `.ax/_templates/spirit/rule.md` 를 복사해 만들어요 |
| `next_id` | 새 룰의 ID. `null` 이면 접두사를 사용자와 정해요 (대문자 4자 이내) |
| `similar[]` | 제목 낱말이 겹치는 기존 룰. §2 에서 써요 |
| `mistakes[].summary` · `paths` · `pattern` | 룰 제목 초안, frontmatter `paths:` 후보, 검출 패턴 초안 |
| `enforcement` | `grep` 이면 결정형 후보, `human` 이면 비결정형 후보 (§3) |

## 2. 기존 룰과 겹치는지 보기

`similar` 가 비어 있지 않으면, 이 skill 은 해당 룰 본문을 Read 하고 AskUserQuestion 으로 물어요.

- 기존 룰 보강 — 그 룰의 본문이나 예시를 고쳐요. 새 ID 를 만들지 않아요.
- 새 룰 — 기존 룰과 무엇이 다른지 한 줄로 적고 §3 으로 가요.
- 둘이 서로 반대 방향이면 — 모순 후보라고 알리고, 어느 쪽을 남길지 사용자가 정해요.

이유: 같은 규칙이 ID 두 개로 갈라지면 주입량이 두 배가 되고, 한쪽만 고쳐질 때 서로 어긋나요.

## 3. 결정형인지 비결정형인지 정하기

| 판정 | 조건 | 룰에 쓰는 것 |
|---|---|---|
| 결정형 | 위반이 코드 한 줄의 모양으로 드러나고, ERE 한 줄로 ❌ 는 잡히고 ✅ 는 안 잡혀요 | `<!-- 검출 패턴: <ERE> -->`, frontmatter `enforced_kind: grep` |
| 비결정형 | 위반을 알아보려면 맥락(호출 관계, 의도, 설계)이 필요해요 | 검출 패턴 없음, `enforced_by: human:review`, `enforced_kind: human` |

`enforcement: grep` 이어도 패턴이 너무 넓으면(일반 코드에서 오탐이 날 모양) 비결정형으로 내려요.
비결정형 룰은 완료 직전 `rules-auditor` 가 변경 파일과 대조해요 (tasks-gate G7). 그래서 비결정형 룰은 사람이 읽고 판정할 수 있게 조건과 행동을 구체적으로 써요.
severity 가 critical 인 룰은 결정형이어야 해요 (invariant I1). 결정형으로 만들 수 없으면, 이 skill 은 severity 를 mandatory 로 제안해요.

## 4. 고정 틀로 쓰기

```markdown
## SP-<PREFIX>-<NNN>: <규범 한 줄>

<조건>에서, <주어>는 <행동>해요.
이유: <한 줄>

❌ `<나쁜 예 한 줄>`
✅ `<좋은 예 한 줄>`

<!-- 검출 패턴: <ERE> -->              ← 결정형만
<!-- adr: .ax/docs/adr/<id>-<slug>.md --> ← 근거 ADR 이 있을 때만
```

- 제목은 지켜야 할 행동 한 문장이에요. 사건 이름, 경위, "~금지합니다" 같은 완곡한 꼬리를 쓰지 않아요.
- 본문은 1–3줄, 헤더 아래 8줄을 넘기지 않아요. 넘으면 예시를 `.ax/spirit/references/<category>.md` 로 옮기고 `자세한 예: .ax/spirit/references/<category>.md#sp-…` 한 줄을 남겨요. 결정형 룰(검출 패턴이 있는 룰)은 ❌/✅ 를 옮기지 않아요. 프로브가 그 예시를 써요. 결정형 룰이 8줄을 넘으면 규범 문장과 설명만 줄이고, 예시가 여러 쌍이면 그대로 둔 채 사용자에게 "예시 N쌍이 프로브용이라 남겼어요" 라고 알려요.
- ❌/✅ 는 백틱 안에 실제 코드 한 줄이에요. `"..."` 같은 자리표시자는 프로브가 쓸 수 없어요. 시크릿 류 예시 값만 `"<plain-value>"` 처럼 `<…>` 로 감싸요. 이유: 룰 파일 자체가 시크릿 스캐너에 걸리지 않게 해요.
- 날짜, 커밋 해시, PR·이슈 번호, 세션 경위는 쓰지 않아요. 그 내용은 mistake 파일이나 ADR 에 남아 있어요.
- goax 에이전트·skill·게이트(lane-worker, evaluator, spec-validate, tasks-gate …)에 대한 지시는 룰로 쓰지 않아요. 이 skill 은 사용자에게 "goax 에서 고칠 일" 이라고 알리고 멈춰요.

대상 파일이 없으면 `.ax/_templates/spirit/rule.md` 를 복사해 frontmatter 를 채워요. `paths:` 는 `result.paths` 의 확장자·디렉토리로 좁게 잡아요. 비우면 편집 때 주입되지 않아요.
module 룰(`.ax/modules/<name>/rules.md`)에 넣을 때도 같은 틀이에요.

## 5. 검사

쓴 뒤, 이 skill 은 아래를 차례로 돌려요. 하나라도 지적이 있으면 고치고 다시 돌려요.

```bash
bash .ax/scripts/bash/rule-lint.sh --json "$TARGET" | jq --arg id "$NEW_ID" '[.result.findings[] | select(.id == $id)]'
bash .ax/scripts/bash/spirit-lint.sh --json | jq '.result | {bad_headers, duplicates}'
# 결정형이면:
bash .ax/scripts/bash/zero-probe.sh --only pattern-rules --json | jq -r '.result.probes[] | select(.name=="pattern-rules") | .tail_lines[]' | grep "$NEW_ID"
```

- `rule-lint` 는 새 룰에 대한 지적이 0건이어야 해요. 같은 파일의 다른 룰 지적은 사용자에게 개수만 알려요 (압축 모드 안내).
- 프로브 줄이 `FAIL` 이면 패턴이나 예시를 고쳐요. `ok` 가 나올 때까지 §6 으로 가지 않아요. 이유: 재지 않은 패턴은 아무것도 막지 않아요.

## 6. 신입 테스트 — 비결정형 룰만

비결정형 룰은 읽는 모델의 판단에 기대요. 그래서 이 skill 은 새 컨텍스트의 작은 모델에게 룰을 읽혀 봐요.

Agent 도구로 `general-purpose` 를 `model: "haiku"` 로 띄우고, 아래만 넘겨요 (대화 맥락·mistake 는 넘기지 않아요).

```
아래 룰 하나와 코드 상황 두 개가 있어요. 상황마다 룰 위반인지 "위반/준수/판단 불가" 로 답하고, 근거를 룰 문장에서 인용해 한 줄로 적어요.
<룰 본문 전체>
상황 A: <룰이 잡아야 하는 상황 — mistake 의 실제 코드>
상황 B: <비슷하지만 룰 대상이 아닌 상황>
```

A 가 "위반", B 가 "준수" 가 아니면, 이 skill 은 룰의 조건이나 행동 문장을 고치고 한 번 더 돌려요. 두 번째도 다르면 결과를 사용자에게 보여주고 문장을 같이 정해요.

## 7. 사용자 확인 후 쓰기

이 skill 은 최종 룰 블록과 대상 파일을 보여주고 Y/n 을 받아요. Y 면 Edit 으로 넣어요 (기존 파일이면 마지막 룰의 `---` 뒤에 붙여요).
쓰고 나서 `grep -n "^## $NEW_ID:" "$TARGET"` 가 1줄이어야 해요.

## 8. mistake 정리 — mistake → 룰 모드만

```bash
bash .ax/scripts/bash/promote-mistake.sh --apply --json --token "$NEW_ID" --category "$CATEGORY" --file .ax/mistakes/<파일>.md
bash .ax/scripts/bash/promote-mistake.sh --archive --json --token "$NEW_ID"
```

`--file` 은 §1 에 넘긴 mistake 마다 하나씩 줘요. 주지 않으면 같은 카테고리의 다른 mistake 까지 마킹돼요.
같은 카테고리의 다른 mistake 는 그대로 `.ax/mistakes/` 에 남아요. 같은 원인이면 이 skill 은 사용자에게 "이 룰로 같이 정리할까요?" 라고 묻고, Y 면 그 파일도 `--file` 로 넘겨요. 아니면 다음 audit 이 다시 봐요.
`--archive` 는 룰 헤더가 파일에 있어야 진행해요. `SP token not found` 가 나오면 §7 이 안 끝난 거예요.
`mistakes[].promoted` 가 `true` 인 파일은 이미 다른 룰로 승격됐어요. 이 skill 은 그 파일을 마킹하지 않고 사용자에게 알려요.

## 9. 마무리

```bash
bash .ax/scripts/bash/update-state.sh --skill rule --json >/dev/null
```

보고는 세 줄이에요: 추가·수정한 룰 ID와 파일, 판정(결정형·비결정형)과 검사 결과, mistake 를 정리했으면 archive 건수.

## 하지 않는 것

- 룰 본문에 세션 경위를 남기지 않아요. 사용자가 "왜 생겼는지도 적어줘" 라고 하면 ADR(`adr` skill)을 제안하고, 룰에는 `adr` 링크 한 줄만 둬요.
- plugin 이 출고한 룰 파일이 아니라 프로젝트 룰 파일에만 써요.
- frontmatter 의 `severity`·`enforced_by` 를 사용자 확인 없이 바꾸지 않아요.
