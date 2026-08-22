---
name: doctor
description: "goax 설치 상태 진단 — 'goax doctor', 'goax 진단', '하네스 점검', 'goax 상태' 트리거. 4계층 + cross-cut + sensors 결손을 검사하고 다음 단계를 친절히 안내."
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
echo "ADR:    $(ls $ROOT/.ax/docs/adr/*.md 2>/dev/null | wc -l) 건"
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

각 항목 ✅ / ⚠️ / ❌ 표시 + 빈 placeholder 검출. 매핑은 본 문서 끝 "규칙" 섹션 참조.

| Layer | 검사 |
|---|---|
| **Layer 1** | `CLAUDE.md` 존재 + 시그널(🔴/🟡/🔵) 라벨 있는지 + 4계층 인덱스 표 |
| **Layer 0 / 설정** | `.ax/config.yml` (domain_risk 5+ 권장) + `.ax/version` |
| **Cross-cut Spirit** | `values.md`/`tone.md` (placeholder 검사), `rules/<카테고리>.md` 1개+ |
| **Cross-cut Mistake Loop** | `.ax/mistakes/` 디렉토리 존재 |
| **Layer 3 / Spec·ADR** | `.ax/docs/adr/`, ADR 1개+, `.ax/_templates/spec/` (drift 비교는 "Plugin update 반영" 섹션 통합) |
| **Layer 2 / Module Rules** | (선택) 모듈별 `<module>/CLAUDE.md` 카운트 |
| **Sensors / Hooks** | `.ax/hooks/{pre-bash,pre-edit,post-edit,pre-commit}/` + `.claude/settings.json` + **template hook 전체가 settings.json 에 등록됐는지** (Spirit lint 섹션의 SSOT 기반 점검) |
| **Rule Enforcement** | `enforced_by` schema invariant 검증 — `check-rule-enforcement.sh --json` 위임 ("Rule Enforcement invariant" 섹션) |
| **Sensors — Liveness** | Sensors 장치 생사 검증 (grep 스캐폴드·git hook·차단 능력·세션 루트) — `check-sensor-liveness.sh --json` 위임 (3.10 섹션) |

### 3.5 Plugin update 반영 — version + 출고 자산 신선도 (script-backed)

핵심 질문: **"현재 설치 상태 == 최신 plugin 출고?"**

3 가지 신호를 한꺼번에 감지하고 **단일 y/n** 으로 처리. 모두 "plugin 갱신 후 `/up` 재호출 안 함" 단일 원인 — 4 가지 결정을 따로 묻는 건 인지 부담만 키우고 답은 거의 항상 "yes 동기화".

검사 신호:
1. **version drift** — `.ax/version` ↔ `state.json:goax_version` ↔ plugin `VERSION` 3-way 비교
2. **MANIFEST missing/drift** — `check-manifest-install.sh --json` (출고 디렉토리 파일 단위)
3. **_templates plugin 갱신** — `check-templates-drift.sh --json` 의 `plugin_updated=true` 만 (user_modified 단독은 정상 — 정보성으로만 표시)

> ⚠ **drift 감지 범위 제한**: `check-templates-drift.sh` 는 `.ax/_templates/spec/` SHA snapshot 비교 한정. 나머지 MANIFEST 출고분 (`hooks/`, `scripts/bash/*.sh`, `modules/`, `docs/`, `_templates/{adr,module,spirit,mistakes}/`) 은 `check-manifest-install.sh` 가 파일 단위로 커버 — `up` 재실행 시 `cp -R` 로 전부 덮어씀 (idempotent). `.ax/spirit/{values,tone,README}.md` 와 `.ax/spirit/rules/` 는 사용자 customize 영역이라 plugin 출고 자체가 conditional (`.suggested` 패턴) — 검증 대상 아님 (`.ax/_templates/spirit/` opt-in 샘플만 검증).

```bash
# plugin root 도출 — ${CLAUDE_SKILL_DIR} 우선, ${CLAUDE_PLUGIN_ROOT}는 호환용 fallback
if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
    PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    PLUGIN_ROOT=""
fi

# (1) 3-way version 비교
INSTALLED_V=$(cat "$ROOT/.ax/version" 2>/dev/null | tr -d '[:space:]')
STATE_V=$(jq -r '.goax_version // ""' "$ROOT/.ax/state.json" 2>/dev/null)
PLUGIN_V=""
[ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/VERSION" ] \
    && PLUGIN_V=$(cat "$PLUGIN_ROOT/VERSION" | tr -d '[:space:]')

VERSION_DRIFT=false
[ -n "$PLUGIN_V" ] && [ "$INSTALLED_V" != "$PLUGIN_V" ] && VERSION_DRIFT=true

# (2) _templates drift — plugin_updated 만 reinstall 신호 (user_modified 단독은 정상)
RESULT_T=$(bash "$ROOT/.ax/scripts/bash/check-templates-drift.sh" --json \
    ${PLUGIN_ROOT:+--plugin-dir "$PLUGIN_ROOT"} 2>/dev/null)
PLUGIN_UPD=$(echo "$RESULT_T" | jq -r '.result.plugin_updated // false')
USER_MOD=$(echo "$RESULT_T" | jq -r '.result.user_modified // false')
DRIFT_FILES=$(echo "$RESULT_T" | jq -r '.result.drift_files // [] | join(", ")')

# (3) MANIFEST missing/drift
RESULT_M=$(bash "$ROOT/.ax/scripts/bash/check-manifest-install.sh" --json \
    ${PLUGIN_ROOT:+--plugin-dir "$PLUGIN_ROOT"} 2>/dev/null)
MI_STATUS=$(echo "$RESULT_M" | jq -r '.status // "skipped"')
MI_MISSING_N=$(echo "$RESULT_M" | jq -r '.result.missing // [] | length')
MI_DRIFT_N=$(echo "$RESULT_M" | jq -r '.result.drift // [] | length')

# 종합 판정 — 하나라도 yes 면 reinstall 권장
NEEDS_REINSTALL=false
[ "$VERSION_DRIFT" = "true" ] && NEEDS_REINSTALL=true
[ "$PLUGIN_UPD" = "true" ] && NEEDS_REINSTALL=true
[ "$MI_MISSING_N" -gt 0 ] && NEEDS_REINSTALL=true
[ "$MI_DRIFT_N" -gt 0 ] && NEEDS_REINSTALL=true

# (4) changelog 발췌 — INSTALLED_V <  ver  <= PLUGIN_V 사이 release notes title 만 수집
#     사용자가 [y] 누르기 전에 "무엇이 바뀌는지" 한눈에 보이게
CHANGELOG_LINES=()
if [ "$VERSION_DRIFT" = "true" ] && [ -n "$PLUGIN_ROOT" ] && [ -d "$PLUGIN_ROOT/changelog" ]; then
    while IFS= read -r f; do
        ver=$(basename "$f" .md)
        # ver > INSTALLED_V (sort -V tail = max)
        max1=$(printf '%s\n%s\n' "$INSTALLED_V" "$ver" | sort -V | tail -1)
        [ "$max1" = "$ver" ] && [ "$ver" != "$INSTALLED_V" ] || continue
        # ver <= PLUGIN_V
        max2=$(printf '%s\n%s\n' "$ver" "$PLUGIN_V" | sort -V | tail -1)
        [ "$max2" = "$PLUGIN_V" ] || continue
        # 첫 줄 `# X.Y.Z — title` 추출 (`# ` 제거)
        title=$(head -1 "$f" | sed -E 's/^#[[:space:]]*//')
        CHANGELOG_LINES+=("- $title")
    done < <(ls "$PLUGIN_ROOT/changelog/"*.md 2>/dev/null | grep -vE '/README\.md$' | sort -V)
fi
```

#### 보고

- `NEEDS_REINSTALL=false && USER_MOD=false` → 출력 생략 (조용)
- `NEEDS_REINSTALL=false && USER_MOD=true` → 한 줄 정보성: `ℹ️  _templates 사용자 수정 감지 (정상 — 도메인 적응): $DRIFT_FILES`
- `MI_STATUS=skipped` (PLUGIN_ROOT 미도출) → 한 줄: `ℹ️  plugin shipped 검증 skip — plugin 컨텍스트에서 doctor 실행 권장`
- `NEEDS_REINSTALL=true` → 별도 섹션:

```
🔄  Plugin update 반영
   ⚠️  신규 버전 출고 미반영 — installed $INSTALLED_V → plugin $PLUGIN_V

   변경 내역 (changelog/<ver>.md 발췌):   (CHANGELOG_LINES 비어있지 않을 때만)
   <CHANGELOG_LINES 한 줄씩 — 8개 cap, 더 있으면 "... and N more">

   감지된 drift:
   - version: .ax/version=$INSTALLED_V ↔ state=$STATE_V ↔ plugin=$PLUGIN_V   (VERSION_DRIFT=true 일 때만)
   - MANIFEST 누락 $MI_MISSING_N개   (>0 일 때만; 5개 cap, 더 있으면 "... and N more")
     - <missing[] 한 줄씩>
   - MANIFEST drift $MI_DRIFT_N개   (>0 일 때만 — scripts/bash/*.sh 포함)
     - <drift[] 한 줄씩>
   - _templates 갱신: $DRIFT_FILES   (PLUGIN_UPD=true 일 때만)
```

#### 다음 단계 — 단일 y/n

```
 [u] ✅ 전체 업데이트 파일 덮어쓰기                       [추천]
   명령 "goax up" 또는 /up skill 호출
   동작 up 재실행 — MANIFEST 기반 `cp -R` 로 누락분 backfill +
        drift 파일 덮어쓰기 + `chmod +x` 재적용 + `.ax/version` 갱신 (idempotent)
   포함 자산:
        scripts/bash/*.sh  ·  hooks/*.sh  ·  _templates/  ·  modules/  ·  docs/
        (SSOT: templates/default/MANIFEST)
   보존 사용자 customize 자산 (`.ax/spirit/{values,tone,README}.md`,
        `.ax/config.yml`, `.ax/mistakes/README.md`, `CLAUDE.md`,
        `.claude/settings.json`) 은 `.suggested` 패턴으로 보존 — 덮어쓰기 X.
   주의 사용자 수정한 _templates / MANIFEST 출고분 (scripts/bash, hooks 등) 은
        덮어써짐. up 재실행 시 자체 backup 안 함 — 보존 원하면 먼저 git stash /
        git diff 로 사후 검토. 진짜 customization 은 wrapper 패턴
        (별도 파일 + @import) 권장.

 ▸ 답해주세요 [y/n]
```

`y` → up 재실행 (또는 `/up` skill)
`n` → 그대로 유지 (다음 doctor 에서 동일 안내)

**원칙**: 자동 적용 X — 사용자 [y] 응답 후 LLM 이 up 재실행. 옵션을 1 개로 좁힌 이유는 답이 거의 항상 "yes" 라서 — 사용자 수정 보호는 git 가 함, doctor 단계에서 분기로 다루지 않음.

### 3.6 마이그레이션 잔재 점검

이전 up 호출이 신규 항목을 갖추지 못했거나, 정책 변경으로 폐기된 자산이 남았을 때 안내.
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
- 누락 있으면 결과 본 표 끝에 "마이그레이션 잔재" 섹션 추가:

```
🧹  마이그레이션 잔재
   ⚠️ .gitignore 누락 엔트리 — N줄 (예: .ax/state.json, .ax/current-task.json, ...)
   ⚠️ .ax/spirit/rules/output-style.md — plugin meta 로 분류되어 출고에서 제거됨
   ⚠️ .ax/mistakes/README.md.suggested 미처리 — 머지 후 rm 권장
   ⚠️ spec README.md 잔재 N건 — slim 정책으로 폐기 (rm 권장):
      <SPEC_README_STALE 한 줄씩>
   ⚠️ spec 빈 dir K건 — lazy 생성 정책 (rmdir 권장):
      <SPEC_EMPTY_DIRS 한 줄씩>
```

`다음 단계`에 옵션 추가:

```
 [m] ✅ 마이그레이션 잔재 처리                         [추천]
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
# PLUGIN_ROOT는 "Plugin update 반영" 섹션에서 이미 도출됨 (없으면 SSOT 검증 skip — 결과는 path-scoped 1개만).
TPL_SETTINGS="${PLUGIN_ROOT:-}/templates/default/.claude/settings.json.template"
SETTINGS="$ROOT/.claude/settings.json"

EXPECTED_HOOKS=()
REGISTERED_HOOKS=()
MISSING_HOOKS=()
MISSING_HOOK_FILES=()  # template에 선언됐는데 .ax/hooks/ 안 자체가 없는 경우 (초기 설치 미완)

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
- (1)/(2) 결과(비표준 헤더 / 중복 토큰) 어느 하나라도 있으면 본 표 출력에 "Spirit lint" 섹션 추가
- (3) 결과는 별도 "Sensors — settings.json hook 등록" 섹션으로 분리. `MISS_HOOKS > 0` 일 때만 출력 (전부 등록이면 본 표 row의 ✅ 만으로 충분).
  - `MISSING_HOOK_FILES` 가 비어있지 않으면 초기 설치 미완으로 별도 표기 — 등록 옵션 [s]만으로는 못 고침.

```
🧪  Spirit lint
   ⚠️ spirit/rules/<project>-<category>.md — 비표준 헤더 3개 (SP-CAT-NNN 형식 위배)
   ⚠️ 중복 SP-DOM-008 — <project>-domain.md 2회 등장

🪝  Sensors — settings.json hook 등록
   ⚠️  template hook REG_HOOKS/TOTAL_HOOKS 등록 — MISS_HOOKS 개 미등록:
      <MISSING_HOOKS 배열을 한 줄씩 echo — 아래는 형태 예시일 뿐, hook 이름·개수는 template SSOT 따라감>
      - .ax/hooks/<sub>/<file>.sh
      - .ax/hooks/<sub>/<file>.sh
      ...
   ⚠️ path-scoped loading 담당 hook 이 미등록 — paths 선언 룰 N개 있는데 동작 안 함
      (HAS_PATHS && HOOK_REGISTERED == 0 일 때만 출력. 어떤 hook 이 그 역할인지는 template 이 정함)
   ❌ 초기 설치 미완 — .ax/hooks/ 안에 없는 항목 K개:  ← MISSING_HOOK_FILES 비었을 땐 출력 생략
      <MISSING_HOOK_FILES 배열을 한 줄씩 echo — `/up` 재실행으로만 복원 가능>
```

> **TOTAL_HOOKS 가 0인 경우**: `PLUGIN_ROOT` 미도출 또는 template 부재 — 이때는 "Sensors — settings.json hook 등록" 섹션을 통째로 skip 하고 path-scoped 단독 검증(HAS_PATHS + HOOK_REGISTERED) 결과만 본 표에서 처리. doctor가 plugin 컨텍스트에서 발동되면 거의 항상 도출돼요.

`다음 단계`에 추가:

```
 [n] ✅ spirit lint 정리                 [추천]
  명령 비표준 헤더 수정 + 중복 토큰 해소 (사용자)
  이유 spirit/SKILL.md:28-31 lint 통과

 [s] ✅ template hook 등록 (미등록 MISS_HOOKS 개)         [추천 — MISS_HOOKS > 0 일 때]
  1순위 bash .ax/scripts/bash/register-spirit-hook.sh
        → path-scoped loading 담당 hook 1개 등록 (idempotent)
        → 나머지 hook 은 (i) `.ax/settings.json.suggested` 머지 또는 (ii) LLM 이 template 을
          읽어 jq 로 직접 append (백업 후, 사용자 키 보존)
  초기 설치 미완 (MISSING_HOOK_FILES 비지 않음) 항목은 [s]로 못 고침 →
        `/up` 재호출 권장: `goax up` 또는 `/up` skill 호출 (기존 자산 보존).
  결과 template 이 선언한 EventName · matcher · hook 전체 활성
  이유 hook 셋 자체는 template 이 결정 — 어떤 조합이든 doctor 는
        이름 hardcode 없이 자동 따라감
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
    && MISMATCHES+=("CLAUDE.md는 shim 메커니즘 명시 — 폐기됨 (generate-rule-shims.sh 없음)")
[ "$DESC_HOOK" -eq 1 ] && [ "$DESC_SHIM" -eq 1 ] \
    && MISMATCHES+=("CLAUDE.md가 두 메커니즘 동시 명시 — 모순")
[ "$INST_HOOK" -eq 1 ] && [ "$DESC_HOOK" -eq 0 ] && [ "$DESC_SHIM" -eq 0 ] \
    && MISMATCHES+=("hook 활성됐지만 CLAUDE.md path-scoped 설명 누락")
```

보고:
- mismatch 없으면 출력 생략 (조용)
- 있으면 본 표 끝에 "문서 ↔ 실제 일치" 섹션 추가:

```
📑  문서 ↔ 실제 일치
   ⚠️  CLAUDE.md는 shim 메커니즘 명시 — 옛 버전에서 폐기됨 (generate-rule-shims.sh 없음)
   ⚠️  CLAUDE.md가 두 메커니즘 동시 명시 — 모순
```

`다음 단계`에 추가:

```
 [d] ✅ CLAUDE.md path-scoped 설명 갱신                 [추천]
  명령 path-scoped 섹션을 현재 활성 메커니즘으로 갱신
        (Design B → "PreToolUse hook이 자동 안내, .ax/hooks/pre-edit/spirit-rules-inject.sh")
  이유 다른 세션이 stale 메커니즘 언어로 답변하는 위험 차단
```

자동 적용 X — 사용자 + LLM이 함께 path-scoped 섹션 본문을 작성. 이 검증 자체는 grep만 — 결정론.

**왜 이 검증이 필요한가**: 세션마다 CLAUDE.md 컨텍스트가 다를 수 있어, 한 세션이 옛 design generation으로 작업하면 CLAUDE.md를 Design A 언어로 되돌리거나 두 메커니즘을 섞을 수 있음. 실제 hook은 Design B로 동작하지만 문서는 다른 메커니즘을 가리키면 신뢰 침식. 이 검증이 마지막 방어선.

### 3.9 Rule Enforcement invariant — `check-rule-enforcement.sh` 위임

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
RE_I6=$(echo "$RESULT" | jq -r '.result.i6_no_trigger | length')
```

검증 invariants (스크립트가 mandate, doctor 는 보고만):
- **I1**: 🔴 CRITICAL 의 `enforced_by` 는 `hook:*` / `external:*` 만 (TODO/human/script 금지)
- **I2**: `TODO:*` 는 deadline 필수 (`YYYY-MM-DD` 또는 `+Nd/+Nw`)
- **I3**: deadline 임박(≤7일) / 초과 보고
- **I5**: `enforced_by: hook:<path>` 면 (a) 파일 존재 (b) `.claude/settings.json` 등록
- **I6**: `enforced_by: external:*` 면 자동 트리거(CI workflow[GitHub/GitLab/Circle/Jenkins/
  Azure/Buildkite] / git pre-commit / husky / pre-commit-framework / lefthook)가 리포에
  1개 이상 실재 — 없으면 "손으로 돌릴 때만" 도는 라벨뿐인 룰 (I1 을 통과해도 실체가
  없는 케이스를 잡는 invariant). goax wrapper 만 있는 pre-commit 은 트리거로 안 쳐요
  (up 이 기본 설치하므로 자기 무력화) — 프로젝트 전용 chain 훅이 있을 때만 인정

자세한 schema·invariant 본문: `.ax/docs/reference/rule-enforcement.md` (사용자 프로젝트에 깔림).

보고 — 위반 0 이면 본 표의 ✅ 만, 1+ 이면 별도 섹션:

```
⚖️  Rule Enforcement
   ❌ I1 위반 — CRITICAL 인데 자동 차단 메커니즘 없음 (거짓 약속) RE_I1건:
      <i1_violations 배열을 한 줄씩 echo: "rule_id (enforced_by, enforced_kind)">
   ❌ I2 위반 — TODO 인데 deadline 없음 RE_I2건:
      <i2_violations 동상>
   ⚠️  I3 임박 (≤7일) RE_I3IM건 / 초과 RE_I3OD건:
      <i3_imminent + i3_overdue, deadline + days_left/days_overdue 포함>
   ⚠️  I5 위반 — hook 파일 부재 RE_I5F건 / 미등록 RE_I5R건:
      <i5_file_missing + i5_not_registered>
   ❌ I6 위반 — external 인데 자동 트리거 없음 RE_I6건 (I6 는 트리거 0 일 때만 발동 — 감지된 트리거는 항상 "없음"):
      <i6_no_trigger 배열을 한 줄씩 echo: "rule_id (enforced_by)">
```

`다음 단계` 옵션 (위반 종류별, 무거운 것부터):

```
 [r] ✅ 라벨 강등 — CRITICAL → MANDATORY (I1 위반 RE_I1건)         [최우선 추천]
   명령  CLAUDE.md 의 🔴 → 🟡 일괄 변환 + enforced_by 형식 정리 (사용자 confirm 후 LLM 적용)
   이유  CRITICAL 라벨이 거짓 약속 — 라벨과 실제가 일치해야 다른 세션 오인 차단
   대안  [w] hook 작성 후 🔴 유지 — 이쪽이 정직하지만 시간 듦

 [w] ✅ hook 작성 — enforced_by 가 가리키는 hook 파일 신규 작성   [장기 — 룰 진짜 enforce]
   명령  .ax/hooks/<sub>/<basename>.sh 직접 작성 (룰 의미 의존, template 없음)
        + 작성 후 register-spirit-hook.sh 로 settings.json 등록 (또는 suggested 병합)
   이유  CRITICAL 유지하면서 약속을 진짜로 지킴

 [d] ✅ deadline 갱신 — 임박/초과 TODO 에 새 absolute date 부여     [강등 거부 시]
   명령  enforced_by: TODO:<new-date> 갱신 (사용자 입력)
   이유  ADR 검토 시점 연기. 단 단순 연기 반복은 anti-pattern (3회 이상 → 강등 권장)

 [g] ✅ deadline 입력 — I2 위반 (deadline 없음) 에 absolute date 부여
   명령  enforced_by: TODO → TODO:<YYYY-MM-DD>
   이유  invariant I2 통과 + doctor 가 추적 가능 상태로

 [t] ✅ 트리거 설치 — I6 위반 (external 인데 자동 실행 없음)
   명령  CI 워크플로우 작성 (external 도구를 push 마다 실행) — 이게 본 처방
        또는 external 도구를 실행하는 프로젝트 전용 훅을 .ax/hooks/pre-commit/ 에 추가
        + bash .ax/scripts/bash/install-git-hooks.sh (chain 을 사람 커밋에도 연결)
   이유  external 라벨을 진짜 자동 차단으로. goax wrapper 설치만으로는 I6 가 안 풀려요 —
        wrapper 는 chain 만 하고 external 도구를 직접 실행하지 않으니까요
```

**원칙**: 자동 수정 X — 모든 옵션은 사용자 confirm 후 LLM 이 CLAUDE.md / spirit/rules 갱신. 강등은 특히 사용자 의도 변경이라 명시 동의 필수.

**왜 이 검증이 필요한가**: onboarding 이 deferred ("나중에 hook 작성") 옵션을 받아도 추적 메커니즘이 없으면 deadline 이 흘러도 아무도 모름. 🔴 라벨이 enforce 보장 없이 박혀있으면 다른 세션이 "이 룰은 자동 차단됨" 으로 오인 → 진짜 위반이 살아있어도 안전한 줄. 이 검증이 영구 추적 안전망.

### 3.10 Sensors — Liveness (`check-sensor-liveness.sh` 위임)

rule-enforcement(3.9) 가 룰 **라벨**의 schema 를 본다면, 이 검사는 **Sensors 장치**의 생사를 봐요 — 라벨이 완벽해도 장치가 죽어 있으면 아무것도 차단되지 않아요.

```bash
RESULT_L=$(bash "$ROOT/.ax/scripts/bash/check-sensor-liveness.sh" --json 2>/dev/null)
L_SCAFFOLD=$(echo "$RESULT_L" | jq -r '.result.grep_scaffold_unfilled')
L_DEMO=$(echo "$RESULT_L" | jq -r '.result.grep_demo_content')
L_GITHOOK=$(echo "$RESULT_L" | jq -r '.result.git_precommit_installed')
L_BZ=$(echo "$RESULT_L" | jq -r '.result.blocking_zero')
L_RM=$(echo "$RESULT_L" | jq -r '.result.session_root_mismatch')
L_ROOT=$(echo "$RESULT_L" | jq -r '.result.project_root')
```

검사 항목 (스크립트가 mandate, doctor 는 보고만):
- **C1 grep 스캐폴드/데모**: `critical-rule-grep.sh` 가 미작성 스캐폴드(`#goax-grep-scaffold` 마커)거나 구버전 데모 내용(남의 룰 검사) 그대로면 보고
- **C2 git pre-commit 미설치**: Claude Code PreToolUse 는 **에이전트가 실행하는** `git commit` 만 잡음 — 사람이 터미널에서 하는 커밋은 git hook 이 없으면 완전 우회. `install-git-hooks.sh` 로 커버
- **C3 차단 능력 0**: `sensors.mode` 가 warning/off 이고 git hook 도 없으면 어떤 위반도 "경고 후 통과"(off 는 검사 자체 생략)만 함. 기본 설치가 이 상태라 명시적으로 보고
- **C4 세션 루트 이탈**: `CLAUDE_PROJECT_DIR ≠ .ax 루트` — 서브디렉토리(특히 gitignore 된 생성물 디렉토리)에서 세션 시작 시 훅·spirit 주입이 조용히 누락될 위험

보고 — finding 0 이면 본 표의 ✅ 만, 1+ 이면:

```
🫀 Sensors — Liveness
   ⚠️  C1 grep 훅 미작성/데모 잔존 — AGENTS.md 🔴 룰의 패턴을 채우거나 /up 재실행
   ⚠️  C2 git pre-commit 미설치 — bash .ax/scripts/bash/install-git-hooks.sh
   ❌ C3 차단 능력 0 — mode=<sensors_mode> (+ git hook 부재). 지금 어떤 위반도 자동 차단되지 않아요
   ⚠️  C4 세션 루트 이탈 — 세션을 <L_ROOT> 에서 시작하세요
```

## 3. 출력

```
🩺 goax doctor — /path/to/your-project
    goax 0.3.1 · preset=default · installed 2026-05-02

🏛️  Layer 1 — Constitution
   ✅ CLAUDE.md (62줄, 시그널 라벨 🔴×3 / 🟡×9 / 🔵×1, 4계층 인덱스 ✓)

⚙️  Layer 0 — Triage / 설정
   ✅ config.yml (domain_risk 30 keys, default L1)
   ✅ version (goax <version>)

🧠  Cross-cut — Spirit
   ✅ spirit/values.md (사용자 정의됨)
   ⚠️ spirit/tone.md → placeholder 그대로
   ✅ spirit/rules/ (사용자 큐레이션 N 카테고리; opt-in 샘플은 .ax/_templates/spirit/)

🪤  Cross-cut — Mistake Loop
   ✅ mistakes/ (3건 누적)

🥕  Layer 3 — Spec / ADR
   ✅ docs/adr/ (1건: 0001-goax-adoption.md)
   ✅ .ax/_templates/spec/
   ⚠️ docs/spec/NNN-*/ — 작성된 spec 0건 (첫 spec 권장)

📦  Layer 2 — Module Rules
   ✅ <module>/CLAUDE.md (5/13 모듈 — L2/L3 도메인만, 선택적)

🪝  Sensors — Hooks
   ✅ pre-bash, pre-edit, post-edit, pre-commit hooks (디렉토리)
   ✅ .claude/settings.json
   ✅ template hook 등록: REG_HOOKS/TOTAL_HOOKS   (미등록 시 ⚠️  — 리스트는 별도 🪝 "Sensors — settings.json hook 등록" 섹션)

🎯  점수
   90%   (9 / 11)
   ▲ +7%p vs 직전 호출 (83% → 90%)        ← state.json 에 직전 점수 있을 때만 표기
   ✅ 해소: version drift · scripts backfill · _templates drift

🚦  다음 단계

   [a] ✅ tone.md 우리 팀 말투로 수정    [추천]
       파일 .ax/spirit/tone.md
       이유 placeholder 그대로 — 모든 sub-agent가 default 톤 사용 중
       방법 ~해요 체 + 우리 팀 안티패턴 추가

   [b] 📝 첫 spec 작성         [권장]
       명령 "새 spec 만들어줘 — <slug>"
       이유 Layer 3은 template만 — 실제 spec이 있어야 game이 시작됨

   ▸ 답해주세요 [a] / [b] / 또는 그냥 보고만
```

**규칙**
- **상태 emoji** (인라인): ✅ pass · ⚠️ placeholder/주의/drift/회귀 위험 · ❌ 누락/실패 · ℹ️ 정보성
  ※ 🟡 는 doctor 상태 indicator 로 쓰지 않음 — CLAUDE.md 시그널 라벨 (🔴 CRITICAL / 🟡 MANDATORY / 🔵 CONVENTION) 전용. 충돌 회피 위해 doctor 주의 = ⚠️ 로 통일.
- **섹션 헤더 emoji** (layer 구분): 🏛️ Constitution · ⚙️ Triage/설정 · 🧠 Spirit · 🪤 Mistake Loop · ⚖️ Rule Enforcement · 🥕 Spec/ADR · 📦 Module Rules · 🪝 Sensors · 🔄 Plugin update · 🧪 Spirit lint · 📑 문서↔실제 일치 · 🧹 마이그레이션 잔재 · 🎯 점수 · 🚦 다음 단계
- 다음 단계 옵션은 결손이 큰 항목부터 우선순위 부여
- `[권장]`/`[추천]` 표시는 점수 기여도 + 안전성 기준
- 문제 없으면 "다음 단계" 섹션에 [a] "첫 spec 작성"·[b] "tone.md 커스터마이즈"처럼 발전적 옵션
- audit (mistake 회고) 안내는 doctor 가 하지 않음 — `audit` skill 전담
- **점수 시각화**: 백분율 큰 글자 우선 + 분수 보조 (`90%   (9 / 11)`). 직전 점수가 `state.json:cross_cut.doctor.last_score` 에 있으면 다음 줄에 `▲ +Np vs 직전 호출 (X% → Y%)` 한 줄. 해소된 항목은 `✅ 해소:` 한 줄에 `·` separator. 길어지면 bullet list. 한 줄에 다 박지 말 것 — 시각적 stacking 이 핵심.
- **이모지 사용 원칙**: 섹션 헤더 + 상태 indicator 만 emoji. 본문 안에 emoji 남발 X (사용자 가독성). monochrome ASCII (`✓` `·` `✗` `─`) 는 색깔이 없어 layer scan 어려우므로 위 매핑으로 통일.

## 4. --strict 모드

placeholder는 통과로 안 봄. 모든 항목이 사용자 정의 상태여야 score 만점.
사용자가 "엄격하게 진단해줘", "strict mode" 같은 표현 쓰면 자동 적용.

## 절대 금지

- 결손이 있으면 그냥 ✗만 찍지 말고 **구체적 다음 명령**을 제시
- "전부 OK!" 같은 자가 칭찬 금지
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
