#!/usr/bin/env bash
# .ax/scripts/bash/spec-review.sh — spec 합의 리뷰 원장. 스냅샷 sha 고정 · 리뷰어별 verdict 집계 · 합본
#
# Usage:
#   bash spec-review.sh [--spec <NNN-slug>] --snapshot [--json]   # spec.md sha 고정 + 라운드 +1, 리뷰어 파일 경로 안내
#   bash spec-review.sh [--spec <NNN-slug>] --status   [--json]   # 두 리뷰 파일의 verdict·sha 를 집계 → pass 여부
#   bash spec-review.sh [--spec <NNN-slug>] --merge    [--json]   # review-spec.md 합본 생성 (사람이 읽는 용)
#
# 왜 필요한가 — 계획의 품질은 diff 시점이 아니라 계획 시점에 리뷰해야 올라가요. 그런데 리뷰어
# 둘(architect · evaluator)이 한 파일에 쓰면 (a) 첫 줄 verdict 하나로 "둘 다 진행" 을 표현할 수
# 없고 (b) 뒤에 쓰는 쪽이 앞 절을 읽게 돼 독립성이 깨져요. 그래서 **리뷰어별 파일**이고, 이 스크립트가
# 둘을 집계해요. 리뷰어는 자기 파일 경로만 받아요.
#
# 파일 (스크립트가 쓰는 것 / 리뷰어가 쓰는 것):
#   <spec>/.review-round              라운드 번호 + 스냅샷 sha  ← --snapshot 이 씀
#   <spec>/review-spec.architect.md   architect 가 직접 씀 — 1줄 `verdict: 진행|보강 필요|재논의 필요` · 2줄 `sha: <12자>`
#   <spec>/review-spec.evaluator.md   evaluator 가 직접 씀 — 같은 형식
#   <spec>/review-spec.md             --merge 가 생성 (합본)
#
# 통과 조건 (--status 의 pass):
#   required=none (size S)        → pass. 리뷰 대상이 아니에요
#   required=optional (size M)    → 파일이 하나도 없으면 pass (선택). 하나라도 있으면 아래 규칙
#   required=required (size L/XL) → 두 파일 모두 있고, 둘 다 `진행`, 둘 다 sha 가 현재 spec.md 와 같아야 pass
#   sha 불일치 = 리뷰 뒤에 spec 이 바뀜 = 그쪽만 다시 받아요
#
# 필수 여부의 SSOT 는 tier-from-state.sh 의 `spec_review` 필드예요 (Size 축만: L/XL 필수 · M 선택 · S 없음).
# 활성 spec 이 아니면 <spec>/.tier 로 근사해요 (full → required, standard → optional).
#
# Output (--json):
#   {"status":"ok|warning","result":{"spec":"014-x","sha":"…","required":"required","round":2,
#     "architect":{"present":true,"verdict":"진행","sha":"…","sha_match":true,"file":"…"},
#     "evaluator":{…},"pass":false,"reason":"…"},…}
#
# Exit: 0 ok · 1 error · 2 skipped (jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; MODE=""; SPEC=""; MAX_ROUNDS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  : ;;                       # --status·--merge 는 읽기, --snapshot 은 원장 한 줄
        --snapshot) MODE="snapshot" ;;
        --status)   MODE="status" ;;
        --merge)    MODE="merge" ;;
        --spec)     shift; SPEC="${1:-}" ;;
        --max-rounds) shift; MAX_ROUNDS="${1:-3}" ;;
        --help|-h)  SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "$EXIT_OK"
fi
[ -n "$MODE" ] || MODE="status"

if [ "$JSON_MODE" = true ] && ! command -v jq >/dev/null 2>&1; then
    printf '{"status":"skipped","result":{},"next_step":"jq 가 필요해요","warnings":["jq not found"],"errors":[]}\n'
    exit "$EXIT_SKIPPED"
fi

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"

fail() {
    if [ "$JSON_MODE" = true ]; then json_error "$1"; fi
    goax_error "$1"; exit "$EXIT_ERROR"
}

ACTIVE_SPEC=""
if command -v jq >/dev/null 2>&1 && [ -f "$PROJECT_ROOT/.ax/current-task.json" ]; then
    SD=$(jq -r '.spec_dir // empty' "$PROJECT_ROOT/.ax/current-task.json" 2>/dev/null || true)
    [ -n "$SD" ] && ACTIVE_SPEC=$(basename "$SD")
fi
[ -z "$SPEC" ] && SPEC="$ACTIVE_SPEC"
SPEC_DIR="$PROJECT_ROOT/.ax/docs/spec/$SPEC"
[ -n "$SPEC" ] && [ -f "$SPEC_DIR/spec.md" ] || fail "spec.md 를 찾을 수 없어요: .ax/docs/spec/${SPEC:-<없음>}/spec.md"

A_FILE="$SPEC_DIR/review-spec.architect.md"
E_FILE="$SPEC_DIR/review-spec.evaluator.md"
ROUND_FILE="$SPEC_DIR/.review-round"

spec_sha() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -c1-12
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-12
    else printf 'nosha'; fi
}
SHA=$(spec_sha "$SPEC_DIR/spec.md")

# 필수 여부 — 활성 spec 이면 tier-from-state.sh (SSOT), 아니면 .tier 근사
REQUIRED=""
if [ "$SPEC" = "$ACTIVE_SPEC" ] && command -v jq >/dev/null 2>&1; then
    REQUIRED=$(bash "$SCRIPT_DIR/tier-from-state.sh" --json 2>/dev/null | jq -r '.result.spec_review // empty' 2>/dev/null || true)
fi
if [ -z "$REQUIRED" ]; then
    TIER=$(cat "$SPEC_DIR/.tier" 2>/dev/null | tr -d '[:space:]' || true)
    case "$TIER" in full) REQUIRED="required" ;; standard) REQUIRED="optional" ;; *) REQUIRED="optional" ;; esac
fi

ROUND=0
[ -f "$ROUND_FILE" ] && ROUND=$(awk -F'|' 'NR==1{print $1+0}' "$ROUND_FILE" 2>/dev/null || echo 0)

# 리뷰 파일 파싱 → "present|verdict|sha"
parse_review() {
    local f="$1" v="" s=""
    [ -f "$f" ] || { printf 'false||'; return; }
    v=$(grep -m1 -E '^verdict:' "$f" 2>/dev/null | sed -E 's/^verdict:[[:space:]]*//; s/[[:space:]]+$//' || true)
    s=$(grep -m1 -E '^sha:' "$f" 2>/dev/null | sed -E 's/^sha:[[:space:]]*//; s/[[:space:]]+$//' || true)
    printf 'true|%s|%s' "$v" "$s"
}

case "$MODE" in
  snapshot)
    ROUND=$((ROUND + 1))
    printf '%s|%s|%s\n' "$ROUND" "$SHA" "$(date -u +%Y-%m-%dT%H:%MZ)" > "$ROUND_FILE"
    WARN='[]'
    if [ "$ROUND" -gt "$MAX_ROUNDS" ] && command -v jq >/dev/null 2>&1; then
        WARN=$(_goax_json_array "라운드 ${ROUND} — 상한 ${MAX_ROUNDS} 을 넘었어요. 리뷰를 더 돌리기보다 spec 을 다시 정의하거나 사용자 결정을 받으세요")
    fi
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg sha "$SHA" --arg req "$REQUIRED" --argjson round "$ROUND" \
            --arg a "$A_FILE" --arg e "$E_FILE" --arg s "$SPEC_DIR/spec.md" \
            '{spec:$spec, sha:$sha, required:$req, round:$round, spec_file:$s,
              architect_file:$a, evaluator_file:$e,
              header:("verdict: 진행 | 보강 필요 | 재논의 필요\nsha: " + $sha)}')
        json_output "ok" "$RESULT" "architect → evaluator 순서로, 각자 자기 파일에만 쓰게 띄우세요. 상대 파일은 브리프에 넣지 않아요" "$WARN"
    else
        printf 'spec %s — round %s · sha %s · %s\n  architect → %s\n  evaluator → %s\n  첫 줄: verdict: 진행 | 보강 필요 | 재논의 필요\n  둘째 줄: sha: %s\n' \
            "$SPEC" "$ROUND" "$SHA" "$REQUIRED" "$A_FILE" "$E_FILE" "$SHA"
    fi
    ;;
  status|merge)
    IFS='|' read -r A_P A_V A_S <<EOF
$(parse_review "$A_FILE")
EOF
    IFS='|' read -r E_P E_V E_S <<EOF
$(parse_review "$E_FILE")
EOF
    A_M=false; E_M=false
    [ "$A_P" = true ] && [ "$A_S" = "$SHA" ] && A_M=true
    [ "$E_P" = true ] && [ "$E_S" = "$SHA" ] && E_M=true

    PASS=false; REASON=""
    if [ "$REQUIRED" = "none" ]; then
        PASS=true; REASON="size S — 합의 리뷰 대상이 아니에요"
    elif [ "$REQUIRED" = "optional" ] && [ "$A_P" = false ] && [ "$E_P" = false ]; then
        PASS=true; REASON="size M — 선택. 리뷰 없이 통과 (--consensus 로 강제할 수 있어요)"
    elif [ "$A_P" = false ] || [ "$E_P" = false ]; then
        MISSING=""; [ "$A_P" = false ] && MISSING="architect "; [ "$E_P" = false ] && MISSING="${MISSING}evaluator"
        REASON="리뷰 파일 없음: ${MISSING% } — --snapshot 뒤 리뷰어를 띄우세요"
    elif [ "$A_M" = false ] || [ "$E_M" = false ]; then
        STALE=""; [ "$A_M" = false ] && STALE="architect "; [ "$E_M" = false ] && STALE="${STALE}evaluator"
        REASON="sha 불일치: ${STALE% } — 리뷰 뒤에 spec.md 가 바뀌었어요. 그쪽만 다시 받으세요"
    elif [ "$A_V" != "진행" ] || [ "$E_V" != "진행" ]; then
        REASON="verdict — architect '${A_V:-?}' · evaluator '${E_V:-?}'. 지적을 spec 에 반영하고 --snapshot 부터 다시"
    else
        PASS=true; REASON="둘 다 진행 · sha 일치 (round ${ROUND})"
    fi

    if [ "$MODE" = "merge" ]; then
        OUT="$SPEC_DIR/review-spec.md"
        {
            printf '# review-spec — %s (round %s · sha %s · %s)\n\n' "$SPEC" "$ROUND" "$SHA" "$REQUIRED"
            printf 'pass: %s — %s\n\n' "$PASS" "$REASON"
            for who in architect evaluator; do
                f="$SPEC_DIR/review-spec.$who.md"
                printf '## %s\n\n' "$who"
                if [ -f "$f" ]; then cat "$f"; else printf '_(없음)_\n'; fi
                printf '\n'
            done
        } > "$OUT"
    fi

    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg sha "$SHA" --arg req "$REQUIRED" --argjson round "$ROUND" \
            --argjson ap "$A_P" --arg av "$A_V" --arg as "$A_S" --argjson am "$A_M" --arg af "$A_FILE" \
            --argjson ep "$E_P" --arg ev "$E_V" --arg es "$E_S" --argjson em "$E_M" --arg ef "$E_FILE" \
            --argjson pass "$PASS" --arg reason "$REASON" --arg mode "$MODE" \
            '{spec:$spec, sha:$sha, required:$req, round:$round, mode:$mode,
              architect:{present:$ap, verdict:(if $av=="" then null else $av end), sha:(if $as=="" then null else $as end), sha_match:$am, file:$af},
              evaluator:{present:$ep, verdict:(if $ev=="" then null else $ev end), sha:(if $es=="" then null else $es end), sha_match:$em, file:$ef},
              pass:$pass, reason:$reason}')
        if [ "$PASS" = true ]; then json_output "ok" "$RESULT" "$REASON"; else json_output "warning" "$RESULT" "$REASON"; fi
    else
        printf 'spec %s — round %s · sha %s · %s\n' "$SPEC" "$ROUND" "$SHA" "$REQUIRED"
        printf '  architect  %s\n' "$([ "$A_P" = true ] && printf '%s (sha %s%s)' "${A_V:-?}" "$A_S" "$([ "$A_M" = true ] && echo ' ✓' || echo ' ✗')" || echo '없음')"
        printf '  evaluator  %s\n' "$([ "$E_P" = true ] && printf '%s (sha %s%s)' "${E_V:-?}" "$E_S" "$([ "$E_M" = true ] && echo ' ✓' || echo ' ✗')" || echo '없음')"
        printf '  pass: %s — %s\n' "$PASS" "$REASON"
        [ "$MODE" = "merge" ] && printf '  합본: %s\n' "$SPEC_DIR/review-spec.md"
    fi
    ;;
esac
exit "$EXIT_OK"
