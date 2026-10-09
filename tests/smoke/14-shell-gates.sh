#!/usr/bin/env bash
# tests/smoke/14-shell-gates.sh — §50–§54 — 셸 스캔 · destructive-facts · rule-read-gate · 훅 프로필 · session-brief
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/14-shell-gates.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "50. goax_shell_scan · block-hook-bypass — 에이전트가 git 훅을 끄는 형태만 막아요"
# ───────────────────────────────────────────────────────────
# 정규식 한 줄로 보면 `git commit -m "fix -n handling"` 의 -n 을 플래그로 읽어요 — 토큰 단위 판정을 고정해요.
if command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    HB=$(mktemp -d)
    mkdir -p "$HB/.ax/scripts/bash" "$HB/.ax/hooks/pre-bash"
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$HB/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-bash/block-hook-bypass.sh" "$HB/.ax/hooks/pre-bash/"
    hb_rc() { jq -nc --arg c "$1" --arg d "$HB" '{tool_input:{command:$c},session_id:"s",cwd:$d}' \
        | CLAUDE_PROJECT_DIR="$HB" bash "$HB/.ax/hooks/pre-bash/block-hook-bypass.sh" >/dev/null 2>&1; echo $?; }
    HB_MISS=0
    for c in 'git commit --no-verify -m x' 'git commit -nm wip' 'git push --no-verify' 'git -C sub merge --no-verify x' \
             'git -c core.hooksPath=/dev/null commit -m x' 'git config core.hooksPath .none' 'HUSKY=0 git commit -m x' \
             'bash -lc "git commit --no-verify -m x"' 'cd a && git commit --no-verify'; do
        [ "$(hb_rc "$c")" = 2 ] || { fail "block-hook-bypass 미차단: $c"; HB_MISS=1; }
    done
    [ "$HB_MISS" -eq 0 ] && pass "block-hook-bypass — 우회 9형태 차단 (--no-verify · commit -n · -c/config core.hooksPath · HUSKY=0 · sh -c 안쪽)"
    HB_FP=0
    for c in 'git commit -m "fix -n handling"' 'git commit -am x' 'git commit -mn' 'git push -n origin main' \
             'git config core.hooksPath' 'echo "--no-verify" && git status' "$(printf 'git commit -F - <<EOF\nuse --no-verify\nEOF')" 'ls -la'; do
        [ "$(hb_rc "$c")" = 0 ] || { fail "block-hook-bypass 오탐: $c"; HB_FP=1; }
    done
    [ "$HB_FP" -eq 0 ] && pass "block-hook-bypass — 메시지 속 -n·--no-verify · push -n(dry-run) · heredoc 본문 · 읽기 전용 config 는 통과 (오탐 0)"
    printf 'sensors:\n  mode: warning\n' > "$HB/.ax/config.yml"
    [ "$(hb_rc 'git push --no-verify')" = 2 ] && pass "block-hook-bypass — sensors.mode=warning 에서도 막아요" \
        || fail "block-hook-bypass — warning 모드에서 통과해요"
    printf 'sensors:\n  hook_profile: minimal\n' > "$HB/.ax/config.yml"
    [ "$(hb_rc 'git push --no-verify')" = 2 ] && pass "block-hook-bypass — minimal 프로필에서도 돌아요 (안전망)" \
        || fail "block-hook-bypass — minimal 프로필에서 꺼져요"
    printf 'sensors:\n  disabled_hooks: [block-hook-bypass]\n' > "$HB/.ax/config.yml"
    [ "$(hb_rc 'git push --no-verify')" = 0 ] && pass "block-hook-bypass — disabled_hooks 로 끌 수 있어요" \
        || fail "block-hook-bypass — disabled_hooks 가 안 먹어요"
    rm -rf "$HB"
else
    pass "§50 — jq/python3 없음, skip"
fi
grep -q 'block-hook-bypass' "$REPO/templates/default/.ax/hooks/pre-commit/spec-completion-gate.sh" \
    && ! grep -q '사용자 승인 후 --no-verify' "$REPO/templates/default/.ax/hooks/pre-commit/spec-completion-gate.sh" \
    && pass "spec-completion-gate — 에이전트에게 --no-verify 를 권하지 않아요" \
    || fail "spec-completion-gate 가 아직 --no-verify 를 권해요"

# ───────────────────────────────────────────────────────────
section "51. destructive-facts — 프로젝트 안 되돌리기 어려운 명령은 한 번 막고 사실을 요구해요"
# ───────────────────────────────────────────────────────────
# 실측(commerce): 내가 만든 파일을 되돌리려 rm -rf 로 디렉토리째 지웠다가 추적 안 되던 운영 파일이 같이 사라졌어요.
if command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    DF=$(mktemp -d)
    mkdir -p "$DF/.ax/scripts/bash" "$DF/.ax/hooks/pre-bash" "$DF/src"
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$DF/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-bash/destructive-facts.sh" "$DF/.ax/hooks/pre-bash/"
    df_rc() { jq -nc --arg c "$1" --arg s "${2:-s1}" --arg d "$DF" '{tool_input:{command:$c},session_id:$s,cwd:$d}' \
        | CLAUDE_PROJECT_DIR="$DF" bash "$DF/.ax/hooks/pre-bash/destructive-facts.sh" >/dev/null 2>&1; echo $?; }
    DF_MISS=0; k=0
    for c in 'rm -rf src' 'rm -rf .' 'cd src && rm -rf ../src' 'sh -c "rm -rf src"' 'ls | xargs rm -rf' \
             'find src -name "*.orig" -delete' 'git clean -fd' 'git checkout -- src/a.kt' 'git checkout .' \
             'git restore src/a.kt' 'git reset --hard' 'git stash drop' 'git branch -D feat'; do
        k=$((k+1))
        [ "$(df_rc "$c" "m$k")" = 2 ] || { fail "destructive-facts 미차단: $c"; DF_MISS=1; }
    done
    [ "$DF_MISS" -eq 0 ] && pass "destructive-facts — 13형태 첫 시도 차단 (재귀 rm · cd 추적 · sh -c · xargs · find -delete · git clean/checkout/restore/reset/stash/branch)"
    DF_FP=0
    for c in 'rm -rf build' 'rm -rf app/build dist node_modules' 'rm -rf /tmp/x' 'rm src/a.kt' 'rm -rf "$TMP"' \
             'git clean -nfd' 'git checkout main' 'git restore --staged src/a.kt' 'git reset --soft HEAD~1' \
             'git stash pop' 'git branch -d feat' 'find /tmp -delete' 'echo "rm -rf src"'; do
        [ "$(df_rc "$c" fp)" = 0 ] || { fail "destructive-facts 오탐: $c"; DF_FP=1; }
    done
    [ "$DF_FP" -eq 0 ] && pass "destructive-facts — 재생성 디렉토리 · 프로젝트 밖 · 변수 경로 · 비재귀 rm · 안전한 git 은 통과 (오탐 0)"
    # 세션 스크래치패드는 프로젝트 밖이라 묻지 않아요 — 프로젝트 루트 자체는 여전히 사실을 요구해요
    [ "$(df_rc 'cd /private/tmp/claude-502/-p/s/scratchpad/ios-dd && rm -rf Build Index.noindex; df -h /' sp1)" = 0 ] \
        && [ "$(df_rc "rm -rf $DF" sp2)" = 2 ] \
        && pass "destructive-facts — 스크래치패드(프로젝트 밖)는 통과 · 프로젝트 루트 자체는 차단" \
        || fail "destructive-facts — 스크래치패드/프로젝트 루트 판정이 틀려요"
    [ "$(df_rc 'git reset --hard' r1)" = 2 ] && [ "$(df_rc 'git reset --hard' r1)" = 0 ] \
        && pass "destructive-facts — 같은 명령 재시도는 통과 (사실을 적고 다시 온 것)" \
        || fail "destructive-facts — 재시도가 통과하지 않아요"
    DF_ERR=$(jq -nc --arg d "$DF" '{tool_input:{command:"git reset --hard"},cwd:$d}' \
        | CLAUDE_PROJECT_DIR="$DF" bash "$DF/.ax/hooks/pre-bash/destructive-facts.sh" 2>&1 >/dev/null); DF_RC=$?
    [ "$DF_RC" -eq 0 ] && printf '%s' "$DF_ERR" | grep -q '추적 불가' \
        && pass "destructive-facts — 세션 id 가 없으면 막지 않고 경고로 강등" \
        || fail "destructive-facts — 세션 id 없음 처리 (rc=$DF_RC): $DF_ERR"
    for k in 1 2 3; do df_rc "git stash clear $k" damp >/dev/null; done
    DF_4=$(jq -nc --arg d "$DF" '{tool_input:{command:"git stash clear 4"},session_id:"damp",cwd:$d}' \
        | CLAUDE_PROJECT_DIR="$DF" bash "$DF/.ax/hooks/pre-bash/destructive-facts.sh" 2>&1 >/dev/null)
    [ "$(printf '%s\n' "$DF_4" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$DF_4" | grep -q '(#4)' \
        && pass "destructive-facts — 4번째부터 한 줄 안내 (반복 루프 방지)" \
        || fail "destructive-facts — 4번째 차단 문구가 한 줄이 아니에요: $DF_4"
    printf 'sensors:\n  hook_profile: minimal\n' > "$DF/.ax/config.yml"
    [ "$(df_rc 'git reset --hard' p1)" = 0 ] && pass "destructive-facts — minimal 프로필에선 꺼져요" \
        || fail "destructive-facts — minimal 프로필에서도 돌아요"
    rm -rf "$DF"
else
    pass "§51 — jq/python3 없음, skip"
fi

# ───────────────────────────────────────────────────────────
section "52. rule-read-gate — 이 파일에 걸린 룰을 이번 세션에 Read 안 했으면 편집을 막아요"
# ───────────────────────────────────────────────────────────
# 실측(commerce): "hook 이 읽으라 지시한 commerce-application.md 를 건너뛰고" 금지된 suffix 를 썼어요.
# 경로 안내(B-pointer)는 건너뛸 수 있어서, 읽었다는 사실(Read 마커)로 판정해요.
if command -v jq >/dev/null 2>&1; then
    RG=$(mktemp -d)
    mkdir -p "$RG/.ax/scripts/bash" "$RG/.ax/hooks/pre-edit" "$RG/.ax/spirit/rules" "$RG/.ax/modules/pay" "$RG/.ax/modules/rev" "$RG/src/pay"
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$RG/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-edit/rule-read-gate.sh" "$RG/.ax/hooks/pre-edit/"
    printf -- '---\npaths:\n  - "src/**/*.kt"\n---\n## SP-APP-001: x\n' > "$RG/.ax/spirit/rules/app.md"
    printf -- '---\npaths: ["**/*.kt"]\n---\n## SP-UNI-001: x\n' > "$RG/.ax/spirit/rules/universal.md"
    printf -- '---\npaths:\n  - "src/pay/**"\napplies_to: [code]\n---\n## SP-PAY-001: y\n' > "$RG/.ax/modules/pay/rules.md"
    printf -- '---\npaths:\n  - "src/pay/**"\napplies_to: [pr]\n---\n## SP-REV-001: z\n' > "$RG/.ax/modules/rev/rules.md"
    printf '@.ax/spirit/rules/universal.md\n' > "$RG/AGENTS.md"
    rg_run() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' "$1" "$2" "${3:-s1}" \
        | CLAUDE_PROJECT_DIR="$RG" bash "$RG/.ax/hooks/pre-edit/rule-read-gate.sh"; }
    RG_ERR=$(rg_run Edit "$RG/src/pay/A.kt" 2>&1 >/dev/null); RG_RC=$?
    { [ "$RG_RC" -eq 2 ] && printf '%s' "$RG_ERR" | grep -q 'spirit/rules/app.md' && printf '%s' "$RG_ERR" | grep -q 'modules/pay/rules.md'; } \
        && pass "rule-read-gate — 안 읽은 spirit·module 룰을 나열하고 막아요" \
        || fail "rule-read-gate — 첫 편집 판정 (rc=$RG_RC): $RG_ERR"
    printf '%s' "$RG_ERR" | grep -q 'universal.md' \
        && fail "rule-read-gate — @import 된 룰까지 읽으라고 해요 (이미 컨텍스트에 있어요)" \
        || pass "rule-read-gate — CLAUDE.md/AGENTS.md 가 @import 한 룰은 빼요"
    printf '%s' "$RG_ERR" | grep -q 'modules/rev' \
        && fail "rule-read-gate — applies_to 에 code 가 없는 모듈 룰까지 요구해요" \
        || pass "rule-read-gate — applies_to: [pr] 모듈 룰은 편집 게이트 대상이 아니에요"
    rg_run Read "$RG/.ax/spirit/rules/app.md" >/dev/null 2>&1
    rg_run Read "$RG/.ax/modules/pay/rules.md" >/dev/null 2>&1
    rg_run Edit "$RG/src/pay/A.kt" >/dev/null 2>&1 && pass "rule-read-gate — 둘 다 Read 하면 통과" \
        || fail "rule-read-gate — Read 한 뒤에도 막아요"
    rg_run Edit "$RG/src/pay/A.kt" other >/dev/null 2>&1 \
        && fail "rule-read-gate — 다른 세션의 Read 가 새어 들어와요" \
        || pass "rule-read-gate — Read 기록은 세션 단위"
    rg_run Write "$RG/README.md" s9 >/dev/null 2>&1 && rg_run Edit "$RG/.ax/spirit/rules/app.md" s9 >/dev/null 2>&1 \
        && printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$RG/src/pay/A.kt" \
           | CLAUDE_PROJECT_DIR="$RG" bash "$RG/.ax/hooks/pre-edit/rule-read-gate.sh" >/dev/null 2>&1 \
        && pass "rule-read-gate — 매칭 룰 없는 파일 · .ax/ 편집 · 세션 id 없음은 통과" \
        || fail "rule-read-gate — 통과해야 할 경우를 막아요"
    printf 'sensors:\n  rule_gate_exempt: ["src/pay/**"]\n' > "$RG/.ax/config.yml"
    rg_run Edit "$RG/src/pay/A.kt" s8 >/dev/null 2>&1 && pass "rule-read-gate — sensors.rule_gate_exempt 글롭은 건너뛰어요" \
        || fail "rule-read-gate — rule_gate_exempt 가 안 먹어요"
    printf 'sensors:\n  hook_profile: minimal\n' > "$RG/.ax/config.yml"
    rg_run Edit "$RG/src/pay/A.kt" s8 >/dev/null 2>&1 && pass "rule-read-gate — minimal 프로필에선 꺼져요" \
        || fail "rule-read-gate — minimal 프로필에서도 돌아요"
    rm -f "$RG/.ax/config.yml"
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"},"session_id":"s7"}' "$RG/src/pay/A.kt" \
        | GOAX_DISABLED_HOOKS=x,rule-read-gate CLAUDE_PROJECT_DIR="$RG" bash "$RG/.ax/hooks/pre-edit/rule-read-gate.sh" >/dev/null 2>&1 \
        && pass "rule-read-gate — GOAX_DISABLED_HOOKS 로 세션 한정 끄기" \
        || fail "rule-read-gate — GOAX_DISABLED_HOOKS 가 안 먹어요"
    rm -rf "$RG"
else
    pass "§52 — jq 없음, skip"
fi
# 주입 훅과 게이트가 같은 매처를 써야 "주입은 했는데 게이트는 안 거는" 룰이 안 생겨요
grep -q 'goax_module_rules_matching' "$REPO/templates/default/.ax/hooks/pre-edit/module-rules-inject.sh" \
    && grep -q 'goax_module_rules_matching' "$REPO/templates/default/.ax/hooks/pre-edit/rule-read-gate.sh" \
    && ! grep -q 'goax_yaml_list "$rules" paths' "$REPO/templates/default/.ax/hooks/pre-edit/module-rules-inject.sh" \
    && pass "module 룰 매칭 — 주입 훅과 게이트가 같은 common.sh 함수" \
    || fail "module 룰 매칭이 주입 훅과 게이트에서 갈라졌어요"

# ───────────────────────────────────────────────────────────
section "53. 훅 프로필 · 끄기 — 모든 등록 훅이 goax_hook_enabled 를 거쳐요"
# ───────────────────────────────────────────────────────────
# 게이트를 켜는 순간 탈출구가 필요해요. 훅마다 ID(파일 이름) 로 끌 수 있어야 하고,
# minimal 프로필은 안전망만 남겨요. CATASTROPHIC 은 이 스위치 앞에서 끝나야 해요.
HP_MISS=0
for h in "$REPO"/templates/default/.ax/hooks/{session-start,pre-compact,user-prompt,pre-bash,pre-edit,post-edit,subagent-start,stop}/*.sh; do
    [ -f "$h" ] || continue
    id=$(basename "$h" .sh)
    grep -qE "goax_hook_enabled $id (minimal|standard)" "$h" || { fail "$(basename "$(dirname "$h")")/$id.sh — goax_hook_enabled $id 가 없어요"; HP_MISS=1; }
done
[ "$HP_MISS" -eq 0 ] && pass "등록 훅 전부 goax_hook_enabled <자기 ID> 를 거쳐요"
BD="$REPO/templates/default/.ax/hooks/pre-bash/block-destructive.sh"
CAT_LINE=$(grep -n 'CATASTROPHIC 명령 차단' "$BD" | head -1 | cut -d: -f1)
EN_LINE=$(grep -n 'goax_hook_enabled block-destructive' "$BD" | head -1 | cut -d: -f1)
[ -n "$CAT_LINE" ] && [ -n "$EN_LINE" ] && [ "$CAT_LINE" -lt "$EN_LINE" ] \
    && pass "block-destructive — CATASTROPHIC 차단이 끄기 스위치보다 앞 (끌 수 없는 안전망)" \
    || fail "block-destructive — CATASTROPHIC 이 끄기 스위치 뒤에 있어요 (cat=$CAT_LINE enable=$EN_LINE)"
grep -qE '^[[:space:]]+hook_profile:' "$REPO/templates/default/.ax/config.yml" \
    && grep -qE '^[[:space:]]+disabled_hooks:' "$REPO/templates/default/.ax/config.yml" \
    && grep -qE '^[[:space:]]+rule_gate_exempt:' "$REPO/templates/default/.ax/config.yml" \
    && pass "config.yml — sensors.hook_profile · disabled_hooks · rule_gate_exempt 출고" \
    || fail "config.yml 에 훅 프로필 키가 없어요"

# ───────────────────────────────────────────────────────────
section "54. session-brief — 세션 첫머리 알림은 스크립트가 정하고 훅은 전달만"
# ───────────────────────────────────────────────────────────
# 실측(commerce): 설치본 0.5.13 이 플러그인 0.6.3 에 머물고, mistakes 22건에 audit 은 139일 전.
if command -v jq >/dev/null 2>&1; then
    SB=$(mktemp -d)
    mkdir -p "$SB/.ax/scripts/bash" "$SB/.ax/hooks/session-start" "$SB/.ax/mistakes" "$SB/home/plugins"
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$REPO/templates/default/.ax/scripts/bash/session-brief.sh" "$SB/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/session-start/session-brief.sh" "$SB/.ax/hooks/session-start/"
    cp "$REPO/templates/default/.ax/current-task.json.template" "$SB/.ax/current-task.json"
    sb_brief() { CLAUDE_CONFIG_DIR="$SB/home" GOAX_PROJECT_DIR="$SB" bash "$SB/.ax/scripts/bash/session-brief.sh" "$@"; }
    sb_hook() { printf '{"session_id":"s","source":"startup"}' | CLAUDE_CONFIG_DIR="$SB/home" CLAUDE_PROJECT_DIR="$SB" bash "$SB/.ax/hooks/session-start/session-brief.sh"; }
    [ -z "$(sb_hook)" ] && pass "session-brief — 말할 게 없으면 아무것도 안 내요" || fail "session-brief — 빈 프로젝트에서 뭔가 출력해요: $(sb_hook)"
    printf 'goax: 0.5.13\n' > "$SB/.ax/version"
    printf '{"plugins":{"goax@goax":[{"version":"0.6.3"}]}}' > "$SB/home/plugins/installed_plugins.json"
    printf -- '---\nstatus: open\n---\n' > "$SB/.ax/mistakes/2026-07-01-1-a.md"
    printf -- '---\ncategory: x\n---\n' > "$SB/.ax/mistakes/2026-07-02-1-b.md"
    printf -- '---\nstatus: promoted\n---\n' > "$SB/.ax/mistakes/2026-07-03-1-c.md"
    printf '{"cross_cut":{"mistakes":{"last_audit":"2026-05-09"}}}' > "$SB/.ax/state.json"
    jq '.phase="implementing" | .task_id="t1" | .description="d" | .handoff.next=["n1","n2","n3","n4"]' \
        "$SB/.ax/current-task.json" > "$SB/ct" && mv "$SB/ct" "$SB/.ax/current-task.json"
    SBJ=$(sb_brief --json)
    [ "$(printf '%s' "$SBJ" | jq -r '.result.version.behind')" = true ] \
        && pass "session-brief — installed_plugins.json 기준 버전 지연 감지 (0.5.13 < 0.6.3)" \
        || fail "session-brief — 버전 지연을 못 봐요: $(printf '%s' "$SBJ" | jq -c .result.version)"
    [ "$(printf '%s' "$SBJ" | jq -r '.result.audit.unresolved')" = 2 ] && [ "$(printf '%s' "$SBJ" | jq -r '.result.audit.overdue')" = true ] \
        && pass "session-brief — 미처리 mistakes(open·status 없음) 2건 + 날짜만 적힌 last_audit 로 audit 지연 판정" \
        || fail "session-brief — audit 판정: $(printf '%s' "$SBJ" | jq -c .result.audit)"
    [ "$(printf '%s' "$SBJ" | jq -r '.result.handoff.next | length')" = 3 ] \
        && pass "session-brief — handoff next 는 앞 3개만" || fail "session-brief — handoff 자르기가 안 돼요"
    SBH=$(sb_hook)
    [ "$(printf '%s' "$SBH" | jq -r '.hookSpecificOutput.hookEventName')" = SessionStart ] \
        && printf '%s' "$SBH" | jq -r '.hookSpecificOutput.additionalContext' | grep -q '/up' \
        && pass "session-brief 훅 — SessionStart additionalContext 로 전달" \
        || fail "session-brief 훅 출력이 이상해요: $SBH"
    [ "$(sb_brief --max-chars 40 | tail -1 | grep -c '상한 40자')" = 1 ] \
        && pass "session-brief — 글자 상한을 넘으면 뒤를 잘라요" || fail "session-brief — 상한이 안 먹어요"
    printf 'sensors:\n  disabled_hooks: [session-brief]\n' > "$SB/.ax/config.yml"
    [ -z "$(sb_hook)" ] && pass "session-brief — disabled_hooks 로 끌 수 있어요" || fail "session-brief — disabled_hooks 가 안 먹어요"
    rm -rf "$SB"
else
    pass "§54 — jq 없음, skip"
fi
jq -e '.hooks.SessionStart' "$REPO/templates/default/.claude/settings.json.template" >/dev/null 2>&1 \
    && pass "settings.json.template — SessionStart 이벤트 등록" || fail "settings.json.template 에 SessionStart 가 없어요"

smoke_done
