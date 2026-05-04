# Spec — Rule Enforcement (CLAUDE.md / module rules 의 enforce 메커니즘 계약)

CLAUDE.md 와 `.ax/spirit/rules/`, `.ax/modules/*/rules.md` 의 룰은 **시그널 라벨(🔴/🟡/🔵) + enforce 메커니즘 선언**의 한 쌍이에요. 이 spec 은 두 쌍이 깨지지 않게 — *"CRITICAL 이라고 박았는데 자동 차단 안 되는 거짓 약속"* 같은 anti-pattern 을 schema 와 invariant 로 차단해요.

> ⚠ **이 spec 의 동기**: 🔴 CRITICAL 라벨이 자동 차단을 *보장* 한다는 약속인데, hook 미작성 + `enforced_by: TODO` 로 박힌 채로 추적 메커니즘이 없으면 deadline 이 흘러도 아무도 모름. 라벨이 실제 enforce 와 어긋나 있으면 다른 세션이 "이 룰은 자동 차단됨" 으로 오인 → 진짜 위반이 살아있어도 안전한 줄. 이 spec 의 invariant 가 그 거짓 약속을 영구 차단.

## 시그널 라벨 ↔ enforce 메커니즘 계약

| 라벨 | 의미 | enforce 메커니즘 의무 |
|---|---|---|
| 🔴 **CRITICAL** | 자동 차단, 우회 불가 | `enforced_by` 가 `hook:*` 또는 `external:*` 이어야 함. 그 hook/도구가 실제로 존재 + 활성. **TODO 금지**. |
| 🟡 **MANDATORY** | 사람 승인 게이트 | `enforced_by` 가 `human:*`, `external:*`, `hook:*`, 또는 `TODO:<deadline>` 허용 |
| 🔵 **CONVENTION** | 권장 가이드 | `enforced_by` 생략 가능 (PR 리뷰 인용용) |

핵심: **🔴 라벨은 자동 차단을 *보장*** 한다는 약속이에요. 약속을 못 지키면 라벨을 🟡 로 강등하는 게 정직. spec 의 invariant 가 이 정직을 강제해요.

## `enforced_by` schema (값 enum)

```
enforced_by: <kind>:<value>
```

| kind | value | 의미 |
|---|---|---|
| `hook` | `.ax/hooks/<sub>/<file>.sh` | Claude Code hook + git hook. 자동 차단. **CRITICAL 만 사용 가능 / MANDATORY 도 OK**. |
| `script` | `.ax/scripts/<...>.sh` 또는 임의 명령 | 검증 스크립트 (정보 출력만, 차단 X). |
| `human` | `pr-review` / `adr` / `team-lead` 등 | 사람 게이트. 도구 차단 X. |
| `external` | `archunit` / `konsist` / `coderabbit` / `<도구>` | 외부 도구. 도구 자체가 차단 메커니즘 가짐. |
| `TODO` | `<deadline-YYYY-MM-DD>` | **deferred 상태**. deadline 필수. |

복수 메커니즘은 줄바꿈 또는 `+` 로:
```
enforced_by:
  - hook:.ax/hooks/pre-commit/<rule-name>.sh
  - external:archunit
```

## `enforced_kind` schema (검증 카테고리)

| 값 | 의미 |
|---|---|
| `block` | 위반 시 commit/edit 자체 차단 (exit ≠ 0) |
| `warn` | stderr 경고만, 작업 진행 허용 |
| `grep` | 패턴 매칭 (block 또는 warn 의 한 형식) |
| `arch` | 의존 그래프·layer 검증 (ArchUnit/Konsist 류) |
| `human` | 사람 검토. 도구 X. |
| `missing` | enforce 메커니즘 자체 없음 — `🔵 CONVENTION` 외 사용 금지 |

`enforced_kind` 는 정보 분류 — `enforced_by` 가 SSOT 이고, `kind` 는 reader 편의용. spec 검증은 `enforced_by` 만으로 충분.

## TODO deadline 형식

`enforced_by: TODO:<deadline>` 의 deadline 은 두 형식 중 하나:

| 형식 | 예 | 해석 |
|---|---|---|
| `YYYY-MM-DD` | `TODO:2026-06-01` | absolute date |
| `+Nd` / `+Nw` | `TODO:+4w` | install/onboarding 시점 + 상대 (한 번만 해석돼서 absolute 로 박힘 — 절대 동적 해석 금지) |

상대 형식은 onboarding 이 받을 때 즉시 absolute 로 변환해서 저장. **나중에 doctor 가 다시 해석하지 않음** — deadline 기준일이 흐를 위험 차단.

## 불변량 (Invariants — spec 위반은 doctor 가 fail 처리)

- **I1. CRITICAL ≠ TODO** — 🔴 라벨의 `enforced_by` 는 `hook:*` 또는 `external:*` 만. `TODO:*`, `human:*`, `script:*` 면 invariant 위반 → 강등 또는 hook 작성.
- **I2. TODO 는 deadline 필수** — `enforced_by: TODO` (deadline 없음) 는 형식 위반. `TODO:YYYY-MM-DD` 또는 `TODO:+Nw` (즉시 절대화).
- **I3. doctor 매 호출 추적** — `enforced_by: TODO:*` 를 grep 해서 deadline 과 오늘 비교. 임박(≤7일) / 초과(<오늘) 시 별도 보고 섹션 + 옵션 제시.
- **I4. deadline 초과는 강등 권장** — 자동 강등 X (UX 안전: 사용자 confirm 필요). 단 doctor 는 강등 명령을 옵션 [r] 로 강조.
- **I5. hook 경로는 실제 존재 + settings.json 등록** — `enforced_by: hook:.ax/hooks/...sh` 면 (a) 파일 실제 존재 (b) `.claude/settings.json` 또는 `.git/hooks/pre-commit` 에 등록. 둘 다 OK 여야 enforce 보장. 한 쪽만이면 ⚠ "활성화 안 됨".

## 룰 파일 frontmatter / inline 표기 — 두 형태 허용

**A. spirit/rules/<name>.md frontmatter** (룰 1개당 파일 1개일 때):
```
---
category: data
applies_to: [code, pr, review]
paths:
  - "**/db/migration/**"
enforced_by:
  - hook:.ax/hooks/pre-commit/<rule-name>.sh
enforced_kind: block
---
```

**B. CLAUDE.md inline** (Constitution 의 짧은 핵심 룰일 때):
```
🔴 **`<SCOPE>:CRITICAL:001`** <룰 한 줄 요약> ...
- enforced_by: hook:.ax/hooks/pre-commit/<rule-name>.sh
- enforced_kind: block
```

doctor 는 양쪽 모두 grep 으로 추출 가능해야 해요. 같은 룰 ID 가 양쪽에 등장하면 frontmatter 가 우선 (더 풍부한 메타).

## doctor 통합 — 신규 §3.x "Rule Enforcement"

`skills/doctor/SKILL.md` 의 §3 검사 표에 row 추가, 그리고 §3.7 옆에 새 §3.x 섹션. 검증 알고리즘:

```bash
# (1) 모든 룰 enforced_by 추출 — CLAUDE.md inline + spirit/rules + modules/*/rules.md
RULES_TODO=()       # enforced_by: TODO:* 항목 (deadline + 룰 ID)
RULES_BAD_CRITICAL=()  # 🔴 인데 enforced_by 가 hook/external 아님 (I1 위반)
RULES_NO_DEADLINE=()   # TODO 인데 deadline 없음 (I2 위반)
RULES_HOOK_MISSING=()  # enforced_by: hook:<path> 인데 파일/등록 어느 한쪽 부재 (I5 위반)

# CLAUDE.md inline 파싱 — 🔴/🟡/🔵 라벨 + 다음 줄 enforced_by:
# spirit/rules/*.md, modules/*/rules.md frontmatter 파싱 — category, enforced_by, enforced_kind

# (2) deadline 비교 (오늘 = $(date +%Y-%m-%d))
# 각 TODO:<date> 에 대해:
#   - date < today          → RULES_TODO_OVERDUE  (강등 권장)
#   - today ≤ date ≤ +7d    → RULES_TODO_IMMINENT (임박 안내)
#   - date > today + 7d     → RULES_TODO_FUTURE   (참고만, 보고 생략)

# (3) hook 존재 + 등록 검증 (hook-registration.md §3.7-(3) 와 같은 추출 로직 재사용)
```

보고 형식 (어느 하나라도 있을 때만 출력):

```
 ─ Rule Enforcement ─────────────────────────────────────
 ❌ I1 위반 — CRITICAL 인데 자동 차단 메커니즘 없음 (거짓 약속):
   - <SCOPE>:CRITICAL:001 — enforced_by: TODO:<date> (hook 부재)
   - <SCOPE>:CRITICAL:002 — 동상
 ⚠ TODO deadline 임박 (≤7일) N건 / 초과 K건:
   - <SCOPE>:MANDATORY:002 — TODO:<date> (D-3)
   - <SCOPE>:MANDATORY:005 — TODO:<date> (15일 초과 — 강등 권장)
 ⚠ I5 위반 — hook 경로 부재 또는 미등록:
   - hook:.ax/hooks/pre-commit/<rule-name>.sh — 파일 부재
   - hook:.ax/hooks/pre-commit/<rule-name>.sh — 파일 존재, settings.json 미등록
```

`다음 단계` 옵션:

```
 [r] ✓ 라벨 강등 — CRITICAL → MANDATORY (I1 위반 N건)         [최우선 추천]
   명령  CLAUDE.md 의 🔴 → 🟡 일괄 변환 (사용자 confirm 후 LLM 적용)
   이유  CRITICAL 라벨이 거짓 약속 — 라벨과 실제가 일치해야 다른 세션이 오인 안 함

 [w] ✓ hook 작성 — enforced_by 가 가리키는 hook 파일 신규 작성   [장기 — 룰 진짜 enforce]
   명령  .ax/hooks/<sub>/<basename>.sh 직접 작성. template 없음 (룰 의미 의존).
   이유  CRITICAL 유지하면서 약속을 진짜로 지킴

 [d] ✓ deadline 갱신 — 임박/초과 TODO 에 새 absolute date 부여     [강등 거부 시]
   명령  enforced_by: TODO:<new-date> 로 갱신 (사용자 입력)
   이유  ADR 검토 시점 연기 — 단 단순 연기 반복은 anti-pattern (3회 이상 연기 시 강등 권장)
```

## onboarding 통합 — deferred 받을 때 deadline 강제

`skills/onboarding/SKILL.md` 가 사용자에게 "CRITICAL hook 지금 작성? / 나중에?" 같은 옵션을 받을 때:

1. **"나중에" (deferred) 선택 시 deadline 강제 입력** — "언제까지? (기본 +4w = `<absolute date>`)"
2. **CLAUDE.md 룰에 자동 박기** — `enforced_by: TODO:<absolute-date>` (상대 형식 → 즉시 절대화, I2)
3. **ADR 에 checklist 추가** — `- [ ] <YYYY-MM-DD> CRITICAL hook <name> 작성 또는 강등` (doctor 가 grep 해서 추적)
4. **CRITICAL 보다 MANDATORY 권장** — 메시지: "hook 미작성 deferred 면 라벨을 🟡 MANDATORY 로 시작하는 걸 권장해요. 작성 후 🔴 승급이 정직해요."
5. **사용자가 그래도 🔴 고집하면 ADR 에 명시** — `## 거짓 약속 위험 인지` 섹션 자동 생성, `enforced_by: TODO:<date>` + 강등 트리거 명시

## 비목표 (Non-goals)

- **자동 hook 코드 생성** — 룰 의미는 사람이 작성. spec 은 schema · 추적 · 강등 권장만.
- **deadline 초과 자동 강등** — UX 안전 위해 사용자 confirm 필수.
- **`enforced_kind` 의 자동 분류** — 자유 형식 입력 → spec enum 자동 매핑은 fragile. 사용자 명시 입력.
- **외부 도구(ArchUnit 등) 동작 검증** — `enforced_by: external:archunit` 이 선언만 — 실제 도구 활성 여부는 별도 검증.

## 검증 시나리오 (acceptance)

| # | 룰 상태 | 기대 doctor 결과 |
|---|---|---|
| 1 | 🔴 + `hook:.ax/hooks/.../foo.sh` + 파일 존재 + settings.json 등록 | ✅ pass, 보고 생략 |
| 2 | 🔴 + `hook:.../foo.sh` + 파일 부재 | ❌ I5 위반 — "거짓 약속" |
| 3 | 🔴 + `hook:.../foo.sh` + 파일 존재 + 미등록 | ⚠ I5 위반 — "활성화 안 됨" |
| 4 | 🔴 + `TODO:2026-06-01` | ❌ I1 위반 — "CRITICAL ≠ TODO" |
| 5 | 🔴 + `human:pr-review` | ❌ I1 위반 — "CRITICAL ≠ human-only" |
| 6 | 🟡 + `TODO:2026-06-01` (오늘 2026-05-05, D-27) | · "deadline 27일 남음" (참고만) |
| 7 | 🟡 + `TODO:2026-05-10` (D-5) | ⚠ "deadline 5일 남음 — 임박" |
| 8 | 🟡 + `TODO:2026-04-01` (15일 초과) | ⚠ "deadline 15일 초과 — 강등 권장" |
| 9 | 🟡 + `TODO` (deadline 없음) | ❌ I2 위반 — "deadline 필수" |
| 10 | 🔵 + `enforced_by` 생략 | ✅ pass |
| 11 | 🔴 + `external:archunit` | ✅ pass (외부 도구 활성 검증은 비목표) |
| 12 | 같은 룰 ID 가 CLAUDE.md inline + spirit/rules frontmatter 양쪽 | frontmatter 가 우선, doctor 출력에 "duplicated declaration" 경고 |

## 호환·이행

- **이 spec 도입 전 룰** (`enforced_by: TODO` deadline 없음 등) — doctor 가 I2 위반으로 보고 + onboarding 재실행 권장
- **wrapper 단계 없음** — schema 가 strict, 사용자가 한 번 fix 하면 끝
- **`enforced_by` 미사용 룰** — `🔵 CONVENTION` 으로 분류 권장. 다른 라벨이면 doctor 가 schema 위반으로 보고

## 관련

- `docs/spec/config-yml.md` — `sensors.mode` (warning/fail) 가 hook 차단 강도 결정
- `skills/doctor/SKILL.md` §3.x — 이 spec 의 invariant 를 검증
- `skills/onboarding/SKILL.md` — deferred 옵션 받을 때 schema 강제 입력
- `templates/default/CLAUDE.md.template` — inline 표기 형식의 출고 예시
