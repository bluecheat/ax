# Skill Routing

> Triage가 작업 분류 후 어떤 skill/agent를 호출할지 결정할 때 참조하는 라우팅 표.

## 그룹 (14 skill — 0.1.16 spec-plan 폐기)

| 그룹 | skill |
|---|---|
| 핵심 spec workflow | `spec`, `spec-validate`, `spec-tasks`, `spec-implement` |
| 진단·관리 | `doctor`, `rules`, `audit`, `spirit`, `hud` |
| 도입 | `install`, `onboarding` |
| `global/` | `triage` |
| `workflows/` | `adr`, `mistake` |

> 0.1.16 변경: `spec-plan` 폐기 (설계 결정은 ADR 로). plan.md 템플릿·command 함께 제거.

## 라우팅 매트릭스 (size × risk × spec tier)

| Size × Risk | 첫 호출 | spec tier | 권장 길 |
|---|---|---|---|
| S × L0~L1 | inline fallback | — | hooks만 → commit |
| M × L0~L1 | inline fallback | standard (선택) | hooks + lint → commit |
| M × L2~L3 | `spec` | **standard** | spec → spec-check → tasks → 구현 |
| L × L0~L2 | `spec` | **standard** | spec → tasks → 구현 (+ ADR 권장) |
| L × L3 / XL × * | `adr` 먼저 | **full** | architect → spec --tier full → ADR → tasks → tester → evaluator |

## 두 가지 spec 길 

### 빠른 길 — tier-aware (한 명령으로)
```
/spec --tier full payment-refund
 → spec.md + tasks.md + research.md + data-model.md
  + contracts/{api,events} + quickstart.md (6 파일)
  + ADR (.ax/docs/adr/NNNN-*.md) — 별도 작성
```

### 점진 길 — 단계별 (standard 부터 시작, 필요시 추가)
```
/spec --tier standard payment-refund   → spec.md + tasks.md (2)
add-spec-files.sh --add research,data-model  → 점진 확장
/spec-tasks                                  → tasks 분해 가이드
/spec-implement                              → tasks.md 순차 실행
/adr                                         → 설계 결정 기록
```

자연어 override: "간단"/"tasks까지" → standard, "풀패키지" → full.

## Workflow phase (current-task.json)

```
idle → triaged → spec → spec_checked
           → spec_blocked (명료성 게이트 — NEEDS / placeholder / 빈 섹션)
   → tasks → implementing → done
   → blocked (사용자 결정 대기)
```

각 skill이 phase 갱신. `doctor`가 phase 보고 결손 진단.

## Mistake Loop

| 단계 | skill | 호출 |
|---|---|---|
| 캡처 | `audit` (capture mode) | "또 그걸…", "재발", `.ax/mistakes/` 작성 |
| 심사 | `audit` (audit mode) | 주 1회, `promote-mistake.sh --json --threshold 2` |
| 승격 | `audit --apply` | `promote-mistake.sh --apply --token --rule-text` → CLAUDE.md 룰 추가 + mistake `promoted_to:` 마킹 |

## 한 폴더 = 한 의도

각 SKILL.md의 `description`은 **트리거 키워드 5~10개**. 다른 skill과 트리거 중복 검사.

큰 skill(>200줄)은 `<skill>/references/<topic>.md`로 분리 권장.

## 자기 프로젝트 맞춤화

1. **`.ax/_templates/spec/`** 도메인에 맞게 수정 — 이게 SSOT (drift는 `doctor`가 알려줘요)
2. **`.ax/spirit/rules/<카테고리>.md`** 추가 — 새 카테고리 룰
3. **모듈별 `<module>/CLAUDE.md`** — Layer 2 스코프 룰
4. **`.ax/scripts/bash/`** — 자기 프로젝트에 맞는 결정론 스크립트 추가 가능 (--json 표준 따르면 SKILL이 호출 가능)

## 직접 호출 — slash commands (0.1.16 — 14개)

```
/goax              도움말
/doctor            진단 + _templates drift
/rules             통합 인덱스
/spec              tier-aware 생성 (한 번에)
/spec-tasks        tasks.md 단계 (점진)
/spec-implement    구현 실행
/spec-validate     명료성 게이팅 (NEEDS / placeholder / 빈 섹션)
/audit             Mistake Loop
/adr               설계 결정 기록
```

자연어로 부르고 싶으면: "goax 도입해줘" / "spec 만들어줘 — payment-refund" / "tasks 분해" / "구현 시작" / "ADR 작성" / "audit 실행" 등.
