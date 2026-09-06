---
name: doctor
description: "goax 설치 상태 진단 — 'goax doctor', 'goax 진단', '하네스 점검', 'goax 상태', 'spirit 점검', 'spirit lint', 'rules 보여줘', '룰 인덱스', 'CRITICAL 룰만' 트리거. 4계층 + cross-cut + sensors 결손, Spirit 무결성, 룰 통합 인덱스, 룰이 실제로 세션에 닿는지(도달 지도)를 스크립트로 검사하고 다음 단계를 안내. 슬래시로도 호출 가능: '/doctor'."
---

# goax doctor — 4계층 결손 진단

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거
- `/doctor`, `goax doctor`, "goax 진단", "하네스 점검", "goax 상태"
- "spirit 점검", "spirit lint" → §3.7 만 (Spirit lint 단독 보고)
- "rules 보여줘", "룰 인덱스", "CRITICAL 룰만", "SP-SEC-001 찾아줘" → §3.13 만 (룰 인덱스 단독 보고)
- `--strict` 도 인식 (placeholder 를 통과로 안 보고 fail 처리)

## 0. 원칙 — 판정은 스크립트, 보고와 옵션은 여기

결손 검사는 전부 `.ax/scripts/bash/*.sh --json` 이 해요. doctor 는 JSON 을 읽어 섹션으로 그리고, **자동 수정하지 않고** 사용자에게 옵션을 제시해요. 산문 bash 로 다시 세지 않아요 — 같은 걸 두 곳에서 세면 언젠가 둘이 달라져요.

## 1. PROJECT_ROOT 감지

`.ax/` 가 있는 가장 가까운 디렉토리: 자기 + 조상 → 자식(2~4단) → 없으면 `먼저 'goax 도입해줘'라고 말해주세요`.
다른 디렉토리에서 발동되면 알려요: `⚠ 현재 디렉토리에 .ax/가 없어요. <root> 의 설치를 진단해요.`

```bash
if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else PLUGIN_ROOT=""; fi
ROOT=$(pwd)   # 또는 감지한 PROJECT_ROOT
```

## 2. 빠른 사전 통계

```bash
echo "Spirit rules: $(ls "$ROOT"/.ax/spirit/rules/*.md 2>/dev/null | wc -l) 카테고리"
echo "ADR: $(ls "$ROOT"/.ax/docs/adr/*.md 2>/dev/null | wc -l) · Spec: $(ls -d "$ROOT"/.ax/docs/spec/[0-9][0-9][0-9]-* 2>/dev/null | wc -l) · Mistakes: $(ls "$ROOT"/.ax/mistakes/*.md 2>/dev/null | grep -v README | wc -l)"
grep -h "^category:" "$ROOT"/.ax/mistakes/*.md 2>/dev/null | awk '{print $2}' | sort | uniq -c | sort -rn   # 미승격 mistakes
```

## 3. 검사 — 스크립트 → 섹션

| Layer / 섹션 | 검사 | 스크립트 |
|---|---|---|
| **Layer 1** | Constitution 존재 + 시그널 라벨 + 4계층 인덱스 표 | `rules-index.sh` (§3.13) · `doctor-scan.sh reach` (§3.8) |
| **Layer 0 / 설정** | `.ax/config.yml` (domain_risk 5+ 권장) + `.ax/version` | `zero-domain-risk.sh --show` |
| **Cross-cut Spirit** | values/tone placeholder · rules/ 1개+ · 헤더 형식 · 토큰 중복 | `spirit-lint.sh` (§3.7) |
| **Cross-cut Mistake Loop** | `.ax/mistakes/` 존재 | — |
| **Layer 3** | `.ax/docs/adr/` 1개+, `_templates/spec/` (drift 는 §3.5) | — |
| **Layer 2** | `.ax/modules/*/rules.md` 카운트 + 도달 | `doctor-scan.sh reach` |
| **Sensors / Hooks** | hook 디렉토리 + settings.json + template hook 전체 등록 | `doctor-scan.sh hooks` (§3.7) |
| **Rule Enforcement** | `enforced_by` invariant I1~I6 | `check-rule-enforcement.sh` (§3.9) |
| **Sensors — Liveness** | 장치 생사 C1~C4 | `check-sensor-liveness.sh` (§3.10) |
| **번호 무결성** | spec/ADR 중복 번호 | `next-spec-num.sh --check-duplicates` (§3.11) |
| **동봉본** | vendored skills 신선도 | `vendor-skills.sh --check` (§3.12) |
| **인계 노트** | STATUS.md 기한(`- [ ] YYYY-MM-DD`) 임박·초과 — zero 의 가정 검증 · ablation 재검토 | `doctor-scan.sh handoff` (§3.6~) |

각 항목 ✅ / ⚠️ / ❌. 규칙은 §4.

### 3.5 Plugin update 반영 — version + 출고 자산 신선도

핵심 질문: **"현재 설치 == 최신 plugin 출고?"** 세 신호를 한꺼번에 보고 **단일 y/n** 으로 처리해요. 모두 "plugin 갱신 후 `/up` 재호출 안 함" 이 원인이라 따로 물으면 인지 부담만 커요.

```bash
INSTALLED_V=$(tr -d '[:space:]' < "$ROOT/.ax/version" 2>/dev/null)
STATE_V=$(jq -r '.goax_version // ""' "$ROOT/.ax/state.json" 2>/dev/null)
PLUGIN_V=""; [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/VERSION" ] && PLUGIN_V=$(tr -d '[:space:]' < "$PLUGIN_ROOT/VERSION")
VERSION_DRIFT=false; [ -n "$PLUGIN_V" ] && [ "$INSTALLED_V" != "$PLUGIN_V" ] && VERSION_DRIFT=true

RESULT_T=$(bash "$ROOT/.ax/scripts/bash/check-templates-drift.sh" --json ${PLUGIN_ROOT:+--plugin-dir "$PLUGIN_ROOT"} 2>/dev/null)
PLUGIN_UPD=$(echo "$RESULT_T" | jq -r '.result.plugin_updated // false')
USER_MOD=$(echo "$RESULT_T" | jq -r '.result.user_modified // false')
DRIFT_FILES=$(echo "$RESULT_T" | jq -r '.result.drift_files // [] | join(", ")')

RESULT_M=$(bash "$ROOT/.ax/scripts/bash/check-manifest-install.sh" --json ${PLUGIN_ROOT:+--plugin-dir "$PLUGIN_ROOT"} 2>/dev/null)
MI_STATUS=$(echo "$RESULT_M" | jq -r '.status // "skipped"')
MI_MISSING_N=$(echo "$RESULT_M" | jq -r '.result.missing // [] | length')
MI_DRIFT_N=$(echo "$RESULT_M" | jq -r '.result.drift // [] | length')

NEEDS_REINSTALL=false
{ [ "$VERSION_DRIFT" = true ] || [ "$PLUGIN_UPD" = true ] || [ "$MI_MISSING_N" -gt 0 ] || [ "$MI_DRIFT_N" -gt 0 ]; } && NEEDS_REINSTALL=true

# changelog 발췌 — INSTALLED_V < ver <= PLUGIN_V 의 제목만 (사용자가 [y] 전에 "무엇이 바뀌는지")
CHANGELOG_LINES=()
if [ "$VERSION_DRIFT" = true ] && [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_ROOT/changelog" ]; then
    while IFS= read -r f; do
        ver=$(basename "$f" .md)
        [ "$(printf '%s\n%s\n' "$INSTALLED_V" "$ver" | sort -V | tail -1)" = "$ver" ] && [ "$ver" != "$INSTALLED_V" ] || continue
        [ "$(printf '%s\n%s\n' "$ver" "$PLUGIN_V" | sort -V | tail -1)" = "$PLUGIN_V" ] || continue
        CHANGELOG_LINES+=("- $(head -1 "$f" | sed -E 's/^#[[:space:]]*//')")
    done < <(ls "$PLUGIN_ROOT/changelog/"*.md 2>/dev/null | grep -vE '/README\.md$' | sort -V)
fi
```

> drift 감지 범위: `check-templates-drift.sh` 는 `_templates/spec/` sha 비교. 나머지 MANIFEST 출고분(`hooks/`, `scripts/bash/`, `modules/`, `docs/`)은 `check-manifest-install.sh` 가 파일 단위. `.ax/spirit/{values,tone,README}.md` · `spirit/rules/` 는 사용자 영역이라 검증 대상 아님.

보고: `NEEDS_REINSTALL=false && USER_MOD=false` → 생략. `USER_MOD` 만 → `ℹ️  _templates 사용자 수정 감지 (정상): $DRIFT_FILES`. `MI_STATUS=skipped` → `ℹ️  plugin shipped 검증 skip — plugin 컨텍스트에서 실행 권장`. `NEEDS_REINSTALL=true` →

```
🔄  Plugin update 반영
   ⚠️  신규 버전 출고 미반영 — installed $INSTALLED_V → plugin $PLUGIN_V
   변경 내역 (changelog 발췌, 8개 cap):  <CHANGELOG_LINES>
   감지된 drift:  version 3-way · MANIFEST 누락 N (5개 cap) · MANIFEST drift N · _templates 갱신 $DRIFT_FILES

 [u] ✅ 전체 업데이트 파일 덮어쓰기                       [추천]
   명령 "goax up" 또는 /up — MANIFEST 기반 cp -R backfill + drift 덮어쓰기 + .ax/version 갱신 (idempotent)
   보존 사용자 customize 자산은 .suggested 패턴. 사용자가 고친 출고분(scripts/hooks)은 덮어써요 — git diff 로 사후 검토
 ▸ 답해주세요 [y/n]
```

옵션을 하나로 좁힌 이유: 답이 거의 항상 yes 라서. 사용자 수정 보호는 git 이 해요.

### 3.6 · 3.7(hook) · 3.8 · 도달 지도 — `doctor-scan.sh`

```bash
SCAN=$(bash "$ROOT/.ax/scripts/bash/doctor-scan.sh" --json ${PLUGIN_ROOT:+--plugin-dir "$PLUGIN_ROOT"} 2>/dev/null)
S_FIND=$(echo "$SCAN" | jq -r '.result.findings // 0')
S_GI=$(echo "$SCAN" | jq -r '.result.migration.gitignore_missing | join(", ")')
S_OS=$(echo "$SCAN" | jq -r '.result.migration.stale_output_style')
S_SG=$(echo "$SCAN" | jq -r '.result.migration.suggested | join(", ")')
S_SR=$(echo "$SCAN" | jq -r '.result.migration.spec_readme_stale | length')
S_SE=$(echo "$SCAN" | jq -r '.result.migration.spec_empty_dirs | length')
H_CHK=$(echo "$SCAN" | jq -r '.result.hooks.checked')
H_TOT=$(echo "$SCAN" | jq -r '.result.hooks.total'); H_REG=$(echo "$SCAN" | jq -r '.result.hooks.registered_n')
H_MISS=$(echo "$SCAN" | jq -r '.result.hooks.missing | join("\n")'); H_MF=$(echo "$SCAN" | jq -r '.result.hooks.missing_files | join("\n")')
D_MM=$(echo "$SCAN" | jq -r '.result.doc_actual.mismatches | join("\n")')
R_BAD=$(echo "$SCAN" | jq -r '.result.reach[] | select(.reached==false) | "\(.source) (\(.count)) — \(.reason)"')
E_MISS=$(echo "$SCAN" | jq -r '.result.hooks.events.missing | join(", ")')
D_BAD=$(echo "$SCAN" | jq -r '.result.handoff.deadlines[] | select(.status!="ok") | "\(.status) \(.date) (\(.days_left)일) — \(.text)"')
```

**3.6 마이그레이션 잔재** (0건이면 생략):
```
🧹  마이그레이션 잔재
   ⚠️ .gitignore 누락 엔트리 — <S_GI>
   ⚠️ .ax/spirit/rules/output-style.md — plugin meta 로 분류되어 출고에서 제거됨
   ⚠️ 미처리 .suggested — <S_SG> (머지 후 rm)
   ⚠️ spec README.md 잔재 <S_SR>건 · 빈 checklists/contracts <S_SE>건 (slim 정책 — rm/rmdir 권장)
```
다음 단계 `[m] ✅ 마이그레이션 잔재 처리 — .gitignore 보강 + 잔재 제거 (사용자 동의 후, git 영향)`.

**3.7 hook 등록** (`H_CHK=false` 면 통째로 skip — plugin 경로 미도출. `H_MISS` 비었으면 본 표의 ✅ 만):
```
🪝  Sensors — settings.json hook 등록
   ⚠️  template hook <H_REG>/<H_TOT> 등록 — 미등록: <H_MISS 한 줄씩>
   ❌ 초기 설치 미완 — .ax/hooks/ 안에 없는 항목: <H_MF 한 줄씩>   ← 비었으면 생략. /up 재실행으로만 복원
   ⚠️  이벤트 키 미등록: <E_MISS>   ← settings.json 에 그 이벤트가 아예 없어요. Stop·SubagentStart 는 나중 판에 생긴 hook —
       파일은 /up 이 깔았는데 키가 없으면 안 돌아요. .ax/settings.json.suggested 머지 또는 template 을 읽어 jq 로 append
```
다음 단계 `[s] ✅ template hook 등록 — 1순위 bash .ax/scripts/bash/register-spirit-hook.sh (path-scoped inject, idempotent) → 나머지는 .ax/settings.json.suggested 머지 또는 template 을 읽어 jq 로 append (백업 후, 사용자 키 보존). 파일 자체가 없으면 /up`. hook 셋은 template 이 정해요 — doctor 는 이름을 hardcode 하지 않아요.

**3.8 문서 ↔ 실제** (`D_MM` 비었으면 생략):
```
📑  문서 ↔ 실제 일치
   ⚠️  <D_MM 한 줄씩 — 예: Constitution 은 shim 메커니즘을 명시 — 폐기됨>
```
다음 단계 `[d] ✅ Constitution 의 path-scoped 설명 갱신 — 현재 활성 메커니즘(PreToolUse hook, spirit-rules-inject.sh)으로 (사용자 + LLM 이 함께)`. 왜: 세션마다 컨텍스트가 달라 한 세션이 옛 설계 언어로 문서를 되돌릴 수 있어요. 실제 hook 은 도는데 문서가 다른 메커니즘을 가리키면 신뢰가 깎여요.

**도달 지도** (`R_BAD` 비었으면 본 표의 ✅ 만):
```
🗺   도달 지도 — 룰이 실제로 세션에 닿는가
   ✗ constitution (12) — CLAUDE.md 가 없어요. Claude Code 는 AGENTS.md 를 읽지 않아서 Constitution 이 어디에도 안 가요
   ✗ spirit-scoped (3) — paths: 있는 룰인데 spirit-rules-inject.sh 미등록 — 편집 시점에 안 닿아요
   ✗ module (2) — module-rules-inject.sh 미등록 — triage 키워드 매칭만 남아요
```
다음 단계 `[reach] ✅ 배관 잇기 — constitution: CLAUDE.md 에 '@AGENTS.md' 한 줄 / spirit-universal: Constitution CONVENTION 절에 @import / scoped·module: [s] hook 등록`. **라벨이 완벽해도 배관이 끊기면 룰은 0개예요** — 이 표가 doctor 에서 가장 먼저 봐야 할 줄이에요.

**인계 노트 기한** (`D_BAD` 비었으면 생략) — `.ax/docs/STATUS.md` 의 `- [ ] YYYY-MM-DD …` 를 I3 와 같은 규칙(≤7일 임박 · 초과)으로 봐요. zero 의 "1순위 가정 검증" 과 "룰 ablation 재검토" 가 여기 살아요 — 날짜가 문서 안에만 있으면 아무도 안 봐요.
```
📅  인계 노트 기한
   ⚠️  overdue 2026-03-01 (-12일) — 룰 ablation 재검토 (.ax/_templates/zero/ablation.md)
   ⚠️  imminent 2026-09-10 (4일) — 1순위 위험 가정 "…" 을 …으로 검증
```
다음 단계 `[k] ✅ 기한 처리 — 하거나(ablation 이면 zero-ablation.sh --off → 실제 작업 5회 → --on, 이게 다음 기한을 다시 적어요) 날짜를 옮기거나(status-note.sh --done next "…" · --add next "- [ ] <새 날짜> …"). 세 번 넘게 미루면 그 항목은 할 생각이 없는 거예요 — 지우세요`.

### 3.7 Spirit lint — `spirit-lint.sh`

```bash
SL=$(bash "$ROOT/.ax/scripts/bash/spirit-lint.sh" --json 2>/dev/null)
SL_OK=$(echo "$SL" | jq -r '.result.ok'); SL_N=$(echo "$SL" | jq -r '.result.findings')
SL_RC=$(echo "$SL" | jq -r '.result.rules_files'); SL_TK=$(echo "$SL" | jq -r '.result.rules_count')
SL_BAD=$(echo "$SL" | jq -r '.result.bad_headers[] | "\(.file):\(.line) — \(.text)"')
SL_DUP=$(echo "$SL" | jq -r '.result.duplicates[] | "\(.token) — \(.files | join(", "))"')
SL_MISS=$(echo "$SL" | jq -r '.result.missing_files + .result.missing_frontmatter | join(", ")')
SL_PH=$(echo "$SL" | jq -r '.result.placeholders[] | "\(.file):\(.line)"')
```

헤더 형식 `## SP-<CAT>-<NNN>: 제목` 의 SSOT 는 `.ax/docs/reference/rules-tokens.md`. 0건이면 본 표 `🧠 Spirit` 의 ✅ 만:
```
🧪  Spirit lint — <SL_RC> 카테고리 · SP 토큰 <SL_TK>개
   ✗ 필수 파일/frontmatter — <SL_MISS>
   ⚠️ 비표준 헤더 — <SL_BAD 한 줄씩>
   ✗ 중복 토큰 — <SL_DUP 한 줄씩>
   ⚠️ placeholder 잔재 — <SL_PH 한 줄씩>
```
다음 단계 `[n] ✅ spirit lint 정리 — 비표준 헤더 수정 + 중복 토큰 해소 (사용자와 함께, 자동 수정 X)`. "spirit 점검" 으로 불렸으면 이 절만 보고하고 끝내요. `--strict` 면 placeholder 도 fail.

### 3.9 Rule Enforcement — `check-rule-enforcement.sh`

```bash
RESULT=$(bash "$ROOT/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null)
RE_I1=$(echo "$RESULT" | jq -r '.result.i1_violations | length'); RE_I2=$(echo "$RESULT" | jq -r '.result.i2_violations | length')
RE_I3IM=$(echo "$RESULT" | jq -r '.result.i3_imminent | length'); RE_I3OD=$(echo "$RESULT" | jq -r '.result.i3_overdue | length')
RE_I5F=$(echo "$RESULT" | jq -r '.result.i5_file_missing | length'); RE_I5R=$(echo "$RESULT" | jq -r '.result.i5_not_registered | length')
RE_I6=$(echo "$RESULT" | jq -r '.result.i6_no_trigger | length')
```

- **I1** 🔴 의 `enforced_by` 는 `hook:*`/`external:*` 만 · **I2** `TODO:*` 는 deadline 필수 · **I3** 임박(≤7일)/초과 · **I5** hook 파일 존재 + settings 등록 · **I6** `external:*` 면 자동 트리거(CI workflow / git pre-commit / husky / lefthook)가 실재 — goax wrapper 만 있는 pre-commit 은 트리거로 안 쳐요. 본문: `.ax/docs/reference/rule-enforcement.md`.

위반 0 이면 ✅ 만, 1+ 이면:
```
⚖️  Rule Enforcement
   ❌ I1 위반 — CRITICAL 인데 자동 차단 없음 (거짓 약속) N건: <rule_id (enforced_by, enforced_kind)>
   ❌ I2 위반 — TODO 인데 deadline 없음 N건
   ⚠️  I3 임박 N건 / 초과 N건 (deadline + days)
   ⚠️  I5 위반 — hook 파일 부재 N건 / 미등록 N건
   ❌ I6 위반 — external 인데 자동 트리거 없음 N건
```
다음 단계 (무거운 것부터): `[r] 라벨 강등 🔴→🟡 (I1) [최우선]` · `[w] hook 작성 후 🔴 유지 (장기)` · `[d] deadline 갱신 (강등 거부 시 — 3회 이상 연기는 강등 권장)` · `[g] deadline 입력 (I2)` · `[t] 트리거 설치 (I6) — CI 워크플로우 또는 프로젝트 전용 pre-commit + install-git-hooks.sh`. 강등은 사용자 의도 변경이라 명시 동의 필수.

### 3.10 Sensors — Liveness — `check-sensor-liveness.sh`

3.9 가 룰 **라벨**의 schema 를 본다면 이건 **장치**의 생사예요 — 라벨이 완벽해도 장치가 죽어 있으면 아무것도 차단되지 않아요.

```bash
RESULT_L=$(bash "$ROOT/.ax/scripts/bash/check-sensor-liveness.sh" --json 2>/dev/null)
L_SCAFFOLD=$(echo "$RESULT_L" | jq -r '.result.grep_scaffold_unfilled'); L_GITHOOK=$(echo "$RESULT_L" | jq -r '.result.git_precommit_installed')
L_BZ=$(echo "$RESULT_L" | jq -r '.result.blocking_zero'); L_RM=$(echo "$RESULT_L" | jq -r '.result.session_root_mismatch'); L_ROOT=$(echo "$RESULT_L" | jq -r '.result.project_root')
```
```
🫀 Sensors — Liveness
   ⚠️  C1 grep 훅 미작성/데모 잔존 — AGENTS.md 🔴 룰의 패턴을 채우거나 /up 재실행
   ⚠️  C2 git pre-commit 미설치 — bash .ax/scripts/bash/install-git-hooks.sh (사람 터미널 커밋은 PreToolUse 를 우회해요)
   ❌ C3 차단 능력 0 — mode=<sensors_mode> (+ git hook 부재). 지금 어떤 위반도 자동 차단되지 않아요
   ⚠️  C4 세션 루트 이탈 — 세션을 <L_ROOT> 에서 시작하세요
```

### 3.11 번호 무결성 — `next-spec-num.sh --check-duplicates`

```bash
N_SPEC=$(bash "$ROOT/.ax/scripts/bash/next-spec-num.sh" --kind spec --check-duplicates --json 2>/dev/null | jq -r '.result.duplicate_count // 0')
N_ADR=$(bash "$ROOT/.ax/scripts/bash/next-spec-num.sh" --kind adr --check-duplicates --json 2>/dev/null | jq -r '.result.duplicate_count // 0')
```
읽기 전용 · 자동 수정 X — 재번호는 기존 링크를 깨뜨려서 사람이 결정해요. 0 이면 생략: `🔢 번호 무결성 — ⚠️ ADR 중복 N건 / spec 중복 N건`.

### 3.12 동봉본 신선도 — `vendor-skills.sh --check`

```bash
VEN=$(bash "$ROOT/.ax/scripts/bash/vendor-skills.sh" --check --plugin-dir "$PLUGIN_ROOT" --json 2>/dev/null)
V_ON=$(echo "$VEN" | jq -r '.result.vendored // false'); V_STALE=$(echo "$VEN" | jq -r '.result.stale // false'); V_SPLIT=$(echo "$VEN" | jq -r '.result.split // false')
```
`vendored=false` 면 생략. `📦 동봉본 — ⚠️ 동봉 v<X> ↔ plugin v<Y>: /vendor 재실행 후 커밋 · ❌ ADE 루트 ≠ 프로젝트 루트인데 .goax-root 없음`.

### 3.13 룰 인덱스 — `rules-index.sh`

Constitution + Spirit + Module 세 소스를 한 인덱스로. "rules 보여줘" 로 불렸으면 **이 절만** 텍스트 모드 그대로 보여주고 끝내요 — 룰 본문은 요약하지 않아요 (원문이 정본).

```bash
bash "$ROOT/.ax/scripts/bash/rules-index.sh"                            # 인덱스 (사용자에게 그대로)
bash "$ROOT/.ax/scripts/bash/rules-index.sh" --level critical           # "CRITICAL 룰만"
bash "$ROOT/.ax/scripts/bash/rules-index.sh" --source spirit --category security
bash "$ROOT/.ax/scripts/bash/rules-index.sh" --find AX:CRITICAL:001     # 토큰 정확 매칭
RI=$(bash "$ROOT/.ax/scripts/bash/rules-index.sh" --json 2>/dev/null); RI_C=$(echo "$RI" | jq -r '.result.counts.critical'); RI_M=$(echo "$RI" | jq -r '.result.counts.mandatory'); RI_V=$(echo "$RI" | jq -r '.result.counts.convention')
```

전체 진단에선 `🏛️ Layer 1` 줄에 카운트만 써요: `✅ AGENTS.md (시그널 🔴×$RI_C / 🟡×$RI_M / 🔵×$RI_V, 4계층 인덱스 ✓)`. 룰은 외워서 적용하지 않아요 — 매번 이 스크립트로 다시 읽어요.

## 4. 출력

```
🩺 goax doctor — /path/to/your-project
    goax <installed> · preset=default · installed 2026-05-02

🏛️  Layer 1 — Constitution
   ✅ AGENTS.md (62줄, 시그널 🔴×3 / 🟡×9 / 🔵×1, 4계층 인덱스 ✓) · CLAUDE.md @AGENTS.md ✓
⚙️  Layer 0 — Triage / 설정
   ✅ config.yml (domain_risk 30 keys, default L1) · version
🧠  Cross-cut — Spirit
   ✅ values.md (사용자 정의됨) · ⚠️ tone.md placeholder · ✅ rules/ 4 카테고리 · lint ✓
🪤  Cross-cut — Mistake Loop
   ✅ mistakes/ (3건 누적)
🥕  Layer 3 — Spec / ADR
   ✅ docs/adr/ (1건) · ✅ _templates/spec/ · ⚠️ spec 0건 (첫 spec 권장)
📦  Layer 2 — Module Rules
   ✅ modules/ 5/13 (L2/L3 만) · 도달 ✓
🪝  Sensors — Hooks
   ✅ 디렉토리 4종 · settings.json · template hook 8/8 등록
🗺   도달 지도   ✅ constitution · spirit-universal · spirit-scoped · module

🎯  점수
   90%   (9 / 11)
   ▲ +7%p vs 직전 호출 (83% → 90%)        ← state.json 에 직전 점수 있을 때만
   ✅ 해소: version drift · scripts backfill

🚦  다음 단계
   [a] ✅ tone.md 우리 팀 말투로 수정    [추천]
       파일 .ax/spirit/tone.md · 이유 placeholder 그대로 — 모든 sub-agent 가 default 톤
   [b] 📝 첫 spec 작성 — "새 spec 만들어줘 — <slug>"
   ▸ 답해주세요 [a] / [b] / 또는 그냥 보고만
```

**규칙**
- 상태 emoji: ✅ pass · ⚠️ placeholder/주의/drift · ❌ 누락/실패 · ℹ️ 정보. 🟡 는 doctor 상태로 쓰지 않아요 — CLAUDE.md 시그널 전용.
- 섹션 emoji: 🏛️ Constitution · ⚙️ 설정 · 🧠 Spirit · 🪤 Mistake · ⚖️ Rule Enforcement · 🥕 Spec/ADR · 📦 Module · 🪝 Sensors · 🗺 도달 지도 · 🔄 Plugin update · 🧪 Spirit lint · 📑 문서↔실제 · 🧹 잔재 · 📜 룰 인덱스 · 🎯 점수 · 🚦 다음 단계
- 다음 단계는 결손이 큰 것부터. 도달 결손 > I1/C3 > 등록 > placeholder 순.
- 점수는 백분율 큰 글자 + 분수. 직전 점수(`state.json:cross_cut.doctor.last_score`)가 있으면 `▲ +Np` 한 줄, 해소 항목은 `✅ 해소:` 한 줄.
- audit 안내는 doctor 가 하지 않아요 — `audit` 전담. 본문 안 emoji 남발 X.

## 5. --strict 모드

placeholder 를 통과로 안 봐요. "엄격하게 진단해줘", "strict mode" 면 자동 적용. `spirit-lint.sh --strict` 도 같이.

## 절대 금지

- 결손에 ✗ 만 찍지 말고 **구체적 다음 명령** 제시
- "전부 OK!" 자가 칭찬 금지 · placeholder 를 통과로 위장 X
- 스크립트가 세는 것을 산문 bash 로 다시 세기 X — 결과가 갈리면 어느 쪽도 못 믿어요
- 자동 수정 X — [m]·[s]·[d]·[n]·[r]·[reach] 전부 사용자 답 뒤에

## state.json 갱신

```bash
bash .ax/scripts/bash/update-state.sh                     # canonical (layers · cross_cut · sensors_mode · hud 캐시)
jq '.last_skill = "doctor" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
