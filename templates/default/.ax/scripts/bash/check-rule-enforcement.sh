#!/usr/bin/env bash
# .ax/scripts/bash/check-rule-enforcement.sh — 룰의 enforced_by/enforced_kind invariant 검증
#
# Usage:
#   bash check-rule-enforcement.sh [--json] [--strict] [--help]
#
# Sources (read-only):
#   - $ROOT/AGENTS.md (또는 CLAUDE.md)  (inline 룰: 🔴/🟡/🔵 + 다음 라인 - enforced_by:)
#   - $ROOT/.ax/spirit/rules/*.md   (frontmatter severity/enforced_by/enforced_kind)
#   - $ROOT/.ax/modules/*/rules.md  (frontmatter)
#   - $ROOT/.ax/docs/adr/*.md       (deadline checklist: - [ ] YYYY-MM-DD ...)
#
# Invariants (docs/reference/rule-enforcement.md):
#   I1. 🔴 CRITICAL 의 enforced_by 는 hook:* 또는 external:* 만 (TODO/human/script 금지)
#   I2. TODO:* 는 deadline 필수 (YYYY-MM-DD)
#   I3. deadline 임박(≤7일) 또는 초과 보고
#   I5. enforced_by: hook:<path> 면 (a) 파일 존재 (b) 배선됨
#       — 배선 = settings.json 에 등록. 단 .ax/hooks/pre-commit/*.sh 는 디렉토리째
#         glob 되므로 디스패처 존재로 판정해요: settings.json 의 grep-on-commit.sh
#         (에이전트 커밋) 또는 .git/hooks/pre-commit 의 goax chain wrapper (사람 커밋)
#   I6. enforced_by: external:* 면 그걸 자동 실행하는 트리거가 리포에 실재해야 함
#       (CI workflow[GitHub/GitLab/Circle/Jenkins/Azure/Buildkite] / git pre-commit /
#        husky / pre-commit-framework / lefthook 중 1+)
#       — goax wrapper 만 있는 pre-commit 은 트리거로 안 쳐요 (up 이 기본 설치하므로
#         자기 무력화). 프로젝트 전용 chain 훅이 있을 때만 git:pre-commit-chain 인정.
#       external 라벨만 있고 트리거가 없으면 "누군가 손으로 돌릴 때만" 도는 거짓 약속
#
# 미작성 예시(placeholder) 제외:
#   enforced_by 가 아직 `<...>` 나 `YYYY-MM-DD`/`NNNN` 자리표시자면 위반이 아니라
#   "안 채운 자리" 예요. 출고 AGENTS.md 의 예시 룰이 여기 걸려서, 위반으로 세면
#   갓 설치한 프로젝트가 첫날부터 --strict 로 빨개져요. warnings 로 빼고
#   result.placeholder_rules 에 담아요 — 값을 채우면 그때부터 검사 대상이에요.
#
# JSON output schema (--json):
#   { status: ok|warning|error,
#     result: {
#       i1_violations: [...], i2_violations: [...],
#       i3_imminent: [...], i3_overdue: [...],
#       i5_file_missing: [...], i5_not_registered: [...],
#       i6_no_trigger: [...], placeholder_rules: [...],
#       trigger_surfaces: [...],
#       rule_count: N, source_files: [...]
#     },
#     next_step, warnings, errors }
#
# Exit codes:
#   0 = ok (위반 0)
#   1 = error (jq 미설치 등)
#   2 = skipped (CLAUDE.md 부재)
#
# 단, --strict 미설정 시 violations > 0 도 exit 0 (보고만). doctor 호출 시 exit code 보다는
# JSON 의 i*_violations 배열을 파싱해서 사용자 보고에 포함.

set -uo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false
STRICT=false
SHOW_HELP=false
while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --strict)  STRICT=true ;;
        --help|-h) SHOW_HELP=true ;;
        *) goax_error "unknown option: $1"; exit "$EXIT_ERROR" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,49p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#//'
    exit "$EXIT_OK"
fi

if ! command -v jq >/dev/null 2>&1; then
    if [ "$JSON_MODE" = true ]; then json_error "jq 미설치"
    else goax_error "jq 미설치 — invariant 검증 불가"; exit "$EXIT_ERROR"; fi
fi

ROOT=$(find_project_root) || exit "$EXIT_ERROR"

# Constitution 파일 — 0.2.0 부터 AGENTS.md 가 SSOT 본문이고 CLAUDE.md 는 `@AGENTS.md`
# alias(룰 시그널 라인 없음). "먼저 존재하는 파일" 이 아니라 "실제 룰 시그널(🔴/🟡/🔵 **`)
# 을 가진 파일" 을 골라요 — alias 를 잘못 집어 rule_count=0 으로 보이던 버그 방지.
# (build-memory.sh 의 RULES_FILE 해석 체인과 동일 — SSOT 일치)
RULES_FILE=""
for _cand in AGENTS.md CLAUDE.md; do
    if [ -f "$ROOT/$_cand" ] && grep -qE '^(🔴|🟡) \*\*`' "$ROOT/$_cand" 2>/dev/null; then
        RULES_FILE="$ROOT/$_cand"; break
    fi
done
[ -z "$RULES_FILE" ] && [ -f "$ROOT/AGENTS.md" ] && RULES_FILE="$ROOT/AGENTS.md"
[ -z "$RULES_FILE" ] && [ -f "$ROOT/CLAUDE.md" ] && RULES_FILE="$ROOT/CLAUDE.md"

SETTINGS="$ROOT/.claude/settings.json"
# install-git-hooks.sh 가 wrapper 안에 심는 마커. I6 트리거 판정과 I5 배선 판정이
# 같은 것을 봐야 해서 한 곳에 뒀어요 (두 리터럴이 갈라지면 한쪽만 조용히 틀어져요).
GOAX_CHAIN_MARKER="#goax-pre-commit-chain"
TODAY=$(date -u +%Y-%m-%d)

if [ -z "$RULES_FILE" ]; then
    if [ "$JSON_MODE" = true ]; then json_skip "AGENTS.md/CLAUDE.md 부재 — 검증 skip"
    else goax_warn "AGENTS.md/CLAUDE.md 부재 — 검증 skip"; fi
    exit "$EXIT_SKIPPED"
fi

# ─── (1) inline 룰 추출 — AGENTS.md/CLAUDE.md ───────────────────────
# 라벨 시그널 + 다음 라인들의 - enforced_by:/- enforced_kind: 페어링
# 출력: TSV "rule_id\tlabel\tenforced_by\tenforced_kind\tsource_file"
extract_inline() {
    local file="$1"
    awk -v file="$file" '
        function flush() {
            if (current_id != "" && current_label != "") {
                printf "%s\t%s\t%s\t%s\t%s\n",
                    current_id, current_label, current_eb, current_ek, file
            }
            current_id=""; current_label=""; current_eb=""; current_ek=""
        }
        # 라벨 라인: 🔴/🟡/🔵 + ID
        /^(🔴|🟡|🔵)/ {
            flush()
            if (/🔴/) current_label="critical"
            else if (/🟡/) current_label="mandatory"
            else if (/🔵/) current_label="convention"
            # ID 추출: `XX:YY:ZZZ` 또는 `XX:YY:ZZZ` 형식
            if (match($0, /`[A-Z][A-Z0-9_-]*:[A-Z]+:[0-9]+`/)) {
                current_id = substr($0, RSTART+1, RLENGTH-2)
            }
            next
        }
        # enforced_by 라인 (라벨 다음 - 리스트 안)
        current_label != "" && /^[[:space:]]*-[[:space:]]+enforced_by:/ {
            sub(/^[[:space:]]*-[[:space:]]+enforced_by:[[:space:]]*/, "")
            current_eb = $0
            next
        }
        current_label != "" && /^[[:space:]]*-[[:space:]]+enforced_kind:/ {
            sub(/^[[:space:]]*-[[:space:]]+enforced_kind:[[:space:]]*/, "")
            current_ek = $0
            next
        }
        # 새 ## 섹션 또는 빈 라인 2개 = 룰 끝
        /^## / { flush() }
        END { flush() }
    ' "$file"
}

# ─── (2) frontmatter 추출 — spirit/rules + modules/*/rules.md ─────
# 출력 동일 TSV. label 은 frontmatter `severity:` 에서 읽어요 (critical/mandatory,
# 그 외·부재는 "convention"). 이걸 안 읽으면 frontmatter 룰 전면이 I1 사각지대가 돼요.
extract_frontmatter() {
    local file="$1"
    awk -v file="$file" '
        BEGIN { c=0; in_fm=0; eb=""; ek=""; cat=""; sev="" }
        /^---$/ { c++; if (c==2) { print_record(); exit } next }
        c==1 {
            # YAML 인라인 주석 제거 — 안 걷어내면 주석이 값으로 들어와요
            # (출고 _templates/spirit/*.md 가 필드마다 설명 주석을 답니다).
            # `#` 앞에 공백을 요구해서 값 안의 `#` (글롭 앵커 등) 은 안 건드려요.
            ln=$0; sub(/(^|[[:space:]])#.*$/, "", ln)
            sub(/[[:space:]]+$/, "", ln); $0=ln

            # 새 키가 시작되면 배열 수집을 닫아요. **이 검사가 opener 보다 뒤에 있으면
            # `enforced_by:` 자기 자신이 새 키로 읽혀 같은 줄에서 in_fm 이 꺼져요** —
            # 배열 형식(`enforced_by:` + `- item`)이 통째로 안 읽히던 원인이에요.
            if (in_fm && /^[a-zA-Z]/) in_fm=0

            if (/^category:/) { cat=$0; sub(/^category:[[:space:]]*/, "", cat) }
            if (/^severity:/) {
                sev=$0; sub(/^severity:[[:space:]]*/, "", sev)
                gsub(/["'"'"']/, "", sev); gsub(/[[:space:]]/, "", sev)
                sev=tolower(sev)
            }
            if (/^enforced_by:[[:space:]]*[^[:space:]]/) {
                # scalar 형식: enforced_by: hook:...
                eb=$0; sub(/^enforced_by:[[:space:]]*/, "", eb)
            }
            if (/^enforced_by:[[:space:]]*$/) {
                # array 형식 — 다음 - 라인부터 수집
                in_fm=1; eb=""
            }
            if (in_fm && /^[[:space:]]+-[[:space:]]+/) {
                v=$0; sub(/^[[:space:]]+-[[:space:]]+/, "", v)
                if (eb=="") eb=v; else eb=eb "+" v
            }
            if (/^enforced_kind:/) {
                ek=$0; sub(/^enforced_kind:[[:space:]]*/, "", ek)
            }
        }
        function print_record(   lab) {
            if (eb != "" || ek != "") {
                # rule_id 는 파일 basename 기반 — frontmatter 룰은 파일 = 카테고리
                file_id=file; sub(/.*\//, "", file_id); sub(/\.md$/, "", file_id)
                rid="SPIRIT:" toupper(file_id)
                lab = "convention"
                if (sev == "critical") lab = "critical"
                else if (sev == "mandatory") lab = "mandatory"
                printf "%s\t%s\t%s\t%s\t%s\n", rid, lab, eb, ek, file
            }
        }
    ' "$file"
}

# ─── (3) 룰 전체 수집 ────────────────────────────────────────────
ALL_RULES=$(mktemp)
trap 'rm -f "$ALL_RULES"' EXIT

extract_inline "$RULES_FILE" >> "$ALL_RULES"
for f in "$ROOT/.ax/spirit/rules/"*.md; do
    [ -f "$f" ] || continue
    extract_frontmatter "$f" >> "$ALL_RULES"
done
for f in "$ROOT/.ax/modules/"*/rules.md; do
    [ -f "$f" ] || continue
    extract_frontmatter "$f" >> "$ALL_RULES"
done

RULE_COUNT=$(wc -l < "$ALL_RULES" | tr -d ' ')

# ─── (4) invariant 검증 ─────────────────────────────────────────
I1=()  # CRITICAL + enforced_by ∉ {hook:*, external:*}
I2=()  # TODO 인데 deadline 없음
I3_IMMINENT=()
I3_OVERDUE=()
I5_FILE=()  # hook:<path> 파일 부재
I5_REG=()   # hook:<path> 파일 OK 인데 settings.json 미등록
I6=()       # external:* 인데 자동 실행 트리거(CI/git hook) 부재
PLACEHOLDERS=()  # enforced_by 가 아직 자리표시자 — 위반이 아니라 미작성

# enforced_by 가 `<...>` / YYYY-MM-DD / NNNN 이면 아직 안 채운 예시예요.
# 출고 AGENTS.md 의 예시 룰이 여기 해당 — 위반으로 세면 --strict 가 첫날부터
# 빨개져서 아무도 안 켜요. 값을 채우는 순간 자동으로 검사 대상이 돼요.
is_placeholder_eb() {
    case "$1" in
        *"<"*">"*)           return 0 ;;
        *YYYY-MM-DD*|*NNNN*) return 0 ;;
    esac
    return 1
}

# I6 준비 — 리포에 존재하는 자동 트리거 표면을 한 번만 수집.
# external:<tool> 의 내용까지는 도구별이라 검증 못 하지만, "무엇이 그걸 자동으로
# 돌리는가" 는 도구 무관하게 검사 가능. 하나도 없으면 external 룰 전부가 수동 집행.
TRIGGER_SURFACES=()
# CI — GitHub Actions 외 주요 CI 도 표면으로 인정 (도구 무관 검사라는 원칙 유지)
if ls "$ROOT/.github/workflows/"*.yml >/dev/null 2>&1 \
    || ls "$ROOT/.github/workflows/"*.yaml >/dev/null 2>&1; then
    TRIGGER_SURFACES+=("ci:github-actions")
fi
for _ci in .gitlab-ci.yml .circleci/config.yml Jenkinsfile azure-pipelines.yml; do
    [ -f "$ROOT/$_ci" ] && { TRIGGER_SURFACES+=("ci:$_ci"); break; }
done
[ -d "$ROOT/.buildkite" ] && TRIGGER_SURFACES+=("ci:buildkite")

# git pre-commit — core.hooksPath 설정(husky v9 등)까지 반영해 실제 경로로 확인.
# 실행권한 없는 훅은 git 이 무시하므로 -x 까지 요구.
GIT_PC=$(git -C "$ROOT" rev-parse --git-path hooks/pre-commit 2>/dev/null || echo "")
if [ -n "$GIT_PC" ]; then
    case "$GIT_PC" in /*) ;; *) GIT_PC="$ROOT/$GIT_PC" ;; esac
    if [ -f "$GIT_PC" ] && [ -x "$GIT_PC" ]; then
        if grep -q "$GOAX_CHAIN_MARKER" "$GIT_PC" 2>/dev/null; then
            # goax wrapper 는 .ax/hooks/pre-commit/*.sh 만 chain 해요 — up 이 전 환경
            # 기본으로 설치하므로 wrapper 존재 자체는 external 실행의 근거가 못 돼요
            # (그걸 근거로 치면 I6 가 항상 통과하는 자기 무력화). 출고 훅 이외의
            # 프로젝트 전용 훅이 1개 이상 있을 때만 트리거로 인정해요.
            for _h in "$ROOT/.ax/hooks/pre-commit/"*.sh; do
                [ -f "$_h" ] || continue
                case "$(basename "$_h")" in
                    critical-rule-grep.sh|check-mistake-secrets.sh) ;;
                    *) TRIGGER_SURFACES+=("git:pre-commit-chain"); break ;;
                esac
            done
        else
            TRIGGER_SURFACES+=("git:pre-commit")
        fi
    fi
fi
[ -f "$ROOT/.pre-commit-config.yaml" ] && TRIGGER_SURFACES+=("framework:pre-commit")
[ -f "$ROOT/.husky/pre-commit" ] && TRIGGER_SURFACES+=("framework:husky")
{ [ -f "$ROOT/lefthook.yml" ] || [ -f "$ROOT/.lefthook.yml" ]; } && TRIGGER_SURFACES+=("framework:lefthook")

# hook 이 실제로 배선돼 있는가 (I5-b).
#
# .ax/hooks/pre-commit/*.sh 는 settings.json 에 개별 등록하지 않아요 — 디스패처 둘이
# 디렉토리째 glob 해요. settings.json 에 등록된 pre-bash/grep-on-commit.sh 가 에이전트
# 커밋을, install-git-hooks.sh 가 깐 .git/hooks/pre-commit wrapper 가 사람 커밋을 잡아요.
# 그래서 basename 리터럴로 찾으면 배선이 멀쩡해도 항상 미등록으로 나와요.
# rule-enforcement.md I5 가 "settings.json 또는 .git/hooks/pre-commit 에 등록" 이라고
# 규정한 게 이것 — 구현이 앞의 절반만 보고 있었어요.
hook_wired() {   # hook_wired <hook_path> → 0=배선됨
    local hp="$1"
    case "$hp" in
        */hooks/pre-commit/*)
            [ -f "$SETTINGS" ] && grep -q 'grep-on-commit\.sh' "$SETTINGS" 2>/dev/null && return 0
            [ -n "$GIT_PC" ] && [ -f "$GIT_PC" ] && [ -x "$GIT_PC" ] \
                && grep -q "$GOAX_CHAIN_MARKER" "$GIT_PC" 2>/dev/null && return 0
            return 1 ;;
    esac
    [ -f "$SETTINGS" ] && grep -q "$(basename "$hp")" "$SETTINGS" 2>/dev/null
}

# 날짜 차이 (YYYY-MM-DD) — bash 만으로 (date -d 가 BSD 에선 다름. macOS/Linux 호환).
date_diff_days() {
    local d1="$1"; local d2="$2"  # d2 - d1 (양수면 d2 가 미래)
    if date -j -f "%Y-%m-%d" "$d1" +%s >/dev/null 2>&1; then
        # BSD (macOS)
        local s1 s2; s1=$(date -j -f "%Y-%m-%d" "$d1" +%s); s2=$(date -j -f "%Y-%m-%d" "$d2" +%s)
        echo $(( (s2 - s1) / 86400 ))
    else
        # GNU
        local s1 s2; s1=$(date -d "$d1" +%s); s2=$(date -d "$d2" +%s)
        echo $(( (s2 - s1) / 86400 ))
    fi
}

while IFS=$'\t' read -r rid label eb ek file; do
    [ -z "$rid" ] && continue

    # 미작성 예시는 어떤 invariant 도 판정하지 않아요 (보고만)
    if is_placeholder_eb "$eb"; then
        PLACEHOLDERS+=("$rid|$eb|placeholder|$file")
        continue
    fi

    # I1: CRITICAL 인데 enforced_by 가 hook:* 또는 external:* 가 아님
    if [ "$label" = "critical" ]; then
        case "$eb" in
            hook:*|external:*|*hook:*|*external:*) ;;  # OK (단일 또는 +복수)
            *) I1+=("$rid|$eb|$ek|$file") ;;
        esac
    fi

    # I2: TODO 인데 deadline 없음 (TODO 뒤 :YYYY-MM-DD 또는 :+Nd 없음)
    case "$eb" in
        *TODO:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) ;;  # absolute date OK
        *TODO:+[0-9]*) ;;  # 상대 — onboarding 이 절대화 안 한 잔재 (보고만)
        *TODO*) I2+=("$rid|$eb|$ek|$file") ;;
    esac

    # I3: TODO:YYYY-MM-DD 의 deadline 비교
    if [[ "$eb" =~ TODO:([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
        deadline="${BASH_REMATCH[1]}"
        days=$(date_diff_days "$TODAY" "$deadline" 2>/dev/null || echo "")
        if [ -n "$days" ]; then
            if [ "$days" -lt 0 ]; then
                I3_OVERDUE+=("$rid|$deadline|days_overdue=$((-days))|$file")
            elif [ "$days" -le 7 ]; then
                I3_IMMINENT+=("$rid|$deadline|days_left=$days|$file")
            fi
        fi
    fi

    # I6: external:* 인데 리포에 자동 트리거 표면이 하나도 없음
    # (TRIGGER_SURFACES 는 루프 불변 — 룰별 조건은 external 여부뿐이라 루프 안 판정이 안전)
    if [ "${#TRIGGER_SURFACES[@]}" -eq 0 ]; then
        case "$eb" in
            *external:*) I6+=("$rid|$eb|no_trigger|$file") ;;
        esac
    fi

    # I5: enforced_by 가 hook:<path> 형식이면 파일 존재 + 배선 검증
    # eb 안에 hook:.ax/hooks/<...>.sh 추출 (복수면 모두)
    while [[ "$eb" =~ hook:([^[:space:]+]+\.sh) ]]; do
        hook_path="${BASH_REMATCH[1]}"
        if [ ! -f "$ROOT/$hook_path" ]; then
            I5_FILE+=("$rid|$hook_path|file_missing|$file")
        elif ! hook_wired "$hook_path"; then
            I5_REG+=("$rid|$hook_path|not_registered|$file")
        fi
        # 처리한 hook 제거 후 다음 hook 매칭 (복수 처리)
        eb="${eb/hook:$hook_path/}"
    done
done < "$ALL_RULES"

# ─── (5) 보고 ────────────────────────────────────────────────────
TOTAL_VIOLATIONS=$((${#I1[@]} + ${#I2[@]} + ${#I3_OVERDUE[@]} + ${#I5_FILE[@]} + ${#I5_REG[@]} + ${#I6[@]}))

if [ "$JSON_MODE" = true ]; then
    # 배열 → JSON. set -u 환경에서 빈 배열 expand 안전하게.
    arr_to_json() {
        if [ "$#" -eq 0 ]; then echo "[]"; return; fi
        printf '%s\n' "$@" | jq -R 'split("|") | {rule_id: .[0], detail: .[1], extra: .[2], file: .[3]}' | jq -s '.'
    }
    # ${ARR[@]+"${ARR[@]}"} 패턴 — 빈 배열에서도 unbound 에러 안 남
    result=$(jq -n \
        --argjson i1 "$(arr_to_json ${I1[@]+"${I1[@]}"})" \
        --argjson i2 "$(arr_to_json ${I2[@]+"${I2[@]}"})" \
        --argjson i3im "$(arr_to_json ${I3_IMMINENT[@]+"${I3_IMMINENT[@]}"})" \
        --argjson i3od "$(arr_to_json ${I3_OVERDUE[@]+"${I3_OVERDUE[@]}"})" \
        --argjson i5f "$(arr_to_json ${I5_FILE[@]+"${I5_FILE[@]}"})" \
        --argjson i5r "$(arr_to_json ${I5_REG[@]+"${I5_REG[@]}"})" \
        --argjson i6 "$(arr_to_json ${I6[@]+"${I6[@]}"})" \
        --argjson ph "$(arr_to_json ${PLACEHOLDERS[@]+"${PLACEHOLDERS[@]}"})" \
        --argjson ts "$(if [ "${#TRIGGER_SURFACES[@]}" -eq 0 ]; then echo "[]"; else printf '%s\n' "${TRIGGER_SURFACES[@]}" | jq -R . | jq -s .; fi)" \
        --argjson rc "$RULE_COUNT" \
        '{i1_violations: $i1, i2_violations: $i2, i3_imminent: $i3im, i3_overdue: $i3od, i5_file_missing: $i5f, i5_not_registered: $i5r, i6_no_trigger: $i6, placeholder_rules: $ph, trigger_surfaces: $ts, rule_count: $rc}')

    if [ "${#PLACEHOLDERS[@]}" -gt 0 ]; then
        warnings_json=$(printf 'placeholder %d건 — enforced_by 가 아직 예시 자리표시자예요 (실제 값으로 채우면 검사 대상)\n' "${#PLACEHOLDERS[@]}" | jq -R . | jq -sc .)
    else
        warnings_json="[]"
    fi

    if [ "$TOTAL_VIOLATIONS" -eq 0 ]; then
        json_output "ok" "$result" "all invariants pass" "$warnings_json"
    else
        json_output "warning" "$result" "$TOTAL_VIOLATIONS violations — see i*_violations arrays" "$warnings_json"
    fi
else
    if [ "${#PLACEHOLDERS[@]}" -gt 0 ]; then
        goax_warn "placeholder ${#PLACEHOLDERS[@]}건 — enforced_by 가 아직 예시 자리표시자예요 (채우면 검사 대상)"
    fi
    if [ "$TOTAL_VIOLATIONS" -eq 0 ]; then
        goax_log "✓ rule enforcement invariants pass ($RULE_COUNT 룰 검사)"
    else
        goax_log "⚠ rule enforcement: $TOTAL_VIOLATIONS 위반 ($RULE_COUNT 룰 검사)"
        [ "${#I1[@]}" -gt 0 ] && printf '  I1 (CRITICAL ≠ TODO/human/script) %d건\n' "${#I1[@]}" >&2
        [ "${#I2[@]}" -gt 0 ] && printf '  I2 (TODO deadline 없음) %d건\n' "${#I2[@]}" >&2
        [ "${#I3_IMMINENT[@]}" -gt 0 ] && printf '  I3 임박(≤7일) %d건\n' "${#I3_IMMINENT[@]}" >&2
        [ "${#I3_OVERDUE[@]}" -gt 0 ] && printf '  I3 초과 %d건\n' "${#I3_OVERDUE[@]}" >&2
        [ "${#I5_FILE[@]}" -gt 0 ] && printf '  I5 (hook 파일 부재) %d건\n' "${#I5_FILE[@]}" >&2
        [ "${#I5_REG[@]}" -gt 0 ] && printf '  I5 (settings.json 미등록) %d건\n' "${#I5_REG[@]}" >&2
        [ "${#I6[@]}" -gt 0 ] && printf '  I6 (external 인데 자동 트리거 부재 — CI/git hook 없음) %d건\n' "${#I6[@]}" >&2
        goax_log "자세한 보고: $0 --json | jq"
    fi
fi

if [ "$STRICT" = true ] && [ "$TOTAL_VIOLATIONS" -gt 0 ]; then
    exit "$EXIT_ERROR"
fi
exit "$EXIT_OK"
