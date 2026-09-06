#!/usr/bin/env bash
# .ax/scripts/bash/constitution-apply.sh — onboarding Q5 의 Constitution 시그널 블록 적용 (prepend · 중복 스캔 · 4계층 인덱스)
#
# Usage:
#   bash constitution-apply.sh --block <file> [--target AGENTS.md|CLAUDE.md] [--dry-run] [--json]
#       블록 파일을 대상 상단에 prepend 하고 기존 본문은 `---` 아래 그대로 보존해요.
#       블록의 **룰 토큰**(`AX:MANDATORY:002` · `SP-OPS-001`)이 대상에 전부 있을 때만 적용된 걸로
#       보고 skip (exit 2). 토큰이 없는 블록은 룰 라인, 그것도 없으면 첫 `## ` 헤더로. 덮어쓰려면 --force
#   bash constitution-apply.sh --scan-duplicates --block <file> [--target …] [--json]
#       블록의 룰 라인 ↔ 기존 본문의 정확 일치(normalize 뒤 구 줄 ⊆ 신 룰 줄) 목록만 — 지우지 않아요
#   bash constitution-apply.sh --drop-exact --block <file> [--target …] [--dry-run] [--json]
#       정확 일치 줄만 기존 본문에서 제거 — 사용자가 중복 박스에서 [a] 를 고른 *뒤에만* 부르세요
#   bash constitution-apply.sh --append-index [--target …] [--plugin-dir <dir>] [--dry-run] [--json]
#       `## 4계층 인덱스` 절이 없으면 .ax/AGENTS.md.suggested → plugin 템플릿 순으로 찾아 끝에 append
#
# 왜 스크립트인가 — prepend·구분선·인덱스 append 는 매번 같은 절차인데 SKILL.md 산문으로 시키면 세션마다
# 조금씩 다르게 했어요. 판단(어떤 룰을 어느 시그널로) 은 skill, 파일 조작은 여기예요.
# 대상 기본값: AGENTS.md 가 있으면 AGENTS.md (SSOT), 없으면 CLAUDE.md. 백업은 git 이 해요.
#
# Output (--json): {"status":"ok|skipped","result":{"target":"AGENTS.md","mode":"prepend|scan|drop|index",
#   "applied":bool,"duplicates":[{"rule":"…","old_line":N,"old_text":"…"}],"dropped":N,"index_source":"…"},…}
# Exit: 0 ok · 1 error · 2 skipped (이미 적용 · 인덱스 이미 있음 · 원본 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false; FORCE=false
MODE="prepend"; BLOCK=""; TARGET=""; PLUGIN_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json)            JSON_MODE=true ;;
        --dry-run)         DRY_RUN=true ;;
        --force)           FORCE=true ;;
        --block)           shift; BLOCK="${1:-}" ;;
        --target)          shift; TARGET="${1:-}" ;;
        --plugin-dir)      shift; PLUGIN_DIR="${1:-}" ;;
        --scan-duplicates) MODE="scan" ;;
        --drop-exact)      MODE="drop" ;;
        --append-index)    MODE="index" ;;
        --help|-h)         SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'   # 2..'# Exit:' 줄까지
    exit "$EXIT_OK"
fi
fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }
skip() { if [ "$JSON_MODE" = true ]; then json_skip "$1"; fi; goax_warn "$1"; exit "$EXIT_SKIPPED"; }

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT" || exit "$EXIT_ERROR"
if [ -z "$TARGET" ]; then
    if [ -f AGENTS.md ]; then TARGET="AGENTS.md"; elif [ -f CLAUDE.md ]; then TARGET="CLAUDE.md"; else TARGET="AGENTS.md"; fi
fi
if [ "$MODE" != "index" ]; then
    [ -n "$BLOCK" ] && [ -f "$BLOCK" ] || fail "--block <file> 이 필요해요 (시그널 블록 파일)"
fi

# 정규화 — 소문자 · 마크다운 장식 제거 · 공백 축약
norm() { sed -E 's/[*`_>#]+//g; s/^[[:space:]]*[-•·][[:space:]]*//; s/[[:space:]]+/ /g; s/^ //; s/ $//' | tr '[:upper:]' '[:lower:]'; }

# 블록의 룰 라인 (시그널 라인만)
rule_lines() { grep -E '^(🔴|🟡|🔵) \*\*`' "$BLOCK" 2>/dev/null || true; }

# 중복 스캔 → "rule<TAB>old_line<TAB>old_text"
# 비교 대상은 *구 본문* 만 — 블록이 이미 prepend 돼 있으면 첫 `---` 아래만 봐요 (블록 자기 자신과의 일치는 중복이 아니에요).
# 일치 기준: 룰의 핵심 문장(토큰 뒤)을 normalize 해서, 구 줄 ⊆ 핵심 또는 핵심 ⊆ 구 줄. 둘 다 12자 이상.
scan_dups() {
    [ -f "$TARGET" ] || return 0
    local rl core cn ln n t tn sep=0 first
    first=$(grep -m1 -E '^## ' "$BLOCK" || true)
    if [ -n "$first" ] && grep -qxF -- "$first" "$TARGET"; then
        sep=$(grep -n -m1 -E '^---[[:space:]]*$' "$TARGET" | cut -d: -f1 || true); sep=${sep:-0}
    fi
    while IFS= read -r rl; do
        [ -z "$rl" ] && continue
        core=$(printf '%s' "$rl" | sed -E 's/^[^`]*`[^`]+`\*\*[[:space:]]*//; s/^[—–-][[:space:]]*//')
        cn=$(printf '%s' "$core" | norm)
        [ "${#cn}" -ge 12 ] || continue
        while IFS= read -r ln; do
            [ -z "$ln" ] && continue
            n=${ln%%:*}; t=${ln#*:}
            [ "$n" -gt "$sep" ] || continue
            case "$t" in '#'*|'---'*|'') continue ;; esac
            tn=$(printf '%s' "$t" | norm)
            [ "${#tn}" -ge 12 ] || continue
            case "$cn" in *"$tn"*) printf '%s\t%s\t%s\n' "$rl" "$n" "$t"; continue ;; esac
            case "$tn" in *"$cn"*) printf '%s\t%s\t%s\n' "$rl" "$n" "$t" ;; esac
        done < <(grep -n '' "$TARGET")
    done < <(rule_lines)
}

case "$MODE" in
  prepend)
    # "이미 적용됨" 판정 — 예전엔 블록의 첫 `## ` 헤더 **텍스트 하나**만 봤어요.
    # `## META — 핵심 가드레일` 처럼 대상에 흔히 있는 제목이면 룰이 하나도 안 들어갔는데도
    # skip 으로 나가서, onboarding Q5 로 정한 룰이 조용히 사라졌어요.
    # 그래서 블록이 실어나르는 **룰 토큰**(AX:MANDATORY:002 · SP-OPS-001)이 대상에
    # **전부** 있을 때만 skip 해요. 토큰이 없는 블록은 룰 라인 자체로, 그것도 없으면 헤더로.
    FIRST_H2=$(grep -m1 -E '^## ' "$BLOCK" || true)
    if [ -f "$TARGET" ] && [ "$FORCE" = false ]; then
        TOKENS=$(LC_ALL=C grep -oE '([[:upper:]][[:upper:]]*:[[:upper:]][[:upper:]]*:[0-9][0-9][0-9]|SP-[[:upper:]][[:upper:]]*-[0-9][0-9][0-9])' "$BLOCK" | sort -u || true)
        PROBES=0; MISSING=0
        if [ -n "$TOKENS" ]; then
            for tok in $TOKENS; do       # 토큰엔 공백이 없어요 — 단어 분리로 충분
                PROBES=$((PROBES + 1))
                grep -qF -- "$tok" "$TARGET" || MISSING=$((MISSING + 1))
            done
        else
            while IFS= read -r rl; do
                [ -z "$rl" ] && continue
                PROBES=$((PROBES + 1))
                grep -qxF -- "$rl" "$TARGET" || MISSING=$((MISSING + 1))
            done < <(rule_lines)
        fi
        if [ "$PROBES" -gt 0 ] && [ "$MISSING" -eq 0 ]; then
            skip "$TARGET 에 이 블록의 룰 ${PROBES}개가 전부 있어요 — 적용된 것으로 봐요 (--force 로 덮어쓰기)"
        fi
        # 룰이 한 줄도 없는 블록(헤더·산문만) 은 예전처럼 첫 헤더로 판정해요
        if [ "$PROBES" -eq 0 ] && [ -n "$FIRST_H2" ] && grep -qxF -- "$FIRST_H2" "$TARGET"; then
            skip "$TARGET 에 이미 '$FIRST_H2' 가 있어요 — 적용된 것으로 봐요 (--force 로 덮어쓰기)"
        fi
    fi
    OLD_LINES=0; [ -f "$TARGET" ] && OLD_LINES=$(wc -l < "$TARGET" | tr -d ' ')
    NEW_LINES=$(wc -l < "$BLOCK" | tr -d ' ')
    if [ "$DRY_RUN" = true ]; then
        RES=$(jq -nc --arg t "$TARGET" --arg b "$BLOCK" --arg o "$OLD_LINES" --arg n "$NEW_LINES" \
            '{target:$t,mode:"prepend",applied:false,dry_run:true,block:$b,block_lines:($n|tonumber),existing_lines:($o|tonumber)}')
        [ "$JSON_MODE" = true ] && json_output "ok" "$RES" "dry-run — ${TARGET} 상단에 ${NEW_LINES}줄 prepend 예정, 기존 ${OLD_LINES}줄은 --- 아래 보존" \
            || goax_log "dry-run — ${TARGET} 상단에 ${NEW_LINES}줄 prepend 예정 (기존 ${OLD_LINES}줄 보존)"
        exit "$EXIT_OK"
    fi
    TMP="$TARGET.tmp.$$"
    { cat "$BLOCK"; printf '\n'
      if [ -f "$TARGET" ] && [ "$OLD_LINES" -gt 0 ]; then printf -- '---\n\n'; cat "$TARGET"; fi
    } > "$TMP" && mv "$TMP" "$TARGET"
    RES=$(jq -nc --arg t "$TARGET" --arg o "$OLD_LINES" --arg n "$NEW_LINES" \
        '{target:$t,mode:"prepend",applied:true,block_lines:($n|tonumber),preserved_lines:($o|tonumber)}')
    [ "$JSON_MODE" = true ] && json_output "ok" "$RES" "prepend 완료 — 다음은 --scan-duplicates 로 중복 룰을 사용자에게 보여주세요" \
        || goax_log "${TARGET} 에 ${NEW_LINES}줄 prepend (기존 ${OLD_LINES}줄 --- 아래 보존)"
    ;;
  scan|drop)
    [ -f "$TARGET" ] || fail "$TARGET 이 없어요"
    DUPS=$(scan_dups)
    DN=$(printf '%s' "$DUPS" | grep -c . || true); DN=${DN:-0}
    # 중복 0건이 가장 흔한 경우인데, 예전엔 여기서 죽었어요 — 빈 입력의 `grep -v` 는 exit 1 이고
    # pipefail × set -e 가 그걸 그대로 받아서 json_error 도 못 찍고 stdout·stderr 둘 다 빈 채 exit 1.
    # --json 계약(항상 envelope 한 줄)이 가장 흔한 경로에서 깨져 있었어요.
    DJ='[]'
    if [ "$DN" -gt 0 ]; then
        DJ=$(printf '%s\n' "$DUPS" | grep -v '^$' | jq -Rc 'split("\t") | {rule:.[0],old_line:(.[1]|tonumber),old_text:.[2]}' | jq -sc .)
    fi
    if [ "$MODE" = "scan" ]; then
        RES=$(jq -nc --arg t "$TARGET" --argjson d "$DJ" '{target:$t,mode:"scan",duplicates:$d,count:($d|length)}')
        if [ "$JSON_MODE" = true ]; then
            [ "$DN" -gt 0 ] && json_output "warning" "$RES" "정확 일치 ${DN}건 — 박스로 보여주고 사용자가 [a] 를 고르면 --drop-exact" \
                || json_output "ok" "$RES" "중복 없음"
        else
            printf '🔍 중복 스캔 — %s건\n' "$DN"
            printf '%s' "$DUPS" | awk -F'\t' 'NF{printf "  %s\n    ↔ line %s: %s\n", $1, $2, $3}'
        fi
        exit "$EXIT_OK"
    fi
    # drop — 신 블록 아래 `---` 이후 구 본문에서만 지워요 (블록 자체는 안 건드려요)
    if [ "$DN" -eq 0 ]; then
        [ "$JSON_MODE" = true ] && json_output "ok" '{"target":"'"$TARGET"'","mode":"drop","dropped":0}' "지울 중복 없음" || goax_log "지울 중복 없음"
        exit "$EXIT_OK"
    fi
    if [ "$DRY_RUN" = true ]; then
        RES=$(jq -nc --arg t "$TARGET" --argjson d "$DJ" '{target:$t,mode:"drop",dropped:0,dry_run:true,would_drop:$d}')
        [ "$JSON_MODE" = true ] && json_output "ok" "$RES" "dry-run — ${DN}줄 삭제 예정" || goax_log "dry-run — ${DN}줄 삭제 예정"
        exit "$EXIT_OK"
    fi
    SEP=$(grep -n -m1 -E '^---[[:space:]]*$' "$TARGET" | cut -d: -f1 || true); SEP=${SEP:-0}
    LINES_TO_DROP=$(printf '%s' "$DUPS" | awk -F'\t' -v sep="$SEP" 'NF && $2 > sep {print $2}' | sort -un)
    DROPPED=$(printf '%s' "$LINES_TO_DROP" | grep -c . || true)
    TMP="$TARGET.tmp.$$"
    awk -v drops="$(printf '%s' "$LINES_TO_DROP" | tr '\n' ',')" '
        BEGIN { n = split(drops, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") d[a[i]] = 1 }
        !(NR in d) { print }' "$TARGET" > "$TMP" && mv "$TMP" "$TARGET"
    RES=$(jq -nc --arg t "$TARGET" --arg n "$DROPPED" '{target:$t,mode:"drop",dropped:($n|tonumber)}')
    [ "$JSON_MODE" = true ] && json_output "ok" "$RES" "정확 일치 ${DROPPED}줄 제거 — 부분 일치는 사용자가 직접" || goax_log "${DROPPED}줄 제거"
    ;;
  index)
    [ -f "$TARGET" ] || fail "$TARGET 이 없어요"
    if grep -qE '^## 4계층 인덱스' "$TARGET"; then skip "$TARGET 에 4계층 인덱스가 이미 있어요"; fi
    SRC=""
    [ -f .ax/AGENTS.md.suggested ] && grep -qE '^## 4계층 인덱스' .ax/AGENTS.md.suggested && SRC=".ax/AGENTS.md.suggested"
    if [ -z "$SRC" ]; then
        if [ -z "$PLUGIN_DIR" ]; then
            if [ -n "${CLAUDE_SKILL_DIR:-}" ] && [ -d "${CLAUDE_SKILL_DIR}/../../templates" ]; then PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
            elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then PLUGIN_DIR="$CLAUDE_PLUGIN_ROOT"; fi
        fi
        [ -n "$PLUGIN_DIR" ] && [ -f "$PLUGIN_DIR/templates/default/AGENTS.md.template" ] && SRC="$PLUGIN_DIR/templates/default/AGENTS.md.template"
    fi
    [ -n "$SRC" ] || skip "4계층 인덱스 원본을 못 찾았어요 (.ax/AGENTS.md.suggested 없음 · plugin 경로 미도출 — --plugin-dir)"
    INDEX=$(awk '/^## 4계층 인덱스/{p=1} p && /^## / && !/^## 4계층 인덱스/{exit} p{print}' "$SRC" \
            | awk '{ l[NR]=$0 } END { last=NR; while (last>0 && (l[last] ~ /^[[:space:]]*$/ || l[last] ~ /^---[[:space:]]*$/)) last--; for (i=1;i<=last;i++) print l[i] }')   # 끝의 빈 줄·구분선 제거
    IL=$(printf '%s\n' "$INDEX" | grep -c . || true)
    if [ "$DRY_RUN" = true ]; then
        RES=$(jq -nc --arg t "$TARGET" --arg s "$SRC" --arg n "$IL" '{target:$t,mode:"index",applied:false,dry_run:true,index_source:$s,index_lines:($n|tonumber)}')
        [ "$JSON_MODE" = true ] && json_output "ok" "$RES" "dry-run — ${IL}줄 append 예정 (원본 ${SRC})" || goax_log "dry-run — ${IL}줄 append 예정 (원본 ${SRC})"
        exit "$EXIT_OK"
    fi
    { printf '\n'; printf '%s\n' "$INDEX"; } >> "$TARGET"
    RES=$(jq -nc --arg t "$TARGET" --arg s "$SRC" --arg n "$IL" '{target:$t,mode:"index",applied:true,index_source:$s,index_lines:($n|tonumber)}')
    [ "$JSON_MODE" = true ] && json_output "ok" "$RES" "4계층 인덱스 append (원본 ${SRC})" || goax_log "4계층 인덱스 ${IL}줄 append (원본 ${SRC})"
    ;;
esac
exit "$EXIT_OK"
