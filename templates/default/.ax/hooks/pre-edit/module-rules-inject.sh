#!/usr/bin/env bash
# pre-edit hook — Layer 2(module rules) + Layer 3(활성 spec/ADR) 자동 주입
#
# 왜 필요한가: 하네스의 4계층 중 Layer 0(triage-nudge)·Layer 1(CLAUDE.md import)·
# Spirit(spirit-rules-inject) 는 자동으로 컨텍스트에 들어가는데, Layer 2 와 3 은
# **모델이 읽기로 선택해야만** 들어왔어요. "환경으로 통제한다" 는 테제의 절반이
# 비어 있던 셈이에요. 이 훅이 그 자리를 메꿔요.
#
# 입력: stdin JSON {tool_input.file_path|tool_input.notebook_path}
# 출력: stdout JSON {hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"..."}}
#
# 본문이 아니라 **경로만** 주입해요 (B-pointer, lazy Read).
# 룰 전문을 밀어 넣으면 편집 한 번에 수천 토큰이 들어가고 필요 없는 것까지 따라와요.
# 매칭 없으면 silent exit 0. 차단하지 않아요 — 정보 주입 전용.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
TARGET_PATH=""; SID=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
    TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
    SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
fi
TARGET_PATH="${TARGET_PATH:-${CLAUDE_EDIT_PATH:-${1:-}}}"
[ -z "$TARGET_PATH" ] && exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
[ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

TARGET_ABS=$(goax_normalize_path "$TARGET_PATH" "$PROJECT_ROOT")
ROOT_ABS=$(goax_normalize_path "$PROJECT_ROOT" "$PROJECT_ROOT")
TARGET_REL="${TARGET_ABS#$ROOT_ABS/}"
[ "$TARGET_REL" = "$TARGET_ABS" ] && TARGET_REL="${TARGET_ABS#/}"

# .ax/ 자체를 편집할 땐 주입 안 해요 (하네스가 자기 자신을 물지 않도록)
case "$TARGET_REL" in .ax/*) exit 0 ;; esac

LINES=""

# ── Layer 2 — module rules (path-scoped) ─────────────────────────
# 모듈 룰은 `.ax/modules/<name>/rules.md` 로 중첩돼 있어 flat glob 이 안 통해요.
MOD_DIR="$PROJECT_ROOT/.ax/modules"
if [ -d "$MOD_DIR" ]; then
    for rules in "$MOD_DIR"/*/rules.md; do
        [ -f "$rules" ] || continue
        mod=$(basename "$(dirname "$rules")")

        # applies_to 에 `code` 가 없으면 편집 시점 주입 대상이 아니에요.
        # (pr/commit/review 전용 룰은 편집 중에 나오면 노이즈)
        # 필드가 아예 없으면 하위호환으로 주입 — 기존 프로젝트를 깨지 않으려고요.
        APPLIES=$(goax_yaml_list "$rules" applies_to)
        if [ -n "$APPLIES" ] && ! printf '%s\n' "$APPLIES" | grep -qx 'code'; then
            continue
        fi

        matched=false
        while IFS= read -r glob; do
            [ -z "$glob" ] && continue
            if goax_glob_match "$glob" "$TARGET_REL"; then
                matched=true
                break
            fi
        done < <(goax_yaml_list "$rules" paths)
        [ "$matched" = true ] || continue
        # 같은 세션에서 이미 준 모듈 포인터는 다시 안 줘요 (서브에이전트 하나가 168회 받은 실측)
        goax_inject_fresh "$SID" "module:$mod" || continue

        LINES="${LINES}  Layer 2 · ${mod}  →  .ax/modules/${mod}/rules.md"$'\n'

        # 모듈이 자기 결정 근거 ADR 을 선언했으면 같이 가리켜요.
        # 룰만 보면 "왜 이런 룰인지" 를 몰라서 다시 제안하는 일이 생겨요 (컨텍스트 drift).
        while IFS= read -r adrp; do
            [ -z "$adrp" ] && continue
            case "$adrp" in *"<slug>"*|*NNNN*) continue ;; esac   # 템플릿 placeholder 무시
            [ -f "$PROJECT_ROOT/$adrp" ] && LINES="${LINES}  Layer 2 · ${mod} ADR  →  ${adrp}"$'\n'
        done < <(goax_yaml_list "$rules" adr)
    done
fi

# ── Layer 3 — 진행 중인 spec / 관련 ADR ──────────────────────────
# 파일 경로가 아니라 *작업* 에 걸린 컨텍스트라 current-task.json 을 봐요.
TASK_FILE="$PROJECT_ROOT/.ax/current-task.json"
if [ -f "$TASK_FILE" ] && command -v jq >/dev/null 2>&1; then
    PHASE=$(jq -r '.phase // "idle"' "$TASK_FILE" 2>/dev/null || echo idle)
    SPEC_DIR=$(jq -r '.spec_dir // empty' "$TASK_FILE" 2>/dev/null || true)
    if [ "$PHASE" != "idle" ] && [ -n "$SPEC_DIR" ] && [ -d "$PROJECT_ROOT/$SPEC_DIR" ] \
       && goax_inject_fresh "$SID" "spec:$(basename "$SPEC_DIR")"; then
        [ -f "$PROJECT_ROOT/$SPEC_DIR/spec.md" ]  && LINES="${LINES}  Layer 3 · spec   →  ${SPEC_DIR}/spec.md"$'\n'
        [ -f "$PROJECT_ROOT/$SPEC_DIR/tasks.md" ] && LINES="${LINES}  Layer 3 · tasks  →  ${SPEC_DIR}/tasks.md"$'\n'
        # spec.md 가 인용한 ADR 만 (전체 ADR 을 흘리면 노이즈)
        if [ -f "$PROJECT_ROOT/$SPEC_DIR/spec.md" ]; then
            while IFS= read -r adr; do
                [ -z "$adr" ] && continue
                [ -f "$PROJECT_ROOT/$adr" ] && LINES="${LINES}  Layer 3 · ADR    →  ${adr}"$'\n'
            done < <(grep -ohE '\.ax/docs/adr/[0-9]+-[A-Za-z0-9._-]+\.md' \
                        "$PROJECT_ROOT/$SPEC_DIR/spec.md" 2>/dev/null | sort -u | head -5)
        fi
    fi
fi

[ -z "$LINES" ] && exit 0

CTX="[goax] 이 파일에 걸린 상위 계층이에요. 편집 전에 해당 파일을 Read 하세요.
${LINES}"

if command -v jq >/dev/null 2>&1; then
    jq -nc --arg c "$CTX" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
else
    printf '%s\n' "$CTX" >&2
fi
exit 0
