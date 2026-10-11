---
name: audit
description: "쌓인 실수 기록(.ax/mistakes/)을 돌아보고 반복 패턴과 룰 승격 후보를 찾을 때 써요 — 여러 건을 보는 회고예요. 트리거: '/audit', 'goax audit', '실수 회고', '실수 분석', '실수 패턴 분석', 'mistakes 정리', 'mistakes 점검', '재발', '같은 문제', '또 그걸', '룰 승격', '룰 강화 후보', '주간 회고'. 안 쓰는 경우: 방금 생긴 실수 1건을 남기는 일('기록'·'캡처'·'남겨'·'박아'·'적어' — mistake), 룰이 실제로 걸려 있는지 점검(doctor)."
---

# goax audit — Mistake Loop (캡처 → 심사 → 승격)

## 핵심 사상
> "agent 실패 시 코드를 고치지 않고 하네스를 고친다."

같은 실수가 N번 반복되면 → 그건 룰로 박힐 신호.

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거 — review 의도만

audit 은 **누적된 mistakes 회고·승격 전용**. 새 mistake 캡처는 `mistake` skill 의 책임.

- 주기 도래: `mistake_loop.audit_cadence_days` (config.yml) 임박/초과
- 사용자 명시 호출: "goax audit", "/audit", "실수 회고", "이번 주 mistakes 정리", "주간 회고"
- 패턴 의심: "또 그걸…", "같은 문제", "재발", "룰 승격 후보 보여줘"

> **capture 의도와 구분**: 사용자가 "이거 mistake 로 박아줘", "방금 실수 기록" 같이 표현하면 audit 이 아니라 `mistake` skill 발동. audit 호출 시 사용자가 capture 의도라고 판단되면 짧게 묻기 — "audit (누적 회고) 인가요, mistake skill (1건 capture) 인가요?"

## 1. 캡처 — `mistake` skill 에 위임

캡처는 별도 skill (`mistake`) 의 책임. 사용자가 `audit` 호출했는데 새 mistake 가 있으면:

1. 사용자에게 짧게 묻기 — "이번에 캡처할 mistake 있나요? 있으면 `mistake` skill 로 먼저 1건씩 박고 audit 으로 돌아올게요."
2. 사용자 confirm → `mistake` skill 발동 → capture 끝나면 audit 본 작업 (스캔·승격) 으로 돌아옴.

직접 capture 하지 마세요 — `init-mistake-file.sh` 호출도 mistake skill 의 책임. audit 은 누적된 `.ax/mistakes/*.md` 만 읽음.

## 2. .ax/mistakes/ 스캔 — `promote-mistake.sh` 위임 

스크립트가 카테고리 분포 + 승격 후보를 계산해요. LLM은 결과 받아 사용자 인터랙션만:

```bash
# 후보 조회 (dry-run 기본 — 변경 없음). threshold 는 config.yml promotion_threshold (기본 3) 사용
RESULT=$(bash .ax/scripts/bash/promote-mistake.sh --json)

CANDIDATES=$(printf '%s\n' "$RESULT" | jq -r '.result.candidates')
TOTAL=$(printf '%s\n' "$RESULT" | jq -r '.result.total_categories')
```

추가 통계가 필요하면 (큰 프로젝트):
```bash
TOTAL=$(ls .ax/mistakes/*.md 2>/dev/null | grep -v README | wc -l)
find .ax/mistakes -name "*.md" -mtime -7 2>/dev/null | sort # 최근 7일
```

## 3. 출력 — 발견 + 승격 후보

```
◆  Audit (.ax/mistakes/ — N건 누적, 기간: <시작> ~ <끝>)

 📍 발견 카테고리별 분포
  security  N건
  data   M건
  pr    K건
  ...

 🎯 목표 반복 패턴 → CRITICAL/MANDATORY/CONVENTION 룰 승격
   (.ax/config.yml의 promotion_threshold 기준)

 ▸ 가이드 먼저 — 룰 본문은 "어떻게 해야 하나"(위치·이름·방법)로 시작해요. 막는 방법 우선순위는 그 가이드를
   무엇으로 집행할지 고르는 거지, 가이드를 대신하지 않아요. 금지만 적힌 룰은 피할 것만 알려주고
   쓸 것은 추측하게 둬서, 가장 가까운 선례(대개 잔재)를 따라 쓰게 돼요.

 ▸ 막는 방법 우선순위 — 후보마다 **위에서부터** 보고, 처음 해당하는 하나를 골라요. 문서만 두는 ④ 는 마지막이에요
   ① 구조로 제거할 수 있나? (디렉토리·타입·의존 방향으로 아예 못 쓰게)  → ADR + 리팩토링 task
   ② 이미 있는 lint/CI 가 잡을 수 있나? (ArchUnit·detekt 등)            → enforced_by: external:<도구> + 프로브
   ③ grep 한 줄로 잡히고, 걸리면 커밋을 멈춰야 하나?                     → 룰 아래 <!-- 검출 패턴: <ERE> --> (이번 커밋에서 집행)
   ④ 셋 다 아니면                                                        → 가이드만 (🟡/🔵 · 사람 게이트)
   근거: 룰·스킬·스타일 가이드는 soft — 모델은 잊어요. 리뷰 코멘트로 룰을 지키게 하는 순간이
   code smell 이고, 그 자리는 lint·CI 실패·구조 제거로 옮겨야 해요. ③ 은 이 스킬이 바로 해요.

 ▸ ③ grep 검사를 쓰지 않는 경우 — 가이드만 두고 ② CI 테스트로 올리거나 ④ 리뷰로 내려요
   · 경고로 끝나는 규약 — 이름·위치처럼 "다르게 하라" 로는 답이 안 나오는 룰. 경고는 틀렸다는 것만 알리고
     무엇을 쓸지는 가이드가 알려줘요. 구조로 잴 수 있으면 ② (ArchUnit 같은 CI 테스트 + 잔재 허용목록)
   · 잔재가 많은 패턴 — `critical-rule-grep.sh` 는 staged 파일 전체를 봐서, 잔재 파일을 건드릴 때마다 무관한
     경고가 떠요. 패턴을 넣기 전에 `grep -rlE '<ERE>' <paths> | wc -l` 로 잔재 수를 재서 후보에 적어요

 ─ 승격 후보 ──────────────────────────────────────

 [a] ✅ security → 🔴 CRITICAL     [권장 — 3회+]
  패턴 PG 키 평문 노출 2회 + DB 비번 로그 1회
  막는 방법 ③ grep 검사 — `(password|secret|api[_-]?key|token)[[:space:]]*[=:][[:space:]]*["'][^"']{6,}` (①·② 해당 없음)
  제안 SP-SEC-NNN — 시크릿 hardcode 절대 금지 (frontmatter severity: critical, enforced_by: hook:...)
  생성 .ax/spirit/rules/<project>-security.md 에 SP-SEC-NNN 추가 (없으면 신설)
        frontmatter paths: ["**/*.kt", "**/*.kts", ...] 명시 — 주입 훅과 grep 집행 둘 다 이 paths 를 봐요 (비면 둘 다 안 돌아요)
  ※ plugin shipped 파일 (security.md, ops.md 등) 직접 append 금지 — project-specific 새 파일로 만들기
        (onboarding 절대 금지 #6 참조). plugin 갱신 시 clobber 방지.
  ※ CLAUDE.md 는 안 건드림 — 룰 본문은 spirit/rules 가 SSOT, hook 이 inject. CLAUDE.md 누적 = heavy
  수정 mistake 파일 3개에 promoted_to 마킹 (promote-mistake.sh --apply)
  영향 파일 1~2개 (spirit/rules + mistake 마킹)

 [b] data → 🔴 CRITICAL       [추천 — 2회]
  패턴 마이그레이션 down 누락 2회
  제안 SP-DATA-NNN — 모든 migration 은 down 포함
  생성/수정/영향 (위와 동일 패턴 — spirit/rules 만)

 [c] pr → 🟡 MANDATORY       [검토]
  패턴 refactor + feature 한 PR 로 묶음 4회
  막는 방법 ④ 리뷰 — 한 PR 의 의도는 diff 로 못 재요 (①~③ 해당 없음)
  제안 SP-PR-NNN — refactor + feature 한 PR 금지 (severity: mandatory, enforced_by: human:pr-review)
  생성/수정/영향 (spirit/rules 만)

 [d] naming → 🔵 CONVENTION      [선택]
  패턴 파일명 underscore vs kebab 혼재 2회
  막는 방법 가이드 + ② CI 테스트 — "kebab-case 로 짓는다" 가 본문, 기존 lint 가 파일명을 보면 거기로 (③ 경고만으론 무엇을 쓸지 안 나와요)
  제안 SP-NAMING-NNN 추가 (.ax/spirit/rules/<project>-naming.md, severity: convention)
  생성/수정/영향 (spirit/rules 만)

 [e] 모두 보류 — 다음 audit 으로

 ▸ 답해주세요 복수 가능: a,b / 또는 [e]
```

**규칙**
- `promotion_threshold` (기본 3) 이상이면 `[권장]` 라벨
- 2회는 `[추천]`, 1회는 안 띄움 (소음)
- 옵션은 카테고리 단위 — 사용자가 복수 선택 가능 (예: `a, b`)
- 항상 마지막에 `[e]` 모두 보류 옵션

## 4. 적용 — `rule` skill 에 넘겨요

사용자가 고른 카테고리마다, audit 은 그 카테고리의 mistake 파일 목록을 들고 `rule` skill 의 "mistake → 룰" 모드로 넘어가요.
룰 본문 작성, 검사(rule-lint, 프로브, 신입 테스트), mistake 마킹(`promote-mistake.sh --apply --file`), archive 는 모두 `rule` skill 이 해요.
이유: 룰을 쓰는 길이 audit, onboarding, 세션 요청으로 갈라져 있으면, 형식 기준이 한 곳에서만 지켜져요.

넘길 때 audit 이 정해 둔 값:

| 값 | 어디서 |
|---|---|
| mistake 파일 목록 | §2 스캔 결과에서 그 카테고리 파일 |
| severity 제안 | §3 의 🔴/🟡/🔵 |
| 막는 방법 | §3 의 ①–④ 판정. ③ 이면 결정형, ④ 면 비결정형으로 `rule` §3 에 넘겨요 |

카테고리가 여럿이면 하나씩 차례로 넘겨요. 한 카테고리의 `rule` 이 끝나야(archive 까지) 다음 카테고리로 가요.

**완료 검증 (보고 직전)**:
- `grep -l "^promoted_to:" .ax/mistakes/*.md 2>/dev/null` 결과가 0줄이에요. 남아 있으면 `rule` §8 의 archive 가 안 끝난 거예요.
- 고른 카테고리마다 새 SP 헤더가 `.ax/spirit/rules/` 에 1줄씩 있어요.

## model 분포 — 어느 모델에서 몰리나

`model` frontmatter 가 쌓이면 카테고리와 교차해서 볼 수 있어요.

```bash
grep -h '^model:' .ax/mistakes/*.md .ax/mistakes/_archive/*/*/*.md 2>/dev/null \
  | awk '{print $2}' | sort | uniq -c | sort -rn
```

읽는 법 — **모델을 탓하는 지표가 아니에요.** 특정 모델에 특정 카테고리가 몰리면
그건 보통 *그 모델에 안 맞는 지시* 라는 신호예요. 룰을 그 모델이 지킬 수 있는
형태로 다시 쓰는 게 대응이에요.

`unknown` 이 많으면 감지가 안 되는 환경(다른 CLI·CI)에서 캡처된 거예요. 문제 아니에요.

## 절대 금지

- 사용자 동의 없이 룰을 자동 승격 X
- mistakes 파일 삭제 X — 이력은 보존 (archive 는 mv 이지 rm 아님)
- 1회만 있는 패턴은 승격 후보로 띄우지 않음 (소음)
- **커밋을 멈춰야 하는 룰을 패턴 없이 산문으로만 승격 X** — ③ grep 검사로 막는 룰이면 `<!-- 검출 패턴: -->` 이 룰 본문의 일부예요. 산문만 쓰면 다음 audit 에 같은 카테고리가 또 올라와요
- **가이드 없이 금지·경고만 있는 룰로 승격 X** — `대안` 이 없으면 모델은 가장 가까운 선례(대개 잔재)를 따라 써요. 경고로 끝나는 규약은 ③ grep 검사 대신 가이드 + ② CI 테스트로 가요
- 캡처만 하고 audit 안 함 → 누적만 됨 (주 1회는 회고)
- 룰 본문을 audit 안에서 직접 Edit 하지 않아요. `rule` skill 에 넘겨요 (§4). archive 까지 끝나기 전에는 완료로 보고하지 않아요.

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- cross_cut.mistakes.last_audit, due_in_days

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
# canonical 갱신 — derived value + updated_at (mistakes.count, last_audit, due_in_days 포함) + last_skill·skill_calls
bash .ax/scripts/bash/update-state.sh --skill audit
```
