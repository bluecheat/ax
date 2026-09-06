#!/usr/bin/env bash
# pre-edit hook — 보호 경로 변경 시 명시적 확인
#
# ⚠️ 성격: 사고 방지용 안전망이지 보안 경계가 아니에요. 에이전트가 다른 도구
#    (Bash 의 `sed -i`, `tee` 등) 로 같은 파일을 고치면 이 훅은 발화하지 않아요.
#    → .ax/docs/reference/rule-enforcement.md "집행 강도" 참고.
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
if [ -z "$TARGET_PATH" ]; then
    # stdin 은 왔는데 경로를 못 뽑았으면 jq 가 없는 거예요. fail-open 은 유지하되 침묵하진 않아요 —
    # 조용히 통과하면 보호 경로 deny 가 아무 출력 없이 꺼진 상태가 돼요.
    if [ -n "$INPUT" ] && ! command -v jq >/dev/null 2>&1; then
        printf '[goax] jq 없음 — 이 안전망이 비활성 상태예요 (보호 경로 검사)\n' >&2
    fi
    exit 0
fi

# CLAUDE_PROJECT_DIR이 표준. 없으면 git/cwd로 fallback.
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG="$PROJECT_ROOT/.ax/config.yml"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"

[ -f "$CONFIG" ] || exit 0

# common.sh 를 먼저 로드 — 경로 정규화·경계 매칭·YAML 파싱 헬퍼가 여기 있어요.
# 부분 설치 등으로 없으면 degrade (정규화 없이 원래 문자열 비교) 하되 죽지 않아요.
if [ -f "$COMMON" ]; then
    # shellcheck source=../../scripts/bash/common.sh
    source "$COMMON"
fi
type goax_normalize_path >/dev/null 2>&1 || goax_normalize_path() { printf '%s' "${1:-}"; }
type goax_path_under     >/dev/null 2>&1 || goax_path_under() { case "${1:-}" in "${2:-}"|"${2:-}"/*) return 0 ;; esac; return 1; }
type goax_yaml_list      >/dev/null 2>&1 || goax_yaml_list() {
    awk '/^[[:space:]]*protected_paths:/{f=1;next} f&&/^[[:space:]]+-[[:space:]]+/{sub(/^[[:space:]]*-[[:space:]]+/,"");print;next} f{exit}' "${1:-}"
}

PROTECTED=$(goax_yaml_list "$CONFIG" protected_paths)

# 목록이 비었는데 키는 존재 → 파싱 실패 가능성. 조용히 넘어가면 보안 컨트롤이
# 소리 없이 꺼진 상태가 되므로 반드시 알려요 (silent failure 방지).
if [ -z "$PROTECTED" ]; then
    if grep -qE '^[[:space:]]*protected_paths:' "$CONFIG" 2>/dev/null; then
        printf '\033[33m[goax hook]\033[0m ⚠ .ax/config.yml 에 protected_paths 키는 있는데 항목을 읽지 못했어요.\n' >&2
        printf '             보호 경로 검사가 비활성 상태예요 — YAML 형식을 확인해 주세요.\n' >&2
    fi
    exit 0
fi

# 경로 정규화 — `./x`, `a/../x`, 중복 슬래시 같은 표기 변형을 흡수해야
# 표기만 바꿔서 보호를 우회하는 걸 막아요.
TARGET_ABS=$(goax_normalize_path "$TARGET_PATH" "$PROJECT_ROOT")
ROOT_ABS=$(goax_normalize_path "$PROJECT_ROOT" "$PROJECT_ROOT")
TARGET_REL="${TARGET_ABS#$ROOT_ABS/}"
[ "$TARGET_REL" = "$TARGET_ABS" ] && TARGET_REL="${TARGET_ABS#/}"   # 프로젝트 밖 경로

# while-read 로 순회 — `for p in $PROTECTED` 는 워드 스플리팅 + glob 확장이 일어나서
# 항목에 `*` 나 공백이 있으면 cwd 파일명으로 확장돼 매칭이 깨져요.
while IFS= read -r p; do
    [ -z "$p" ] && continue
    if goax_path_under "$TARGET_REL" "$p"; then
        printf '\033[33m[goax hook]\033[0m 보호 경로 변경 시도: %s\n' "$TARGET_REL" >&2
        printf '이 변경이 의도적인지 사용자에게 확인 후 진행해.\n' >&2

        SENSOR_MODE="warning"
        if type goax_mode >/dev/null 2>&1; then
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
done <<EOF
$PROTECTED
EOF

exit 0
