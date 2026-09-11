#!/usr/bin/env bash
# .ax/scripts/bash/spec-review.sh — spec 합의 리뷰 원장. 스냅샷 sha 고정 · 리뷰어별 verdict 집계 · 합본
#
# Usage:
#   bash spec-review.sh [--spec <NNN-slug>] --snapshot [--dry-run] [--json]   # sha 고정 + 라운드 +1, 리뷰어 파일 경로 안내
#   bash spec-review.sh [--spec <NNN-slug>] --status            [--json]      # 두 리뷰 파일의 verdict·sha 를 집계 → pass 여부
#   bash spec-review.sh [--spec <NNN-slug>] --merge   [--dry-run] [--json]    # review-spec.md 합본 생성 (사람이 읽는 용)
#
# 왜 필요한가 — 계획의 품질은 diff 시점이 아니라 계획 시점에 리뷰해야 올라가요. 그런데 리뷰어
# 둘(architect · evaluator)이 한 파일에 쓰면 (a) 첫 줄 verdict 하나로 "둘 다 진행" 을 표현할 수
# 없고 (b) 뒤에 쓰는 쪽이 앞 절을 읽게 돼 독립성이 깨져요. 그래서 **리뷰어별 파일**이고, 이 스크립트가
# 둘을 집계해요. 리뷰어는 자기 파일 경로만 받아요.
#
# 파일 (스크립트가 쓰는 것 / 리뷰어가 쓰는 것):
#   <spec>/.review-round              라운드|합산sha|시각|spec.md sha|tasks.md sha  ← --snapshot 이 씀
#   <spec>/review-spec.architect.md   architect 가 직접 씀 — 1줄 `verdict: 진행|보강 필요|재논의 필요` · 2줄 `sha: <12자>`
#   <spec>/review-spec.evaluator.md   evaluator 가 직접 씀 — 같은 형식
#   <spec>/review-spec.md             --merge 가 생성 (합본)
#
# sha 는 **spec.md + tasks.md 합산**이에요. spec.md 만 보면 리뷰 뒤에 tasks.md 를 통째로
# 갈아끼워도 pass 가 유지돼서, "L/XL 은 evaluator 가 tasks.md 까지 본다" 가 no-op 이 돼요.
# tasks.md 가 아직 없으면 spec.md 만으로 계산하고, 생기는 순간 sha 가 바뀌어요 (그게 맞아요 —
# 리뷰어가 본 것과 지금이 다르니까).
#
# 통과 조건 (--status 의 pass):
#   required=none (size S)        → pass. 리뷰 대상이 아니에요
#   required=optional (size M)    → 파일이 하나도 없으면 pass (선택). 하나라도 있으면 아래 규칙
#   required=required (size L/XL) → 두 파일 모두 있고, 둘 다 `진행`, 둘 다 sha 가 현재와 같아야 pass
#   sha 불일치 = 리뷰 뒤에 spec/tasks 가 바뀜 = 그쪽만 다시 받아요 (어느 파일인지 알려줘요)
#
# 필수 여부의 SSOT 는 tier-from-state.sh 의 `spec_review` 필드예요 (Size 축만: L/XL 필수 · M 선택 · S 없음).
# 활성 spec 이 아니거나 SSOT 조회가 실패하면 <spec>/.tier 의 `tier:` 키로 **보수적으로** 근사해요
# (full → required · standard → optional · 값이 없으면 required). 판정 못 한 걸 optional 로
# 열어 두면 가장 큰 spec 이 가장 조용히 통과해요 — 그래서 모르면 닫는 쪽이에요.
# 근거는 result 의 `required_source` 에 적어요.
#
# --dry-run 은 아무 파일도 안 써요 (--snapshot 의 .review-round, --merge 의 review-spec.md).
# 라운드가 상한(--max-rounds, 기본 3)을 넘으면 status: warning 으로 알려요. 차단은 안 해요 —
# 계속할지 멈출지는 skill 의 판단이라 exit 는 0 이에요.
#
# Output (--json):
#   {"status":"ok|warning","result":{"spec":"014-x","sha":"…","spec_sha":"…","tasks_sha":"…",
#     "required":"required","required_source":"size L · tier-from-state","round":2,
#     "changed_files":["tasks.md"],
#     "architect":{"present":true,"verdict":"진행","sha":"…","sha_match":true,"file":"…"},
#     "evaluator":{…},"pass":false,"reason":"…"},…}
#
# Exit: 0 ok (pass 여부와 무관 — 판단은 caller) · 1 error (spec.md 없음 · --spec 모호) · 2 skipped (jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false; MODE=""; SPEC=""; MAX_ROUNDS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  DRY_RUN=true ;;
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
    goax_help "${BASH_SOURCE[0]}"
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

# --spec 해석은 공통 규칙 (정확 일치 → prefix 1개 → 실패)
if [ -n "$SPEC" ]; then
    RESOLVED=$(goax_resolve_spec "$SPEC" "$PROJECT_ROOT/.ax/docs/spec") && RC=0 || RC=$?
    if [ "$RC" -eq 0 ]; then SPEC="$RESOLVED"
    elif [ "$RC" -eq 2 ]; then
        fail "--spec '$SPEC' 이 여러 spec 에 걸려요: ${GOAX_SPEC_CANDIDATES} — 하나를 정확히 적으세요"
    fi
fi

SPEC_DIR="$PROJECT_ROOT/.ax/docs/spec/$SPEC"
[ -n "$SPEC" ] && [ -f "$SPEC_DIR/spec.md" ] || fail "spec.md 를 찾을 수 없어요: .ax/docs/spec/${SPEC:-<없음>}/spec.md"

A_FILE="$SPEC_DIR/review-spec.architect.md"
E_FILE="$SPEC_DIR/review-spec.evaluator.md"
ROUND_FILE="$SPEC_DIR/.review-round"

sha_file() {
    [ -f "$1" ] || { printf ''; return 0; }
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -c1-12
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-12
    else printf 'nosha'; fi
}
sha_str() {
    if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | cut -c1-12
    elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -c1-12
    else printf 'nosha'; fi
}

SPEC_SHA=$(sha_file "$SPEC_DIR/spec.md")
TASKS_SHA=$(sha_file "$SPEC_DIR/tasks.md")
SHA=$(sha_str "spec:${SPEC_SHA}|tasks:${TASKS_SHA}")

# 필수 여부 — 활성 spec 이면 tier-from-state.sh (SSOT), 아니면 .tier 로 보수적 근사
REQUIRED=""; REQ_SRC=""
if [ "$SPEC" = "$ACTIVE_SPEC" ] && command -v jq >/dev/null 2>&1; then
    TFS=$(bash "$SCRIPT_DIR/tier-from-state.sh" --json 2>/dev/null || true)
    REQUIRED=$(printf '%s' "$TFS" | jq -r '.result.spec_review // empty' 2>/dev/null || true)
    if [ -n "$REQUIRED" ]; then
        SZ=$(printf '%s' "$TFS" | jq -r '.result.size // empty' 2>/dev/null || true)
        REQ_SRC="tier-from-state${SZ:+ · size $SZ}"
    fi
fi
if [ -z "$REQUIRED" ]; then
    # .tier 는 3줄 YAML (tier: full / created_at: … / files: N) — 통째로 비교하면 영원히 안 걸려요
    TIER=$(awk -F: '/^[[:space:]]*tier:/{v=$2; gsub(/[[:space:]]/,"",v); print v; exit}' "$SPEC_DIR/.tier" 2>/dev/null || true)
    case "$TIER" in
        full)     REQUIRED="required"; REQ_SRC=".tier=full — 근사(비활성 spec)" ;;
        standard) REQUIRED="optional"; REQ_SRC=".tier=standard — 근사(비활성 spec)" ;;
        *)        REQUIRED="required"; REQ_SRC=".tier 를 못 읽음 — 보수적으로 필수(비활성 spec). 이 spec 을 활성화하거나 .tier 에 tier: 를 적으세요" ;;
    esac
fi

# .review-round: 라운드|합산sha|시각|spec.md sha|tasks.md sha
ROUND=0; SNAP_SPEC_SHA=""; SNAP_TASKS_SHA=""
if [ -f "$ROUND_FILE" ]; then
    IFS='|' read -r R_R _R_SHA _R_TIME SNAP_SPEC_SHA SNAP_TASKS_SHA <<EOF
$(head -1 "$ROUND_FILE" 2>/dev/null || true)
EOF
    # 빈 파일·깨진 줄이면 0 — --argjson round "" 는 jq 를 죽여요 (stdout 없이 exit 2)
    case "${R_R:-}" in ''|*[!0-9]*) ROUND=0 ;; *) ROUND="$R_R" ;; esac
fi
ROUND=${ROUND:-0}

# 스냅샷 이후 무엇이 바뀌었나 — sha 불일치의 원인을 파일 단위로 짚어줘요
CHANGED_FILES=""
[ -n "$SNAP_SPEC_SHA" ]  && [ "$SNAP_SPEC_SHA"  != "$SPEC_SHA" ]  && CHANGED_FILES="spec.md "
[ -n "$SNAP_TASKS_SHA" ] && [ "$SNAP_TASKS_SHA" != "$TASKS_SHA" ] && CHANGED_FILES="${CHANGED_FILES}tasks.md "
CHANGED_FILES="${CHANGED_FILES% }"

# 리뷰 파일 파싱 → "present|verdict|sha" (verdict 는 첫 줄, sha 는 둘째 줄이 계약)
parse_review() {
    local f="$1" v="" s=""
    [ -f "$f" ] || { printf 'false||'; return; }
    v=$(head -1 "$f" 2>/dev/null | sed -n 's/^verdict:[[:space:]]*//p' | sed -E 's/[[:space:]]+$//' || true)
    s=$(head -3 "$f" 2>/dev/null | sed -n 's/^sha:[[:space:]]*//p' | head -1 | sed -E 's/[[:space:]]+$//' || true)
    printf 'true|%s|%s' "$v" "$s"
}

case "$MODE" in
  snapshot)
    ROUND=$((ROUND + 1))
    if [ "$DRY_RUN" != true ]; then
        printf '%s|%s|%s|%s|%s\n' "$ROUND" "$SHA" "$(date -u +%Y-%m-%dT%H:%MZ)" "$SPEC_SHA" "$TASKS_SHA" > "$ROUND_FILE"
    fi
    OVER=false; WARN='[]'; WARN_MSG=""
    if [ "$ROUND" -gt "$MAX_ROUNDS" ]; then
        OVER=true
        WARN_MSG="라운드 ${ROUND} — 상한 ${MAX_ROUNDS} 을 넘었어요. 리뷰를 더 돌리기보다 spec 을 다시 정의하거나 사용자 결정을 받으세요"
        command -v jq >/dev/null 2>&1 && WARN=$(_goax_json_array "$WARN_MSG")
    fi
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg sha "$SHA" --arg ssha "$SPEC_SHA" --arg tsha "$TASKS_SHA" \
            --arg req "$REQUIRED" --arg reqsrc "$REQ_SRC" --argjson round "$ROUND" \
            --argjson maxr "$MAX_ROUNDS" --argjson over "$OVER" --argjson dry "$DRY_RUN" \
            --arg a "$A_FILE" --arg e "$E_FILE" --arg s "$SPEC_DIR/spec.md" \
            '{spec:$spec, sha:$sha, spec_sha:$ssha, tasks_sha:(if $tsha=="" then null else $tsha end),
              required:$req, required_source:$reqsrc, round:$round, max_rounds:$maxr,
              round_exceeded:$over, dry_run:$dry, spec_file:$s,
              architect_file:$a, evaluator_file:$e,
              header:("verdict: 진행 | 보강 필요 | 재논의 필요\nsha: " + $sha)}')
        NEXT="architect → evaluator 순서로, 각자 자기 파일에만 쓰게 띄우세요. 상대 파일은 브리프에 넣지 않아요"
        if [ "$OVER" = true ]; then
            json_output "warning" "$RESULT" "$WARN_MSG" "$WARN"
        else
            json_output "ok" "$RESULT" "$NEXT" "$WARN"
        fi
    else
        printf 'spec %s — round %s · sha %s · %s (%s)\n  architect → %s\n  evaluator → %s\n  첫 줄: verdict: 진행 | 보강 필요 | 재논의 필요\n  둘째 줄: sha: %s\n' \
            "$SPEC" "$ROUND" "$SHA" "$REQUIRED" "$REQ_SRC" "$A_FILE" "$E_FILE" "$SHA"
        [ "$OVER" = true ] && printf '  ⚠ %s\n' "$WARN_MSG"
        [ "$DRY_RUN" = true ] && printf '  (dry-run — .review-round 는 그대로예요)\n'
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
        PASS=true; REASON="합의 리뷰 대상이 아니에요 (${REQ_SRC})"
    elif [ "$REQUIRED" = "optional" ] && [ "$A_P" = false ] && [ "$E_P" = false ]; then
        PASS=true; REASON="합의 리뷰는 선택이에요 (${REQ_SRC}) — 리뷰 없이 통과. --consensus 로 강제할 수 있어요"
    elif [ "$A_P" = false ] || [ "$E_P" = false ]; then
        MISSING=""; [ "$A_P" = false ] && MISSING="architect "; [ "$E_P" = false ] && MISSING="${MISSING}evaluator"
        REASON="리뷰 파일 없음: ${MISSING% } (${REQ_SRC}) — --snapshot 뒤 리뷰어를 띄우세요"
    elif [ "$A_M" = false ] || [ "$E_M" = false ]; then
        STALE=""; [ "$A_M" = false ] && STALE="architect "; [ "$E_M" = false ] && STALE="${STALE}evaluator"
        REASON="sha 불일치: ${STALE% } — 리뷰 뒤에 ${CHANGED_FILES:-spec/tasks} 가 바뀌었어요. 그쪽만 다시 받으세요"
    elif [ "$A_V" != "진행" ] || [ "$E_V" != "진행" ]; then
        REASON="verdict — architect '${A_V:-?}' · evaluator '${E_V:-?}'. 지적을 spec 에 반영하고 --snapshot 부터 다시"
    else
        PASS=true; REASON="둘 다 진행 · sha 일치 (round ${ROUND})"
    fi

    if [ "$MODE" = "merge" ] && [ "$DRY_RUN" != true ]; then
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
        CH_J=$(printf '%s' "$CHANGED_FILES" | tr ' ' '\n' | jq -Rn '[inputs|select(length>0)]')
        RESULT=$(jq -nc --arg spec "$SPEC" --arg sha "$SHA" --arg ssha "$SPEC_SHA" --arg tsha "$TASKS_SHA" \
            --arg req "$REQUIRED" --arg reqsrc "$REQ_SRC" --argjson round "$ROUND" --argjson ch "$CH_J" \
            --argjson ap "$A_P" --arg av "$A_V" --arg as "$A_S" --argjson am "$A_M" --arg af "$A_FILE" \
            --argjson ep "$E_P" --arg ev "$E_V" --arg es "$E_S" --argjson em "$E_M" --arg ef "$E_FILE" \
            --argjson pass "$PASS" --arg reason "$REASON" --arg mode "$MODE" --argjson dry "$DRY_RUN" \
            '{spec:$spec, sha:$sha, spec_sha:$ssha, tasks_sha:(if $tsha=="" then null else $tsha end),
              required:$req, required_source:$reqsrc, round:$round, mode:$mode, dry_run:$dry,
              changed_files:$ch,
              architect:{present:$ap, verdict:(if $av=="" then null else $av end), sha:(if $as=="" then null else $as end), sha_match:$am, file:$af},
              evaluator:{present:$ep, verdict:(if $ev=="" then null else $ev end), sha:(if $es=="" then null else $es end), sha_match:$em, file:$ef},
              pass:$pass, reason:$reason}')
        if [ "$PASS" = true ]; then json_output "ok" "$RESULT" "$REASON"; else json_output "warning" "$RESULT" "$REASON"; fi
    else
        printf 'spec %s — round %s · sha %s · %s (%s)\n' "$SPEC" "$ROUND" "$SHA" "$REQUIRED" "$REQ_SRC"
        printf '  architect  %s\n' "$([ "$A_P" = true ] && printf '%s (sha %s%s)' "${A_V:-?}" "$A_S" "$([ "$A_M" = true ] && echo ' ✓' || echo ' ✗')" || echo '없음')"
        printf '  evaluator  %s\n' "$([ "$E_P" = true ] && printf '%s (sha %s%s)' "${E_V:-?}" "$E_S" "$([ "$E_M" = true ] && echo ' ✓' || echo ' ✗')" || echo '없음')"
        [ -n "$CHANGED_FILES" ] && printf '  스냅샷 이후 변경: %s\n' "$CHANGED_FILES"
        printf '  pass: %s — %s\n' "$PASS" "$REASON"
        [ "$MODE" = "merge" ] && [ "$DRY_RUN" != true ] && printf '  합본: %s\n' "$SPEC_DIR/review-spec.md"
        [ "$MODE" = "merge" ] && [ "$DRY_RUN" = true ] && printf '  (dry-run — 합본을 만들지 않았어요)\n'
    fi
    ;;
esac
exit "$EXIT_OK"
