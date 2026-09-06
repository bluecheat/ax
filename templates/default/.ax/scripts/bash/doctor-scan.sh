#!/usr/bin/env bash
# .ax/scripts/bash/doctor-scan.sh — doctor 의 인라인 진단 셋을 스크립트로: 마이그레이션 잔재 · hook 등록 · 문서↔실제 · 도달 지도
#
# Usage:
#   bash doctor-scan.sh [--json] [--plugin-dir <dir>]
#
# 검사 (doctor SKILL.md 3.6 · 3.7(3) · 3.8 이 산문 bash 로 하던 것 + 신규 도달 지도):
#   migration   .gitignore 누락 엔트리 · spirit/rules/output-style.md 잔재 · 미처리 .suggested ·
#               spec README.md 잔재 · 빈 checklists/contracts 디렉토리
#   hooks       settings.json.template(SSOT) 이 선언한 (이벤트 키, .ax/hooks/*.sh) **쌍** 전부가
#               .claude/settings.json 의 같은 이벤트 아래 있는지 — 훅은 등록된 이벤트에서만 발화하니
#               Stop 훅이 PreToolUse 에 적혀 있으면 미등록이에요
#               (파일 자체가 없으면 missing_files — 초기 설치 미완). PLUGIN_DIR 없으면 skip
#   doc_actual  CLAUDE.md/AGENTS.md 가 설명하는 path-scoped 메커니즘(hook vs 폐기된 shim) ↔ 실제 설치 상태
#   hooks.events settings.json 에 template 의 이벤트 키(UserPromptSubmit·PreToolUse·PostToolUse·SubagentStart·Stop)가 다 있는지
#   handoff     인계 노트(.ax/docs/STATUS.md)의 `- [ ] YYYY-MM-DD …` 기한 — ≤7일 임박 · 초과 (I3 와 같은 규칙)
#   reach       도달 지도 — 룰 소스마다 "어떤 배관으로 세션에 닿는가, 그 배관이 살아 있는가":
#                 constitution   AGENTS.md 본문이 Claude Code 에 닿으려면 CLAUDE.md 가 있고 @AGENTS.md 를 import 해야 해요.
#                                AGENTS.md 만 있으면 Constitution 이 어디에도 안 가요 (Claude Code 는 AGENTS.md 를 안 읽어요)
#                 spirit-universal  paths: 없는 spirit 룰 — Constitution 의 @.ax/spirit/rules/<file> import 로만 닿아요
#                 spirit-scoped     paths: 있는 spirit 룰 — spirit-rules-inject.sh 가 등록돼야 닿아요
#                 module            .ax/modules/*/rules.md — module-rules-inject.sh 가 등록돼야 편집 시점에 닿아요
#
# 자동 수정은 안 해요. doctor 가 결과를 읽어 옵션([m]·[s]·[d]·[reach])을 사용자에게 제시해요.
#
# Output (--json):
#   {"status":"ok|warning","result":{"migration":{…},"hooks":{…},"doc_actual":{…},"reach":[{source,file,via,reached,reason,count}],
#     "findings":N},…}
# Exit: 0 ok/warning · 1 error · 2 skipped (jq 없음)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false; PLUGIN_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json)       JSON_MODE=true ;;
        --dry-run)    DRY_RUN=true ;;      # 읽기 전용 — 표준 옵션 호환용
        --plugin-dir) shift; PLUGIN_DIR="${1:-}" ;;
        --help|-h)    SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi
if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then
        printf '{"status":"skipped","result":{},"next_step":"jq 가 필요해요","warnings":["jq not found"],"errors":[]}\n'
    else goax_warn "jq 가 없어 skip"; fi
    exit "$EXIT_SKIPPED"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT" || exit "$EXIT_ERROR"
if [ -z "$PLUGIN_DIR" ]; then
    if [ -n "${CLAUDE_SKILL_DIR:-}" ] && [ -d "${CLAUDE_SKILL_DIR}/../../templates" ]; then
        PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
    elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/templates" ]; then
        PLUGIN_DIR="$CLAUDE_PLUGIN_ROOT"
    fi
fi
SETTINGS=".claude/settings.json"
FINDINGS=0
to_json_arr() { grep -v '^$' | jq -R . | jq -sc .; }

# ── migration ────────────────────────────────────────────────────
GI_EXPECT=".ax/state.json
.ax/current-task.json
.ax/*.suggested
.ax/.onboarding-pending"
if [ -n "$PLUGIN_DIR" ] && [ -f "$PLUGIN_DIR/templates/default/.gitignore.template" ]; then
    GI_EXPECT=$(grep -vE '^[[:space:]]*(#|$)' "$PLUGIN_DIR/templates/default/.gitignore.template")
fi
GI_MISSING=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ -f .gitignore ]; then grep -qxF "$line" .gitignore || GI_MISSING="${GI_MISSING}${line}
"; else GI_MISSING="${GI_MISSING}${line}
"; fi
done <<< "$GI_EXPECT"
STALE_OS=false; [ -f .ax/spirit/rules/output-style.md ] && STALE_OS=true
SUGGESTED=$(find .ax -maxdepth 2 -name '*.suggested' 2>/dev/null | sed 's|^\./||' | sort)
SPEC_README=""; SPEC_EMPTY=""
while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -f "$d/README.md" ] && SPEC_README="${SPEC_README}${d}/README.md
"
    for sub in checklists contracts; do
        [ -d "$d/$sub" ] && [ -z "$(ls -A "$d/$sub" 2>/dev/null)" ] && SPEC_EMPTY="${SPEC_EMPTY}${d}/${sub}/
"
    done
done < <(find .ax/docs/spec -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|^\./||' | sort)
GI_N=$(printf '%s' "$GI_MISSING" | grep -c . || true); SG_N=$(printf '%s' "$SUGGESTED" | grep -c . || true)
SR_N=$(printf '%s' "$SPEC_README" | grep -c . || true); SE_N=$(printf '%s' "$SPEC_EMPTY" | grep -c . || true)
MIG_N=$(( GI_N + SG_N + SR_N + SE_N )); [ "$STALE_OS" = true ] && MIG_N=$((MIG_N + 1))
FINDINGS=$((FINDINGS + MIG_N))
MIG=$(jq -nc --argjson gi "$(printf '%s' "$GI_MISSING" | to_json_arr)" --argjson os "$STALE_OS" \
    --argjson sg "$(printf '%s' "$SUGGESTED" | to_json_arr)" --argjson sr "$(printf '%s' "$SPEC_README" | to_json_arr)" \
    --argjson se "$(printf '%s' "$SPEC_EMPTY" | to_json_arr)" --arg n "$MIG_N" \
    '{gitignore_missing:$gi,stale_output_style:$os,suggested:$sg,spec_readme_stale:$sr,spec_empty_dirs:$se,findings:($n|tonumber)}')

# ── hooks — template SSOT 기반 ────────────────────────────────────
TPL="$PLUGIN_DIR/templates/default/.claude/settings.json.template"
EXPECTED=""; REGISTERED=""; MISSING=""; MISSING_FILES=""; HOOKS_CHECKED=false
SETTINGS_PRESENT=false; [ -f "$SETTINGS" ] && SETTINGS_PRESENT=true
# (이벤트, 경로) **쌍**으로 봐요. 예전엔 basename 이 settings.json 어딘가에 있기만 하면 등록으로 쳤어요 —
# Stop 훅을 PreToolUse 로 옮기고 Stop 을 빈 배열로 둬도 "이상 없음" 이 나왔어요. 훅은 등록된 이벤트에서만
# 발화하니, 파일 이름이 어디 적혔는지가 아니라 **어느 이벤트 아래** 적혔는지가 검사 대상이에요.
hook_pairs() {   # hook_pairs <settings.json> → "<Event> <.ax/hooks/….sh>" 줄 목록
    jq -r '(.hooks // {}) | to_entries[] | .key as $ev
           | (.value // []) | .[]? | (.hooks // []) | .[]? | (.command // empty)
           | "\($ev) \(.)"' "$1" 2>/dev/null \
      | sed -nE 's#^([A-Za-z]+) .*(\.ax/hooks/[^"'"'"' ]+\.sh).*$#\1 \2#p' | sort -u
}
if [ -n "$PLUGIN_DIR" ] && [ -f "$TPL" ]; then
    HOOKS_CHECKED=true
    REG_PAIRS=""
    [ "$SETTINGS_PRESENT" = true ] && REG_PAIRS=$(hook_pairs "$SETTINGS")
    while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        hp="${pair#* }"
        EXPECTED="${EXPECTED}${pair}
"
        if [ ! -f "$hp" ]; then
            # 파일 부재는 이벤트와 무관하니 경로 기준으로 한 번만 세요
            case "
$MISSING_FILES" in *"
$hp
"*) ;; *) MISSING_FILES="${MISSING_FILES}${hp}
" ;; esac
            MISSING="${MISSING}${pair}
"
        elif printf '%s\n' "$REG_PAIRS" | grep -qxF -- "$pair"; then
            REGISTERED="${REGISTERED}${pair}
"
        else
            MISSING="${MISSING}${pair}
"
        fi
    done <<< "$(hook_pairs "$TPL")"
fi
# path-scoped spirit 룰 수 (paths: 에 항목이 하나라도 있는 파일)
SCOPED_N=0; UNIVERSAL_N=0; SCOPED_FILES=""; UNIVERSAL_FILES=""
for f in .ax/spirit/rules/*.md; do
    [ -f "$f" ] || continue; case "$f" in */README.md) continue ;; esac
    if [ -n "$(goax_yaml_list "$f" paths | head -1)" ]; then SCOPED_N=$((SCOPED_N + 1)); SCOPED_FILES="${SCOPED_FILES}${f}
"
    else UNIVERSAL_N=$((UNIVERSAL_N + 1)); UNIVERSAL_FILES="${UNIVERSAL_FILES}${f}
"; fi
done
INJ_REG=false
[ -f .ax/hooks/pre-edit/spirit-rules-inject.sh ] && [ "$SETTINGS_PRESENT" = true ] \
    && grep -q 'spirit-rules-inject\.sh' "$SETTINGS" 2>/dev/null && INJ_REG=true
MOD_REG=false
[ -f .ax/hooks/pre-edit/module-rules-inject.sh ] && [ "$SETTINGS_PRESENT" = true ] \
    && grep -q 'module-rules-inject\.sh' "$SETTINGS" 2>/dev/null && MOD_REG=true
# 이벤트 키 자체가 있는지 — Stop·SubagentStart 처럼 나중에 생긴 이벤트는 파일이 있어도 키가 없으면 안 돌아요
EV_EXP=""; EV_REG=""; EV_MISS=""
if [ "$HOOKS_CHECKED" = true ]; then
    EV_EXP=$(jq -r '.hooks // {} | keys[]' "$TPL" 2>/dev/null | sort)
    [ "$SETTINGS_PRESENT" = true ] && EV_REG=$(jq -r '.hooks // {} | keys[]' "$SETTINGS" 2>/dev/null | sort)
    while IFS= read -r ev; do
        [ -z "$ev" ] && continue
        printf '%s\n' "$EV_REG" | grep -qx -- "$ev" || EV_MISS="${EV_MISS}${ev}
"
    done <<< "$EV_EXP"
fi
EVM_N=$(printf '%s' "$EV_MISS" | grep -c . || true); FINDINGS=$((FINDINGS + EVM_N))
EX_N=$(printf '%s' "$EXPECTED" | grep -c . || true); RG_N=$(printf '%s' "$REGISTERED" | grep -c . || true)
MS_N=$(printf '%s' "$MISSING" | grep -c . || true); MF_N=$(printf '%s' "$MISSING_FILES" | grep -c . || true)
FINDINGS=$((FINDINGS + MS_N))
HOOKS=$(jq -nc --argjson chk "$HOOKS_CHECKED" --argjson sp "$SETTINGS_PRESENT" \
    --argjson ex "$(printf '%s' "$EXPECTED" | to_json_arr)" --argjson rg "$(printf '%s' "$REGISTERED" | to_json_arr)" \
    --argjson ms "$(printf '%s' "$MISSING" | to_json_arr)" --argjson mf "$(printf '%s' "$MISSING_FILES" | to_json_arr)" \
    --arg exn "$EX_N" --arg rgn "$RG_N" --arg msn "$MS_N" --arg mfn "$MF_N" \
    --arg sc "$SCOPED_N" --argjson ir "$INJ_REG" --argjson mr "$MOD_REG" \
    --argjson ee "$(printf '%s' "$EV_EXP" | to_json_arr)" --argjson er "$(printf '%s' "$EV_REG" | to_json_arr)" \
    --argjson em "$(printf '%s' "$EV_MISS" | to_json_arr)" --arg emn "$EVM_N" \
    '{checked:$chk,settings_present:$sp,expected:$ex,registered:$rg,missing:$ms,missing_files:$mf,
      total:($exn|tonumber),registered_n:($rgn|tonumber),missing_n:($msn|tonumber),missing_files_n:($mfn|tonumber),
      path_scoped_rules:($sc|tonumber),spirit_inject_registered:$ir,module_inject_registered:$mr,
      events:{expected:$ee,registered:$er,missing:$em,missing_n:($emn|tonumber)}}')

# ── doc_actual — Constitution 이 설명하는 메커니즘 ↔ 실제 ─────────
DOC_FILES=""; [ -f CLAUDE.md ] && DOC_FILES="CLAUDE.md"; [ -f AGENTS.md ] && DOC_FILES="$DOC_FILES AGENTS.md"
DESC_HOOK=false; DESC_SHIM=false
# shellcheck disable=SC2086
[ -n "$DOC_FILES" ] && grep -q 'spirit-rules-inject\.sh' $DOC_FILES 2>/dev/null && DESC_HOOK=true
# shellcheck disable=SC2086
[ -n "$DOC_FILES" ] && grep -qE 'generate-rule-shims\.sh|\.claude/rules/.*shim' $DOC_FILES 2>/dev/null && DESC_SHIM=true
INST_SHIM=false; [ -f .ax/scripts/bash/generate-rule-shims.sh ] && INST_SHIM=true
MM=""
[ "$DESC_HOOK" = true ] && [ "$INJ_REG" = false ] && MM="${MM}Constitution 은 hook 메커니즘을 명시 — 실제는 미설치/미등록
"
[ "$DESC_SHIM" = true ] && [ "$INST_SHIM" = false ] && MM="${MM}Constitution 은 shim 메커니즘을 명시 — 폐기됨 (generate-rule-shims.sh 없음)
"
[ "$DESC_HOOK" = true ] && [ "$DESC_SHIM" = true ] && MM="${MM}Constitution 이 두 메커니즘을 동시에 명시 — 모순
"
[ "$INJ_REG" = true ] && [ "$DESC_HOOK" = false ] && [ "$DESC_SHIM" = false ] && [ "$SCOPED_N" -gt 0 ] && MM="${MM}hook 은 활성인데 Constitution 에 path-scoped 설명이 없음
"
MM_N=$(printf '%s' "$MM" | grep -c . || true); FINDINGS=$((FINDINGS + MM_N))
DOC=$(jq -nc --argjson dh "$DESC_HOOK" --argjson ds "$DESC_SHIM" --argjson ih "$INJ_REG" --argjson is "$INST_SHIM" \
    --argjson mm "$(printf '%s' "$MM" | to_json_arr)" '{desc_hook:$dh,desc_shim:$ds,inst_hook:$ih,inst_shim:$is,mismatches:$mm}')

# ── reach — 도달 지도 ─────────────────────────────────────────────
REACH="[]"
add_reach() {   # source file via reached reason count
    REACH=$(printf '%s' "$REACH" | jq -c --arg s "$1" --arg f "$2" --arg v "$3" --argjson r "$4" --arg why "$5" --arg n "$6" \
        '. + [{source:$s,file:$f,via:$v,reached:$r,reason:$why,count:($n|tonumber)}]')
    [ "$4" = false ] && FINDINGS=$((FINDINGS + 1))
}
RULES_FILE=""
for c in AGENTS.md CLAUDE.md; do
    [ -f "$c" ] && grep -qE '^(🔴|🟡|🔵) \*\*`' "$c" 2>/dev/null && { RULES_FILE="$c"; break; }
done
[ -z "$RULES_FILE" ] && [ -f AGENTS.md ] && RULES_FILE="AGENTS.md"
[ -z "$RULES_FILE" ] && [ -f CLAUDE.md ] && RULES_FILE="CLAUDE.md"
RULE_N=0; [ -n "$RULES_FILE" ] && RULE_N=$(grep -cE '^(🔴|🟡|🔵) \*\*`' "$RULES_FILE" 2>/dev/null || true)
if [ -z "$RULES_FILE" ]; then
    add_reach constitution "" "—" false "Constitution 파일이 없어요 (AGENTS.md · CLAUDE.md 둘 다 부재) — /up 또는 onboarding Q1" 0
elif [ "$RULES_FILE" = "CLAUDE.md" ]; then
    add_reach constitution CLAUDE.md "CLAUDE.md 직접" true "" "$RULE_N"
elif [ ! -f CLAUDE.md ]; then
    add_reach constitution AGENTS.md "CLAUDE.md @AGENTS.md" false "CLAUDE.md 가 없어요 — Claude Code 는 AGENTS.md 를 읽지 않아서 Constitution 이 어디에도 안 가요. CLAUDE.md 에 '@AGENTS.md' 한 줄이 필요해요" "$RULE_N"
elif ! grep -qE '^@AGENTS\.md[[:space:]]*$' CLAUDE.md 2>/dev/null; then
    add_reach constitution AGENTS.md "CLAUDE.md @AGENTS.md" false "CLAUDE.md 가 @AGENTS.md 를 import 하지 않아요 — 룰은 AGENTS.md 에 있는데 Claude Code 는 CLAUDE.md 만 읽어요" "$RULE_N"
else
    add_reach constitution AGENTS.md "CLAUDE.md @AGENTS.md" true "" "$RULE_N"
fi
if [ "$UNIVERSAL_N" -gt 0 ]; then
    NOT_IMPORTED=""
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if [ -z "$RULES_FILE" ] || ! grep -qF "@$f" "$RULES_FILE" 2>/dev/null; then NOT_IMPORTED="${NOT_IMPORTED}${f}
"; fi
    done <<< "$UNIVERSAL_FILES"
    NI_N=$(printf '%s' "$NOT_IMPORTED" | grep -c . || true)
    if [ "$NI_N" -eq 0 ]; then add_reach spirit-universal ".ax/spirit/rules/" "Constitution @import" true "" "$UNIVERSAL_N"
    else add_reach spirit-universal ".ax/spirit/rules/" "Constitution @import" false "paths: 없는 룰 ${NI_N}/${UNIVERSAL_N} 파일이 Constitution 에 @import 되지 않았어요 — 어느 세션에도 안 닿아요: $(printf '%s' "$NOT_IMPORTED" | tr '\n' ' ')" "$UNIVERSAL_N"; fi
fi
if [ "$SCOPED_N" -gt 0 ]; then
    if [ "$INJ_REG" = true ]; then add_reach spirit-scoped ".ax/spirit/rules/" "spirit-rules-inject.sh" true "" "$SCOPED_N"
    else add_reach spirit-scoped ".ax/spirit/rules/" "spirit-rules-inject.sh" false "paths: 있는 룰 ${SCOPED_N}개인데 spirit-rules-inject.sh 가 미설치/미등록 — 편집 시점에 안 닿아요 (register-spirit-hook.sh)" "$SCOPED_N"; fi
fi
MOD_N=$(find .ax/modules -mindepth 2 -maxdepth 2 -name 'rules.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "${MOD_N:-0}" -gt 0 ]; then
    if [ "$MOD_REG" = true ]; then add_reach module ".ax/modules/" "module-rules-inject.sh" true "" "$MOD_N"
    else add_reach module ".ax/modules/" "module-rules-inject.sh" false "모듈 룰 ${MOD_N}개인데 module-rules-inject.sh 가 미설치/미등록 — 편집 시점 자동 주입이 안 돼요 (triage 키워드 매칭만 남아요)" "$MOD_N"; fi
fi

# ── handoff — 인계 노트의 기한 (`- [ ] YYYY-MM-DD …`) — I3 와 같은 규칙: ≤7일 임박 · 초과 ──
# zero 의 "1순위 가정 검증" 과 "룰 ablation 재검토" 가 여기 살아요. 날짜가 문서 안에만 있으면 아무도 안 봐요.
to_epoch() { date -j -u -f '%Y-%m-%d' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null || echo ""; }
NOTE=".ax/docs/STATUS.md"; DL_JSON="[]"; DL_IMM=0; DL_OVER=0; NOTE_PRESENT=false
if [ -f "$NOTE" ]; then
    NOTE_PRESENT=true
    TODAY_E=$(to_epoch "$(date +%F)")
    while IFS= read -r ln; do
        [ -z "$ln" ] && continue
        d=$(printf '%s' "$ln" | sed -E 's/^- \[ \] ([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')
        txt=$(printf '%s' "$ln" | sed -E 's/^- \[ \] [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*//')
        de=$(to_epoch "$d"); [ -n "$de" ] && [ -n "$TODAY_E" ] || continue
        days=$(( (de - TODAY_E) / 86400 ))
        st=ok; [ "$days" -le 7 ] && st=imminent; [ "$days" -lt 0 ] && st=overdue
        [ "$st" = imminent ] && DL_IMM=$((DL_IMM + 1)); [ "$st" = overdue ] && DL_OVER=$((DL_OVER + 1))
        DL_JSON=$(printf '%s' "$DL_JSON" | jq -c --arg d "$d" --arg t "$txt" --arg n "$days" --arg s "$st" '. + [{date:$d,text:$t,days_left:($n|tonumber),status:$s}]')
    done < <(grep -E '^- \[ \] [0-9]{4}-[0-9]{2}-[0-9]{2}' "$NOTE" 2>/dev/null || true)
fi
FINDINGS=$((FINDINGS + DL_IMM + DL_OVER))
HANDOFF=$(jq -nc --argjson p "$NOTE_PRESENT" --argjson d "$DL_JSON" --arg i "$DL_IMM" --arg o "$DL_OVER" \
    '{present:$p,deadlines:$d,imminent:($i|tonumber),overdue:($o|tonumber)}')

RESULT=$(jq -nc --argjson m "$MIG" --argjson h "$HOOKS" --argjson d "$DOC" --argjson r "$REACH" --argjson ho "$HANDOFF" --arg n "$FINDINGS" \
    '{migration:$m,hooks:$h,doc_actual:$d,reach:$r,handoff:$ho,findings:($n|tonumber)}')
if [ "$JSON_MODE" = true ]; then
    if [ "$FINDINGS" -eq 0 ]; then json_output "ok" "$RESULT" "잔재·미등록·불일치·도달 결손 없음"
    else json_output "warning" "$RESULT" "finding ${FINDINGS}건 — doctor 가 옵션으로 제시해요 (자동 수정 안 함)"; fi
    exit "$EXIT_OK"
fi

printf '🩺 doctor-scan — %s\n' "$PROJECT_ROOT"
printf '\n🧹 마이그레이션 잔재 — %s건\n' "$MIG_N"
[ "$GI_N" -gt 0 ] && printf '   ⚠ .gitignore 누락 %s줄: %s\n' "$GI_N" "$(printf '%s' "$GI_MISSING" | tr '\n' ' ')"
[ "$STALE_OS" = true ] && printf '   ⚠ .ax/spirit/rules/output-style.md — 출고에서 제거된 잔재\n'
[ "$SG_N" -gt 0 ] && printf '   ⚠ 미처리 .suggested %s개: %s\n' "$SG_N" "$(printf '%s' "$SUGGESTED" | tr '\n' ' ')"
[ "$SR_N" -gt 0 ] && printf '   ⚠ spec README.md 잔재 %s건\n' "$SR_N"
[ "$SE_N" -gt 0 ] && printf '   ⚠ spec 빈 디렉토리 %s건\n' "$SE_N"
printf '\n🪝 hook 등록 — '
if [ "$HOOKS_CHECKED" = true ]; then
    printf '%s/%s 등록 (이벤트 키 + 경로 쌍)\n' "$RG_N" "$EX_N"
    [ "$MS_N" -gt 0 ] && printf '%s' "$MISSING" | sed '/^$/d; s/^/   ⚠ 미등록: /'
    [ "$MF_N" -gt 0 ] && printf '   ✗ 파일 자체가 없음 (초기 설치 미완 → /up): %s\n' "$(printf '%s' "$MISSING_FILES" | tr '\n' ' ')"
    [ "$EVM_N" -gt 0 ] && printf '   ⚠ 이벤트 키 미등록: %s — settings.json 에 그 이벤트가 아예 없어요\n' "$(printf '%s' "$EV_MISS" | tr '\n' ' ')"
else printf 'skip (plugin 경로 미도출 — --plugin-dir)\n'; fi
printf '\n📅 인계 노트 기한 — 임박 %s · 초과 %s\n' "$DL_IMM" "$DL_OVER"
printf '%s' "$DL_JSON" | jq -r '.[] | select(.status!="ok") | "   ⚠ \(.status) \(.date) (\(.days_left)일) — \(.text)"'
printf '\n📑 문서 ↔ 실제 — %s건\n' "$MM_N"
printf '%s' "$MM" | sed '/^$/d; s/^/   ⚠ /'
printf '\n🗺  도달 지도\n'
printf '%s' "$REACH" | jq -r '.[] | "   \(if .reached then "✓" else "✗" end) \(.source) (\(.count)) — \(.via)\(if .reached then "" else "\n      " + .reason end)"'
printf '\n→ finding %s건\n' "$FINDINGS"
exit "$EXIT_OK"
