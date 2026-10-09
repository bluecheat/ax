#!/usr/bin/env bash
# .ax/scripts/bash/agent-model.sh — goax 서브에이전트를 띄울 때 Agent 도구에 넘길 model
#
# 왜: 에이전트 정의(agents/*.md frontmatter `model:`)가 기본값이고, 팀이 그걸 바꾸려면 .ax/config.yml 의
#     `agent_models` 에 적어요. skill 이 띄우기 직전에 이걸 불러 값이 있으면 `model` 로 넘겨요 — 넘기지 않으면
#     에이전트 정의의 기본값이 쓰여요.
#
# Usage:
#   bash agent-model.sh <agent> [<agent>...] [--json]     # 예: agent-model.sh architect evaluator --json
#   bash agent-model.sh --all [--json]                    # goax 에이전트 전부
#
#   agent_models:            # .ax/config.yml — 줄마다 `  <에이전트>: <모델>`
#     architect: opus
#     evaluator: sonnet
#
#   값: opus | sonnet | haiku | fable — Agent 도구의 model 값 그대로. 그 밖의 값(`inherit` 포함 — Agent 도구엔
#   "부모 모델" 값이 없어서 넘기지 않으면 에이전트 정의 기본값이 쓰여요)과 goax 에 없는 에이전트 이름,
#   블록이 아닌 `agent_models: {…}` 는 경고로 알리고 무시해요 — 설정이 조용히 안 먹히지 않게요.
#
# Output (--json):
#   {"status":"ok","result":{"models":{"architect":"sonnet","evaluator":null},
#                            "sources":{"architect":"config","evaluator":"default"}},…}
#   models.<이름> 이 null 이면 model 을 넘기지 않아요.
#
# Exit: 0 ok(경고 있어도) · 1 error (에이전트 이름 없음 · 모르는 이름)
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# plugin 의 agents/*.md 와 같아야 해요 (smoke 가 대조해요)
KNOWN="architect evaluator lane-scout lane-worker rules-auditor screen-designer"
MODELS="opus sonnet haiku fable"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; ALL=false; NAMES=()
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi   # --dry-run 은 읽기 전용이라 no-op
    case "$1" in
        --all) ALL=true ;;
        --*)   goax_error "알 수 없는 옵션: $1"; exit "$EXIT_ERROR" ;;
        *)     NAMES+=("$1") ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

known() { local a; for a in $KNOWN; do [ "$a" = "$1" ] && return 0; done; return 1; }
model_ok() { local m; for m in $MODELS; do [ "$m" = "$1" ] && return 0; done; return 1; }
if [ "$ALL" = true ]; then
    # shellcheck disable=SC2206
    NAMES=($KNOWN)
fi
[ "${#NAMES[@]}" -gt 0 ] || fail "에이전트 이름이 필요해요 (예: architect evaluator) — 전부는 --all"
for n in "${NAMES[@]}"; do known "$n" || fail "goax 에이전트가 아니에요: $n (있는 것: $KNOWN)"; done

command -v jq >/dev/null 2>&1 || fail "jq 가 필요해요 — 모델을 못 정하면 넘기지 말고 에이전트 기본값으로 띄워요"
ROOT=$(find_project_root) || exit "$EXIT_ERROR"
CFG="$ROOT/.ax/config.yml"

# agent_models 블록의 `  키: 값` 만 — 값의 따옴표 한 쌍과 뒤 주석을 벗겨요. 블록이 없으면 빈 출력.
PAIRS=""
if [ -f "$CFG" ]; then
    PAIRS=$(awk '
        /^agent_models:[ \t]*[^ \t#]/ { print "@@flow\t"; inb = 0; next }
        /^[^ \t#]/ { inb = ($0 ~ /^agent_models:[ \t]*(#.*)?$/); next }
        inb && /^[ \t]+[^ \t#][^:]*:/ {
            k = $0; sub(/^[ \t]+/, "", k); sub(/:.*/, "", k)
            v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
            gsub(/^["\047]|["\047]$/, "", v)
            print k "\t" v
        }
    ' "$CFG")
fi

WARNS=()
while IFS="$(printf '\t')" read -r k v; do
    [ -n "$k" ] || continue
    if [ "$k" = @@flow ]; then WARNS+=("config.yml agent_models 는 블록으로 적어요 (줄마다 '  <에이전트>: <모델>') — 한 줄 {…} 형식은 읽지 않아요"); continue; fi
    known "$k" || WARNS+=("config.yml agent_models.$k — goax 에이전트가 아니에요, 무시해요 (있는 것: $KNOWN)")
    model_ok "$v" || WARNS+=("config.yml agent_models.$k: '$v' — 넘길 수 없는 값이라 에이전트 기본값을 써요 (값: $MODELS)")
done <<EOF
$PAIRS
EOF

M_JSON="{}"; S_JSON="{}"
for n in "${NAMES[@]}"; do
    v=$(printf '%s\n' "$PAIRS" | awk -F '\t' -v k="$n" '$1 == k { v = $2 } END { print v }')
    if model_ok "$v"; then src=config; else src=default; v=""; fi
    M_JSON=$(printf '%s' "$M_JSON" | jq -c --arg k "$n" --arg v "$v" '. + {($k): (if $v == "" then null else $v end)}')
    S_JSON=$(printf '%s' "$S_JSON" | jq -c --arg k "$n" --arg s "$src" '. + {($k): $s}')
done

if [ "$JSON_MODE" = true ]; then
    W_JSON="[]"; [ "${#WARNS[@]}" -gt 0 ] && W_JSON=$(printf '%s\n' "${WARNS[@]}" | jq -Rsc 'split("\n") | map(select(. != ""))')
    STATUS=ok; [ "${#WARNS[@]}" -gt 0 ] && STATUS=warning
    json_output "$STATUS" "{\"models\":$M_JSON,\"sources\":$S_JSON}" \
        "models 값이 null 이 아니면 Agent 호출에 model 로 넘겨요 — null 이면 넘기지 않아요 (에이전트 정의 기본값)" "$W_JSON"
else
    for w in ${WARNS[@]+"${WARNS[@]}"}; do goax_warn "$w"; done
    printf '%s\n' "$M_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value // "-")"'
fi
exit "$EXIT_OK"
