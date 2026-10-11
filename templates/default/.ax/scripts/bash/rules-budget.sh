#!/usr/bin/env bash
# .ax/scripts/bash/rules-budget.sh — 룰이 세션에 얼마나 실리는지 재요 (rule skill 압축 모드 · doctor 가 불러요)
#
# Usage: bash rules-budget.sh [--json] [--sample <N>]
#
# 재는 것:
#   always  세션 시작부터 실리는 글 — CLAUDE.md · CLAUDE.local.md 와 `@` import 를 5단계까지 따라간 파일의 줄 수와 바이트
#           (doctor-scan 의 budget 과 같은 파일 목록이에요 — goax_always_loaded)
#   files   룰 파일(.ax/spirit/rules/*.md · .ax/modules/*/rules.md)마다 줄 · 바이트 · SP 수 · 펜스 줄 비율
#   edit    추적 파일마다 편집 전에 Read 해야 하는 룰 파일(paths 매칭, always 에 든 파일 제외)의 바이트 합 — p50 · p90 · max
#           파일이 --sample 개(기본 3000)보다 많으면 같은 간격으로 골라서 재요. python3 가 없으면 edit 는 null 이에요.
# 기준값: 상시 300줄 또는 16KB (goax 기본 설치가 약 220줄 · 11.5KB) · 파일 150줄 또는 8KB · 편집 p90 24KB · 펜스 30% 이상.
# 기준을 넘은 항목은 over_budget[] 에 {kind, target, value, limit} 로 들어가요. 이 스크립트는 판정만 하고 고치지 않아요.
#
# Output (--json):
#   {"status":"ok","result":{"always":{"lines":394,"bytes":19000,"files":["CLAUDE.md","AGENTS.md"]},
#     "files":[{"file":"…","lines":120,"bytes":7000,"rules":9,"fence_ratio":0.12}],
#     "edit":{"tracked":7315,"sampled":2439,"p50":8000,"p90":24000,"max":32000,"max_file":"…"}|null,
#     "over_budget":[{"kind":"always|file_lines|file_bytes|fence|edit_p90","target":"…","value":0,"limit":0}]},…}
# Exit: 0 ok · 1 error · 2 skipped (jq 없음)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; SAMPLE=3000
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) ;;                           # 읽기 전용 — 표준 옵션 호환
        --sample)  shift; SAMPLE="${1:-3000}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
command -v jq >/dev/null 2>&1 || { [ "$JSON_MODE" = true ] && printf '{"status":"skipped","result":{},"next_step":"jq 가 필요해요","warnings":["jq not found"],"errors":[]}\n'; exit "$EXIT_SKIPPED"; }
case "$SAMPLE" in ''|*[!0-9]*) goax_error "--sample 은 숫자예요"; exit "$EXIT_ERROR" ;; esac

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT" || exit "$EXIT_ERROR"
LIM_ALWAYS_LINES=300; LIM_ALWAYS_BYTES=16384; LIM_FILE_LINES=150; LIM_FILE_BYTES=8192; LIM_EDIT_P90=24576; LIM_FENCE=30
WARN=()

# ── 상시 로드 ──────────────────────────────────────────────────────
ALWAYS_FILES=$(goax_always_loaded "$PROJECT_ROOT")
A_LINES=0; A_BYTES=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    A_LINES=$(( A_LINES + $(wc -l < "$f") )); A_BYTES=$(( A_BYTES + $(wc -c < "$f") ))
done <<< "$ALWAYS_FILES"

# ── 룰 파일마다 ────────────────────────────────────────────────────
RULE_FILES=()
for f in .ax/spirit/rules/*.md .ax/modules/*/rules.md; do
    [ -f "$f" ] || continue
    [ "$f" = .ax/spirit/rules/README.md ] && continue
    RULE_FILES+=("$f")
done
FILES_TSV=""
# awk length 는 C 로케일에서 바이트예요 (common.sh 가 LC_COLLATE 만 고정하므로 여기서 LC_ALL 을 줘요)
[ ${#RULE_FILES[@]} -gt 0 ] && FILES_TSV=$(LC_ALL=C awk '
        function flush() { if (name != "") printf "%s\t%d\t%d\t%d\t%d\n", name, lines, bytes, rules, fenced }
        FNR == 1 { flush(); name = FILENAME; lines = 0; bytes = 0; rules = 0; fenced = 0; fence = 0 }
        { lines++; bytes += length($0) + 1 }
        /^[[:space:]]*(```|~~~)/ { fence = !fence; fenced++; next }
        fence { fenced++; next }
        /^## SP-[[:upper:][:digit:]]+-[[:digit:]]+:/ { rules++ }
        END { flush() }' "${RULE_FILES[@]}")
FILES_JSON=$(printf '%s\n' "$FILES_TSV" | jq -Rn '[inputs | select(length>0) | split("\t")
    | {file:.[0], lines:(.[1]|tonumber), bytes:(.[2]|tonumber), rules:(.[3]|tonumber),
       fence_ratio:(if (.[1]|tonumber) == 0 then 0 else (((.[4]|tonumber) / (.[1]|tonumber)) * 100 | floor) / 100 end)}]')

# ── 편집당 Read 부담 ───────────────────────────────────────────────
EDIT_JSON=null
if [ ${#RULE_FILES[@]} -gt 0 ] && goax_py_ok && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # 룰 파일 → paths 글롭. 모듈 룰은 applies_to 에 code 가 없으면 편집 대상이 아니라 빼요 (goax_module_rules_matching 과 같아요)
    GLOBS=$(_goax_yaml_list_multi paths "${RULE_FILES[@]}")
    NOCODE=$(_goax_yaml_list_multi applies_to "${RULE_FILES[@]}" \
        | awk -F '\t' '{ has[$1] = 1; if ($2 == "code") code[$1] = 1 } END { for (f in has) if (!(f in code)) print f }')
    # 파일이 많으면 같은 간격으로 SAMPLE 개를 골라요 — 앞에서부터 자르면 알파벳 앞쪽 디렉토리만 재요
    TRACKED=$(git -c core.quotepath=off ls-files 2>/dev/null | grep -v '^\.ax/' || true)
    TOTAL=$(printf '%s\n' "$TRACKED" | grep -c . || true)
    STEP=$(( TOTAL > SAMPLE && SAMPLE > 0 ? (TOTAL + SAMPLE - 1) / SAMPLE : 1 ))
    EDIT_JSON=$(printf '%s\n' "$TRACKED" | awk -v s="$STEP" 'NF && (NR - 1) % s == 0' \
        | GOAX_GLOBS="$GLOBS" GOAX_NOCODE="$NOCODE" GOAX_IMPORTED="$ALWAYS_FILES" GOAX_TOTAL="$TOTAL" python3 -c '
import os, re, sys, json
def rx(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == "*":
            if i + 1 < n and g[i+1] == "*":
                out.append(".*"); i += 2
                if i < n and g[i] == "/": i += 1
                continue
            out.append("[^/]*")
        elif c == "?": out.append("[^/]")
        elif c in ".+(){}[]|^$\\": out.append("\\" + c)
        else: out.append(c)
        i += 1
    return re.compile("^" + "".join(out) + "$")
nocode = set(x for x in os.environ.get("GOAX_NOCODE", "").splitlines() if x)
imported = set(x for x in os.environ.get("GOAX_IMPORTED", "").splitlines() if x)
rules = {}
for line in os.environ.get("GOAX_GLOBS", "").splitlines():
    if "\t" not in line: continue
    f, g = line.split("\t", 1)
    if f in nocode or f in imported: continue
    rules.setdefault(f, []).append(rx(g))
size = {f: os.path.getsize(f) for f in rules}
totals = []
for p in sys.stdin.read().splitlines():
    t = sum(size[f] for f, gs in rules.items() if any(r.match(p) for r in gs))
    totals.append((t, p))
if not totals:
    print("null"); sys.exit(0)
vals = sorted(t for t, _ in totals)
def pct(q): return vals[min(len(vals) - 1, int(q * len(vals)))]
mx = max(totals)
print(json.dumps({"tracked": int(os.environ.get("GOAX_TOTAL", "0")), "sampled": len(vals), "p50": pct(0.5), "p90": pct(0.9), "max": mx[0], "max_file": mx[1]}))
') || EDIT_JSON=null
    [ -n "$EDIT_JSON" ] || EDIT_JSON=null
else
    [ ${#RULE_FILES[@]} -gt 0 ] && WARN+=("python3 나 git 이 없어 편집당 부담(edit)은 재지 않았어요")
fi

ALWAYS_JSON=$(jq -nc --argjson l "$A_LINES" --argjson b "$A_BYTES" --arg fs "$ALWAYS_FILES" \
    '{lines:$l, bytes:$b, files:($fs | split("\n") | map(select(length>0)))}')
OVER=$(jq -nc --argjson a "$ALWAYS_JSON" --argjson fs "$FILES_JSON" --argjson e "$EDIT_JSON" \
    --argjson al "$LIM_ALWAYS_LINES" --argjson ab "$LIM_ALWAYS_BYTES" --argjson fl "$LIM_FILE_LINES" \
    --argjson fb "$LIM_FILE_BYTES" --argjson ep "$LIM_EDIT_P90" --argjson fe "$LIM_FENCE" '
    [ (if $a.lines > $al then {kind:"always", target:"lines", value:$a.lines, limit:$al} else empty end),
      (if $a.bytes > $ab then {kind:"always", target:"bytes", value:$a.bytes, limit:$ab} else empty end),
      ($fs[] | (if .lines > $fl then {kind:"file_lines", target:.file, value:.lines, limit:$fl} else empty end),
               (if .bytes > $fb then {kind:"file_bytes", target:.file, value:.bytes, limit:$fb} else empty end),
               (if (.fence_ratio * 100) >= $fe then {kind:"fence", target:.file, value:(.fence_ratio * 100 | floor), limit:$fe} else empty end)),
      (if $e != null and $e.p90 > $ep then {kind:"edit_p90", target:$e.max_file, value:$e.p90, limit:$ep} else empty end) ]')
RESULT=$(jq -nc --argjson a "$ALWAYS_JSON" --argjson fs "$FILES_JSON" --argjson e "$EDIT_JSON" --argjson o "$OVER" \
    '{always:$a, files:$fs, edit:$e, over_budget:$o}')
N_OVER=$(printf '%s' "$OVER" | jq 'length')
NEXT_STEP=""
[ "$N_OVER" -gt 0 ] && NEXT_STEP="기준을 넘은 항목이 ${N_OVER}개예요. rule skill 압축 모드로 줄여요 (bash .ax/scripts/bash/rules-compress.sh --snapshot)"

if [ "$JSON_MODE" = true ]; then
    WJ=$(printf '%s\n' ${WARN[@]+"${WARN[@]}"} | jq -Rn '[inputs|select(length>0)]')
    jq -nc --argjson r "$RESULT" --arg n "$NEXT_STEP" --argjson w "$WJ" \
        '{status:"ok", result:$r, next_step:$n, warnings:$w, errors:[]}'
else
    printf '%s\n' "$RESULT" | jq .
    [ -n "$NEXT_STEP" ] && goax_log "$NEXT_STEP"
fi
exit "$EXIT_OK"
