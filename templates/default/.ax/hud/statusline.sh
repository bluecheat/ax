#!/usr/bin/env bash
# .ax/hud/statusline.sh — goax HUD. 하네스 위치만, OMC HUD 의 문법으로
# .claude/settings.json 의 statusLine.command 에서 호출 (Claude Code statusline 사양: stdin JSON, ANSI, 멀티라인)
#
# 보여주는 것 (한 줄, 프리셋 full 이면 둘째 줄):
#   [goax#0.5.1] | M×L2 · payment | spec ✓ › tasks ✓ › impl ● [######----]7/12 › review ○ | mistakes:3
#   ┬──────────   ┬──────────────   ┬──────────────────────────────────────────────────   ┬──────────
#   설치 버전      triage 결과        워크플로 체인 — 지금 어느 단계인지                          실수 누적
#   (plugin 이 새로우면 `-> 0.5.2 goax up`)
#
# 안 보여주는 것: 모델·ctx%·에이전트 수·todo (OMC HUD 몫) · 레인·게이트·경보 (skill 출력·doctor 몫)
#
# 구조는 OMC HUD 를 그대로 옮겼어요 — 요소를 각각 렌더해 배열에 담고 레이아웃 순서로 조립,
# 프리셋이 최대 줄 수를 정하고, 폭을 넘치면 ` | ` 경계에서 잘라요.
#   preset  minimal (1줄, 짧게) · focused (1줄, 기본) · full (2줄 — 둘째 줄에 spec 슬러그·tier·다음 단계)
#   bars    ascii (#-) 기본 · unicode (█░)
#   설정: .ax/config.yml 의 hud: { preset, bars }. 키가 없으면 focused · ascii.
#
# 읽는 파일: .ax/current-task.json · .ax/state.json(hud 캐시) · .ax/version · <spec>/tasks.md · .ax/mistakes/
# 스크립트는 하나도 안 불러요 — statusline 은 300ms 디바운스에 새 이벤트가 오면 취소돼서 50ms 안에 끝나야 해요.
# 실측 외부 명령 (bash -x 추적): COLUMNS 없이 focused 16회 · full 17회, COLUMNS 이 있으면 21회
# (폭 계산이 조각마다 awk 를 한 번 더 불러서 awk 5 → 10). 내역은 jq 3 · awk 5 · tr 2 ·
# find·date·cat·grep·head·wc 각 1 (+ full 이면 basename 1).
# ("jq 3회 + awk 1패스 + find 1회" 라고 적혀 있었는데 실제와 달랐어요 — 예산을 재려면 숫자가 맞아야 해요.)
# state.json 은 read-only (docs/state-ownership.md 규칙 2).
#
# stdin 은 전부 읽어요 (workspace.current_dir 이 필요). 다른 statusline 과 합칠 땐 합성 스크립트가
# stdin 을 변수로 받아 양쪽에 각각 먹여야 해요 — hud skill 의 [c] 참고. 출력은 개행으로 끝나요.

set -u

RESET=$'\033[0m'; DIM=$'\033[2m'; BOLD=$'\033[1m'
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'

INPUT=$(cat 2>/dev/null || echo '{}')
WS_DIR="."
if command -v jq >/dev/null 2>&1; then
    WS_DIR=$(printf '%s' "$INPUT" | jq -r '.workspace.current_dir // "."' 2>/dev/null || echo ".")
fi

# goax 미설치 / jq 없음 — 조용한 fallback
if [ ! -d "$WS_DIR/.ax" ] || ! command -v jq >/dev/null 2>&1; then
    printf '%sgoax%s\n' "$DIM" "$RESET"
    exit 0
fi

CT="$WS_DIR/.ax/current-task.json"
S="$WS_DIR/.ax/state.json"
CFG="$WS_DIR/.ax/config.yml"

# ── 설정 — config.yml hud: 블록 (없으면 focused · ascii) ──
PRESET="focused"; BARS="ascii"
if [ -f "$CFG" ]; then
    _hud=$(awk '/^hud:/{f=1;next} f && /^[^[:space:]]/{exit} f' "$CFG" 2>/dev/null)
    # 값 앞 공백을 먼저 떼고, 그다음 공백·주석부터 끝까지 잘라요 (순서가 바뀌면 값이 통째로 사라져요)
    _p=$(printf '%s\n' "$_hud" | awk -F: '/^[[:space:]]+preset:/{v=$2; sub(/^[[:space:]]+/,"",v); sub(/[[:space:]#].*$/,"",v); print v; exit}')
    _b=$(printf '%s\n' "$_hud" | awk -F: '/^[[:space:]]+bars:/{v=$2; sub(/^[[:space:]]+/,"",v); sub(/[[:space:]#].*$/,"",v); print v; exit}')
    case "$_p" in minimal|focused|full) PRESET="$_p" ;; esac
    case "$_b" in ascii|unicode) BARS="$_b" ;; esac
fi
case "$PRESET" in full) MAX_LINES=2 ;; *) MAX_LINES=1 ;; esac

# ── 상태 읽기 — jq 는 파일당 1회, 필드는 탭으로 한꺼번에 ──
# 구분자는 탭이 아니라 US(0x1f) — bash 의 read 는 IFS 가 공백류(탭 포함)면 빈 필드를 건너뛰어 값이 한 칸씩 밀려요
US=$'\x1f'
PHASE="idle"; SIZE=""; RISK=""; DOMAIN=""; TIER=""; SPEC_DIR=""
if [ -f "$CT" ]; then
    IFS="$US" read -r PHASE SIZE RISK DOMAIN TIER SPEC_DIR <<EOF
$(jq -r '[(.phase // "idle"), (.size // ""), (.risk // ""), (.domain // ""), (.spec_tier // ""), (.spec_dir // "")] | join("\u001f")' "$CT" 2>/dev/null)
EOF
fi
[ "$PHASE" = "null" ] && PHASE="idle"
[ "$SIZE" = "null" ] && SIZE=""; [ "$RISK" = "null" ] && RISK=""; [ "$DOMAIN" = "null" ] && DOMAIN=""
[ "$TIER" = "null" ] && TIER=""; [ "$SPEC_DIR" = "null" ] && SPEC_DIR=""

PLUGIN_VER=""; REVIEW_REQ=""; CACHED_AT=""
if [ -f "$S" ]; then
    IFS="$US" read -r PLUGIN_VER REVIEW_REQ CACHED_AT <<EOF
$(jq -r '[(.hud.plugin_version // ""), (.hud.review_required // ""), (.hud.cached_at // "")] | join("\u001f")' "$S" 2>/dev/null)
EOF
fi

INSTALLED=""
[ -f "$WS_DIR/.ax/version" ] && INSTALLED=$(grep -E '^goax:' "$WS_DIR/.ax/version" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '[:space:]')
[ -z "$INSTALLED" ] && [ -f "$WS_DIR/.ax/version" ] && INSTALLED=$(head -1 "$WS_DIR/.ax/version" | tr -d '[:space:]')

# ── 요소 ──────────────────────────────────────────────────
# 각 함수는 자기 조각을 출력하거나, 보여줄 게 없으면 아무것도 출력하지 않아요 (OMC 의 요소 맵과 같아요).

seg_version() {
    local tag="[goax#${INSTALLED:-?}]"
    if [ -n "$PLUGIN_VER" ] && [ -n "$INSTALLED" ] && [ "$PLUGIN_VER" != "$INSTALLED" ]; then
        # plugin 이 더 새로우면 (sort -V 로 큰 쪽이 plugin 이면) 업데이트 힌트 — OMC 의 "-> X omc update" 그대로
        local newest; newest=$(printf '%s\n%s\n' "$INSTALLED" "$PLUGIN_VER" | sort -V | tail -1)
        if [ "$newest" = "$PLUGIN_VER" ]; then
            printf '%s%s%s %s-> %s goax up%s' "$BOLD" "$tag" "$RESET" "$YELLOW" "$PLUGIN_VER" "$RESET"
            return
        fi
    fi
    printf '%s%s%s' "$BOLD" "$tag" "$RESET"
}

risk_color() { case "$1" in L3) printf '%s' "$RED" ;; L2) printf '%s' "$YELLOW" ;; L1) printf '%s' "$GREEN" ;; *) printf '%s' "$DIM" ;; esac; }
size_color() { case "$1" in XL) printf '%s' "$RED" ;; L) printf '%s' "$YELLOW" ;; M) printf '%s' "$CYAN" ;; *) printf '%s' "$DIM" ;; esac; }

seg_triage() {
    [ "$PHASE" = "idle" ] && { printf '%sidle%s' "$DIM" "$RESET"; return; }
    [ -z "$SIZE" ] && [ -z "$RISK" ] && return
    local out=""
    [ -n "$SIZE" ] && out="$(size_color "$SIZE")${SIZE}${RESET}"
    [ -n "$RISK" ] && out="${out}${DIM}×${RESET}$(risk_color "$RISK")${RISK}${RESET}"
    if [ "$PRESET" != "minimal" ] && [ -n "$DOMAIN" ] && [ "$DOMAIN" != "default" ]; then
        out="${out} ${DIM}·${RESET} ${DOMAIN}"
    fi
    printf '%s' "$out"
}

# tasks.md 진행 — awk 한 패스 (done|total). ``` 펜스 안은 형식 설명이라 건너뛰어요 —
# 세면 진행률이 부풀어서 갓 만든 spec 이 이미 뭔가 한 것처럼 보여요.
TASK_DONE=0; TASK_TOTAL=0
if [ -n "$SPEC_DIR" ] && [ -f "$WS_DIR/$SPEC_DIR/tasks.md" ]; then
    IFS='|' read -r TASK_DONE TASK_TOTAL <<EOF
$(awk '/^[[:space:]]*```/{fence=!fence; next} fence{next} /^- \[[xX]\] /{d++} /^- \[[ xX~]\] /{t++} END{printf "%d|%d", d+0, t+0}' "$WS_DIR/$SPEC_DIR/tasks.md" 2>/dev/null)
EOF
fi

bar() {   # $1 done $2 total → 10칸
    local d="$1" t="$2" fill=0 empty=10 f e
    [ "$t" -gt 0 ] && fill=$(( d * 10 / t )); empty=$(( 10 - fill ))
    if [ "$BARS" = "unicode" ]; then f='█'; e='░'; else f='#'; e='-'; fi
    local i out=""
    i=0; while [ $i -lt $fill ]; do out="$out$f"; i=$((i+1)); done
    out="$out$DIM"
    i=0; while [ $i -lt $empty ]; do out="$out$e"; i=$((i+1)); done
    printf '%s[%s%s%s]' "$GREEN" "$out" "$RESET" "$GREEN"
}

# 단계 기호: ✓ 완료(초록) · ● 진행(시안 bold, blocked 면 노랑) · ○ 남음(dim)
step() {   # $1 name $2 state(done|cur|todo|blocked) $3 extra
    local n="$1" st="$2" x="${3:-}"
    case "$st" in
        done)    printf '%s%s ✓%s' "$GREEN" "$n" "$RESET" ;;
        cur)     printf '%s%s%s ●%s' "$BOLD$CYAN" "$n" "$RESET$CYAN" "$RESET" ;;
        blocked) printf '%s%s ●%s' "$YELLOW" "$n" "$RESET" ;;
        *)       printf '%s%s ○%s' "$DIM" "$n" "$RESET" ;;
    esac
    [ -n "$x" ] && printf ' %s' "$x"
}

# ADR 단계 (full tier) — 이 spec 을 참조하는 ADR 이 있나
adr_done() {
    local id; id=$(basename "${SPEC_DIR:-}" | cut -d- -f1)
    [ -n "$id" ] && [ -d "$WS_DIR/.ax/docs/adr" ] && grep -lq -- "$id" "$WS_DIR/.ax/docs/adr/"[0-9]*.md 2>/dev/null
}

NEXT_STEP=""
seg_flow() {
    [ "$PHASE" = "idle" ] && return
    case "$SIZE" in
        S) case "$RISK" in L3) printf '%s사람 게이트 + ADR%s' "$YELLOW" "$RESET" ;; *) printf '%s즉시 작업 — spec 불필요%s' "$DIM" "$RESET" ;; esac; return ;;
    esac
    # 단계 상태
    local spec_st tasks_st impl_st review_st adr_st
    case "$PHASE" in
        triaged|spec)            spec_st=cur ;;
        spec_blocked)            spec_st=blocked ;;
        *)                       spec_st=done ;;
    esac
    case "$PHASE" in
        spec_checked)            tasks_st=cur ;;
        tasks|implementing|review) tasks_st=done ;;
        *)                       tasks_st=todo ;;
    esac
    case "$PHASE" in
        implementing)            impl_st=cur ;;
        review)                  impl_st=done ;;
        *)                       impl_st=todo ;;
    esac
    case "$PHASE" in review) review_st=cur ;; *) review_st=todo ;; esac
    if [ "$TIER" = "full" ]; then adr_st=todo; adr_done && adr_st=done; fi

    # 진행 표시는 impl 이 현재 단계일 때만 — 완료된 단계 옆의 2/3 는 거짓말이고, 시작 전 단계엔 0/N 이면 충분해요
    local prog=""
    if [ "$TASK_TOTAL" -gt 0 ]; then
        case "$impl_st" in
            cur)  if [ "$PRESET" = "minimal" ]; then prog="${TASK_DONE}/${TASK_TOTAL}"
                  else prog="$(bar "$TASK_DONE" "$TASK_TOTAL")${TASK_DONE}/${TASK_TOTAL}${RESET}"; fi ;;
            todo) [ "$tasks_st" = done ] && prog="${DIM}${TASK_DONE}/${TASK_TOTAL}${RESET}" ;;
        esac
    fi
    local sep="${DIM} › ${RESET}"
    if [ "$PRESET" = "minimal" ]; then
        # 현재 단계 하나만
        case "$PHASE" in
            triaged|spec|spec_blocked) step spec "$spec_st" ;;
            spec_checked) step tasks cur ;;
            tasks) step impl todo "$prog" ;;
            implementing) step impl cur "$prog" ;;
            review) step review cur ;;
        esac
        return
    fi
    local out; out="$(step spec "$spec_st")"
    [ "$TIER" = "full" ] && out="${out}${sep}$(step adr "$adr_st")"
    out="${out}${sep}$(step tasks "$tasks_st")${sep}$(step impl "$impl_st" "$prog")"
    [ "$REVIEW_REQ" = "required" ] && out="${out}${sep}$(step review "$review_st")"
    printf '%s' "$out"
    case "$PHASE" in
        triaged|spec|spec_blocked) NEXT_STEP="spec-validate" ;;
        spec_checked) NEXT_STEP="spec-tasks" ;;
        tasks) NEXT_STEP="spec-implement" ;;
        implementing) NEXT_STEP="tasks-gate" ;;
        review) NEXT_STEP="evaluator 리뷰" ;;
    esac
}

seg_mistakes() {
    local n=0
    [ -d "$WS_DIR/.ax/mistakes" ] && n=$(find "$WS_DIR/.ax/mistakes" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
    local c="$DIM"
    [ "$n" -ge 5 ] && c="$YELLOW"; [ "$n" -ge 10 ] && c="$RED"; [ "$n" -gt 0 ] && [ "$n" -lt 5 ] && c=""
    printf '%smistakes:%s%s%s%s' "$DIM" "$RESET" "$c" "$n" "$RESET"
}

seg_stale() {   # hud 캐시가 30분 넘게 오래됐거나 없으면 — 거짓 초록을 안 만들려고
    [ "$PHASE" = "idle" ] && return
    local now_s cache_s
    now_s=$(date +%s)
    cache_s=0
    if [ -n "$CACHED_AT" ]; then
        cache_s=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$CACHED_AT" +%s 2>/dev/null \
                  || date -u -d "$CACHED_AT" +%s 2>/dev/null || echo 0)
    fi
    if [ "$cache_s" -eq 0 ] || [ $((now_s - cache_s)) -gt 1800 ]; then printf '%s(stale)%s' "$DIM" "$RESET"; fi
}

seg_detail() {   # full 프리셋 둘째 줄
    [ "$PHASE" = "idle" ] && return
    local slug; slug=$(basename "${SPEC_DIR:-}")
    [ -n "$slug" ] && [ "$slug" != "." ] || return
    printf '%s%s · tier %s · 다음: %s%s' "$DIM" "$slug" "${TIER:-?}" "${NEXT_STEP:-?}" "$RESET"
}

# ── 조립 — 레이아웃 순서, 빈 조각은 빠짐, 폭 넘치면 ` | ` 경계에서 잘라요 ──
SEP="${DIM} | ${RESET}"
MAIN=()
for f in seg_version seg_triage seg_flow seg_mistakes seg_stale; do
    piece=$("$f")
    [ -n "$piece" ] && MAIN+=("$piece")
done

# 가시 폭 — ANSI 를 걷어내고 한글·CJK 를 2칸으로 세요. `wc -m` 은 글자 수라 한글 도메인·슬러그가
# 1칸으로 잡혀서, 실제로는 넘치는 줄이 안 잘렸어요. LC_ALL=C 로 awk 를 바이트 모드로 돌린 뒤
# UTF-8 을 직접 디코드해요 — 로케일에 안 흔들리고, sed|wc|tr 3프로세스를 awk 1개로 줄여요.
# 폭 2 는 한글 자모/음절 · CJK · 전각만. ✓ ● › ⚠ 같은 Ambiguous 기호는 1칸 그대로예요 (기존 동작 유지).
_HUD_WIDTH_AWK=$'
BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
function wide(c) {
    return (c >= 4352  && c <= 4447)  ||
           (c >= 11904 && c <= 42191) ||
           (c >= 44032 && c <= 55203) ||
           (c >= 63744 && c <= 64255) ||
           (c >= 65072 && c <= 65135) ||
           (c >= 65280 && c <= 65376) ||
           (c >= 65504 && c <= 65510)
}
{
    s = $0
    gsub(/\033\\[[0-9;]*[A-Za-z]/, "", s)
    n = length(s); i = 1
    while (i <= n) {
        b = ord[substr(s, i, 1)]
        if (b < 128)      { w += 1; i += 1 }
        else if (b < 224) { w += 1; i += 2 }
        else if (b < 240) {
            cp = (b % 16) * 4096 + (ord[substr(s, i+1, 1)] % 64) * 64 + (ord[substr(s, i+2, 1)] % 64)
            w += wide(cp) ? 2 : 1
            i += 3
        }
        else { w += 2; i += 4 }
    }
}
END { print w+0 }'

visible_width() { printf '%s' "$1" | LC_ALL=C awk "$_HUD_WIDTH_AWK"; }

COLS="${COLUMNS:-0}"
LINE=""
for piece in "${MAIN[@]}"; do
    cand="$LINE"; [ -n "$cand" ] && cand="${cand}${SEP}"; cand="${cand}${piece}"
    if [ "$COLS" -gt 0 ] && [ "$(visible_width "$cand")" -gt "$COLS" ] && [ -n "$LINE" ]; then break; fi
    LINE="$cand"
done
printf '%s\n' "$LINE"

if [ "$MAX_LINES" -ge 2 ]; then
    detail=$(seg_detail)
    [ -n "$detail" ] && printf '%s\n' "$detail"
fi
exit 0
