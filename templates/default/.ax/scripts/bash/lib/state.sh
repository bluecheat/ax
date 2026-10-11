#!/usr/bin/env bash
# .ax/scripts/bash/lib/state.sh — 런타임 상태 파일 — 작업별 파일 경로, 템플릿 seed, 글롭 소유자
# common.sh 가 source 해요. 직접 source 하지 않아요.
# shellcheck disable=SC2034  # 여기서 정의한 변수는 common.sh 를 source 한 스크립트가 써요

# ─── 작업별 상태 — .ax/tasks/<task_id>.json ─────────────────────────────
# 작업 하나 = 파일 하나예요. current-task.json 은 **지금 작업**의 사본(최상위 task 필드)과 handoff 를 들고
# 있어서, 읽는 쪽(HUD · 게이트 · triage)은 예전처럼 current-task.json 만 보면 돼요. 병렬 작업이면 각자
# update-task.sh --task <id> 로 자기 파일만 갱신하고, 지금 작업이 아닌 쪽은 current-task.json 을 건드리지 않아요.
#   goax_task_key <id>          파일 이름에 쓸 키 ([[:alnum:]_.-] 밖은 `_`)
#   goax_task_path <root> <id>  <root>/.ax/tasks/<key>.json
#   GOAX_TASK_FIELDS            작업 필드 — 지금 작업을 바꿀 때 current-task.json 에서 지우고 새 작업 것으로 채워요
GOAX_TASK_FIELDS='["task_id","description","size","risk","domain","spec_id","spec_dir","spec_tier","plan_doc","friction","started_at","updated_at","phase","intent_notes","blocked_by"]'
goax_task_key() { printf '%s' "${1:-}" | tr -c '[:alnum:]_.-' '_'; }
goax_task_path() { printf '%s/.ax/tasks/%s.json' "${1:-.}" "$(goax_task_key "${2:-}")"; }

# ─── 런타임 상태 파일 — .ax/current-task.json · .ax/state.json ─────────────
# 둘 다 gitignore 대상이라 새 워크트리·클론엔 없어요. 워크트리마다 /up 을 다시 돌리게 하지 않고, 쓰는 쪽이
# 처음 쓸 때 설치본에 같이 들어 있는 템플릿을 복사해요. /up 의 seed(MANIFEST `->`)와 같은 원본이라 누가
# 먼저 만들어도 내용이 같아요.
#   goax_runtime_template <file>  그 파일의 템플릿 경로 (런타임 파일이 아니면 1)
#   goax_runtime_seed <file>      없으면 템플릿으로 만들어요 — 0 있음·만듦 · 1 템플릿 없음·복사 실패.
#                                 `ln` 으로 붙여서 이미 생긴 파일(다른 세션이 먼저 만든 것)은 덮지 않아요.
goax_runtime_template() {
    case "${1:-}" in
        *.ax/current-task.json) printf '%s\n' "${1%current-task.json}current-task.json.template" ;;
        *.ax/state.json)        printf '%s\n' "${1%state.json}hud/state.json.template" ;;
        *) return 1 ;;
    esac
}
goax_runtime_seed() {
    local f="${1:-}" tpl tmp
    [ -f "$f" ] && return 0
    tpl=$(goax_runtime_template "$f") && [ -f "$tpl" ] || return 1
    tmp="$f.seed.$$"
    cp "$tpl" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    # 하드링크를 막는 파일 시스템이면 mv 로 — 그 사이 다른 세션이 만들었으면 건드리지 않아요
    if ln "$tmp" "$f" 2>/dev/null || { [ ! -f "$f" ] && mv "$tmp" "$f" 2>/dev/null; }; then
        goax_warn ".ax/${f##*.ax/} 이 없어 템플릿으로 만들었어요 (새 워크트리·클론)"
    fi
    rm -f "$tmp"
    [ -f "$f" ]
}

# goax_glob_owners <path>
#   stdin `<label>\t<glob>` 줄 중 glob 이 path 에 맞는 label 을 처음 나온 순서대로 한 번씩 출력.
#   goax_glob_filter 의 반대 방향(경로 하나 × 글롭 여럿)이고 규칙은 goax_glob_match 와 같아요.
#   python 을 **한 번만** 띄워요 — 글롭마다 goax_glob_match 를 부르면 룰 41개짜리 프로젝트(commerce 실측)에서
#   편집 한 번에 2초가 걸렸어요. 모든 Edit/Read 에 걸리는 훅이라 그대로 두면 세션이 느려져요.
#   python3 가 없으면 goax_glob_match 의 substring degrade 를 줄마다 써요.
goax_glob_owners() {
    local path="${1:-}" label glob
    if goax_py_ok; then
        python3 -c '
import sys, re
path = sys.argv[1]
def glob_to_regex(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == "*":
            if i + 1 < n and g[i+1] == "*":
                out.append(".*"); i += 2
                if i < n and g[i] == "/": i += 1
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c in ".+(){}[]|^$\\":
            out.append("\\" + c)
        else:
            out.append(c)
        i += 1
    return "^" + "".join(out) + "$"
seen = set()
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line:
        continue
    label, glob = line.split("\t", 1)
    if not glob or label in seen:
        continue
    if re.match(glob_to_regex(glob), path):
        seen.add(label); print(label)
' "$path" 2>/dev/null
        return 0
    fi
    local seen=""
    while IFS="$(printf '\t')" read -r label glob; do
        [ -n "$glob" ] || continue
        case " $seen " in *" $label "*) continue ;; esac
        goax_glob_match "$glob" "$path" && { printf '%s\n' "$label"; seen="$seen $label"; }
    done
}

# goax_glob_filter <glob>
#   stdin 의 경로 목록에서 glob 에 맞는 것만 출력. `goax_glob_match` 와 같은 규칙인데
#   python 을 **한 번만** 띄워요 — staged 50개 × 룰 10개를 경로마다 호출하면 프로세스 500개예요.
#   python3 가 없으면 goax_glob_match 와 같은 substring degrade.
goax_glob_filter() {
    local pattern="${1:-}"
    [ -z "$pattern" ] && return 0
    if goax_py_ok; then
        # 스크립트는 -c 로 줘요 — heredoc 으로 주면 그게 stdin 을 차지해서 경로 목록이 안 들어와요.
        python3 -c '
import sys, re
pattern = sys.argv[1]
def glob_to_regex(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == "*":
            if i + 1 < n and g[i+1] == "*":
                out.append(".*"); i += 2
                if i < n and g[i] == "/": i += 1
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c in ".+(){}[]|^$\\":
            out.append("\\" + c)
        else:
            out.append(c)
        i += 1
    return "^" + "".join(out) + "$"
rx = re.compile(glob_to_regex(pattern))
for line in sys.stdin:
    p = line.rstrip("\n")
    if p and rx.match(p):
        print(p)
' "$pattern" 2>/dev/null
        return 0
    fi
    local tail="${pattern##*\*\*/}" p
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        case "$p" in *"$tail"*) printf '%s\n' "$p" ;; esac
    done
}
