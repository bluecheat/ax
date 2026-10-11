#!/usr/bin/env bash
# .ax/scripts/bash/config-merge.sh — 템플릿에만 있는 config.yml 키를 프로젝트 config.yml 에 더해요
#
# Usage: bash config-merge.sh --template <템플릿 config.yml> [--json] [--dry-run]
#
# 왜: 새 버전이 config.yml 에 키를 더해도, 이미 설치된 프로젝트는 그 키를 받을 길이 없었어요.
#   `/up` 은 사용자 config.yml 을 덮지 않고 `.suggested` 만 남기고, config-set.sh 는 없는 키를 만들지 않아요.
#   키가 없으면 스크립트는 기본값으로 돌지만, 팀은 그 설정이 있는지 몰라서 바꿀 수 없어요.
# 하는 일:
#   - 템플릿의 최상위 키가 프로젝트에 없으면, 그 블록(바로 위 주석 포함)을 파일 끝에 더해요.
#   - 템플릿 섹션 아래 키(들여쓰기 2칸)가 프로젝트의 같은 섹션에 없으면, 그 키 블록(바로 위 주석 포함)을 섹션 끝에 더해요.
#   - 이미 있는 키의 값은 건드리지 않아요. 주석 처리된 예시 키는 키로 세지 않아요.
#   - domain_risk 아래 키는 프로젝트 데이터라 더하지 않아요.
# 쓰기는 config-set.sh 와 같은 락(<config.yml>.lock) 안에서 해요. 백업 파일은 만들지 않아요.
#
# Output (--json):
#   {"status":"ok","result":{"path":".ax/config.yml","added":["ade_root","sensors.foreign_executors"],"dry_run":false},…}
# Exit: 0 ok · 1 error (config.yml 없음 · 템플릿 없음 · 락 실패)
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; TEMPLATE=""
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi
    case "$1" in
        --template) shift; TEMPLATE="${1:-}" ;;
        *) goax_error "알 수 없는 옵션: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

ROOT=$(find_project_root) || exit "$EXIT_ERROR"
CFG="$ROOT/.ax/config.yml"
[ -f "$CFG" ] || fail ".ax/config.yml 이 없어요 — /up 먼저"
[ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ] || fail "--template <템플릿 config.yml> 가 필요해요"

# 키 목록 — "top" 또는 "top.sub". 주석·빈 줄은 키가 아니에요
keys_of() {
    awk '
        /^[^[:space:]#][^:]*:/ { t = $0; sub(/:.*/, "", t); print t; next }
        /^  [^[:space:]#-][^:]*:/ && t != "" { s = $0; sub(/^  /, "", s); sub(/:.*/, "", s); print t "." s }
    ' "$1"
}
# 템플릿 블록 하나 — 바로 위 주석(빈 줄 없이 붙은 것) + 키 줄 + 더 깊이 들여쓴 줄
#   block <file> <top> [sub]
block_of() {
    awk -v top="$2" -v sub_="${3:-}" '
        function flush_comments() { n = 0 }
        {
            line = $0
            if (line ~ /^[^[:space:]#][^:]*:/) {
                k = line; sub(/:.*/, "", k); cur = k
                if (on) exit
                if (sub_ == "" && k == top) { for (i = 1; i <= n; i++) print c[i]; print line; on = 1; deep = 0; n = 0; next }
                n = 0; next
            }
            if (line ~ /^#/) { if (on && sub_ == "") exit; c[++n] = line; next }
            if (line ~ /^[[:space:]]*$/) { if (on) exit; n = 0; next }
            if (cur != top) { n = 0; next }
            if (sub_ == "") { if (on) print line; next }
            # 섹션 안 — 2칸 들여쓴 키 또는 주석
            if (line ~ /^  [^[:space:]#-][^:]*:/) {
                k = line; sub(/^  /, "", k); sub(/:.*/, "", k)
                if (on) exit
                if (k == sub_) { for (i = 1; i <= n; i++) print c[i]; print line; on = 1; next }
                n = 0; next
            }
            if (line ~ /^  #/) { if (on) exit; c[++n] = line; next }
            if (on && line ~ /^   /) { print line; next }
            if (on) exit
            n = 0
        }
    ' "$1"
}

PROJ_KEYS=$(keys_of "$CFG")
TPL_KEYS=$(keys_of "$TEMPLATE")
MISSING=$(printf '%s\n' "$TPL_KEYS" | while IFS= read -r k; do
    [ -n "$k" ] || continue
    case "$k" in (domain_risk.*) continue ;; esac
    printf '%s\n' "$PROJ_KEYS" | grep -qxF -- "$k" && continue
    # 섹션째 없으면 섹션 블록만 더해요 (그 아래 키는 섹션에 같이 들어 있어요)
    case "$k" in (*.*) printf '%s\n' "$PROJ_KEYS" | grep -qxF -- "${k%%.*}" || continue ;; esac
    printf '%s\n' "$k"
done)

LOCK=""
if [ "$DRY_RUN" != true ] && [ -n "$MISSING" ]; then
    LOCK="$CFG.lock"   # config-set.sh · zero-domain-risk.sh 와 같은 문자열 — 락 단위는 파일
    goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "락을 못 잡았어요: $LOCK"
    trap '[ -n "$LOCK" ] && goax_unlock "$LOCK"' EXIT
    TMP=$(goax_mktemp "$ROOT") || { goax_tmp_error; exit "$EXIT_ERROR"; }
    cp "$CFG" "$TMP"
    while IFS= read -r k; do
        [ -n "$k" ] || continue
        case "$k" in
            *.*)
                top="${k%%.*}"; sub="${k#*.}"
                BLK=$(block_of "$TEMPLATE" "$top" "$sub")
                [ -n "$BLK" ] || continue
                # 섹션 끝 = 섹션 키 다음, 0칸에서 시작하는 첫 줄 앞의 마지막 비어 있지 않은 줄
                GOAX_BLK="$BLK" awk -v top="$top" '
                    { L[NR] = $0 }
                    END {
                        for (i = 1; i <= NR; i++) {
                            k = L[i]; if (k !~ /^[^[:space:]#][^:]*:/) continue
                            sub(/:.*/, "", k); if (k != top) continue
                            last = i
                            for (j = i + 1; j <= NR; j++) {
                                if (L[j] ~ /^[^[:space:]]/) break
                                if (L[j] !~ /^[[:space:]]*$/) last = j
                            }
                            break
                        }
                        for (i = 1; i <= NR; i++) { print L[i]; if (i == last) print ENVIRON["GOAX_BLK"] }
                    }' "$TMP" > "$TMP.n" && mv "$TMP.n" "$TMP"
                ;;
            *)
                BLK=$(block_of "$TEMPLATE" "$k")
                [ -n "$BLK" ] || continue
                printf '\n%s\n' "$BLK" >> "$TMP"
                ;;
        esac
    done <<< "$MISSING"
    cat "$TMP" > "$CFG"; rm -f "$TMP"
    goax_unlock "$LOCK"; LOCK=""
fi

ADDED=$(printf '%s\n' "$MISSING" | jq -Rn '[inputs | select(length > 0)]')
N=$(printf '%s' "$ADDED" | jq 'length')
NEXT=""; [ "$N" -gt 0 ] && NEXT="config.yml 에 새 키 ${N}개를 기본값으로 더했어요. 값이 맞는지 보고 필요하면 config-set.sh 로 바꿔요"
[ "$N" -gt 0 ] && [ "$DRY_RUN" = true ] && NEXT="config.yml 에 없는 키 ${N}개 — --dry-run 이라 쓰지 않았어요"
if [ "$JSON_MODE" = true ]; then
    json_output ok "$(jq -nc --argjson a "$ADDED" --argjson d "$DRY_RUN" '{path:".ax/config.yml", added:$a, dry_run:$d}')" "$NEXT"
else
    [ "$N" -gt 0 ] && goax_log "$NEXT: $(printf '%s' "$ADDED" | jq -r 'join(", ")')" || goax_log "config.yml 에 빠진 키가 없어요"
fi
exit "$EXIT_OK"
