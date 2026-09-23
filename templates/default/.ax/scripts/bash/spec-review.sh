#!/usr/bin/env bash
# .ax/scripts/bash/spec-review.sh — spec 합의 리뷰 원장. 스냅샷 sha 고정 · 리뷰어별 verdict 집계 · 합본
#
# Usage:
#   bash spec-review.sh [--spec <NNN-slug>] --snapshot [--stage spec|tasks] [--dry-run] [--json]
#                                                                   # sha 고정 (+ 필요할 때만 라운드 +1), 리뷰어 파일 경로 안내
#   bash spec-review.sh [--spec <NNN-slug>] --status            [--json]   # 두 리뷰 파일의 verdict·sha 를 집계 → pass 여부
#   bash spec-review.sh [--spec <NNN-slug>] --delta             [--json]   # 리뷰어가 본 본문 → 지금 본문 diff (재리뷰 브리프용)
#   bash spec-review.sh [--spec <NNN-slug>] --fixup   [--dry-run] [--json] # 통과 뒤의 오타·문구 수정을 리뷰 없이 받아들여요
#   bash spec-review.sh [--spec <NNN-slug>] --merge   [--dry-run] [--json] # review-spec.md 합본 생성 (사람이 읽는 용)
#
# 왜 필요한가 — 계획의 품질은 diff 시점이 아니라 계획 시점에 리뷰해야 올라가요. 그런데 리뷰어
# 둘(architect · evaluator)이 한 파일에 쓰면 (a) 첫 줄 verdict 하나로 "둘 다 진행" 을 표현할 수
# 없고 (b) 뒤에 쓰는 쪽이 앞 절을 읽게 돼 독립성이 깨져요. 그래서 **리뷰어별 파일**이고, 이 스크립트가
# 둘을 집계해요. 리뷰어는 자기 파일 경로만 받아요.
#
# 파일 (스크립트가 쓰는 것 / 리뷰어가 쓰는 것):
#   <spec>/.review-round              라운드|스냅샷sha|시각|spec.md sha|tasks.md sha|단계|fixup sha  ← --snapshot · --fixup 이 씀
#   <spec>/.review-snapshot/          reviewed/ (리뷰어가 본 본문) · current/ (마지막 스냅샷 본문) · delta.diff  ← --snapshot · --delta 가 씀
#   <spec>/review-spec.architect.md   architect 가 직접 씀 — 1줄 `verdict: 진행|보강 필요|재논의 필요` · 2줄 `sha: <12자>`
#   <spec>/review-spec.evaluator.md   evaluator 가 직접 씀 — 같은 형식
#   <spec>/review-spec.md             --merge 가 생성 (합본)
#
# sha 는 **spec.md + tasks.md 합산**이에요. spec.md 만 보면 리뷰 뒤에 tasks.md 를 통째로
# 갈아끼워도 pass 가 유지돼서, "L/XL 은 evaluator 가 tasks.md 까지 본다" 가 no-op 이 돼요.
# tasks.md 가 아직 없으면 spec.md 만으로 계산하고, 생기는 순간 sha 가 바뀌어요 (그게 맞아요 —
# 리뷰어가 본 것과 지금이 다르니까).
#
# 라운드는 "리뷰어가 실제로 본 횟수" 예요 — --snapshot 을 부를 때마다 오르지 않아요:
#   같은 sha 를 다시 찍으면          → 그대로 (reused)
#   직전 스냅샷을 아무도 안 봤으면   → 그 자리를 바꿔 끼워요 (replaced) — 리뷰어 띄우기 전 고친 오타로 라운드를 태우지 않아요
#   직전 스냅샷을 누가 봤으면        → +1
#   --stage 가 바뀌면 (spec → tasks) → 1 부터 다시. 상한도 단계별이에요 (spec 3 · tasks 2 · --max-rounds 로 덮어써요)
#
# --fixup 은 **통과한 뒤**에만 돼요 (둘 다 `진행` · 둘 다 스냅샷 sha). 그 뒤 오타·문구를 고쳐 sha 가
# 어긋났을 때, 지금 본문의 sha 를 "리뷰된 것과 같다" 고 원장에 적어요. 설계가 바뀌었으면 쓰지 않아요 —
# 그건 --snapshot 으로 새 라운드예요. 뭐가 바뀌었는지는 결과의 changed_lines 로 보여줘요.
#
# 통과 조건 (--status 의 pass):
#   required=none (size S)        → pass. 리뷰 대상이 아니에요
#   required=optional (size M)    → 파일이 하나도 없으면 pass (선택). 하나라도 있으면 아래 규칙
#   required=required (size L/XL) → 두 파일 모두 있고, 둘 다 `진행`, 둘 다 sha 가 현재(또는 fixup 으로 받아들인 것)와 같아야 pass
#   sha 불일치 = 리뷰 뒤에 spec/tasks 가 바뀜 = 그쪽만 다시 받아요 (어느 파일인지 알려줘요)
#
# 필수 여부의 SSOT 는 tier-from-state.sh 의 `spec_review` 필드예요 (Size 축만: L/XL 필수 · M 선택 · S 없음).
# 활성 spec 이 아니거나 SSOT 조회가 실패하면 <spec>/.tier 의 `tier:` 키로 **보수적으로** 근사해요
# (full → required · standard → optional · 값이 없으면 required). 판정 못 한 걸 optional 로
# 열어 두면 가장 큰 spec 이 가장 조용히 통과해요 — 그래서 모르면 닫는 쪽이에요.
# 근거는 result 의 `required_source` 에 적어요.
#
# --dry-run 은 아무 파일도 안 써요 (--snapshot 의 .review-round · .review-snapshot, --fixup 의 .review-round, --merge 의 review-spec.md).
# 라운드가 상한을 넘으면 status: warning 으로 알려요. 차단은 안 해요 —
# 계속할지 멈출지는 skill 의 판단이라 exit 는 0 이에요.
#
# Output (--json):
#   --snapshot  {"status":"ok|warning","result":{"spec":"014-x","sha":"…","stage":"spec","round":2,"max_rounds":3,
#                 "reused":false,"replaced":false,"round_exceeded":false,"architect_file":"…","evaluator_file":"…",…}}
#   --status    {"status":"ok|warning","result":{"spec":"014-x","sha":"…","snapshot_sha":"…","stage":"spec","round":2,
#                 "required":"required","required_source":"size L · tier-from-state","changed_files":["tasks.md"],
#                 "fixup":{"applied":false,"sha":null},
#                 "architect":{"present":true,"verdict":"진행","sha":"…","sha_match":true,"file":"…"},
#                 "evaluator":{…},"pass":false,"reason":"…"},…}
#   --delta     {"status":"ok","result":{"base":"reviewed|snapshot|none","files":[{"file":"spec.md","changed_lines":4}],
#                 "delta_file":"…/.review-snapshot/delta.diff","diff":"…"}}
#                base=reviewed 는 리뷰어가 본 본문 대비, base=snapshot 은 아직 아무도 안 본 스냅샷 대비예요
#                (재리뷰 브리프에 붙일 것은 reviewed 쪽이에요 — snapshot 대비는 "리뷰 전에 더 고쳤다" 는 뜻)
#   --fixup     {"status":"ok","result":{"reviewed_sha":"…","accepted_sha":"…","changed_lines":3,…}}
#
# Exit: 0 ok (pass 여부와 무관 — 판단은 caller) · 1 error (spec.md 없음 · --spec 모호 · --fixup 조건 미달) · 2 skipped (jq 없음)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; SHOW_HELP=false; DRY_RUN=false; MODE=""; SPEC=""; MAX_ROUNDS=""; STAGE_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  DRY_RUN=true ;;
        --snapshot) MODE="snapshot" ;;
        --status)   MODE="status" ;;
        --merge)    MODE="merge" ;;
        --delta)    MODE="delta" ;;
        --fixup)    MODE="fixup" ;;
        --spec)     shift; SPEC="${1:-}" ;;
        --stage)    shift; STAGE_ARG="${1:-}" ;;
        --max-rounds) shift; MAX_ROUNDS="${1:-}" ;;
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

case "$STAGE_ARG" in ''|spec|tasks) ;; *) fail "--stage 는 spec|tasks 중 하나예요 (받은 값: '${STAGE_ARG}')" ;; esac
case "$MAX_ROUNDS" in ''|*[!0-9]*) [ -z "$MAX_ROUNDS" ] || fail "--max-rounds 는 숫자예요 (받은 값: '${MAX_ROUNDS}')" ;; esac

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
SNAP_DIR="$SPEC_DIR/.review-snapshot"
DELTA_FILE="$SNAP_DIR/delta.diff"

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

# .review-round: 라운드|스냅샷sha|시각|spec.md sha|tasks.md sha|단계|fixup sha  (6·7번째는 없을 수 있어요 — 옛 원장)
ROUND=0; SNAP_SHA=""; SNAP_SPEC_SHA=""; SNAP_TASKS_SHA=""; STAGE=""; FIXUP_SHA=""
if [ -f "$ROUND_FILE" ]; then
    IFS='|' read -r R_R SNAP_SHA _R_TIME SNAP_SPEC_SHA SNAP_TASKS_SHA STAGE FIXUP_SHA <<EOF
$(head -1 "$ROUND_FILE" 2>/dev/null || true)
EOF
    # 빈 파일·깨진 줄이면 0 — --argjson round "" 는 jq 를 죽여요 (stdout 없이 exit 2)
    case "${R_R:-}" in ''|*[!0-9]*) ROUND=0 ;; *) ROUND="$R_R" ;; esac
fi
ROUND=${ROUND:-0}; SNAP_SHA=${SNAP_SHA:-}; STAGE=${STAGE:-}; FIXUP_SHA=${FIXUP_SHA:-}
case "$STAGE" in spec|tasks) ;; *) STAGE="spec" ;; esac

# 스냅샷 이후 무엇이 바뀌었나 — sha 불일치의 원인을 파일 단위로 짚어줘요
CHANGED_FILES=""
[ -n "$SNAP_SPEC_SHA" ]  && [ "$SNAP_SPEC_SHA"  != "$SPEC_SHA" ]  && CHANGED_FILES="spec.md "
[ -n "$SNAP_TASKS_SHA" ] && [ "$SNAP_TASKS_SHA" != "$TASKS_SHA" ] && CHANGED_FILES="${CHANGED_FILES}tasks.md "
[ -z "$SNAP_TASKS_SHA" ] && [ -n "$SNAP_SHA" ] && [ -n "$TASKS_SHA" ] && CHANGED_FILES="${CHANGED_FILES}tasks.md "
CHANGED_FILES="${CHANGED_FILES% }"

# 리뷰 파일 파싱 → "present|verdict|sha" (verdict 는 첫 줄, sha 는 둘째 줄이 계약)
parse_review() {
    local f="$1" v="" s=""
    [ -f "$f" ] || { printf 'false||'; return; }
    v=$(head -1 "$f" 2>/dev/null | sed -n 's/^verdict:[[:space:]]*//p' | sed -E 's/[[:space:]]+$//' || true)
    s=$(head -3 "$f" 2>/dev/null | sed -n 's/^sha:[[:space:]]*//p' | head -1 | sed -E 's/[[:space:]]+$//' || true)
    printf 'true|%s|%s' "$v" "$s"
}
IFS='|' read -r A_P A_V A_S <<EOF
$(parse_review "$A_FILE")
EOF
IFS='|' read -r E_P E_V E_S <<EOF
$(parse_review "$E_FILE")
EOF

# "이 sha 를 누가 봤나" — 리뷰 파일 중 하나라도 그 sha 를 달고 있으면 본 거예요
reviewed_by_anyone() { [ -n "$1" ] && { [ "$A_S" = "$1" ] || [ "$E_S" = "$1" ]; }; }
# "이 sha 를 둘 다 진행으로 봤나" — fixup 의 전제
passed_at() { [ -n "$1" ] && [ "$A_P" = true ] && [ "$E_P" = true ] && [ "$A_S" = "$1" ] && [ "$E_S" = "$1" ] && [ "$A_V" = "진행" ] && [ "$E_V" = "진행" ]; }

# 두 본문 세트(디렉토리 vs 워킹 카피)의 diff → DIFF · CHANGED_LINES · CHANGED_JSON 을 채워요
# (stdout 으로 내보내면 $(…) 가 서브셸이라 줄 수가 caller 에 안 남아요)
diff_against() {
    local base="$1" label="${2:-reviewed}" f b c n
    CHANGED_LINES=0; CHANGED_JSON='[]'; DIFF=""
    for f in spec.md tasks.md; do
        n=0
        if [ -f "$base/$f" ] || [ -f "$SPEC_DIR/$f" ]; then
            # 한쪽에만 있는 파일(리뷰 뒤 생긴 tasks.md)은 /dev/null 과 비교해 전부 바뀐 걸로 세요
            b="$base/$f"; [ -f "$b" ] || b=/dev/null
            c="$SPEC_DIR/$f"; [ -f "$c" ] || c=/dev/null
            n=$(diff "$b" "$c" 2>/dev/null | grep -cE '^[<>]' || true)
            n=${n:-0}
            if [ "$n" -gt 0 ]; then
                DIFF="${DIFF}$(diff -u -L "$label/$f" -L "current/$f" "$b" "$c" 2>/dev/null || true)
"
            fi
        fi
        CHANGED_LINES=$((CHANGED_LINES + n))
        command -v jq >/dev/null 2>&1 && CHANGED_JSON=$(jq -nc --argjson a "$CHANGED_JSON" --arg f "$f" --argjson n "$n" '$a + [{file:$f, changed_lines:$n}]')
    done
    return 0
}

# 스냅샷 본문 보관 — 리뷰어가 본 것과 지금을 나중에 diff 하려면 그때 본문이 남아 있어야 해요
save_snapshot_copy() {
    local dst="$1"
    mkdir -p "$dst"
    cp "$SPEC_DIR/spec.md" "$dst/spec.md"
    if [ -f "$SPEC_DIR/tasks.md" ]; then cp "$SPEC_DIR/tasks.md" "$dst/tasks.md"; else rm -f "$dst/tasks.md"; fi
}

case "$MODE" in
  snapshot)
    NEW_STAGE="${STAGE_ARG:-$STAGE}"
    if [ -z "$MAX_ROUNDS" ]; then
        if [ "$NEW_STAGE" = tasks ]; then MAX_ROUNDS=2; else MAX_ROUNDS=3; fi
    fi
    REUSED=false; REPLACED=false; STAGE_RESET=false; PREV_REVIEWED=false
    reviewed_by_anyone "$SNAP_SHA" && PREV_REVIEWED=true
    if [ "$ROUND" -gt 0 ] && [ "$NEW_STAGE" != "$STAGE" ]; then
        STAGE_RESET=true; ROUND=1
    elif [ "$ROUND" -gt 0 ] && { [ "$SNAP_SHA" = "$SHA" ] || [ "$FIXUP_SHA" = "$SHA" ]; }; then
        # 같은 본문(또는 --fixup 으로 이미 받아들인 본문)이면 원장을 건드리지 않아요 — fixup 기록이 지워지면 안 돼요
        REUSED=true
    elif [ "$ROUND" -gt 0 ] && [ "$PREV_REVIEWED" = false ]; then
        REPLACED=true
    else
        ROUND=$((ROUND + 1))
    fi
    if [ "$DRY_RUN" != true ] && [ "$REUSED" = false ]; then
        # 직전 스냅샷을 누가 봤으면 그 본문이 "리뷰된 것" — reviewed/ 로 옮기고 지금 본문을 current/ 에
        if [ -d "$SNAP_DIR/current" ] && [ "$PREV_REVIEWED" = true ]; then
            rm -rf "$SNAP_DIR/reviewed"; mv "$SNAP_DIR/current" "$SNAP_DIR/reviewed"
        fi
        save_snapshot_copy "$SNAP_DIR/current"
        printf '%s|%s|%s|%s|%s|%s|\n' "$ROUND" "$SHA" "$(date -u +%Y-%m-%dT%H:%MZ)" "$SPEC_SHA" "$TASKS_SHA" "$NEW_STAGE" > "$ROUND_FILE"
    fi
    OVER=false; WARN='[]'; WARN_MSG=""
    if [ "$ROUND" -gt "$MAX_ROUNDS" ]; then
        OVER=true
        WARN_MSG="${NEW_STAGE} 단계 라운드 ${ROUND} — 상한 ${MAX_ROUNDS} 을 넘었어요. 리뷰를 더 돌리기보다 spec 을 다시 정의하거나 사용자 결정을 받으세요"
        command -v jq >/dev/null 2>&1 && WARN=$(_goax_json_array "$WARN_MSG")
    fi
    NOTE=""
    [ "$REUSED" = true ]      && NOTE="같은 sha — 라운드 ${ROUND} 그대로예요"
    [ "$REPLACED" = true ]    && NOTE="직전 스냅샷을 아무도 안 봤어요 — 라운드 ${ROUND} 를 이 본문으로 바꿔 끼웠어요"
    [ "$STAGE_RESET" = true ] && NOTE="${NEW_STAGE} 단계로 넘어와 라운드를 1 부터 다시 세요 (상한 ${MAX_ROUNDS})"
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg sha "$SHA" --arg ssha "$SPEC_SHA" --arg tsha "$TASKS_SHA" \
            --arg req "$REQUIRED" --arg reqsrc "$REQ_SRC" --argjson round "$ROUND" --arg stage "$NEW_STAGE" \
            --argjson maxr "$MAX_ROUNDS" --argjson over "$OVER" --argjson dry "$DRY_RUN" \
            --argjson reused "$REUSED" --argjson replaced "$REPLACED" --argjson sreset "$STAGE_RESET" \
            --arg a "$A_FILE" --arg e "$E_FILE" --arg s "$SPEC_DIR/spec.md" --arg note "$NOTE" \
            '{spec:$spec, sha:$sha, spec_sha:$ssha, tasks_sha:(if $tsha=="" then null else $tsha end),
              required:$req, required_source:$reqsrc, stage:$stage, round:$round, max_rounds:$maxr,
              reused:$reused, replaced:$replaced, stage_reset:$sreset,
              round_exceeded:$over, dry_run:$dry, spec_file:$s,
              architect_file:$a, evaluator_file:$e, note:(if $note=="" then null else $note end),
              header:("verdict: 진행 | 보강 필요 | 재논의 필요\nsha: " + $sha)}')
        NEXT="architect 와 evaluator 를 한 메시지에 같이 띄우세요 — 각자 자기 파일에만 쓰고, 상대 파일은 브리프에 넣지 않아요. 재리뷰면 --delta 를 브리프에 붙여요"
        if [ "$OVER" = true ]; then
            json_output "warning" "$RESULT" "$WARN_MSG" "$WARN"
        else
            json_output "ok" "$RESULT" "$NEXT" "$WARN"
        fi
    else
        printf 'spec %s — %s 단계 round %s/%s · sha %s · %s (%s)\n  architect → %s\n  evaluator → %s\n  첫 줄: verdict: 진행 | 보강 필요 | 재논의 필요\n  둘째 줄: sha: %s\n' \
            "$SPEC" "$NEW_STAGE" "$ROUND" "$MAX_ROUNDS" "$SHA" "$REQUIRED" "$REQ_SRC" "$A_FILE" "$E_FILE" "$SHA"
        [ -n "$NOTE" ] && printf '  %s\n' "$NOTE"
        [ "$OVER" = true ] && printf '  ⚠ %s\n' "$WARN_MSG"
        [ "$DRY_RUN" = true ] && printf '  (dry-run — .review-round 는 그대로예요)\n'
    fi
    ;;
  delta)
    # base 는 이름표고 디렉토리는 따로예요 — 이름표를 경로로 쓰면 없는 디렉토리와 비교해서
    # "전부 바뀜" 이 나와요 (reviewed/ 가 아직 없는 1 라운드에서 실제로 그랬어요)
    BASE="none"; BASE_DIR=""; DIFF=""
    if [ -d "$SNAP_DIR/reviewed" ]; then BASE="reviewed"; BASE_DIR="$SNAP_DIR/reviewed"
    elif [ -d "$SNAP_DIR/current" ]; then BASE="snapshot"; BASE_DIR="$SNAP_DIR/current"
    fi
    CHANGED_LINES=0; CHANGED_JSON='[]'
    if [ "$BASE" != none ]; then
        diff_against "$BASE_DIR" "$BASE"
        [ "$DRY_RUN" = true ] || printf '%s' "$DIFF" > "$DELTA_FILE"
    fi
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg sha "$SHA" --arg base "$BASE" --argjson files "$CHANGED_JSON" \
            --argjson n "$CHANGED_LINES" --arg df "$DELTA_FILE" --arg diff "$DIFF" --argjson dry "$DRY_RUN" \
            '{spec:$spec, sha:$sha, base:$base, changed_lines:$n, files:$files,
              delta_file:(if $base=="none" or $dry then null else $df end), diff:$diff}')
        case "$BASE" in
            none)     NEXT="스냅샷 본문이 없어요 — --snapshot 을 먼저 하면 그때부터 diff 를 낼 수 있어요" ;;
            reviewed) NEXT="리뷰어가 본 본문 대비 ${CHANGED_LINES}줄 — 재리뷰 브리프에 delta_file 을 붙이면 리뷰어가 바뀐 곳만 봐요" ;;
            snapshot) NEXT="아직 아무도 안 본 스냅샷 대비 ${CHANGED_LINES}줄 — 리뷰 전이면 --snapshot 을 다시 찍어요" ;;
        esac
        json_output "ok" "$RESULT" "$NEXT"
    else
        printf 'spec %s — base %s · %s줄 바뀜\n' "$SPEC" "$BASE" "$CHANGED_LINES"
        [ -n "$DIFF" ] && printf '%s\n' "$DIFF"
    fi
    ;;
  fixup)
    if [ "$REQUIRED" = none ]; then fail "합의 리뷰 대상이 아니에요 (${REQ_SRC}) — fixup 할 리뷰가 없어요"; fi
    if [ -z "$SNAP_SHA" ]; then fail "스냅샷이 없어요 — --snapshot 뒤 리뷰가 통과한 다음에 쓰는 거예요"; fi
    if ! passed_at "$SNAP_SHA"; then
        fail "통과한 리뷰가 없어요 (architect '${A_V:-없음}' sha ${A_S:-없음} · evaluator '${E_V:-없음}' sha ${E_S:-없음} · 스냅샷 ${SNAP_SHA}) — fixup 은 둘 다 진행인 뒤에만이에요"
    fi
    if [ "$SHA" = "$SNAP_SHA" ]; then fail "본문이 리뷰된 그대로예요 (sha ${SHA}) — fixup 할 게 없어요"; fi
    CHANGED_LINES=0; CHANGED_JSON='[]'; DIFF=""; HAVE_COPY=true
    if [ -d "$SNAP_DIR/current" ]; then diff_against "$SNAP_DIR/current" "reviewed"; else HAVE_COPY=false; fi
    if [ "$DRY_RUN" != true ]; then
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$ROUND" "$SNAP_SHA" "$(date -u +%Y-%m-%dT%H:%MZ)" "$SNAP_SPEC_SHA" "$SNAP_TASKS_SHA" "$STAGE" "$SHA" > "$ROUND_FILE"
    fi
    if [ "$HAVE_COPY" = true ]; then FX_N="${CHANGED_LINES}줄"; else FX_N="바뀐 줄 수는 몰라요 — 스냅샷 본문 사본이 없어요"; fi
    NEXT="리뷰된 ${SNAP_SHA} 와 지금 ${SHA} 를 같은 것으로 적었어요 (${FX_N}) — --status 가 pass 예요. 설계가 바뀐 거면 --snapshot 으로 새 라운드를 여세요"
    if [ "$JSON_MODE" = true ]; then
        RESULT=$(jq -nc --arg spec "$SPEC" --arg rs "$SNAP_SHA" --arg as "$SHA" --argjson round "$ROUND" --arg stage "$STAGE" \
            --argjson n "$CHANGED_LINES" --argjson files "$CHANGED_JSON" --argjson dry "$DRY_RUN" --arg diff "$DIFF" \
            --argjson have "$HAVE_COPY" \
            '{spec:$spec, reviewed_sha:$rs, accepted_sha:$as, round:$round, stage:$stage,
              changed_lines:(if $have then $n else null end), files:(if $have then $files else [] end),
              diff:$diff, dry_run:$dry}')
        json_output "ok" "$RESULT" "$NEXT"
    else
        printf 'spec %s — fixup: 리뷰된 %s → 지금 %s (%s)\n' "$SPEC" "$SNAP_SHA" "$SHA" "$FX_N"
        [ -n "$DIFF" ] && printf '%s\n' "$DIFF"
        [ "$DRY_RUN" = true ] && printf '  (dry-run — .review-round 는 그대로예요)\n'
    fi
    ;;
  status|merge)
    FIXUP_APPLIED=false
    [ -n "$FIXUP_SHA" ] && [ "$FIXUP_SHA" = "$SHA" ] && FIXUP_APPLIED=true
    A_M=false; E_M=false
    if [ "$A_P" = true ]; then
        { [ "$A_S" = "$SHA" ] || { [ "$FIXUP_APPLIED" = true ] && [ "$A_S" = "$SNAP_SHA" ]; }; } && A_M=true
    fi
    if [ "$E_P" = true ]; then
        { [ "$E_S" = "$SHA" ] || { [ "$FIXUP_APPLIED" = true ] && [ "$E_S" = "$SNAP_SHA" ]; }; } && E_M=true
    fi

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
        HINT="그쪽만 다시 받으세요 (--delta 로 바뀐 곳만 브리프에)"
        passed_at "$SNAP_SHA" && HINT="오타·문구 수준이면 --fixup, 설계가 바뀌었으면 --snapshot 으로 새 라운드"
        REASON="sha 불일치: ${STALE% } — 리뷰 뒤에 ${CHANGED_FILES:-spec/tasks} 가 바뀌었어요. ${HINT}"
    elif [ "$A_V" != "진행" ] || [ "$E_V" != "진행" ]; then
        REASON="verdict — architect '${A_V:-?}' · evaluator '${E_V:-?}'. 지적을 spec 에 반영하고 --snapshot 부터 다시"
    else
        FIXUP_NOTE=""; [ "$FIXUP_APPLIED" = true ] && FIXUP_NOTE=" · fixup ${SHA}"
        PASS=true; REASON="둘 다 진행 · sha 일치 (${STAGE} 단계 round ${ROUND}${FIXUP_NOTE})"
    fi

    if [ "$MODE" = "merge" ] && [ "$DRY_RUN" != true ]; then
        OUT="$SPEC_DIR/review-spec.md"
        {
            printf '# review-spec — %s (%s 단계 round %s · sha %s · %s)\n\n' "$SPEC" "$STAGE" "$ROUND" "$SHA" "$REQUIRED"
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
            --arg snap "$SNAP_SHA" --arg stage "$STAGE" --argjson fx "$FIXUP_APPLIED" --arg fxs "$FIXUP_SHA" \
            --arg req "$REQUIRED" --arg reqsrc "$REQ_SRC" --argjson round "$ROUND" --argjson ch "$CH_J" \
            --argjson ap "$A_P" --arg av "$A_V" --arg as "$A_S" --argjson am "$A_M" --arg af "$A_FILE" \
            --argjson ep "$E_P" --arg ev "$E_V" --arg es "$E_S" --argjson em "$E_M" --arg ef "$E_FILE" \
            --argjson pass "$PASS" --arg reason "$REASON" --arg mode "$MODE" --argjson dry "$DRY_RUN" \
            '{spec:$spec, sha:$sha, spec_sha:$ssha, tasks_sha:(if $tsha=="" then null else $tsha end),
              snapshot_sha:(if $snap=="" then null else $snap end), stage:$stage,
              fixup:{applied:$fx, sha:(if $fxs=="" then null else $fxs end)},
              required:$req, required_source:$reqsrc, round:$round, mode:$mode, dry_run:$dry,
              changed_files:$ch,
              architect:{present:$ap, verdict:(if $av=="" then null else $av end), sha:(if $as=="" then null else $as end), sha_match:$am, file:$af},
              evaluator:{present:$ep, verdict:(if $ev=="" then null else $ev end), sha:(if $es=="" then null else $es end), sha_match:$em, file:$ef},
              pass:$pass, reason:$reason}')
        if [ "$PASS" = true ]; then json_output "ok" "$RESULT" "$REASON"; else json_output "warning" "$RESULT" "$REASON"; fi
    else
        printf 'spec %s — %s 단계 round %s · sha %s · %s (%s)\n' "$SPEC" "$STAGE" "$ROUND" "$SHA" "$REQUIRED" "$REQ_SRC"
        printf '  architect  %s\n' "$([ "$A_P" = true ] && printf '%s (sha %s%s)' "${A_V:-?}" "$A_S" "$([ "$A_M" = true ] && echo ' ✓' || echo ' ✗')" || echo '없음')"
        printf '  evaluator  %s\n' "$([ "$E_P" = true ] && printf '%s (sha %s%s)' "${E_V:-?}" "$E_S" "$([ "$E_M" = true ] && echo ' ✓' || echo ' ✗')" || echo '없음')"
        [ -n "$CHANGED_FILES" ] && printf '  스냅샷 이후 변경: %s\n' "$CHANGED_FILES"
        [ "$FIXUP_APPLIED" = true ] && printf '  fixup: %s 를 리뷰된 %s 와 같은 것으로 받아들였어요\n' "$SHA" "$SNAP_SHA"
        printf '  pass: %s — %s\n' "$PASS" "$REASON"
        [ "$MODE" = "merge" ] && [ "$DRY_RUN" != true ] && printf '  합본: %s\n' "$SPEC_DIR/review-spec.md"
        [ "$MODE" = "merge" ] && [ "$DRY_RUN" = true ] && printf '  (dry-run — 합본을 만들지 않았어요)\n'
    fi
    ;;
esac
exit "$EXIT_OK"
