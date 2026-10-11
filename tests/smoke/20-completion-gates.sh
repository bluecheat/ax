#!/usr/bin/env bash
# tests/smoke/20-completion-gates.sh — §71 G8 전체 검증 기록 · §72 레인 소유 파일 스택 판정
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/20-completion-gates.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "71. tasks-gate G8 — 완료 전에 config.yml commands 전부를 돌린 기록이 있어야 해요"
# ───────────────────────────────────────────────────────────
# 실측(commerce): 패키지 필터 테스트로만 확인하고 완료로 넘긴 뒤, 전체 스캔 테스트의 빈 이름 충돌을 CI 가 처음 잡았어요.
if command -v jq >/dev/null 2>&1 && fx_install VG --git; then
    SPD="$VG/.ax/docs/spec/2026-10-11-ab12-v"; mkdir -p "$SPD" "$VG/src"
    printf '## 3.\n- **AC1** a\n' > "$SPD/spec.md"; printf -- '- [x] T001 [AC1] a — files: src/a.kt\n' > "$SPD/tasks.md"
    echo 'verdict: 진행' > "$SPD/review.md"; echo 'verdict: 진행' > "$SPD/review-rules.md"
    echo 'fun a() = 1' > "$VG/src/a.kt"
    jq '.task_id="V"|.phase="implementing"|.spec_dir=".ax/docs/spec/2026-10-11-ab12-v"|.size="L"|.risk="L2"' \
        "$VG/.ax/current-task.json" > "$VG/ct" && mv "$VG/ct" "$VG/.ax/current-task.json"
    vg_gate() { GOAX_PROJECT_DIR="$VG" bash "$VG/.ax/scripts/bash/tasks-gate.sh" --spec ab12 --json 2>/dev/null | jq -c "$1"; }
    vg_rec()  { GOAX_PROJECT_DIR="$VG" bash "$VG/.ax/scripts/bash/zero-verify.sh" --record ab12 "$@" --json 2>/dev/null; }

    # commands.test 가 없으면 요구하지 않아요 (warning 대상도 아니에요 — 스택을 추측하지 않아요)
    G8U=$(vg_gate '[.result.complete, .result.verify_state]')
    sed -i.bak 's/^  test: ""/  test: "test -f src\/a.kt"/' "$VG/.ax/config.yml" && rm -f "$VG/.ax/config.yml.bak"
    G8M=$(vg_gate '[.result.complete, .result.verify_state, (.next_step|test("zero-verify.sh --record"))]')
    vg_rec --cmd "true" >/dev/null; G8C=$?
    vg_rec --dry-run >/dev/null; G8D=$([ -f "$SPD/verify.json" ] && echo wrote || echo none)
    VR=$(vg_rec)
    G8OK=$(vg_gate '[.result.complete, .result.verify_state]')
    git -C "$VG" add -A >/dev/null 2>&1; git -C "$VG" -c core.hooksPath=/dev/null -c user.name=s -c user.email=s@x commit -qm v >/dev/null 2>&1
    G8CM=$(vg_gate '[.result.complete, .result.verify_state]')
    echo 'fun a() = 2' > "$VG/src/a.kt"
    G8ST=$(vg_gate '[.result.complete, .result.verify_state]')
    vg_rec >/dev/null
    sed -i.bak 's/^  test: .*/  test: "test -f src\/a.kt --filtered"/' "$VG/.ax/config.yml" && rm -f "$VG/.ax/config.yml.bak"
    G8MM=$(vg_gate '[.result.complete, .result.verify_state]')
    sed -i.bak 's/^  test: .*/  test: "false"/' "$VG/.ax/config.yml" && rm -f "$VG/.ax/config.yml.bak"
    vg_rec >/dev/null; G8RC=$?
    G8F=$(vg_gate '[.result.complete, .result.verify_state]')
    jq '.size="S"|.risk="L1"' "$VG/.ax/current-task.json" > "$VG/ct" && mv "$VG/ct" "$VG/.ax/current-task.json"
    G8FS=$(vg_gate '[.result.complete, .result.verify_state]')
    { [ "$G8U" = '[true,"unconfigured"]' ] && [ "$G8M" = '[false,"missing",true]' ] && [ "$G8C" -eq 1 ] && [ "$G8D" = none ] \
      && printf '%s' "$VR" | jq -e '.status=="ok" and (.result.record_file|endswith("verify.json"))' >/dev/null 2>&1 \
      && [ "$G8OK" = '[true,"ok"]' ] && [ "$G8CM" = '[true,"ok"]' ] && [ "$G8ST" = '[false,"stale"]' ] \
      && [ "$G8MM" = '[false,"mismatch"]' ] && [ "$G8RC" -eq 1 ] && [ "$G8F" = '[false,"fail"]' ] && [ "$G8FS" = '[false,"fail"]' ]; } \
        && pass "G8 — 미설정은 요구 안 함 · 기록 없음/낡음/명령 불일치/실패는 미완료 · 커밋해도 유효 · --cmd 기록 거부 · dry-run 무기록 · 실패 기록은 필수가 아니어도 막아요" \
        || fail "G8: 미설정=$G8U 없음=$G8M cmd거부=$G8C dry=$G8D ok=$G8OK 커밋뒤=$G8CM 수정뒤=$G8ST 명령다름=$G8MM 실패rc=$G8RC 실패=$G8F S=$G8FS"
    grep -q 'zero-verify.sh --record' "$REPO/skills/spec-implement/SKILL.md" && grep -q 'zero-verify.sh --record' "$REPO/skills/spec-implement/references/lane-mode.md" \
        && pass "G8 — spec-implement 완료 절차와 레인 모드 통합 검증이 --record 를 불러요" || fail "G8 — spec-implement/lane-mode 에 --record 호출이 없어요"
    rm -rf "$VG"
else
    pass "§71 — jq 없음 또는 설치 실패, skip"
fi

# ───────────────────────────────────────────────────────────
section "72. lanes-dispatch 스택 판정 — 정리·스윕 레인 소유 목록에 레거시가 섞이지 않게"
# ───────────────────────────────────────────────────────────
# 실측(commerce): 스타일 정리 레인 목록을 패키지 글롭으로 뽑아 main 의 레거시 4파일이 섞였고, PR diff 에 옛 raw SQL 이 드러났어요.
if command -v jq >/dev/null 2>&1 && fx_install LS --git; then
    git -C "$LS" branch -M main >/dev/null 2>&1
    mkdir -p "$LS/src/ranking"; echo legacy > "$LS/src/ranking/Legacy.kt"; echo old > "$LS/src/ranking/Touch.kt"
    git -C "$LS" add -A >/dev/null 2>&1; git -C "$LS" -c core.hooksPath=/dev/null -c user.name=s -c user.email=s@x commit -qm legacy >/dev/null 2>&1
    git -C "$LS" checkout -qb feat >/dev/null 2>&1
    echo new > "$LS/src/ranking/New.kt"; git -C "$LS" add -A >/dev/null 2>&1
    git -C "$LS" -c core.hooksPath=/dev/null -c user.name=s -c user.email=s@x commit -qm new >/dev/null 2>&1
    echo wip > "$LS/src/ranking/Wip.kt"; echo changed >> "$LS/src/ranking/Touch.kt"
    LSD="$LS/.ax/docs/spec/2026-10-11-cd34-s"; mkdir -p "$LSD"
    printf -- '- [ ] T001 [AC1] 정리 — files: src/ranking/New.kt, src/ranking/Legacy.kt, src/ranking/Touch.kt\n    레인: A\n' > "$LSD/tasks.md"
    ld() { GOAX_PROJECT_DIR="$LS" bash "$LS/.ax/scripts/bash/lanes-dispatch.sh" "$@" --json 2>/dev/null; }
    SF=$(ld --stack-files --path src/ranking | jq -c '.result.files')
    DP=$(ld --spec cd34 --dispatch A)
    { [ "$SF" = '["src/ranking/New.kt","src/ranking/Touch.kt","src/ranking/Wip.kt"]' ] \
      && printf '%s' "$DP" | jq -e '.result.outside_stack==["src/ranking/Legacy.kt"] and (.warnings|any(test("스택 밖")))' >/dev/null 2>&1 \
      && grep -q '디스패치:' "$LSD/tasks.md"; } \
        && pass "lanes-dispatch — --stack-files 는 커밋·워킹 트리·새 파일만, --dispatch 는 스택 밖 기존 파일을 outside_stack 로 알리고 보내요" \
        || fail "lanes-dispatch 스택: files=$SF dispatch=$(printf '%s' "$DP" | jq -c '{o:.result.outside_stack,w:.warnings}')"
    grep -q -- '--stack-files' "$REPO/skills/lane/SKILL.md" && grep -q 'outside_stack' "$REPO/skills/spec-implement/references/lane-mode.md" \
        && pass "lane · lane-mode — 소유 목록을 --stack-files 로 뽑고 outside_stack 를 확인해요" || fail "lane/lane-mode 에 스택 판정 안내가 없어요"
    rm -rf "$LS"
else
    pass "§72 — jq 없음 또는 설치 실패, skip"
fi

smoke_done
