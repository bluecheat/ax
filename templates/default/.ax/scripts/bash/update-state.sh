#!/usr/bin/env bash
# update-state.sh — .ax/state.json canonical update.
#
# 파일시스템 *실측*으로 derived value 계산:
#   - layers.{L0~L3}.active + 메트릭 (rules, signals, modules, specs, adrs)
#   - cross_cut.{spirit,mistakes}.active + 메트릭
#   - sensors_mode (config.yml)
#   - updated_at
#
# 모든 skill의 마무리에서 호출. ad-hoc jq 대신 이 스크립트 한 줄.
# state.json schema·ownership: docs/state-ownership.md (plugin repo).
#
# 사용:
#   bash .ax/scripts/bash/update-state.sh           # in-place update (기본)
#   bash .ax/scripts/bash/update-state.sh --json    # stdout JSON only (state.json은 안 건드림)
#   bash .ax/scripts/bash/update-state.sh --dry     # 계산 결과 미리보기 (stderr)
#
# 의존: jq (필수), grep, find, awk, common.sh

set -u

# common.sh source — goax_log, goax_mode 등 helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

# WS 검출 — common.sh 패턴 따름 (env 우선, cwd fallback)
WS="${CLAUDE_PROJECT_DIR:-$(pwd)}"
S="$WS/.ax/state.json"

MODE="${1:-update}"

if [ ! -f "$S" ]; then
    goax_error "state.json 없음 ($S) — installer 먼저 실행"
    exit 1
fi
command -v jq >/dev/null || { goax_error "jq 필요 (brew install jq)"; exit 1; }

# ─── derived values ─────────────────────────────────────

# Layer 0 — plugin 깔리면 항상 active (skills 자체가 plugin 제공)
L0_ACTIVE=true

# Layer 1 — root CLAUDE.md의 시그널 라벨 카운트 (wc -l: BSD/GNU grep 모두 안전)
# CONVENTION은 인라인(root) + @import된 spirit/rules/*.md 합산 — root에 인라인 정의가 없어도
# spirit/rules/ 의 🔵 룰들이 카운트되도록 (state.json convention=0 방지)
CRIT=0; MAND=0; CONV=0
if [ -f "$WS/CLAUDE.md" ]; then
    CRIT=$(grep -E '^🔴 \*\*`' "$WS/CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')
    MAND=$(grep -E '^🟡 \*\*`' "$WS/CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')
    # CLAUDE.md inline rule: 🔵 **`TOKEN`** 형식
    CONV_INLINE=$(grep -E '^🔵 \*\*`' "$WS/CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')

    # spirit/rules/ — heading 형식 (## SP-CAT-NNN: text, plugin 컨벤션, 0.1.8+)
    # + 옛 inline 형식 (^🔵 \*\*`) 합산해 0.1.7 호환 유지
    CONV_SPIRIT=0
    if [ -d "$WS/.ax/spirit/rules" ]; then
        CONV_SPIRIT_HEAD=$(grep -hE '^## SP-[A-Z]+-[0-9]{3}:' "$WS/.ax/spirit/rules/"*.md 2>/dev/null | wc -l | tr -d ' ')
        CONV_SPIRIT_INLINE=$(grep -hE '^🔵 \*\*`' "$WS/.ax/spirit/rules/"*.md 2>/dev/null | wc -l | tr -d ' ')
        CONV_SPIRIT=$((CONV_SPIRIT_HEAD + CONV_SPIRIT_INLINE))
    fi
    CONV=$((CONV_INLINE + CONV_SPIRIT))
fi
RULES=$((CRIT + MAND + CONV))
[ "$RULES" -gt 0 ] && L1_ACTIVE=true || L1_ACTIVE=false

# Layer 2 — modules/<name>/rules.md
MOD_COUNT=0
if [ -d "$WS/.ax/modules" ]; then
    MOD_COUNT=$(find "$WS/.ax/modules" -mindepth 2 -maxdepth 2 -name 'rules.md' 2>/dev/null \
                | wc -l | tr -d ' ')
fi
[ "$MOD_COUNT" -gt 0 ] && L2_ACTIVE=true || L2_ACTIVE=false

# Layer 3 — spec + ADR
SPEC_COUNT=0
ADR_COUNT=0
if [ -d "$WS/.ax/docs/spec" ]; then
    SPEC_COUNT=$(find "$WS/.ax/docs/spec" -mindepth 2 -name 'spec.md' 2>/dev/null | wc -l | tr -d ' ')
fi
if [ -d "$WS/.ax/docs/adr" ]; then
    ADR_COUNT=$(find "$WS/.ax/docs/adr" -maxdepth 1 -name '[0-9]*-*.md' 2>/dev/null | wc -l | tr -d ' ')
fi
L3_TOTAL=$((SPEC_COUNT + ADR_COUNT))
[ "$L3_TOTAL" -gt 0 ] && L3_ACTIVE=true || L3_ACTIVE=false

# Cross-cut Spirit — rules/*.md (README 제외) 또는 values.md 채워짐
SPIRIT_RULES=0
if [ -d "$WS/.ax/spirit/rules" ]; then
    SPIRIT_RULES=$(find "$WS/.ax/spirit/rules" -maxdepth 1 -name '*.md' \
                   ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
fi
VALUES_FILLED=false
if [ -f "$WS/.ax/spirit/values.md" ]; then
    BYTES=$(wc -c < "$WS/.ax/spirit/values.md" | tr -d ' ')
    [ "$BYTES" -gt 100 ] && VALUES_FILLED=true
fi
SP_ACTIVE=false
[ "$SPIRIT_RULES" -gt 0 ] && SP_ACTIVE=true
[ "$VALUES_FILLED" = "true" ] && SP_ACTIVE=true

# Cross-cut Mistakes — mistakes/*.md (README 제외)
MIS_COUNT=0
if [ -d "$WS/.ax/mistakes" ]; then
    MIS_COUNT=$(find "$WS/.ax/mistakes" -maxdepth 1 -name '*.md' \
                ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
fi
[ "$MIS_COUNT" -gt 0 ] && ML_ACTIVE=true || ML_ACTIVE=false

# 다음 audit까지 일수 — .ax/mistakes/.last-audit (epoch sec)
DUE_DAYS_PIPE=""
LAST_AUDIT_PIPE=""
if [ -f "$WS/.ax/mistakes/.last-audit" ]; then
    LAST=$(cat "$WS/.ax/mistakes/.last-audit" 2>/dev/null | tr -d '\n ')
    if [ -n "$LAST" ]; then
        ISO=$(date -u -r "$LAST" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
        if [ -n "$ISO" ]; then
            NOW_SEC=$(date +%s)
            DIFF=$(( (LAST + 7*24*3600 - NOW_SEC) / 86400 ))
            LAST_AUDIT_PIPE=" | .cross_cut.mistakes.last_audit = \"$ISO\""
            DUE_DAYS_PIPE=" | .cross_cut.mistakes.due_in_days = $DIFF"
        fi
    fi
fi

# Sensors mode (common.sh helper)
SENSORS_MODE=$(goax_mode)

# goax_version — .ax/version 파일에서 install 시점 stamp 읽기 (state.json.template은 placeholder)
GOAX_VER=""
if [ -f "$WS/.ax/version" ]; then
    GOAX_VER=$(grep -E '^goax:' "$WS/.ax/version" | head -1 | awk '{print $2}' | tr -d '\n ' || echo "")
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ─── jq filter ─────────────────────────────────────────

VERSION_PIPE=""
if [ -n "$GOAX_VER" ]; then
    VERSION_PIPE=" | .goax_version = \$ver"
fi

JQ_FILTER='
.updated_at = $now
| .layers.L0_triage.active = ($l0 | test("true"))
| .layers.L1_constitution.active = ($l1 | test("true"))
| .layers.L1_constitution.rules = ($rules | tonumber)
| .layers.L1_constitution.signals.critical = ($crit | tonumber)
| .layers.L1_constitution.signals.mandatory = ($mand | tonumber)
| .layers.L1_constitution.signals.convention = ($conv | tonumber)
| .layers.L2_module.active = ($l2 | test("true"))
| .layers.L2_module.module_claude_count = ($modc | tonumber)
| .layers.L3_spec_adr.active = ($l3 | test("true"))
| .layers.L3_spec_adr.specs = ($specs | tonumber)
| .layers.L3_spec_adr.adrs = ($adrs | tonumber)
| .cross_cut.spirit.active = ($sp | test("true"))
| .cross_cut.spirit.rules_count = ($spr | tonumber)
| .cross_cut.spirit.values_filled = ($vf | test("true"))
| .cross_cut.mistakes.active = ($ml | test("true"))
| .cross_cut.mistakes.count = ($misc | tonumber)
| .sensors_mode = $smode
'"$LAST_AUDIT_PIPE$DUE_DAYS_PIPE$VERSION_PIPE"

JQ_ARGS=(
    --arg now      "$NOW"
    --arg l0       "$L0_ACTIVE"
    --arg l1       "$L1_ACTIVE"
    --arg rules    "$RULES"
    --arg crit     "$CRIT"
    --arg mand     "$MAND"
    --arg conv     "$CONV"
    --arg l2       "$L2_ACTIVE"
    --arg modc     "$MOD_COUNT"
    --arg l3       "$L3_ACTIVE"
    --arg specs    "$SPEC_COUNT"
    --arg adrs     "$ADR_COUNT"
    --arg sp       "$SP_ACTIVE"
    --arg spr      "$SPIRIT_RULES"
    --arg vf       "$VALUES_FILLED"
    --arg ml       "$ML_ACTIVE"
    --arg misc     "$MIS_COUNT"
    --arg smode    "$SENSORS_MODE"
    --arg ver      "$GOAX_VER"
)

case "$MODE" in
    --json)
        jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$S"
        ;;
    --dry)
        goax_log "update-state dry-run:"
        printf '  layers   L0=%s L1=%s(%d rules: 🔴%d 🟡%d 🔵%d) L2=%s(modules=%d) L3=%s(spec=%d adr=%d)\n' \
            "$L0_ACTIVE" "$L1_ACTIVE" "$RULES" "$CRIT" "$MAND" "$CONV" \
            "$L2_ACTIVE" "$MOD_COUNT" "$L3_ACTIVE" "$SPEC_COUNT" "$ADR_COUNT" >&2
        printf '  cross    Sp=%s(rules=%d values_filled=%s) Ml=%s(count=%d)\n' \
            "$SP_ACTIVE" "$SPIRIT_RULES" "$VALUES_FILLED" "$ML_ACTIVE" "$MIS_COUNT" >&2
        printf '  sensors  mode=%s\n' "$SENSORS_MODE" >&2
        ;;
    update|*)
        TMP="$S.tmp.$$"
        if jq "${JQ_ARGS[@]}" "$JQ_FILTER" "$S" > "$TMP" 2>/dev/null; then
            mv "$TMP" "$S"
            goax_log "state.json updated — L:$L0_ACTIVE/$L1_ACTIVE/$L2_ACTIVE/$L3_ACTIVE Sp:$SP_ACTIVE Ml:$ML_ACTIVE mode:$SENSORS_MODE"
        else
            rm -f "$TMP"
            goax_error "jq update 실패 — state.json 그대로"
            exit 1
        fi
        ;;
esac
