---
name: audit
description: "Mistake Loop 통합 — 실수 캡처(.ax/mistakes/ 작성)와 심사·승격(주기적 회고). 트리거: 'goax audit', '실수 회고', 'mistakes 점검', '실수', '재발', '같은 문제', '룰 승격', '피드백', '또 그걸'."
---

# goax audit — Mistake Loop (캡처 → 심사 → 승격)

## 핵심 사상
> "agent 실패 시 코드를 고치지 않고 하네스를 고친다."

같은 실수가 N번 반복되면 → 그건 룰로 박힐 신호.

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거

**캡처 모드** (실수 발견 시 즉시):
- 사용자/리뷰가 실수·오해·누락 지적
- "또 그걸…", "같은 문제", "재발" 같은 표현
- 같은 hook 5회 fail / 코드 리뷰 코멘트의 동일 카테고리 3회 이상

**심사 모드** (회고):
- 주 1회 정기 호출 권장 (또는 `mistake_loop.audit_cadence_days` 도래 시)
- "goax audit", "실수 회고", "이번 주 mistakes 정리"

## 1. 캡처 — 실수 발견 즉시

`.ax/mistakes/YYYY-MM-DD-NNN-<slug>.md` 생성:

```markdown
---
category: <security | data | testing | pr | error-handling | concurrency | observability | architecture | naming | dependency-direction | hydration | n+1 | secrets-in-code | ...>
severity: <low | medium | high>
detected_by: <claude | reviewer | ci | self | user>
context_link: <PR URL or commit SHA>
---

# 무엇이 일어났나
# 어디서 (파일·모듈)
# 왜 발생 (근본 원인)
# 어떻게 막을 수 있나 (사람 리뷰 / Sensor 자동화 / 룰 추가)
```

캡처 후 한 줄 보고:
```
✓ .ax/mistakes/2026-05-02-001-pg-key-leak.md 생성 (category=security, severity=high)
 다음 audit에서 승격 후보로 검토돼요.
```

캡처만 하고 끝낼 수 있고, 바로 심사로 이어갈 수도 있어요(사용자가 "audit까지 해줘"라고 하면).

## 2. .ax/mistakes/ 스캔 — `promote-mistake.sh` 위임 

스크립트가 카테고리 분포 + 승격 후보를 계산해요. LLM은 결과 받아 사용자 인터랙션만:

```bash
# 후보 조회 (dry-run 기본 — 변경 없음)
RESULT=$(bash .ax/scripts/bash/promote-mistake.sh --json --threshold 2)

CANDIDATES=$(echo "$RESULT" | jq -r '.result.candidates')
TOTAL=$(echo "$RESULT" | jq -r '.result.total_categories')
```

추가 통계가 필요하면 (큰 프로젝트):
```bash
TOTAL=$(ls .ax/mistakes/*.md 2>/dev/null | grep -v README | wc -l)
find .ax/mistakes -name "*.md" -mtime -7 2>/dev/null | sort # 최근 7일
```

## 3. 출력 — 발견 + 승격 후보

```
🔍 Audit (.ax/mistakes/ — N건 누적, 기간: <시작> ~ <끝>)

 📍 발견 카테고리별 분포
  security  N건
  data   M건
  pr    K건
  ...

 🎯 목표 반복 패턴 → CRITICAL/MANDATORY/CONVENTION 룰 승격
   (.ax/config.yml의 promotion_threshold 기준)

 ─ 승격 후보 ──────────────────────────────────────

 [a] ✓ security → 🔴 CRITICAL     [권장 — 3회+]
  패턴 PG 키 평문 노출 2회 + DB 비번 로그 1회
  제안 AX:CRITICAL:003 — 시크릿 hardcode 절대 금지
  생성 CLAUDE.md 시그널 섹션에 룰 추가 + .ax/spirit/rules/<project>-security.md 신설 + @import 한 줄
  ※ plugin shipped 파일(.ax/spirit/rules/security.md 등) 직접 append 금지 — project-specific 새 파일로
   만들고 root CLAUDE.md CONVENTION 섹션에 @import. plugin 갱신 시 clobber 방지. (onboarding 절대 금지 #6 참조)
  수정 mistake 파일 3개에 promoted_to 마킹
  영향 파일 5개

 [b] data → 🔴 CRITICAL       [추천 — 2회]
  패턴 마이그레이션 down 누락 2회
  제안 AX:CRITICAL:004 — 모든 migration은 down 포함
  생성/수정/영향 (위와 동일 패턴)

 [c] pr → 🟡 MANDATORY       [검토]
  패턴 refactor + feature 한 PR로 묶음 4회
  제안 AX:MANDATORY:002 — refactor + feature 한 PR 금지
  생성/수정/영향

 [d] naming → 🔵 CONVENTION      [선택]
  패턴 파일명 underscore vs kebab 혼재 2회
  제안 SP-NAMING-005 추가 (.ax/spirit/rules/naming.md)
  생성/수정/영향

 [e] 모두 보류 — 다음 audit으로

 ▸ 답해주세요 복수 가능: a,b / 또는 [e]
```

**규칙**
- `promotion_threshold` (기본 3) 이상이면 `[권장]` 라벨
- 2회는 `[추천]`, 1회는 안 띄움 (소음)
- 옵션은 카테고리 단위 — 사용자가 복수 선택 가능 (예: `a, b`)
- 항상 마지막에 `[e]` 모두 보류 옵션

## 4. 적용 — `promote-mistake.sh --apply` 

사용자 승낙 후, 카테고리당 룰 토큰·본문을 결정해 스크립트로 적용:

```bash
# CLAUDE.md 룰 추가 + 해당 카테고리 mistakes에 promoted_to 마킹
RESULT=$(bash .ax/scripts/bash/promote-mistake.sh --apply --json \
   --token AX:CRITICAL:003 \
   --category security \
   --rule-text "PG 키·시크릿 hardcode 절대 금지")
MARKED=$(echo "$RESULT" | jq -r '.result.marked_count')
```

스크립트가 자동:
1. CLAUDE.md에 시그널 라벨로 룰 추가 (🔴/🟡/🔵 토큰으로 결정)
2. 해당 카테고리의 미승격 mistake 파일들에 `promoted_to: <token>` frontmatter 추가
3. (선택) hooks 패턴 추가 제안 — `.ax/hooks/pre-commit/critical-rule-grep.sh`에 grep 라인 (수동)

각 단계 ✓로 보고:
```
✓ AX:CRITICAL:003 추가 — CLAUDE.md (security)
✓ mistake 3건 promoted_to=AX:CRITICAL:003 마킹
✓ pre-commit grep 패턴 추가 권장 (수동) — `secret_key|api_key|password\s*=`
```

## 절대 금지

- 사용자 동의 없이 룰을 자동 승격 X
- mistakes 파일 삭제 X — 이력은 보존
- 1회만 있는 패턴은 승격 후보로 띄우지 않음 (소음)
- 캡처만 하고 audit 안 함 → 누적만 됨 (주 1회는 회고)

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- cross_cut.mistakes.last_audit, due_in_days

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
# canonical 갱신 — derived value + updated_at (mistakes.count, last_audit, due_in_days 포함)
bash .ax/scripts/bash/update-state.sh

# 메타데이터만
jq '.last_skill = "audit" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
