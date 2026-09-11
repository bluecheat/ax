# Skill Routing

> Triage가 작업 분류 후 어떤 skill을 호출할지 결정할 때 참조하는 라우팅 표.
> skill 은 자연어 트리거로 발동돼요 — slash command 는 `/goax` 인덱스 하나만 남아 있어요.

## 그룹 (15 skill)

| 그룹 | skill |
|---|---|
| 핵심 spec workflow | `spec`, `spec-validate`, `spec-tasks`, `lane`, `spec-implement` |
| 진단·관리 | `doctor`, `hud`, `vendor` |
| 도입 | `up`, `onboarding` (brownfield), `zero` (greenfield 0→1) |
| Mistake Loop | `mistake` (캡처), `audit` (회고·승격) |
| 진입점 | `triage` |
| 결정 기록 | `adr` |

`skills/<name>/SKILL.md` 는 `.claude-plugin` 플러그인이 자동 로드해요 — 프로젝트 파일이 아니라 plugin 자산. `install` skill 은 `up` 으로 개명됐고, `spec-plan` 은 폐기됐어요 (설계 결정은 ADR 로 이동). `rules` 와 `spirit` 도 폐기됐어요 — 하던 일이 산문이었고 스크립트가 없었어요. 이제 `rules-index.sh` 와 `spirit-lint.sh` 가 하고, `doctor` 가 "rules 보여줘" · "spirit 점검" 트리거를 받아 그 스크립트를 불러요.

## 라우팅 매트릭스 (size × risk × spec tier × friction)

Size·Risk 등급 정의는 [`reference/triage-matrix.md`](reference/triage-matrix.md) 참조. friction 모드(`autopilot`/`phase_gate`/`per_task`)의 결정 규칙은 [`reference/confirmation-policy.md`](reference/confirmation-policy.md) 가 SSOT.

| Size × Risk | 권장 경로 | spec tier | friction |
|---|---|---|---|
| S × L0~L1 | 즉시 작업 → hooks → commit | — | autopilot |
| M × L0~L1 | inline (+ lint) → commit | — (standard 선택 가능) | autopilot / phase_gate |
| M × L2 | `spec` → spec-tasks → 구현 | standard 또는 full (모호 영역 — 메뉴) | phase_gate |
| M × L3 | `spec` → spec-tasks → 구현 (+ evaluator) | standard | per_task |
| L × L0~L2 | `spec` → spec-tasks → 구현 (+ evaluator 필수 · ADR 권장) | standard | phase_gate |
| L × L3 / XL × * | `adr` 먼저 → `spec --tier full` → spec-tasks → 구현 (+ architect·evaluator 합의 리뷰 필수 + evaluator 게이트) | full | per_task |

## 두 가지 spec 길

### 빠른 길 — tier-aware (한 명령으로)
```
"spec 만들어줘 payment-refund — 풀패키지"
 → spec.md + tasks.md + research.md + data-model.md
  + contracts/{api,events} + quickstart.md (6 파일)
  + ADR (.ax/docs/adr/NNNN-*.md) — 별도 작성
```

### 점진 길 — 단계별 (standard 부터 시작, 필요시 추가)
```
"spec 만들어줘 payment-refund"        → spec.md + tasks.md (2)
add-spec-files.sh --add research,data-model  → 점진 확장
"tasks 분해"                          → spec-tasks
"구현 시작"                           → spec-implement (tasks.md 순차 실행)
"ADR 작성"                            → adr — 설계 결정 기록
```

자연어 override: "간단"/"tasks 까지" → standard, "풀패키지" → full.

## Workflow phase (current-task.json)

```
idle → triaged → spec → spec_checked → tasks → implementing → review → idle
                   ↘ spec_blocked (명료성 게이트 — NEEDS / placeholder / 빈 섹션, 또는 합의 리뷰 미통과)
```

| phase | 누가 쓰나 | HUD 체인 |
|---|---|---|
| `triaged` | triage | `spec ●` |
| `spec` | spec | `spec ●` |
| `spec_blocked` | spec-validate (게이트 실패) | `spec ●` 노랑 |
| `spec_checked` | spec-validate (명료성 + 합의 리뷰 통과) | `tasks ●` |
| `tasks` | spec-tasks | `impl ○ 0/N` — 다음: spec-implement |
| `implementing` | spec-implement §1.6 | `impl ● n/N` |
| `review` | spec-implement §8.1 (evaluator 대기) | `review ●` |
| `idle` | spec-implement §8.2 (`reset-task.sh`) | `idle` |

위 표의 skill 은 전부 `update-task.sh --phase <p> [--set …]` 로 써요 — 인라인 jq 는 금지(smoke 가 잡아요). writer 셋(`update-task.sh` · `status-note.sh` · `tier-from-state.sh --reset`)이 같은 락 문자열을 잡아요.
`handoff` 하위 객체 (`current-task.json.handoff`) — 누가 쓰나: `status-note.sh` 만. 언제: halt·완료·레인 보고·zero §13·onboarding 9단계.
`reset-task.sh` 의 phase 리셋에 살아남아요 (next·open·renamed 는 task 를 넘어 살아야 해요).

`done`·`blocked` 는 폐기됐어요 — 완료는 `reset-task.sh` 가 곧바로 idle 로 닫고, 막힘은 `blocked_by` 배열이 표현해요.

각 skill이 phase 갱신. `doctor`가 phase 보고 결손 진단.

**세션 간 인계는 phase 가 아니라 `current-task.json` 의 `handoff`** 예요 (`status-note.sh` — 지금 상태 · 다음 · 열린 질문 · 이번에 바뀐 이름). `triage` 가 매 작업 진입 때 MEMORY.md 보다 먼저 읽고, `spec-implement` 가 halt·완료·레인 보고 시점에 갱신하고, `zero` 가 첫날 끝에 개설해요. 대화가 압축되면 사라지는 것만 담고, 끝난 항목은 지워요.

## Mistake Loop — capture(mistake) vs review(audit) 분리

| 단계 | skill | 발동 트리거 |
|---|---|---|
| 캡처 | `mistake` | "실수 기록해줘", "mistake 박아줘", "/mistake" — 사용자가 명시적으로 1건 capture 의도를 표현할 때만. hook 자동 capture 는 폐기됨 |
| 심사 | `audit` | "goax audit", "실수 회고", "재발", "룰 승격 후보" — `promote-mistake.sh --json --threshold N` 으로 카테고리 분포·후보 계산 |
| 승격 | `audit` (4단계) | 마킹 → 룰 본문 작성 → archive, 3단계 모두 완료해야 종료 |

승격 3단계와 `promote-mistake.sh` 실제 플래그:

```bash
# 1. 후보 조회 (dry-run 기본 — threshold 는 config.yml promotion_threshold, 기본 3)
bash .ax/scripts/bash/promote-mistake.sh --json

# 2. mistake 에 promoted_to 마킹 (룰 본문은 LLM 이 spirit/rules 에 직접 Edit)
bash .ax/scripts/bash/promote-mistake.sh --apply --json --token SP-SEC-001 --category security

# 3. 룰 본문 작성·검증 후 archive 로 이동
bash .ax/scripts/bash/promote-mistake.sh --archive --json --token SP-SEC-001
```

`audit` 은 새 mistake 를 캡처하지 않아요 — 누적된 `.ax/mistakes/*.md` 만 읽고 회고해요. `mistake` 는 반대로 회고·승격을 하지 않고 1건 캡처만 해요.

## 한 폴더 = 한 의도

`skills/<name>/SKILL.md` 는 평탄한 구조 — 하위 카테고리 디렉토리(`global/`, `personas/`, `workflows/` 등) 없이 skill 하나당 디렉토리 하나예요. 각 SKILL.md의 `description`은 **트리거 키워드 5~10개**를 담아 자동 라우팅 정확도를 올려요. 다른 skill과 트리거 중복은 피해요 — 예: `mistake` 는 '기록'·'캡처'·'남겨' 같은 capture 의도만, `audit` 은 '회고'·'심사'·'승격' 같은 review 의도만 매칭.

큰 skill(>200줄)은 `<skill>/references/<topic>.md`로 분리 권장.

## 자기 프로젝트 맞춤화

1. **`.ax/_templates/spec/`** 도메인에 맞게 수정 — 이게 SSOT (drift는 `doctor`가 알려줘요)
2. **`.ax/spirit/rules/<카테고리>.md`** 추가 — 새 카테고리 룰 (`audit` 승격 또는 onboarding 이 생성)
3. **모듈별 `.ax/modules/<name>/rules.md`** — Layer 2 스코프 룰. `keywords` frontmatter 로 triage 가 자동 매칭
4. **`.ax/scripts/bash/`** — 자기 프로젝트에 맞는 결정론 스크립트 추가 가능 (--json 표준 따르면 SKILL이 호출 가능)

## 직접 호출 — slash command

```
/goax   도움말 겸 인덱스 — 모든 트리거 한눈에 (유일하게 남은 slash 명령)
```

그 외 모든 기능은 자연어로 부르면 돼요: "goax 도입해줘" / "spec 만들어줘 — payment-refund" / "tasks 분해" / "구현 시작" / "spec 확인" / "ADR 작성" / "audit 실행" / "실수 기록해줘" / "진단해줘" / "rules 보여줘" · "spirit 점검" (둘 다 doctor) 등. 자동 라우팅이 안 잡히면 `/goax` 인덱스의 키워드를 참고하거나 `Skill goax:<name>` 으로 명시 호출해요.
