---
name: spec-implement
description: "tasks.md의 - [ ] 항목을 순차 실행하고 완료 시 - [x]로 마킹 — '/spec-implement', '구현 시작', 'tasks 실행', 'task 진행'. 실패 시 halt+보고. spec.md/plan.md/tasks.md를 입력으로. friction 강도는 .ax/config.yml 의 confirmation 정책으로 결정."
---

# spec-implement — 구현 단계

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거
- `/spec-implement`
- "spec 005 구현 시작"
- "tasks.md 실행해줘"
- "다음 task 진행"

## 1. 컨텍스트 로드

```bash
SPEC=$(jq -r '.spec_dir | split("/") | .[-1]' .ax/current-task.json 2>/dev/null)
SPEC_DIR=".ax/docs/spec/$SPEC"

# 필수 파일 검증
for f in spec.md plan.md tasks.md; do
 [ ! -f "$SPEC_DIR/$f" ] && { echo "$f 누락 — 먼저 작성"; exit 1; }
done

# 다음 미완료 task 찾기
NEXT_TASK=$(grep -m1 '^- \[ \]' "$SPEC_DIR/tasks.md" || true)
[ -z "$NEXT_TASK" ] && { echo "✓ 모든 task 완료"; exit 0; }
```

context로 로드:
- `CLAUDE.md` (Layer 1)
- `<영향 받는 모듈>/CLAUDE.md` (Layer 2)
- `$SPEC_DIR/spec.md` (요구사항)
- `$SPEC_DIR/plan.md` (설계)
- `$SPEC_DIR/tasks.md` (체크리스트)

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
TASK_TIER=$(jq -r '.spec_tier // "basic"' .ax/current-task.json)
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
# - [ ] T020 ... → - [x] T020 ...
sed -i '' 's/^- \[ \] \(\[T020\]\)/- [x] \1/' "$SPEC_DIR/tasks.md"
```

각 task 완료 후 1줄 보고 (대화 [y/n] X):
```
✓ T020 — payment/RefundService.kt 구현, 단위 테스트 통과
```

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

## 8. 모든 task 완료 시

```bash
REMAINING=$(grep -c '^- \[ \]' "$SPEC_DIR/tasks.md" || echo 0)
if [ "$REMAINING" -eq 0 ]; then
 echo "🥳 spec $SPEC 구현 완료."
 bash .ax/scripts/bash/reset-task.sh >/dev/null 2>&1 || true
 echo "  ✓ current-task.json reset → phase=idle"
 echo "  → spec.md 수용 기준 검증 권장. 다음 작업 메시지에 triage가 다시 발동돼요."
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

## 절대 금지 (0.1.14 갱신)

- **모드 불문 모든 task 에 [y/n] 묻기** — `EFFECTIVE_MODE` 결정 결과를 무시한 의례적 확인
- **Phase 경계 게이트를 형식적 [y/n] 으로 축소** — 정보 밀도(이전 결과 + 다음 파일 + 룰 delta) 누락
- **L3 + SP-SEC/DATA 매칭 task 자동 진행** — C5 우회는 거짓 약속 (invariant 위반)
- 실패 / 범위이탈 / elevated 시 자동 우회
- 완료 task 를 다시 - [ ] 로 되돌리기
- spec.md / plan.md / tasks.md 없이 implement
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
