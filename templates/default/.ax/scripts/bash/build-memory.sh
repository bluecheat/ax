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
#   bash build-memory.sh             # .ax/MEMORY.md 재생성 (기본)
#   bash build-memory.sh --json      # 생성 요약 JSON (파일도 씀)
#   bash build-memory.sh --dry-run   # 내용 미리보기만 (파일 안 씀)
#   bash build-memory.sh --no-preview  # 룰 프리뷰 빼고 토큰+경로만 (토큰 최소)
#   bash build-memory.sh --lean      # 강제 lean — 모듈/ADR/spec/mistakes 열거 생략
#   bash build-memory.sh --full      # 강제 full — 크기 게이트 무시하고 전체 열거
#   bash build-memory.sh --help
#
# 크기 게이트: 인덱스가 가리킬 본문 합계 < GOAX_MEMORY_LEAN_BYTES(기본 12000)면 자동 lean.
#   작은 프로젝트에선 인덱스가 오버헤드라 열거를 접고 포인터만 남겨요(룰·현재작업은 유지).
# 의존: grep, sed, awk, find. jq 권장(현재 작업 파싱) — 없으면 그 섹션만 생략.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

JSON_MODE=false
DRY_RUN=false
SHOW_HELP=false
NO_PREVIEW=false      # 룰 프리뷰 끄고 토큰+경로만 (토큰 최소 모드)
FORCE_LEAN=false      # 크기 게이트 무시하고 강제 lean
FORCE_FULL=false      # 크기 게이트 무시하고 강제 full

while [ $# -gt 0 ]; do
    case "$1" in
        --json)       JSON_MODE=true ;;
        --dry-run)    DRY_RUN=true ;;
        --no-preview) NO_PREVIEW=true ;;
        --lean)       FORCE_LEAN=true ;;
        --full)       FORCE_FULL=true ;;
        --help|-h)    SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    # 선두 주석 블록(연속 '#' 라인)만 출력 — 헤더가 길어져도 코드까지 새지 않음
    awk 'NR>=2 && /^#/ { sub(/^# ?/, ""); print; next } NR>=2 { exit }' "${BASH_SOURCE[0]}"
    exit "$EXIT_OK"
fi

WS="${CLAUDE_PROJECT_DIR:-$(find_project_root 2>/dev/null || pwd)}"
cd "$WS" 2>/dev/null || { goax_error "프로젝트 루트 진입 실패: $WS"; exit "$EXIT_ERROR"; }

HAS_JQ=false
if command -v jq >/dev/null 2>&1; then HAS_JQ=true; fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Constitution 파일 — 0.2.0 부터 AGENTS.md 가 SSOT 본문이고 CLAUDE.md 는 `@AGENTS.md`
# alias(시그널 라인 없음). 그래서 "먼저 존재하는 파일" 이 아니라 "실제 룰 시그널(🔴/🟡 **`)
# 을 가진 파일" 을 골라요 — alias 를 잘못 집어 룰 0개로 보이던 버그 방지.
RULES_FILE=""
for _cand in AGENTS.md CLAUDE.md; do
    if [ -f "$_cand" ] && grep -qE '^(🔴|🟡) \*\*`' "$_cand" 2>/dev/null; then
        RULES_FILE="$_cand"; break
    fi
done
# 룰 시그널이 어디에도 없으면(룰 0개 프로젝트) 존재하는 SSOT 파일이라도 가리켜요
[ -z "$RULES_FILE" ] && [ -f AGENTS.md ] && RULES_FILE="AGENTS.md"
[ -z "$RULES_FILE" ] && [ -f CLAUDE.md ] && RULES_FILE="CLAUDE.md"

# 현재 작업 domain 토큰 — D2 personalization 의 relevance 기준.
# ADR/spec/module slug 이 이 토큰을 포함하면 ★ 로 끌어올려요(Aider repo map 의
# "현재 컨텍스트로 편향" 을 cheap substring 으로 근사). 작업이 없으면 빈 값 → 최신순만.
TASK_DOMAINS=""
if [ "$HAS_JQ" = true ] && [ -f .ax/current-task.json ]; then
    TASK_DOMAINS=$(jq -r '.domain // ""' .ax/current-task.json 2>/dev/null | tr ',' ' ' | tr 'A-Z' 'a-z')
    [ "$TASK_DOMAINS" = "null" ] && TASK_DOMAINS=""
fi

# ── D1: 룰 프리뷰 — 원문 줄바꿈을 join 해 첫 문장(들)을 예산 안에서 그대로 노출 ──
# 시그널 라인 다음의 연속 설명 라인을 빈 줄 / '- ' 메타 전까지 이어붙인 뒤 cap 바이트로
# 자르되 마지막 공백/마침표 경계에서 끊고 '…' 표기. (예전엔 첫 물리 라인만 잡아
# '단방향:' 처럼 wrap 지점에서 끊겨 핵심 제약이 통째로 빠졌음)
emit_rules() {
    local sev="$1"
    [ -n "$RULES_FILE" ] || return 0
    awk -v sev="$sev" -v rf="$RULES_FILE" -v cap=180 -v max=12 -v nopre="$NO_PREVIEW" '
    function flush(   t) {
        if (tok == "") return
        pr++
        if (pr > max) { skipped++; tok=""; txt=""; return }
        if (nopre == "true") { printf "- `%s` → %s:%d\n", tok, rf, ln; tok=""; txt=""; return }
        t = txt
        gsub(/`/, "", t)
        gsub(/[ \t]+/, " ", t)
        sub(/^ +/, "", t); sub(/ +$/, "", t)
        if (length(t) > cap) {
            t = substr(t, 1, cap)
            sub(/[^ .][^ .]*$/, "", t)
            sub(/ +$/, "", t)
            t = t " …"
        }
        printf "- `%s` → %s:%d  %s\n", tok, rf, ln, t
        tok = ""; txt = ""
    }
    $0 ~ ("^" sev " [*][*]`") {
        flush()
        ln = NR
        tok = $0; sub(/^[^`]*`/, "", tok); sub(/`.*/, "", tok)
        txt = $0; sub(/^[^`]*`[^`]*`[*][*][ \t]*/, "", txt)
        cap_on = 1
        next
    }
    cap_on == 1 {
        if ($0 ~ /^[ \t]*$/ || $0 ~ /^-[ \t]/) { flush(); cap_on = 0; next }
        txt = txt " " $0
        next
    }
    END { flush(); if (skipped > 0) printf "  … +%d more → %s\n", skipped, rf }
    ' "$RULES_FILE"
}

# ── D2+D3: ADR/spec 랭킹 — 현재 작업 관련(★) 우선 → 최신순, 예산 max + 초과 명시 ──
# emit_ranked <mode:adr|spec> <dir> <max>. silent tail-10 대신 ★ 우선·예산·'… +N more'.
emit_ranked() {
    local mode="$1" dir="$2" max="$3" files
    if [ "$mode" = "adr" ]; then
        files=$(find "$dir" -maxdepth 1 -name '[0-9]*-*.md' 2>/dev/null | sort)
    else
        files=$(find "$dir" -mindepth 2 -name 'spec.md' 2>/dev/null | sort)
    fi
    [ -n "$files" ] || return 0
    printf '%s\n' "$files" | awk -v mode="$mode" -v domains="$TASK_DOMAINS" -v max="$max" -v dir="$dir" '
    BEGIN { nd = split(domains, D, " ") }
    {
        p = $0; n++; pth[n] = p
        if (mode == "adr") {
            slug = p; sub(/.*\//, "", slug); sub(/\.md$/, "", slug)
            title = ""
            while ((getline line < p) > 0) {
                if (line ~ /^#[ \t]/) { title = line; sub(/^#+[ \t]*/, "", title); break }
            }
            close(p)
            if (title == "") title = slug
            if (length(title) > 70) { title = substr(title, 1, 70); sub(/[^ ][^ ]*$/, "", title); title = title "…" }
            disp[n] = title
        } else {
            slug = p; sub(/\/spec\.md$/, "", slug); sub(/.*\//, "", slug)
            disp[n] = slug
        }
        num = slug; sub(/-.*/, "", num); numk[n] = num + 0
        rel = 0; ls = tolower(slug)
        for (j = 1; j <= nd; j++) {
            if (D[j] == "" || D[j] == "—") continue
            if (index(ls, D[j]) > 0) { rel = 1; break }
        }
        relv[n] = rel
    }
    END {
        shown = 0
        for (pass = 1; pass <= 2; pass++) {
            want = (pass == 1) ? 1 : 0
            cnt = 0
            for (i = 1; i <= n; i++) if (relv[i] == want) bucket[++cnt] = i
            for (a = 2; a <= cnt; a++) {
                v = bucket[a]; b = a - 1
                while (b >= 1 && numk[bucket[b]] < numk[v]) { bucket[b+1] = bucket[b]; b-- }
                bucket[b+1] = v
            }
            for (a = 1; a <= cnt; a++) {
                i = bucket[a]
                if (shown >= max) { skipped++; continue }
                printf "- %s%s → %s\n", (relv[i] ? "★ " : ""), disp[i], pth[i]
                shown++
            }
        }
        if (skipped > 0) printf "  … +%d more → %s\n", skipped, dir
    }
    '
}

# ── 본문 생성 (stdout 로 모은 뒤 한 번에 기록) ──
emit_memory() {
    printf '# MEMORY.md — goax 빠른 회상 인덱스 (자동 생성 · 직접 편집 금지)\n'
    printf '<!-- build-memory.sh 가 .ax/ 상태에서 재생성. triage 가 가장 먼저 읽는 1줄 포인터 인덱스. -->\n'
    printf '_생성: %s_\n' "$NOW"
    [ -n "$MODE_NOTE" ] && printf '%s\n' "$MODE_NOTE"
    printf '\n'

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
        emit_rules '🔴'
        printf '\n## 🟡 MANDATORY 룰 (%s)\n' "${mand_n:-0}"
        emit_rules '🟡'
        printf '\n'
    fi

    # 모듈 (name + keywords)
    local mod_n=0
    if [ -d .ax/modules ]; then
        mod_n=$(find .ax/modules -mindepth 2 -maxdepth 2 -name 'rules.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$LEAN" = true ]; then
        printf '## 모듈 (%s) → .ax/modules/\n\n' "$mod_n"
    else
        printf '## 모듈 (%s)\n' "$mod_n"
        if [ "$mod_n" -gt 0 ]; then
            local md name kw star
            for md in .ax/modules/*/rules.md; do
                [ -f "$md" ] || continue
                name=$(printf '%s' "$md" | sed -E 's#\.ax/modules/([^/]+)/rules\.md#\1#')
                kw=$(grep -E '^keywords:' "$md" 2>/dev/null | head -1 | sed -E 's/^keywords:[[:space:]]*//' | awk '{print substr($0,1,80)}')
                star=""
                case " $TASK_DOMAINS " in *" $(printf '%s' "$name" | tr 'A-Z' 'a-z') "*) star="★ " ;; esac
                printf -- '- %s%s — keywords: %s → %s\n' "$star" "$name" "${kw:-—}" "$md"
            done
        fi
        printf '\n'
    fi

    # 최근 ADR — 현재 작업 관련(★) 우선 → 최신순 (예산 8 + 초과 시 … +N more)
    local adr_n=0
    if [ -d .ax/docs/adr ]; then
        adr_n=$(find .ax/docs/adr -maxdepth 1 -name '[0-9]*-*.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$LEAN" = true ]; then
        printf '## 최근 ADR (%s) → .ax/docs/adr/\n\n' "$adr_n"
    else
        if [ -n "$TASK_DOMAINS" ]; then
            printf '## 최근 ADR (%s)  ★=현재 작업 관련\n' "$adr_n"
        else
            printf '## 최근 ADR (%s)\n' "$adr_n"
        fi
        [ "$adr_n" -gt 0 ] && emit_ranked adr .ax/docs/adr 8
        printf '\n'
    fi

    # 열린 mistakes (카테고리별 수)
    local mis_n=0
    if [ -d .ax/mistakes ]; then
        mis_n=$(find .ax/mistakes -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$LEAN" = true ]; then
        printf '## 열린 mistakes (%s) → .ax/mistakes/\n\n' "$mis_n"
    else
        printf '## 열린 mistakes (%s)\n' "$mis_n"
        if [ "$mis_n" -gt 0 ]; then
            # frontmatter 의 category: 값으로 집계
            grep -hE '^category:' .ax/mistakes/*.md 2>/dev/null \
                | sed -E 's/^category:[[:space:]]*//' | tr -d '"' \
                | sort | uniq -c | sort -rn | head -10 \
                | awk '{cnt=$1; $1=""; sub(/^ /,""); printf "- %s: %s건 → .ax/mistakes/\n", $0, cnt}' || true
        fi
        printf '\n'
    fi

    # spec — 현재 작업 관련(★) 우선 → 최신순 (예산 8 + 초과 시 … +N more)
    local spec_n=0
    if [ -d .ax/docs/spec ]; then
        spec_n=$(find .ax/docs/spec -mindepth 2 -name 'spec.md' 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$LEAN" = true ]; then
        printf '## spec (%s) → .ax/docs/spec/\n\n' "$spec_n"
    else
        if [ -n "$TASK_DOMAINS" ]; then
            printf '## spec (%s)  ★=현재 작업 관련\n' "$spec_n"
        else
            printf '## spec (%s)\n' "$spec_n"
        fi
        [ "$spec_n" -gt 0 ] && emit_ranked spec .ax/docs/spec 8
        printf '\n'
    fi
}

# ── 크기 게이트 — 인덱스가 가리킬 '본문' 합계가 작으면 lean(열거 생략) ──
# 인덱스 비용은 항목 수에 비례하고, 이득은 회피한 본문 크기에 비례해요. 본문이 작으면
# (갓 install 한 greenfield 등) triage 가 그냥 glob 해 읽는 게 더 싸므로 열거를 접어요.
BODY_BYTES=$( { [ -n "$RULES_FILE" ] && cat "$RULES_FILE"; \
    find .ax/docs/adr .ax/docs/spec .ax/modules .ax/mistakes -type f -name '*.md' 2>/dev/null -exec cat {} + ; \
    } 2>/dev/null | wc -c | tr -d ' ')
BODY_BYTES=${BODY_BYTES:-0}
LEAN_THRESHOLD=${GOAX_MEMORY_LEAN_BYTES:-12000}

LEAN=false
LEAN_REASON=""
if [ "$FORCE_FULL" = true ]; then
    LEAN=false
elif [ "$FORCE_LEAN" = true ]; then
    LEAN=true; LEAN_REASON="강제 --lean"
elif [ "$BODY_BYTES" -lt "$LEAN_THRESHOLD" ]; then
    LEAN=true; LEAN_REASON="본문 ${BODY_BYTES}B < ${LEAN_THRESHOLD}B"
fi
# lean 은 토큰 최소가 목적이라 룰 프리뷰도 자동 off
[ "$LEAN" = true ] && NO_PREVIEW=true

MODE_NOTE=""
if [ "$LEAN" = true ]; then
    MODE_NOTE="_모드: lean (${LEAN_REASON}) — 섹션 열거 생략·룰 프리뷰 off (전체는 --full)_"
elif [ "$NO_PREVIEW" = true ]; then
    MODE_NOTE="_모드: full · 룰 프리뷰 off (토큰+경로만)_"
fi

CONTENT=$(emit_memory)

if [ "$DRY_RUN" = true ]; then
    if [ "$JSON_MODE" = true ]; then
        BYTES=$(printf '%s' "$CONTENT" | wc -c | tr -d ' ')
        RES=$(printf '{"path":".ax/MEMORY.md","bytes":%s,"dry_run":true,"mode":"%s","body_bytes":%s}' \
            "${BYTES:-0}" "$([ "$LEAN" = true ] && echo lean || echo full)" "${BODY_BYTES:-0}")
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

MODE=$([ "$LEAN" = true ] && echo lean || echo full)
if [ "$JSON_MODE" = true ]; then
    RES=$(printf '{"path":".ax/MEMORY.md","bytes":%s,"lines":%s,"mode":"%s","body_bytes":%s}' \
        "${BYTES:-0}" "${LINES:-0}" "$MODE" "${BODY_BYTES:-0}")
    json_output "ok" "$RES" "MEMORY.md 재생성 — triage 가 가장 먼저 읽는 포인터 인덱스"
else
    goax_log "MEMORY.md 재생성 — ${LINES:-0}줄 / ${BYTES:-0}B (${MODE})"
fi

exit "$EXIT_OK"
