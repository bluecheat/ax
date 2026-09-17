#!/usr/bin/env bash
# pre-commit hook — CRITICAL 룰 패턴을 staged 파일에서 검출
#
# 세 가지를 봐요:
#   ① 룰 패턴 — spirit/rules·modules/*/rules.md 의 `<!-- 검출 패턴: <ERE> -->` (룰 단위).
#      파일 frontmatter 의 `paths:` 글롭에 맞는 staged 파일만, `severity: critical` 만 차단.
#      마커 문법·차단 표: .ax/docs/reference/rule-enforcement.md
#   ② secrets — common.sh 의 goax_secret_rules 표
#   ③ 프로젝트 전용 스캐폴드 — 패턴 한 줄로 못 쓰는 검사(제외 경로·다중 파일 조건)만
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

# core.quotePath=false — 기본값이면 한글 등 비ASCII 파일명이 "\355\225\234…" 로 인용돼 `-f` 검사에서 빠져요
STAGED=$(git -c core.quotePath=false diff --cached --name-only 2>/dev/null || true)
[ -z "$STAGED" ] && { echo "[goax] staged 파일 없음" >&2; exit 0; }

echo "[goax] CRITICAL 룰 검사 (mode=$SENSOR_MODE) — 대상 $(echo "$STAGED" | wc -l | tr -d ' ')개 파일"

# ─── 프로젝트 전용 스캐폴드 — 패턴 마커로 못 쓰는 검사만 ──────────────────
#goax-grep-scaffold — 이 마커는 "프로젝트 패턴 미작성" 신호예요. 그런데 **대부분의 grep 류 룰은
# 여기가 아니라 룰 파일 안의 `<!-- 검출 패턴: <ERE> -->` 한 줄로 끝나요** (아래 ① 섹션이 읽어요).
# 여기 case 문은 제외 경로·여러 파일에 걸친 조건처럼 패턴 한 줄로 표현이 안 될 때만 채우고,
# 채웠으면 이 마커 라인을 지우세요 (doctor C1 은 "마커 잔존 + 패턴 룰 0건" 일 때만 finding 이에요).
#
# 작성 예시 (실룰이 아니라 형식 참고용 — 그대로 켜지 않아요):
#   while IFS= read -r f; do
#       [ -z "$f" ] || [ ! -f "$f" ] && continue
#       case "$f" in
#           *test/context/*) continue ;;                      # 제외 경로 — 패턴 마커로는 못 해요
#           *.kt)
#               if grep -qE '^import[[:space:]]+org\.junit\.jupiter\.' "$f" 2>/dev/null; then
#                   report "testing" "$f: JUnit5 import 금지 — SP-TEST-001"
#               fi
#               ;;
#       esac
#   done <<< "$STAGED"
#
# 본 집행(테스트·린트)이 있는 룰은 그쪽을 pre-commit/CI 에서 직접 실행하는 별도 훅 파일로 두세요 —
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

# ─── ① 룰 패턴 — `<!-- 검출 패턴: -->` 를 실제로 돌려요 ─────────────────────
# 룰 파일마다: severity(파일) · paths(파일) · 패턴(룰 단위, goax_rule_patterns) 을 읽고,
# staged 중 paths 에 맞는 파일만 grep 해요. `.ax/**` 는 항상 빼요 — 룰 파일 자신의 ❌ 예시와
# mistakes 파일이 자기 패턴에 걸려요. 매칭 **줄 내용은 안 찍어요** (secrets 와 같은 이유) —
# `file:line — 토큰` 만.
#
# 차단은 severity: critical 만 (mode=fail 일 때 exit 2). mandatory/convention 은 경고만 —
# 🔴 만 자동 차단이라는 라벨 의미 그대로예요. paths 가 비면 그 파일의 패턴은 안 돌아요
# (주입 훅과 같은 규칙 — "비우면 자동 X"). 이런 상태는 doctor I7 이 finding 으로 보고해요.
WARNINGS=0
STAGED_SRC=""
while IFS= read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    case "$f" in .ax/*|*/.ax/*) continue ;; esac
    STAGED_SRC="${STAGED_SRC}${f}"$'\n'
done <<< "$STAGED"

if [ -n "$STAGED_SRC" ] && type goax_rule_patterns >/dev/null 2>&1; then
    RULE_FILES=""
    for rf in "$PROJECT_ROOT"/.ax/spirit/rules/*.md "$PROJECT_ROOT"/.ax/modules/*/rules.md; do
        [ -f "$rf" ] || continue
        case "$(basename "$rf")" in README.md) continue ;; esac
        RULE_FILES="${RULE_FILES}${rf}"$'\n'
    done

    while IFS= read -r rf; do
        [ -z "$rf" ] && continue
        PATS=$(goax_rule_patterns "$rf")
        [ -z "$PATS" ] && continue
        SEV=$(goax_frontmatter_scalar "$rf" severity); SEV=$(printf '%s' "$SEV" | tr '[:upper:]' '[:lower:]')
        [ -z "$SEV" ] && SEV="convention"
        TARGETS=""
        while IFS= read -r glob; do
            [ -z "$glob" ] && continue
            TARGETS="${TARGETS}$(printf '%s' "$STAGED_SRC" | goax_glob_filter "$glob")"$'\n'
        done < <(goax_yaml_list "$rf" paths)
        TARGETS=$(printf '%s' "$TARGETS" | grep -v '^$' | sort -u || true)
        [ -z "$TARGETS" ] && continue
        RF_REL="${rf#$PROJECT_ROOT/}"

        while IFS=$'\t' read -r token pat; do
            [ -z "$token" ] || [ -z "$pat" ] && continue
            # 패턴 문법 검증 — 깨진 ERE 는 grep 이 rc=2 로 조용히 죽어요. 무음으로 넘기면
            # "검사됨" 으로 보이니 경고를 남기고 이 패턴만 건너뛰어요.
            grep -qE -e "$pat" /dev/null 2>/dev/null; prc=$?
            if [ "$prc" -eq 2 ]; then
                printf '  ⚠ %s — 검출 패턴 문법 오류 (%s) — 이 패턴은 검사 생략\n' "$token" "$RF_REL" >&2
                WARNINGS=$((WARNINGS + 1)); continue
            fi
            while IFS= read -r tf; do
                [ -z "$tf" ] && continue
                # -n 줄번호 · -I 바이너리 제외. 줄번호만 남기고 내용은 버려요 — 파일명은 이미 아니까
                # `file:line` 은 직접 조합해요 (파일명에 `:` 가 있어도 안 깨져요).
                HITS=$(grep -nIE -e "$pat" -- "$tf" 2>/dev/null | cut -d: -f1 || true)
                [ -z "$HITS" ] && continue
                while IFS= read -r ln; do
                    [ -z "$ln" ] && continue
                    hit="$tf:$ln"
                    if [ "$SEV" = "critical" ]; then
                        report "rule-pattern" "$hit — $token (critical · $RF_REL)"
                    else
                        printf '  · %s — %s (%s · %s — 차단 안 함)\n' "$hit" "$token" "$SEV" "$RF_REL" >&2
                        WARNINGS=$((WARNINGS + 1))
                    fi
                done <<< "$HITS"
            done <<< "$TARGETS"
        done <<< "$PATS"
    done <<< "$RULE_FILES"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
    if [ "$SENSOR_MODE" = "fail" ]; then
        echo "[goax] ✗ CRITICAL 위반 ${VIOLATIONS}건 — 차단 (mode=fail)" >&2
        exit 2
    fi
    echo "[goax] ⚠ CRITICAL 위반 ${VIOLATIONS}건 — 경고만 (mode=$SENSOR_MODE). 기록 원하면 mistake skill 호출" >&2
    exit 0
fi

if [ "${WARNINGS:-0}" -gt 0 ]; then
    echo "[goax] ✓ CRITICAL 검사 통과 (mode=$SENSOR_MODE) — 룰 패턴 경고 ${WARNINGS}건 (mandatory/convention · 차단 안 함)"
    exit 0
fi
echo "[goax] ✓ CRITICAL 검사 통과 (mode=$SENSOR_MODE)"
exit 0
