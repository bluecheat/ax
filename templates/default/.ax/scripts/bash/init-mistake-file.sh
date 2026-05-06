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
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

# 필수 인자 검증
for arg in CATEGORY SLUG SEVERITY DETECTED_BY SOURCE; do
    if [ -z "${!arg}" ]; then
        if [ "$JSON_MODE" = true ]; then json_error "--${arg,,} required"
        else goax_error "--$(echo "$arg" | tr '[:upper:]' '[:lower:]') required"; exit "$EXIT_ERROR"; fi
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
DATE=$(date +%F)
SLUG_NORM=$(printf '%s' "$SLUG" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' \
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
    printf -- '- 재발 %s%s\n' "$(date '+%H:%M:%S')" \
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

# Template cp + frontmatter sed 치환
# sed delimiter | 로 path/url 호환. 백슬래시 escape는 caller 책임 (보통 안 들어옴).
sed -e "s|{{CATEGORY}}|$CATEGORY|g" \
    -e "s|{{SEVERITY}}|$SEVERITY|g" \
    -e "s|{{DETECTED_BY}}|$DETECTED_BY|g" \
    -e "s|{{CONTEXT_LINK}}|$CONTEXT_LINK_OUT|g" \
    -e "s|{{CAPTURED_AT}}|$CAPTURED_AT|g" \
    -e "s|{{SOURCE}}|$SOURCE|g" \
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
printf -- '\n- 최초 캡처 %s\n' "$(date '+%H:%M:%S')" >> "$FILE"

if [ "$JSON_MODE" = true ]; then
    json_output "ok" \
        "{\"file_path\":\"$REL\",\"action\":\"created\",\"slug\":\"$SLUG_NORM\",\"idempotent_key\":\"$IDEMPOTENT_KEY\"}" \
        "MANDATORY next: Edit $REL to replace 5 placeholder sections — '# 어디서', '# 왜 발생 (5 Whys)', '# 어떻게 막을 수 있나', '# 영향 (Cost)', '# audit 액션 제안'. Skill must NOT report success while any placeholder line ('파일/모듈/도메인.', '1. 왜 X? → A', '<예: ...>', '<변경 비용 — 예:', empty audit) remains."
else
    goax_log "✓ created $REL — MANDATORY: edit 본문 5섹션 (어디서/왜 발생/어떻게 막을 수 있나/영향/audit 액션). placeholder 잔재 0 까지 채우고 보고."
fi
exit "$EXIT_OK"
