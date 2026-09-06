#!/usr/bin/env bash
# pre-commit hook — CRITICAL 룰 패턴을 staged 파일에서 검출
#
# Dual-use:
#   1) git pre-commit symlink: exit 1+ → commit 차단
#   2) Claude Code PreToolUse:Bash on `git commit`: exit 2 → tool call 차단
#
# 위반 발견 시:
#   - mode=fail   → exit 2 (차단)
#   - mode=warn   → stderr 경고 + exit 0
# mistake 기록은 사용자 명시 `mistake` skill 호출로만 — hook 자동 capture 폐기.

set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONSTITUTION="$PROJECT_ROOT/CLAUDE.md"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"

[ -f "$CONSTITUTION" ] || { echo "[goax] CLAUDE.md 없음 — skip" >&2; exit 0; }

# secrets 패턴은 common.sh 의 표에서 나와요 (goax_secret_patterns). 없으면 검사할 게 없는데,
# 조용히 통과하면 안전망이 꺼진 걸 아무도 몰라요 — 가장 흔한 부재 시점이 provision 중간이에요
# (`.ax/hooks` 는 이미 있고 `.ax/scripts/bash` 는 아직 없는 창). 그래서 시끄럽게 통과해요.
if [ ! -f "$COMMON" ]; then
    printf '[goax] common.sh 없음 — secrets 안전망 비활성 (.ax/scripts/bash/common.sh 복구 필요)\n' >&2
    exit 0
fi
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"
SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning)

[ "$SENSOR_MODE" = "off" ] && exit 0

VIOLATIONS=0

# 위반 보고 (counter 증가만 — mistake 기록은 사용자 명시 mistake skill 로)
report() {
    local category="$1"; local message="$2"; local detail="${3:-}"
    printf '  ⚠ %s\n' "$message" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
}

STAGED=$(git diff --cached --name-only 2>/dev/null || true)
[ -z "$STAGED" ] && { echo "[goax] staged 파일 없음" >&2; exit 0; }

echo "[goax] CRITICAL 룰 검사 (mode=$SENSOR_MODE) — 대상 $(echo "$STAGED" | wc -l | tr -d ' ')개 파일"

# ─── 프로젝트 CRITICAL 패턴 (스캐폴드) ──────────────────────────────
#goax-grep-scaffold — 이 마커는 "프로젝트 패턴 미작성" 신호. AGENTS.md 의 🔴 룰에서
# grep 가능한 패턴을 뽑아 아래에 채우고, 채우면 이 마커 라인을 지우세요 (doctor 가 감지).
#
# 작성 예시 (실룰이 아니라 형식 참고용 — 그대로 켜지 않아요):
#   while IFS= read -r f; do
#       [ -z "$f" ] || [ ! -f "$f" ] && continue
#       case "$f" in
#           *.ts|*.tsx)
#               # 예: 사용자 노출 카피에 내부 용어 금지 (XX:CRITICAL:001)
#               if grep -qE '(내부용어A|내부용어B)' "$f" 2>/dev/null; then
#                   report "internal-terms" "$f: 내부 용어 노출 — XX:CRITICAL:001"
#               fi
#               ;;
#       esac
#   done <<< "$STAGED"
#
# 주의: 여기 검출은 "grep 으로 잡히는 표면 위반"용 보조 그물이에요. 본 집행(테스트·린트)이
# 있는 룰은 그쪽을 pre-commit/CI 에서 직접 실행하는 별도 훅 파일로 두세요 —
# .ax/hooks/pre-commit/ 의 *.sh 는 전부 자동 chain 되고, exit 2 가 커밋을 차단해요.

# ─── secrets 검출 ───────────────────────────────────────────────────
# 패턴은 여기 없어요 — `common.sh` 의 `goax_secret_rules` 표가 SSOT 이고, 검출(여기)과
# 마스킹(`redact_secrets`)이 같은 행에서 나와요. 예전엔 이 파일이 자기 상수를 따로 들고 있어서
# 두 곳이 여덟 축에서 갈라졌고, 한쪽만 잡는 형태(웹훅은 마스킹만·`pg_key` 는 마스킹만)가 실제로
# 생겼어요. 형태를 하나 더할 땐 그 표에만 행을 넣으세요.
#
# 표는 두 갈래를 담아요:
#   ① 토큰 형태 — 발급처가 형식을 정해둔 것. 대소문자 그대로 봐야 오탐이 안 늘어요
#   ② 일반 key=value — 값 첫 글자에서 `$`·`<`·`{`·`%`·`(` 를 빼서 `${GITHUB_TOKEN}`·`<from env>`
#      같은 참조 표기를 오탐하지 않아요. 값은 6자 이상이라 `secret: null`·`token_count = 0` 도 안 걸려요
#      (키 이름의 대소문자는 표가 브래킷으로 담고 있어서 `grep -i` 가 필요 없어요)
#
# `grep` 의 `-e` 는 필수예요 — PEM 행이 `-----` 로 시작해서, 빼면 옵션으로 읽혀 rc=2 가 나고
# 그 한 종이 조용히 미탐돼요.
SECRET_PATTERNS=$(goax_secret_patterns)

SECRET_FILES=""
while IFS= read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    hit=""
    while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        if grep -qIE -e "$pat" "$f" 2>/dev/null; then hit="$pat"; break; fi
    done <<< "$SECRET_PATTERNS"
    # 매칭된 줄은 안 찍어요 — 시크릿을 stderr·로그로 다시 흘리면 검출한 의미가 없어요
    [ -n "$hit" ] && SECRET_FILES="${SECRET_FILES}${f}"$'\n'
done <<< "$STAGED"
if [ -n "$SECRET_FILES" ]; then
    SECRET_N=$(printf '%s' "$SECRET_FILES" | grep -c . || true)
    report "secrets" "Secrets 추정 패턴 — ${SECRET_N}개 파일: $(printf '%s' "$SECRET_FILES" | tr '\n' ' ')"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
    if [ "$SENSOR_MODE" = "fail" ]; then
        echo "[goax] ✗ CRITICAL 위반 ${VIOLATIONS}건 — 차단 (mode=fail)" >&2
        exit 2
    fi
    echo "[goax] ⚠ CRITICAL 위반 ${VIOLATIONS}건 — 경고만 (mode=$SENSOR_MODE). 기록 원하면 mistake skill 호출" >&2
    exit 0
fi

echo "[goax] ✓ CRITICAL 검사 통과 (mode=$SENSOR_MODE)"
exit 0
