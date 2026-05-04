---
name: spec-implement
description: "tasks.md의 - [ ] 항목을 순차 실행하고 완료 시 - [x]로 마킹 — '/spec-implement', '구현 시작', 'tasks 실행', 'task 진행'. 실패 시 halt+보고. spec.md/plan.md/tasks.md를 입력으로."
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

## 2. 한 task 실행 흐름

```
[T020] Service 구현 — payment/RefundService.kt

🎯 task 분석
 파일  payment/RefundService.kt
 의존  T011 (RefundRepository 인터페이스)
 Phase  Phase 3 — User Story 1

📐 적용할 룰
 CLAUDE.md AX:CRITICAL:003 — 시크릿 hardcode 금지
 Spirit  SP-SEC-002 — 멱등성 키 필수
 Module  payment/CLAUDE.md — Service는 Repository 통해서만 DB 접근

▸ 진행해도 될까요? [y/n]
```

사용자 동의 후 코드 작성 → 테스트 → 완료 시 마킹.

## 3. 완료 마킹

```bash
# - [ ] T020 ... → - [x] T020 ...
sed -i '' 's/^- \[ \] \(\[T020\]\)/- [x] \1/' "$SPEC_DIR/tasks.md"
```

각 task 완료 후 ✓ 보고:
```
✓ T020 — payment/RefundService.kt 구현, 단위 테스트 통과
✓ tasks.md 마킹: - [ ] → - [x]
```

## 4. 실패 처리 (halt)

테스트 실패·빌드 실패·룰 위반 시:
```
✗ T020 실패
 원인: RefundService.kt:42 — AX:CRITICAL:003 위반 (PG 키 평문)
 조치: secrets-vault 사용으로 수정 후 재시도

 진행 중단해요. 사용자 확인 필요.
```

자동 우회 X. 사용자 결정 받음. mistake 캡처는 audit으로 위임.

## 5. 모든 task 완료 시

```bash
# 미완료 task 확인
REMAINING=$(grep -c '^- \[ \]' "$SPEC_DIR/tasks.md" || echo 0)
if [ "$REMAINING" -eq 0 ]; then
 echo "🥳 spec $SPEC 구현 완료."
 # current-task.json 자동 리셋 (phase=idle, .triage-nudged 마커 삭제)
 # → 다음 새 작업이 들어왔을 때 triage가 정상 재발동
 bash .ax/scripts/bash/reset-task.sh >/dev/null 2>&1 || true
 echo "  ✓ current-task.json reset → phase=idle"
 echo "  → spec.md 수용 기준 검증 권장. 다음 작업 메시지에 triage가 다시 발동돼요."
fi
```

**왜 reset 하나**: phase가 `done`/`implementing` 으로 남으면 `triage-nudge` hook이 silent 처리 → 다음 새 작업에서도 nudge가 안 옴 → Layer 0 발동 보장 깨짐. spec 완료는 *명시적 작업 사이클 종료*이므로 즉시 idle로 닫는 게 맞아요. spec 자체는 `.ax/docs/spec/` 에 남아 SSOT 유지.

## 6. 출력 패턴 (한 task당)

```
📐 spec-implement (spec 005, T020 진행)

 📍 task T020 — Service 구현
 📁 file payment/RefundService.kt
 📋 rules AX:CRITICAL:003, SP-SEC-002

 ─ 작업 ─────────────────────────────
 (코드 변경, 테스트 실행)

 ✓ T020 완료 — 마킹 - [x]
 ✓ phase 유지: implementing

 📍 다음 task: T021 — REST endpoint
 ▸ 계속? [y/n]
```

## 절대 금지

- 모든 task를 한 번에 실행 X — 한 task씩 진행, 사용자 확인
- 실패 시 자동 우회 X — halt + 보고
- 완료 task를 다시 - [ ]로 되돌리기 X
- spec.md / plan.md / tasks.md 없이 implement X — 먼저 단계 진행

## state.json 갱신

```bash
jq '.last_skill = "spec-implement" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
