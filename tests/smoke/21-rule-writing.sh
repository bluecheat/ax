#!/usr/bin/env bash
# tests/smoke/21-rule-writing.sh — §74 rule-lint · §75 post-edit 훅 · §76 rule-draft · §77 rules-budget · §78 rules-compress · §79 rule skill 배선
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/21-rule-writing.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

command -v jq >/dev/null 2>&1 || { pass "jq 없음 — §74–§79 건너뜀"; smoke_done; }

# 세션에서 바로 쓴 룰 꼴 — 날짜 · 건수 · 세션 경위 · 비유 · ADR 문단 · goax 지시가 붙어 있어요
dirty_rule() {
    cat <<'EOF'
---
category: workflow
paths:
  - "**/*.kt"
severity: mandatory
enforced_by:
  - human:review
enforced_kind: human
---

## SP-CWF-008: 테스트는 전체로 돌려요

2026-10-03 이번 세션에서 패키지 필터로만 돌려 12건 통과로 보고했어요.
그 구멍으로 CI 가 처음 잡았어요.
lane-worker 는 전체 테스트를 돌려요.
EOF
}
clean_rule() {
    cat <<'EOF'
---
category: data
paths:
  - "**/*.kt"
severity: mandatory
enforced_by:
  - hook:.ax/hooks/pre-commit/critical-rule-grep.sh
enforced_kind: grep
---

## SP-DATA-001: 금액은 Long 으로 다뤄요

금액 필드를 선언할 때, 작성자는 Long 을 써요.
이유: 부동소수 오차가 정산 금액을 바꿔요.

❌ `val price: Double = 0.0`
✅ `val price: Long = 0`

<!-- 검출 패턴: val [[:alnum:]]*(price|amount)[[:alnum:]]*: Double -->

---

## SP-DATA-002: 커서 페이지는 정렬 키를 고정해요

커서 페이지 쿼리를 쓸 때, 작성자는 정렬 키에 id 를 함께 넣어요.
이유: 같은 값이 여러 행이면 다음 페이지에서 행이 빠져요.

❌ `orderBy(createdAt)`
✅ `orderBy(createdAt, id)`
EOF
}

# ───────────────────────────────────────────────────────────
section "74. rule-lint — 룰에 붙은 세션 흔적을 줄 번호로 지적해요"
# ───────────────────────────────────────────────────────────
if fx_install RL --git; then
    mkdir -p "$RL/.ax/spirit/rules"
    dirty_rule > "$RL/.ax/spirit/rules/workflow.md"; clean_rule > "$RL/.ax/spirit/rules/data.md"
    rl() { (cd "$RL" && GOAX_PROJECT_DIR="$RL" bash .ax/scripts/bash/rule-lint.sh --json "$@" 2>/dev/null); }
    D=$(rl .ax/spirit/rules/workflow.md); C=$(rl .ax/spirit/rules/data.md)
    printf '%s\n' "$D" | jq -e '.result.total >= 3 and .result.counts.trace >= 1 and .result.counts.metaphor >= 1 and .result.counts.harness >= 1
        and ([.result.findings[] | select(.id == "SP-CWF-008")] | length) == .result.total' >/dev/null \
        && pass "rule-lint — 날짜 · 건수 · 세션 경위 · 비유 · goax 지시를 룰 ID 와 함께 지적" \
        || fail "rule-lint 세션 흔적 룰: $(printf '%s' "$D" | jq -c '.result.counts')"
    printf '%s\n' "$C" | jq -e '.result.total == 0' >/dev/null \
        && pass "rule-lint — 고정 틀 룰 두 개는 지적 0건" || fail "rule-lint 깨끗한 룰 오탐: $(printf '%s' "$C" | jq -c '.result.findings')"
    # 예외 — sensors.rule_lint_allow 와 줄 끝 주석
    printf '  rule_lint_allow: ["12건 통과"]\n' >> "$RL/.ax/config.yml"
    sed -i.bak 's/^그 구멍으로 CI 가 처음 잡았어요\.$/그 구멍으로 CI 가 처음 잡았어요. <!-- rule-lint: 예시 -->/' "$RL/.ax/spirit/rules/workflow.md" && rm -f "$RL/.ax/spirit/rules/workflow.md.bak"
    A=$(rl .ax/spirit/rules/workflow.md)
    printf '%s\n' "$A" | jq -e '[.result.findings[] | select(.kind == "metaphor")] | length == 0' >/dev/null \
        && pass "rule-lint — <!-- rule-lint: … --> 줄은 건너뛰어요" || fail "rule-lint 줄 예외: $(printf '%s' "$A" | jq -c '.result.counts')"
    # --changed — 커밋된 룰은 조용하고, 바뀐 블록만 봐요
    git -C "$RL" add -A >/dev/null 2>&1; git -C "$RL" -c core.hooksPath=/dev/null -c user.name=s -c user.email=s@x commit -qm r >/dev/null 2>&1
    CH0=$(rl --changed .ax/spirit/rules/workflow.md | jq -r '.result.total')
    printf '\n---\n\n## SP-CWF-009: 리뷰는 PR #4512 이후로 둘이에요\n\n리뷰어 둘이 봐요.\n' >> "$RL/.ax/spirit/rules/workflow.md"
    CH1=$(rl --changed .ax/spirit/rules/workflow.md | jq -c '[.result.findings[] | .id] | unique')
    [ "$CH0" = 0 ] && [ "$CH1" = '["SP-CWF-009"]' ] \
        && pass "rule-lint --changed — 커밋된 룰은 지적하지 않고 새로 붙인 블록만 봐요" || fail "rule-lint --changed: before=$CH0 after=$CH1"
fi

# 산문 래칫 — skills · agents · commands 의 비유와 세션 경위는 0건, `·` 나열은 기준선을 넘지 않아요
PROSE=$(cd "$REPO" && find skills agents commands -name '*.md' ! -name incidents.md -print0 | sort -z \
    | GOAX_PROJECT_DIR="$REPO" xargs -0 bash templates/default/.ax/scripts/bash/rule-lint.sh --mode prose --json 2>/dev/null)
PROSE_DOTS_CAP=273
printf '%s\n' "$PROSE" | jq -e --argjson cap "$PROSE_DOTS_CAP" \
    '(.result.counts.metaphor // 0) == 0 and (.result.counts.trace // 0) == 0 and (.result.counts.dots // 0) <= $cap' >/dev/null \
    && pass "skills · agents 글쓰기 — 비유 0 · 세션 경위 0 · '·' 나열 ≤ $PROSE_DOTS_CAP (내리기만 해요)" \
    || fail "skills · agents 글쓰기 기준: $(printf '%s' "$PROSE" | jq -c '.result.counts') — $(printf '%s' "$PROSE" | jq -r '[.result.findings[] | select(.kind != "dots") | "\(.file):\(.line) [\(.kind)]"][0:5] | join(", ")')"

# ───────────────────────────────────────────────────────────
section "75. post-edit/rule-lint.sh — 룰 파일 편집만 보고, 막지 않아요"
# ───────────────────────────────────────────────────────────
if fx_install RH --git; then
    mkdir -p "$RH/.ax/spirit/rules"
    clean_rule > "$RH/.ax/spirit/rules/data.md"
    git -C "$RH" add -A >/dev/null 2>&1; git -C "$RH" -c core.hooksPath=/dev/null -c user.name=s -c user.email=s@x commit -qm r >/dev/null 2>&1
    HOOK="$RH/.ax/hooks/post-edit/rule-lint.sh"
    rh() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_PROJECT_DIR="$RH" bash "$HOOK" 2>/dev/null; echo "rc=$?"; }
    mkdir -p "$RH/src"; echo 'x' > "$RH/src/a.kt"
    O0=$(rh "$RH/src/a.kt"); O1=$(rh "$RH/.ax/spirit/rules/data.md")
    printf '\n---\n\n## SP-DATA-003: 2026-09-30 사고 이후 금액은 반올림해요\n\n이번 세션에서 정했어요.\n' >> "$RH/.ax/spirit/rules/data.md"
    O2=$(rh "$RH/.ax/spirit/rules/data.md")
    [ "$O0" = "rc=0" ] && [ "$O1" = "rc=0" ] \
        && printf '%s\n' "$O2" | head -1 | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"
            and (.hookSpecificOutput.additionalContext | test("SP-DATA-003") and test("writing-for-agents.md") and (test("SP-DATA-001") | not))' >/dev/null 2>&1 \
        && [ "$(printf '%s\n' "$O2" | tail -1)" = "rc=0" ] \
        && pass "post-edit/rule-lint — 룰 밖 파일·지적 없는 편집은 조용하고, 새 블록 지적만 additionalContext 로 (exit 0)" \
        || fail "post-edit/rule-lint: O0=$O0 O1=$O1 O2=$(printf '%s' "$O2" | head -c 300)"
    grep -q 'goax_hook_enabled rule-lint' "$HOOK" && grep -q 'goax_cap_context' "$HOOK" \
        && jq -e '[.hooks.PostToolUse[].hooks[].command | select(test("post-edit/rule-lint.sh"))] | length == 1' "$REPO/templates/default/.claude/settings.json.template" >/dev/null \
        && pass "post-edit/rule-lint — 끄기 스위치 · 출력 상한 · settings 템플릿 등록" || fail "post-edit/rule-lint 배선"
fi

# ───────────────────────────────────────────────────────────
section "76. rule-draft — 새 룰에 필요한 사실만 모으고 아무것도 쓰지 않아요"
# ───────────────────────────────────────────────────────────
if fx_install RD; then
    mkdir -p "$RD/.ax/spirit/rules" "$RD/.ax/mistakes"
    clean_rule > "$RD/.ax/spirit/rules/data.md"
    cat > "$RD/.ax/mistakes/2026-10-01-001-data-cursor.md" <<'EOF'
---
category: data
severity: high
---

# 무엇이 일어났나

커서 페이지 정렬 키에서 id 를 빼서 행이 빠졌어요.

# 어디서 (파일·모듈)
`commerce-data/src/main/kotlin/a/OrderAdapter.kt`

# 어떻게 막을 수 있나
- ③ grep 한 줄로 잡히나? 패턴 초안: `orderBy\(createdAt\)`
EOF
    BEFORE=$(fx_tree_sum "$RD")
    RJ=$(cd "$RD" && GOAX_PROJECT_DIR="$RD" bash .ax/scripts/bash/rule-draft.sh --json --dry-run --from-mistake .ax/mistakes/2026-10-01-001-data-cursor.md 2>/dev/null)
    printf '%s\n' "$RJ" | jq -e '.status == "ok" and .result.target.exists and .result.next_id == "SP-DATA-003"
        and (.result.similar | map(.id) | index("SP-DATA-002")) != null and .result.enforcement == "grep"
        and .result.mistakes[0].pattern_compiles and .result.paths.extensions == ["kt"]' >/dev/null \
        && [ "$BEFORE" = "$(fx_tree_sum "$RD")" ] \
        && pass "rule-draft --from-mistake — 대상 파일 · 다음 ID · 겹치는 룰 · 패턴 판정, 파일 불변" \
        || fail "rule-draft: $(printf '%s' "$RJ" | head -c 300)"
    NJ=$(cd "$RD" && GOAX_PROJECT_DIR="$RD" bash .ax/scripts/bash/rule-draft.sh --json --category Bad 2>/dev/null); NRC=$?
    [ "$NRC" = 1 ] && printf '%s\n' "$NJ" | jq -e '.status == "error"' >/dev/null \
        && pass "rule-draft — 대문자 카테고리는 error 봉투 · exit 1" || fail "rule-draft 카테고리 검증: rc=$NRC $NJ"
fi

# ───────────────────────────────────────────────────────────
section "77. rules-budget — 상시 로드 · 파일 크기 · 편집당 Read 를 재요"
# ───────────────────────────────────────────────────────────
if fx_install RB --git; then
    mkdir -p "$RB/.ax/spirit/rules"
    { dirty_rule; for i in $(seq 1 200); do printf '긴 설명 줄 %s\n' "$i"; done; } > "$RB/.ax/spirit/rules/workflow.md"
    mkdir -p "$RB/src"; echo 'x' > "$RB/src/a.kt"; git -C "$RB" add -A >/dev/null 2>&1
    BJ=$(cd "$RB" && GOAX_PROJECT_DIR="$RB" bash .ax/scripts/bash/rules-budget.sh --json 2>/dev/null)
    DS=$(cd "$RB" && bash .ax/scripts/bash/doctor-scan.sh --json 2>/dev/null | jq -r '.result.budget.bytes')
    printf '%s\n' "$BJ" | jq -e --argjson ds "${DS:-0}" '.status == "ok" and .result.always.bytes == $ds
        and ([.result.over_budget[] | select(.kind == "file_lines" and .target == ".ax/spirit/rules/workflow.md")] | length) == 1
        and (.result.edit == null or .result.edit.max >= 1000)' >/dev/null \
        && pass "rules-budget — always 는 doctor-scan budget 과 같은 값, 150줄 넘는 룰 파일은 over_budget" \
        || fail "rules-budget: ds=$DS $(printf '%s' "$BJ" | jq -c '.result | {always, edit, over_budget}' | head -c 400)"
fi

# ───────────────────────────────────────────────────────────
section "78. rules-compress --verify — 줄여도 바뀌면 안 되는 것"
# ───────────────────────────────────────────────────────────
if fx_install RC --git; then
    mkdir -p "$RC/.ax/spirit/rules"
    { clean_rule; printf '\n<!-- adr: .ax/docs/adr/0001-money.md -->\n\n자세한 설명 문단이 길게 이어져요.\n'; } > "$RC/.ax/spirit/rules/data.md"
    git -C "$RC" add -A >/dev/null 2>&1; git -C "$RC" -c core.hooksPath=/dev/null -c user.name=s -c user.email=s@x commit -qm r >/dev/null 2>&1
    rc() { (cd "$RC" && GOAX_PROJECT_DIR="$RC" bash .ax/scripts/bash/rules-compress.sh --json "$@" 2>/dev/null); }
    reset() { git -C "$RC" checkout -q -- .ax/spirit/rules; }
    F="$RC/.ax/spirit/rules/data.md"
    NOSNAP=$(rc --verify; echo "rc=$?")
    rc --snapshot >/dev/null
    [ -f "$RC/.ax/.rules-snapshot/.ax/spirit/rules/data.md" ] && git -C "$RC" check-ignore -q .ax/.rules-snapshot/x \
        && pass "rules-compress --snapshot — 사본은 .ax/.rules-snapshot/ 이고 gitignore 대상" || fail "rules-compress 사본 위치"
    case "$NOSNAP" in *'"status":"error"'*rc=1) pass "rules-compress --verify — 사본 없으면 error · exit 1" ;; *) fail "사본 없는 verify: $NOSNAP" ;; esac
    V=""
    perl -ni -e 'print unless /자세한 설명 문단/' "$F"; OK1=$(rc --verify | jq -r '.status'); reset
    perl -pi -e 's/^## SP-DATA-001: .*/## SP-DATA-001: 금액 타입/' "$F"; OK2=$(rc --verify | jq -c '[.status, (.warnings | length)]'); reset
    perl -ni -e 'print unless /^## SP-DATA-002:/' "$F"; V="$V $(rc --verify >/dev/null; echo $?)"; reset
    perl -0pi -e 's/paths:\n  - "\*\*\/\*.kt"/paths: ["**\/*.kt"]/' "$F"; V="$V $(rc --verify >/dev/null; echo $?)"; reset
    perl -pi -e 's/<!-- 검출 패턴: .* -->/<!-- 검출 패턴: Double -->/' "$F"; V="$V $(rc --verify >/dev/null; echo $?)"; reset
    perl -ni -e 'print unless /^❌ `val price/' "$F"; V="$V $(rc --verify >/dev/null; echo $?)"; reset
    perl -ni -e 'print unless /<!-- adr:/' "$F"; V="$V $(rc --verify >/dev/null; echo $?)"; reset
    KINDS=$(perl -ni -e 'print unless /^## SP-DATA-002:/' "$F"; rc --verify | jq -c '[.result.files[].violations[].kind] | unique'); reset
    [ "$OK1" = ok ] && [ "$OK2" = '["ok",1]' ] && [ "$V" = " 1 1 1 1 1" ] \
        && pass "rules-compress --verify — 설명 삭제 통과 · 제목 변경은 warning · ID 삭제 · paths 한 줄 · 패턴 변경 · 패턴 룰 예시 삭제 · adr 삭제는 exit 1" \
        || fail "rules-compress --verify: ok1=$OK1 ok2=$OK2 violations=[$V] kinds=$KINDS"
    rc --clear >/dev/null; [ ! -d "$RC/.ax/.rules-snapshot" ] && pass "rules-compress --clear — 사본 삭제" || fail "rules-compress --clear"
fi

# ───────────────────────────────────────────────────────────
section "79. rule skill 배선 — 룰 본문을 쓰는 길은 하나예요"
# ───────────────────────────────────────────────────────────
RS="$REPO/skills/rule/SKILL.md"
{ grep -q 'rule-draft.sh' "$RS" && grep -q 'rule-lint.sh' "$RS" && grep -q 'promote-mistake.sh --apply .*--file' "$RS" \
  && grep -q 'zero-probe.sh --only pattern-rules' "$RS" && grep -q 'model: "haiku"' "$RS" \
  && grep -q 'rules-compress.sh --verify' "$REPO/skills/rule/references/compress.md" && grep -q 'rules-budget.sh' "$REPO/skills/rule/references/compress.md" \
  && grep -q '`rule` skill' "$REPO/skills/audit/SKILL.md" && ! grep -q 'spirit/rules 에 직접 Edit' "$REPO/skills/audit/SKILL.md" \
  && grep -q 'rule-lint.sh' "$REPO/skills/onboarding/SKILL.md" && grep -q 'rules-budget.sh' "$REPO/skills/doctor/SKILL.md" \
  && grep -q '이유: <한 줄>' "$REPO/templates/default/.ax/_templates/spirit/rule.md"; } \
    && pass "rule skill — draft · lint · 프로브 · 신입 테스트 · 압축 가드, audit · onboarding · doctor · 템플릿이 같은 틀을 가리켜요" \
    || fail "rule skill 배선 누락"
if fx_install PM; then
    for n in 1 2; do printf -- '---\ncategory: data\n---\n# 무엇이 일어났나\nx%s\n' "$n" > "$PM/.ax/mistakes/2026-10-0$n-00$n-data-x.md"; done
    PJ=$(cd "$PM" && GOAX_PROJECT_DIR="$PM" bash .ax/scripts/bash/promote-mistake.sh --apply --json --token SP-DATA-003 --category data --file .ax/mistakes/2026-10-01-001-data-x.md 2>/dev/null)
    printf '%s\n' "$PJ" | jq -e '.result.marked_count == 1' >/dev/null && grep -q '^promoted_to: SP-DATA-003' "$PM/.ax/mistakes/2026-10-01-001-data-x.md" \
        && ! grep -q '^promoted_to:' "$PM/.ax/mistakes/2026-10-02-002-data-x.md" \
        && pass "promote-mistake --apply --file — 고른 mistake 만 마킹해요" || fail "promote-mistake --file: $PJ"
fi

smoke_done
