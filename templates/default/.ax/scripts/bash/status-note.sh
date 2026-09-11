#!/usr/bin/env bash
# .ax/scripts/bash/status-note.sh — 세션 간 인계 노트 (`.ax/current-task.json` 의 `handoff` 객체)
#
# Usage:
#   bash status-note.sh --show [--json]                      # 4절 파싱 (다음 세션·triage 가 읽어요)
#   bash status-note.sh --init [--json]                      # handoff 객체 보장 — 없으면 만들고, 있으면 빠진 키만 채워요
#   bash status-note.sh --add  <절> "<한 줄>" [--json]        # 절에 항목 추가 (같은 줄이 있으면 무시)
#   bash status-note.sh --done <절> "<부분 문자열>" [--json]  # 매칭 항목 제거 — 끝난 건 지워요
#   bash status-note.sh --set  <절> "<본문>" [--json]         # 절 통째 교체 (여러 줄은 \n 으로 — 역슬래시 escape 를 해석해요)
#   bash status-note.sh --clear <절> [--json]                 # 절 비우기 (`--set <절> ""` 과 동일)
#   절: now | next | open | renamed
#       now      지금 상태        spec-implement 가 halt·완료·레인 보고 시점에 갱신
#       next     다음             다음 세션이 처음 할 일 1~3개
#       open     열린 질문        사용자 결정 대기
#       renamed  이번에 바뀐 이름  레인 보고의 "다른 레인에 넘길 것" — 이름 대조의 SSOT
#
# 저장소는 `.ax/current-task.json` 의 `handoff` 객체예요 — {now:[], now_at, next:[], open:[], renamed:[]}.
# 상태 파일은 state.json · current-task.json 둘뿐이라 새 파일을 만들지 않아요. handoff 는 task 를
# 넘어 살아요 (reset-task.sh 가 안 지워요). 파일이 없으면 변이 모드는 거절해요 — `/up` 으로 설치를
# 마쳐요 (여기서 최소 파일을 만들면 설치가 정본 템플릿을 영영 못 깔아요).
#
# `--set now` 은 `now_at` 에 현재 UTC 분(YYYY-MM-DDTHH:MMZ)을 적어요. Stop 게이트
# (`.ax/hooks/stop/spec-gate.sh`) 가 "인계 노트에 적혀 있으니 의도된 halt" 로 인정하는 건
# **24시간 안에 찍힌 노트만**이에요. `--add now` 는 시각을 건드리지 않아요 — 게이트의 침묵 창이
# 넓어지면 안 되니까요. `now` 가 비면 `now_at` 도 null 이에요.
#
# 왜 필요한가 — 결정은 ADR, 진행은 tasks.md, 단계는 current-task.json 에 있는데 "막힌 것·열린 질문·
# 이번에 바뀐 공유 이름·다음 세션이 처음 해야 할 것" 은 어디에도 없었어요. 대화가 압축되면 사라져요.
# 상한 40개(네 절 항목 합) — 넘으면 warning. 완료 사실의 SSOT 는 git log · ADR 이라 끝난 항목은 지워요.
#
# Output (--show --json):
#   {"status":"ok|warning","result":{"path":".ax/current-task.json","exists":true,"items":N,"over_cap":false,
#     "now_at":"YYYY-MM-DDTHH:MMZ"|null,"sections":{"now":[…],"next":[…],"open":[…],"renamed":[…]},"counts":{…}},…}
# Exit: 0 ok · 1 error · 2 skipped (jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false; MODE=""; SEC=""; TEXT=""; CAP=40
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --show)    MODE=show ;;
        --init)    MODE=init ;;
        --add)     MODE=add;  shift; SEC="${1:-}"; shift; TEXT="${1:-}" ;;
        --done)    MODE=done; shift; SEC="${1:-}"; shift; TEXT="${1:-}" ;;
        --set)     MODE=set;  shift; SEC="${1:-}"; shift; TEXT="${1:-}" ;;
        --clear)   MODE=set;  shift; SEC="${1:-}"; TEXT="" ;;
        --cap)     shift; CAP="${1:-40}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    [ $# -gt 0 ] && shift
done
if [ "$SHOW_HELP" = true ]; then
    sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi
[ -n "$MODE" ] || MODE=show

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

# 저장소가 JSON 이라 jq 가 필수예요 — 없으면 README 규약대로 skip (exit 2)
if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then json_skip "jq 가 필요해요 — 인계 노트가 .ax/current-task.json 안에 있어요"; fi
    goax_warn "jq 가 없어 skip"; exit "$EXIT_SKIPPED"
fi
case "$CAP" in ''|*[!0-9]*) fail "--cap 은 정수예요 (받은 값: '${CAP}')" ;; esac

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
FILE="$PROJECT_ROOT/.ax/current-task.json"
REL=".ax/current-task.json"

sec_title() {
    case "$1" in
        now)     printf '지금 상태' ;;
        next)    printf '다음' ;;
        open)    printf '열린 질문' ;;
        renamed) printf '이번에 바뀐 이름' ;;
        *) return 1 ;;
    esac
}
if [ "$MODE" != show ] && [ "$MODE" != init ]; then
    sec_title "$SEC" >/dev/null 2>&1 || fail "절은 now|next|open|renamed 중 하나예요 (받은 값: '${SEC}')"
    # --set 만 빈 본문을 허용해요 = 그 절을 비우는 것 (--clear 와 같음).
    # --add·--done 은 빈 본문이면 그냥 오타라서 계속 막아요.
    [ "$MODE" = set ] || [ -n "$TEXT" ] || fail "--${MODE} 에는 본문이 필요해요"
fi

# handoff 객체가 있나 — 파일이 없거나 키가 없으면(업그레이드 전 설치) false. 읽기는 관대해요.
has_handoff() { [ -f "$FILE" ] && jq -e '.handoff | type == "object"' "$FILE" >/dev/null 2>&1; }

# 네 절 항목 합 — 상한은 이 총량 하나로 재요
count_items() { jq -r '(.handoff // {}) | [.now[]?, .next[]?, .open[]?, .renamed[]?] | length' "$FILE" 2>/dev/null || echo 0; }

# in-place 갱신 — handoff 밖의 키(task_id·phase·…)는 다른 writer 의 것이라 그대로 둬요
write_jq() {   # $@ = jq 인자 (필터가 마지막) — tmp.$$ → mv
    local tmp="$FILE.tmp.$$"
    jq "$@" "$FILE" > "$tmp" || { rm -f "$tmp"; fail "$REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요"; }
    mv "$tmp" "$FILE"
}

# handoff 객체 보장 — 없으면 만들고, 있으면 빠진 키만 채워요. 다른 키는 만들지 않아요.
ensure_handoff() {
    write_jq '.handoff = ((.handoff | if type == "object" then . else {} end)
        | {now: (.now // []), now_at: (.now_at // null), next: (.next // []), open: (.open // []), renamed: (.renamed // [])})'
}

emit_show() {
    local empty='{"now":[],"next":[],"open":[],"renamed":[]}' zero='{"now":0,"next":0,"open":0,"renamed":0}'
    if ! has_handoff; then
        local why
        if [ -f "$FILE" ]; then why='첫 인계는 --add next "…" 로 시작해요'; else why="$REL 이 없어요 (/up)"; fi
        if [ "$JSON_MODE" = true ]; then
            json_output "ok" '{"path":"'"$REL"'","exists":false,"items":0,"over_cap":false,"now_at":null,"sections":'"$empty"',"counts":'"$zero"'}' "인계 노트 없음 — $why"
        else
            printf '📝 인계 노트 없음 — %s\n' "$why"
        fi
        return 0
    fi
    local res items over st nx
    res=$(jq -c --arg p "$REL" --argjson cap "$CAP" '
        (.handoff | if type == "object" then . else {} end) as $h
        | {now: ($h.now // []), next: ($h.next // []), open: ($h.open // []), renamed: ($h.renamed // [])} as $s
        | ([$s[][]] | length) as $n
        | {path: $p, exists: true, items: $n, over_cap: ($n > $cap), now_at: ($h.now_at // null), sections: $s,
           counts: {now: ($s.now | length), next: ($s.next | length), open: ($s.open | length), renamed: ($s.renamed | length)}}' "$FILE") \
        || fail "$REL 을 읽지 못했어요 — JSON 이 깨졌는지 봐요"
    items=$(printf '%s' "$res" | jq -r '.items'); over=$(printf '%s' "$res" | jq -r '.over_cap')
    if [ "$JSON_MODE" = true ]; then
        st="ok"; nx="인계 노트 ${items}개 항목"
        [ "$over" = true ] && { st="warning"; nx="인계 노트 ${items}개 항목 — 상한 ${CAP}개를 넘었어요. 끝난 항목을 지우세요 (SSOT 는 git log · ADR)"; }
        json_output "$st" "$res" "$nx"
    else
        printf '📝 %s handoff (%s개 항목 · 상한 %s%s)\n' "$REL" "$items" "$CAP" "$([ "$over" = true ] && printf ' · ⚠ 초과')"
        local s at
        at=$(printf '%s' "$res" | jq -r '.now_at // "—"')
        for s in now next open renamed; do
            if [ "$s" = now ]; then printf '\n## %s (%s)\n' "$(sec_title "$s")" "$at"; else printf '\n## %s\n' "$(sec_title "$s")"; fi
            printf '%s' "$res" | jq -r --arg s "$s" '.sections[$s][]' | sed 's/^/  /'
        done
    fi
}

# 변이 모드는 "바꿀지 말지를 정하는 첫 읽기" 부터 락 안이에요 — ensure_handoff 의 키 존재 판정도,
# --add 의 중복 판정도 읽고 나서 쓰는 자리라 락 밖이면 두 세션이 서로를 덮어써요.
# dry-run 은 아무것도 안 쓰니까 락도 안 잡아요 (락 디렉토리 자체가 부작용이에요).
# 락 단위는 파일 — tier-from-state.sh --reset 도 같은 문자열을 잡아요.
# 파일 부재는 dry-run 도 알려야 해요 — 최소 파일을 만들어 주지 않아요 (설치 seed 가 막혀요).
LOCK="$(goax_normalize_path "$PROJECT_ROOT/.ax/current-task.json" "$PROJECT_ROOT").lock"
if [ "$MODE" != show ]; then
    [ -f "$FILE" ] || fail "$REL 이 없어요 — /up 으로 설치를 마쳐요"
    if [ "$DRY_RUN" != true ]; then
        goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 $REL 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
    fi
fi

case "$MODE" in
    show) emit_show ;;
    init)
        if [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","dry_run":true}' "handoff 객체만 확인 — 파일 안 썼어요" || goax_log "dry-run — $REL 안 썼어요"
        else
            ensure_handoff
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","initialized":true}' "handoff 준비됨 (now·next·open·renamed) — --add 로 채워요" || goax_log "$REL handoff 준비됨"
        fi ;;
    add)
        line="$TEXT"; case "$line" in -*|'- '*) ;; *) line="- $line" ;; esac
        if jq -e --arg s "$SEC" --arg v "$line" '(.handoff // {})[$s] // [] | any(. == $v)' "$FILE" >/dev/null 2>&1; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","added":false,"reason":"duplicate"}' "이미 있는 줄이라 그대로 뒀어요" || goax_log "이미 있는 줄 — 추가 안 함"
        elif [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","added":false,"dry_run":true}' "dry-run — 안 썼어요" || goax_log "dry-run — 안 썼어요"
        else
            ensure_handoff
            write_jq --arg s "$SEC" --arg v "$line" '.handoff[$s] += [$v]'
            n=$(count_items)
            if [ "$n" -gt "$CAP" ]; then
                [ "$JSON_MODE" = true ] && json_output "warning" '{"path":"'"$REL"'","added":true,"items":'"$n"',"over_cap":true}' "추가했지만 ${n}개 — 상한 ${CAP}개 초과. 끝난 항목을 지우세요" || goax_warn "추가됨 — ${n}개, 상한 ${CAP}개 초과"
            else
                [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","added":true,"items":'"$n"',"over_cap":false}' "$(sec_title "$SEC") 에 1개 추가" || goax_log "$(sec_title "$SEC") 에 추가 — $line"
            fi
        fi ;;
    done)
        # handoff 가 없으면 지울 것도 없어요 — 객체를 만들지 않아요
        removed=0
        if has_handoff; then
            removed=$(jq -r --arg s "$SEC" --arg t "$TEXT" '(.handoff[$s] // []) | map(select(contains($t))) | length' "$FILE" 2>/dev/null || echo 0)
        fi
        if [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","removed":'"$removed"',"dry_run":true}' "dry-run — ${removed}개 지워질 예정" || goax_log "dry-run — ${removed}개 지워질 예정"
        else
            # now 가 비면 now_at 도 null — 남은 줄이 있으면 시각은 그대로예요
            [ "$removed" -gt 0 ] && write_jq --arg s "$SEC" --arg t "$TEXT" '.handoff[$s] = ((.handoff[$s] // []) | map(select(contains($t) | not)))
                | if $s == "now" and (.handoff.now | length) == 0 then .handoff.now_at = null else . end'
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","removed":'"$removed"'}' "$(sec_title "$SEC") 에서 ${removed}개 제거" || goax_log "$(sec_title "$SEC") 에서 ${removed}개 제거"
        fi ;;
    set)
        # \n 확장 → 줄로 나눔 → 빈 줄 버림. `- ` 보정은 안 해요 (본문은 통째로 caller 의 것)
        body=$(printf '%b' "$TEXT")
        arr=$(printf '%s\n' "$body" | awk '!/^[[:space:]]*$/' | jq -R . | jq -sc .)
        stamp=""; [ "$SEC" = now ] && stamp=$(date -u +%Y-%m-%dT%H:%MZ)
        if [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","dry_run":true}' "dry-run — 안 썼어요" || goax_log "dry-run — 안 썼어요"
        else
            ensure_handoff
            # now 는 본문이 있으면 현재 UTC 분을 now_at 에 (여러 줄이어도 하나), 비면 null
            write_jq --arg s "$SEC" --argjson v "$arr" --arg ts "$stamp" '.handoff[$s] = $v
                | if $s == "now" then .handoff.now_at = (if ($v | length) > 0 then $ts else null end) else . end'
            n=$(count_items); over=false; [ "$n" -gt "$CAP" ] && over=true
            st=ok; [ "$over" = true ] && st=warning
            res=$(jq -nc --arg p "$REL" --argjson n "$n" --argjson o "$over" --argjson a "$(jq -c '.handoff.now_at // null' "$FILE")" \
                '{path: $p, replaced: true, items: $n, over_cap: $o, now_at: $a}')
            [ "$JSON_MODE" = true ] && json_output "$st" "$res" "$(sec_title "$SEC") 교체 — ${n}개 항목$([ "$over" = true ] && printf ' (상한 %s개 초과)' "$CAP")" || goax_log "$(sec_title "$SEC") 교체 — ${n}개 항목"
        fi ;;
esac
if [ "$MODE" != show ] && [ "$DRY_RUN" != true ]; then goax_unlock "$LOCK"; fi
exit "$EXIT_OK"
