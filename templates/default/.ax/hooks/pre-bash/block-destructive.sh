#!/usr/bin/env bash
# pre-bash hook — 파괴적 명령 안전망 (mode-aware)
#
# ⚠️ 성격: 이 훅은 **보안 경계가 아니라 사고 방지용 안전망**이에요.
#    셸 명령 문자열은 같은 동작을 무한히 다른 표기로 쓸 수 있어서, 문자열 매칭으로
#    "모든" 파괴적 명령을 막는 건 원리적으로 불가능해요. 이 훅의 목표는
#    *의도치 않은 사고* (에이전트/사람의 실수) 를 잡는 거지, 우회하려는 상대를
#    막는 게 아니에요. 신뢰 경계가 필요하면 샌드박스·권한 분리로 해결하세요.
#    → .ax/docs/reference/rule-enforcement.md "집행 강도" 참고.
#
# Claude Code 공식 hook 입력: stdin JSON ({tool_name, tool_input.command, ...}).
# 차단은 exit 2. 경고는 stderr + exit 0.
#
# 두 단계:
#   1. CATASTROPHIC — mode 무관 항상 차단 (복구 불가)
#   2. RECOVERABLE  — mode-aware (warning: 경고, fail: 차단)

set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

# stdin JSON 파싱 — fallback chain: stdin → 구식 env var → argv (직접 실행 호환)
INPUT="$(cat 2>/dev/null || true)"
CMD=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
fi
CMD="${CMD:-${CLAUDE_BASH_COMMAND:-${1:-}}}"
if [ -z "$CMD" ]; then
    # stdin 은 왔는데 명령을 못 뽑았으면 jq 가 없는 거예요. fail-open 은 유지하되 침묵하진 않아요 —
    # 조용히 통과하면 `rm -rf /etc` 가 아무 출력 없이 exit 0 이고, 안전망이 꺼진 걸 아무도 몰라요.
    if [ -n "$INPUT" ] && ! command -v jq >/dev/null 2>&1; then
        printf '[goax] jq 없음 — 이 안전망이 비활성 상태예요 (파괴적 명령 차단)\n' >&2
    fi
    exit 0
fi

# 정규화 — 표기 변형 흡수 (`rm -rf "/"`, `rm  -rf   /`, 탭 구분 등).
# 따옴표 제거는 의도적: 셸이 어차피 벗겨내므로 인용 여부로 우회되면 안 돼요.
# `\047` = ' , `\042` = "
NORM=$(printf '%s' "$CMD" | tr -d '\047\042' | tr '\t\n' '  ' | sed -E 's/  +/ /g')

# PROJECT_ROOT 결정: CLAUDE_PROJECT_DIR → BASH_SOURCE 기반 fallback (이 hook은 .ax/hooks/pre-bash/에 있음)
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"

SENSOR_MODE="warning"
if [ -f "$COMMON" ]; then
    # shellcheck source=../../scripts/bash/common.sh
    source "$COMMON"
    SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning)
fi

# ─── 매처 헬퍼 ──────────────────────────────────────────────────────
# 정규화된 명령에 대해 확장 정규식 매칭.
matches() { printf '%s' "$NORM" | grep -qE "$1"; }

# `rm` 이 **명령어 위치**에 있는지 (confirm·npm 같은 부분 일치 배제).
# 앞이 줄머리이거나 셸 구분자([;&|(]) 또는 공백. `git rm`, `sudo rm` 도 포함돼요.
RM_INVOKED='(^| |[;&|(])rm '

# 재귀 플래그 — short(-r/-R, 다른 플래그와 결합 가능) 또는 long(--recursive).
# `-fvR`, `-r`, `-fr`, `--recursive` 전부 매칭. `-v`, `-f` 단독은 미매칭 (의도).
RM_RECURSIVE=' (-[[:alnum:]]*[rR][[:alnum:]]*|--recursive)( |$)'

# 파괴적 대상 경로 — 루트 자체, 루트 글롭, 시스템 최상위 디렉토리.
# `/tmp/x`, `/home/me/proj` 같은 일반 경로는 의도적으로 미매칭.
#   ` / `      → 루트 자체 (rm -rf -- / 포함, `--` 는 앞의 ` ` 로 흡수)
#   ` /* `     → 루트 글롭 — **`rm -rf /` 와 달리 OS 가 막지 않는 실제 위험 형태**
#   ` /usr ` 등 → 시스템 디렉토리 (뒤에 /* 붙어도 매칭)
ROOT_TARGET=' (/|/\*|/(usr|etc|var|bin|sbin|lib|lib64|opt|boot|dev|proc|sys|root|home|srv|System|Library|Applications|Users|Volumes|private)(/\*)?)( |$)'

# 홈 디렉토리 전체 — 루트만큼은 아니지만 사용자 데이터 전멸.
HOME_TARGET=' (~|~/\*|\$HOME|\$HOME/\*|\$\{HOME\}|\$\{HOME\}/\*)( |$)'

# ─── 1) CATASTROPHIC — 복구 불가, mode 무관 항상 차단 ────────────────
CATASTROPHIC_HIT=""

# 1-a. 재귀 rm + 루트/시스템 경로 (두 조건 동시 충족 시에만 — false positive 최소화)
if matches "$RM_INVOKED" && matches "$RM_RECURSIVE" && matches "$ROOT_TARGET"; then
    CATASTROPHIC_HIT="재귀 rm + 루트/시스템 경로"
fi

# 1-b. 재귀 rm + 홈 디렉토리 전체
if [ -z "$CATASTROPHIC_HIT" ] && matches "$RM_INVOKED" && matches "$RM_RECURSIVE" && matches "$HOME_TARGET"; then
    CATASTROPHIC_HIT="재귀 rm + 홈 디렉토리 전체"
fi

# 1-c. rm 이 아닌 경로로 대량 삭제 — find -delete / find -exec rm
if [ -z "$CATASTROPHIC_HIT" ] \
   && matches '(^| |[;&|(])find ' \
   && matches "$ROOT_TARGET" \
   && matches ' (-delete( |$)|-exec +rm )'; then
    CATASTROPHIC_HIT="find 를 통한 루트/시스템 경로 대량 삭제"
fi

# 1-d. 단독으로 복구 불가한 명령들
if [ -z "$CATASTROPHIC_HIT" ]; then
    for p in \
        'mkfs\.' \
        ':\( *\) *\{ *: *\| *: *& *\} *;:' \
        'dd .*of=/dev/[a-z]' \
        '(^| |[;&|(])chmod +(-R|--recursive) +[0-7]*777 +/( |$)' \
        '(^| |[;&|(])chown +(-R|--recursive) +[^ ]+ +/( |$)' \
        '> */dev/(sd|nvme|disk|hd)[a-z0-9]'
    do
        if matches "$p"; then CATASTROPHIC_HIT="$p"; break; fi
    done
fi

if [ -n "$CATASTROPHIC_HIT" ]; then
    printf '\033[31m[goax hook]\033[0m 🚨 CATASTROPHIC 명령 차단 (mode 무관): %s\n' "$CATASTROPHIC_HIT" >&2
    printf '명령: %s\n' "$CMD" >&2
    printf '복구 불가능한 삭제로 보여요. 의도한 게 맞으면 사용자에게 확인받고 직접 실행해.\n' >&2
    exit 2
fi

[ "$SENSOR_MODE" = "off" ] && exit 0

# ─── 2) RECOVERABLE — mode-aware ────────────────────────────────────
RECOVERABLE_HIT=""

# 2-a. 재귀 rm + 상위 경로(..) — 범위가 의도보다 넓을 가능성
# 옛 매처 ' (\.\.|\.\./\*)( |$)' 는 `..` 뒤에 `/` 가 오면 미매칭이라 `rm -rf ..` 는 잡고
# 더 위험한 `rm -rf ../..`·`../../etc`·`../../../` 는 그냥 통과시켰어요 (위험도 역전).
# 이제 `..` 로 시작하는 경로 전체를 봐요: `..`, `../*`, `../..`, `../../etc`, `../../../`, `../foo`.
PARENT_TARGET=' (\.\.(/\.\.)*(/[^ ]*)?|\.\./\*)( |$)'
if matches "$RM_INVOKED" && matches "$RM_RECURSIVE" && matches "$PARENT_TARGET"; then
    RECOVERABLE_HIT="재귀 rm + 상위 디렉토리(..)"
fi

# 2-b. 히스토리/원격 되돌리기 계열
if [ -z "$RECOVERABLE_HIT" ]; then
    for p in \
        'git +push +.*(--force( |$)|-f( |$))' \
        'git +push +.*--force-with-lease' \
        'git +reset +--hard +(origin|HEAD~|main|master)' \
        'git +clean +-[a-z]*[xX][a-z]*d' \
        '(^| |[;&|(])sudo +rm '
    do
        if matches "$p"; then RECOVERABLE_HIT="$p"; break; fi
    done
fi

if [ -n "$RECOVERABLE_HIT" ]; then
    if [ "$SENSOR_MODE" = "fail" ]; then
        printf '\033[31m[goax hook]\033[0m 차단된 파괴적 패턴 (mode=fail): %s\n' "$RECOVERABLE_HIT" >&2
        printf '명령: %s\n' "$CMD" >&2
        printf '우회가 필요하면 사용자에게 명시적 승인을 받아 직접 실행해.\n' >&2
        exit 2
    fi
    printf '\033[33m[goax hook]\033[0m ⚠ 파괴적 패턴 (mode=%s, 경고만): %s\n' "$SENSOR_MODE" "$RECOVERABLE_HIT" >&2
    printf '명령: %s\n' "$CMD" >&2
    exit 0
fi

exit 0
