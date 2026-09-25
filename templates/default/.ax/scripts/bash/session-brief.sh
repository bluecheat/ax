#!/usr/bin/env bash
# .ax/scripts/bash/session-brief.sh — 세션 첫머리에 알릴 것을 결정론으로 모아요
#
# 세 가지만 봐요. 말할 게 없으면 아무것도 안 내요.
#   handoff  current-task.json 의 handoff — now(+now_at) · next · open 앞 3개씩, 진행 중 task(phase ≠ idle)
#   version  .ax/version 설치본 < 플러그인 버전이면 "/up 으로 올리세요"
#            플러그인 버전: ${CLAUDE_CONFIG_DIR:-~/.claude}/plugins/installed_plugins.json 의 goax@* →
#            없으면 state.json .hud.plugin_version (skill 이 캐시해 둔 값)
#   audit    미처리 mistakes(status: open 또는 status 없음)가 있고 마지막 audit 이
#            mistake_loop.audit_cadence_days(기본 7) 보다 오래됐으면 알려요.
#            마지막 audit: .ax/mistakes/.last-audit(epoch) → 없으면 state.json .cross_cut.mistakes.last_audit
#            미처리 중 같은 category 가 2건 이상이면 주기와 상관없이 "재발" 을 알려요 (audit.recurring).
#
# 왜: 실측(commerce, 2026-09-25) — 설치본 0.5.13 이 플러그인 0.6.3 에 두 달 넘게 머물러 0.6.0 의 룰 집행이
#     안 닿았고, mistakes 는 22건 쌓였는데 audit 은 2026-05-09 뒤로 한 번도 안 돌았어요. HUD 한 칸은 안 보여요.
#     SessionStart 훅(session-start/session-brief.sh)이 이 스크립트의 lines 를 그대로 컨텍스트에 넣어요.
#
# compaction 스냅샷 (PreCompact 훅 → SessionStart source=compact 훅):
#   --snapshot --session <sid>       압축 직전 **사실**을 .ax/.session/<sid>/precompact.txt 에 적어요 — 브랜치·HEAD ·
#                                    작업 트리의 바뀐 파일(최대 10) · 진행 중 spec 과 tasks 진행률. LLM 요약이 아니에요.
#                                    요약은 Claude Code 가 하고, 요약이 흘린 "어디까지 했나" 를 파일이 붙잡아요.
#   --after-compact --session <sid>  브리핑 맨 앞에 그 스냅샷을 붙여요 (파일은 읽고 지워요 — 한 번만 말해요).
#
# Usage:
#   bash session-brief.sh            # 사람용 텍스트 (lines 만)
#   bash session-brief.sh --json     # 기계용
#   --max-chars N                    # lines 합계 상한 (기본 GOAX_SESSION_BRIEF_MAX 또는 1200) — 넘으면 뒤를 잘라요
#
# Output (--json):
#   {"status":"ok","result":{"lines":[…],"version":{"installed":"0.5.13","plugin":"0.6.3","behind":true},
#     "audit":{"unresolved":13,"last_audit":"2026-05-09T…Z"|null,"days_since":139|null,"cadence":7,"overdue":true},
#     "task":{"task_id":…,"description":…,"phase":…}|null,
#     "handoff":{"now":[…],"now_at":…,"next":[…],"open":[…]}},…}
# Exit: 0 ok · 1 error · 2 skipped (jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false
MAX_CHARS="${GOAX_SESSION_BRIEF_MAX:-1200}"
MODE=brief; SESSION=""
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi
    case "$1" in
        --max-chars) MAX_CHARS="${2:-}"; shift 2 ;;
        --snapshot) MODE=snapshot; shift ;;
        --after-compact) MODE=after-compact; shift ;;
        --session) SESSION="${2:-}"; shift 2 ;;
        *) goax_error "알 수 없는 옵션: $1"; exit "$EXIT_ERROR" ;;
    esac
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
case "$MAX_CHARS" in ''|*[!0-9]*) MAX_CHARS=1200 ;; esac

command -v jq >/dev/null 2>&1 || { [ "$JSON_MODE" = true ] && json_skip "jq 없음"; exit "$EXIT_SKIPPED"; }
ROOT=$(find_project_root) || exit "$EXIT_ERROR"
if [ "$MODE" != brief ] && [ -z "$SESSION" ]; then
    [ "$JSON_MODE" = true ] && json_error "--snapshot · --after-compact 는 --session <sid> 가 필요해요"
    goax_error "--session <sid> 가 필요해요"; exit "$EXIT_ERROR"
fi

# ── compaction 스냅샷 쓰기 ──────────────────────────────────────────
if [ "$MODE" = snapshot ]; then
    SNAP=()
    if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        BR=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        HD=$(git -C "$ROOT" log -1 --format='%h %s' 2>/dev/null | cut -c1-100 || true)
        [ -n "$BR" ] && SNAP+=("브랜치 $BR · HEAD $HD")
        CH=$(git -C "$ROOT" status --porcelain --untracked-files=all -- . 2>/dev/null | grep -v ' \.ax/' || true)
        CHN=$(printf '%s' "$CH" | grep -c . || true)
        if [ "${CHN:-0}" -gt 0 ]; then
            FILES=$(printf '%s\n' "$CH" | head -10 | awk '{ $1=""; sub(/^ /, ""); print }' | paste -sd ',' - | sed 's/,/, /g')
            MORE=""; [ "$CHN" -gt 10 ] && MORE=" 외 $((CHN - 10))개"
            SNAP+=("커밋 안 된 변경 ${CHN}개: ${FILES}${MORE}")
        fi
    fi
    TF="$ROOT/.ax/current-task.json"
    if [ -f "$TF" ] && jq -e . "$TF" >/dev/null 2>&1; then
        SD=$(jq -r 'if (.phase // "idle") != "idle" then (.spec_dir // empty) else empty end' "$TF" 2>/dev/null || true)
        if [ -n "$SD" ] && [ -f "$ROOT/$SD/tasks.md" ]; then
            PROG=$(awk '/^[[:space:]]*```/{f=!f; next} f{next}
                        /^[[:space:]]*- \[[xX]\]/{d++} /^[[:space:]]*- \[ \]/{o++; if (!first) first=$0}
                        END{ sub(/^[[:space:]]*- \[ \][[:space:]]*/, "", first); printf "%d/%d\t%s", d, d+o, substr(first,1,90) }' "$ROOT/$SD/tasks.md")
            SNAP+=("spec $SD — tasks ${PROG%%$'\t'*} · 다음: ${PROG#*$'\t'}")
        elif [ -n "$SD" ]; then
            SNAP+=("spec $SD (tasks.md 없음)")
        fi
    fi
    SD_DIR=$(goax_session_dir "$SESSION")
    OUTF="$SD_DIR/precompact.txt"
    if [ "$DRY_RUN" != true ] && [ "${#SNAP[@]}" -gt 0 ]; then
        mkdir -p "$SD_DIR" && printf '%s\n' "${SNAP[@]}" > "$OUTF"
    fi
    if [ "$JSON_MODE" = true ]; then
        SL=$(printf '%s\n' ${SNAP[@]+"${SNAP[@]}"} | jq -R . | jq -sc 'map(select(. != ""))')
        json_output ok "$(jq -nc --argjson l "$SL" --arg p "${OUTF#"$ROOT"/}" --argjson w "$( [ "$DRY_RUN" != true ] && [ "${#SNAP[@]}" -gt 0 ] && echo true || echo false)" '{lines:$l, path:$p, written:$w}')" ""
    else
        printf '%s\n' ${SNAP[@]+"${SNAP[@]}"}
    fi
    exit "$EXIT_OK"
fi

LINES=()
# ── compaction 직후 — 직전 스냅샷을 맨 앞에 ──────────────────────────
if [ "$MODE" = after-compact ]; then
    PF="$(goax_session_dir "$SESSION")/precompact.txt"
    if [ -f "$PF" ]; then
        while IFS= read -r l; do [ -n "$l" ] && LINES+=("압축 직전: $l"); done < "$PF"
        [ "$DRY_RUN" = true ] || rm -f "$PF"
    fi
fi

# ── 진행 중 task · handoff ─────────────────────────────────────────
TASK_FILE="$ROOT/.ax/current-task.json"
TASK_JSON="null"; HANDOFF_JSON='{"now":[],"now_at":null,"next":[],"open":[]}'
if [ -f "$TASK_FILE" ] && jq -e . "$TASK_FILE" >/dev/null 2>&1; then
    TASK_JSON=$(jq -c 'if (.phase // "idle") != "idle" then {task_id, description, phase} else null end' "$TASK_FILE")
    HANDOFF_JSON=$(jq -c '(.handoff // {}) | {now: (.now // [])[:3], now_at: (.now_at // null),
                                             next: (.next // [])[:3], open: (.open // [])[:3]}' "$TASK_FILE")
    if [ "$TASK_JSON" != "null" ]; then
        LINES+=("진행 중: $(jq -r '"\(.task_id // "-") \(.description // "") (phase: \(.phase))"' <<<"$TASK_JSON")")
    fi
    while IFS= read -r l; do [ -n "$l" ] && LINES+=("$l"); done < <(jq -r '
        (if (.now | length) > 0 then "지금: " + (.now | join(" · ")) + (if .now_at then " (" + .now_at + ")" else "" end) else empty end),
        (if (.next | length) > 0 then "다음: " + (.next | join(" · ")) else empty end),
        (if (.open | length) > 0 then "열린 질문: " + (.open | join(" · ")) else empty end)
    ' <<<"$HANDOFF_JSON")
fi

# ── 버전 ──────────────────────────────────────────────────────────
INSTALLED=""
if [ -f "$ROOT/.ax/version" ]; then
    INSTALLED=$(grep -E '^goax:' "$ROOT/.ax/version" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '[:space:]' || true)
fi
PLUGIN=""
IP="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
if [ -f "$IP" ]; then
    PLUGIN=$(jq -r '[(.plugins // {}) | to_entries[] | select(.key | startswith("goax@")) | .value[]? | .version // empty]
                    | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))) | sort_by(split(".") | map(tonumber)) | last // empty' \
             "$IP" 2>/dev/null || true)
fi
if [ -z "$PLUGIN" ] && [ -f "$ROOT/.ax/state.json" ]; then
    PLUGIN=$(jq -r '.hud.plugin_version // empty' "$ROOT/.ax/state.json" 2>/dev/null || true)
fi
BEHIND=false
if [ -n "$INSTALLED" ] && [ -n "$PLUGIN" ] && [ "$INSTALLED" != "$PLUGIN" ]; then
    NEWEST=$(printf '%s\n%s\n' "$INSTALLED" "$PLUGIN" | sort -V | tail -1)
    [ "$NEWEST" = "$PLUGIN" ] && BEHIND=true
fi
[ "$BEHIND" = true ] && LINES+=("goax 설치본 $INSTALLED · 플러그인 $PLUGIN — \`/up\` 으로 올리세요 (새 룰 집행·훅이 이 프로젝트엔 아직 없어요)")

# ── audit ─────────────────────────────────────────────────────────
UNRESOLVED=0; CATS=""
if [ -d "$ROOT/.ax/mistakes" ]; then
    for f in "$ROOT"/.ax/mistakes/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in README.md) continue ;; esac
        st=$(goax_frontmatter_scalar "$f" status 2>/dev/null || true)
        case "$st" in ''|open)
            UNRESOLVED=$((UNRESOLVED + 1))
            cat_=$(goax_frontmatter_scalar "$f" category 2>/dev/null || true)
            [ -n "$cat_" ] && CATS="${CATS}${cat_}"$'\n' ;;
        esac
    done
fi
CADENCE=$(grep -E '^[[:space:]]*audit_cadence_days:' "$ROOT/.ax/config.yml" 2>/dev/null | head -1 \
          | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*#.*$//' || true)
case "$CADENCE" in ''|*[!0-9]*) CADENCE=7 ;; esac
LAST_EPOCH=""
if [ -f "$ROOT/.ax/mistakes/.last-audit" ]; then
    LAST_EPOCH=$(tr -d '[:space:]' < "$ROOT/.ax/mistakes/.last-audit" 2>/dev/null || true)
elif [ -f "$ROOT/.ax/state.json" ]; then
    LA=$(jq -r '.cross_cut.mistakes.last_audit // empty' "$ROOT/.ax/state.json" 2>/dev/null || true)
    if [ -n "$LA" ]; then
        # 옛 audit 는 날짜만(2026-05-09), update-state.sh 는 ISO 시각을 적어요 — 둘 다 받아요
        LAST_EPOCH=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$LA" +%s 2>/dev/null \
                     || date -u -j -f '%Y-%m-%d %H:%M:%S' "${LA%%T*} 00:00:00" +%s 2>/dev/null \
                     || date -u -d "$LA" +%s 2>/dev/null || true)
    fi
fi
case "$LAST_EPOCH" in *[!0-9]*) LAST_EPOCH="" ;; esac
LAST_ISO="null"; DAYS="null"; OVERDUE=false
if [ -n "$LAST_EPOCH" ]; then
    LAST_ISO=$(date -u -r "$LAST_EPOCH" +%Y-%m-%d 2>/dev/null || date -u -d "@$LAST_EPOCH" +%Y-%m-%d 2>/dev/null || echo "")
    DAYS=$(( ($(date +%s) - LAST_EPOCH) / 86400 ))
    [ "$UNRESOLVED" -gt 0 ] && [ "$DAYS" -gt "$CADENCE" ] && OVERDUE=true
    [ -n "$LAST_ISO" ] && LAST_ISO="\"$LAST_ISO\"" || LAST_ISO="null"
elif [ "$UNRESOLVED" -gt 0 ]; then
    OVERDUE=true
fi
if [ "$OVERDUE" = true ]; then
    if [ "$DAYS" = "null" ]; then
        LINES+=("미처리 mistakes ${UNRESOLVED}건 · audit 기록 없음 — \`audit\` 으로 재발 패턴과 룰 승격 후보를 보세요")
    else
        LINES+=("미처리 mistakes ${UNRESOLVED}건 · 마지막 audit ${DAYS}일 전 (주기 ${CADENCE}일) — \`audit\` 으로 재발 패턴과 룰 승격 후보를 보세요")
    fi
fi

# 재발 — 미처리 mistakes 중 같은 category 가 2건 이상이면 audit 주기와 상관없이 알려요.
#   주기는 "밀렸나" 를 보고, 이건 "같은 실수를 또 하고 있나" 를 봐요 (룰 승격 후보).
RECUR=$(printf '%s' "$CATS" | grep -v '^$' | sort | uniq -c | sort -rn | awk '$1 >= 2 {printf "%s%s ×%d", (n++ ? " · " : ""), $2, $1}' || true)
[ -n "$RECUR" ] && LINES+=("같은 종류 실수 재발: ${RECUR} — \`audit\` 으로 룰 승격을 검토하세요")

# ── 상한 — 세션 첫머리에 들어가는 글이라 짧게 ─────────────────────────
OUT=(); TOTAL=0; CUT=false
for l in ${LINES[@]+"${LINES[@]}"}; do
    n=${#l}
    if [ $((TOTAL + n)) -gt "$MAX_CHARS" ]; then CUT=true; break; fi
    OUT+=("$l"); TOTAL=$((TOTAL + n))
done
[ "$CUT" = true ] && OUT+=("… (상한 ${MAX_CHARS}자 — 나머지는 \`status-note.sh --show\` · doctor)")

if [ "$JSON_MODE" = true ]; then
    LINES_JSON=$(printf '%s\n' ${OUT[@]+"${OUT[@]}"} | jq -R . | jq -sc 'map(select(. != ""))')
    RESULT=$(jq -nc --argjson lines "$LINES_JSON" \
        --arg inst "$INSTALLED" --arg plug "$PLUGIN" --argjson behind "$BEHIND" \
        --argjson unres "$UNRESOLVED" --argjson last "$LAST_ISO" --argjson days "$DAYS" \
        --argjson cad "$CADENCE" --argjson over "$OVERDUE" --arg rec "$RECUR" \
        --argjson task "$TASK_JSON" --argjson handoff "$HANDOFF_JSON" \
        '{lines: $lines,
          version: {installed: (if $inst == "" then null else $inst end), plugin: (if $plug == "" then null else $plug end), behind: $behind},
          audit: {unresolved: $unres, last_audit: $last, days_since: $days, cadence: $cad, overdue: $over, recurring: $rec},
          task: $task, handoff: $handoff}')
    json_output ok "$RESULT" ""
else
    printf '%s\n' ${OUT[@]+"${OUT[@]}"}
fi
exit "$EXIT_OK"
