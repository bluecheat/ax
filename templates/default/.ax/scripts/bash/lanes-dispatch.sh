#!/usr/bin/env bash
# .ax/scripts/bash/lanes-dispatch.sh — 레인 디스패치 원장. tasks.md 안에 살아요
#
# Usage:
#   bash lanes-dispatch.sh [--spec <NNN-slug>] [--status] [--json]
#   bash lanes-dispatch.sh [--spec <NNN-slug>] --assign "T010=A,T011=A,T020=B" [--force] [--dry-run] [--json]
#   bash lanes-dispatch.sh [--spec <NNN-slug>] --dispatch <lane> [--force] [--dry-run] [--json]
#   bash lanes-dispatch.sh [--spec <NNN-slug>] --report <lane | T010,T011> [--dry-run] [--json]
#
# 왜 필요한가 — 코디네이터의 기억은 컨텍스트 창 안에만 있어요. 어떤 task 를 어느 레인에
# 넘겼고 무엇이 돌아왔는지가 전부 창 안에 있는데, 그 창은 썩고 압축되고 세션이 죽으면
# 사라져요. 실제로 레인 8개가 전부 idle 이 됐을 때 체크박스는 24/36 이었고(idle ≠ 완료),
# 세 에이전트가 산출물을 완성해 놓고 전송하지 않아 아무것도 도착하지 않은 적이 있어요.
# 둘 다 "누구에게 무엇을 보냈고 무엇을 받았는가" 가 파일에 없어서 생긴 사고예요.
# 이 스크립트는 그 기록을 tasks.md 에 둬요 — 기계가 읽는 유일한 진행 원장이니까요.
#
# 원장 필드 — task 줄 아래 들여쓰기 continuation (`의존:` 과 같은 자리). 손으로 안 적어요.
#   레인: A                       소유 레인. --assign 이 써요
#   디스패치: 2026-09-06T03:12Z   레인에 실제로 넘긴 시각. --dispatch 가 써요
#   보고: 2026-09-06T04:02Z       코디네이터가 산출물을 **받은** 시각. --report 가 써요
#
# 판정 (--status):
#   dispatched_unreported  디스패치됐는데 보고가 없는 미완료 task — "레인이 조용하다" 는 완료가 아니에요
#   done_without_report    디스패치된 task 가 보고 기록 없이 [x] — 레인이 자기 체크박스를 켠 신호
#   lane_file_conflicts    같은 파일을 두 레인이 소유 — 핫 파일 독점 위반
#   unassigned_open        레인 없는 미완료 task — 코디네이터가 직접 하는 몫
#
# --assign 은 트랜잭션이에요 — 하나라도 거부되면 파일을 건드리지 않고 result 의
# `rejected` 에 이유를 담아요. 부분 적용은 원장을 반쯤 옮겨 놓아서 더 나빠요.
# --dispatch 는 기본적으로 **아직 보고를 못 받은** 미완료 task 만 보내요. 이미 보고까지
# 받은 task 를 다시 보내려면 --force (그때만 그 task 의 `보고:` 를 지워요).
# --dispatch 는 그 레인이 lane_file_conflicts 에 걸려 있으면 거부해요 (exit 1, --force 로 우회).
# 소유자는 정하지 않아요 — 배정은 판단이고 lane skill 이 사람과 해요. 여기선 기록과 검사만.
#
# `files:` 경로는 비교 전에 정규화해요 (`./` 제거 · 중복 `/` · 끝 `/`) — `src/a.ts` 와
# `./src/a.ts` 는 같은 파일이고, 표기 차이로 소유 충돌을 빠져나갈 수 없어요.
# ``` 코드펜스 안의 줄은 전부 건너뛰어요 — 형식 설명용 예시 task 가 실 task 로 세지 않도록.
# 원장 쓰기는 goax_lock 으로 직렬화해요 — mv 는 원자적이지만 lost-update 는 못 막아요.
#
# Output (--json):
#   {"status":"ok|warning","result":{"spec":"012-x","mode":"status|assign|dispatch|report",
#     "lanes":[{"lane":"A","tasks":["T010","T011"],"open":2,"dispatched":1,"reported":0,"done":0}],
#     "unassigned_open":["T009"],"dispatched_unreported":["T010"],"done_without_report":[],
#     "lane_file_conflicts":[{"file":"a.ts","lanes":["A","B"],"tasks":["T010","T020"]}],
#     "applied":["T010=A"],"rejected":[{"task":"T999","reason":"…"}],
#     "changed":0,"dry_run":false},...}
#
# Exit: 0 ok · 1 error (대상 없음 · 충돌로 dispatch 거부 · --assign 거부 · 락 실패) · 2 skipped (--json 인데 jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; FORCE=false
SPEC=""; MODE="status"; ASSIGN=""; LANE=""; REPORT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  DRY_RUN=true ;;
        --force)    FORCE=true ;;
        --status)   MODE="status" ;;
        --assign)   shift; MODE="assign";   ASSIGN="${1:-}" ;;
        --dispatch) shift; MODE="dispatch"; LANE="${1:-}" ;;
        --report)   shift; MODE="report";   REPORT="${1:-}" ;;
        --spec)     shift; SPEC="${1:-}" ;;
        --help|-h)  SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,49p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi

if [ "$JSON_MODE" = true ] && ! command -v jq >/dev/null 2>&1; then
    printf '{"status":"skipped","result":{},"next_step":"jq 가 필요해요","warnings":["jq not found"],"errors":[]}\n'
    exit "$EXIT_SKIPPED"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

fail() {
    if [ "$JSON_MODE" = true ]; then json_error "$1"; fi
    goax_error "$1"; exit "$EXIT_ERROR"
}

if [ -z "$SPEC" ] && command -v jq >/dev/null 2>&1; then
    TF="$PROJECT_ROOT/.ax/current-task.json"
    if [ -f "$TF" ]; then
        SD=$(jq -r '.spec_dir // empty' "$TF" 2>/dev/null || true)
        [ -n "$SD" ] && SPEC=$(basename "$SD")
    fi
fi

# --spec 해석은 공통 규칙 (정확 일치 → prefix 1개 → 실패) — 스크립트마다 다르면 같은 인자에 다른 답이 나와요
if [ -n "$SPEC" ]; then
    RESOLVED=$(goax_resolve_spec "$SPEC" "$PROJECT_ROOT/.ax/docs/spec") && RC=0 || RC=$?
    if [ "$RC" -eq 0 ]; then SPEC="$RESOLVED"
    elif [ "$RC" -eq 2 ]; then
        fail "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES} — 하나를 정확히 적으세요"
    fi
fi

TASKS="$PROJECT_ROOT/.ax/docs/spec/$SPEC/tasks.md"
LOCK="$TASKS.lock"
if [ -z "$SPEC" ] || [ ! -f "$TASKS" ]; then
    fail "tasks.md 를 찾을 수 없어요: .ax/docs/spec/${SPEC:-<없음>}/tasks.md"
fi

# ── 파싱: "ID|state|files(,)|lane|dispatched|reported" ─────────────────────────
# ``` 펜스 안은 형식 설명이라 건너뛰고, files: 경로는 비교 전에 정규화해요.
parse_ledger() {
    awk '
        function norm(p) {
            gsub(/\/+/, "/", p)
            while (sub(/^\.\//, "", p)) ;
            while (sub(/\/\.\//, "/", p)) ;
            sub(/\/+$/, "", p)
            return p
        }
        function normlist(s,   n, a, i, v, out) {
            if (s == "") return ""
            n = split(s, a, ",")
            out = ""
            for (i = 1; i <= n; i++) { v = norm(a[i]); if (v != "") out = (out == "" ? v : out "," v) }
            return out
        }
        function flush() {
            if (id != "") printf "%s|%s|%s|%s|%s|%s\n", id, st, files, lane, disp, rep
            id=""; st=""; files=""; lane=""; disp=""; rep=""
        }
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^- \[[ x~X]\] / {
            flush()
            line = $0; st = "open"
            if (line ~ /^- \[[xX]\]/) st = "done"
            else if (line ~ /^- \[~\]/) st = "paused"
            if (match(line, /T[0-9][0-9][0-9]+/)) id = substr(line, RSTART, RLENGTH)
            f = line
            if (match(f, /files:[ ]*/)) {
                f = substr(f, RSTART + RLENGTH)
                gsub(/[ ]*,[ ]*/, ",", f); gsub(/^[ ]+|[ ]+$/, "", f)
                files = normlist(f)
            }
            next
        }
        id != "" && /^[ \t]+레인:/     { v = $0; sub(/^[ \t]*레인:[ ]*/, "", v);     gsub(/[ \t]+$/, "", v); lane = v; next }
        id != "" && /^[ \t]+디스패치:/ { v = $0; sub(/^[ \t]*디스패치:[ ]*/, "", v); gsub(/[ \t]+$/, "", v); disp = v; next }
        id != "" && /^[ \t]+보고:/     { v = $0; sub(/^[ \t]*보고:[ ]*/, "", v);     gsub(/[ \t]+$/, "", v); rep = v;  next }
        END { flush() }
    ' "$1"
}

# ── 편집: task 블록 안의 continuation 필드를 set / del ────────────────────────
# $1 file · $2 ids(,) · $3 key · $4 value · $5 set|del
# 있으면 자리에서 바꾸고, 없으면 블록 끝에 붙여요. 들여쓰기는 블록의 기존 줄을 따라가요.
edit_field() {
    awk -v ids="$2" -v key="$3" -v val="$4" -v mode="$5" '
        BEGIN { n = split(ids, a, ","); for (i = 1; i <= n; i++) want[a[i]] = 1; ind = "      " }
        function leave() {
            if (cur != "" && (cur in want) && mode == "set" && !hit) print ind key ": " val
            cur = ""; hit = 0; ind = "      "; indset = 0
        }
        /^[[:space:]]*```/ { leave(); fence = !fence; print; next }
        fence { print; next }
        /^- \[[ x~X]\] / {
            leave()
            if (match($0, /T[0-9][0-9][0-9]+/)) cur = substr($0, RSTART, RLENGTH)
            print; next
        }
        cur != "" && /^[ \t]+[^ \t]/ {
            body = $0; sub(/^[ \t]+/, "", body)
            if (!indset) { indset = 1; ind = substr($0, 1, length($0) - length(body)) }
            if ((cur in want) && index(body, key ":") == 1) {
                if (mode == "set") { if (!hit) { print ind key ": " val; hit = 1 } ; next }
                if (mode == "del") next
            }
            print; next
        }
        { leave(); print }
        END { leave() }
    ' "$1"
}

# $1 ids(,) · $2 key · $3 value · $4 set|del  — DRY_RUN 이면 파일을 건드리지 않아요.
# read → 변환 → mv 전체를 락으로 감싸요: 레인 둘이 동시에 --report 하면 락 없이는
# 나중에 mv 하는 쪽이 앞의 기록을 통째로 덮어써요 (실측 30/30 유실).
apply_edit() {
    local tmp
    if [ "$DRY_RUN" = true ]; then return 0; fi
    goax_lock "$LOCK" || fail "원장 락을 못 잡았어요: $LOCK — 다른 프로세스가 쓰는 중이거나 락이 남아 있어요"
    tmp="$TASKS.tmp.$$"
    edit_field "$TASKS" "$1" "$2" "$3" "$4" > "$tmp" && mv "$tmp" "$TASKS" || { rm -f "$tmp"; goax_unlock "$LOCK"; fail "원장 갱신 실패: $TASKS"; }
    goax_unlock "$LOCK"
}

has_id() { printf '%s\n' "$LEDGER" | awk -F'|' -v id="$1" '$1==id{f=1} END{exit f?0:1}'; }

NOW=$(date -u +%Y-%m-%dT%H:%MZ)
LEDGER=$(parse_ledger "$TASKS")
CHANGED=0
WARN=""
APPLIED=""       # 공백 구분 "T010=A"
REJECTED=""      # 개행 구분 "T010|사유"
SKIPPED=""       # dispatch 에서 건너뛴 task (이미 보고 받음)
TARGETS=""

case "$MODE" in
  assign)
    [ -n "$ASSIGN" ] || fail "--assign 에 \"T010=A,T011=A\" 형식이 필요해요"
    # 1단계: 전부 검증만 — 하나라도 거부되면 파일을 안 건드려요
    PLAN=""
    oldIFS="$IFS"; IFS=','
    for pair in $ASSIGN; do
        pair=$(printf '%s' "$pair" | tr -d ' ')
        [ -z "$pair" ] && continue
        tid="${pair%%=*}"; ln="${pair#*=}"
        if ! { [ -n "$tid" ] && [ -n "$ln" ] && [ "$tid" != "$ln" ]; }; then
            REJECTED="${REJECTED}${pair}|형식 오류 — T010=A 형식이어야 해요
"; continue
        fi
        if ! has_id "$tid"; then
            REJECTED="${REJECTED}${tid}|tasks.md 에 없는 task
"; continue
        fi
        cur=$(printf '%s\n' "$LEDGER" | awk -F'|' -v id="$tid" '$1==id{print $4}')
        if [ -n "$cur" ] && [ "$cur" != "$ln" ] && [ "$FORCE" != true ]; then
            REJECTED="${REJECTED}${tid}|이미 레인 ${cur} — 옮기려면 --force
"; continue
        fi
        PLAN="${PLAN}${tid}=${ln}
"
    done
    IFS="$oldIFS"

    if [ -n "$REJECTED" ]; then
        if [ "$JSON_MODE" = true ]; then
            REJ_J=$(printf '%s' "$REJECTED" | jq -Rn '[inputs|select(length>0)|split("|")|{task:.[0], reason:.[1]}]')
            RESULT=$(jq -nc --arg spec "$SPEC" --arg mode "$MODE" --argjson rej "$REJ_J" --argjson dry "$DRY_RUN" \
                '{spec:$spec, mode:$mode, applied:[], rejected:$rej, changed:0, dry_run:$dry}')
            ERRS=$(_goax_json_array "--assign 거부 — 파일은 그대로예요. rejected 를 보세요")
            json_output "error" "$RESULT" "" "[]" "$ERRS"
        else
            goax_error "--assign 거부 (파일 무변경):"
            printf '%s' "$REJECTED" | awk -F'|' 'NF{printf "  %-8s %s\n", $1, $2}' >&2
        fi
        exit "$EXIT_ERROR"
    fi

    # 2단계: 전부 적용
    oldIFS="$IFS"; IFS='
'
    for p in $PLAN; do
        [ -z "$p" ] && continue
        tid="${p%%=*}"; ln="${p#*=}"
        apply_edit "$tid" "레인" "$ln" set
        APPLIED="$APPLIED$p "
        CHANGED=$((CHANGED + 1))
    done
    IFS="$oldIFS"
    ;;
  dispatch)
    [ -n "$LANE" ] || fail "--dispatch 에 레인 이름이 필요해요"
    OPEN_IN_LANE=$(printf '%s\n' "$LEDGER" | awk -F'|' -v l="$LANE" '$2=="open" && $4==l{print $1}')
    [ -n "$OPEN_IN_LANE" ] || fail "레인 '$LANE' 에 미완료 task 가 없어요 — --assign 으로 먼저 배정하세요"
    if [ "$FORCE" = true ]; then
        TARGETS=$(printf '%s\n' "$OPEN_IN_LANE" | paste -sd, - || true)
    else
        # 기본 대상 = 디스패치 기록이 없거나 보고를 못 받은 것. 보고까지 받은 task 는 건드리지 않아요
        TARGETS=$(printf '%s\n' "$LEDGER" | awk -F'|' -v l="$LANE" '$2=="open" && $4==l && ($5=="" || $6==""){print $1}' | paste -sd, - || true)
        SKIPPED=$(printf '%s\n' "$LEDGER" | awk -F'|' -v l="$LANE" '$2=="open" && $4==l && $5!="" && $6!=""{print $1}' | paste -sd, - || true)
        [ -n "$TARGETS" ] || fail "레인 '$LANE' 의 미완료 task 는 전부 디스패치 후 보고까지 받았어요 (${SKIPPED}) — 그래도 다시 보내려면 --force"
    fi
    ;;
  report)
    [ -n "$REPORT" ] || fail "--report 에 레인 이름 또는 task ID 목록이 필요해요"
    IS_LANE=$(printf '%s\n' "$LEDGER" | awk -F'|' -v l="$REPORT" '$4==l{f=1} END{print f?1:0}')
    if [ "$IS_LANE" = "1" ]; then
        TARGETS=$(printf '%s\n' "$LEDGER" | awk -F'|' -v l="$REPORT" '$4==l && $5!=""{print $1}' | paste -sd, - || true)
        [ -n "$TARGETS" ] || fail "레인 '$REPORT' 에 디스패치된 task 가 없어요 — 보고할 게 없어요"
    else
        TARGETS=$(printf '%s' "$REPORT" | tr -d ' ')
        MISSING=""; NODISP=""
        oldIFS="$IFS"; IFS=','
        for tid in $TARGETS; do
            [ -z "$tid" ] && continue
            has_id "$tid" || { MISSING="$MISSING$tid "; continue; }
            d=$(printf '%s\n' "$LEDGER" | awk -F'|' -v id="$tid" '$1==id{print $5}')
            [ -z "$d" ] && NODISP="$NODISP$tid "
        done
        IFS="$oldIFS"
        [ -n "$MISSING" ] && fail "tasks.md 에 없는 task: ${MISSING% }"
        [ -n "$NODISP" ] && WARN="디스패치 기록 없이 보고: ${NODISP% } — 원장 밖에서 넘긴 거면 다음부턴 --dispatch 를 거치세요"
    fi
    ;;
  status) ;;
esac

# ── 판정 (assign 뒤엔 갱신된 원장으로) ──────────────────────────────────────────
[ "$MODE" = "assign" ] && [ "$DRY_RUN" != true ] && LEDGER=$(parse_ledger "$TASKS")

# 같은 파일을 두 레인이 소유 — "file|lanes(,)|tasks(,)". 경로는 parse_ledger 가 이미 정규화했어요
CONFLICTS=$(printf '%s\n' "$LEDGER" | awk -F'|' '
    $2=="open" && $4!="" && $3!="" {
        n = split($3, fs, ",")
        for (i = 1; i <= n; i++) {
            f = fs[i]; gsub(/^[ \t]+|[ \t]+$/, "", f); if (f == "") continue
            key = f SUBSEP $4
            if (!(key in seen)) { seen[key] = 1; lanes[f] = (f in lanes) ? lanes[f] "," $4 : $4; cnt[f]++ }
            tasks[f] = (f in tasks) ? tasks[f] "," $1 : $1
        }
    }
    END { for (f in cnt) if (cnt[f] > 1) printf "%s|%s|%s\n", f, lanes[f], tasks[f] }
' | sort)

if [ "$MODE" = "dispatch" ]; then
    if [ -n "$CONFLICTS" ] && [ "$FORCE" != true ] \
       && printf '%s\n' "$CONFLICTS" | awk -F'|' -v l="$LANE" 'BEGIN{f=0} { n=split($2,a,","); for(i=1;i<=n;i++) if(a[i]==l) f=1 } END{exit f?0:1}'; then
        fail "레인 '$LANE' 이 다른 레인과 파일을 공유해요 — 소유권부터 정리하세요 (--status 로 lane_file_conflicts 확인). 그래도 보내려면 --force"
    fi
    apply_edit "$TARGETS" "디스패치" "$NOW" set
    apply_edit "$TARGETS" "보고" "" del
    CHANGED=$(printf '%s' "$TARGETS" | awk -F, '{print NF}')
    [ "$DRY_RUN" != true ] && LEDGER=$(parse_ledger "$TASKS")
elif [ "$MODE" = "report" ]; then
    apply_edit "$TARGETS" "보고" "$NOW" set
    CHANGED=$(printf '%s' "$TARGETS" | awk -F, '{print NF}')
    [ "$DRY_RUN" != true ] && LEDGER=$(parse_ledger "$TASKS")
fi

# lane|tasks(,)|open|dispatched|reported|done
LANES=$(printf '%s\n' "$LEDGER" | awk -F'|' '
    $4!="" {
        l = $4; if (!(l in seen)) { seen[l] = 1; order[++n] = l }
        t[l] = (l in t) ? t[l] "," $1 : $1
        if ($2 == "open") o[l]++
        if ($5 != "") d[l]++
        if ($6 != "") r[l]++
        if ($2 == "done") dn[l]++
    }
    END { for (i = 1; i <= n; i++) { l = order[i]; printf "%s|%s|%d|%d|%d|%d\n", l, t[l], o[l]+0, d[l]+0, r[l]+0, dn[l]+0 } }
')
UNASSIGNED=$(printf '%s\n' "$LEDGER" | awk -F'|' '$2=="open" && $4==""{print $1}')
UNREPORTED=$(printf '%s\n' "$LEDGER" | awk -F'|' '$2=="open" && $5!="" && $6==""{print $1}')
NOREPORT=$(printf '%s\n' "$LEDGER" | awk -F'|' '$2=="done" && $5!="" && $6==""{print $1}')

CONF_N=$(printf '%s' "$CONFLICTS" | grep -c . || true); CONF_N=${CONF_N:-0}
UNREP_N=$(printf '%s' "$UNREPORTED" | grep -c . || true); UNREP_N=${UNREP_N:-0}
NOREP_N=$(printf '%s' "$NOREPORT" | grep -c . || true); NOREP_N=${NOREP_N:-0}

# 방금 디스패치한 task 는 "보고 안 받은 디스패치" 경보에서 빼요 — 방금 보낸 걸 경보로 돌려받으면
# 성공을 알 수 없어요. result 의 dispatched_unreported 는 사실 그대로 두고, 경보 집계만 걸러요.
UNREP_WARN_N="$UNREP_N"
if [ "$MODE" = "dispatch" ] && [ -n "$TARGETS" ]; then
    UNREP_WARN_N=$(printf '%s\n' "$UNREPORTED" | awk -v t="$TARGETS" '
        BEGIN { n = split(t, a, ","); for (i = 1; i <= n; i++) just[a[i]] = 1 }
        NF && !($1 in just) { c++ } END { print c+0 }')
fi

if [ "$JSON_MODE" = true ]; then
    arr() { printf '%s\n' "$1" | jq -Rn '[inputs|select(length>0)]'; }
    LANES_J=$(printf '%s\n' "$LANES" | jq -Rn '[inputs|select(length>0)|split("|")
        | {lane:.[0], tasks:(.[1]|split(",")), open:(.[2]|tonumber), dispatched:(.[3]|tonumber),
           reported:(.[4]|tonumber), done:(.[5]|tonumber)}]')
    CONF_J=$(printf '%s\n' "$CONFLICTS" | jq -Rn '[inputs|select(length>0)|split("|")
        | {file:.[0], lanes:(.[1]|split(",")), tasks:(.[2]|split(","))}]')
    APP_J=$(printf '%s' "$APPLIED" | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
    RESULT=$(jq -nc --arg spec "$SPEC" --arg mode "$MODE" --argjson lanes "$LANES_J" \
        --argjson un "$(arr "$UNASSIGNED")" --argjson dr "$(arr "$UNREPORTED")" \
        --argjson dn "$(arr "$NOREPORT")" --argjson cf "$CONF_J" --argjson app "$APP_J" \
        --argjson changed "${CHANGED:-0}" --argjson dry "$DRY_RUN" \
        '{spec:$spec, mode:$mode, lanes:$lanes, unassigned_open:$un, dispatched_unreported:$dr,
          done_without_report:$dn, lane_file_conflicts:$cf, applied:$app, rejected:[],
          changed:$changed, dry_run:$dry}')
    WARN_J='[]'; [ -n "$WARN" ] && WARN_J=$(_goax_json_array "$WARN")
    if [ "$CONF_N" -gt 0 ]; then
        json_output "warning" "$RESULT" "같은 파일을 두 레인이 소유해요 (${CONF_N}개) — 핫 파일은 한 레인이 독점하거나 별도 task 로 떼세요" "$WARN_J"
    elif [ "$UNREP_WARN_N" -gt 0 ] || [ "$NOREP_N" -gt 0 ]; then
        json_output "warning" "$RESULT" "보고 안 받은 디스패치 ${UNREP_WARN_N}개 · 보고 없이 완료된 task ${NOREP_N}개 — 산출물을 받고 --report 로 기록한 뒤에만 완료예요" "$WARN_J"
    else
        case "$MODE" in
            assign)   NEXT="레인 배정 ${CHANGED}건 기록. tasks-plan.sh 로 violations 확인 뒤 --dispatch <레인>" ;;
            dispatch) NEXT="레인 '$LANE' 에 ${CHANGED} task 디스패치 (${TARGETS})"
                      [ -n "$SKIPPED" ] && NEXT="$NEXT · 보고까지 받은 ${SKIPPED} 은 건너뜀 (--force 로 재전송)"
                      NEXT="$NEXT. 산출물이 오면 --report $LANE" ;;
            report)   NEXT="보고 ${CHANGED}건 기록. 검증 명령을 돌린 뒤 체크박스를 켜세요 — 보고가 곧 완료는 아니에요" ;;
            *)        NEXT="원장 이상 없음" ;;
        esac
        json_output "ok" "$RESULT" "$NEXT" "$WARN_J"
    fi
else
    printf 'spec %s — 레인 원장 (%s)\n' "$SPEC" "$MODE"
    if [ -n "$LANES" ]; then
        printf '%s\n' "$LANES" | awk -F'|' '{ printf "  레인 %-6s task %-28s 미완료 %s · 디스패치 %s · 보고 %s · 완료 %s\n", $1, $2, $3, $4, $5, $6 }'
    else
        printf '  레인 배정 없음 (단일 레인)\n'
    fi
    [ -n "$APPLIED" ] && printf '  배정: %s\n' "${APPLIED% }"
    [ "$MODE" = "dispatch" ] && [ -n "$TARGETS" ] && printf '  보냄: %s\n' "$TARGETS"
    [ -n "$SKIPPED" ] && printf '  건너뜀 (보고 받음): %s — 다시 보내려면 --force\n' "$SKIPPED"
    [ -n "$UNASSIGNED" ] && printf '  레인 없는 미완료: %s\n' "$(printf '%s' "$UNASSIGNED" | tr '\n' ' ')"
    [ "$UNREP_WARN_N" -gt 0 ] && printf '  ⚠ 디스패치됐는데 보고 없음: %s\n' "$(printf '%s' "$UNREPORTED" | tr '\n' ' ')"
    [ "$NOREP_N" -gt 0 ] && printf '  ⚠ 보고 없이 완료 표시: %s\n' "$(printf '%s' "$NOREPORT" | tr '\n' ' ')"
    if [ "$CONF_N" -gt 0 ]; then
        printf '  ⛔ 파일 소유 충돌 (%s)\n' "$CONF_N"
        printf '%s\n' "$CONFLICTS" | awk -F'|' '{ printf "     %-44s 레인 %s (%s)\n", $1, $2, $3 }'
    fi
    [ -n "$WARN" ] && printf '  ⚠ %s\n' "$WARN"
    [ "$DRY_RUN" = true ] && [ "$MODE" != "status" ] && printf '  (dry-run — 파일은 그대로예요, 변경 예정 %s건)\n' "$CHANGED"
fi
exit "$EXIT_OK"
