#!/usr/bin/env bash
# tests/smoke/06-spec-review.sh — §33 — spec-review 합의 리뷰 원장
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/06-spec-review.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "33. spec-review — 합의 리뷰 원장 (리뷰어별 파일 · sha 고정 · Size 축)"
# ───────────────────────────────────────────────────────────
# 한 파일에 둘이 쓰면 첫 줄 verdict 로 "둘 다 진행" 을 못 담고 뒤에 쓰는 쪽이 앞 절을 읽어요.
# 그래서 리뷰어별 파일이고, 스크립트가 집계해요. 필수 여부는 Size 축만 (L/XL 필수 · M 선택 · S 없음).
SR=$(mktemp -d)
mkdir -p "$SR/.ax/scripts/bash" "$SR/.ax/docs/spec/014-x"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,spec-review,tier-from-state}.sh "$SR/.ax/scripts/bash/"
printf '# Spec\n## 3.\n- [ ] **AC1** a\n' > "$SR/.ax/docs/spec/014-x/spec.md"
echo '{"phase":"spec","spec_dir":".ax/docs/spec/014-x","size":"L","risk":"L1"}' > "$SR/.ax/current-task.json"
sr() { GOAX_PROJECT_DIR="$SR" bash "$SR/.ax/scripts/bash/spec-review.sh" --spec 014-x "$@" 2>/dev/null; }

sr_matrix_bad=0
for sz in S:none M:optional L:required XL:required; do
    got=$(GOAX_PROJECT_DIR="$SR" bash "$SR/.ax/scripts/bash/tier-from-state.sh" --json --size "${sz%%:*}" --risk L2 2>/dev/null | jq -r '.result.spec_review')
    [ "$got" = "${sz##*:}" ] || { fail "tier-from-state spec_review — ${sz%%:*} 가 $got (기대 ${sz##*:})"; sr_matrix_bad=$((sr_matrix_bad+1)); }
done
# 루프 결과로 게이팅 — 무조건 pass 면 위 fail 을 초록이 덮어요
[ "$sr_matrix_bad" -eq 0 ] \
    && pass "tier-from-state — spec_review 는 Size 축만 (S none · M optional · L/XL required)" \
    || fail "tier-from-state — spec_review 매트릭스 $sr_matrix_bad 셀 불일치"

sr --status --json | jq -e '.result.required=="required" and .result.pass==false' >/dev/null 2>&1 \
    && pass "spec-review — L 은 리뷰 파일 없으면 미통과" || fail "spec-review — 필수인데 빈 상태를 통과시킴"
SHA=$(sr --snapshot --json | jq -r '.result.sha')
[ "$(sr --status --json | jq -r '.result.round')" = "1" ] && pass "spec-review --snapshot — round 1, sha 고정" || fail "spec-review --snapshot 라운드 기록 실패"
printf 'verdict: 진행\nsha: %s\n' "$SHA" > "$SR/.ax/docs/spec/014-x/review-spec.architect.md"
printf 'verdict: 보강 필요\nsha: %s\n' "$SHA" > "$SR/.ax/docs/spec/014-x/review-spec.evaluator.md"
sr --status --json | jq -e '.result.pass==false and .result.evaluator.verdict=="보강 필요"' >/dev/null 2>&1 \
    && pass "spec-review — 한쪽이 보강 필요면 미통과" || fail "spec-review — 보강 필요를 통과시킴"
printf 'verdict: 진행\nsha: %s\n' "$SHA" > "$SR/.ax/docs/spec/014-x/review-spec.evaluator.md"
sr --status --json | jq -e '.result.pass==true' >/dev/null 2>&1 \
    && pass "spec-review — 둘 다 진행 + sha 일치 → 통과" || fail "spec-review — 정상 합의를 미통과로 봄"
printf -- '- [ ] **AC2** b\n' >> "$SR/.ax/docs/spec/014-x/spec.md"
sr --status --json | jq -e '.result.pass==false and .result.architect.sha_match==false' >/dev/null 2>&1 \
    && pass "spec-review — 리뷰 뒤 spec 변경 → sha 불일치로 미통과" || fail "spec-review — sha 불일치를 못 잡음"
sr --merge --json >/dev/null 2>&1; [ -f "$SR/.ax/docs/spec/014-x/review-spec.md" ] \
    && pass "spec-review --merge — 합본 생성" || fail "spec-review --merge 실패"
echo '{"phase":"spec","spec_dir":".ax/docs/spec/014-x","size":"M","risk":"L3"}' > "$SR/.ax/current-task.json"
rm -f "$SR/.ax/docs/spec/014-x"/review-spec.*.md
sr --status --json | jq -e '.result.required=="optional" and .result.pass==true' >/dev/null 2>&1 \
    && pass "spec-review — M 은 리뷰 없으면 선택 통과 (risk 는 안 봄)" || fail "spec-review — M×L3 에 필수를 강제함"

# 라운드는 리뷰어가 실제로 본 횟수예요 — --snapshot 을 부를 때마다 오르면 오타 한 번에 상한이 타요.
# 같은 sha 는 재사용, 아무도 안 본 스냅샷은 교체, 누가 본 뒤에야 +1. 그리고 통과 뒤 오타는 --fixup,
# 재리뷰 브리프는 --delta, tasks.md 가 생기면 --stage tasks 로 짧은 라운드(상한 2)를 따로 세요.
mkdir -p "$SR/.ax/docs/spec/015-y"
printf '# Spec\n## 3.\n- [ ] **AC1** a\n' > "$SR/.ax/docs/spec/015-y/spec.md"
echo '{"phase":"spec","spec_dir":".ax/docs/spec/015-y","size":"L","risk":"L1"}' > "$SR/.ax/current-task.json"
sy() { GOAX_PROJECT_DIR="$SR" bash "$SR/.ax/scripts/bash/spec-review.sh" --spec 015-y "$@" 2>/dev/null; }
SY="$SR/.ax/docs/spec/015-y"
sy_review() {  # 두 리뷰어가 지금 sha 로 봤다고 적어요 — $1 = architect verdict, $2 = evaluator verdict
    local sha; sha=$(sy --status --json | jq -r '.result.sha')
    printf 'verdict: %s\nsha: %s\n' "$1" "$sha" > "$SY/review-spec.architect.md"
    printf 'verdict: %s\nsha: %s\n' "$2" "$sha" > "$SY/review-spec.evaluator.md"
}
sy --snapshot --json | jq -e '.result.round==1 and .result.stage=="spec" and .result.max_rounds==3 and .result.reused==false' >/dev/null 2>&1 \
    && sy --snapshot --json | jq -e '.result.round==1 and .result.reused==true' >/dev/null 2>&1 \
    && pass "spec-review --snapshot — 같은 sha 를 다시 찍어도 라운드 그대로 (reused)" || fail "spec-review --snapshot — 같은 sha 에 라운드가 오름"
printf 'typo-before-review\n' >> "$SY/spec.md"
sy --snapshot --json | jq -e '.result.round==1 and .result.replaced==true' >/dev/null 2>&1 \
    && pass "spec-review --snapshot — 아무도 안 본 스냅샷은 바꿔 끼움 (replaced · 라운드 유지)" || fail "spec-review --snapshot — 안 본 스냅샷을 새 라운드로 셈"
# 아직 아무도 안 봤으면 base 는 snapshot 이고, 방금 찍은 본문과 같으니 0줄이어야 해요.
# base 이름표를 디렉토리 이름으로 쓰면 없는 경로와 비교해 "전부 바뀜" 이 나와요 (1 라운드 자리에서 실제로 그랬어요).
sy --delta --json | jq -e '.result.base=="snapshot" and .result.changed_lines==0' >/dev/null 2>&1 \
    && pass "spec-review --delta — 리뷰 전(base=snapshot)엔 방금 찍은 본문 대비 0줄 (이름표를 경로로 쓰지 않음)" || fail "spec-review --delta — base=snapshot 이 전부 바뀐 걸로 나옴: $(sy --delta --json | jq -c '.result|{base,changed_lines}')"
sy_review "보강 필요" "진행"
printf 'after-round-1\n' >> "$SY/spec.md"
sy --snapshot --json | jq -e '.result.round==2 and .result.replaced==false and .result.reused==false' >/dev/null 2>&1 \
    && [ -f "$SY/.review-snapshot/reviewed/spec.md" ] && grep -q 'typo-before-review' "$SY/.review-snapshot/reviewed/spec.md" \
    && ! grep -q 'after-round-1' "$SY/.review-snapshot/reviewed/spec.md" \
    && pass "spec-review --snapshot — 누가 본 뒤에만 +1 · 본 본문은 .review-snapshot/reviewed/ 에 남음" || fail "spec-review --snapshot — 리뷰 뒤 라운드/보관 불일치: $(cat "$SY/.review-round" 2>/dev/null)"
DL=$(sy --delta --json)
echo "$DL" | jq -e '.result.base=="reviewed" and .result.changed_lines==1 and ([.result.files[]|select(.file=="spec.md")][0].changed_lines==1) and (.result.diff|test("\\+after-round-1"))' >/dev/null 2>&1 \
    && [ -f "$(echo "$DL" | jq -r '.result.delta_file')" ] \
    && pass "spec-review --delta — 리뷰어가 본 본문 대비 diff (줄 수 · 파일별 · delta_file)" || fail "spec-review --delta — diff 불일치: $(echo "$DL" | jq -c '.result|{base,changed_lines,files}')"
sy_review "진행" "진행"
sy --status --json | jq -e '.result.pass==true' >/dev/null 2>&1 || fail "spec-review — 라운드 2 통과가 안 됨 (fixup 검사 전제)"
sy --fixup --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "spec-review --fixup — 본문이 리뷰된 그대로면 거부 (exit 1)" || fail "spec-review --fixup — 바뀐 게 없는데 받음"
printf 'typo-after-pass\n' >> "$SY/spec.md"
sy --status --json | jq -e '.result.pass==false and (.result.reason|test("fixup"))' >/dev/null 2>&1 \
    && pass "spec-review --status — 통과 뒤 편집은 미통과 + --fixup 안내" || fail "spec-review --status — 통과 뒤 편집을 안 잡거나 fixup 안내 없음"
FX=$(sy --fixup --json)
echo "$FX" | jq -e '.status=="ok" and .result.changed_lines==1 and .result.reviewed_sha!=.result.accepted_sha' >/dev/null 2>&1 \
    && sy --status --json | jq -e '.result.pass==true and .result.fixup.applied==true' >/dev/null 2>&1 \
    && sy --snapshot --json | jq -e '.result.reused==true and .result.round==2' >/dev/null 2>&1 \
    && sy --status --json | jq -e '.result.pass==true' >/dev/null 2>&1 \
    && pass "spec-review --fixup — 통과 뒤 오타를 리뷰 없이 받아들임 · 그 뒤 --snapshot 도 원장을 안 건드림" || fail "spec-review --fixup — 불일치: $(echo "$FX" | jq -c .result) $(sy --status --json | jq -c '.result|{pass,fixup}')"
mv "$SY/.review-snapshot" "$SY/.snapshot-away"     # 옛 원장에서 올라와 본문 사본이 없을 때
printf 'no-copy\n' >> "$SY/spec.md"
sy --fixup --json | jq -e '.status=="ok" and .result.changed_lines==null and .result.files==[]' >/dev/null 2>&1 \
    && pass "spec-review --fixup — 본문 사본이 없으면 changed_lines 를 0 이 아니라 null 로 (모르는 걸 0 으로 말하지 않음)" || fail "spec-review --fixup — 사본 없을 때 0줄로 단정: $(sy --fixup --json | jq -c '.result|{changed_lines,files}')"
mv "$SY/.snapshot-away" "$SY/.review-snapshot"
sy_review "진행" "진행"; sy --snapshot --json >/dev/null 2>&1; sy_review "진행" "진행"
sy_review "진행" "보강 필요"     # fixup 은 통과한 뒤에만
printf 'x\n' >> "$SY/spec.md"
sy --fixup --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "spec-review --fixup — 통과하지 않은 스냅샷엔 거부" || fail "spec-review --fixup — 보강 필요인데 받음"
sy_review "진행" "진행"
printf -- '- [ ] T001 [AC1] a — files: a.kt\n' > "$SY/tasks.md"
TS=$(sy --snapshot --stage tasks --json)
echo "$TS" | jq -e '.result.stage=="tasks" and .result.round==1 and .result.stage_reset==true and .result.max_rounds==2' >/dev/null 2>&1 \
    && sy --status --json | jq -e '.result.stage=="tasks" and (.result.changed_files|index("tasks.md")==null)' >/dev/null 2>&1 \
    && pass "spec-review --snapshot --stage tasks — 단계가 바뀌면 라운드 1 부터 · 상한 2 · --status 가 stage 보고" || fail "spec-review --stage tasks — 불일치: $(echo "$TS" | jq -c .result)"
sy --delta --json | jq -e '.result.base=="reviewed" and ([.result.files[]|select(.file=="tasks.md")][0].changed_lines==1)' >/dev/null 2>&1 \
    && pass "spec-review --delta — 리뷰 뒤 생긴 tasks.md 는 전부 바뀐 줄로" || fail "spec-review --delta — 새 tasks.md 를 못 셈"
sy_review "진행" "진행"; printf 'y\n' >> "$SY/tasks.md"; sy --snapshot --json >/dev/null 2>&1
sy_review "진행" "보강 필요"; printf 'z\n' >> "$SY/tasks.md"
sy --snapshot --json | jq -e '.status=="warning" and .result.round==3 and .result.round_exceeded==true and (.warnings[0]|test("tasks 단계"))' >/dev/null 2>&1 \
    && pass "spec-review --snapshot — tasks 단계는 3 라운드째에 상한 경고" || fail "spec-review — tasks 단계 상한 2 가 안 걸림: $(cat "$SY/.review-round")"
sy --snapshot --stage bogus --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "spec-review --stage — spec|tasks 외 값은 exit 1" || fail "spec-review --stage — 아무 값이나 받음"
printf '2|abc|2026-01-01T00:00Z|def||\n' > "$SY/.review-round"
sy --status --json | jq -e '.result.round==2 and .result.stage=="spec" and .result.snapshot_sha=="abc" and .result.fixup.applied==false' >/dev/null 2>&1 \
    && pass "spec-review — 옛 5필드 .review-round 도 읽음 (stage 기본 spec · fixup 없음)" || fail "spec-review — 옛 원장 형식에 깨짐"
rm -rf "$SR"

# 엣지 연결 — 보내는 쪽만 적고 받는 쪽이 모르면 산문 약속이에요.
grep -q 'spec-review.sh' "$REPO/skills/spec-validate/SKILL.md" && grep -q 'goax:architect' "$REPO/skills/spec-validate/SKILL.md" \
    && pass "spec-validate — 합의 리뷰가 spec-review.sh + architect 를 실제로 호출" || fail "spec-validate — 합의 리뷰 엣지 없음"
grep -q '^verdict:' "$REPO/agents/architect.md" && grep -q 'review-spec.architect.md' "$REPO/agents/architect.md" \
    && pass "architect — spec 리뷰 verdict 파일 계약 명시" || fail "architect — spec 리뷰 계약 없음"
grep -q 'review-spec.evaluator.md' "$REPO/agents/evaluator.md" \
    && pass "evaluator — spec 모드 파일 계약 명시" || fail "evaluator — spec 모드 없음"
# 검토 범위 분리·병렬·비차단 — 두 agent 가 같은 것을 보면 같은 지적이 두 번 오고, 순차는 시간만 더해요
grep -q '^## 비차단' "$REPO/agents/architect.md" && grep -q '^## 비차단' "$REPO/agents/evaluator.md" \
    && grep -q '하지 않는 것' "$REPO/agents/architect.md" && grep -q '하지 않는 것' "$REPO/agents/evaluator.md" \
    && pass "architect·evaluator — spec 모드에 '하지 않는 것' 절 + '## 비차단' 절 (검토 범위 분리 · verdict 에 안 세는 지적)" \
    || fail "architect/evaluator — 검토 범위 분리('하지 않는 것') 또는 '## 비차단' 절 없음"
grep -q '한 메시지에 같이 띄' "$REPO/skills/spec-validate/SKILL.md" && ! grep -q '둘을 한 메시지에 같이 띄우지 마세요' "$REPO/skills/spec-validate/SKILL.md" \
    && grep -q '병렬' "$REPO/agents/architect.md" && grep -q '병렬' "$REPO/agents/evaluator.md" \
    && ! grep -q '순차·독립' "$REPO/CONCEPTS.md" && ! grep -q 'sequentially in fresh contexts' "$REPO/CLAUDE.md" \
    && pass "spec-validate — architect·evaluator 병렬 기동 (agents · CONCEPTS · CLAUDE.md 동기화)" || fail "spec-validate — 순차 기동 문구 잔존"
grep -q -- '--delta' "$REPO/skills/spec-validate/SKILL.md" && grep -q -- '--fixup' "$REPO/skills/spec-validate/SKILL.md" \
    && grep -q -- '--stage tasks' "$REPO/skills/spec-validate/SKILL.md" && grep -q -- '--stage tasks' "$REPO/skills/spec-tasks/SKILL.md" \
    && grep -q 'delta' "$REPO/agents/architect.md" && grep -q 'delta' "$REPO/agents/evaluator.md" \
    && pass "spec-validate·spec-tasks·agents — --delta/--fixup/--stage tasks 가 호출부·수신부에 모두 있음" || fail "spec-review 새 옵션 — 스크립트만 있고 skill/agent 가 안 씀"
grep -q '빌드·테스트' "$REPO/agents/architect.md" && grep -q '빌드·테스트' "$REPO/agents/evaluator.md" && grep -q '검증 예산' "$REPO/skills/spec-validate/SKILL.md" \
    && pass "spec 리뷰 검증 예산 — grep·read 만, 빌드·테스트 금지 (agents + skill)" || fail "spec 리뷰 — 검증 예산 미명시"
grep -qE 'update-task\.sh .*--phase implementing' "$REPO/skills/spec-implement/SKILL.md" && grep -qE 'update-task\.sh .*--phase review' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — phase implementing/review 를 실제로 씀 (HUD 가 움직이는 조건)" || fail "spec-implement — phase 기록 없음 (HUD 가 tasks 에 멈춤)"
grep -q 'hud' "$REPO/templates/default/.ax/hud/state.json.template" && grep -q 'hud.plugin_version' "$REPO/docs/state-ownership.md" \
    && pass "state.json hud 캐시 — template · ownership 문서 동기화" || fail "state.json hud 캐시 3-way 동기화 누락"
# state.json 은 gitignore 라 새 워크트리엔 없어요 — "installer 먼저" 로 죽으면 skill 의 `|| true` 가 삼켜 HUD 가 영영 죽어요.
# 설치본에 같이 들어간 템플릿으로 만들고 진행해요. 템플릿도 없으면(옛 설치본) 그때만 exit 1.
# fixture 는 provision.sh 로 깐 실제 설치본이에요 — 예전엔 템플릿을 손으로 .ax/hud/ 에 넣어 통과했는데,
# MANIFEST 가 그 템플릿을 설치하지 않아서 실사용에선 이 경로가 한 번도 돌지 않았어요.
if command -v jq >/dev/null 2>&1 && fx_install US; then
    rm -f "$US/.ax/state.json"
    GOAX_PROJECT_DIR="$US" bash "$US/.ax/scripts/bash/update-state.sh" --skill triage >/dev/null 2>&1; us_rc=$?
    [ "$us_rc" -eq 0 ] && jq -e '.last_skill=="triage" and .skill_calls==1 and .layers.L0_triage.active==true' "$US/.ax/state.json" >/dev/null 2>&1 \
        && pass "update-state — 설치본에서 state.json 이 없으면 템플릿으로 만들고 진행 (새 워크트리)" || fail "update-state — 설치본 자가 복구 실패 (exit=$us_rc): $(jq -c '{last_skill,skill_calls}' "$US/.ax/state.json" 2>/dev/null)"
    rm -f "$US/.ax/state.json"
    US_J=$(GOAX_PROJECT_DIR="$US" bash "$US/.ax/scripts/bash/update-state.sh" --json 2>/dev/null); us_rc=$?
    [ "$us_rc" -eq 0 ] && [ ! -f "$US/.ax/state.json" ] \
      && printf '%s\n' "$US_J" | jq -e '.status=="ok" and .result.written==false and .result.state.layers.L0_triage.active==true' >/dev/null 2>&1 \
        && pass "update-state --json — 파일이 없으면 템플릿으로 계산만, envelope 한 줄 · 파일 안 만듦" || fail "update-state --json — exit=$us_rc · 파일 생김=$([ -f "$US/.ax/state.json" ] && echo yes || echo no) · $(printf '%s' "$US_J" | head -c 120)"
    rm -f "$US/.ax/hud/state.json.template"
    GOAX_PROJECT_DIR="$US" bash "$US/.ax/scripts/bash/update-state.sh" --skill triage >/dev/null 2>&1; us_rc=$?
    [ "$us_rc" -eq 1 ] && [ ! -f "$US/.ax/state.json" ] \
        && pass "update-state — state.json 도 템플릿도 없으면 exit 1 (파일 안 만듦)" || fail "update-state — 템플릿 없이 state.json 을 만들거나 exit=$us_rc"
    rm -rf "$US"
fi

smoke_done
