---
name: spec-validate
description: "spec 명료성 게이팅 + 합의 리뷰 + 진행률 visibility — 'spec 확인', 'goax spec check', '스펙 게이트', '합의 리뷰', 'spec 리뷰', '--consensus'. spec.md 의 NEEDS CLARIFICATION + placeholder `<...>` + 빈 필수 섹션 3 항목을 게이팅하고, 그 뒤 size L/XL 은 architect → evaluator 를 새 컨텍스트로 순차·독립 리뷰(spec-review.sh 가 리뷰어별 verdict 파일과 sha 를 집계), M 은 '--consensus' 로 선택. tasks.md 진행률 + AC 진행률을 visibility 로 노출. 슬래시로도 호출 가능: '/spec-validate'."
---

# goax spec-validate — 명료성 게이팅 + 진행률 visibility

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## SSOT 원칙
spec.md 가 single source of truth.

**게이팅 (fail 시 진행 차단)**
- NEEDS CLARIFICATION 마커
- placeholder `<...>` 본문
- 빈 필수 섹션

**Visibility (게이팅 X — 사용자 인지용)**
- tasks.md 의 `- [ ]` / `- [x]` 비율
- spec.md §3 (성공 기준) AC 의 `- [ ]` / `- [x]` 비율

→ spec-implement 우회로 코드 commit 했는데 체크박스 동기화 안 한 케이스를 즉시 노출. "게이트가 거짓말 안 하기" 원칙.

## 발동
- "goax spec check"
- "spec 검사"
- "이 스펙으로 다음 단계 가도 돼?"

## 1. spec 디렉토리 식별

- 사용자가 번호/slug 명시: `goax spec check 005`
- 미명시: 가장 최근 수정된 `.ax/docs/spec/NNN-*/` 자동 선택, 사용자에게 "이 spec 맞아요?" 한 번 확인

## 2. 검사 — `check-spec-clarity.sh` 위임

```bash
RESULT=$(bash .ax/scripts/bash/check-spec-clarity.sh --json --spec "$SPEC")
STATUS=$(printf '%s\n' "$RESULT" | jq -r '.status')
NEEDS=$(printf '%s\n' "$RESULT" | jq -r '.result.needs_clarification')
PLACE=$(printf '%s\n' "$RESULT" | jq -r '.result.placeholders')
EMPTY=$(printf '%s\n' "$RESULT" | jq -r '.result.empty_sections | join(", ")')
TASKS_DONE=$(printf '%s\n' "$RESULT" | jq -r '.result.tasks_progress.completed')
TASKS_TOTAL=$(printf '%s\n' "$RESULT" | jq -r '.result.tasks_progress.total')
TASKS_OPEN=$(printf '%s\n' "$RESULT"  | jq -r '.result.tasks_progress.open')
AC_DONE=$(printf '%s\n' "$RESULT"     | jq -r '.result.ac_progress.completed')
AC_TOTAL=$(printf '%s\n' "$RESULT"    | jq -r '.result.ac_progress.total')
WARNINGS=$(printf '%s\n' "$RESULT"    | jq -r '.warnings // [] | join("; ")')
```

스크립트 검사 (게이팅 — fail 시 진행 차단):
- NEEDS CLARIFICATION 마커 잔존
- placeholder `<...>` 본문 잔존 (표 셀·URL 화이트리스트)
- 필수 섹션 (§1.1 한 줄 정의 / §3 성공 기준 / §4 사용자 시나리오) 본문 1 라인 이상

스크립트 visibility (status 영향 X — 누락 인지 신호):
- `tasks_progress`: tasks.md 의 `- [ ]` / `- [x]` 카운트
- `ac_progress`: spec.md §3 AC 의 `- [ ]` / `- [x]` 카운트

## 2.5 합의 리뷰 — 명료성이 통과한 뒤에만

계획의 품질은 diff 시점이 아니라 **계획 시점**에 리뷰해야 올라가요. OMC ralplan 의 구조를
가져왔어요 — 고정 스냅샷 하나를 Architect·Critic 이 독립·순차로 보고, 종합은 Planner(이 세션)만.
goax 가 얹은 건 둘이에요: 리뷰어는 §2 를 **통과한** spec 만 봐요(placeholder 지적에 리뷰어
컨텍스트를 쓰지 않아요), 그리고 verdict 가 대화가 아니라 **파일**에 남아 게이트가 읽어요.

### 발동 — Size 축만

```bash
REVIEW=$(bash .ax/scripts/bash/spec-review.sh --spec "$SPEC" --status --json)
REQ=$(printf '%s\n' "$REVIEW" | jq -r '.result.required')      # required (L·XL) | optional (M) | none (S)
```

| `REQ` | 할 것 |
|---|---|
| `none` | 건너뛰어요. S 는 리뷰 대상이 아니에요 |
| `optional` | 사용자가 이 대화에서 `--consensus`·"합의 리뷰" 라고 했거나, `current-task.json` 의 `intent_notes.consensus_review = "true"` (triage 의 M×L2 모호 영역 메뉴에서 켠 경우) 면 돌려요. 아니면 §3 으로 |
| `required` | 돌려요. `pass` 가 true 가 될 때까지 (라운드 상한 3) |

risk 는 안 봐요 — risk 는 구현 리뷰(evaluator, `tasks-gate.sh` G6)가 이미 반영해요.

### 한 라운드

```bash
SNAP=$(bash .ax/scripts/bash/spec-review.sh --spec "$SPEC" --snapshot --json)
SHA=$(printf '%s\n' "$SNAP" | jq -r '.result.sha')
A_FILE=$(printf '%s\n' "$SNAP" | jq -r '.result.architect_file')
E_FILE=$(printf '%s\n' "$SNAP" | jq -r '.result.evaluator_file')
printf '%s\n' "$SNAP" | jq -r '.warnings[]?'                    # 라운드 상한 경고
```

1. **architect** 를 `Agent` 도구로 띄워요 (`goax:architect`, vendor 설치면 `architect`). 브리프에는
   이것만: `$SPEC_DIR/spec.md` 경로 · `$SHA` · §7.5 진입 ADR 경로들 · **출력 파일 `$A_FILE`** ·
   "첫 줄 `verdict:` 둘째 줄 `sha: $SHA`". **`$E_FILE` 은 넣지 않아요.** 이 대화도 넣지 않아요.
2. architect 가 **끝난 뒤에** **evaluator** 를 띄워요 (`goax:evaluator`, spec 모드). 브리프: spec.md
   경로 · `$SHA` · ADR · tasks.md 가 있으면 그 경로 · **출력 파일 `$E_FILE`**. `$A_FILE` 은 넣지
   않아요. 둘을 한 메시지에 같이 띄우지 마세요 — 순차예요.
3. 집계해요:

```bash
REVIEW=$(bash .ax/scripts/bash/spec-review.sh --spec "$SPEC" --status --json)
PASS=$(printf '%s\n' "$REVIEW" | jq -r '.result.pass')
printf '%s\n' "$REVIEW" | jq -r '"architect \(.result.architect.verdict // "없음") · evaluator \(.result.evaluator.verdict // "없음") — \(.result.reason)"'
```

4. `pass=false` 면 두 파일을 **이 세션이** 읽고 종합해 spec.md 를 고쳐요. 고치면 sha 가 바뀌니
   §2 → `--snapshot` 부터 다시예요 (한쪽만 sha 가 어긋나면 그쪽만 다시 띄워요). `재논의 필요` 가
   하나라도 있으면 spec 자체가 틀렸다는 뜻이라 사용자 결정으로 halt. **round ≥ 3 이면 지적을
   더 반영하려 하지 말고 그 자체로 halt** — 라운드를 더 돌리는 건 리뷰가 아니라 spec 정의가
   문제라는 신호예요 (아래 "상한 3" 참조). `--snapshot` 응답의 `warnings[]` 가 상한 경고를 줘요.
5. `pass=true` 면 합본을 남기고 §3 으로:

```bash
bash .ax/scripts/bash/spec-review.sh --spec "$SPEC" --merge --json >/dev/null
```

### 왜 이 규칙인가

- **리뷰어별 파일** — 한 파일에 둘이 쓰면 첫 줄 verdict 하나로 "둘 다 진행" 을 못 담고, 뒤에 쓰는
  쪽이 앞 절을 읽게 돼요
- **순차·독립** — 앞 리뷰를 읽은 뒤 리뷰는 그 리뷰의 메아리예요. 합의가 아니라 동조가 돼요
- **sha 고정** — 리뷰 뒤에 spec 이 바뀌면 그 리뷰는 다른 문서에 대한 리뷰예요
- **상한 3** — 넘으면 리뷰가 아니라 spec 정의가 문제예요. 라운드를 더 돌리지 말고 사용자와 다시 정해요

## 3. 출력

### 통과 + tasks/AC 모두 0 (clean state)

```
✓ spec-validate 005-payment-refund-policy-change 통과

 📍 발견  NEEDS=0  placeholder=0  빈 섹션=0
 🧭 합의   L — architect 진행 · evaluator 진행 (round 1, sha 3f1a…)   ← required/optional 일 때만
 📊 진행률  tasks 0/0  AC 0/0 (미시작)
 🎯 결과  tasks 진행 가능

 다음 단계
 tasks.md 분해 → 구현 (/spec-tasks → /spec-implement)
 L3 도메인이라 ADR 동반 권장 — "ADR 0006 작성 도와줘"
```

### 통과 + 진행률 미동기화 (visibility warning)

게이팅은 통과하지만 tasks/AC 미체크가 남아있는 상태. spec-implement 우회로 직접 commit 한 경우 또는 phase 가 끝나지 않은 정상 진행 중 상태.

```
✓ spec-validate 008-review-summary-safe-sync 통과 (with warnings)

 📍 발견  NEEDS=0  placeholder=0  빈 섹션=0
 📊 진행률  tasks 6/11 (미체크 5건)  AC 5/10 (미체크 5건)
 🎯 결과  명료성 통과 — 진행률 미동기화 항목 검토

 ⚠ 점검
  spec-implement 우회로 코드 commit 했다면 체크박스 동기화 누락이에요.
  최근 commit 의 변경 파일이 spec dir 외부인지 git log 로 확인 권장.

 다음 단계
 [a] tasks.md / spec.md §3 의 - [ ] 를 - [x] 로 갱신 (chore commit)
 [b] 정상 진행 중이면 다음 phase 진입 — spec-implement 호출
```

### 실패 (1건 이상)

```
✗ spec-validate 005-payment-refund-policy-change 보류

 📍 발견
  NEEDS CLARIFICATION    3 건 — spec.md
  placeholder `<...>`    2 건 — spec.md (§1.1, §7.5)
  빈 섹션                §3 성공 기준

 🎯 게이팅 모두 해결 후 재검사 필요

 ─ 다음 단계 ──────────────────────────────────────

 [a] ✓ 한 항목씩 같이 해결      [권장]
  제가 각 항목을 보여드리고 사용자 결정·도메인 전문가 확인 받아요.
  결정 후 spec/contracts 본문 자동 갱신 (NEEDS CLARIFICATION 제거).

 [b] 사용자가 직접 편집 후 다시 [check]
  파일 위치만 알려드릴게요. 직접 수정 후 "goax spec check 005" 재실행.

 [c] ⚠ 보류 — 일단 다른 작업으로
  경고: L3 도메인이라 게이팅 통과 없인 plan/tasks 진행 시 후폭풍 큼.

 ▸ 답해주세요 [a] / [b] / [c]
```

## 4. Triage 자동 게이팅 (참고)

`.ax/config.yml`의 `domain_risk`가 L2/L3인 도메인 작업이면, 이 게이트 통과 없이는 `triage` 결과가 "spec 미통과 — 진행 금지"로 변해요. spec-validate 가 통과해야 다음 skill (`/spec-tasks`, `/spec-implement`) 흐름이 풀려요.

## 절대 금지

- NEEDS CLARIFICATION을 임의로 "해결"로 처리 X — 사용자만 결정.
- 통과를 가짜로 만들지 않아요. 실패는 명확히 ✗.

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- current_task.spec_passed

갱신 방법: `update-state.sh --skill` (락 안에서 in-place). 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
bash .ax/scripts/bash/update-state.sh --skill spec-validate   # canonical(derived·hud 캐시) + last_skill·skill_calls 를 같은 락 안에서
```

## current-task.json 갱신 

명료성 통과 **그리고** 합의 리뷰 통과(필수일 때) 시 phase 진행, 미해소 시 blocked_by 기록 → 다음 skill (`spec-tasks` / `spec-implement`) 이 phase 보고 차단:

```bash
# 통과 — 명료성 + (required 면) spec-review pass
bash .ax/scripts/bash/update-task.sh --phase spec_checked --blocked-by '[]' --json
bash .ax/scripts/bash/update-state.sh >/dev/null 2>&1 || true     # HUD: spec ✓ › tasks ●

# 미해소 — blocked_by 에 위치/카테고리 기록 (합의 리뷰 미통과도 여기)
BLOCKED='["spec.md:42 NEEDS","spec.md:18 placeholder","review-spec: evaluator 보강 필요"]'
bash .ax/scripts/bash/update-task.sh --phase spec_blocked --blocked-by "$BLOCKED" --json
```
