#!/usr/bin/env bash
# tests/smoke/18-friction-worktree.sh — §65–§66 — 실사용 마찰 · 새 워크트리
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/18-friction-worktree.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

section "65. 실사용 마찰 다섯 — --next 의존 · 관례 위치 · 룰 대조 G7 · 후속 작업 · 합의 리뷰 승인"
# ───────────────────────────────────────────────────────────
SB="$REPO/templates/default/.ax/scripts/bash"
# (1) mark-task --next 는 `의존:` 을 봐요 — tasks-plan 과 같은 파서(goax_tasks_parse)
NX=$(mktemp -d); mkdir -p "$NX/.ax/scripts/bash" "$NX/.ax/docs/spec/2026-09-25-ab12-x"
cp "$SB/"{common,mark-task,tasks-plan}.sh "$NX/.ax/scripts/bash/"
NXF="$NX/.ax/docs/spec/2026-09-25-ab12-x/tasks.md"
cat > "$NXF" <<'NXE'
```
- [ ] T001 예시
```
- [x] T001 a
- [ ] T002 b
      의존: T003
- [~] T004 보류
- [ ] T003 c
      의존: T001, T041 (아직 없는 task)
- [ ] T005 d
      의존: T004 (보류)
NXE
nx() { (cd "$NX" && bash .ax/scripts/bash/mark-task.sh --spec 2026-09-25-ab12-x "$@" 2>/dev/null); }
nxp() { (cd "$NX" && bash .ax/scripts/bash/tasks-plan.sh --spec 2026-09-25-ab12-x --json 2>/dev/null); }
NX1=$(nx --next --json)
{ [ "$(printf '%s' "$NX1" | jq -r '.result.task')" = T005 ] && [ "$(printf '%s' "$NX1" | jq -c '.result.deps')" = '["T004"]' ] \
  && nxp | jq -e '.result.ready == ["T005"] and .result.blocked == ["T002","T003"]' >/dev/null; } \
    && pass "mark-task --next — 의존이 [ ] 인 T002·T003 을 건너뛰고 [~] 의존인 T005 를 골라요 (tasks-plan 과 같은 답)" \
    || fail "mark-task --next 의존 무시: $NX1 / plan $(nxp | jq -c .result)"
sed -i.bak 's/^- \[ \] T005/- [x] T005/' "$NXF" && rm -f "$NXF.bak"
NX2=$(nx --next --json); NXR=$?
{ [ "$NXR" = 0 ] && printf '%s' "$NX2" | jq -e '.status == "warning" and .result.task == null and .result.blocked == true
    and (.result.blocked_tasks | map(.task)) == ["T002","T003"]
    and (.result.blocked_tasks[1].unresolved == ["T041"]) and (.result.blocked_tasks[1].missing == ["T041"])' >/dev/null; } \
    && pass "mark-task --next — 미완료가 전부 막히면 warning · blocked_tasks · 풀리지 않은 의존(없는 ID 는 missing) — 완료로 안 읽혀요" \
    || fail "mark-task --next 전부 막힘 판정: rc=$NXR $NX2"
printf -- '- [ ] T009 e\n      의존: 결제 배포\n' >> "$NXF"
nxp | jq -e '.result.blocked | index("T009")' >/dev/null \
    && pass "goax_tasks_parse — T-ID 없는 의존 표기는 '의존 없음' 으로 풀리지 않아요" || fail "T-ID 없는 의존이 ready 로 풀렸어요"
printf -- '- [ ] T010 f\n      의존: 없음 (첫 task)\n- [ ] T011 g\n      의존: none — 독립\n- [ ] T012 h\n      의존: -\n' >> "$NXF"
nxp | jq -e '(.result.ready | index("T010") and index("T011") and index("T012")) and (.result.blocked | index("T009"))' >/dev/null \
    && pass "goax_tasks_parse — '없음 (설명)' · 'none — 설명' · '-' 은 의존 없음 (T-ID 없는 다른 표기만 막혀요)" \
    || fail "설명이 붙은 '없음' 이 막혔어요: $(nxp | jq -c .result)"
grep -q 'files: 목록과 레포 관례' "$REPO/skills/spec-implement/SKILL.md" && grep -q '같은 레이어 이웃을 grep' "$REPO/skills/spec-tasks/SKILL.md" \
  && grep -q '소유 목록과 레포 관례가 충돌' "$REPO/agents/lane-worker.md" && grep -q '소유 목록과 레포 관례가 충돌' "$REPO/skills/lane/SKILL.md" \
    && pass "관례 위치 — spec-tasks 이웃 grep · spec-implement 위임 브리프 · lane 브리프 · lane-worker 가 충돌 시 멈추고 보고" \
    || fail "files: 와 관례 위치 충돌 규칙이 spec-tasks · spec-implement · lane · lane-worker 중 어딘가에 없어요"
rm -rf "$NX"

# (3) 룰 대조 — rules-audit-scope 는 편집 훅과 같은 매칭, G7 은 G6 과 같은 필수 여부
RA=$(mktemp -d); mkdir -p "$RA/.ax/scripts/bash" "$RA/.ax/spirit/rules" "$RA/.ax/docs/spec/2026-09-25-cd34-y" "$RA/src/domain"
cp "$SB/"{common,rules-audit-scope,tasks-gate,tier-from-state}.sh "$RA/.ax/scripts/bash/"
printf -- '---\npaths:\n  - "**/*.kt"\n---\n## SP-NAME-001: 이름\n' > "$RA/.ax/spirit/rules/naming.md"
printf -- '---\npaths:\n  - "**/domain/**"\n---\n## SP-DOM-001: 도메인\n' > "$RA/.ax/spirit/rules/domain.md"
printf -- '---\ncategory: ops\n---\n## SP-OPS-001: 상시\n' > "$RA/.ax/spirit/rules/ops.md"
echo '# c' > "$RA/AGENTS.md"
git -C "$RA" init -q 2>/dev/null; git -C "$RA" add -A 2>/dev/null
git -C "$RA" -c user.email=a@b -c user.name=a commit -qm init 2>/dev/null
echo x > "$RA/src/domain/OrderProjection.kt"; echo y > "$RA/.ax/docs/spec/2026-09-25-cd34-y/note.md"
RAJ=$(GOAX_PROJECT_DIR="$RA" bash "$RA/.ax/scripts/bash/rules-audit-scope.sh" --spec cd34 --json 2>/dev/null)
printf '%s' "$RAJ" | jq -e '.result.files == [{"path":"src/domain/OrderProjection.kt","new":true,"rules":[".ax/spirit/rules/domain.md",".ax/spirit/rules/naming.md"]}]
    and .result.always == ["AGENTS.md",".ax/spirit/rules/ops.md"] and .result.new_files == ["src/domain/OrderProjection.kt"]
    and (.result.review_file | endswith("2026-09-25-cd34-y/review-rules.md"))' >/dev/null 2>&1 \
    && pass "rules-audit-scope — 변경 파일마다 걸린 룰 · 상시 룰(Constitution · paths 없는 룰) · 새 파일, .ax/** 는 빼요" \
    || fail "rules-audit-scope 범위: $RAJ"
cp "$REPO/templates/default/.ax/current-task.json.template" "$RA/.ax/current-task.json"; echo '{}' > "$RA/.ax/state.json"
jq '.task_id="W"|.phase="implementing"|.spec_dir=".ax/docs/spec/2026-09-25-cd34-y"|.size="L"|.risk="L2"' "$RA/.ax/current-task.json" > "$RA/ct" && mv "$RA/ct" "$RA/.ax/current-task.json"
RD="$RA/.ax/docs/spec/2026-09-25-cd34-y"
printf '## 3.\n- **AC1** a\n' > "$RD/spec.md"; printf -- '- [x] T001 [AC1] a — files: src/domain/OrderProjection.kt\n' > "$RD/tasks.md"
echo 'verdict: 진행' > "$RD/review.md"
rg() { GOAX_PROJECT_DIR="$RA" bash "$RA/.ax/scripts/bash/tasks-gate.sh" --spec cd34 --json 2>/dev/null; }
G7A=$(rg | jq -c '[.result.complete, .result.rules_review_required, .result.rules_review_verdict]')
echo 'verdict: 보강 필요' > "$RD/review-rules.md"; G7B=$(rg | jq -c '[.result.complete, .result.rules_review_verdict]')
echo 'verdict: 진행' > "$RD/review-rules.md"; G7C=$(rg | jq -c '[.result.complete]')
{ [ "$G7A" = '[false,true,null]' ] && [ "$G7B" = '[false,"보강 필요"]' ] && [ "$G7C" = '[true]' ]; } \
    && pass "tasks-gate G7 — 필수(L×L2)인데 review-rules.md 없거나 보강 필요면 미완료, 진행이면 완료" \
    || fail "tasks-gate G7: 없음=$G7A 보강=$G7B 진행=$G7C"
{ grep -q 'review-rules.md' "$REPO/agents/rules-auditor.md" && grep -q '^verdict: 진행 | 보강 필요' "$REPO/agents/rules-auditor.md" \
  && grep -q '시작 전 필수' "$REPO/agents/rules-auditor.md" && grep -q 'rules-auditor' "$REPO/agents/evaluator.md" \
  && grep -q '8.1.5 룰 대조' "$REPO/skills/spec-implement/SKILL.md" && grep -q 'rules-audit-scope.sh' "$REPO/skills/spec-implement/SKILL.md" \
  && grep -q 'rules-auditor' "$REPO/templates/default/.ax/hooks/subagent-start/harness-pointer.sh"; } \
    && pass "rules-auditor — review-rules.md 첫 줄 verdict · evaluator 는 관례 대조를 넘겨요 · spec-implement §8.1.5 · 포인터 훅 제외" \
    || fail "rules-auditor 배선이 빠졌어요 (agent · evaluator 하지 않는 것 · spec-implement §8.1.5 · harness-pointer)"
# 편집 훅은 경로와 함께 룰 제목도 줘요 (세션당 처음 매칭될 때만)
mkdir -p "$RA/.ax/hooks/pre-edit"; cp "$REPO/templates/default/.ax/hooks/pre-edit/spirit-rules-inject.sh" "$RA/.ax/hooks/pre-edit/"
RI=$(echo "{\"tool_input\":{\"file_path\":\"$RA/src/domain/OrderProjection.kt\"},\"session_id\":\"s65\"}" \
     | CLAUDE_PROJECT_DIR="$RA" bash "$RA/.ax/hooks/pre-edit/spirit-rules-inject.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext')
printf '%s' "$RI" | grep -q 'SP-DOM-001: 도메인' && printf '%s' "$RI" | grep -q 'SP-NAME-001: 이름' \
    && pass "spirit-rules-inject — 룰 파일 경로와 함께 룰 제목(SP-…: …)을 줘요" || fail "spirit-rules-inject 제목 누락: $RI"
rm -rf "$RA"

# (4) 끝난 spec 의 후속 작업 — --start --follow-up 이 spec_* 를 이어받아요
FU=$(mktemp -d); mkdir -p "$FU/.ax/scripts/bash" "$FU/.ax/docs/spec/2026-09-25-ef56-pay"
cp "$SB/"{common,update-task,tier-from-state,reset-task}.sh "$FU/.ax/scripts/bash/"
cp "$REPO/templates/default/.ax/current-task.json.template" "$FU/.ax/current-task.json"
echo s > "$FU/.ax/docs/spec/2026-09-25-ef56-pay/spec.md"; printf 'tier: full\n' > "$FU/.ax/docs/spec/2026-09-25-ef56-pay/.tier"
fu() { GOAX_PROJECT_DIR="$FU" bash "$FU/.ax/scripts/bash/update-task.sh" "$@" --json 2>/dev/null; }
fu --start --phase implementing --set task_id=A --set spec_dir=.ax/docs/spec/2026-09-25-ef56-pay >/dev/null
GOAX_PROJECT_DIR="$FU" bash "$FU/.ax/scripts/bash/reset-task.sh" --json >/dev/null 2>&1
FUA=$(fu --task A --activate | jq -r '.errors[0] // ""')
FUB=$(fu --follow-up ef56 --phase tasks | jq -r .status)
fu --start --follow-up ef56 --phase tasks --set task_id=B >/dev/null
{ printf '%s' "$FUA" | grep -q -- '--follow-up' && [ "$FUB" = error ] \
  && [ "$(jq -c '[.task_id,.phase,.spec_id,.spec_dir,.spec_tier,.intent_notes.follow_up_of]' "$FU/.ax/current-task.json")" \
       = '["B","tasks","2026-09-25-ef56",".ax/docs/spec/2026-09-25-ef56-pay","full","2026-09-25-ef56-pay"]' ] \
  && [ -f "$FU/.ax/tasks/B.json" ] && [ "$(fu --start --follow-up nope --set task_id=C | jq -r .status)" = error ]; } \
    && pass "update-task --start --follow-up — 닫힌 작업 대신 새 작업이 spec_id·spec_dir·spec_tier·follow_up_of 를 이어받아요 (--start 없이·없는 spec 은 거부)" \
    || fail "update-task --follow-up: activate=$FUA nostart=$FUB ct=$(jq -c . "$FU/.ax/current-task.json")"
grep -q -- '--follow-up' "$REPO/skills/triage/SKILL.md" && pass "triage — 끝난 spec 후속 작업 사용법 한 줄" || fail "triage 에 --follow-up 안내 없음"
rm -rf "$FU"

# (5) 합의 리뷰 상한 도달 뒤 사용자 승인 — --override 는 지금 sha 에 기록, --status 가 인정
OV=$(mktemp -d); mkdir -p "$OV/.ax/scripts/bash" "$OV/.ax/docs/spec/2026-09-25-aa11-z"
cp "$SB/"{common,spec-review,tier-from-state}.sh "$OV/.ax/scripts/bash/"
OD="$OV/.ax/docs/spec/2026-09-25-aa11-z"; echo 'v1' > "$OD/spec.md"; printf 'tier: full\n' > "$OD/.tier"
git -C "$OV" init -q 2>/dev/null; git -C "$OV" config user.name tester65
ov() { GOAX_PROJECT_DIR="$OV" bash "$OV/.ax/scripts/bash/spec-review.sh" --spec aa11 "$@" --json 2>/dev/null; }
ov_round() {   # 스냅샷 → 두 리뷰어 파일 (architect 보강 필요)
    local sha; sha=$(ov --snapshot | jq -r .result.sha)
    printf 'verdict: 보강 필요\nsha: %s\n' "$sha" > "$OD/review-spec.architect.md"
    printf 'verdict: 진행\nsha: %s\n' "$sha" > "$OD/review-spec.evaluator.md"
}
ov_round; echo v2 > "$OD/spec.md"; ov_round
OVE=$(ov --override --reason "x" | jq -r .status)      # 라운드 2/3 — 상한 전
echo v3 > "$OD/spec.md"; ov_round
OVN=$(ov --override | jq -r .status)                   # --reason 없음
echo 'v3 오타' > "$OD/spec.md"
ov --override --reason "남은 지적은 오타 — 사용자 진행 결정" --dry-run >/dev/null; OVDRY=$([ -f "$OD/review-override.md" ] && echo wrote || echo none)
ov --override --reason "남은 지적은 오타 — 사용자 진행 결정" >/dev/null
OVS=$(ov --status | jq -c '[.result.pass, .result.override.applied, .result.override.by]')
echo v4 > "$OD/spec.md"; OVS2=$(ov --status | jq -c '[.result.pass, .result.override.applied]')
{ [ "$OVE" = error ] && [ "$OVN" = error ] && [ "$OVDRY" = none ] && [ "$OVS" = '[true,true,"tester65"]' ] && [ "$OVS2" = '[false,false]' ] \
  && grep -q '^reason: 남은 지적은 오타' "$OD/review-override.md" && grep -q '^at: ' "$OD/review-override.md"; } \
    && pass "spec-review --override — 상한 전·사유 없음은 거부, dry-run 무기록, 지금 sha 에만 pass (누가·언제·사유), 본문이 바뀌면 풀려요" \
    || fail "spec-review --override: 상한전=$OVE 사유없음=$OVN dry=$OVDRY status=$OVS 변경후=$OVS2"
grep -q -- '--override --reason' "$REPO/skills/spec-validate/SKILL.md" && pass "spec-validate — 상한 절에 --override 사용법" || fail "spec-validate 상한 절에 --override 없음"
rm -rf "$OV"

section "66. 새 워크트리 — 실제 설치본에서 런타임 상태 파일 없이 흐름이 이어지고, --json 은 zsh echo 로 받아도 깨지지 않아요"
# ───────────────────────────────────────────────────────────
# current-task.json · state.json 은 gitignore 대상이라 git worktree 를 새로 뜨면 없어요. 예전엔 쓰는 스크립트가
# "/up 으로 설치를 마쳐요" 로 거부해 워크트리마다 /up 이 필요했어요 (commerce 워크트리 3곳 실측, 2026-10-09).
# fixture 는 provision.sh 로 깐 설치본을 커밋하고 `git worktree add` 로 뜬 진짜 새 워크트리예요 — 손으로 만든 .ax/ 는
# 설치본과 달라 이 결함을 못 잡았어요. 검사 사이엔 `git clean -X` 로 gitignore 대상만 지워 다시 새 워크트리로 돌려요.
if command -v jq >/dev/null 2>&1 && fx_install WT_SRC --git && fx_fresh_worktree WT "$WT_SRC"; then
    WB="$WT/.ax/scripts/bash"
    wt_fresh() { git -C "$WT" clean -fdXq >/dev/null 2>&1; }
    { [ ! -e "$WT/.ax/current-task.json" ] && [ ! -e "$WT/.ax/state.json" ] && [ -f "$WB/update-task.sh" ]; } \
        && pass "새 워크트리 — 스크립트는 있고 gitignore 된 상태 파일 둘은 없어요 (fx_fresh_worktree)" || fail "fx_fresh_worktree 가 새 워크트리 상태가 아니에요"
    { [ -f "$WT/.ax/current-task.json.template" ] && [ -f "$WT/.ax/hud/state.json.template" ]; } \
        && pass "설치본 — 런타임 상태 템플릿 두 개가 .ax/ 안에 있어요" || fail "설치본에 current-task.json.template · hud/state.json.template 이 없어요 (MANIFEST)"

    wt_fresh
    WTO=$(GOAX_PROJECT_DIR="$WT" bash "$WB/update-task.sh" --start --phase triaged --set task_id=t1 --set size=M --json 2>/dev/null | jq -r .status)
    { [ "$WTO" = ok ] && jq -e '.task_id=="t1" and .phase=="triaged" and (.handoff|type)=="object"' "$WT/.ax/current-task.json" >/dev/null 2>&1 \
      && [ -f "$WT/.ax/tasks/t1.json" ]; } \
        && pass "update-task --start — current-task.json 이 없어도 템플릿으로 만들고 작업을 열어요" || fail "update-task --start 새 워크트리 실패: status=$WTO"

    wt_fresh
    WTO=$(GOAX_PROJECT_DIR="$WT" bash "$WB/status-note.sh" --add next "다음 할 일" --json 2>/dev/null | jq -r .status)
    { [ "$WTO" = ok ] && jq -e '.handoff.next==["- 다음 할 일"] and .phase=="idle"' "$WT/.ax/current-task.json" >/dev/null 2>&1; } \
        && pass "status-note --add — 파일이 없으면 템플릿 전체로 만들고 추가해요" || fail "status-note 새 워크트리 실패: status=$WTO"

    wt_fresh
    WTO=$(GOAX_PROJECT_DIR="$WT" bash "$WB/tier-from-state.sh" --reset --json 2>/dev/null | jq -r .status)
    { [ "$WTO" = ok ] && jq -e '.phase=="idle"' "$WT/.ax/current-task.json" >/dev/null 2>&1; } \
        && pass "tier-from-state --reset — 파일이 없어도 idle 로 끝나요" || fail "tier-from-state --reset 새 워크트리 실패: status=$WTO"

    wt_fresh
    WTO=$(GOAX_PROJECT_DIR="$WT" bash "$WB/update-task.sh" --phase spec --dry-run --json 2>/dev/null | jq -r .status)
    { [ "$WTO" = ok ] && [ ! -f "$WT/.ax/current-task.json" ]; } \
        && pass "update-task --dry-run — 파일이 없으면 템플릿으로 따지고 아무것도 안 만들어요" || fail "update-task --dry-run 새 워크트리: status=$WTO · 파일 생김=$([ -f "$WT/.ax/current-task.json" ] && echo yes || echo no)"

    # 동시에 다섯 세션이 처음 쓸 때 — 누가 먼저 만들든 다른 쪽을 덮지 않아요
    wt_fresh; rm -rf "$WT/.ax/tasks"
    for n in 1 2 3 4 5; do
        GOAX_PROJECT_DIR="$WT" bash "$WB/status-note.sh" --add open "질문 $n" --json >/dev/null 2>&1 &
    done; wait
    WTN=$(jq -r '.handoff.open | length' "$WT/.ax/current-task.json" 2>/dev/null)
    [ "$WTN" = 5 ] && pass "동시 첫 쓰기 5개 — 파일 하나, 항목 5개 그대로 (seed 가 서로를 덮지 않아요)" || fail "동시 첫 쓰기 — open 항목 ${WTN:-?}/5"

    wt_fresh; rm -f "$WT/.ax/current-task.json.template"
    WTE=$(GOAX_PROJECT_DIR="$WT" bash "$WB/update-task.sh" --start --set task_id=t9 --json 2>/dev/null | jq -r '.errors[0] // ""')
    { [ ! -f "$WT/.ax/current-task.json" ] && printf '%s' "$WTE" | grep -q '/up'; } \
        && pass "템플릿까지 없는 옛 설치본 — 그때만 /up 을 안내하고 파일을 만들지 않아요" || fail "템플릿 없는 설치본: $WTE"

    # --json 출력은 사용자 셸(zsh)의 echo 로 받아도 jq 가 읽어야 해요 — zsh echo 는 문자열 속 \n 을 진짜 줄바꿈으로 바꿔요
    wt_fresh
    SR=$(cd "$WT" && GOAX_PROJECT_DIR="$WT" bash "$WB/next-spec-num.sh" --reserve --slug zsh-echo --json 2>/dev/null | jq -r '.result.next')
    cp "$WT/.ax/_templates/spec/spec.md" "$WT/.ax/docs/spec/$SR-zsh-echo/spec.md" 2>/dev/null
    SNAP=$(cd "$WT" && GOAX_PROJECT_DIR="$WT" bash "$WB/spec-review.sh" --spec "$SR" --snapshot --json 2>/dev/null)
    SNL=$(printf '%s\n' "$SNAP" | jq -r '[.. | strings | select(test("\n"))] | length' 2>/dev/null)
    [ "$SNL" = 0 ] && pass "spec-review --snapshot — 응답 문자열에 줄바꿈이 없어요 (header 는 줄 배열)" || fail "spec-review --snapshot — 줄바꿈 든 문자열 ${SNL:-?}개"
    if command -v zsh >/dev/null 2>&1; then
        ZR=$(SNAP="$SNAP" zsh -c 'echo "$SNAP" | jq -r .result.round' 2>/dev/null)
        [ "$ZR" = 1 ] && pass "spec-review --snapshot — zsh echo 로 넘겨도 jq 가 읽어요" || fail "spec-review --snapshot — zsh echo 를 거치면 jq 가 못 읽어요 (round=${ZR:-parse error})"
    fi
    unset -f wt_fresh
    rm -rf "$WT" "$WT_SRC"
fi

# 모델이 따라 쓰는 예시라 zsh 에서 깨지는 모양은 문서에도 두지 않아요 — printf '%s\n' "$X" | jq 로 써요
ECHO_JQ=$(cd "$REPO" && grep -rnE 'echo "\$[A-Za-z_][A-Za-z_0-9]*" *\| *jq' skills agents commands docs 2>/dev/null | head -5)
[ -z "$ECHO_JQ" ] && pass "skills·agents·commands·docs — echo \"\$X\" | jq 없음 (zsh 에서 \\n 이 풀려요)" || fail "echo \"\$X\" | jq 가 남아 있어요: $ECHO_JQ"

smoke_done
