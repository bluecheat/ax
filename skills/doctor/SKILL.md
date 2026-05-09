---
name: doctor
description: "goax 설치 상태 진단 — '/doctor', 'goax doctor', 'goax 진단', '하네스 점검', 'goax 상태' 트리거. 4계층 + cross-cut + sensors 결손을 검사하고 다음 단계를 친절히 안내."
---

# goax doctor — 4계층 결손 진단

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거
- `/doctor`, `goax doctor`, "goax 진단", "하네스 점검", "goax 상태"
- `--strict` 옵션도 인식 (placeholder를 통과로 안 보고 fail 처리)

## 1. PROJECT_ROOT 감지

`.ax/`가 있는 가장 가까운 디렉토리:

1. 자기 + 조상 디렉토리에서 `.ax/` 찾기
2. 자식 디렉토리(2~4단 깊이)에서 `.ax/` 찾기
3. 못 찾으면 → `먼저 'goax 도입해줘'라고 말해주세요` 안내

다른 디렉토리에서 발동되면 알려요:
```
⚠ 현재 디렉토리에 .ax/가 없어요.
 /Users/x/projects/your-app 의 goax 설치를 진단해요.
 정확히 거기서 실행하려면: cd /Users/x/projects/your-app
```

## 2. 빠른 사전 통계 (bash) — 큰 프로젝트 대비

수십 모듈·수백 spec이 있을 때 LLM이 모두 읽기 전 bash로 통계:

```bash
ROOT=$(pwd) # 또는 감지한 PROJECT_ROOT

# 전체 자산 한눈에
echo "Spirit rules: $(ls $ROOT/.ax/spirit/rules/*.md 2>/dev/null | wc -l) 카테고리"
echo "ADR:    $(ls $ROOT/.ax/docs/adr/*.md 2>/dev/null | grep -v 0000-template | wc -l) 건"
echo "Spec:   $(ls -d $ROOT/.ax/docs/spec/[0-9][0-9][0-9]-* 2>/dev/null | wc -l) 건"
echo "Mistakes:  $(ls $ROOT/.ax/mistakes/*.md 2>/dev/null | grep -v README | wc -l) 건"
echo "Module CLAUDE: $(find $ROOT -maxdepth 4 -name CLAUDE.md -not -path "*/.*" -not -path $ROOT/CLAUDE.md 2>/dev/null | wc -l) 건"

# Layer 1 시그널 라벨 카운트
echo "CLAUDE.md 시그널:"
echo " 🔴 CRITICAL $(grep -c '🔴' $ROOT/CLAUDE.md 2>/dev/null)"
echo " 🟡 MANDATORY $(grep -c '🟡' $ROOT/CLAUDE.md 2>/dev/null)"
echo " 🔵 CONVENTION $(grep -c '🔵' $ROOT/CLAUDE.md 2>/dev/null)"

# placeholder 잔재 검색
grep -lE "<여기에 본문|<자기 팀|TODO\(goax\)" \
 $ROOT/.ax/spirit/*.md $ROOT/.ax/spirit/rules/*.md 2>/dev/null

# domain_risk 키 개수
grep -cE "^[[:space:]]+[a-z-]+:" $ROOT/.ax/config.yml 2>/dev/null

# 미승격 mistakes (audit 후보 — 카테고리당 카운트)
grep -h "^category:" $ROOT/.ax/mistakes/*.md 2>/dev/null \
 | awk '{print $2}' | sort | uniq -c | sort -rn
```

이 통계가 곧 진단 결과에 들어가요.

## 3. 4계층 + Cross-cut + Sensors 검사

각 항목 ✓/·/✗ 표시 + 빈 placeholder 검출.

| Layer | 검사 |
|---|---|
| **Layer 1** | `CLAUDE.md` 존재 + 시그널(🔴/🟡/🔵) 라벨 있는지 + 4계층 인덱스 표 |
| **Layer 0 / 설정** | `.ax/config.yml` (domain_risk 5+ 권장) + `.ax/version` |
| **Cross-cut Spirit** | `values.md`/`tone.md` (placeholder 검사), `rules/<카테고리>.md` 1개+ |
| **Cross-cut Mistake Loop** | `.ax/mistakes/` 디렉토리 존재 |
| **Layer 3 / Spec·ADR** | `.ax/docs/adr/`, ADR 1개+ (0000-template 외), `.ax/_templates/spec/` (`.origin` drift 비교 — 아래 §3.5) |
| **Layer 2 / Module Rules** | (선택) 모듈별 `<module>/CLAUDE.md` 카운트 |
| **Sensors / Hooks** | `.ax/hooks/{pre-bash,pre-edit,post-edit,pre-commit}/` + `.claude/settings.json` + **template hook 전체가 settings.json 에 등록됐는지 (§3.7-(3), SSOT 기반)** |
| **Rule Enforcement** | `enforced_by` schema invariant 검증 — `check-rule-enforcement.sh --json` 위임 (§3.9) |

### 3.5 _templates drift 체크 (script-backed)

스크립트 위임 — 결정론은 `check-templates-drift.sh`에. plugin 컨텍스트에서 실행되면 `${CLAUDE_SKILL_DIR}`(Claude Code 공식 변수)로 plugin root를 도출(`${CLAUDE_SKILL_DIR}/../..`). 사용자가 직접 bash로 호출했다면 비어있을 수 있어요(그때는 plugin_updated 검사가 skip 되고 user_modified만 보고).

> ⚠ **drift 감지 범위 제한**: `check-templates-drift.sh` 는 `.ax/_templates/spec/` 의 SHA snapshot 비교 한정. `_templates/{adr,module,spirit,mistakes}/` 와 `.ax/{hooks,scripts,modules,docs}/` 등 나머지 MANIFEST 출고분은 §3.5.1 의 `check-manifest-install.sh` 가 파일 단위로 커버해요 (missing + drift). `.ax/spirit/rules/` 는 plugin 출고 X 라 검증 대상 자체가 아니에요 — 그래서 onboarding 절대 금지 항목에 plugin shipped spirit/rules 직접 append 금지가 박혀있음. 프로젝트별 룰은 별도 파일(`<project>-<category>.md`) + @import 권장.

```bash
# plugin root 도출 — ${CLAUDE_SKILL_DIR} 우선, ${CLAUDE_PLUGIN_ROOT}는 호환용 fallback
if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
    PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    PLUGIN_ROOT=""
fi

if [ -n "$PLUGIN_ROOT" ]; then
 RESULT=$(bash .ax/scripts/bash/check-templates-drift.sh --json --plugin-dir "$PLUGIN_ROOT")
else
 RESULT=$(bash .ax/scripts/bash/check-templates-drift.sh --json)
fi
USER_MOD=$(echo "$RESULT" | jq -r '.result.user_modified')
PLUGIN_UPD=$(echo "$RESULT" | jq -r '.result.plugin_updated')
DRIFT_FILES=$(echo "$RESULT" | jq -r '.result.drift_files | join(", ")')
```

상태별 보고:
- `user_modified=false, plugin_updated=false` → `✓ _templates 출고본과 동일`
- `user_modified=true, plugin_updated=false` → `· _templates: 사용자 수정 감지 (정상 — 이게 SSOT). 변경: $DRIFT_FILES`
- `user_modified=*, plugin_updated=true` → `⚠ plugin _templates 갱신됨` + 옵션 제시:
 - [a] ✓ 사용자 수정 유지 (권장 — 도메인 적응 결과)
 - [b] plugin 출고본을 `.ax/_templates/spec.suggested/`로 떨어트려 사용자가 머지
 - [c] ⚠ 사용자 수정 백업(`.ax/_templates/spec.bak/`) 후 plugin으로 덮어쓰기

### 3.5.1 plugin shipped 자산 검증 — `check-manifest-install.sh` 위임

`_templates/spec/` SHA snapshot 비교 (§3.5) 와 별개로, MANIFEST 가 약속한 출고 디렉토리 (`.ax/{spirit,hooks,modules,docs,_templates,scripts}/`) 가 사용자 프로젝트에 **빠짐없이** 들어와 있는지 + 변경됐는지 파일 단위로 검증. install 미완(plugin 갱신 후 재install 안 함) 같은 케이스가 silently 누적되는 걸 차단. 결정론은 `check-manifest-install.sh` 가 SSOT — doctor 는 호출 + 보고만.

`spirit/rules/` 는 plugin 출고 X (사용자 큐레이션) — `.ax/_templates/spirit/` 의 opt-in 샘플만 검증 대상.

```bash
# PLUGIN_ROOT 는 §3.5 에서 이미 도출됨 — 없으면 스크립트가 status:skipped 로 응답
RESULT=$(bash "$ROOT/.ax/scripts/bash/check-manifest-install.sh" --json \
    ${PLUGIN_ROOT:+--plugin-dir "$PLUGIN_ROOT"} 2>/dev/null)
MI_STATUS=$(echo "$RESULT" | jq -r '.status')
MI_FILES=$(echo "$RESULT" | jq -r '.result.files_checked // 0')
MI_MISSING_N=$(echo "$RESULT" | jq -r '.result.missing // [] | length')
MI_DRIFT_N=$(echo "$RESULT" | jq -r '.result.drift // [] | length')
```

보고:
- `status=ok` (`MI_MISSING_N=0` && `MI_DRIFT_N=0`) → 출력 생략 (조용)
- `status=skipped` (PLUGIN_ROOT 미도출) → "plugin shipped 검증 skip — plugin 컨텍스트에서 doctor 실행 권장" 한 줄만
- `status=warning` 이면 별도 섹션:

```
 ─ plugin shipped 자산 검증 ─────────────────────────────
 ⚠ MANIFEST 누락 MI_MISSING_N개 — install 미완 또는 plugin 갱신 후 재install 안 함:
   <missing[] 한 줄씩 (5개 cap, 더 있으면 "... and N more")>
 ⚠ MANIFEST 변경 MI_DRIFT_N개 — install 재실행 시 silent 회귀 위험:
   <drift[] 동상>
```

`다음 단계` 옵션:

```
 [u] ✓ plugin shipped 자산 처리                         [추천 — missing/drift 있을 때]
   missing → installer 재실행 (`goax 도입` 또는 `/install` skill)
              기존 자산은 보존 + 누락분만 backfill (cp -R 이 idempotent)
   drift   → LLM 이 사용자 수정 의도 인터뷰:
              - "이 변경은 의도된 customization 인가요?" → [u-keep]
              - "복원하고 싶으신가요?" → [u-restore]
   [u-keep]    backup ($ROOT/.ax/<rel>.user) + plugin 갱신 시 회귀 위험 명시 안내
                + wrapper 패턴 권장 (custom 스크립트는 별도 파일로, plugin 출고는 그대로)
   [u-restore] $ROOT/<rel>.bak.<TS> 백업 후 plugin 출고로 복원 (cp from PLUGIN_TPL/<rel>)
```

**원칙**: 자동 수정 X — 사용자 customization 일 수 있어 항상 명시 의도 확인. plugin shipped 파일은 SSOT 가 plugin repo 라 사용자 수정은 본질적으로 fragile. 진짜 customization 은 wrapper 또는 별도 파일이 옳은 패턴.

**원칙**: 사용자 수정은 *절대* 자동 덮어쓰기 X. 머지 결정은 사용자.

### 3.5.5 Mistake audit 주기 점검

`config.yml`의 `audit_cadence_days` 와 `state.json`의 `cross_cut.mistakes.last_audit` 비교 → 임박/초과 시 안내.

```bash
CADENCE=$(grep -E '^[[:space:]]+audit_cadence_days:' "$ROOT/.ax/config.yml" 2>/dev/null \
    | awk '{print $2}' || echo 7)
LAST=$(jq -r '.cross_cut.mistakes.last_audit // "never"' "$ROOT/.ax/state.json" 2>/dev/null)
DUE=$(jq -r '.cross_cut.mistakes.due_in_days // 0' "$ROOT/.ax/state.json" 2>/dev/null)
COUNT=$(ls "$ROOT/.ax/mistakes/"*.md 2>/dev/null | grep -v README | wc -l | tr -d ' ')
```

보고:
- `last_audit=never` + `count > 0` → "audit 한 번도 안 돈 상태, 누적 N건 — `goax audit` 권장"
- `due <= 0` → "audit 주기 도래/초과 (N일 경과)"
- `due > 0` → "audit 다음 주기까지 N일"

`다음 단계`에 추가:

```
 [a] ✓ goax audit — N건 mistake 회고          [추천 — 주기 도래]
  명령 "goax audit"
  이유 audit_cadence_days=7 도래, mistakes N건 누적 — 카테고리 패턴 보일 수 있음
```

자동화 옵션은 안내에 한 줄: "주 1회 자동 audit 원하면 Claude Routine 등록 — `goax audit` 명령 + weekly cron".

### 3.6 마이그레이션 잔재 점검

이전 install 이 신규 항목을 갖추지 못했거나, 정책 변경으로 폐기된 자산이 남았을 때 안내.
모두 수동 — 자동 수정 X (사용자 동의 후 별도 명령 또는 doctor 옵션 [a]/[b]/...).

```bash
# (1) .gitignore 누락 엔트리
NEED_GITIGNORE=()
for line in ".ax/state.json" ".ax/current-task.json" ".ax/*.suggested" ".ax/.onboarding-pending"; do
    if [ -f .gitignore ]; then
        grep -qxF "$line" .gitignore || NEED_GITIGNORE+=("$line")
    else
        NEED_GITIGNORE+=("$line")
    fi
done

# (2) spirit/rules/output-style.md 잔재 — plugin 출고에서 제거됨 (plugin meta 였음)
HAS_STALE_OUTPUT_STYLE=false
[ -f .ax/spirit/rules/output-style.md ] && HAS_STALE_OUTPUT_STYLE=true

# (3) 처리 안 한 .suggested 잔재
SUGGESTED=$(find .ax -maxdepth 2 -name "*.suggested" 2>/dev/null)

# (4) spec slim 잔재 — README.md 또는 빈 checklists/contracts dir
# init-spec-dir 의 slim 정책: README.md 폐기, checklists/contracts 는 lazy 생성.
# 그 정책 도입 전 만들어진 spec 디렉토리는 정리 후보.
SPEC_README_STALE=()
SPEC_EMPTY_DIRS=()
for d in $(find .ax/docs/spec -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do
    [ -f "$d/README.md" ] && SPEC_README_STALE+=("$d/README.md")
    for sub in checklists contracts; do
        if [ -d "$d/$sub" ] && [ -z "$(ls -A "$d/$sub" 2>/dev/null)" ]; then
            SPEC_EMPTY_DIRS+=("$d/$sub/")
        fi
    done
done
```

보고 형식:
- 누락/잔재 0건 → 출력 생략 (조용)
- 누락 있으면 결과 §3 끝에 "마이그레이션 잔재" 섹션 추가:

```
 ─ 마이그레이션 잔재 ────────────────────────────────────
 · .gitignore 누락 엔트리 — N줄 (예: .ax/state.json, .ax/current-task.json, ...)
 · .ax/spirit/rules/output-style.md — plugin meta 로 분류되어 출고에서 제거됨
 · .ax/mistakes/README.md.suggested 미처리 — 머지 후 rm 권장
 · spec README.md 잔재 N건 — slim 정책으로 폐기 (rm 권장):
   <SPEC_README_STALE 한 줄씩>
 · spec 빈 dir K건 — lazy 생성 정책 (rmdir 권장):
   <SPEC_EMPTY_DIRS 한 줄씩>
```

`다음 단계`에 옵션 추가:

```
 [m] ✓ 마이그레이션 잔재 처리                         [추천]
  명령 .gitignore 보강 + output-style.md 제거 + .suggested 정리 +
       spec README.md / 빈 checklists·contracts dir 정리 (slim 정책 부합)
  이유 잔재 정리 (PR 노이즈 방지 + slim spec 일관)
```

**원칙**: 자동 수정 X — 사용자가 [m] 선택해야 실행. output-style.md / spec README.md 제거는 git commit 영향 → 사용자 컨텍스트에서만.

### 3.7 spirit lint + path-scoped hook 등록 점검

`spirit/SKILL.md:28-31`이 mandate하는 `^## SP-CAT-NNN: text` 형식 검증 + path-scoped 룰의 hook (`spirit-rules-inject.sh`) 이 settings.json에 등록됐는지 확인.

```bash
# (1) spirit/rules/*.md + modules/*/rules.md 헤더 형식 검증 — 비표준 헤더 검출
SPIRIT_BAD=()
for f in "$ROOT/.ax/spirit/rules/"*.md "$ROOT/.ax/modules/"*/rules.md; do
    [ -f "$f" ] || continue
    bad=$(grep -nE '^## ' "$f" | grep -vE '^[0-9]+:## SP-[A-Z]+-[0-9]{3}: ')
    [ -n "$bad" ] && SPIRIT_BAD+=("$f")
done

# (2) SP-* 토큰 중복 검출 — spirit + modules 통합 (같은 prefix-NNN이 어디든 여러 번 나오면 충돌)
DUPES=$(grep -hE '^## SP-[A-Z]+-[0-9]{3}:' \
        "$ROOT/.ax/spirit/rules/"*.md \
        "$ROOT/.ax/modules/"*/rules.md \
        2>/dev/null \
    | sed -E 's/^## (SP-[A-Z]+-[0-9]{3}):.*/\1/' \
    | sort | uniq -d)

# (3) hook 등록 검증 — template SSOT 기반 7개 hook 전체 일괄 점검
# templates/default/.claude/settings.json.template 에서 .ax/hooks/*.sh 경로를 추출 →
# 사용자 .claude/settings.json 에 basename grep 으로 등록 여부 판정.
# template에 hook 추가/삭제되면 doctor가 자동으로 따라감 (hardcode 아님).
# PLUGIN_ROOT는 §3.5에서 이미 도출됨 (없으면 SSOT 검증 skip — 결과는 path-scoped 1개만).
TPL_SETTINGS="${PLUGIN_ROOT:-}/templates/default/.claude/settings.json.template"
SETTINGS="$ROOT/.claude/settings.json"

EXPECTED_HOOKS=()
REGISTERED_HOOKS=()
MISSING_HOOKS=()
MISSING_HOOK_FILES=()  # template에 선언됐는데 .ax/hooks/ 안 자체가 없는 경우 (install 미완)

if [ -f "$TPL_SETTINGS" ]; then
    while IFS= read -r hook_path; do
        [ -z "$hook_path" ] && continue
        EXPECTED_HOOKS+=("$hook_path")
        hook_basename=$(basename "$hook_path")
        if [ ! -f "$ROOT/$hook_path" ]; then
            MISSING_HOOK_FILES+=("$hook_path")
            MISSING_HOOKS+=("$hook_path")
        elif [ -f "$SETTINGS" ] && grep -q "$hook_basename" "$SETTINGS" 2>/dev/null; then
            REGISTERED_HOOKS+=("$hook_path")
        else
            MISSING_HOOKS+=("$hook_path")
        fi
    done < <(grep -oE '\.ax/hooks/[^"]+\.sh' "$TPL_SETTINGS" | sort -u)
fi

TOTAL_HOOKS=${#EXPECTED_HOOKS[@]}
REG_HOOKS=${#REGISTERED_HOOKS[@]}
MISS_HOOKS=${#MISSING_HOOKS[@]}

# 호환 — 기존 path-scoped 단독 검증 변수 (paths 선언 룰 + spirit-rules-inject 미등록 한정 메시지)
HAS_PATHS=$(grep -lE '^paths:[[:space:]]*$' "$ROOT/.ax/spirit/rules/"*.md 2>/dev/null | head -1)
HOOK_REGISTERED=$(grep -c 'spirit-rules-inject\.sh' "$SETTINGS" 2>/dev/null || echo 0)
HOOK_FILE="$ROOT/.ax/hooks/pre-edit/spirit-rules-inject.sh"
```

보고:
- (1)/(2) 결과(비표준 헤더 / 중복 토큰) 어느 하나라도 있으면 §3 출력에 "Spirit lint" 섹션 추가
- (3) 결과는 별도 "Sensors — settings.json hook 등록" 섹션으로 분리. `MISS_HOOKS > 0` 일 때만 출력 (전부 등록이면 §3 본 표 row의 ✓ 만으로 충분).
  - `MISSING_HOOK_FILES` 가 비어있지 않으면 install 미완으로 별도 표기 — 등록 옵션 [s]만으로는 못 고침.

```
 ─ Spirit lint ──────────────────────────────────────────
 · spirit/rules/<project>-<category>.md — 비표준 헤더 3개 (SP-CAT-NNN 형식 위배)
 · 중복 SP-DOM-008 — <project>-domain.md 2회 등장

 ─ Sensors — settings.json hook 등록 ────────────────────
 ⚠ template hook REG_HOOKS/TOTAL_HOOKS 등록 — MISS_HOOKS 개 미등록:
   <MISSING_HOOKS 배열을 한 줄씩 echo — 아래는 형태 예시일 뿐, hook 이름·개수는 template SSOT 따라감>
   - .ax/hooks/<sub>/<file>.sh
   - .ax/hooks/<sub>/<file>.sh
   ...
 · path-scoped loading 담당 hook 이 미등록 — paths 선언 룰 N개 있는데 동작 안 함
   (HAS_PATHS && HOOK_REGISTERED == 0 일 때만 출력. 어떤 hook 이 그 역할인지는 template 이 정함)
 · install 미완 — .ax/hooks/ 안에 없는 항목 K개:  ← MISSING_HOOK_FILES 비었을 땐 출력 생략
   <MISSING_HOOK_FILES 배열을 한 줄씩 echo — installer 재실행으로만 복원 가능>
```

> **TOTAL_HOOKS 가 0인 경우**: `PLUGIN_ROOT` 미도출 또는 template 부재 — 이때는 "Sensors — settings.json hook 등록" 섹션을 통째로 skip 하고 path-scoped 단독 검증(HAS_PATHS + HOOK_REGISTERED) 결과만 §3 본 표에서 처리. doctor가 plugin 컨텍스트에서 발동되면 거의 항상 도출돼요.

`다음 단계`에 추가:

```
 [n] ✓ spirit lint 정리                 [추천]
  명령 비표준 헤더 수정 + 중복 토큰 해소 (사용자)
  이유 spirit/SKILL.md:28-31 lint 통과

 [s] ✓ template hook 등록 (미등록 MISS_HOOKS 개)         [추천 — MISS_HOOKS > 0 일 때]
  1순위 bash .ax/scripts/bash/register-hooks.sh
        → template SSOT 기반 누락분 일괄 additive merge (idempotent, 백업 자동)
        → 사용자 추가 hook 보존, --prune 명시 안 하면 어떤 entry 도 삭제 안 함
        → 자세한 계약: docs/spec/hook-registration.md
  fallback (스크립트 부재 시) bash .ax/scripts/bash/register-spirit-hook.sh
        → path-scoped loading 담당 hook 1개만 등록 (역할 hook 한정 — 나머지는 미등록 채로 남음)
        → 나머지 hook 은 (i) `.ax/settings.json.suggested` 머지 또는 (ii) LLM 이 template 을
          읽어 jq 로 직접 append (백업 후, 사용자 키 보존). 이 경로는 docs/spec/hook-registration.md
          가 mandate 하는 "register-hooks.sh 통합" 이행 전 임시 — 도입되면 사라짐.
  install 미완 (MISSING_HOOK_FILES 비지 않음) 항목은 [s]로 못 고침 →
        installer 재실행 권장: `goax 도입` skill 호출 (기존 자산 보존).
  결과 template 이 선언한 EventName · matcher · hook 전체 활성
  이유 hook 셋 자체는 template 이 결정 — 어떤 조합이든 doctor / register-hooks 는
        이름 hardcode 없이 자동 따라감 (Anti-pattern 회피, hook-registration.md I1)
```

[s]는 사용자 동의 후 실행 — 직접 수정이지만 idempotent + 백업이라 안전. 헤더 수정/중복 해소(`[n]`)는 의미상 LLM이 사용자와 함께.

### 3.8 CLAUDE.md ↔ 실제 메커니즘 일치 검증

CLAUDE.md가 path-scoped 메커니즘을 어떻게 *설명하는지* 와 실제 설치 상태가 일치하는지 검증. 다른 Claude 세션이 stale 컨텍스트로 작업하거나 design generation 마이그레이션을 누락했을 때 문서·실제 drift가 silent하게 누적되는 걸 차단.

```bash
CLAUDE_MD="$ROOT/CLAUDE.md"
SETTINGS="$ROOT/.claude/settings.json"

# CLAUDE.md가 명시하는 메커니즘
DESC_HOOK=0
DESC_SHIM=0
grep -q 'spirit-rules-inject\.sh' "$CLAUDE_MD" 2>/dev/null && DESC_HOOK=1
grep -q 'generate-rule-shims\.sh\|\.claude/rules/.*shim' "$CLAUDE_MD" 2>/dev/null && DESC_SHIM=1

# 실제 설치 상태
INST_HOOK=0
INST_SHIM=0
[ -f "$ROOT/.ax/hooks/pre-edit/spirit-rules-inject.sh" ] \
    && grep -q 'spirit-rules-inject\.sh' "$SETTINGS" 2>/dev/null \
    && INST_HOOK=1
[ -f "$ROOT/.ax/scripts/bash/generate-rule-shims.sh" ] && INST_SHIM=1

# 4가지 mismatch
MISMATCHES=()
[ "$DESC_HOOK" -eq 1 ] && [ "$INST_HOOK" -eq 0 ] \
    && MISMATCHES+=("CLAUDE.md는 hook 메커니즘 명시 — 실제 미설치/미등록")
[ "$DESC_SHIM" -eq 1 ] && [ "$INST_SHIM" -eq 0 ] \
    && MISMATCHES+=("CLAUDE.md는 shim 메커니즘 명시 — 0.1.8에서 폐기됨 (generate-rule-shims.sh 없음)")
[ "$DESC_HOOK" -eq 1 ] && [ "$DESC_SHIM" -eq 1 ] \
    && MISMATCHES+=("CLAUDE.md가 두 메커니즘 동시 명시 — 모순")
[ "$INST_HOOK" -eq 1 ] && [ "$DESC_HOOK" -eq 0 ] && [ "$DESC_SHIM" -eq 0 ] \
    && MISMATCHES+=("hook 활성됐지만 CLAUDE.md path-scoped 설명 누락")
```

보고:
- mismatch 없으면 출력 생략 (조용)
- 있으면 §3 끝에 "문서 ↔ 실제 일치" 섹션 추가:

```
 ─ 문서 ↔ 실제 일치 ─────────────────────────────────────
 ⚠ CLAUDE.md는 shim 메커니즘 명시 — 0.1.8에서 폐기됨 (generate-rule-shims.sh 없음)
 ⚠ CLAUDE.md가 두 메커니즘 동시 명시 — 모순
```

`다음 단계`에 추가:

```
 [d] ✓ CLAUDE.md path-scoped 설명 갱신                 [추천]
  명령 path-scoped 섹션을 현재 활성 메커니즘으로 갱신
        (Design B → "PreToolUse hook이 자동 안내, .ax/hooks/pre-edit/spirit-rules-inject.sh")
  이유 다른 세션이 stale 메커니즘 언어로 답변하는 위험 차단
```

자동 적용 X — 사용자 + LLM이 함께 path-scoped 섹션 본문을 작성. 이 검증 자체는 grep만 — 결정론.

**왜 이 검증이 필요한가**: 세션마다 CLAUDE.md 컨텍스트가 다를 수 있어, 한 세션이 0.1.7 시점 design generation으로 작업하면 CLAUDE.md를 Design A 언어로 되돌리거나 두 메커니즘을 섞을 수 있음. 실제 hook은 Design B로 동작하지만 문서는 다른 메커니즘을 가리키면 신뢰 침식. 이 §3.8이 마지막 방어선.

### 3.9 Rule Enforcement invariant — `check-rule-enforcement.sh` 위임 (NEW)

`enforced_by` / `enforced_kind` schema 검증 로직 자체는 결정론 — `.ax/scripts/bash/check-rule-enforcement.sh` 가 SSOT. doctor 는 호출 + JSON 파싱 + 보고만.

```bash
RESULT=$(bash "$ROOT/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null)
RE_STATUS=$(echo "$RESULT" | jq -r '.status')
RE_RULE_COUNT=$(echo "$RESULT" | jq -r '.result.rule_count // 0')
RE_I1=$(echo "$RESULT" | jq -r '.result.i1_violations | length')
RE_I2=$(echo "$RESULT" | jq -r '.result.i2_violations | length')
RE_I3IM=$(echo "$RESULT" | jq -r '.result.i3_imminent | length')
RE_I3OD=$(echo "$RESULT" | jq -r '.result.i3_overdue | length')
RE_I5F=$(echo "$RESULT" | jq -r '.result.i5_file_missing | length')
RE_I5R=$(echo "$RESULT" | jq -r '.result.i5_not_registered | length')
```

검증 invariants (스크립트가 mandate, doctor 는 보고만):
- **I1**: 🔴 CRITICAL 의 `enforced_by` 는 `hook:*` / `external:*` 만 (TODO/human/script 금지)
- **I2**: `TODO:*` 는 deadline 필수 (`YYYY-MM-DD` 또는 `+Nd/+Nw`)
- **I3**: deadline 임박(≤7일) / 초과 보고
- **I5**: `enforced_by: hook:<path>` 면 (a) 파일 존재 (b) `.claude/settings.json` 등록

자세한 schema·invariant 본문: `.ax/docs/reference/rule-enforcement.md` (사용자 프로젝트에 깔림).

보고 — 위반 0 이면 §3 본 표의 ✓ 만, 1+ 이면 별도 섹션:

```
 ─ Rule Enforcement ─────────────────────────────────────
 ❌ I1 위반 — CRITICAL 인데 자동 차단 메커니즘 없음 (거짓 약속) RE_I1건:
   <i1_violations 배열을 한 줄씩 echo: "rule_id (enforced_by, enforced_kind)">
 ❌ I2 위반 — TODO 인데 deadline 없음 RE_I2건:
   <i2_violations 동상>
 ⚠ I3 임박 (≤7일) RE_I3IM건 / 초과 RE_I3OD건:
   <i3_imminent + i3_overdue, deadline + days_left/days_overdue 포함>
 ⚠ I5 위반 — hook 파일 부재 RE_I5F건 / 미등록 RE_I5R건:
   <i5_file_missing + i5_not_registered>
```

`다음 단계` 옵션 (위반 종류별, 무거운 것부터):

```
 [r] ✓ 라벨 강등 — CRITICAL → MANDATORY (I1 위반 RE_I1건)         [최우선 추천]
   명령  CLAUDE.md 의 🔴 → 🟡 일괄 변환 + enforced_by 형식 정리 (사용자 confirm 후 LLM 적용)
   이유  CRITICAL 라벨이 거짓 약속 — 라벨과 실제가 일치해야 다른 세션 오인 차단
   대안  [w] hook 작성 후 🔴 유지 — 이쪽이 정직하지만 시간 듦

 [w] ✓ hook 작성 — enforced_by 가 가리키는 hook 파일 신규 작성   [장기 — 룰 진짜 enforce]
   명령  .ax/hooks/<sub>/<basename>.sh 직접 작성 (룰 의미 의존, template 없음)
        + 작성 후 register-hooks.sh 또는 register-spirit-hook.sh 로 settings.json 등록
   이유  CRITICAL 유지하면서 약속을 진짜로 지킴

 [d] ✓ deadline 갱신 — 임박/초과 TODO 에 새 absolute date 부여     [강등 거부 시]
   명령  enforced_by: TODO:<new-date> 갱신 (사용자 입력)
   이유  ADR 검토 시점 연기. 단 단순 연기 반복은 anti-pattern (3회 이상 → 강등 권장)

 [g] ✓ deadline 입력 — I2 위반 (deadline 없음) 에 absolute date 부여
   명령  enforced_by: TODO → TODO:<YYYY-MM-DD>
   이유  invariant I2 통과 + doctor 가 추적 가능 상태로
```

**원칙**: 자동 수정 X — 모든 옵션은 사용자 confirm 후 LLM 이 CLAUDE.md / spirit/rules 갱신. 강등은 특히 사용자 의도 변경이라 명시 동의 필수.

**왜 이 검증이 필요한가**: onboarding 이 deferred ("나중에 hook 작성") 옵션을 받아도 추적 메커니즘이 없으면 deadline 이 흘러도 아무도 모름. 🔴 라벨이 enforce 보장 없이 박혀있으면 다른 세션이 "이 룰은 자동 차단됨" 으로 오인 → 진짜 위반이 살아있어도 안전한 줄. 이 §3.9 가 영구 추적 안전망.

## 3. 출력

```
🩺 goax doctor — /path/to/your-project
    goax 0.3.0 · preset=default · installed 2026-05-02

 ─ Layer 1 — Constitution ───────────────────────────────
 ✓ CLAUDE.md (62줄, 시그널 라벨 있음, 4계층 인덱스 ✓)

 ─ Layer 0 — Triage / 설정 ───────────────────────────────
 ✓ config.yml (domain_risk 30 keys, default L1)
 ✓ version (goax &lt;version&gt;)

 ─ Cross-cut — Spirit ───────────────────────────────────
 ✓ spirit/values.md (사용자 정의됨)
 · spirit/tone.md → placeholder 그대로
 ✓ spirit/rules/ (사용자 큐레이션 N 카테고리; opt-in 샘플은 .ax/_templates/spirit/)

 ─ Cross-cut — Mistake Loop ─────────────────────────────
 ✓ mistakes/ (3건 누적, 다음 audit: 2026-05-09)

 ─ Layer 3 — Spec / ADR ─────────────────────────────────
 ✓ docs/adr/ (1건: 0001-goax-adoption.md)
 ✓ docs/_templates/spec/
 · docs/spec/NNN-*/ — 작성된 spec 0건 (첫 spec 권장)

 ─ Layer 2 — Module Rules ───────────────────────────────
 ✓ <module>/CLAUDE.md (5/13 모듈 — L2/L3 도메인만, 선택적)

 ─ Sensors — Hooks ──────────────────────────────────────
 ✓ pre-bash, pre-edit, post-edit, pre-commit hooks (디렉토리)
 ✓ .claude/settings.json
 ✓ template hook 등록: REG_HOOKS/TOTAL_HOOKS  (또는 ⚠ — 미등록 리스트는 §3.7 "Sensors — settings.json hook 등록" 섹션)

 ─ 점수 ──────────────────────────────────────────────────
 9/11 (90%)

 ─ 다음 단계 ──────────────────────────────────────────────

 [a] ✓ tone.md 우리 팀 말투로 수정    [추천]
  파일 .ax/spirit/tone.md
  이유 placeholder 그대로 — 모든 sub-agent가 default 톤 사용 중
  방법 ~해요 체 + 우리 팀 안티패턴 추가

 [b] 첫 spec 작성         [권장]
  명령 "새 spec 만들어줘 — <slug>"
  이유 Layer 3은 template만 — 실제 spec이 있어야 game이 시작됨

 [c] audit 실행 — mistakes 3건 회고
  명령 "goax audit"
  이유 3건 누적, 카테고리별 패턴 보일 수 있음

 ▸ 답해주세요 [a] / [b] / [c] / 또는 그냥 보고만
```

**규칙**
- 빈 placeholder는 `·` (warning), 누락은 `✗` (fail)
- 다음 단계 옵션은 결손이 큰 항목부터 우선순위 부여
- `[권장]`/`[추천]` 표시는 점수 기여도 + 안전성 기준
- 문제 없으면 "다음 단계" 섹션에 [a] "spec 1개 작성"·[b] "audit"처럼 발전적 옵션

## 4. --strict 모드

placeholder는 통과로 안 봄. 모든 항목이 사용자 정의 상태여야 score 만점.
사용자가 "엄격하게 진단해줘", "strict mode" 같은 표현 쓰면 자동 적용.

## 절대 금지

- 결손이 있으면 그냥 ✗만 찍지 말고 **구체적 다음 명령**을 제시
- "전부 OK!" 같은 자가 칭찬 금지 (Spirit 1️⃣)
- placeholder를 통과로 위장 X

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- 모든 layers + cross_cut (canonical)

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
# canonical 갱신 (layer.active, cross_cut.active, sensors_mode, updated_at) — 결정론 스크립트
bash .ax/scripts/bash/update-state.sh

# 메타데이터 (last_skill, skill_calls)만 별도
jq '.last_skill = "doctor" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
