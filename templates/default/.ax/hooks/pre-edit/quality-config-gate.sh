#!/usr/bin/env bash
# pre-edit hook — 품질 설정(lint·format·타입·커버리지·git 훅) 파일은 고치기 전에 이유부터 적게 해요
#
# 왜: 검사가 실패하면 코드 대신 규칙을 끄고 임계값을 낮추는 게 가장 싼 길이에요 (ECC config-protection).
# 대상: **이미 있는** 파일 — 기본값(is_default: 생태계 공통 이름 + `.husky/`) + sensors.quality_configs 글롭.
#   다른 설정이 섞인 파일(package.json · pyproject.toml · build.gradle)은 기본값이 아니에요 — 소음이 돼요.
# 동작: 세션에서 처음 고치는 파일이면 exit 2 로 "완화/강화 · 사용자 지시 원문" 을 요구하고, 같은 파일 재편집은 통과.
#   새 파일은 안 막아요. 3번째 뒤로는 한 줄. 세션 id 가 없으면 경고만.
# 모드: warning·fail 둘 다 막아요. 끄기: sensors.disabled_hooks 에 quality-config-gate. Bash 의 `sed -i` 는 안 걸려요.
set -uo pipefail

[ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
IFS="$(printf '\t')" read -r TOOL TARGET_PATH SID < <(printf '%s' "$INPUT" \
    | jq -r '[(.tool_name // ""), (.tool_input.file_path // ""), (.session_id // "")] | @tsv' 2>/dev/null) || true
case "$TOOL" in Edit|Write|MultiEdit) ;; *) exit 0 ;; esac
[ -n "$TARGET_PATH" ] || exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TARGET_ABS="$TARGET_PATH"
case "$TARGET_ABS" in /*) ;; *) TARGET_ABS="$PROJECT_ROOT/$TARGET_ABS" ;; esac
[ -f "$TARGET_ABS" ] || exit 0                      # 새 파일 — 만드는 건 막지 않아요

# 기본값 — 생태계 공통 품질 설정 파일 이름 (basename). 경로가 붙는 건 .husky/ 만.
is_default() {
    case "$1" in
        .editorconfig|.eslintrc|.eslintrc.*|eslint.config.*|.prettierrc|.prettierrc.*|prettier.config.*) return 0 ;;
        biome.json|biome.jsonc|.stylelintrc|.stylelintrc.*|stylelint.config.*|tsconfig.json|tsconfig.*.json) return 0 ;;
        .markdownlint*|.yamllint|.yamllint.*|.shellcheckrc|.hadolint.yaml|.sqlfluff) return 0 ;;
        detekt.yml|detekt.yaml|detekt-*.yml|.detekt.yml|checkstyle*.xml|pmd*.xml|spotbugs*.xml|.scalafmt.conf|.scalafix.conf) return 0 ;;
        .golangci.yml|.golangci.yaml|.golangci.toml|.golangci.json) return 0 ;;
        ruff.toml|.ruff.toml|mypy.ini|.mypy.ini|.flake8|.pylintrc|pylintrc|pyrightconfig.json|.coveragerc) return 0 ;;
        .rubocop.yml|.swiftlint.yml|clippy.toml|.clippy.toml|rustfmt.toml|.rustfmt.toml|.clang-format|.clang-tidy) return 0 ;;
        phpstan.neon|phpstan.neon.dist|psalm.xml|.php-cs-fixer.php|.php-cs-fixer.dist.php) return 0 ;;
        codecov.yml|.codecov.yml|.nycrc|.nycrc.*|.c8rc|.c8rc.*) return 0 ;;
        .pre-commit-config.yaml|lefthook.yml|.lefthook.yml|commitlint.config.*|.commitlintrc|.commitlintrc.*) return 0 ;;
    esac
    return 1
}

COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"
[ -f "$COMMON" ] || exit 0
# shellcheck source=../../scripts/bash/common.sh
source "$COMMON"

goax_hook_enabled quality-config-gate standard || exit 0
[ "$(goax_mode)" = "off" ] && exit 0

ROOT_ABS=$( (CDPATH="" cd -P "$PROJECT_ROOT" 2>/dev/null && pwd -P) || printf '%s' "$PROJECT_ROOT")
TD=$( (CDPATH="" cd -P "$(dirname "$TARGET_ABS")" 2>/dev/null && pwd -P) || dirname "$TARGET_ABS")
TARGET_REL="${TD%/}/$(basename "$TARGET_ABS")"
TARGET_REL="${TARGET_REL#"$ROOT_ABS"/}"
case "$TARGET_REL" in /*) exit 0 ;; .ax/*) exit 0 ;; esac   # 프로젝트 밖 · goax 자체 설정은 대상 아님

HIT=false
if is_default "$(basename "$TARGET_REL")"; then HIT=true
else
    case "$TARGET_REL" in .husky/*) HIT=true ;; esac
fi
if [ "$HIT" != true ]; then
    EXTRA=$(goax_yaml_list "$PROJECT_ROOT/.ax/config.yml" quality_configs 2>/dev/null || true)
    if [ -n "$EXTRA" ]; then
        while IFS= read -r g; do
            [ -n "$g" ] || continue
            goax_glob_match "$g" "$TARGET_REL" && { HIT=true; break; }
        done <<< "$EXTRA"
    fi
fi
[ "$HIT" = true ] || exit 0

if [ -z "$SID" ]; then
    printf '\033[33m[goax hook]\033[0m ❗ 품질 설정 파일 편집 (세션 추적 불가 — 경고만): %s\n' "$TARGET_REL" >&2
    exit 0
fi

KEY=$(printf '%s' "$TARGET_REL" | cksum | awk '{print $1 "-" $2}')
goax_session_marked "$SID" quality "$KEY" && exit 0
goax_session_mark "$SID" quality "$KEY"
N=$(goax_session_count "$SID" quality-denials)

if [ "$N" -gt 3 ]; then
    printf '\033[33m[goax hook]\033[0m ✋ (#%s) 품질 설정 %s — 무엇을 왜 바꾸는지(완화/강화) · 사용자 지시 원문을 적고 같은 편집을 다시 하세요.\n' \
        "$N" "$TARGET_REL" >&2
    exit 2
fi

{
    printf '\033[33m[goax hook]\033[0m ✋ 품질 설정 파일이에요 — 고치기 전에 이유를 먼저 적어 주세요 (이번 세션 %s번째).\n' "$N"
    printf '  파일: %s\n' "$TARGET_REL"
    printf '  검사가 실패해서 규칙을 끄거나 임계값을 낮추거나 제외 목록에 넣는 건 해결이 아니에요 — 코드를 고쳐요.\n'
    printf '  1. 무엇을 왜 바꾸는지 — 완화(규칙 끄기·임계값 낮추기·제외 추가)인지 강화인지\n'
    printf '  2. 이 변경을 지시한 사용자 메시지 원문 — 없으면 고치지 말고 사용자에게 물어보세요\n'
    printf '  적은 뒤 같은 편집을 다시 하면 통과해요 (이 파일은 이번 세션 동안 다시 묻지 않아요).\n'
    printf '  (끄기: .ax/config.yml sensors.disabled_hooks 에 quality-config-gate · 대상 추가: sensors.quality_configs)\n'
} >&2
exit 2
