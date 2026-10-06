#!/usr/bin/env bash
# .ax/scripts/bash/rules-audit-scope.sh — 룰 대조 리뷰(G7)의 범위: 변경 파일마다 걸린 룰 · 상시 룰 · 새 파일
#
# Usage:
#   bash rules-audit-scope.sh [--spec <id-slug>] [--base <git ref>] [--files a,b,…] [--json] [--help]
#
# 왜 있나 — 편집 시점 훅은 룰 **경로**만 알려주고(spirit-rules-inject.sh · module-rules-inject.sh),
#   rule-read-gate.sh 는 그 파일을 **읽었는지**만 봐요. 읽은 룰을 지켰는지, 새 파일이 이웃 관례(같은 레이어의
#   projection/·vo/·dto/ 같은 위치 · 이름 꼴)를 따랐는지는 아무도 대조하지 않았어요 (commerce 실측: `**/*.kt`
#   이름 룰과 `**/domain/**` 룰이 편집 때 안내됐는데도 위반이 완료 게이트를 통과했어요).
#   완료 직전에 새 컨텍스트의 rules-auditor 가 대조하고, 그 범위를 여기서 기계적으로 정해요 —
#   "어떤 룰이 어느 파일에 걸리나" 를 리뷰어가 직접 grep 하면 빠뜨린 룰은 아무도 몰라요.
#
# 변경 파일 — --files 가 있으면 그것만. 없으면 git 에서:
#   base(--base · 없으면 origin/HEAD → main → master 와의 merge-base)...HEAD + 워킹 트리(스테이징 포함) + 추적 안 되는 새 파일.
#   `.ax/**` 는 빼요 (하네스 자신의 상태·문서예요 — 룰 파일의 ❌ 예시가 룰에 걸려요).
# 파일마다 걸린 룰 — 편집 훅과 **같은 매칭 함수**예요 (goax_rules_matching · goax_module_rules_matching).
#   훅과 다르게 매칭하면 "편집 때 안내한 룰" 과 "완료 때 대조한 룰" 이 갈라져요.
# 상시 룰 — Constitution(AGENTS.md, 없으면 CLAUDE.md) + `paths:` 가 없는 spirit 룰 파일 (경로를 안 가리고 늘 적용).
# 새 파일 — base 이후 추가됐거나 추적 안 되는 파일. 이웃 관례 대조의 대상이에요.
#
# Output (--json):
#   {"status":"ok","result":{"spec":"…","base":"<sha>|null","review_file":".ax/docs/spec/<s>/review-rules.md",
#     "header":"verdict: 진행 | 보강 필요","files":[{"path":"a/B.kt","new":true,"rules":[".ax/spirit/rules/naming.md"]}],
#     "always":["AGENTS.md"],"rule_files":["…합집합…"],"new_files":["a/B.kt"]},…}
#   변경 파일이 0개면 status skipped (exit 2) — 대조할 게 없어요.
# Exit: 0 ok · 1 error (spec 없음 · --spec 모호 · git 아님인데 --files 도 없음) · 2 skipped (jq 없음 · 변경 0)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; SPEC=""; BASE_ARG=""; FILES_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) : ;;                                    # 읽기 전용
        --spec)    shift; SPEC="${1:-}" ;;
        --base)    shift; BASE_ARG="${1:-}" ;;
        --files)   shift; FILES_ARG="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi

fail() { if [ "$JSON_MODE" = true ]; then json_error "$1"; fi; goax_error "$1"; exit "$EXIT_ERROR"; }
if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then json_skip "jq 가 필요해요"; fi
    goax_warn "jq 가 없어 skip"; exit "$EXIT_SKIPPED"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
if [ -z "$SPEC" ] && [ -f "$PROJECT_ROOT/.ax/current-task.json" ]; then
    SD=$(jq -r '.spec_dir // empty' "$PROJECT_ROOT/.ax/current-task.json" 2>/dev/null || true)
    [ -n "$SD" ] && SPEC=$(basename "$SD")
fi
if [ -n "$SPEC" ]; then
    RESOLVED=$(goax_resolve_spec "$SPEC" "$PROJECT_ROOT/.ax/docs/spec") && RC=0 || RC=$?
    if [ "$RC" -eq 0 ]; then SPEC="$RESOLVED"
    elif [ "$RC" -eq 2 ]; then fail "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES} — 하나를 정확히 적으세요"; fi
fi
[ -n "$SPEC" ] && [ -d "$PROJECT_ROOT/.ax/docs/spec/$SPEC" ] || fail "spec 을 찾을 수 없어요: .ax/docs/spec/${SPEC:-<없음>}"
REVIEW_REL=".ax/docs/spec/$SPEC/review-rules.md"

# ── 변경 파일 · 새 파일 ─────────────────────────────────────────
BASE=""; CHANGED=""; NEW=""
if [ -n "$FILES_ARG" ]; then
    CHANGED=$(printf '%s' "$FILES_ARG" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//; s#^\./##')
    # --files 로 받은 것 중 아직 추적 안 되는 파일은 새 파일이에요 (git 이 없으면 새 파일 판정은 비워요)
    if git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        NEW=$(printf '%s\n' "$CHANGED" | while IFS= read -r f; do
                [ -n "$f" ] || continue
                git -C "$PROJECT_ROOT" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || printf '%s\n' "$f"
              done)
    fi
else
    git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
        || fail "git 저장소가 아니에요 — --files a,b 로 변경 파일을 주세요"
    if [ -n "$BASE_ARG" ]; then
        BASE=$(git -C "$PROJECT_ROOT" merge-base HEAD "$BASE_ARG" 2>/dev/null) || fail "--base '$BASE_ARG' 를 HEAD 와 이을 수 없어요"
    else
        for cand in origin/HEAD main master; do
            git -C "$PROJECT_ROOT" rev-parse --verify -q "$cand" >/dev/null 2>&1 || continue
            BASE=$(git -C "$PROJECT_ROOT" merge-base HEAD "$cand" 2>/dev/null || true)
            [ -n "$BASE" ] && break
        done
    fi
    # 프로젝트 기준 상대 경로로 — 모노레포에선 git 루트와 프로젝트 루트가 달라요 (--relative)
    G() { git -C "$PROJECT_ROOT" "$@" 2>/dev/null || true; }
    CHANGED=$( { [ -n "$BASE" ] && G diff --relative --name-only --diff-filter=ACMR "$BASE" HEAD
                 G diff --relative --name-only --diff-filter=ACMR HEAD
                 G ls-files --others --exclude-standard; } | sort -u)
    NEW=$( { [ -n "$BASE" ] && G diff --relative --name-only --diff-filter=A "$BASE" HEAD
             G diff --relative --name-only --diff-filter=A HEAD
             G ls-files --others --exclude-standard; } | sort -u)
fi
CHANGED=$(printf '%s\n' "$CHANGED" | grep -v '^\.ax/' | awk 'NF && !s[$0]++' || true)

if [ -z "$CHANGED" ]; then
    if [ "$JSON_MODE" = true ]; then json_skip "변경 파일이 없어요 (.ax/** 제외) — 대조할 게 없어요"; fi
    goax_log "변경 파일 없음 — 대조할 게 없어요"; exit "$EXIT_SKIPPED"
fi

# ── 파일마다 걸린 룰 — 편집 훅과 같은 함수 ────────────────────────
SPIRIT_DIR="$PROJECT_ROOT/.ax/spirit/rules"
ROWS=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    rules=$( { goax_rules_matching "$SPIRIT_DIR" "$f" ".ax/spirit/rules/"
               goax_module_rules_matching "$PROJECT_ROOT" "$f" | sed 's#^\(.*\)$#.ax/modules/\1/rules.md#'; } | awk 'NF && !s[$0]++' | paste -sd, -)
    isnew=false; printf '%s\n' "$NEW" | grep -qxF -- "$f" && isnew=true
    ROWS="${ROWS}${f}"$'\t'"${isnew}"$'\t'"${rules}"$'\n'
done <<EOF
$CHANGED
EOF

# ── 상시 룰 — Constitution + paths: 없는 spirit 룰 ─────────────────
ALWAYS=""
if [ -f "$PROJECT_ROOT/AGENTS.md" ]; then ALWAYS="AGENTS.md"
elif [ -f "$PROJECT_ROOT/CLAUDE.md" ]; then ALWAYS="CLAUDE.md"; fi
if [ -d "$SPIRIT_DIR" ]; then
    for rf in "$SPIRIT_DIR"/*.md; do
        [ -f "$rf" ] || continue
        case "$(basename "$rf")" in README.md) continue ;; esac
        [ -n "$(goax_yaml_list "$rf" paths)" ] && continue
        ALWAYS="${ALWAYS:+$ALWAYS
}.ax/spirit/rules/$(basename "$rf")"
    done
fi

RESULT=$(printf '%s' "$ROWS" | jq -Rn --arg spec "$SPEC" --arg base "$BASE" --arg rf "$REVIEW_REL" --arg always "$ALWAYS" '
    [inputs | select(length > 0) | split("\t") | {path: .[0], new: (.[1] == "true"),
        rules: ((.[2] // "") | split(",") | map(select(length > 0)))}] as $files
    | ($always | split("\n") | map(select(length > 0))) as $al
    | {spec: $spec, base: (if $base == "" then null else $base end), review_file: $rf,
       header: "verdict: 진행 | 보강 필요",
       files: $files, always: $al,
       rule_files: (($files | map(.rules[]) + $al) | unique),
       new_files: ($files | map(select(.new) | .path))}')

N_FILES=$(printf '%s' "$RESULT" | jq '.files | length')
N_RULES=$(printf '%s' "$RESULT" | jq '.rule_files | length')
N_NEW=$(printf '%s' "$RESULT" | jq '.new_files | length')
NEXT="변경 ${N_FILES}개 · 대조할 룰 파일 ${N_RULES}개 · 새 파일 ${N_NEW}개 — 이 결과를 브리프로 rules-auditor 를 새 컨텍스트로 띄워 ${REVIEW_REL} 첫 줄에 verdict 를 받으세요"
if [ "$JSON_MODE" = true ]; then
    json_output "ok" "$RESULT" "$NEXT"
else
    printf '%s\n' "$RESULT" | jq -r '"base: \(.base // "없음 (워킹 트리만)")",
        (.files[] | "  \(.path)\(if .new then " (새 파일)" else "" end) ← \(if (.rules|length) > 0 then (.rules|join(", ")) else "경로 룰 없음" end)"),
        "상시: \(.always | join(", "))", "리뷰 파일: \(.review_file)"'
fi
exit "$EXIT_OK"
