#!/usr/bin/env bash
# .ax/scripts/bash/init-mistake-file.sh — mistake 파일 skeleton 생성 (template cp + frontmatter sed 치환)
#
# Usage:
#   bash init-mistake-file.sh \
#       --category <cat> --slug <slug> \
#       --severity <low|medium|high> --detected-by <claude|reviewer|ci|self|user> \
#       --source <skill|hook> \
#       [--context-link <url>] [--one-line <title>] \
#       [--json] [--dry-run] [--help]
#
# 동작:
#   1. _templates/mistakes/mistake.md 를 cp 후 frontmatter {{...}} placeholder sed 치환
#   2. 본문 (5 Whys / 영향 / audit 액션) 은 template 그대로 — LLM 이 mistake skill 안에서 Edit 으로 채움
#   3. 파일명: ${DATE}-${EPOCH}-${RAND4}-${CATEGORY}-${SLUG}.md (race-free, 짧음)
#   4. idempotent: 같은 (DATE, CATEGORY, SLUG) 파일 있으면 ## 이력 에 재발 라인 append (재생성 X)
#   5. --one-line 주면 # 무엇이 일어났나 섹션도 자동 채움 (skill 인터뷰 결과)
#
# JSON output (--json):
#   {"status":"ok","result":{"file_path":"...","action":"created|appended","slug":"...","idempotent_key":"..."}}
#
# Exit:
#   0 OK / 1 ERROR / 2 SKIPPED (필수 인자 누락 등)

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
CATEGORY=""
SLUG=""
SEVERITY=""
DETECTED_BY=""
SOURCE=""
MODEL=""
SESSION_REF=""
CONTEXT_LINK=""
ONE_LINE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)         JSON_MODE=true ;;
        --dry-run)      DRY_RUN=true ;;
        --help|-h)      SHOW_HELP=true ;;
        --category)     shift; CATEGORY="${1:-}" ;;
        --slug)         shift; SLUG="${1:-}" ;;
        --severity)     shift; SEVERITY="${1:-}" ;;
        --detected-by)  shift; DETECTED_BY="${1:-}" ;;
        --source)       shift; SOURCE="${1:-}" ;;
        --context-link) shift; CONTEXT_LINK="${1:-}" ;;
        --one-line)     shift; ONE_LINE="${1:-}" ;;
        --model)        shift; MODEL="${1:-}" ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

# 필수 인자 검증
# `${arg,,}` 는 bash 4+ 문법이라 macOS 기본 bash 3.2 에선 "bad substitution" 이에요.
# 이 스크립트는 `set -uo`(−e 없음)라 그 줄만 죽고 루프가 그대로 이어졌고, 결과로
# `--category ""` 도 status ok · 빈 category 파일이 만들어졌어요 (audit 집계가 무의미해져요).
# bash -n 은 통과해서 smoke 도 못 봤어요. 그래서 tr 로 바꾸고 반드시 exit 1 로 세워요.
for arg in CATEGORY SLUG SEVERITY DETECTED_BY SOURCE; do
    if [ -z "${!arg}" ]; then
        opt=$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        if [ "$JSON_MODE" = true ]; then json_error "--${opt} required"; fi   # json_error 는 exit 1
        goax_error "--${opt} required"; exit "$EXIT_ERROR"
    fi
done

# enum 검증
case "$SEVERITY" in low|medium|high) ;; *)
    if [ "$JSON_MODE" = true ]; then json_error "--severity invalid: $SEVERITY (low|medium|high)"
    else goax_error "--severity invalid: $SEVERITY"; exit "$EXIT_ERROR"; fi ;;
esac
case "$DETECTED_BY" in claude|reviewer|ci|self|user) ;; *)
    if [ "$JSON_MODE" = true ]; then json_error "--detected-by invalid: $DETECTED_BY"
    else goax_error "--detected-by invalid: $DETECTED_BY"; exit "$EXIT_ERROR"; fi ;;
esac
case "$SOURCE" in skill|hook|manual) ;; *)
    if [ "$JSON_MODE" = true ]; then json_error "--source invalid: $SOURCE (skill|hook|manual)"
    else goax_error "--source invalid: $SOURCE"; exit "$EXIT_ERROR"; fi ;;
esac

PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
TEMPLATE="$PROJECT_ROOT/.ax/_templates/mistakes/mistake.md"
MISTAKES="$PROJECT_ROOT/.ax/mistakes"

if [ ! -f "$TEMPLATE" ]; then
    if [ "$JSON_MODE" = true ]; then json_error "template not found: $TEMPLATE"
    else goax_error "template not found: $TEMPLATE"; exit "$EXIT_ERROR"; fi
fi
mkdir -p "$MISTAKES"

# SLUG 정규화 — 영숫자만, cut 30 + trailing dash 제거. 한글 only 면 md5 hash 8자.
# LC_ALL=C — 파일명은 ASCII 로 고정해요. UTF-8 로케일에선 `[[:lower:]]` 가 `é` 같은 글자도
# 포함해서 한글이 아닌 비ASCII 가 파일명에 새어 들어와요.
DATE=$(date +%F)
SLUG_NORM=$(printf '%s' "$SLUG" \
        | tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed 's/[^[:lower:][:digit:]]/-/g; s/--*/-/g; s/^-//; s/-$//' \
        | cut -c1-30 \
        | sed 's/-$//')
if [ -z "$SLUG_NORM" ]; then
    SLUG_NORM=$(printf '%s' "$SLUG" | md5 2>/dev/null | cut -c1-8 \
        || printf '%s' "$SLUG" | md5sum 2>/dev/null | cut -c1-8 \
        || printf '%s' "$SLUG" | shasum -a 1 2>/dev/null | cut -c1-8 \
        || echo "auto")
fi

IDEMPOTENT_KEY="${DATE}-${CATEGORY}-${SLUG_NORM}"

# Idempotent 체크 — 같은 (DATE, CATEGORY, SLUG) 파일 있으면 ## 이력 append
EXISTING=$(find "$MISTAKES" -maxdepth 1 -type f \
            -name "${DATE}-*-${CATEGORY}-${SLUG_NORM}.md" 2>/dev/null | head -1)

if [ -n "$EXISTING" ]; then
    if [ "$DRY_RUN" = true ]; then
        if [ "$JSON_MODE" = true ]; then
            REL="${EXISTING#$PROJECT_ROOT/}"
            json_output "ok" \
                "{\"file_path\":\"$REL\",\"action\":\"append\",\"slug\":\"$SLUG_NORM\",\"idempotent_key\":\"$IDEMPOTENT_KEY\",\"dry_run\":true}" \
                "would append 재발 라인"
        else
            goax_log "dry-run: would append 재발 to $EXISTING"
        fi
        exit "$EXIT_OK"
    fi
    DETAILS_SAFE=""
    [ -n "$ONE_LINE" ] && DETAILS_SAFE=$(printf '%s' "$ONE_LINE" | redact_secrets)
    printf -- '- 재발 %s%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
        "${DETAILS_SAFE:+ — $DETAILS_SAFE}" >> "$EXISTING"
    REL="${EXISTING#$PROJECT_ROOT/}"
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" \
            "{\"file_path\":\"$REL\",\"action\":\"appended\",\"slug\":\"$SLUG_NORM\",\"idempotent_key\":\"$IDEMPOTENT_KEY\"}" \
            "재발 line appended — review existing file"
    else
        goax_log "✓ 재발 appended → $REL"
    fi
    exit "$EXIT_OK"
fi

# 새 파일 — race-free ID: EPOCH(초) + RAND4(hex), 충돌 사실상 0
EPOCH=$(date +%s)
RAND4=$(printf '%04x' "${RANDOM}")
TS="${EPOCH}-${RAND4}"
FILE="$MISTAKES/${DATE}-${TS}-${CATEGORY}-${SLUG_NORM}.md"
REL="${FILE#$PROJECT_ROOT/}"

CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CONTEXT_LINK_OUT="${CONTEXT_LINK:-}"

# 어떤 모델이 낸 실수인지 — audit 에서 "특정 모델에 몰린 실수" 를 보려면 필요해요.
# --model 로 명시 안 하면 결정론 스크립트가 transcript 에서 뽑아요 (LLM 자가보고 X).
# 식별 실패는 unknown 으로 넘어가요 — 캡처 자체를 막으면 안 되니까요.
if [ -z "$MODEL" ] && [ -x "$SCRIPT_DIR/detect-model.sh" ]; then
    if command -v jq >/dev/null 2>&1; then
        DM=$(bash "$SCRIPT_DIR/detect-model.sh" --json 2>/dev/null || true)
        MODEL=$(printf '%s' "$DM" | jq -r '.result.model // empty' 2>/dev/null || true)
        SESSION_REF=$(printf '%s' "$DM" | jq -r '.result.session_ref // empty' 2>/dev/null || true)
    else
        MODEL=$(bash "$SCRIPT_DIR/detect-model.sh" 2>/dev/null || true)
    fi
fi
MODEL="${MODEL:-unknown}"

if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        json_output "ok" \
            "{\"file_path\":\"$REL\",\"action\":\"created\",\"slug\":\"$SLUG_NORM\",\"idempotent_key\":\"$IDEMPOTENT_KEY\",\"dry_run\":true}" \
            "would create $REL"
    else
        goax_log "dry-run: would create $REL"
    fi
    exit "$EXIT_OK"
fi

# Template cp + frontmatter sed 치환.
# sed delimiter | 와 replacement 메타 (&, \) 를 사전 escape — URL 의 `|` 쿼리 파라미터
# 등이 CONTEXT_LINK 로 들어와도 delimiter 충돌 없이 동작.
_sed_escape() { printf '%s' "$1" | sed 's/[\&|]/\\&/g'; }
CATEGORY_E=$(_sed_escape "$CATEGORY")
SEVERITY_E=$(_sed_escape "$SEVERITY")
DETECTED_BY_E=$(_sed_escape "$DETECTED_BY")
CONTEXT_LINK_E=$(_sed_escape "$CONTEXT_LINK_OUT")
CAPTURED_AT_E=$(_sed_escape "$CAPTURED_AT")
SOURCE_E=$(_sed_escape "$SOURCE")
MODEL_E=$(_sed_escape "$MODEL")
SESSION_REF_E=$(_sed_escape "$SESSION_REF")

sed -e "s|{{MODEL}}|$MODEL_E|g" \
    -e "s|{{SESSION_REF}}|$SESSION_REF_E|g" \
    -e "s|{{CATEGORY}}|$CATEGORY_E|g" \
    -e "s|{{SEVERITY}}|$SEVERITY_E|g" \
    -e "s|{{DETECTED_BY}}|$DETECTED_BY_E|g" \
    -e "s|{{CONTEXT_LINK}}|$CONTEXT_LINK_E|g" \
    -e "s|{{CAPTURED_AT}}|$CAPTURED_AT_E|g" \
    -e "s|{{SOURCE}}|$SOURCE_E|g" \
    "$TEMPLATE" > "$FILE"

# --one-line 주면 # 무엇이 일어났나 섹션 자동 채움
if [ -n "$ONE_LINE" ]; then
    ONE_LINE_SAFE=$(printf '%s' "$ONE_LINE" | redact_secrets)
    # "# 무엇이 일어났나" 다음 라인의 placeholder ("한 줄 요약.") 를 ONE_LINE 으로
    # macOS/GNU sed 호환을 위해 임시 파일 사용
    awk -v line="$ONE_LINE_SAFE" '
        /^# 무엇이 일어났나/ { print; print line; getline; if ($0 ~ /^한 줄 요약/) next; print; next }
        { print }
    ' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
fi

# ## 이력 에 최초 캡처 라인 추가
printf -- '\n- 최초 캡처 %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$FILE"

if [ "$JSON_MODE" = true ]; then
    json_output "ok" \
        "{\"file_path\":\"$REL\",\"action\":\"created\",\"slug\":\"$SLUG_NORM\",\"idempotent_key\":\"$IDEMPOTENT_KEY\"}" \
        "MANDATORY next: Edit $REL to replace 5 placeholder sections — '# 어디서', '# 왜 발생 (5 Whys)', '# 어떻게 막을 수 있나', '# 영향 (Cost)', '# audit 액션 제안'. Skill must NOT report success while any placeholder line ('파일/모듈/도메인.', '1. 왜 X? → A', '<예: ...>', '<변경 비용 — 예:', empty audit) remains."
else
    goax_log "✓ created $REL — MANDATORY: edit 본문 5섹션 (어디서/왜 발생/어떻게 막을 수 있나/영향/audit 액션). placeholder 잔재 0 까지 채우고 보고."
fi
exit "$EXIT_OK"
