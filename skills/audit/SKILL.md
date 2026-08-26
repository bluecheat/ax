---
name: audit
description: "Mistake Loop **회고·승격** skill (read+aggregate, review phase). 누적된 .ax/mistakes/*.md 를 카테고리·빈도로 분석하고 룰 승격 후보 제시. 트리거: '/audit', 'goax audit', '실수 회고', '실수 분석', '실수 패턴 분석', 'mistakes 정리', 'mistakes 점검', '재발', '같은 문제', '룰 승격', '룰 강화 후보', '또 그걸', '주간 회고'. **'회고'·'심사'·'정리'·'패턴'·'승격'·'재발' 같은 review 의도 키워드만 매칭** — '기록'·'캡처'·'남겨' 같은 capture 의도는 mistake skill 이 담당. 1건 새로 캡처하지 않음 (mistake skill 위임)."
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
  제안 SP-SEC-NNN — 시크릿 hardcode 절대 금지 (frontmatter severity: critical, enforced_by: hook:...)
  생성 .ax/spirit/rules/<project>-security.md 에 SP-SEC-NNN 추가 (없으면 신설)
        frontmatter paths: ["**/*.kt", "**/*.kts", ...] 명시 — path-scoped hook 이 매 작업 inject
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
  제안 SP-PR-NNN — refactor + feature 한 PR 금지 (severity: mandatory, enforced_by: human:pr-review)
  생성/수정/영향 (spirit/rules 만)

 [d] naming → 🔵 CONVENTION      [선택]
  패턴 파일명 underscore vs kebab 혼재 2회
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

## 4. 적용 — 3단계 강제 (마킹 → 룰 본문 → archive)

**3단계 모두 완료해야 audit 종료.** 1·2단계만 하고 보고하면 mistake 가 `.ax/mistakes/` root 에 promoted_to 마킹된 채 누적됨 (시각적 잔재 + 후속 audit 노이즈). 3단계 archive 까지 강제.

사용자 승낙 후, 카테고리당:

### 4.1 mistake 마킹 — `promote-mistake.sh --apply`

```bash
RESULT=$(bash .ax/scripts/bash/promote-mistake.sh --apply --json \
   --token SP-SEC-001 \
   --category security)
MARKED=$(echo "$RESULT" | jq -r '.result.marked_count')
```

스크립트가 하는 일 — **mistake 파일 frontmatter 에 `promoted_to: <token>` 추가만**.
CLAUDE.md / spirit/rules 는 안 건드림 (룰 본문 작성은 LLM 책임).

### 4.2 룰 본문 — LLM 이 spirit/rules 에 직접 Edit (필수, 스킵 금지)

`.ax/spirit/rules/<project>-<category>.md` 에 SP-<CAT>-NNN 추가:

```markdown
---
category: security
applies_to: [code, pr, review]
keywords: [secret, api-key, password, ...]
paths:
  - "**/*.kt"
  - "**/*.properties"
  - "**/*.yaml"
severity: critical
enforced_by:
  - hook:.ax/hooks/pre-commit/critical-rule-grep.sh
enforced_kind: block
---

## SP-SEC-001: 시크릿·API 키·비번 hardcode 금지
- 위반 예: `password = "..."`, `apiKey: "ghp_..."`, `private val pgKey = "rk_live_..."`
- 대안: AWS Secrets Manager / Vault / 환경변수 (CI/CD secret store)
- 검증: pre-commit grep `(password|secret|api[_-]?key|token).*=.*["']`
```

**압축·탈맥락 원칙 (룰 본문·CLAUDE.md 공통)**

룰은 매 turn hook 으로 inject 돼요. verbose 하면 매 작업마다 토큰 낭비. 그리고 매번 새 세션에서 읽히는 evergreen 문서 — 이전 세션 흔적 (시간 부사·발견 경위·일회성 ref) 이 본문에 박히면 6개월 뒤엔 노이즈.

**압축**
- **3줄 골격 권장** — `위반 예` / `대안` / `검증`. 헤더 1줄 + 본문 3 bullet = 4줄로 끝나면 베스트.
- **한 줄 한 사실** — 한 bullet 에 사실 1개. "A 이고 B 이며 C" 는 3 bullet 으로 쪼개기.
- **의례적 표현 제거** — "다음과 같이", "~할 수 있어요", "참고로", "필요시", "일반적으로" 다 삭제. `~해요` 체 자체는 유지 (tone).
- **단정·명령형** — "~하면 좋습니다" → "~해요" / "~금지". 완곡 어법 X.
- **약어 OK** — PR, DB, API, CI, regex 같은 표준 약어는 그대로. 처음 등장 풀네임 X.
- **보존 필수 (절대 압축 X)** — 코드블록(백틱), URL, SP 토큰 (`SP-SEC-001`), 파일경로, 정규식, frontmatter 스키마. 식별자·기술용어는 원본 유지.
- **목표 길이** — CRITICAL/MANDATORY 룰: 헤더 포함 5~8줄. CONVENTION 룰: 3~5줄. 10줄 넘으면 압축 부족.

**탈맥락 (세션·시간 흔적 금지)**
- **시간 부사 X** — "이번 세션에서", "방금 전", "최근", "어제", "지난 주", "현재 audit 에서" 모두 삭제. 룰은 시간 불변.
- **일회성 ref X** — 특정 PR 번호 (`PR #1234`), 이슈 ID, 절대 날짜 (`2026-05-17`), 커밋 SHA 본문에 박지 말기. 식별자는 SP 토큰 하나로 충분.
- **발견 경위 X** — "이번 audit 에서 발견", "OO 가 제보", "사건 X 로 추가" 같은 출처는 mistake 파일 (archive 후 보존) 의 책임. 룰 본문은 패턴·대안·검증만.
- **세션 자아 X** — "내가 분석한 결과", "조사해보니" 같은 1인칭/조사 표현 삭제. 룰은 사실의 진술.

before / after 예시:

```diff
- ## SP-SEC-001: 이번 audit (2026-05-17) 에서 PR #1234 통해 발견된 시크릿 노출 패턴 — 절대 금지합니다
- - 일반적으로 다음과 같은 패턴이 위반 예시가 될 수 있어요: `password = "..."`, `apiKey: "ghp_..."`
- - 최근 사건들을 보면 AWS Secrets Manager 나 Vault 같은 시크릿 매니저, 혹은 환경변수를 사용하시면 됩니다
- - 제가 조사해보니 pre-commit hook 에서 정규식 `(password|secret|api[_-]?key|token).*=.*["']` 로 grep 하면 좋아요
+ ## SP-SEC-001: 시크릿·API 키·비번 hardcode 금지
+ - 위반 예: `password = "..."`, `apiKey: "ghp_..."`, `private val pgKey = "rk_live_..."`
+ - 대안: AWS Secrets Manager / Vault / 환경변수
+ - 검증: pre-commit grep `(password|secret|api[_-]?key|token).*=.*["']`
```

**왜 spirit/rules 만?**: path-scoped hook (`spirit-rules-inject.sh`) 이 매 작업마다 frontmatter `paths:` 매칭해서 자동 inject — 매 turn CLAUDE.md 에 누적할 필요 없음. Constitution(AGENTS.md) 은 META(Triage First)·핵심 가드만 유지 (heavy 회피).

**plugin shipped 파일 append 금지**: `security.md`, `ops.md` 같은 plugin 출고본에 직접 append X. project-specific 별도 파일 (`<project>-<category>.md`) 로 만들고, 같은 카테고리 룰이 누적되면 그 파일에 SP-<CAT>-NNN 만 추가.

**완료 검증 (다음 단계 진입 전 필수)** — `grep '^## SP-SEC-001' .ax/spirit/rules/*.md` 가 1줄 이상 hit 해야 함. 0 hit 면 룰 본문 안 쓰인 것 — 추가 Edit 후 재검증. 0 hit 인 채로 4.3 시도하면 archive 스크립트가 `SP token not found` 에러로 거부.

### 4.3 archive — `promote-mistake.sh --archive` (필수)

룰 본문 작성·검증 완료 후 마킹된 mistake 들을 `_archive/<YYYY>/<MM>/` 로 이동:

```bash
RESULT=$(bash .ax/scripts/bash/promote-mistake.sh --archive --json --token SP-SEC-001)
ARCHIVED=$(echo "$RESULT" | jq -r '.result.archived_count')
```

스크립트가 하는 일 — `promoted_to: <token>` 마킹된 mistake 를 `.ax/mistakes/_archive/<YYYY>/<MM>/` 로 mv. 사전 검증 — SP 토큰이 `spirit/rules/*.md` 에 `## <token>` 헤딩으로 존재해야만 진행 (없으면 `SP token not found` 에러).

archived 파일은 maxdepth 1 scan 에서 자동 제외 — 후속 audit candidate · count · HUD state 모두 정확.

**완료 검증 (보고 직전 필수)**:
- `grep -l "^promoted_to: SP-SEC-001" .ax/mistakes/*.md 2>/dev/null` 결과 0줄 (root 에서 사라짐)
- `ls .ax/mistakes/_archive/<YEAR>/<MONTH>/` 에 archived 파일 N개

각 단계 ✓ 보고:
```
✓ mistake 3건 promoted_to=SP-SEC-001 마킹 (.ax/mistakes/)
✓ SP-SEC-001 추가 — .ax/spirit/rules/<project>-security.md (frontmatter paths: 명시)
✓ archive 3건 → .ax/mistakes/_archive/2026/05/ (audit candidate 검색에서 제외됨)
✓ path-scoped hook 활성 — 매 .kt / .properties / .yaml 편집 시 SP-SEC-001 자동 inject
```

## 절대 금지

- 사용자 동의 없이 룰을 자동 승격 X
- mistakes 파일 삭제 X — 이력은 보존 (archive 는 mv 이지 rm 아님)
- 1회만 있는 패턴은 승격 후보로 띄우지 않음 (소음)
- 캡처만 하고 audit 안 함 → 누적만 됨 (주 1회는 회고)
- **마킹 (4.1) 만 하고 룰 본문 (4.2) 또는 archive (4.3) 스킵 후 보고 X** — promoted_to 마킹된 mistake 가 `.ax/mistakes/` root 에 남아있으면 미완료. 4.3 archive 까지 끝낸 후 검증 (root 에 promoted_to 마킹 0건) 후 보고.

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
