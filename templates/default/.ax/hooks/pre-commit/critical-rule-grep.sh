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

# common.sh 사용 가능하면 goax_mode 통일 helper 활용
SENSOR_MODE="warning"
if [ -f "$COMMON" ]; then
    # shellcheck source=../../scripts/bash/common.sh
    source "$COMMON"
    SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning)
else
    CONFIG="$PROJECT_ROOT/.ax/config.yml"
    [ -f "$CONFIG" ] && SENSOR_MODE=$(grep -E '^[[:space:]]*mode:' "$CONFIG" | head -1 | awk '{print $2}' || echo warning)
fi

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
# 옛 정규식은 `(password|secret|api[_-]?key|token).*=.*["']` 하나였어요. 대소문자를 가리고
# `=` 와 따옴표를 둘 다 요구해서, 실검체 9종(AKIA·ghp_·xox·sk_live·sk-·PEM·JWT·`PASSWORD=`·`password:`)
# 을 **전부** 놓쳤어요 — `templates/zero/probe/examples/secret-scan.sh` 가 자기 프로브에서
# PROBE FAILED 를 냈고요. `common.sh` 의 `redact_secrets` 는 이 토큰 형태들을 이미 알고 있었는데
# 여기서 안 쓰고 있었어요 (redact 는 sed 치환용이라 검출용으로 그대로 못 씀 → 같은 패턴 세트를 여기 둬요).
#
# 두 갈래로 봐요:
#   ① 토큰 형태 — 발급처가 형식을 정해둔 것. 대소문자 그대로 봐야 오탐이 안 늘어요
#   ② 일반 key=value — 대소문자 무시. 값 첫 글자에서 `$`·`<`·`{`·`%`·`(` 를 빼서
#      `${GITHUB_TOKEN}`·`<from env>` 같은 참조 표기를 오탐하지 않아요. 값은 6자 이상이라
#      `secret: null`·`token_count = 0` 도 안 걸려요
SECRET_SHAPES='AKIA[0-9A-Z]{16}
gh[posru]_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{20,}
xox[abprs]-[A-Za-z0-9-]{10,}
(sk|pk|rk)_live_[A-Za-z0-9]{16,}
sk-(ant|proj)-[A-Za-z0-9_-]{20,}
sk-[A-Za-z0-9]{20,}
AIza[0-9A-Za-z_-]{35}
npm_[A-Za-z0-9]{30,}
whsec_[A-Za-z0-9]{20,}
-----BEGIN [A-Z ]*PRIVATE KEY-----
eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
SECRET_KV='(password|passwd|secret|api[_-]?key|access[_-]?key|token|bearer)[[:space:]]*[:=][[:space:]]*['"'"'"]?[^[:space:]'"'"'"$<{%(][^[:space:]'"'"'"]{5,}'

SECRET_FILES=""
while IFS= read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    hit=""
    while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        if grep -qIE -e "$pat" "$f" 2>/dev/null; then hit="$pat"; break; fi
    done <<< "$SECRET_SHAPES"
    [ -z "$hit" ] && grep -qIEi -e "$SECRET_KV" "$f" 2>/dev/null && hit="key=value"
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
