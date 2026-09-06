#!/usr/bin/env bash
# .ax/scripts/bash/status-note.sh — 세션 간 인계 노트 `.ax/docs/STATUS.md`
#
# Usage:
#   bash status-note.sh --show [--json]                      # 4절 파싱 (다음 세션·triage 가 읽어요)
#   bash status-note.sh --init [--json]                      # 없으면 골격 생성, 있으면 빠진 절만 추가
#   bash status-note.sh --add  <절> "<한 줄>" [--json]        # 절에 항목 추가 (같은 줄이 있으면 무시)
#   bash status-note.sh --done <절> "<부분 문자열>" [--json]  # 매칭 항목 제거 — 끝난 건 지워요
#   bash status-note.sh --set  <절> "<본문>" [--json]         # 절 통째 교체 (여러 줄은 \n 으로)
#   bash status-note.sh --clear <절> [--json]                 # 절 비우기 (`--set <절> ""` 과 동일)
#   절: now | next | open | renamed
#       now      ## 지금 상태        spec-implement 가 halt·완료·레인 보고 시점에 갱신
#       next     ## 다음             다음 세션이 처음 할 일 1~3개
#       open     ## 열린 질문        사용자 결정 대기
#       renamed  ## 이번에 바뀐 이름  레인 보고의 "다른 레인에 넘길 것" — 이름 대조의 SSOT
#
# `--set now` 은 마지막 줄 끝에 `(YYYY-MM-DDTHH:MMZ)` 를 박아요. Stop 게이트
# (`.ax/hooks/stop/spec-gate.sh`) 가 "인계 노트에 적혀 있으니 의도된 halt" 로 인정하는 건
# **24시간 안에 찍힌 노트만**이에요. 시각이 없으면 옛 노트 한 줄이 새 세션의 게이트를
# 영원히 침묵시켜요 (다른 session_id 로 몇 번을 불러도 안 잡히던 구멍).
#
# 왜 필요한가 — 결정은 ADR, 진행은 tasks.md, 단계는 current-task.json 에 있는데 "막힌 것·열린 질문·
# 이번에 바뀐 공유 이름·다음 세션이 처음 해야 할 것" 은 어디에도 없었어요. 대화가 압축되면 사라져요.
# 형식이 고정돼야 다음 세션이 파싱하니까 쓰는 쪽은 스크립트, 무엇을 적을지는 skill 이 정해요.
# 상한 40줄 — 넘으면 warning. 완료 사실의 SSOT 는 git log · ADR 이라 끝난 항목은 지워요.
#
# Output (--show --json):
#   {"status":"ok|warning","result":{"path":".ax/docs/STATUS.md","exists":true,"lines":N,"over_cap":false,
#     "sections":{"now":[…],"next":[…],"open":[…],"renamed":[…]},"counts":{…}},…}
# Exit: 0 ok · 1 error

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
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi
[ -n "$MODE" ] || MODE=show

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
FILE="$PROJECT_ROOT/.ax/docs/STATUS.md"
REL=".ax/docs/STATUS.md"

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

# `지금 상태` 는 시각을 같이 박아요 — Stop 게이트가 24시간 안의 노트만 인정해요.
# 이미 박혀 있으면 지우고 다시 박아요 (두 번 붙는 걸 막아요).
stamp_now() {   # stdin 본문 → 마지막 줄 끝에 (YYYY-MM-DDTHH:MMZ)
    sed -E 's/[[:space:]]*\([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z\)[[:space:]]*$//' \
        | awk -v s=" ($(date -u +%Y-%m-%dT%H:%MZ))" \
              '{ l[NR] = $0 } END { for (i = 1; i <= NR; i++) print l[i] (i == NR ? s : "") }'
}

# 골격 — zero 가 만든 2절짜리도 여기서 4절로 승격돼요
ensure_file() {
    mkdir -p "$(dirname "$FILE")"
    if [ ! -f "$FILE" ]; then
        printf '# STATUS — 세션 간 인계 노트\n\n> 끝난 항목은 지워요. 완료의 SSOT 는 git log · ADR 이에요. 상한 %s줄.\n\n' "$CAP" > "$FILE"
    fi
    for s in now next open renamed; do
        t=$(sec_title "$s")
        grep -qE "^## ${t}[[:space:]]*$" "$FILE" || printf '\n## %s\n' "$t" >> "$FILE"
    done
}

# 절 본문 추출 (헤더 제외, 빈 줄 제외)
section_lines() {
    local t; t=$(sec_title "$1")
    [ -f "$FILE" ] || return 0
    awk -v t="$t" '
        /^## / { inb = ($0 ~ ("^## " t "[ \t]*$")); next }
        inb && $0 !~ /^[ \t]*$/ { print }' "$FILE"
}

# 절 본문 교체 — stdin 이 새 본문. 본문은 파일로 넘겨요 (macOS awk 는 -v 값에 개행을 못 받아요)
replace_section() {
    local t tmp bodyf; t=$(sec_title "$1"); tmp="$FILE.tmp.$$"; bodyf="$FILE.body.$$"
    cat > "$bodyf"
    awk -v t="$t" -v bodyf="$bodyf" '
        /^## / {
            if (inb) { inb = 0 }
            if ($0 ~ ("^## " t "[ \t]*$")) {
                print
                while ((getline l < bodyf) > 0) { if (l !~ /^[ \t]*$/) print l }
                close(bodyf); print ""; inb = 1; next
            }
        }
        inb { next }
        { print }' "$FILE" > "$tmp" && mv "$tmp" "$FILE"
    rm -f "$bodyf"
}

emit_show() {
    local lines over
    if [ ! -f "$FILE" ]; then
        if [ "$JSON_MODE" = true ]; then
            json_output "ok" '{"path":"'"$REL"'","exists":false,"lines":0,"over_cap":false,"sections":{"now":[],"next":[],"open":[],"renamed":[]},"counts":{"now":0,"next":0,"open":0,"renamed":0}}' "인계 노트 없음 — status-note.sh --init 또는 --add 로 시작해요"
        else
            printf '📝 %s 없음 — 첫 인계는 --add next "…" 로 시작해요\n' "$REL"
        fi
        return 0
    fi
    lines=$(wc -l < "$FILE" | tr -d ' '); over=false; [ "$lines" -gt "$CAP" ] && over=true
    if [ "$JSON_MODE" = true ]; then
        local sj="{}" cj="{}" s arr n
        for s in now next open renamed; do
            arr=$(section_lines "$s" | jq -R . | jq -sc .)
            n=$(printf '%s' "$arr" | jq 'length')
            sj=$(printf '%s' "$sj" | jq -c --arg k "$s" --argjson v "$arr" '. + {($k): $v}')
            cj=$(printf '%s' "$cj" | jq -c --arg k "$s" --argjson v "$n" '. + {($k): $v}')
        done
        local res st="ok" nx="인계 노트 ${lines}줄"
        res=$(jq -nc --arg p "$REL" --arg l "$lines" --argjson o "$over" --argjson s "$sj" --argjson c "$cj" \
            '{path:$p,exists:true,lines:($l|tonumber),over_cap:$o,sections:$s,counts:$c}')
        [ "$over" = true ] && { st="warning"; nx="인계 노트 ${lines}줄 — 상한 ${CAP}줄을 넘었어요. 끝난 항목을 지우세요 (SSOT 는 git log · ADR)"; }
        json_output "$st" "$res" "$nx"
    else
        printf '📝 %s (%s줄%s)\n' "$REL" "$lines" "$([ "$over" = true ] && printf ' — ⚠ 상한 %s줄 초과' "$CAP")"
        for s in now next open renamed; do
            printf '\n## %s\n' "$(sec_title "$s")"
            section_lines "$s" | sed 's/^/  /'
        done
    fi
}

# 변이 모드는 "바꿀지 말지를 정하는 첫 읽기" 부터 락 안이에요 — ensure_file 의 절 추가도,
# --add 의 중복 판정도 읽고 나서 쓰는 자리라 락 밖이면 두 세션이 서로를 덮어써요.
# dry-run 은 아무것도 안 쓰니까 락도 안 잡아요 (락 디렉토리 자체가 부작용이에요).
LOCK="$FILE.lock"
if [ "$MODE" != show ] && [ "$DRY_RUN" != true ]; then
    goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 $REL 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
fi

case "$MODE" in
    show) emit_show ;;
    init)
        if [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","dry_run":true}' "골격만 확인 — 파일 안 썼어요" || goax_log "dry-run — $REL 안 썼어요"
        else
            ensure_file
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","initialized":true}' "4절 골격 준비됨 — --add 로 채워요" || goax_log "$REL 준비됨 (4절)"
        fi ;;
    add)
        line="$TEXT"; case "$line" in -*|'- '*) ;; *) line="- $line" ;; esac
        if section_lines "$SEC" | grep -qxF -- "$line"; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","added":false,"reason":"duplicate"}' "이미 있는 줄이라 그대로 뒀어요" || goax_log "이미 있는 줄 — 추가 안 함"
        elif [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","added":false,"dry_run":true}' "dry-run — 안 썼어요" || goax_log "dry-run — 안 썼어요"
        else
            ensure_file
            { section_lines "$SEC"; printf '%s\n' "$line"; } | replace_section "$SEC"
            n=$(wc -l < "$FILE" | tr -d ' ')
            if [ "$n" -gt "$CAP" ]; then
                [ "$JSON_MODE" = true ] && json_output "warning" '{"path":"'"$REL"'","added":true,"lines":'"$n"',"over_cap":true}' "추가했지만 ${n}줄 — 상한 ${CAP}줄 초과. 끝난 항목을 지우세요" || goax_warn "추가됨 — ${n}줄, 상한 ${CAP}줄 초과"
            else
                [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","added":true,"lines":'"$n"',"over_cap":false}' "$(sec_title "$SEC") 에 1줄 추가" || goax_log "$(sec_title "$SEC") 에 추가 — $line"
            fi
        fi ;;
    done)
        [ -f "$FILE" ] || fail "$REL 이 없어요"
        before=$(section_lines "$SEC" | grep -c . || true)
        remaining=$(section_lines "$SEC" | grep -vF -- "$TEXT" || true)
        after=$(printf '%s' "$remaining" | grep -c . || true)
        removed=$(( before - after ))
        if [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","removed":'"$removed"',"dry_run":true}' "dry-run — ${removed}줄 지워질 예정" || goax_log "dry-run — ${removed}줄 지워질 예정"
        else
            printf '%s' "$remaining" | replace_section "$SEC"
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","removed":'"$removed"'}' "$(sec_title "$SEC") 에서 ${removed}줄 제거" || goax_log "$(sec_title "$SEC") 에서 ${removed}줄 제거"
        fi ;;
    set)
        body=$(printf '%b' "$TEXT")
        if [ "$SEC" = now ] && [ -n "$body" ]; then body=$(printf '%s\n' "$body" | stamp_now); fi
        if [ "$DRY_RUN" = true ]; then
            [ "$JSON_MODE" = true ] && json_output "ok" '{"path":"'"$REL"'","dry_run":true}' "dry-run — 안 썼어요" || goax_log "dry-run — 안 썼어요"
        else
            ensure_file
            printf '%s' "$body" | replace_section "$SEC"
            n=$(wc -l < "$FILE" | tr -d ' ')
            st=ok; [ "$n" -gt "$CAP" ] && st=warning
            [ "$JSON_MODE" = true ] && json_output "$st" '{"path":"'"$REL"'","replaced":true,"lines":'"$n"',"over_cap":'"$([ "$st" = warning ] && echo true || echo false)"'}' "$(sec_title "$SEC") 교체 — ${n}줄" || goax_log "$(sec_title "$SEC") 교체 — ${n}줄"
        fi ;;
esac
if [ "$MODE" != show ] && [ "$DRY_RUN" != true ]; then goax_unlock "$LOCK"; fi
exit "$EXIT_OK"
