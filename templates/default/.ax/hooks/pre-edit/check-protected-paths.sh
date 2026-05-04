#!/usr/bin/env bash
# pre-edit hook — 보호 경로 변경 시 명시적 확인
#
# Claude Code 공식 hook 입력: stdin JSON ({tool_name, tool_input.file_path, ...}).
# 차단은 exit 2 (sensors.mode=fail일 때만). 그 외엔 경고 후 exit 0.
set -uo pipefail   # set -e 제거 — grep returning 1 (no match) 등이 hook 본체를 silent abort하지 않도록

# Bootstrap guard — install 중간이거나 .ax/ 부분 정리 시 silent skip (UX 노이즈 방지)
[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

# stdin JSON 파싱 — Edit/Write/MultiEdit는 file_path, NotebookEdit는 notebook_path
INPUT="$(cat 2>/dev/null || true)"
TARGET_PATH=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
fi
TARGET_PATH="${TARGET_PATH:-${CLAUDE_EDIT_PATH:-${1:-}}}"
[ -z "$TARGET_PATH" ] && exit 0

# CLAUDE_PROJECT_DIR이 표준. 없으면 git/cwd로 fallback.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG="$PROJECT_ROOT/.ax/config.yml"

[ -f "$CONFIG" ] || exit 0

PROTECTED=$(awk '/^[[:space:]]*protected_paths:/,/^[^[:space:]]/' "$CONFIG" 2>/dev/null \
    | grep -E '^[[:space:]]+- ' \
    | sed -E 's/^[[:space:]]+-[[:space:]]+//; s/[[:space:]]*$//')

[ -z "$PROTECTED" ] && exit 0

TARGET_REL="${TARGET_PATH#$PROJECT_ROOT/}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"

for p in $PROTECTED; do
    if [[ "$TARGET_REL" == "$p" ]] || [[ "$TARGET_REL" == "$p"* ]]; then
        printf '\033[33m[goax hook]\033[0m 보호 경로 변경 시도: %s\n' "$TARGET_REL" >&2
        printf '이 변경이 의도적인지 사용자에게 확인 후 진행해.\n' >&2

        SENSOR_MODE="warning"
        if [ -f "$COMMON" ]; then
            # shellcheck source=../../scripts/bash/common.sh
            source "$COMMON"
            SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning)
        else
            SENSOR_MODE=$(grep -E '^[[:space:]]*mode:' "$CONFIG" | head -1 | awk '{print $2}' || echo warning)
        fi

        # mistake 자동 캡처는 폐기 — 사용자 명시 `mistake` skill 호출로만 기록.
        # 이 hook 은 차단/경고만 (mode=fail → deny / 그 외 → 경고).
        if [ "$SENSOR_MODE" = "fail" ]; then
            # Modern path: stdout JSON으로 permissionDecision="deny" + 이유를 surfacing.
            # Claude는 error가 아닌 정책적 거부로 인식 → reason을 사용자에게 깔끔히 전달.
            # jq 없는 환경(드뭄) fallback은 exit 2.
            if command -v jq >/dev/null 2>&1; then
                jq -nc --arg reason "보호 경로 변경 차단: $TARGET_REL (sensors.mode=fail). 의도적이라면 .ax/config.yml의 protected_paths 조정 또는 사용자 승인 후 재시도." \
                    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
                exit 0
            fi
            exit 2
        fi
        exit 0
    fi
done
exit 0
