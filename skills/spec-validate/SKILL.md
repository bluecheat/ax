---
name: spec-validate
description: "spec 명료성 게이팅 + 진행률 visibility — 'spec 확인', 'goax spec check', '스펙 게이트'. spec.md 의 NEEDS CLARIFICATION + placeholder `<...>` + 빈 필수 섹션 3 항목을 게이팅하고, tasks.md 진행률 + AC 진행률을 visibility 로 노출 (spec-implement 우회 시 누락 즉시 인지)."
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
STATUS=$(echo "$RESULT" | jq -r '.status')
NEEDS=$(echo "$RESULT" | jq -r '.result.needs_clarification')
PLACE=$(echo "$RESULT" | jq -r '.result.placeholders')
EMPTY=$(echo "$RESULT" | jq -r '.result.empty_sections | join(", ")')
TASKS_DONE=$(echo "$RESULT" | jq -r '.result.tasks_progress.completed')
TASKS_TOTAL=$(echo "$RESULT" | jq -r '.result.tasks_progress.total')
TASKS_OPEN=$(echo "$RESULT"  | jq -r '.result.tasks_progress.open')
AC_DONE=$(echo "$RESULT"     | jq -r '.result.ac_progress.completed')
AC_TOTAL=$(echo "$RESULT"    | jq -r '.result.ac_progress.total')
WARNINGS=$(echo "$RESULT"    | jq -r '.warnings // [] | join("; ")')
```

스크립트 검사 (게이팅 — fail 시 진행 차단):
- NEEDS CLARIFICATION 마커 잔존
- placeholder `<...>` 본문 잔존 (표 셀·URL 화이트리스트)
- 필수 섹션 (§1.1 한 줄 정의 / §3 성공 기준 / §4 사용자 시나리오) 본문 1 라인 이상

스크립트 visibility (status 영향 X — 누락 인지 신호):
- `tasks_progress`: tasks.md 의 `- [ ]` / `- [x]` 카운트
- `ac_progress`: spec.md §3 AC 의 `- [ ]` / `- [x]` 카운트

## 3. 출력

### 통과 + tasks/AC 모두 0 (clean state)

```
✓ spec-validate 005-payment-refund-policy-change 통과

 📍 발견  NEEDS=0  placeholder=0  빈 섹션=0
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
  결정 후 spec/plan/contracts 본문 자동 갱신 (NEEDS CLARIFICATION 제거).

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

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
jq '.last_skill = "spec-validate" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```

## current-task.json 갱신 

명료성 통과 시 phase 진행, 미해소 시 blocked_by 기록 → 다음 skill (`spec-tasks` / `spec-implement`) 이 phase 보고 차단:

```bash
# 통과
jq '.phase = "spec_checked" | .blocked_by = [] | .updated_at = (now | todate)' \
 .ax/current-task.json \
 > .ax/current-task.json.tmp && mv .ax/current-task.json.tmp .ax/current-task.json

# 미해소 — blocked_by 에 위치/카테고리 기록
BLOCKED='["spec.md:42 NEEDS","spec.md:18 placeholder"]'
jq --argjson bb "$BLOCKED" \
 '.phase = "spec_blocked" | .blocked_by = $bb | .updated_at = (now | todate)' \
 .ax/current-task.json > .ax/current-task.json.tmp \
 && mv .ax/current-task.json.tmp .ax/current-task.json
```
