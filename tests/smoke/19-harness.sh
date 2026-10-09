#!/usr/bin/env bash
# tests/smoke/19-harness.sh — §67–§70 — 실설치본 fixture · --json 일괄 계약 · zsh 함정 · agent_models
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/19-harness.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "67. fixture — 실제 설치본(fx_install) · 새 워크트리(fx_fresh_worktree) · 손복사 상한"
# ───────────────────────────────────────────────────────────
# 손으로 고른 .ax/ 위의 테스트가 설치본과 달라 거짓 양성을 냈어요 (0.7.11: update-state 자가 복구 · 룰 파일 위치).
# 새 테스트는 fx_install 로 쓰고, 손복사 fixture 는 지금 개수에서 더 늘지 못해요. 줄이면 상한도 같이 내려요.
HAND_FX_CAP=115
# 셉니다: 출고 원본(templates/default/.ax/ · $SCRIPTS_DIR)에서 fixture 로 cp 하는 줄
HAND_FX=$(cat "$REPO"/tests/smoke/*.sh | grep -cE 'cp( -[[:alpha:]]+)* "?\$(REPO/templates/default/\.ax/|\{?SCRIPTS_DIR)' || true)
if [ "$HAND_FX" -gt "$HAND_FX_CAP" ]; then
    fail "손복사 fixture ${HAND_FX}곳 — 상한 ${HAND_FX_CAP} 을 넘었어요. 새 테스트는 fx_install (tests/lib/harness.sh) 로 실제 설치본 위에서 써요"
elif [ "$HAND_FX" -lt "$HAND_FX_CAP" ]; then
    fail "손복사 fixture 가 ${HAND_FX}곳으로 줄었어요 — 19-harness.sh 의 HAND_FX_CAP 을 ${HAND_FX} 로 내려요 (래칫)"
else
    pass "손복사 fixture ${HAND_FX}곳 = 상한 ${HAND_FX_CAP} (더 늘지 않아요)"
fi

if fx_install FX_SRC --git; then
    FX_VER=$(sed -n 's/^goax:[[:space:]]*//p' "$FX_SRC/.ax/version" 2>/dev/null)
    [ "$FX_VER" = "$(cat "$REPO/VERSION")" ] && [ -z "$(git -C "$FX_SRC" status --porcelain 2>/dev/null)" ] \
        && pass "fx_install --git — provision.sh 설치본 · .ax/version = VERSION · 커밋까지 깨끗" \
        || fail "fx_install --git — version=${FX_VER:-?} · 미커밋 $(git -C "$FX_SRC" status --porcelain 2>/dev/null | wc -l | tr -d ' ')건"
    if fx_fresh_worktree FX_WT "$FX_SRC"; then
        FX_MISS=""
        for f in current-task.json state.json; do [ -e "$FX_SRC/.ax/$f" ] && [ ! -e "$FX_WT/.ax/$f" ] || FX_MISS="$FX_MISS $f"; done
        { [ -z "$FX_MISS" ] && [ -f "$FX_WT/.ax/current-task.json.template" ] && [ -f "$FX_WT/.ax/scripts/bash/common.sh" ]; } \
            && pass "fx_fresh_worktree — 원본엔 있는 런타임 상태가 새 워크트리엔 없고 설치본 나머지는 그대로" \
            || fail "fx_fresh_worktree — 새 워크트리 상태가 아니에요:${FX_MISS:- 템플릿·스크립트 없음}"
        rm -rf "$FX_WT"
    fi
    rm -rf "$FX_SRC"
fi

# ───────────────────────────────────────────────────────────
section "68. --json 계약 — 설치본의 모든 스크립트가 --json --dry-run 에 한 줄 JSON 을 내고 아무것도 안 써요"
# ───────────────────────────────────────────────────────────
# 모델은 stdout 을 jq 로 읽어요. 두 줄이 섞이거나(stdout 누수) 오류가 stderr 로만 가면(envelope 없음) 파싱이 깨지고,
# 라벨 문자열 속 \n 은 zsh echo 가 풀어 jq 를 깨요 (0.7.11 spec-review header). 인자 없이 부르면 대부분 오류인데,
# 오류도 envelope 한 줄이어야 해요. --dry-run 은 쓰는 스크립트가 아무것도 안 바꾸는지까지 봐요 (gitignore 대상 포함).
# 줄바꿈 허용 — 보고에 그대로 붙이는 내용 필드만:
JSON_NL_OK="zero-verify.sh:result.evidence"
if ! command -v jq >/dev/null 2>&1; then
    if [ -n "${CI:-}" ]; then fail "CI 에 jq 가 없어요 — §68 · §70 이 돌지 않아요"; else pass "jq 없음 — §68 · §70 은 건너뛰어요"; fi
fi
if command -v jq >/dev/null 2>&1 && fx_install JW --git; then
    JW_SUM=$(fx_tree_sum "$JW")
    jw_n=0; jw_bad=0
    # 두 번씩 — 그냥 부를 때, 그리고 파서가 --json 에 닿기 전에 오류가 날 때(모르는 옵션이 앞에)
    for s in "$JW"/.ax/scripts/bash/*.sh "$JW"/.ax/scripts/bash/*.sh; do
        n=$(basename "$s"); [ "$n" = common.sh ] && continue
        jw_n=$((jw_n + 1)); pre=""
        [ "$jw_n" -gt "$(( $(ls "$JW"/.ax/scripts/bash/*.sh | wc -l) - 1 ))" ] && { pre=--smoke-unknown-opt; n="$n (앞에 모르는 옵션)"; }
        out=$(cd "$JW" && GOAX_PROJECT_DIR="$JW" CLAUDE_PROJECT_DIR="$JW" fx_timeout 30 bash "$s" $pre --json --dry-run </dev/null 2>/dev/null); rc=$?
        lines=$(printf '%s' "$out" | awk 'END { print NR }')
        why=""
        if [ "$rc" -eq 142 ]; then why="30초 안에 안 끝나요"
        elif [ "$lines" != 1 ]; then why="stdout ${lines}줄 (exit $rc)"
        elif ! printf '%s\n' "$out" | jq -e 'type=="object" and (.status|IN("ok","warning","error","skipped")) and has("result") and has("next_step") and (.warnings|type)=="array" and (.errors|type)=="array"' >/dev/null 2>&1; then
            why="envelope 아님: $(printf '%s' "$out" | head -c 80)"
        else
            nl=$(printf '%s\n' "$out" | jq -r --arg n "${n%% *}" --arg ok "$JSON_NL_OK" \
                '[paths(type=="string") as $p | select(getpath($p) | test("\n")) | ($p | map(tostring) | join("."))
                  | select(($n + ":" + .) as $k | ($ok | split(" ") | index([$k])) == null)] | join(",")' 2>/dev/null)
            [ -n "$nl" ] && why="줄바꿈 든 문자열: $nl (줄 배열로)"
        fi
        if [ -n "$why" ]; then jw_bad=$((jw_bad + 1)); fail "$n --json --dry-run — $why"; fi
    done
    [ "$jw_n" -ge 80 ] && [ "$jw_bad" -eq 0 ] && pass "스크립트 $((jw_n / 2))개 × 2 (그냥 · 앞에 모르는 옵션) — --json --dry-run 이 전부 한 줄 envelope · 라벨에 줄바꿈 없음"
    [ "$jw_n" -lt 80 ] && fail "설치본 스크립트가 $((jw_n / 2))개뿐이에요 — 순회가 깨졌어요"
    # 인자 없이 부르면 대부분 인자 검사에서 끝나요 — 쓰기 경로의 dry-run 은 아래에서 인자를 줘서 따로 봐요
    [ "$(fx_tree_sum "$JW")" = "$JW_SUM" ] && pass "인자 없는 일괄 실행 뒤 설치본 파일 불변 (gitignore 대상 포함)" \
        || fail "--dry-run 이 파일을 바꿨어요: $(git -C "$JW" status --porcelain --ignored 2>/dev/null | head -5 | tr '\n' ' ')"

    # 쓰는 스크립트가 --dry-run 을 무시하고 쓰면 안 돼요 — 상태가 있는 설치본에서 대표 쓰기를 dry-run 으로
    GOAX_PROJECT_DIR="$JW" bash "$JW/.ax/scripts/bash/update-task.sh" --start --set task_id=jw1 --phase triaged --json >/dev/null 2>&1
    JW_SUM=$(fx_tree_sum "$JW")
    JW_W=0
    while IFS= read -r args; do
        [ -n "$args" ] || continue
        wo=$(cd "$JW" && export GOAX_PROJECT_DIR="$JW" && eval "bash .ax/scripts/bash/$args --json --dry-run" </dev/null 2>/dev/null)
        printf '%s\n' "$wo" | jq -e '.status=="ok" or .status=="skipped"' >/dev/null 2>&1 || { JW_W=$((JW_W + 1)); fail "dry-run 쓰기 경로가 ok 가 아니에요: $args — $(printf '%s' "$wo" | head -c 120)"; }
    done <<'ARGS'
reset-task.sh
update-state.sh
promote-mistake.sh --apply --token SP-X-001 --category x
update-task.sh --start --set task_id=jw2 --phase triaged
status-note.sh --add next "할 일"
config-set.sh commands.test "make test"
next-spec-num.sh --reserve --slug dry-x
init-mistake-file.sh --category ops --slug dry-y --severity low --detected-by self --source skill
zero-domain-risk.sh --set "payment=L3"
register-spirit-hook.sh
build-memory.sh
ARGS
    JR=$(cd "$JW" && GOAX_PROJECT_DIR="$JW" bash .ax/scripts/bash/reset-task.sh --json --dry-run 2>/dev/null)
    { [ "$(fx_tree_sum "$JW")" = "$JW_SUM" ] && printf '%s\n' "$JR" | jq -e '.result.dry_run==true and .result.task_id=="jw1" and .result.would_delete==".ax/tasks/jw1.json"' >/dev/null 2>&1; } \
        && [ "$JW_W" -eq 0 ] && pass "쓰는 스크립트 11종 — 실제 인자로 --dry-run 해도 ok 이고 진행 중 작업이 있는 설치본 파일 불변 (reset-task 는 지울 파일만 알려줘요)" \
        || fail "쓰는 스크립트 --dry-run 이 파일을 바꾸거나 계획이 틀려요: $(printf '%s' "$JR" | head -c 160)"
    rm -rf "$JW"
fi

# ───────────────────────────────────────────────────────────
section "69. zsh — SKILL.md·agents·commands·docs 의 bash 블록을 사용자 셸(zsh)로도 읽어요"
# ───────────────────────────────────────────────────────────
# 모델은 펜스 블록을 사용자 셸에서 그대로 돌려요 — 대개 zsh 예요. §30 은 bash -n 만 봐요.
# zsh -n 은 문법만 잡고, 문법은 맞는데 zsh 에서 뜻이 바뀌는 모양은 tests/lib/zsh-traps.awk 가 잡아요:
# `[ "$a" == b ]`·`echo ===` (EQUALS 확장 — "= not found") 와 `echo "$X" | jq` (\n 이 풀려 JSON 이 깨져요).
ZD=$(mktemp -d)
find "$REPO/skills" "$REPO/commands" "$REPO/agents" "$REPO/docs/reference" -name '*.md' 2>/dev/null | while IFS= read -r sf; do
    tag=$(printf '%s' "${sf#"$REPO"/}" | tr '/' '_')
    awk -v out="$ZD/$tag" 'BEGIN { i = 0 }
        /^[[:space:]]*```(bash|sh)[[:space:]]*$/ { inb = 1; i = i + 1; f = out "-" i ".sh"; next }
        /^[[:space:]]*```/ { inb = 0; next }
        inb { print >> f }' "$sf"
done
z_total=0; z_bad=0; z_trap=0
z_has=false; command -v zsh >/dev/null 2>&1 && z_has=true
for bf in "$ZD"/*.sh; do
    [ -f "$bf" ] || continue
    z_total=$((z_total + 1))
    if [ "$z_has" = true ] && ! zsh -n "$bf" 2>/dev/null; then
        z_bad=$((z_bad + 1)); fail "zsh -n 문법 오류: $(basename "$bf" .sh) — $(zsh -n "$bf" 2>&1 | head -1)"
    fi
    while IFS="$(printf '\t')" read -r ln why src; do
        [ -n "$ln" ] || continue
        z_trap=$((z_trap + 1)); fail "zsh 함정($why): $(basename "$bf" .sh):$ln — $src"
    done <<EOF
$(awk -f "$REPO/tests/lib/zsh-traps.awk" "$bf")
EOF
done
rm -rf "$ZD"
if [ "$z_total" -lt 50 ]; then
    fail "bash 블록이 ${z_total}개뿐이에요 — 추출이 깨졌어요"
elif [ "$z_has" != true ]; then
    # CI 는 zsh 를 깔아요 (.github/workflows/test.yml) — 거기서 빠지면 이 검사가 조용히 꺼져요
    if [ -n "${CI:-}" ]; then fail "CI 에 zsh 가 없어요 — workflow 에서 설치해요"; else pass "zsh 없음 — zsh -n 은 건너뛰고 함정 검사만 ($z_total 블록)"; fi
fi
[ "$z_has" = true ] && [ "$z_total" -ge 50 ] && [ "$z_bad" -eq 0 ] && pass "bash 블록 ${z_total}개 — zsh -n 문법 OK"
[ "$z_total" -ge 50 ] && [ "$z_trap" -eq 0 ] && pass "bash 블록 ${z_total}개 — zsh 함정(= 로 시작하는 단어 · echo \"\$X\" | jq) 없음"
# 검출기 자체 — 잡아야 할 것과 놓아줘야 할 것
ZT=$(printf '%s\n' '[ "$a" == b ] && echo ok' 'echo ===' 'R=$(echo "$J" | jq -r .x)' '[[ $a == b ]]' "echo '=='" 'X=$(cmd --a=b)' 'printf "%s\n" "$J" | jq .' 'echo "a==b"' \
    | awk -f "$REPO/tests/lib/zsh-traps.awk" | cut -f1 | paste -sd, -)
[ "$ZT" = "1,2,3" ] && pass "zsh-traps.awk — == · === · echo|jq 는 잡고 [[ == ]] · 따옴표 · --a=b · printf 는 놓아줘요" || fail "zsh-traps.awk 자기 점검 — 잡은 줄: ${ZT:-없음} (기대 1,2,3)"

# ───────────────────────────────────────────────────────────
section "70. agent_models — config.yml 로 에이전트 모델을 바꾸고, 띄우는 skill 은 그 값을 넘겨요"
# ───────────────────────────────────────────────────────────
# frontmatter model: 이 기본값이에요(0.7.11). 팀이 바꾸는 자리는 .ax/config.yml 의 agent_models 하나 — skill 이
# 띄우기 직전에 agent-model.sh 로 읽어 Agent 호출의 model 로 넘겨요 (#44).
AM_KNOWN=$(sed -n 's/^KNOWN="\(.*\)"$/\1/p' "$SCRIPTS_DIR/agent-model.sh" | tr ' ' '\n' | sort | paste -sd' ' -)
AM_AGENTS=$(find "$REPO/agents" -maxdepth 1 -name '*.md' -exec basename {} .md \; | sort | paste -sd' ' -)
[ -n "$AM_KNOWN" ] && [ "$AM_KNOWN" = "$AM_AGENTS" ] && pass "agent-model.sh 의 에이전트 목록 = agents/*.md ($AM_AGENTS)" \
    || fail "agent-model.sh KNOWN ($AM_KNOWN) ≠ agents/*.md ($AM_AGENTS)"
grep -qE '^agent_models:' "$REPO/templates/default/.ax/config.yml" && pass "config.yml 템플릿에 agent_models 블록" || fail "config.yml 템플릿에 agent_models 가 없어요"

if command -v jq >/dev/null 2>&1 && fx_install AM; then
    AMJ=$(GOAX_PROJECT_DIR="$AM" bash "$AM/.ax/scripts/bash/agent-model.sh" --all --json 2>/dev/null)
    printf '%s\n' "$AMJ" | jq -e '.status=="ok" and ([.result.models[]] | all(. == null)) and (.result.models | length) == 6' >/dev/null 2>&1 \
        && pass "갓 설치 — agent_models 가 주석뿐이라 6개 모두 null (에이전트 정의 기본값)" || fail "갓 설치 agent-model.sh --all: $(printf '%s' "$AMJ" | head -c 200)"
    awk '{ print } /^agent_models:/ { print "  evaluator: \"haiku\"   # 비용"; print "  architect: inherit"; print "  lane-worker: gpt4"; print "  archtect: opus"; print "  rules-auditor: opus sonnet" }' \
        "$AM/.ax/config.yml" > "$AM/.ax/config.yml.t" && mv "$AM/.ax/config.yml.t" "$AM/.ax/config.yml"
    AMJ=$(GOAX_PROJECT_DIR="$AM" bash "$AM/.ax/scripts/bash/agent-model.sh" evaluator architect lane-worker rules-auditor --json 2>/dev/null)
    printf '%s\n' "$AMJ" | jq -e '.status=="warning" and .result.models == {"evaluator":"haiku","architect":null,"lane-worker":null,"rules-auditor":null}
        and .result.sources.evaluator=="config" and .result.sources.architect=="default" and .result.sources["rules-auditor"]=="default"
        and (.warnings | length) == 4 and (.warnings | map(test("inherit|gpt4|archtect|opus sonnet")) | all)' >/dev/null 2>&1 \
        && pass "agent_models — 값은 넘기고 · inherit · 모를 값 · 두 단어 값 · 오타 이름은 경고 후 기본값" || fail "agent_models 해석: $(printf '%s' "$AMJ" | head -c 300)"
    sed 's/^agent_models:.*/agent_models: {evaluator: haiku}/' "$AM/.ax/config.yml" > "$AM/.ax/config.yml.t" && mv "$AM/.ax/config.yml.t" "$AM/.ax/config.yml"
    AMJ=$(GOAX_PROJECT_DIR="$AM" bash "$AM/.ax/scripts/bash/agent-model.sh" evaluator --json 2>/dev/null)
    printf '%s\n' "$AMJ" | jq -e '.status=="warning" and .result.models.evaluator==null and (.warnings | map(test("블록")) | any)' >/dev/null 2>&1 \
        && pass "agent_models: {…} 한 줄 형식 — 읽지 않고 경고해요 (조용히 기본값이 되지 않게)" || fail "agent_models 한 줄 형식: $(printf '%s' "$AMJ" | head -c 200)"
    AMJ=$(GOAX_PROJECT_DIR="$AM" bash "$AM/.ax/scripts/bash/agent-model.sh" evaluatr --json 2>/dev/null); am_rc=$?
    [ "$am_rc" -eq 1 ] && printf '%s\n' "$AMJ" | jq -e '.status=="error"' >/dev/null 2>&1 \
        && pass "agent-model.sh — 모르는 에이전트 이름을 물으면 exit 1 (envelope)" || fail "agent-model.sh 모르는 이름: exit=$am_rc $AMJ"
    rm -rf "$AM"
fi

# 띄우는 자리마다 모델 안내가 있어야 해요 — 없으면 config 를 바꿔도 그 에이전트엔 안 닿아요
AM_MISS=""
for sf in $(grep -rlE '`goax:(architect|evaluator|lane-scout|lane-worker|rules-auditor|screen-designer)`' "$REPO/skills" 2>/dev/null); do
    grep -qE '띄워|띄우' "$sf" || continue
    grep -q 'agent-model\.sh' "$sf" || AM_MISS="$AM_MISS ${sf#"$REPO"/}"
done
[ -z "$AM_MISS" ] && pass "goax 에이전트를 띄우는 skill 문서 전부 agent-model.sh 를 거쳐요" || fail "agent-model.sh 안내가 없는 스폰 문서:$AM_MISS"

smoke_done
