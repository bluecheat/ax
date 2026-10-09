#!/usr/bin/env bash
# tests/smoke/08-hook-reach.sh — §35–§37 — 훅 도달 범위 · 원장 동시성 · SDD 템플릿 파서
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/08-hook-reach.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "35. hook 도달 범위 — Stop 게이트 · SubagentStart 포인터 · 주입 중복 제거 · 이벤트 키 · 인계 기한 · .omc 잔재"
# ───────────────────────────────────────────────────────────
# 하네스가 메인 세션 안에서만 돌았어요. 서브에이전트는 Constitution 을 모른 채 떴고, 커밋 없이 턴이 끝나면
# 완료 게이트는 아무도 안 봤고, 같은 룰 포인터가 한 세션에 1,200회 들어갔어요 (실측). 셋 다 파일로 고정해요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§35 skip (jq 없음)"
else
    HX=$(mktemp -d)
    mkdir -p "$HX/.ax/scripts/bash" "$HX/.ax/hooks/stop" "$HX/.ax/hooks/subagent-start" "$HX/.ax/hooks/pre-edit" \
             "$HX/.ax/docs/spec/014-x" "$HX/.ax/spirit/rules" "$HX/.ax/modules/order" "$HX/.claude" "$HX/src"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,tasks-gate,tier-from-state,lanes-dispatch,status-note,doctor-scan,zero-ablation}.sh "$HX/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/stop/spec-gate.sh" "$HX/.ax/hooks/stop/"
    cp "$REPO/templates/default/.ax/hooks/subagent-start/harness-pointer.sh" "$HX/.ax/hooks/subagent-start/"
    cp "$REPO/templates/default/.ax/hooks/pre-edit/"{spirit-rules-inject,module-rules-inject}.sh "$HX/.ax/hooks/pre-edit/"
    cp "$REPO/templates/default/.ax/spirit/"{values,tone}.md "$HX/.ax/spirit/"
    printf '# Spec\n## 3.\n- [ ] **AC1** a\n' > "$HX/.ax/docs/spec/014-x/spec.md"
    printf '# tasks\n- [ ] T001 [AC1] do — files: src/A.kt\n' > "$HX/.ax/docs/spec/014-x/tasks.md"
    echo '{"phase":"implementing","spec_dir":".ax/docs/spec/014-x","size":"M","risk":"L1"}' > "$HX/.ax/current-task.json"
    printf '# X\n🔴 **`AX:CRITICAL:001`** — x\n' > "$HX/AGENTS.md"; printf '@AGENTS.md\n' > "$HX/CLAUDE.md"
    printf -- '---\ncategory: naming\npaths:\n  - "**/*.kt"\n---\n## SP-NAM-001: kebab\n' > "$HX/.ax/spirit/rules/naming.md"
    printf -- '---\nmodule: order\napplies_to: [code]\npaths:\n  - "src/**"\n---\n## SP-ORD-001: x\n' > "$HX/.ax/modules/order/rules.md"
    echo '{"hooks":{"PreToolUse":[]}}' > "$HX/.claude/settings.json"
    hx() { CLAUDE_PROJECT_DIR="$HX" bash "$HX/$1" 2>/dev/null; }
    STOP=.ax/hooks/stop/spec-gate.sh

    # Stop 게이트
    O=$(printf '{"session_id":"s1","hook_event_name":"Stop","stop_hook_active":false}' | hx $STOP)
    echo "$O" | jq -e '.decision=="block" and (.reason|test("status-note.sh"))' >/dev/null 2>&1 \
        && pass "stop 게이트 — implementing + 미완료 → decision:block, reason 에 인계 노트 명령" || fail "stop 게이트 — block 안 함: ${O:0:120}"
    [ -z "$(printf '{"session_id":"s1","stop_hook_active":true}' | hx $STOP)" ] \
        && pass "stop 게이트 — stop_hook_active=true (재시도) 면 통과 (무한 루프 없음)" || fail "stop 게이트 — 재시도를 또 잡음"
    for i in 1 2 3 4 5 6 7 8 9; do LAST=$(printf '{"session_id":"s2","stop_hook_active":false}' | hx $STOP); done
    [ -z "$LAST" ] && [ "$(cat "$HX/.ax/.session/s2/stop-blocks")" = "8" ] \
        && pass "stop 게이트 — 세션당 8회 상한 뒤 통과" || fail "stop 게이트 — 상한 없이 계속 잡음"
    CLAUDE_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/status-note.sh" --set now "spec 014-x 에서 멈춤 — T001" --json >/dev/null 2>&1
    [ -z "$(printf '{"session_id":"s3","stop_hook_active":false}' | hx $STOP)" ] \
        && pass "stop 게이트 — 인계 노트에 spec 이 적혀 있으면 통과 (멈추는 게 의도)" || fail "stop 게이트 — 인계 노트를 무시"
    CLAUDE_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/status-note.sh" --set now "" --json >/dev/null 2>&1
    jq -e '.handoff.now==[] and .handoff.now_at==null' "$HX/.ax/current-task.json" >/dev/null 2>&1 \
        && pass "status-note --set now \"\" — now 비움 + now_at null" || fail "status-note --set now \"\" — now/now_at 잔존: $(jq -c '.handoff|{now,now_at}' "$HX/.ax/current-task.json" 2>/dev/null)"
    echo '{"phase":"spec","spec_dir":".ax/docs/spec/014-x"}' > "$HX/.ax/current-task.json"
    [ -z "$(printf '{"session_id":"s4","stop_hook_active":false}' | hx $STOP)" ] \
        && pass "stop 게이트 — 계획 단계(phase=spec)엔 안 잡음" || fail "stop 게이트 — 계획 단계를 잡음"
    echo '{"phase":"implementing","spec_dir":".ax/docs/spec/014-x","size":"M","risk":"L1"}' > "$HX/.ax/current-task.json"
    printf 'sensors:\n  mode: off\n' > "$HX/.ax/config.yml"
    [ -z "$(printf '{"session_id":"s5","stop_hook_active":false}' | hx $STOP)" ] \
        && pass "stop 게이트 — sensors.mode=off 면 침묵" || fail "stop 게이트 — off 에서도 잡음"
    rm -f "$HX/.ax/config.yml"

    # SubagentStart 포인터
    O=$(printf '{"session_id":"s1","hook_event_name":"SubagentStart","agent_type":"Explore"}' | hx .ax/hooks/subagent-start/harness-pointer.sh)
    echo "$O" | jq -e '.hookSpecificOutput.hookEventName=="SubagentStart" and (.hookSpecificOutput.additionalContext|test("AGENTS.md") and test("values.md") and test("014-x"))' >/dev/null 2>&1 \
        && pass "subagent-start — Explore 에 Constitution·Spirit·현재 spec 경로 (hookEventName 중첩 OK)" || fail "subagent-start — 포인터 누락: ${O:0:120}"
    [ -z "$(printf '{"agent_type":"goax:evaluator"}' | hx .ax/hooks/subagent-start/harness-pointer.sh)" ] \
        && pass "subagent-start — goax 자기 에이전트는 건너뜀 (이미 spirit 선언)" || fail "subagent-start — 자기 에이전트에도 주입"
    echo "$O" | jq -e '(.hookSpecificOutput.additionalContext|length) < 600' >/dev/null 2>&1 \
        && pass "subagent-start — 경로만 (600자 미만, 본문 주입 아님)" || fail "subagent-start — 본문을 밀어 넣음"
    # 인계 노트 포인터 — handoff 에 항목이 있을 때만, 경로만 (명령은 싣지 않아요)
    CLAUDE_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/status-note.sh" --add open "q" --json >/dev/null 2>&1
    OH=$(printf '{"session_id":"s1","hook_event_name":"SubagentStart","agent_type":"Explore"}' | hx .ax/hooks/subagent-start/harness-pointer.sh)
    echo "$OH" | jq -e '.hookSpecificOutput.additionalContext | test("current-task.json") and test("handoff") and (test("status-note.sh")|not) and length < 600' >/dev/null 2>&1 \
        && pass "subagent-start — handoff 가 있으면 인계 노트 경로 한 줄 (명령 없음 · 600자 미만)" || fail "subagent-start — 인계 노트 포인터 불일치: ${OH:0:160}"
    CLAUDE_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/status-note.sh" --done open "q" --json >/dev/null 2>&1
    printf '{"session_id":"s1","hook_event_name":"SubagentStart","agent_type":"Explore"}' | hx .ax/hooks/subagent-start/harness-pointer.sh \
        | jq -e '.hookSpecificOutput.additionalContext | test("인계 노트") | not' >/dev/null 2>&1 \
        && pass "subagent-start — handoff 가 비면 인계 노트 줄 없음" || fail "subagent-start — 빈 handoff 에도 인계 노트 줄"

    # 주입 중복 제거
    J='{"session_id":"d1","tool_input":{"file_path":"'"$HX"'/src/A.kt"}}'
    O1=$(printf '%s' "$J" | hx .ax/hooks/pre-edit/spirit-rules-inject.sh); O2=$(printf '%s' "$J" | hx .ax/hooks/pre-edit/spirit-rules-inject.sh)
    echo "$O1" | jq -e '.hookSpecificOutput.additionalContext|test("naming.md")' >/dev/null 2>&1 && [ -z "$O2" ] \
        && pass "spirit-rules-inject — 같은 세션 두 번째는 침묵 (1,200회 실측의 원인 제거)" || fail "spirit-rules-inject — 중복 주입: [$O2]"
    [ -n "$(printf '{"session_id":"d2","tool_input":{"file_path":"'"$HX"'/src/A.kt"}}' | hx .ax/hooks/pre-edit/spirit-rules-inject.sh)" ] \
        && pass "spirit-rules-inject — 다른 세션은 다시 주입" || fail "spirit-rules-inject — 세션 경계를 넘어 억제"
    [ -n "$(printf '{"tool_input":{"file_path":"'"$HX"'/src/A.kt"}}' | hx .ax/hooks/pre-edit/spirit-rules-inject.sh)" ] \
        && pass "spirit-rules-inject — session_id 없으면 예전처럼 매번 (수동 실행 호환)" || fail "spirit-rules-inject — session_id 없을 때 침묵"
    M1=$(printf '%s' "$J" | hx .ax/hooks/pre-edit/module-rules-inject.sh); M2=$(printf '%s' "$J" | hx .ax/hooks/pre-edit/module-rules-inject.sh)
    echo "$M1" | jq -e '.hookSpecificOutput.additionalContext|test("Layer 2") and test("Layer 3")' >/dev/null 2>&1 && [ -z "$M2" ] \
        && pass "module-rules-inject — 모듈·spec 포인터도 세션당 한 번" || fail "module-rules-inject — 중복 주입: [$M2]"

    # doctor-scan — 이벤트 키 · 인계 노트 기한 · STATUS.md 잔재
    # 기한 줄은 writer 로 심어요 — 형식 보정까지 실사용과 같은 길을 타야 doctor 의 파싱이 실질이에요
    CLAUDE_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/status-note.sh" --add next "- [ ] 2020-01-01 룰 ablation 재검토" --json >/dev/null 2>&1
    CLAUDE_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/status-note.sh" --add next "- [ ] 2099-01-01 far" --json >/dev/null 2>&1
    DS=$(GOAX_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/doctor-scan.sh" --json --plugin-dir "$REPO" 2>/dev/null)
    echo "$DS" | jq -e '(.result.hooks.events.missing|index("Stop"))!=null and (.result.hooks.events.missing|index("SubagentStart"))!=null' >/dev/null 2>&1 \
        && pass "doctor-scan — settings.json 에 Stop·SubagentStart 키가 없으면 events.missing" || fail "doctor-scan — 이벤트 키 검사 없음"
    echo "$DS" | jq -e '.result.handoff.overdue==1 and .result.handoff.imminent==0 and .result.handoff.deadlines[0].status=="overdue"' >/dev/null 2>&1 \
        && pass "doctor-scan — 인계 노트 기한 초과 1 · 먼 기한은 ok (I3 규칙)" || fail "doctor-scan — 기한 판정 불일치: $(echo "$DS" | jq -c .result.handoff)"
    # 옛 인계 노트 파일이 남아 있으면 잔재로 알려요 — 자동 삭제·import 는 없어요
    mkdir -p "$HX/.ax/docs"; touch "$HX/.ax/docs/STATUS.md"
    DS2=$(GOAX_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/doctor-scan.sh" --json --plugin-dir "$REPO" 2>/dev/null)
    echo "$DS2" | jq -e --argjson before "$(echo "$DS" | jq '.result.findings // -1')" '.result.migration.stale_status_md==true and .result.findings==$before+1' >/dev/null 2>&1 \
        && pass "doctor-scan — .ax/docs/STATUS.md 잔재 → migration.stale_status_md · findings +1" \
        || fail "doctor-scan — STATUS.md 잔재 미검출: stale=$(echo "$DS2" | jq -r '.result.migration.stale_status_md') findings=$(echo "$DS" | jq -r .result.findings)→$(echo "$DS2" | jq -r .result.findings)"
    rm -f "$HX/.ax/docs/STATUS.md"
    GOAX_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/doctor-scan.sh" --json --plugin-dir "$REPO" 2>/dev/null | jq -e '.result.migration.stale_status_md==false' >/dev/null 2>&1 \
        && pass "doctor-scan — STATUS.md 없으면 stale_status_md false" || fail "doctor-scan — STATUS.md 없는데 잔재로 봄"

    # zero-ablation — 회차 기록 + 다음 기한
    GOAX_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/zero-ablation.sh" --off --json >/dev/null 2>&1
    AB=$(GOAX_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/zero-ablation.sh" --on --json 2>/dev/null)
    echo "$AB" | jq -e '.result.last_round!="" and .result.next_due!=""' >/dev/null 2>&1 \
        && jq -e '.handoff.next | any(test("^- \\[ \\] 20[0-9]{2}-[0-9]{2}-[0-9]{2} 룰 ablation 재검토"))' "$HX/.ax/current-task.json" >/dev/null 2>&1 \
        && jq -e '.handoff.next | any(test("2020-01-01 룰 ablation")) | not' "$HX/.ax/current-task.json" >/dev/null 2>&1 \
        && pass "zero-ablation --on — 회차 기록 + 다음 기한(+180일)을 인계 노트 체크박스로 (옛 기한은 제거)" || fail "zero-ablation — 회차/기한 기록 실패: $(echo "$AB" | jq -c .result) next=$(jq -c .handoff.next "$HX/.ax/current-task.json" 2>/dev/null)"

    # tier-from-state --reset — task 필드는 비우고 handoff 는 남겨요 (next·open·renamed 는 task 를 넘어 살아요).
    # HX 의 phase 는 아직 implementing 이라 idle 판정이 실질이에요 — 이 검사가 §35 의 마지막이어야 해요.
    CLAUDE_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/status-note.sh" --add next "살아남기" --json >/dev/null 2>&1
    GOAX_PROJECT_DIR="$HX" bash "$HX/.ax/scripts/bash/tier-from-state.sh" --reset --json >/dev/null 2>&1
    jq -e '.phase=="idle" and (.handoff.next|index("- 살아남기"))!=null' "$HX/.ax/current-task.json" >/dev/null 2>&1 \
        && pass "tier-from-state --reset — handoff 는 지우지 않아요" || fail "tier-from-state --reset — phase/handoff 불일치: $(jq -c '{phase,next:.handoff.next}' "$HX/.ax/current-task.json" 2>/dev/null)"
    rm -rf "$HX"
fi

# .omc 잔재 — plugin 디렉토리에서 세션을 열면 OMC 가 templates/ 안에 상태를 만들어요. tracked 되면 안 되고,
# 로컬 설치(cp -R)도 실어 나르면 안 돼요.
git -C "$REPO" ls-files templates | grep -q '/\.omc/' && fail "templates/ 안에 .omc/ 가 tracked 됨" || pass "templates/ — .omc/ tracked 파일 0"
grep -q "name .omc -prune" "$REPO/scripts/provision.sh" && pass "provision.sh — 복사 뒤 .omc 잔재 제거" || fail "provision.sh — .omc 잔재를 사용자 프로젝트로 실어 나름"
grep -q "not -path '\*/.omc/\*'" "$REPO/templates/default/.ax/scripts/bash/check-manifest-install.sh" && pass "check-manifest-install — .omc 열거 제외" || fail "check-manifest-install — .omc 를 출고분으로 셈"

# 엣지 연결 — 새 hook 이 template 에 등록돼야 doctor 도 사용자 설치도 따라가요
grep -q '"SubagentStart"' "$REPO/templates/default/.claude/settings.json.template" && grep -q '"Stop"' "$REPO/templates/default/.claude/settings.json.template" \
    && pass "settings.json.template — SubagentStart · Stop 이벤트 등록" || fail "settings.json.template — 새 이벤트 미등록"
grep -q 'events.missing' "$REPO/skills/doctor/SKILL.md" && grep -q 'handoff.deadlines' "$REPO/skills/doctor/SKILL.md" \
    && pass "doctor — 이벤트 키 · 인계 노트 기한을 실제로 읽음" || fail "doctor — 새 검사 결과를 안 읽음"
grep -q 'stale_status_md' "$REPO/skills/doctor/SKILL.md" \
    && pass "doctor — STATUS.md 잔재(stale_status_md)를 실제로 읽음" || fail "doctor — 잔재 통지 결과를 안 읽음"
grep -q 'goax_inject_fresh' "$REPO/templates/default/.ax/hooks/pre-edit/spirit-rules-inject.sh" && grep -q 'goax_inject_fresh' "$REPO/templates/default/.ax/hooks/pre-edit/module-rules-inject.sh" \
    && pass "주입 훅 둘 다 goax_inject_fresh 로 세션 dedupe" || fail "주입 훅 dedupe 누락"

# ───────────────────────────────────────────────────────────
section "36. 원장 동시성 — 두 레인이 같은 파일에 동시에 쓸 때"
# ───────────────────────────────────────────────────────────
# 코디네이터는 레인 보고를 **동시에** 받아요. `read → 바꿔서 tmp → mv` 는 원자적이지
# 않아서, 락이 없으면 뒤에 쓰는 쪽이 앞의 보고를 통째로 덮어써요. 실측(수정 전):
# `--report A` ‖ `--report B` 를 10회 돌리면 매회 8건 중 4건이 사라졌고, tasks-gate 를
# 두 spec 으로 동시에 돌리면 state.json 의 task_seal 키 하나가 유실됐어요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§36 skip (jq 없음)"
else
    CC=$(mktemp -d)
    mkdir -p "$CC"/.ax/scripts/bash "$CC"/.ax/docs/spec/030-a "$CC"/.ax/docs/spec/031-b
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,lanes-dispatch,tasks-gate,tier-from-state}.sh "$CC/.ax/scripts/bash/"
    echo '{}' > "$CC/.ax/state.json"; echo '{"phase":"idle"}' > "$CC/.ax/current-task.json"
    printf '## 3. \n- [ ] **AC1** a\n' > "$CC/.ax/docs/spec/030-a/spec.md"
    printf '## 3. \n- [ ] **AC1** b\n' > "$CC/.ax/docs/spec/031-b/spec.md"
    printf -- '- [x] T001 [AC1] z — files: z.kt\n' > "$CC/.ax/docs/spec/031-b/tasks.md"
    LEDGER="$CC/.ax/docs/spec/030-a/tasks.md"
    seed_ledger() {
        : > "$LEDGER"
        for i in 1 2 3 4; do printf -- '- [ ] T00%s [AC1] t%s — files: f%s.kt\n      레인: A\n      디스패치: 2026-01-01T00:00Z\n' "$i" "$i" "$i" >> "$LEDGER"; done
        for i in 5 6 7 8; do printf -- '- [ ] T00%s [AC1] t%s — files: f%s.kt\n      레인: B\n      디스패치: 2026-01-01T00:00Z\n' "$i" "$i" "$i" >> "$LEDGER"; done
    }

    lost_reports=0
    for i in 1 2 3 4 5 6 7 8 9 10; do
        seed_ledger
        GOAX_PROJECT_DIR="$CC" bash "$CC/.ax/scripts/bash/lanes-dispatch.sh" --spec 030-a --report A --json >/dev/null 2>&1 &
        GOAX_PROJECT_DIR="$CC" bash "$CC/.ax/scripts/bash/lanes-dispatch.sh" --spec 030-a --report B --json >/dev/null 2>&1 &
        wait
        [ "$(grep -c '^      보고:' "$LEDGER")" -eq 8 ] || lost_reports=$((lost_reports+1))
    done
    [ "$lost_reports" -eq 0 ] \
        && pass "lanes-dispatch --report — 두 레인 동시 보고 10회, 보고 8건 전부 보존" \
        || fail "lanes-dispatch --report — 동시 보고에서 유실 $lost_reports/10회 (락 없음)"

    echo '{}' > "$CC/.ax/state.json"
    seal_lost=0
    for i in 1 2 3 4 5; do
        GOAX_PROJECT_DIR="$CC" bash "$CC/.ax/scripts/bash/tasks-gate.sh" --spec 030-a --json >/dev/null 2>&1 &
        GOAX_PROJECT_DIR="$CC" bash "$CC/.ax/scripts/bash/tasks-gate.sh" --spec 031-b --json >/dev/null 2>&1 &
        wait
        [ "$(jq -r '.task_seal | keys | length' "$CC/.ax/state.json" 2>/dev/null)" = "2" ] || seal_lost=$((seal_lost+1))
    done
    [ "$seal_lost" -eq 0 ] \
        && pass "tasks-gate — 두 spec 동시 실행 5회, state.json task_seal 양쪽 보존" \
        || fail "tasks-gate — 동시 실행에서 task_seal 유실 $seal_lost/5회 (state.json 락 없음)"
    rm -rf "$CC"
fi

# ───────────────────────────────────────────────────────────
section "37. 출고 SDD 템플릿 ↔ 파서 — 코드펜스 예시를 실 task/마커로 세면 안 돼요"
# ───────────────────────────────────────────────────────────
# `_templates/spec/tasks.md` 의 "한 줄 형식" 예시는 코드펜스 안에 있는데, 파서 6개가
# 펜스를 몰라서 가짜 T001 을 실 task 로 셌어요 — 출고 템플릿을 그대로 복사한 spec 에서
# tasks-plan 이 T001 을 ready·blocked 양쪽에 넣고 tasks-gate total 이 하나 부풀었어요.
# spec.md 쪽은 반대 방향 — 안내문의 이름 언급을 마커로 세서 "성실히 채운 spec" 이
# 영원히 fail 이었어요. 둘 다 출고 파일 그대로로 고정해요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§37 skip (jq 없음)"
else
    TPL=$(mktemp -d)
    mkdir -p "$TPL"/.ax/scripts/bash "$TPL"/.ax/docs/spec/012-x
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,tasks-gate,tasks-plan,lanes-dispatch,lanes-hotfiles,check-spec-clarity,tier-from-state}.sh "$TPL/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/_templates/spec/tasks.md" "$TPL/.ax/docs/spec/012-x/tasks.md"
    cp "$REPO/templates/default/.ax/_templates/spec/spec.md"  "$TPL/.ax/docs/spec/012-x/spec.md"
    echo '{}' > "$TPL/.ax/state.json"; echo '{"phase":"idle"}' > "$TPL/.ax/current-task.json"
    tpl() { GOAX_PROJECT_DIR="$TPL" bash "$TPL/.ax/scripts/bash/$1" --spec 012-x "${@:2}" 2>/dev/null; }

    # 출고 tasks.md 의 실 task 는 T001~T004 (T004 는 [~] 보류) — 펜스 예시는 세면 안 돼요
    tpl tasks-gate.sh --json | jq -e '.result.total == 4 and .result.open == 3 and .result.paused == 1' >/dev/null 2>&1 \
        && pass "tasks-gate — 출고 tasks.md 그대로: total 4 (펜스 예시 미포함)" || fail "tasks-gate — 펜스 예시를 실 task 로 셈"
    tpl tasks-plan.sh --json | jq -e '.result.ready == ["T001","T002"] and .result.blocked == ["T003"]' >/dev/null 2>&1 \
        && pass "tasks-plan — 출고 tasks.md 그대로: ready/blocked 에 T001 중복 없음" || fail "tasks-plan — T001 이 ready·blocked 양쪽에 (펜스 예시)"
    tpl lanes-dispatch.sh --json | jq -e '.result.unassigned_open == ["T001","T002","T003"]' >/dev/null 2>&1 \
        && pass "lanes-dispatch --status — unassigned_open 에 T001 하나" || fail "lanes-dispatch — unassigned_open 에 T001 중복"
    tpl lanes-hotfiles.sh --json | jq -e '(.result.hot_files | length) == 0' >/dev/null 2>&1 \
        && pass "lanes-hotfiles — 출고 tasks.md 는 핫 파일 0 (펜스 경로 미수집)" || fail "lanes-hotfiles — 펜스 안 경로를 핫 파일로"
    # check-spec-clarity 의 진행률 분모는 `[x]`+`[ ]` 라 보류(T004)를 빼고 3 이에요.
    # 펜스를 세던 시절엔 4 였으니, 3 이 곧 회귀 고정이에요.
    tpl check-spec-clarity.sh --json | jq -e '.result.tasks_progress.total == 3 and .result.tasks_progress.open == 3' >/dev/null 2>&1 \
        && pass "check-spec-clarity — tasks 진행률 분모 3 (펜스 예시 제외 · [~] 보류 제외)" || fail "check-spec-clarity — 진행률에 펜스 예시 포함"

    # 성실히 채운 spec 은 통과해야 해요 — 안 그러면 게이트가 우회 대상이 돼요
    mkdir -p "$TPL/.ax/docs/spec/050-fill"
    FILLED="$TPL/.ax/docs/spec/050-fill/spec.md"
    # 산문에서 마커 *이름* 을 언급하는 줄이 핵심이에요 — 옛 정규식은 `**` 없이도 잡아서
    # 이 줄 하나로 "다 채운 spec" 이 영원히 fail 이었어요. 마커는 `**…**` 형식일 때만이에요.
    cat > "$FILLED" <<'FILLEOF'
# Spec — 리뷰 스코어

> NEEDS CLARIFICATION 항목은 §8 에서 전부 해소했어요.

## 1. 문제

### 1.1 한 줄 정의
리뷰 점수를 계산해 목록 API 로 노출해요.

## 2. 범위
- 포함: 점수 계산 · API 노출
- 제외: 캐시 계층

## 3. 성공 기준
- [ ] **AC1** 점수가 0~100 범위로 계산돼요
- [ ] **AC2** 목록 API 응답에 점수가 실려요

## 4. 사용자 시나리오
판매자가 상품 목록에서 자기 리뷰 점수를 봐요.
FILLEOF
    cp "$FILLED" "$TPL/filled.base"
    csc() { GOAX_PROJECT_DIR="$TPL" bash "$TPL/.ax/scripts/bash/check-spec-clarity.sh" --spec 050-fill --json 2>/dev/null; }
    csc >/dev/null 2>&1
    [ $? -eq 0 ] && csc | jq -e '.result.needs_clarification == 0 and .result.placeholders == 0 and .result.empty_sections == []' >/dev/null 2>&1 \
        && pass "check-spec-clarity — 성실히 채운 spec 은 exit 0 (안내문을 마커로 안 셈)" || fail "check-spec-clarity — 채운 spec 을 막음"
    printf '\n**NEEDS CLARIFICATION**: 점수 상한?\n' >> "$FILLED"
    csc >/dev/null 2>&1
    [ $? -eq 1 ] && csc | jq -e '.result.needs_clarification == 1' >/dev/null 2>&1 \
        && pass "check-spec-clarity — 진짜 마커 1개면 exit 1" || fail "check-spec-clarity — 마커를 못 잡음"
    cp "$TPL/filled.base" "$FILLED"; printf '\n담당: <이름>\n' >> "$FILLED"
    csc >/dev/null 2>&1
    [ $? -eq 1 ] && csc | jq -e '.result.placeholders == 1 and (.result.placeholder_lines|length)==1 and (.result.placeholder_lines[0]|test("^[0-9]+: 담당: <이름>$"))' >/dev/null 2>&1 \
        && pass "check-spec-clarity — placeholder 1개면 exit 1 + placeholder_lines 에 '줄번호: 본문'" || fail "check-spec-clarity — placeholder 를 못 잡거나 줄을 안 보여줌: $(csc | jq -c '.result|{placeholders,placeholder_lines}')"
    # 긴 한글 placeholder 줄 — 바이트로 자르면 한글이 반으로 갈려 JSON 이 깨지고 호출부의 jq 가 통째로 죽어요.
    # GNU cut -c 는 C·C.UTF-8 둘 다 바이트 단위라 리눅스에서만 터져요 (실측). 공용 clip() 은 낱말 경계라 안 깨져요.
    cp "$TPL/filled.base" "$FILLED"
    { printf '\n담당자와 승인 절차는'; for _i in $(seq 25); do printf ' 아직 정하지 않았어요'; done; printf ' <이름>\n'; } >> "$FILLED"
    CSC_OUT=$(csc)
    printf '%s' "$CSC_OUT" | jq -e '.result.placeholders == 1 and (.result.placeholder_lines[0] | length > 20)' >/dev/null 2>&1 \
        && printf '%s' "$CSC_OUT" | jq -r '.result.placeholder_lines[0]' | iconv -f utf-8 -t utf-8 >/dev/null 2>&1 \
        && pass "check-spec-clarity — 긴 한글 placeholder 줄도 JSON 이 안 깨짐 (바이트 절단 금지 · clip 낱말 경계)" \
        || fail "check-spec-clarity — 긴 한글 줄에서 JSON/UTF-8 깨짐: $(printf '%s' "$CSC_OUT" | head -c 160)"
    # 인라인 코드 `…` 안의 <패턴> 은 코드 인용이지 placeholder 가 아니에요 — 이 오탐 하나가 리뷰 라운드를 태웠어요
    cp "$TPL/filled.base" "$FILLED"; printf '\n- [ ] **AC3** `grep -E "<a|b>"` 가 0건이고 `<패턴>` 도 안 남아요\n' >> "$FILLED"
    csc >/dev/null 2>&1
    [ $? -eq 0 ] && csc | jq -e '.result.placeholders == 0' >/dev/null 2>&1 \
        && pass "check-spec-clarity — 인라인 코드 안의 <…> 는 placeholder 로 안 셈" || fail "check-spec-clarity — 인라인 코드 인용을 placeholder 로 오탐"
    rm -rf "$TPL"
fi

smoke_done
