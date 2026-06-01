#!/usr/bin/env bash
# .ax/scripts/bash/build-memory.sh — .ax/MEMORY.md 빠른 회상 인덱스 재생성.
#
# MEMORY.md 는 triage 가 *가장 먼저 읽는* 한 줄 포인터 인덱스 — 본문이 아니라
# "무엇이 어디 있는지" 만 담아 작게 유지(항상 로드해도 토큰 저렴). 본문은 LLM 이
# 포인터를 보고 필요할 때만 해당 파일을 read.  (index/detail 분리 패턴)
#
# 생성 소스(.ax/ 실측):
#   - 현재 작업       .ax/current-task.json (task_id/size/risk/domain/phase/spec_id)
#   - 🔴/🟡 룰        CLAUDE.md (또는 AGENTS.md) 시그널 라인
#   - 모듈            .ax/modules/<name>/rules.md (name + keywords)
#   - 최근 ADR        .ax/docs/adr/NNNN-*.md (제목)
#   - 열린 mistakes   .ax/mistakes/*.md (카테고리별 수)
#   - spec            .ax/docs/spec/NNN-*/spec.md
#
# 사용:
#   bash build-memory.sh            # .ax/MEMORY.md 재생성 (기본)
#   bash build-memory.sh --json     # 생성 요약 JSON (파일도 씀)
#   bash build-memory.sh --dry-run  # 내용 미리보기만 (파일 안 씀)
#   bash build-memory.sh --help
#
# 의존: grep, sed, awk, find. jq 권장(현재 작업 파싱) — 없으면 그 섹션만 생략.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

WS="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
cd "$WS" 2>/dev/null || { goax_error "프로젝트 루트 진입 실패: $WS"; exit "$EXIT_ERROR"; }

HAS_JQ=false
if command -v jq >/dev/null 2>&1; then HAS_JQ=true; fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Constitution 파일 — CLAUDE.md 우선, 없으면 AGENTS.md
RULES_FILE=""
[ -f CLAUDE.md ] && RULES_FILE="CLAUDE.md"
[ -z "$RULES_FILE" ] && [ -f AGENTS.md ] && RULES_FILE="AGENTS.md"

# ── 본문 생성 (stdout 로 모은 뒤 한 번에 기록) ──
emit_memory() {
    printf '# MEMORY.md — goax 빠른 회상 인덱스 (자동 생성 · 직접 편집 금지)\n'
    printf '<!-- build-memory.sh 가 .ax/ 상태에서 재생성. triage 가 가장 먼저 읽는 1줄 포인터 인덱스. -->\n'
    printf '_생성: %s_\n\n' "$NOW"

    # 현재 작업
    printf '## 현재 작업\n'
    if [ "$HAS_JQ" = true ] && [ -f .ax/current-task.json ]; then
        local tid sz rk dm ph sp
        tid=$(jq -r '.task_id // "—"' .ax/current-task.json 2>/dev/null)
        sz=$(jq -r '.size // "—"' .ax/current-task.json 2>/dev/null)
        rk=$(jq -r '.risk // "—"' .ax/current-task.json 2>/dev/null)
        dm=$(jq -r '.domain // "—"' .ax/current-task.json 2>/dev/null)
        ph=$(jq -r '.phase // "idle"' .ax/current-task.json 2>/dev/null)
        sp=$(jq -r '.spec_id // "—"' .ax/current-task.json 2>/dev/null)
        if [ "$tid" = "null" ] || [ -z "$tid" ]; then tid="—"; fi
        printf -- '- task: `%s` · %s/%s · domain=%s · phase=%s · spec=%s → .ax/current-task.json\n\n' \
            "$tid" "$sz" "$rk" "$dm" "$ph" "$sp"
    else
        printf -- '- (현재 작업 없음 — triage 가 채워요)\n\n'
    fi

    # 🔴 CRITICAL / 🟡 MANDATORY 룰 (CLAUDE.md 시그널 라인 → 토큰만)
    if [ -n "$RULES_FILE" ]; then
        local crit_n mand_n
        crit_n=$(grep -cE '^🔴 \*\*`' "$RULES_FILE" 2>/dev/null || true); crit_n=${crit_n:-0}
        mand_n=$(grep -cE '^🟡 \*\*`' "$RULES_FILE" 2>/dev/null || true); mand_n=${mand_n:-0}
        printf '## 🔴 CRITICAL 룰 (%s)\n' "${crit_n:-0}"
        grep -nE '^🔴 \*\*`' "$RULES_FILE" 2>/dev/null | head -12 \
            | sed -E "s/^([0-9]+):🔴 \*\*\`([^\`]*)\`\*\*[[:space:]]*/- \`\2\` → ${RULES_FILE}:\1  /" \
            | awk '{print substr($0,1,160)}' || true
        printf '\n## 🟡 MANDATORY 룰 (%s)\n' "${mand_n:-0}"
        grep -nE '^🟡 \*\*`' "$RULES_FILE" 2>/dev/null | head -12 \
            | sed -E "s/^([0-9]+):🟡 \*\*\`([^\`]*)\`\*\*[[:space:]]*/- \`\2\` → ${RULES_FILE}:\1  /" \
            | awk '{print substr($0,1,160)}' || true
        printf '\n'
    fi

    # 모듈 (name + keywords)
    local mod_n=0
    if [ -d .ax/modules ]; then
        mod_n=$(find .ax/modules -mindepth 2 -maxdepth 2 -name 'rules.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    printf '## 모듈 (%s)\n' "$mod_n"
    if [ "$mod_n" -gt 0 ]; then
        local md name kw
        for md in .ax/modules/*/rules.md; do
            [ -f "$md" ] || continue
            name=$(printf '%s' "$md" | sed -E 's#\.ax/modules/([^/]+)/rules\.md#\1#')
            kw=$(grep -E '^keywords:' "$md" 2>/dev/null | head -1 | sed -E 's/^keywords:[[:space:]]*//' | awk '{print substr($0,1,80)}')
            printf -- '- %s — keywords: %s → %s\n' "$name" "${kw:-—}" "$md"
        done
    fi
    printf '\n'

    # 최근 ADR (제목)
    local adr_n=0
    if [ -d .ax/docs/adr ]; then
        adr_n=$(find .ax/docs/adr -maxdepth 1 -name '[0-9]*-*.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    printf '## 최근 ADR (%s)\n' "$adr_n"
    if [ "$adr_n" -gt 0 ]; then
        local af title
        find .ax/docs/adr -maxdepth 1 -name '[0-9]*-*.md' 2>/dev/null | sort | tail -10 | while IFS= read -r af; do
            title=$(grep -m1 -E '^#[[:space:]]' "$af" 2>/dev/null | sed -E 's/^#+[[:space:]]*//' | awk '{print substr($0,1,70)}')
            printf -- '- %s → %s\n' "${title:-$(basename "$af")}" "$af"
        done
    fi
    printf '\n'

    # 열린 mistakes (카테고리별 수)
    local mis_n=0
    if [ -d .ax/mistakes ]; then
        mis_n=$(find .ax/mistakes -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    printf '## 열린 mistakes (%s)\n' "$mis_n"
    if [ "$mis_n" -gt 0 ]; then
        # frontmatter 의 category: 값으로 집계
        grep -hE '^category:' .ax/mistakes/*.md 2>/dev/null \
            | sed -E 's/^category:[[:space:]]*//' | tr -d '"' \
            | sort | uniq -c | sort -rn | head -10 \
            | awk '{cnt=$1; $1=""; sub(/^ /,""); printf "- %s: %s건 → .ax/mistakes/\n", $0, cnt}' || true
    fi
    printf '\n'

    # spec
    local spec_n=0
    if [ -d .ax/docs/spec ]; then
        spec_n=$(find .ax/docs/spec -mindepth 2 -name 'spec.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    printf '## spec (%s)\n' "$spec_n"
    if [ "$spec_n" -gt 0 ]; then
        local sd
        find .ax/docs/spec -mindepth 2 -name 'spec.md' 2>/dev/null | sort | tail -10 | while IFS= read -r sd; do
            printf -- '- %s → %s\n' "$(dirname "$sd" | sed 's#\.ax/docs/spec/##')" "$sd"
        done
    fi
    printf '\n'
}

CONTENT=$(emit_memory)

if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        BYTES=$(printf '%s' "$CONTENT" | wc -c | tr -d ' ')
        RES=$(printf '{"path":".ax/MEMORY.md","bytes":%s,"dry_run":true}' "${BYTES:-0}")
        json_output "ok" "$RES" "미리보기만 — 파일 안 썼어요"
    else
        printf '%s\n' "$CONTENT"
        printf '\n(dry-run — .ax/MEMORY.md 안 썼어요)\n' >&2
    fi
    exit "$EXIT_OK"
fi

# 원자적 기록
mkdir -p .ax
TMP=".ax/MEMORY.md.tmp.$$"
if printf '%s\n' "$CONTENT" > "$TMP" 2>/dev/null; then
    mv "$TMP" .ax/MEMORY.md
else
    rm -f "$TMP"
    if [ "$JSON_MODE" = true ]; then json_error ".ax/MEMORY.md 기록 실패"; else goax_error ".ax/MEMORY.md 기록 실패"; exit "$EXIT_ERROR"; fi
fi

BYTES=$(wc -c < .ax/MEMORY.md 2>/dev/null | tr -d ' ')
LINES=$(wc -l < .ax/MEMORY.md 2>/dev/null | tr -d ' ')

if [ "$JSON_MODE" = true ]; then
    RES=$(printf '{"path":".ax/MEMORY.md","bytes":%s,"lines":%s}' "${BYTES:-0}" "${LINES:-0}")
    json_output "ok" "$RES" "MEMORY.md 재생성 — triage 가 가장 먼저 읽는 포인터 인덱스"
else
    goax_log "MEMORY.md 재생성 — ${LINES:-0}줄 / ${BYTES:-0}B"
fi

exit "$EXIT_OK"
