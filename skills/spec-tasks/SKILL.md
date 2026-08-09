---
name: spec-tasks
description: "기존 spec에 tasks.md 추가 + 분해 가이드 — 'tasks 분해', 'tasks.md 작성', '작업 분해', '체크리스트 만들어'. spec.md (§3 acceptance + §7.5 Technical Context) + 관련 ADR 기반. add-spec-files.sh 로 selective cp."
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

사용자에게 spec.md (§3 acceptance + §7.5 Technical Context + 관련 ADR) 를 기반으로 dependency-ordered 작업 분해 안내:

```markdown
# Tasks: <feature>

## Phase 1 — Setup (순서 중요)
- [ ] T001 [setup] 의존성 추가 — `package.json`, `build.gradle.kts` 등
- [ ] T002 [setup] 마이그레이션 SQL 작성 — `db/migration/V005__refund.sql`
- [ ] T003 [setup] 환경변수 정의 — `.env.example`

## Phase 2 — Foundational (병렬 가능 [P])
- [ ] T010 [P] DTO 정의 — `payment/RefundRequest.kt`
- [ ] T011 [P] Repository 인터페이스 — `payment/RefundRepository.kt`
- [ ] T012 [P] 도메인 이벤트 — `payment/RefundCreated.kt`

## Phase 3 — User Story 1: 환불 요청 접수 (priority: high)
- [ ] T020 Service 구현 — `payment/RefundService.kt`
- [ ] T021 REST endpoint — `payment/RefundController.kt`
- [ ] T022 통합 테스트 — `payment/RefundControllerIT.kt`

## Phase 4 — User Story 2: PG 환불 호출 (priority: high)
- [ ] T030 PG Adapter — `payment/pg/PgRefundAdapter.kt`
- [ ] T031 멱등성 키 처리 — `payment/IdempotencyService.kt`
- [ ] T032 통합 테스트

## Phase 5 — Polish
- [ ] T100 문서 업데이트 — `README.md`, ADR
- [ ] T110 모니터링 — Grafana dashboard
```

규칙:
- 모든 task: `- [ ] [TaskID] description with file path`
- 병렬 가능한 task: `[P]` 마커
- Phase 순서: setup → foundational → user stories(priority순) → polish
- TaskID는 sortable (T001, T010, T100)

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
  2. 각 task에 file path + [P] 마커
  3. 구현 단계로: "/spec-implement"
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
