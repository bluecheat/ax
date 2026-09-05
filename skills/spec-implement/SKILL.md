---
name: spec-implement
description: "tasks.md 의 - [ ] 항목을 실행하고 완료 시 - [x] 로 마킹 — '구현 시작', 'tasks 실행', 'task 진행', '레인 실행', '레인으로 돌려'. tasks.md 에 레인 배정(`레인:`)이 있으면 코디네이터로 lane-worker 를 띄우고 원장(lanes-dispatch.sh)에 디스패치·보고를 기록해요. 진입 시 tasks-plan.sh violations 검사, 완료 시 tasks-gate.sh G1~G6 + 새 컨텍스트 evaluator 게이트. 실패 시 halt+보고. friction 강도는 .ax/config.yml 의 confirmation 정책으로 결정. 슬래시로도 호출 가능: '/spec-implement'."
---

# spec-implement — 구현 단계

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거
- `/spec-implement`
- "spec 005 구현 시작"
- "tasks.md 실행해줘"
- "다음 task 진행"
- "레인 실행", "레인으로 돌려줘" (tasks.md 에 `레인:` 배정이 있을 때 — 없으면 `/lane` 먼저)

## 1. 컨텍스트 로드

```bash
SPEC=$(jq -r '.spec_dir | split("/") | .[-1]' .ax/current-task.json 2>/dev/null)
SPEC_DIR=".ax/docs/spec/$SPEC"

# 필수 파일 검증 (plan.md 폐기 — spec.md + tasks.md 만)
for f in spec.md tasks.md; do
 [ ! -f "$SPEC_DIR/$f" ] && { echo "$f 누락 — 먼저 작성"; exit 1; }
done

# 다음 미완료 task 찾기 — 없으면 끝난 게 아니라 §8 완료 게이트로 가요 (게이트가 완료를 판정해요)
NEXT_TASK=$(grep -m1 '^- \[ \]' "$SPEC_DIR/tasks.md" || true)
[ -z "$NEXT_TASK" ] && echo "미완료 task 없음 → §8 완료 게이트로"
```

context로 로드:
- `CLAUDE.md` (Layer 1)
- `<영향 받는 모듈>/CLAUDE.md` (Layer 2)
- `$SPEC_DIR/spec.md` (요구사항 + §7.5 Technical Context)
- 관련 ADR `docs/adr/NNNN-*.md` (설계 결정 — spec.md §7.5 의 *진입 ADR* 인용)
- `$SPEC_DIR/tasks.md` (체크리스트)

## 1.5 진입 게이트 — `[P]` 주장 검증 + 실행 모드 결정

`lane` 을 거쳤든 안 거쳤든 여기서 다시 확인해요. 계획서가 권고한 것을 실행자가 검사하지
않으면, 계획을 건너뛰는 순간 방어가 0 이에요.

```bash
PLAN=$(bash .ax/scripts/bash/tasks-plan.sh --spec "$SPEC" --json)
VIOL_N=$(echo "$PLAN" | jq '.result.violations | length')
if [ "$VIOL_N" -gt 0 ]; then
 echo "$PLAN" | jq -r '.result.violations[] | "  \(.tasks | join("↔")) — \(.file)"'
 echo "[P] 인데 파일이 겹치는 task 가 ${VIOL_N}쌍 — 진행 중단. tasks.md 를 먼저 고치세요 (/lane)"
 exit 1
fi

LEDGER=$(bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --status --json)
LANE_N=$(echo "$LEDGER" | jq '.result.lanes | length')
CONFLICT_N=$(echo "$LEDGER" | jq '.result.lane_file_conflicts | length')
[ "$CONFLICT_N" -gt 0 ] && { echo "$LEDGER" | jq -r '.next_step'; exit 1; }
```

| `LANE_N` | 모드 | 어디로 |
|---|---|---|
| 0 | **단일 레인** — 이 세션이 순차로 구현해요 | §3 |
| > 0 | **레인 모드** — 이 세션은 코디네이터, 구현은 `lane-worker` | §3.5 |

사용자가 "레인으로 돌려" 라고 했는데 `레인:` 이 없으면 `/lane` 로 먼저 배정해요. 배정은
판단이라 여기서 대신 정하지 않아요 — 원장에 없는 배정은 다음 세션이 못 봐요.

## 1.6 phase 기록 — HUD 가 여기서 움직여요

구현이 시작됐다는 사실을 파일에 적어요. 이 한 줄이 없으면 statusline 이 구현 내내 `tasks` 에
멈춰 있어요 (이전 판까지의 실제 결함 — spec-implement 가 phase 를 안 썼어요).

```bash
jq '.phase = "implementing" | .updated_at = (now | todate)' .ax/current-task.json \
 > .ax/current-task.json.tmp && mv .ax/current-task.json.tmp .ax/current-task.json
bash .ax/scripts/bash/update-state.sh >/dev/null 2>&1 || true    # HUD 캐시 (review 단계 표시 여부)
```

## 2. Friction 모드 결정 — Confirmation Friction Policy 적용

policy SSOT: `.ax/docs/reference/confirmation-policy.md` (Decision Rules C1~C5).

```bash
# 1. config 읽기
CONF_MODE=$(awk '/^confirmation:/{f=1;next} f && /^[a-z]/{exit} f && /^  mode:/{print $2; exit}' \
            .ax/config.yml 2>/dev/null)
CONF_MODE="${CONF_MODE:-phase_gate}"   # default

L3_OVERRIDE=$(awk '/^confirmation:/{f=1;next} f && /^[a-z]/{exit} f && /^  l3_override:/{print $2; exit}' \
              .ax/config.yml 2>/dev/null)
L3_OVERRIDE="${L3_OVERRIDE:-per_task}"

MISTAKE_THRESHOLD=$(awk '/^confirmation:/{f=1;next} f && /^[a-z]/{exit} f && /^  mistake_threshold:/{print $2; exit}' \
                    .ax/config.yml 2>/dev/null)
MISTAKE_THRESHOLD="${MISTAKE_THRESHOLD:-3}"

# 2. current-task.json 에서 분류 결과 읽기
TASK_RISK=$(jq -r '.risk // "L0"' .ax/current-task.json)
TASK_DOMAIN=$(jq -r '.domain // "default"' .ax/current-task.json)

# 3. effective mode 결정 (priority: C5 > C3 > C1)
EFFECTIVE_MODE="$CONF_MODE"
[ "$TASK_RISK" = "L3" ] && EFFECTIVE_MODE="$L3_OVERRIDE"   # C5: L3 override

# 4. mistake recurrence 체크 (C3)
RECURRENCE=$(grep -lE "^category:.*\\b${TASK_DOMAIN}\\b" .ax/mistakes/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$RECURRENCE" -ge "$MISTAKE_THRESHOLD" ] && CATEGORY_GATED=true
```

결정 결과:
- `EFFECTIVE_MODE = autopilot` → 모든 task silent, 실패·범위이탈·elevated 만 halt
- `EFFECTIVE_MODE = phase_gate` → Phase 경계에서만 사용자 확인 (정보 밀도 풍부)
- `EFFECTIVE_MODE = per_task` → 매 task 강제 게이트 (legacy + L3 override)
- `CATEGORY_GATED = true` → mistake 누적 카테고리 task 만 추가 게이트

## 3. Task 실행 흐름

### 3.1 Silent 진행 (autopilot / phase_gate 의 phase 내부)

```
📐 T013 진행 — payment/RefundService.kt
   매칭 룰  AX:CRITICAL:003, SP-SEC-002

(코드 변경 + 테스트)

✓ T013 — payment/RefundService.kt 구현, 단위 테스트 통과
✓ tasks.md 마킹: - [ ] → - [x]
```

사용자 [y/n] X — Spirit + hooks + Mistake Loop 가 안전망 역할.

### 3.2 Strict 게이트 (per_task 또는 다음 조건 매칭)

다음 중 하나면 *task 단위* `[y/n]` 강제:

| 조건 | 근거 |
|---|---|
| `EFFECTIVE_MODE = per_task` | 사용자 명시 / L3 override |
| Spirit 매칭에 `SP-SEC-*` 또는 `SP-DATA-*` + risk ≥ L2 | C5 |
| Task 도메인이 `CATEGORY_GATED=true` 카테고리 | C3 |
| Task 가 `enforced_by: TODO:*` 룰 (sensor 부재) 영역 | C4 |

출력:
```
🛑 T020 — payment/RefundService.kt (strict 게이트)
   원인  L3 도메인 + SP-SEC-002 매칭 (C5 적용)
   매칭 룰  AX:CRITICAL:003, SP-SEC-002

   📐 적용할 룰
    AX:CRITICAL:003 — 시크릿 hardcode 금지 (hook:.ax/hooks/pre-commit/critical-rule-grep.sh)
    SP-SEC-002 — 멱등성 키 필수

   📂 영향 파일
    payment/RefundService.kt (신규)
    payment/RefundServiceTest.kt (신규)

   ▸ 진행해도 될까요? [y/n]
```

`[n]` 시 halt + 사용자 결정 대기.

### 3.5 레인 모드 — 코디네이터 루프

이 세션은 **코디네이터**예요. 코드를 직접 고치지 않고, 레인을 띄우고, 보고를 받고, 검증하고,
체크박스를 켜요. 판단은 여기서 하고 기록은 원장이 해요 — 컨텍스트 안의 "누구에게 뭘 보냈더라"
는 압축되거나 세션이 죽으면 사라져요. 실제로 레인 8개가 전부 idle 이 됐을 때 체크박스는
24/36 이었고, 세 레인이 산출물을 만들어 놓고 전송하지 않아 아무것도 도착하지 않은 적이 있어요.

**0. 전제** — §1.5 의 violations 0 + `lane_file_conflicts` 0. 하나라도 있으면 띄우지 않아요.

**1. 준비된 task 를 레인별로 묶어요.**

```bash
echo "$PLAN"   | jq -r '.result.ready | join(" ")'                                   # 지금 시작 가능
echo "$LEDGER" | jq -r '.result.lanes[] | "\(.lane): \(.tasks | join(","))"'          # 레인 → task
echo "$LEDGER" | jq -r '.result.unassigned_open | join(" ")'                         # 레인 없는 task
```

- ready ∩ 레인 A 의 task → 레인 A 의 이번 브리프
- ready 인데 `레인:` 없음 → **코디네이터가 직접** 해요 (§3.1). 배럴·인덱스처럼 떼어낸 순차
  task 가 보통 여기예요
- §3.2 strict 조건(L3 + SP-SEC/DATA 등)에 걸리는 task 는 **레인에 넘기지 않아요.**
  코디네이터가 `[y/n]` 을 받고 직접 해요

**2. 디스패치를 원장에 먼저 적고, 그다음 띄워요.**

```bash
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --dispatch A --json   # 파일 소유 충돌이면 여기서 거부돼요
```

브리프는 `lane` §10 형식 그대로예요 — 소유 파일(그 레인 task 들의 `files:` 합집합) ·
금지 파일(다른 레인 소유 + `protected_paths` + 버전 파일) · task ID 와 각 `검증:` 명령 ·
정지 조건 · "커밋하지 않는다" · "체크박스는 켜지 않는다" · "`SendMessage` 로 보고한다".

`Agent` 도구로 `goax:lane-worker` 를 띄워요 (vendor 설치면 `lane-worker`). 준비된 레인이
여럿이면 **한 메시지에 같이** 띄워요 — 하나 띄우고 기다렸다 다음을 띄우는 건 병렬이 아니에요.

**3. 보고를 받으면 — 받았다는 사실부터 적어요.**

```bash
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --report A --json           # 레인 전체가 왔을 때
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --report T010,T011 --json   # 일부만 왔을 때
```

그다음 **보고에 인용된 검증 명령을 코디네이터가 직접 다시 돌려요.** 통과한 task 만 §5 로
체크박스를 켜요. 레인이 "완료" 라고 했어도 명령이 실패하면 미완료예요 — 보고와 완료는 별개예요.

- 보고가 잘렸으면 잘린 지점을 지목해서 이어 보내달라고 해요 ("T3 섹션 3번째 항목부터"). "다시
  보내주세요" 만 하면 앞부분이 또 오고 또 잘려요
- 레인이 소유 목록 밖 파일을 건드렸다고 보고하면 → §7 범위 이탈, halt
- 레인이 정지 조건에 걸려 멈췄으면 → 전제가 틀린 거예요. 남은 task 를 재배정하지 말고 사용자 결정

**4. 바로 다음 ready 를 띄워요 — 전원 완료를 기다리지 않아요.**

레인 A 가 끝나서 T020 의 의존이 풀렸으면 B 가 아직 돌고 있어도 T020 을 띄워요. 가장 느린 레인이
나머지를 붙잡는 배리어는 `tasks-plan.sh` 가 일부러 안 만든 거예요 (항목별 승격).

`phase_gate` 모드의 사람 확인은 **레인 보고를 받은 시점**에 해요. Phase 경계가 아니에요 —
Phase 와 레인은 1:1 이 아니라서 "Phase 2 → 3 전환" 이 레인 모드에선 정의되지 않아요. 확인
박스 내용은 §4 와 같아요: 받은 보고 요약 + 다음에 띄울 레인과 파일 + 룰 delta.

**5. 종료 조건** — `tasks-plan.sh` 의 `ready` 와 `blocked` 가 둘 다 비고, 원장의
`dispatched_unreported` 가 비어야 해요. 레인이 전부 idle 인 건 조건이 아니에요.

**6. 통합 검증** — 파일이 안 겹쳤다는 건 물리적 충돌이 없었다는 뜻뿐이에요. 전체를 한 번 더:

```bash
bash .ax/scripts/bash/zero-verify.sh --json    # .ax/config.yml commands.* 를 파이프 없이 — 안 돌린 항목도 보고
```

그리고 레인 보고의 "다른 레인에 넘길 것" 을 모아 **이름 대조** — 같은 개념에 두 이름이 생기지
않았는지 (props·타입·토큰·이벤트). 명령으로 안 잡히는 유일한 항목이라 사람 몫이에요.
여기까지 통과해야 §8 로 가요.

## 4. Phase 경계 게이트 — 정보 밀도 풍부

`tasks.md` 의 `## Phase N` 섹션 경계에서 (`EFFECTIVE_MODE = phase_gate` 일 때) 1회 확인. 형식적 [y/n] X — *의사결정 컨텍스트* 출력:

```
◆  Phase 2 → Phase 3 전환

│  ✓ 완료 — Phase 2 (T007~T012, 6 task, 12분 소요)
│   └─ commerce-data 4 파일 — port + service + adapter 통합
│
│  📍 다음 — Phase 3 (T013~T015, 3 task)
│   └─ commerce-batch — HandlerRegistry / R-P-W / cron 등록
│
│  📐 적용될 룰 (Phase 2 와의 차이)
│   + SP-OPS-002 — chunk size 명시 (Phase 3 신규)
│   + SP-DATA-007 → 그대로 유지
│
│  📂 영향 파일 (예정)
│   commerce-batch/.../HandlerRegistry.kt (신규)
│   commerce-batch/.../DispatchJobConfig.kt (신규)
│   .deploy/commerce/values.yml (cron 추가)
│
│  ⚠ 주의
│   T013 의 HandlerRegistry 가 Phase 2 의 ScheduledNotificationHandler 인터페이스에 의존.
│   Phase 2 결과물 검토 권장.
│
└  ▸ 진행 / 변경 사항 있으면 말씀
```

핵심: 이전 Phase 결과 요약 + 다음 Phase 파일 + 적용 룰 delta + 의존성 주의. *비판적 사고가 작동하도록* 정보 제공. `Phase N → Phase N+1` 전환 외에는 묻지 않음.

## 5. 완료 마킹 — silent

```bash
# 방금 끝낸 task 의 ID 를 변수로 — 예시값을 그대로 쓰면 엉뚱한 task 가 체크돼요.
TASK_ID="$COMPLETED_TASK_ID"     # 예: T013

# 체크박스만 뒤집어요. task 줄 형식이 `**T013**`·`[T013]`·`T013 [P]` 중 무엇이든
# ID 만 찾으면 되도록 했어요 (출고 템플릿은 `- [ ] **T013** — ...` 형식).
# ID 뒤에 영숫자가 오면 매칭 안 함 → T001 이 T0011 을 건드리지 않아요.
# `\b` 는 GNU sed 전용이라 안 써요 (BSD/macOS 비호환).
sed -E "/^- \[ \] .*${TASK_ID}([^0-9A-Za-z]|\$)/ s/^- \[ \]/- [x]/" \
  "$SPEC_DIR/tasks.md" > "$SPEC_DIR/tasks.md.tmp" \
  && mv "$SPEC_DIR/tasks.md.tmp" "$SPEC_DIR/tasks.md"
```

각 task 완료 후 1줄 보고 (대화 [y/n] X):
```
✓ T020 — payment/RefundService.kt 구현, 단위 테스트 통과
```

레인 모드에선 **코디네이터만** 켜요 — 원장에 `보고:` 가 적힌 뒤, 검증 명령을 직접 돌린 뒤에요.
레인이 켜면 `tasks-gate.sh` G5 가 "보고 없이 완료 표시" 로 잡아 완료를 막아요.

## 6. 실패 처리 (halt) — 모드 불문 강제

테스트 실패·빌드 실패·룰 위반 시:
```
✗ T020 실패
 원인: RefundService.kt:42 — AX:CRITICAL:003 위반 (PG 키 평문)
 조치: secrets-vault 사용으로 수정 후 재시도

 진행 중단해요. 사용자 확인 필요.
```

자동 우회 X. 사용자 결정 받음. mistake 캡처는 audit 으로 위임.

## 7. 범위 이탈 / Elevated — 모드 불문 강제

다음은 mode 불문 즉시 halt:
- task 가 `tasks.md` 에 명시되지 않은 파일 수정
- 외부 명령(`rm -rf`, `git push --force`, 외부 API 호출, secrets 접근)
- `.ax/config.yml` 의 `protected_paths` 매칭

```
🛑 범위 이탈 감지
 task: T020 (payment/RefundService.kt 만 명시)
 시도: payment/PaymentGateway.kt 수정 (tasks.md 외)

 사용자 결정 필요. tasks.md 갱신 또는 작업 중단 중 선택.
```

## 8. 모든 task 완료 시 — 게이트 + evaluator

완료 판정은 게이트에 위임해요. 빈 체크박스만 세면 (a) 수용 기준은 안 채워졌는데 task 만 끝난
경우, (b) 미완료를 지워서 통과시킨 경우, (c) 레인이 보고 없이 체크박스를 켠 경우를 구분 못 해요.
그리고 **체크박스를 채운 세션이 검사받는 세션이면 그건 게이트가 아니라 자기보고예요.** 그래서
size×risk 가 높으면 다른 컨텍스트가 한 번 봐야 완료예요 (G6).

```bash
GATE=$(bash .ax/scripts/bash/tasks-gate.sh --spec "$SPEC" --json)
COMPLETE=$(echo "$GATE" | jq -r '.result.complete')
OPEN=$(echo "$GATE" | jq -r '.result.open')
REVIEW_REQ=$(echo "$GATE" | jq -r '.result.review_required')
VERDICT=$(echo "$GATE" | jq -r '.result.review_verdict // ""')

if [ "$OPEN" != "0" ] || [ "$(echo "$GATE" | jq -r '.result.task_count_drop')" != "0" ] \
   || [ "$(echo "$GATE" | jq '.result.ac_uncovered | length')" != "0" ] \
   || [ "$(echo "$GATE" | jq '.result.dispatched_unreported + .result.done_without_report | length')" != "0" ]; then
 echo "$GATE" | jq -r '.next_step'
 echo "  → 남은 걸 끝내거나, 의도적 보류면 `- [~] T0NN … 보류: <사유>` 로 표기하세요."
 exit 0
fi
```

여기까지 왔으면 task 는 끝났어요. 이제 verdict 로 갈라요:

| `REVIEW_REQ` | `VERDICT` | 할 것 |
|---|---|---|
| true | 없음 | **§8.1 evaluator 호출** — 필수예요 (size L 이상 · M×L3) |
| false | 없음 | `EFFECTIVE_MODE = autopilot` 이면 생략, 그 외엔 한 번만 제안: "evaluator 리뷰 돌릴까요?" |
| * | `진행` | §8.2 완료 |
| * | `보강 필요` | review.md 의 지적 하나하나를 task 로 옮겨요 (`- [ ] T1NN [ACn] <지적> — files: …`), §3 으로 돌아가요. 끝나면 evaluator 를 **다시** 띄워요 — review.md 는 evaluator 가 덮어써요 |
| * | `재논의 필요` | halt. 사용자 결정 — spec 자체를 다시 봐야 한다는 뜻이에요 |

### 8.1 evaluator — 새 컨텍스트로, 산출물만 주고

`Agent` 도구로 `goax:evaluator` 를 띄워요 (vendor 설치면 `evaluator`). **이 대화를 넘기지
않아요.** 구현 과정을 본 컨텍스트는 자기가 내린 결정의 근거를 이미 "맞다" 고 판단한 상태라
같은 맹점을 그대로 가지고 검토해요. 브리프에 넣는 건 이 넷뿐이에요:

- spec — `$SPEC_DIR/spec.md`
- ADR — spec.md §7.5 의 진입 ADR 경로들
- diff 범위 — 브랜치면 `git diff <base>...HEAD`, 아니면 spec 시작 이후 (`current-task.json` 의
  `started_at` 부터 `git log --since`) + 워킹 트리 (`git diff HEAD`)
- 산출물 — `$SPEC_DIR/review.md` 에 직접 쓰고, **첫 줄은 `verdict: 진행 | 보강 필요 | 재논의 필요`**

띄우기 전에 phase 를 `review` 로 적어요 — HUD 체인의 `review ●` 가 여기서 켜져요:

```bash
jq '.phase = "review" | .updated_at = (now | todate)' .ax/current-task.json \
 > .ax/current-task.json.tmp && mv .ax/current-task.json.tmp .ax/current-task.json
```

evaluator 가 파일을 직접 써요. 코디네이터는 결과를 받아 적지 않아요 — 받아 적는 순간 검사받는
쪽이 검사 기록을 쓰게 돼요. 돌아오면 `tasks-gate.sh` 를 다시 돌려요. G6 이 review.md 의 첫 줄을
읽어 판정해요. `보강 필요` 로 §3 에 돌아갈 땐 phase 를 다시 `implementing` 으로 되돌려요.

### 8.2 완료

```bash
if [ "$COMPLETE" = "true" ]; then
 echo "🥳 spec $SPEC 구현 완료."
 [ -f "$SPEC_DIR/review.md" ] && echo "  ✓ evaluator verdict: $(head -1 "$SPEC_DIR/review.md")"
 bash .ax/scripts/bash/reset-task.sh >/dev/null 2>&1 || true
 echo "  ✓ current-task.json reset → phase=idle"
 echo "  → 다음 작업 메시지에 triage가 다시 발동돼요."
fi
```

**왜 reset 하나**: phase가 `done`/`implementing` 으로 남으면 `triage-nudge` hook이 silent 처리 → 다음 새 작업에서도 nudge가 안 옴. spec 완료는 *명시적 작업 사이클 종료*이므로 즉시 idle로 닫는 게 맞아요.

## 9. 출력 패턴 — silent + Phase 게이트

### autopilot / phase_gate 의 phase 내부 (대부분의 task)
```
📐 spec-implement (spec 005, T013 진행)

 📍 task T013 — HandlerRegistry 구현
 📁 file commerce-batch/.../ScheduledNotificationHandlerRegistry.kt
 📋 rules SP-APP-002

 (코드 작성 → 테스트 → 마킹)

 ✓ T013 완료 — 마킹 [x]
 → 다음 task: T014 — DispatchJobConfig
```

### Phase 경계 (phase_gate)
§4 의 풍부한 컨텍스트 박스 + `▸ 진행 / 변경 사항 있으면 말씀`.

### per_task 또는 strict 매칭 (§3.2)
§3.2 의 `[y/n]` 박스.

### 레인 모드 (§3.5)
```
📐 spec-implement (spec 014, 레인 모드)

 ▸ 게이트  violations 0 · 소유 충돌 0
 ▸ ready   T010 T011 T020   ·  레인 A {T010,T011}  B {T020}  ·  직접 T009
 ▸ 디스패치 A, B — 원장 기록 ✓ → lane-worker 2개 동시 기동

 (보고 수신)
 ✓ 보고 A — 원장 기록 · $ pnpm test Card (exit 0) · T010 T011 마킹 [x]
 → T021 의존 해소 → 레인 A 재디스패치 (B 는 아직 진행 중)

 (전원 종료)
 ▸ 원장   dispatched_unreported 0 · done_without_report 0
 ▸ 통합   zero-verify.sh 전 항목 exit 0 · 이름 대조 — `Pill.tone` → `variant` 1건 정합 확인
 → §8 완료 게이트
```

### 완료 시 (§8)
```
🏁 spec 014 — task 12/12 · AC 3/3 · 원장 정합

 ▸ evaluator 필수 (L × L2) → goax:evaluator 기동 (새 컨텍스트 · spec + ADR 2 + diff)
 ✓ review.md — verdict: 진행 (발견 0건 · 검토 범위 9 파일)
 🥳 spec 014 구현 완료 · current-task.json → idle
```

## 절대 금지

- **모드 불문 모든 task 에 [y/n] 묻기** — `EFFECTIVE_MODE` 결정 결과를 무시한 의례적 확인
- **Phase 경계 게이트를 형식적 [y/n] 으로 축소** — 정보 밀도(이전 결과 + 다음 파일 + 룰 delta) 누락
- **L3 + SP-SEC/DATA 매칭 task 자동 진행** — C5 우회는 거짓 약속 (invariant 위반)
- **violations 가 남은 채로 진행** — §1.5 는 통과 의례가 아니에요. `/lane` 을 건너뛴 경우를 위해 있어요
- **원장 없이 레인 띄우기** — `--dispatch` 없이 띄운 레인은 `--report` 할 곳이 없고, 완료 판정에서 사라져요
- **레인 보고를 받고 검증 명령 없이 마킹** — "테스트 통과했어요" 는 주장이고, 코디네이터가 돌린 명령의 exit 0 이 근거예요
- **코디네이터가 review.md 를 쓰기** — evaluator 의 출력을 받아 적는 순간 검사받는 쪽이 검사 기록을 쓰는 거예요
- **evaluator 에 이 대화를 넘기기** — 새 컨텍스트가 성립 조건이에요 (`agents/evaluator.md` §성립 조건)
- **`review_required = true` 인데 evaluator 생략** — G6 이 막지만, 막히기 전에 안 하는 게 맞아요
- 실패 / 범위이탈 / elevated 시 자동 우회
- 완료 task 를 다시 - [ ] 로 되돌리기
- spec.md / tasks.md 없이 implement
- 모든 task 를 한 번에 *batch 실행* — 한 task 씩 진행하되, 정상 흐름은 silent (모드에 따라 결정)

## state.json 갱신

```bash
jq '.last_skill = "spec-implement" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```

## 관련 룰

- `.ax/docs/reference/confirmation-policy.md` — friction 결정 규칙 SSOT (C1~C5)
- `.ax/docs/reference/triage-matrix.md` — size×risk 별 friction 모드 매핑
- `.ax/config.yml` `confirmation:` 섹션 — 사용자 설정
- `CONCEPTS.md` §5.7 — Confirmation Friction Policy design rationale
