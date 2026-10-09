#!/usr/bin/env bash
# tests/smoke/17-budget-screen.sh — §62–§64 — 훅 출력 예산 · screen · 레인 정리
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/17-budget-screen.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

section "62. 훅 출력 예산 — 모델에게 주는 글은 10,000자 상한 아래, 한글 중간에서 안 끊어요"
# ───────────────────────────────────────────────────────────
# Claude Code 는 훅의 additionalContext·stdout 이 10,000자를 넘으면 파일로 빼고 앞 2,000자만 보여 줘요.
# 그 파일을 읽으라고 하지도 않아요. 그래서 주입 훅은 goax_cap_context 로 먼저 줄여요.
# 최악 입력(50KB 출력 lint · 모듈/룰 수백 개 · 아주 긴 브리핑)을 넣고, 출력이 유효한 JSON 이고 상한 아래인지 봐요.
if command -v jq >/dev/null 2>&1; then
    OB=$(mktemp -d)
    mkdir -p "$OB/.ax/scripts/bash" "$OB/.ax/hooks" "$OB/src" "$OB/.ax/spirit/rules" "$OB/.ax/modules"
    cp "$REPO/templates/default/.ax/scripts/bash/"*.sh "$OB/.ax/scripts/bash/"; cp -R "$REPO/templates/default/.ax/hooks/"* "$OB/.ax/hooks/"
    cp "$REPO/templates/default/.ax/config.yml" "$OB/.ax/config.yml"; cp "$REPO/templates/default/.ax/current-task.json.template" "$OB/.ax/current-task.json"
    : > "$OB/src/a.ts"
    # 상한 검사 — 유효 JSON · 문자 수 < 10000 · 바이트 수 ≤ 8000 · 깨진 글자(U+FFFD) 없음 · 생략 꼬리 있음
    ob_check() {   # <이름> <훅 stdout>
        local name="$1" out="$2" ctx chars bytes
        ctx=$(printf '%s' "$out" | jq -er '.hookSpecificOutput.additionalContext' 2>/dev/null) \
            || { fail "$name — 유효한 JSON additionalContext 가 아니에요: $(printf '%s' "$out" | head -c 200)"; return; }
        chars=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext | length')
        bytes=$(printf '%s' "$ctx" | LC_ALL=C wc -c | tr -d ' ')
        if [ "$chars" -lt 10000 ] && [ "$bytes" -le 8000 ] && ! printf '%s' "$ctx" | grep -q $'\xef\xbf\xbd' \
            && printf '%s' "$ctx" | grep -q '생략'; then
            pass "$name — 최악 입력에서도 ${chars}자·${bytes}바이트, 유효 JSON, 생략 꼬리"
        else
            fail "$name — chars=$chars bytes=$bytes (상한 10000자·8000바이트, 생략 꼬리 필요)"
        fi
    }
    # 헬퍼 단위 — 상한 아래면 그대로, 넘으면 꼬리까지 상한 안 · 바이트 경계가 글자 중간이어도 유효한 UTF-8
    OBH=$( (source "$REPO/templates/default/.ax/scripts/bash/common.sh"
        [ "$(printf 'short' | goax_cap_context)" = short ] || echo "짧은 입력이 바뀜"
        for m in 100 101 102 103; do
            r=$(awk 'BEGIN{for(i=0;i<20000;i++) printf "가나다"; print ""}' | goax_cap_context "$m" "전체: x")
            b=$(printf '%s' "$r" | LC_ALL=C wc -c | tr -d ' ')
            [ "$b" -le "$m" ] || echo "max=$m 인데 $b바이트"
            printf '%s' "$r" | jq -Rrs . 2>/dev/null | grep -q $'\xef\xbf\xbd' && echo "max=$m 에서 글자가 깨짐"
            printf '%s' "$r" | tail -1 | grep -q '바이트 생략 — 전체: x$' || echo "max=$m 꼬리 없음: $(printf '%s' "$r" | tail -1)"
        done) 2>&1)
    [ -z "$OBH" ] && pass "goax_cap_context — 상한 아래면 그대로, 넘으면 꼬리까지 상한 안 · 3바이트 글자를 반으로 안 잘라요" \
        || fail "goax_cap_context: $OBH"

    # lint-changed — 50KB 넘게 찍고 실패하는 lint_file 명령
    cat > "$OB/big-lint.sh" <<'EOF'
awk 'BEGIN{for(i=0;i<20000;i++) printf "한글"; print ""; for(i=0;i<500;i++) print "src/a.ts:" i " 경고 " i}'
exit 1
EOF
    (cd "$OB" && bash .ax/scripts/bash/config-set.sh --add commands.lint_file '**/*.ts => bash big-lint.sh {file}' >/dev/null)
    ob_check "lint-changed" "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$OB/src/a.ts" \
        | CLAUDE_PROJECT_DIR="$OB" bash "$OB/.ax/hooks/post-edit/lint-changed.sh")"

    # module-rules-inject — src/** 에 걸린 모듈 300개
    i=0; while [ "$i" -lt 300 ]; do
        mkdir -p "$OB/.ax/modules/module-with-a-fairly-long-name-$i"
        printf -- '---\napplies_to: [code]\npaths:\n  - "src/**"\n---\n' > "$OB/.ax/modules/module-with-a-fairly-long-name-$i/rules.md"
        printf -- '---\ncategory: c%s\npaths:\n  - "src/**"\n---\n## SP-C%s-001: x\n' "$i" "$i" > "$OB/.ax/spirit/rules/category-with-a-long-name-$i.md"
        i=$((i + 1))
    done
    ob_check "module-rules-inject" "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.ts"}}' \
        | CLAUDE_PROJECT_DIR="$OB" bash "$OB/.ax/hooks/pre-edit/module-rules-inject.sh")"
    ob_check "spirit-rules-inject" "$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.ts"}}' \
        | CLAUDE_PROJECT_DIR="$OB" bash "$OB/.ax/hooks/pre-edit/spirit-rules-inject.sh")"

    # session-brief 훅 — 스크립트 상한을 아주 크게 잡은 경우를 흉내 내요 (스크립트를 50KB 를 내는 가짜로)
    cat > "$OB/.ax/scripts/bash/session-brief.sh" <<'EOF'
awk 'BEGIN{printf "{\"status\":\"ok\",\"result\":{\"lines\":["; for(i=0;i<1000;i++) printf "%s\"인계 노트 항목 %d — 아주 긴 설명이 붙어 있어요\"", (i?",":""), i; print "]}}"}'
EOF
    ob_check "session-brief 훅" "$(printf '{"session_id":"s","source":"startup"}' \
        | CLAUDE_PROJECT_DIR="$OB" bash "$OB/.ax/hooks/session-start/session-brief.sh")"

    # harness-pointer — 경로 몇 줄이라 자를 일은 없지만, 출력은 유효 JSON 이고 같은 함수를 거쳐요
    HPO=$(printf '{"agent_type":"Explore"}' | CLAUDE_PROJECT_DIR="$OB" bash "$OB/.ax/hooks/subagent-start/harness-pointer.sh")
    { [ -z "$HPO" ] || printf '%s' "$HPO" | jq -e '.hookSpecificOutput.additionalContext | length < 10000' >/dev/null; } \
        && pass "harness-pointer — 유효 JSON · 상한 아래" || fail "harness-pointer 출력: $HPO"

    # block-destructive — heredoc 으로 50KB 를 쓰는 명령 끝에 rm -rf / 가 붙으면 되돌려 주는 원문은 앞부분만
    BIG=$(awk 'BEGIN{for(i=0;i<20000;i++) printf "가나"}')
    BDE=$(jq -nc --arg c "cat > f <<'X'
$BIG
X
rm -rf /" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$OB" bash "$OB/.ax/hooks/pre-bash/block-destructive.sh" 2>&1 >/dev/null); BDR=$?
    BDB=$(printf '%s' "$BDE" | LC_ALL=C wc -c | tr -d ' ')
    [ "$BDR" = 2 ] && [ "$BDB" -lt 2000 ] && printf '%s' "$BDE" | grep -q '생략 — 원문은 방금 보낸 명령 그대로예요' \
        && pass "block-destructive — 막을 때 되돌려 주는 명령은 앞 600바이트만 (${BDB}바이트)" \
        || fail "block-destructive 큰 명령: rc=$BDR bytes=$BDB"
    rm -rf "$OB"
else
    pass "§61 — jq 없음, skip"
fi
# 정적 — additionalContext 를 내는 훅은 전부 goax_cap_context 를 거쳐요 (stop/ 은 다른 레인이 맡아요)
OB_MISS=""
for h in "$REPO"/templates/default/.ax/hooks/*/*.sh; do
    case "$h" in */stop/*|*/pre-commit/*) continue ;; esac
    grep -q 'additionalContext:' "$h" || continue
    grep -q 'goax_cap_context' "$h" || OB_MISS="$OB_MISS $(basename "$(dirname "$h")")/$(basename "$h")"
done
[ -z "$OB_MISS" ] && pass "additionalContext 를 내는 훅 전부 goax_cap_context 를 거쳐요" \
    || fail "goax_cap_context 없이 additionalContext 를 내는 훅:$OB_MISS"

# ───────────────────────────────────────────────────────────
section "63. screen — 외부 의존 없는 화면 skill · screen-designer · design-caps · screen-measure"
# ───────────────────────────────────────────────────────────
# 지식은 skill 안에 다 있어야 해요 — 개인 경로·특정 외부 스킬·특정 MCP·특정 디자인 시스템 이름이 새면 다른 머신에서 깨져요
SC_LEAK=$(grep -rnE '~/\.claude|ui-ux-pro-max|taste-skill|frontend-design|uibowl|mcp-connect|mcp__[[:alnum:]_-]+__|\bSeed\b|\bSEED\b|토스([^트]|$)|당근' \
          "$REPO/skills/screen" "$REPO/agents/screen-designer.md" 2>/dev/null || true)
[ -z "$SC_LEAK" ] && pass "screen · screen-designer — 개인 경로·외부 스킬·특정 MCP·디자인 시스템 이름 0건 (자립)" \
    || fail "screen — 외부 의존이 새요:
$(printf '%s' "$SC_LEAK" | head -5)"
grep -q '시작 전 필수' "$REPO/agents/screen-designer.md" && grep -q '시작 전 필수' "$REPO/skills/screen/SKILL.md" \
    && pass "screen · screen-designer — 시작 전 필수 (spirit 로드)" || fail "screen — 시작 전 필수 누락"
{ grep -q 'verdict:' "$REPO/agents/screen-designer.md" && grep -q 'verdict:' "$REPO/skills/screen/SKILL.md" \
  && grep -q '실측 아님' "$REPO/agents/screen-designer.md"; } \
    && pass "screen — 리포트 첫 줄 verdict 계약 · 실측 못 하면 \"실측 아님\" (skill · agent 양쪽)" || fail "screen — verdict 계약 누락"
{ grep -q 'design-caps.sh' "$REPO/skills/screen/SKILL.md" && grep -q 'screen-measure.sh' "$REPO/agents/screen-designer.md"; } \
    && pass "screen — 진입은 design-caps.sh, 실측은 screen-measure.sh (결정론 경계)" || fail "screen — 스크립트 연결 누락"
[ "$(grep -E '^model:' "$REPO/agents/screen-designer.md")" = "model: inherit" ] && pass "screen-designer — 모델을 고정하지 않아요 (model: inherit)" || fail "screen-designer — model 이 inherit 가 아니에요"

DC=$(mktemp -d)
mkdir -p "$DC/.ax/scripts/bash" "$DC/src/theme" "$DC/.storybook"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,design-caps,screen-measure}.sh "$DC/.ax/scripts/bash/"
echo '{"dependencies":{"react":"18","next":"14"}}' > "$DC/package.json"
echo ':root{--brand:#f60}' > "$DC/src/theme/tokens.css"; echo '{}' > "$DC/components.json"
echo '{"mcpServers":{"figma":{"type":"http","url":"https://x","headers":{"Authorization":"Bearer SECRET-SHOULD-NOT-LEAK"}},"mobbin":{"type":"http"},"shadcn":{"command":"npx"}}}' > "$DC/.mcp.json"
DCJ=$(cd "$DC" && HOME="$DC" GOAX_PROJECT_DIR="$DC" bash "$DC/.ax/scripts/bash/design-caps.sh" --json 2>/dev/null)
printf '%s' "$DCJ" | jq -e '.result.stack == "web"
    and (.result.slots.tokens[0] | .provider == "file" and .detail == "src/theme/tokens.css")
    and ([.result.slots.tokens[].provider] | index("mcp:figma")) != null
    and ([.result.slots.reference[].provider] | index("mcp:mobbin")) != null
    and ([.result.slots.components[].provider] | (index("file") != null and index("mcp:shadcn") != null))' >/dev/null \
    && pass "design-caps — 스택 · 프로젝트 토큰 파일이 먼저 · MCP 이름을 슬롯에 (figma→tokens, mobbin→reference, shadcn→components)" \
    || fail "design-caps — 슬롯 판정 불일치: $(printf '%s' "$DCJ" | jq -c '.result' 2>/dev/null | head -c 300)"
printf '%s' "$DCJ" | grep -q 'SECRET-SHOULD-NOT-LEAK' && fail "design-caps — MCP 설정의 비밀값이 출력에 샜어요" \
    || pass "design-caps — MCP 는 서버 이름만, 비밀값은 출력하지 않아요"
if python3 -c 'import PIL' >/dev/null 2>&1; then
    python3 - "$DC" <<'PYM'
import sys
from PIL import Image, ImageDraw
d = sys.argv[1]
im = Image.new("RGB", (1170, 600), (255, 255, 255)); ImageDraw.Draw(im).rectangle([60, 300, 1109, 455], fill=(255, 111, 15)); im.save(d + "/a.png")
ImageDraw.Draw(im).rectangle([60, 300, 1109, 455], fill=(0, 0, 0)); im.save(d + "/b.png")
PYM
    SMJ=$(GOAX_PROJECT_DIR="$DC" bash "$DC/.ax/scripts/bash/screen-measure.sh" --image "$DC/a.png" --logical-width 390 --x 195 --json 2>/dev/null)
    printf '%s' "$SMJ" | jq -e '.result.scale == 3 and ([.result.lines[0].segments[] | select(.rgb == [255,111,15])][0] | .start == 100 and .length == 52)' >/dev/null \
        && pass "screen-measure — 3배 스크린샷의 버튼을 y 100 · 높이 52pt 로 재요" || fail "screen-measure — 스캔 불일치: $(printf '%s' "$SMJ" | head -c 300)"
    SMD=$(GOAX_PROJECT_DIR="$DC" bash "$DC/.ax/scripts/bash/screen-measure.sh" --diff "$DC/a.png" "$DC/b.png" --json 2>/dev/null)
    SMS=$(GOAX_PROJECT_DIR="$DC" bash "$DC/.ax/scripts/bash/screen-measure.sh" --diff "$DC/a.png" "$DC/a.png" --crop-top 10 --json 2>/dev/null)
    { printf '%s' "$SMD" | jq -e '.result.same == false and .result.bbox == [60,300,1110,456]' >/dev/null \
      && printf '%s' "$SMS" | jq -e '.result.same == true and .result.bbox == null' >/dev/null; } \
        && pass "screen-measure --diff — 바뀐 영역 bbox · 같으면 same" || fail "screen-measure --diff 불일치: $SMD / $SMS"
else
    GOAX_PROJECT_DIR="$DC" bash "$DC/.ax/scripts/bash/screen-measure.sh" --image x.png --logical-width 390 --x 1 >/dev/null 2>&1
    [ $? -eq 2 ] && pass "screen-measure — Pillow 없으면 exit 2 (skipped — \"실측 아님\")" || fail "screen-measure — Pillow 없는데 skip 이 아니에요"
fi

# 리포트 판정 — 첫 줄 verdict 만 믿지 않아요: 통과면 실제 스크린샷 · 측정값 빈 칸 0 · ❌ 0
mkdir -p "$DC/docs/design/reports" "$DC/shots"; : > "$DC/shots/after-390.png"
cp "$REPO/templates/default/.ax/scripts/bash/screen-report-check.sh" "$DC/.ax/scripts/bash/"
src_report() {   # $1 verdict · $2 스크린샷 경로 · $3 측정값 · $4 결과
    printf '%s\n' "verdict: $1" "## 화면 리포트 — x" "### 스크린샷" "- 후: \`$2\`" "### 게이트" \
        "| 항목 | 측정값 | 기준 | 결과 |" "|---|---|---|---|" "| G1 주 버튼 높이 | $3 | ≥ 44 | $4 |" "### 미해결" "- 없음" \
        > "$DC/docs/design/reports/r.md"
    GOAX_PROJECT_DIR="$DC" bash "$DC/.ax/scripts/bash/screen-report-check.sh" --json 2>/dev/null | jq -c '[.result.valid, .result.verdict]'
}
SRC_OK=$(src_report 통과 shots/after-390.png "52 (px·390)" ✅); SRC_NOSHOT=$(src_report 통과 shots/none.png "52 (px·390)" ✅)
SRC_EMPTY=$(src_report 통과 shots/after-390.png "" ✅); SRC_FAILPASS=$(src_report 통과 shots/after-390.png "40 (px·390)" ❌)
SRC_NA=$(src_report "실측 아님" none.png "40 (코드)" ❌)
SRC_CODE=$(src_report 통과 shots/after-390.png "코드값 52 (실측 아님)" ✅)
printf 'hello\n' > "$DC/docs/design/reports/r.md"
SRC_BAD=$(GOAX_PROJECT_DIR="$DC" bash "$DC/.ax/scripts/bash/screen-report-check.sh" --json 2>/dev/null | jq -c '[.result.valid, .result.verdict]')
{ [ "$SRC_OK" = '[true,"통과"]' ] && [ "$SRC_NOSHOT" = '[false,"통과"]' ] && [ "$SRC_EMPTY" = '[false,"통과"]' ] \
  && [ "$SRC_FAILPASS" = '[false,"통과"]' ] && [ "$SRC_NA" = '[true,"실측 아님"]' ] && [ "$SRC_CODE" = '[false,"통과"]' ] && [ "$SRC_BAD" = '[false,null]' ]; } \
    && pass "screen-report-check — 통과는 실제 스크린샷·측정값·❌0·코드값 0 이어야, 실측 아님은 미해결과 함께, 첫 줄 형식 검사" \
    || fail "screen-report-check 판정 불일치: ok=$SRC_OK noshot=$SRC_NOSHOT empty=$SRC_EMPTY failpass=$SRC_FAILPASS na=$SRC_NA code=$SRC_CODE bad=$SRC_BAD"
rm -rf "$DC"

# 게이트 목록은 하나예요 — SKILL.md · screen-designer · spec-template 표 7 의 G 번호 집합이 같아야 해요
gate_ids() { grep -oE '\bG[0-9]{1,2}\b' "$1" 2>/dev/null | sort -u -t G -k2 -n | paste -sd, -; }
G_SKILL=$(gate_ids "$REPO/skills/screen/SKILL.md"); G_AGENT=$(gate_ids "$REPO/agents/screen-designer.md")
G_TPL=$(gate_ids "$REPO/skills/screen/references/spec-template.md")
{ [ -n "$G_SKILL" ] && [ "$G_SKILL" = "$G_AGENT" ] && [ "$G_SKILL" = "$G_TPL" ]; } \
    && pass "screen 게이트 — SKILL · screen-designer · spec-template 표 7 이 같은 목록 ($(printf '%s' "$G_SKILL" | tr ',' '\n' | grep -c .)개)" \
    || fail "screen 게이트 목록이 갈려요 — SKILL[$G_SKILL] agent[$G_AGENT] template[$G_TPL]"

# ───────────────────────────────────────────────────────────
section "64. 레인 정리 — 보고·검증 뒤 TaskStop, 묻지 않음, 외부 쓰기는 브리프 허용분만"

# 레인은 보고 뒤에도 idle 로 남아요 (실측: 하루 46개). 규칙이 문서에서 빠지면 다시 쌓여요.
LM="$REPO/skills/spec-implement/references/lane-mode.md"; LS="$REPO/skills/lane/SKILL.md"
{ grep -q '3.5 레인 정리' "$LM" && grep -q 'TaskStop' "$LM" && grep -q '한 번만' "$LM" \
  && grep -q 'shutdown_request` 를 보내지 않아요' "$LM"; } \
    && pass "lane-mode §3.5 — 검증 통과 뒤 TaskStop, 재시도 한 번 상한, shutdown_request 로 묻지 않음" \
    || fail "lane-mode §3.5 레인 정리 절차가 빠졌어요 (TaskStop · 재시도 상한 · 묻지 않음)"
awk '/^\*\*5\. 종료 조건/,/^\*\*6\./' "$LM" | grep -q 'ListAgents' \
    && pass "lane-mode §5 — 종료 조건에 살아 있는 레인 0개 (ListAgents)" \
    || fail "lane-mode §5 종료 조건에 ListAgents 대조가 없어요 — 원장 밖 레인을 못 잡아요"
{ grep -q 'lane-<레인>' "$LM" && grep -q 'scout-<주제>' "$LM"; } \
    && pass "lane-mode — 레인 이름 접두사(lane-·scout-) 규칙 — 정리가 목록 거르기로 끝나요" \
    || fail "lane-mode — 레인 이름 규칙이 없어요"
{ grep -q '^## 외부 쓰기 허용' "$LS" && grep -q '"type": "shutdown_response"' "$LS"; } \
    && pass "lane §10 브리프 — 외부 쓰기 허용(기본 없음) · 종료 응답 객체 형식이 브리프에 실려요" \
    || fail "lane §10 브리프에 외부 쓰기 허용 절이나 종료 응답 형식이 없어요"
for ag in lane-worker lane-scout; do
    f="$REPO/agents/$ag.md"
    { grep -q 'PATCH' "$f" && grep -q '"message": {"type": "shutdown_response"' "$f" \
      && ! grep -qE '"message": "\{' "$f"; } \
        && pass "$ag — 외부 쓰기 금지 · 종료 응답은 객체 (문자열 예시 없음)" \
        || fail "$ag — 외부 쓰기 금지나 객체 형식 종료 응답이 빠졌어요"
done

smoke_done
