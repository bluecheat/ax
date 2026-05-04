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

# slug 생성: 영숫자만 보존 (한글/특수문자 제외 — 파일시스템·grep 친화).
# 한글 only 입력은 SLUG 가 빈 문자열이 되므로 hash fallback 으로 고유성 확보
# (그렇지 않으면 같은 날 같은 카테고리의 다른 한글 mistake 가 idempotent key 로 묶여 재발 처리됨).
DATE=$(date +%F)
SLUG=$(printf '%s' "$ONE_LINE" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' \
        | cut -c1-40)
if [ -z "$SLUG" ]; then
    # ONE_LINE 의 hash 8자 — macOS(md5) / GNU(md5sum) / fallback shasum 순으로 시도.
    SLUG=$(printf '%s' "$ONE_LINE" | md5 2>/dev/null | cut -c1-8 \
        || printf '%s' "$ONE_LINE" | md5sum 2>/dev/null | cut -c1-8 \
        || printf '%s' "$ONE_LINE" | shasum -a 1 2>/dev/null | cut -c1-8 \
        || echo "auto")
fi

# Idempotent 체크 — 같은 (date, category, slug)면 재발 라인만 append
# Glob은 새 ID 포맷(${DATE}-${TS}-${CATEGORY}-${SLUG}.md)과 구 포맷(${DATE}-${NUM}-${CATEGORY}-${SLUG}.md)
# 모두 매치 — 0.1.7→0.1.8 마이그레이션 호환.
EXISTING=$(find "$MISTAKES" -maxdepth 1 -type f \
            -name "${DATE}-*-${CATEGORY}-${SLUG}.md" 2>/dev/null | head -1)

if [ -n "$EXISTING" ]; then
    # Sanitize DETAILS before append. ONE_LINE은 idempotent key라 이 경로엔 등장하지 않음.
    DETAILS_SAFE=$(printf '%s' "${DETAILS}" | redact_secrets)
    printf -- '- 재발 %s%s\n' "$(date '+%H:%M:%S')" \
        "${DETAILS_SAFE:+ — $DETAILS_SAFE}" >> "$EXISTING"
    exit "$EXIT_OK"
fi

# 새 파일 — race-free ID: ms-timestamp + PID + random.
# 구 포맷 ${NUM_PAD}는 동시성 race(find | wc -l)에 취약했음 — 0.1.8에서 제거.
if EPOCH_MS=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null); then
    :
else
    EPOCH_MS="$(date +%s)000"
fi
TS="${EPOCH_MS}-$$-${RANDOM}"
FILE="$MISTAKES/${DATE}-${TS}-${CATEGORY}-${SLUG}.md"

# DETAILS만 sanitize. ONE_LINE은 신호 손실 방지를 위해 보존 — caller가
# 시크릿을 직접 타이틀에 박지 않도록 hook 측에서 책임.
DETAILS_SAFE=$(printf '%s' "${DETAILS}" | redact_secrets)

cat > "$FILE" <<EOF
---
category: ${CATEGORY}
severity: medium
detected_by: hook
context_link:
captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
source: hook-auto
status: open
---

# 무엇이 일어났나
${ONE_LINE}

# 어디서 (파일·모듈)
${DETAILS_SAFE}

# 왜 발생 (5 Whys 기법)
<!-- audit 시점에 채움. "왜?" 를 5번까지: 1. 왜 X? → A / 2. 왜 A? → B / ... / 5. → 근본 원인 -->

# 어떻게 막을 수 있나 (사람 리뷰 / Sensor 자동화 / 룰 추가)
<!-- audit 시점에 채움 -->

# 영향 (Cost)
즉시:
- <!-- 변경 비용 / 사용자 turn 추가 등. audit 시점에 채움 -->

잠재 후속 (정정 안 했을 경우):
- <!-- 후속 비용 (CI 실패, rename 비용, 모듈 미검출 등). audit 시점에 채움 -->

# audit 액션 제안
<!-- 룰 승격 후보 / hook 작성 / 관측 보강 등. audit 시점에 채움 -->

## 이력
- 최초 캡처 $(date '+%H:%M:%S')
EOF

exit "$EXIT_OK"
