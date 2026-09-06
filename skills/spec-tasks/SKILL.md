---
name: spec-tasks
description: "기존 spec에 tasks.md 추가 + 분해 가이드 — 'tasks 분해', 'tasks.md 작성', '작업 분해', '체크리스트 만들어'. spec.md (§3 acceptance + §7.5 Technical Context) + 관련 ADR 기반. add-spec-files.sh 로 selective cp. 슬래시로도 호출 가능: '/spec-tasks'."
---

# spec-tasks — tasks.md 단계

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거
- `/spec-tasks`
- "spec 005 tasks 분해해줘"
- "tasks.md 작성"
- "체크리스트 만들어"

## 1. spec_id 결정 + spec.md 검증

```bash
SPEC=$(jq -r '.spec_dir | split("/") | .[-1]' .ax/current-task.json 2>/dev/null)
[ -z "$SPEC" ] && goax_error "no spec in current-task.json — use /spec-tasks <NNN-slug>"

SPEC_DIR=".ax/docs/spec/$SPEC"
if [ ! -f "$SPEC_DIR/spec.md" ]; then
 echo "spec.md 먼저 작성 필요. /spec 실행해주세요."
 exit 1
fi
```

> plan.md 는 폐기됐어요 — spec.md §7.5 Technical Context 가 기술 컨텍스트, ADR 이 설계 결정.

## 2. 파일 추가

```bash
RESULT=$(bash .ax/scripts/bash/add-spec-files.sh --json --spec "$SPEC" --add tasks)
```

기존 tasks.md 있으면 skip + 작성 가이드.

## 3. tasks.md 분해 가이드

### 무엇을 기준으로 쪼개나 — 크기가 아니라 **필요한 컨텍스트**

"1~3 파일, 1~3시간" 같은 크기 기준은 쪼개는 *양*만 정해줄 뿐, 쪼갠 결과가
서로 어긋나는 걸 막지 못해요. 기준을 바꿔요:

> **"이 task 는 무슨 일을 하나" 가 아니라 "이 task 를 하려면 무엇을 알아야 하나"**
> 로 묶어요. 같은 지식을 요구하는 일은 한 task 로, 다른 지식을 요구하면 나눠요.

이렇게 묶으면 핸드오프에서 새는 정보가 줄어요. 반대로 **작업 종류로 쪼개는 건
안티패턴**이에요 — 플래너/코더/테스터로 나누면 단계마다 맥락이 새는 전화 놀이가 돼요.

실무 사례 하나: "백엔드 리팩터링" 을 셋으로 나눴더니 하나는 async 핸들러를 넣고,
하나는 에러 타입을 재구성하고, 하나는 함수 이름을 바꿨어요. 각자는 멀쩡한데 서로
양립이 불가능해서, 아낀 시간보다 긴 충돌 해결이 따라왔어요.

### `[P]` 는 증명될 때만 — 기본은 순차

쓰기는 읽기와 달라요. 읽기는 여럿이 같은 파일을 봐도 아무 일도 안 생기지만,
쓰기는 서로의 암묵적 결정을 못 본 채 진행돼요. 그래서 `[P]` 는 다음을 **둘 다**
만족할 때만 붙여요:

1. 미완료 의존이 없다
2. 다른 `[P]` task 와 **파일이 겹치지 않는다** (`files:` 로 판정)

판단이 서지 않으면 붙이지 마세요. 순차는 느릴 뿐이지만, 잘못된 병렬은 되돌리는
비용이 더 커요.

> goax 는 병렬 실행을 **대신 해주지 않아요.** `[P]` 는 "동시에 돌려도 안전하다"
> 는 표시일 뿐이고, 실제로 몇 개를 어떻게 돌릴지는 세션이 판단해요.

### AC 매핑

각 task 에 `[AC<n>]` 을 붙여요. spec.md §3 의 수용 기준과 연결돼서, 게이트가
"이 기준에 대응하는 task 가 없다" 를 기계적으로 잡아요. 어느 기준에도 안 붙는
task 가 있으면 그건 spec 에 없는 일을 하고 있다는 신호예요.

---

사용자에게 spec.md (§3 acceptance + §7.5 Technical Context + 관련 ADR) 를 기반으로 dependency-ordered 작업 분해 안내. **한 줄 형식은 기계가 읽어요** (`tasks-plan.sh`, `tasks-gate.sh`, `lanes-dispatch.sh`) — `_templates/spec/tasks.md` 가 SSOT 형식이에요:

```
- [ ] T001 [P] [AC2] <한 줄 설명> — files: path/a.kt, path/b.kt
      의존: T000
      검증: <어떻게>
```

| 토큰 | 뜻 |
|---|---|
| `T001` | task ID. spec 안에서 sequential (T001, T010, T100 처럼 sortable) |
| `[P]` | **병렬 가능** — 미완료 의존 없음 + 다른 `[P]` task 와 파일 안 겹침, 둘 다 만족할 때만 |
| `[AC2]` | 이 task 가 충족하는 spec.md §3 의 수용 기준 |
| `files:` | 건드리는 파일. **모든 task 에 필수** — 빠지면 겹침 검사가 그 task 엔 안 닿아서 "위반 없음"이 "검사 안 함"이 돼요 |
| `의존:` | 앞선 task ID. 없으면 `없음`·`none`·`-` 중 하나만 인정돼요 (`deps:`·`depends:` 는 안 읽혀요) |

체크박스는 셋 — `[ ]` 미완료 · `[x]` 완료 · `[~]` 의도적 보류(사유 병기).

```markdown
# Tasks: <feature>

## Phase 1 — Setup (순서 중요)
- [ ] T001 [AC1] 의존성 추가 — files: package.json, build.gradle.kts
      의존: 없음
      검증: 빌드 통과
- [ ] T002 [AC1] 마이그레이션 SQL 작성 — files: db/migration/V005__refund.sql
      의존: 없음
      검증: 마이그레이션 dry-run

## Phase 2 — Foundational (병렬 가능 [P])
- [ ] T010 [P] [AC1] DTO 정의 — files: payment/RefundRequest.kt
      의존: T001
      검증: RefundRequestTest
- [ ] T011 [P] [AC1] Repository 인터페이스 — files: payment/RefundRepository.kt
      의존: T001
      검증: RefundRepositoryTest

## Phase 3 — User Story 1: 환불 요청 접수 (priority: high)
- [ ] T020 [AC2] Service 구현 — files: payment/RefundService.kt
      의존: T010, T011
      검증: RefundServiceTest
- [ ] T021 [AC2] REST endpoint — files: payment/RefundController.kt
      의존: T020
      검증: RefundControllerIT

## Phase 4 — Polish
- [ ] T100 [AC3] 문서 업데이트 — files: README.md
      의존: T021
      검증: 리뷰
```

규칙:
- **모든 task 에 `files:` 필수** — 겹침 검사가 이 값으로만 성립해요 (`lanes-hotfiles.sh` 의 `tasks_missing_files` 로 사각지대 확인)
- Phase 순서: setup → foundational → user stories(priority순) → polish
- TaskID는 sortable (T001, T010, T100)
- `[P]` 는 기본값이 아니라 증명될 때만 — 판단이 서지 않으면 붙이지 않아요

## 4. current-task.json 갱신

```bash
jq '.phase = "tasks" | .updated_at = (now | todate)' .ax/current-task.json \
 > .ax/current-task.json.tmp && mv .ax/current-task.json.tmp .ax/current-task.json
```

## 5. 출력

```
📐 spec-tasks (spec 005-payment-refund-policy-change)

 ✓ tasks.md 추가 (tier: standard 유지)
 ✓ phase 갱신: spec_checked → tasks

 📍 다음
  1. tasks.md 를 spec.md §3 acceptance + §7.5 Technical Context + ADR 기반으로 분해
  2. 각 task에 `files:` (필수) + `[P]` 마커 + `의존:`
  3. L/XL 이면 "/spec-validate" 를 한 번 더 — spec-review 의 sha 가 tasks.md 도 포함해서(`spec:<sha>|tasks:<sha>`), tasks.md 를 바꾸면 재리뷰가 걸려요. evaluator 는 컨텍스트 기준 분해인가 · files: 가 실제인가 · [P] 근거를 봐요
  4. 병렬로 나눌지 판단: "/lane" — 가를 수 있는 일인지 먼저 판정하고, 파일 소유권으로 레인을 그어요 (`레인:` 원장 기록까지)
  5. 구현 단계로: "/spec-implement" — `레인:` 배정이 있으면 코디네이터 모드, 없으면 단일 레인 순차
```

## 절대 금지

- spec.md 없이 tasks 작성 — 먼저 spec 권유
- spec.md NEEDS CLARIFICATION 미해소 상태에서 tasks 작성 — `/spec-validate` 먼저
- task에 file path 없이 작성 — 모호함
- 한 task에 여러 책임 묶기 — 한 task = 한 일
- 자동으로 task 본문 채우기 — 사용자가 도메인을 알아요
- 환경 e2e·배포·모니터링 task 를 정상 phase 로 박지 않기 — 운영 활동은 spec 범위 밖

## state.json 갱신

```bash
jq '.last_skill = "spec-tasks" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
