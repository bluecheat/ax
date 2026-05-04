#!/usr/bin/env bash
# .ax/scripts/bash/capture-mistake.sh — hook 위반·경고를 .ax/mistakes/에 자동 캡처
#
# Mistake Loop의 cold-start 해소: hook이 stderr로 경고만 출력하고 끝나면
# .ax/mistakes/ 가 평생 비어있음 → 이 스크립트가 자동 기록.
#
# Usage:
#   bash capture-mistake.sh <category> <one-line> [<details>]
#
# 예:
#   bash capture-mistake.sh secrets "password 평문 하드코딩" "$f:$LINE"
#
# Idempotent:
#   같은 날 + 같은 category + 같은 slug → 새 파일 X, 기존 파일에 재발 라인만 append
#   → 룰 인플레이션 방지
#
# Exit codes:
#   0 정상 (캡처 또는 재발 기록)
#   2 SKIP (입력 부족 — graceful)

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CATEGORY="${1:-uncategorized}"
ONE_LINE="${2:-}"
DETAILS="${3:-}"

# 빈 입력은 silent skip — caller가 안전하게 호출 가능
[ -z "$ONE_LINE" ] && exit "$EXIT_SKIPPED"

ROOT="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
MISTAKES="$ROOT/.ax/mistakes"

[ -d "$MISTAKES" ] || mkdir -p "$MISTAKES"

# slug 생성: 한글·영문 보존, 그 외 문자는 dash
DATE=$(date +%F)
SLUG=$(printf '%s' "$ONE_LINE" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9가-힣]/-/g; s/--*/-/g; s/^-//; s/-$//' \
        | cut -c1-40)
[ -z "$SLUG" ] && SLUG="auto"

# Idempotent 체크 — 같은 (date, category, slug)면 재발 라인만 append
EXISTING=$(find "$MISTAKES" -maxdepth 1 -type f \
            -name "${DATE}-*-${CATEGORY}-${SLUG}.md" 2>/dev/null | head -1)

if [ -n "$EXISTING" ]; then
    printf -- '- 재발 %s%s\n' "$(date '+%H:%M:%S')" \
        "${DETAILS:+ — $DETAILS}" >> "$EXISTING"
    exit "$EXIT_OK"
fi

# 새 파일 — 그날의 다음 번호
NUM=$(find "$MISTAKES" -maxdepth 1 -type f -name "${DATE}-*.md" 2>/dev/null | wc -l | tr -d ' ')
NUM=$((NUM + 1))
NUM_PAD=$(printf '%03d' "$NUM")
FILE="$MISTAKES/${DATE}-${NUM_PAD}-${CATEGORY}-${SLUG}.md"

cat > "$FILE" <<EOF
---
category: ${CATEGORY}
captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
source: hook-auto
status: open
---

# ${ONE_LINE}

${DETAILS}

## 이력
- 최초 캡처 $(date '+%H:%M:%S')
EOF

exit "$EXIT_OK"
