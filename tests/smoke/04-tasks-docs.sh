#!/usr/bin/env bash
# tests/smoke/04-tasks-docs.sh — §16–§29 — git 훅 · ID · 개수 서술 · tasks-plan/gate · vendor · 주입 · 프롬프트 규율 · lint
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/04-tasks-docs.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "16. install-git-hooks.sh — OpenCode mode hook 보전"
# ───────────────────────────────────────────────────────────
IGH="$REPO/templates/default/.ax/scripts/bash/install-git-hooks.sh"
[ -f "$IGH" ] && pass "install-git-hooks.sh 존재" || fail "install-git-hooks.sh 누락"
[ -x "$IGH" ] && pass "install-git-hooks.sh 실행권한" || fail "install-git-hooks.sh 실행권한 X"
bash -n "$IGH" 2>/dev/null && pass "install-git-hooks.sh 문법 OK" || fail "install-git-hooks.sh 문법 오류"

# E2E — 임시 fixture 에서 install / re-install (idempotent) / wrapper 검증
IGH_FX=$(mktemp -d)
mkdir -p "$IGH_FX/.ax/scripts/bash" "$IGH_FX/.ax/hooks/pre-commit"
cp "$REPO/templates/default/.ax/scripts/bash/"{common.sh,install-git-hooks.sh} "$IGH_FX/.ax/scripts/bash/"
( cd "$IGH_FX" && git init -q && git config user.email t@l && git config user.name t )

# (1) install — action=installed
OUT=$(GOAX_PROJECT_DIR=$IGH_FX bash "$IGH_FX/.ax/scripts/bash/install-git-hooks.sh" --json 2>&1)
ACTION=$(echo "$OUT" | jq -r '.result.action' 2>/dev/null)
[ "$ACTION" = "installed" ] \
    && pass "install-git-hooks — 첫 install action=installed" \
    || fail "install-git-hooks — action 부정확: $ACTION ($OUT)"

# (2) marker + 실행권한
grep -q "#goax-pre-commit-chain" "$IGH_FX/.git/hooks/pre-commit" \
    && pass "install-git-hooks — wrapper 에 goax marker 포함" \
    || fail "install-git-hooks — goax marker 누락"
[ -x "$IGH_FX/.git/hooks/pre-commit" ] \
    && pass "install-git-hooks — wrapper 실행권한 (755)" \
    || fail "install-git-hooks — wrapper 실행권한 X"

# (3) re-install — idempotent (action=skipped, exit=2)
OUT=$(GOAX_PROJECT_DIR=$IGH_FX bash "$IGH_FX/.ax/scripts/bash/install-git-hooks.sh" --json 2>&1; echo "EXIT=$?")
STATUS=$(echo "$OUT" | grep -v '^EXIT=' | jq -r '.status' 2>/dev/null)
EXIT=$(echo "$OUT" | grep '^EXIT=' | cut -d= -f2)
if [ "$STATUS" = "skipped" ] && [ "$EXIT" = "2" ]; then
    pass "install-git-hooks — 재호출 시 skipped + exit 2 (idempotent)"
else
    fail "install-git-hooks — idempotent 부정확: status=$STATUS exit=$EXIT"
fi

# (4) wrapper 안에 .ax/hooks/pre-commit chain 로직 포함
grep -q '.ax/hooks/pre-commit' "$IGH_FX/.git/hooks/pre-commit" \
    && pass "install-git-hooks — wrapper 에 .ax/hooks/pre-commit chain 로직 포함" \
    || fail "install-git-hooks — chain 로직 누락"

rm -rf "$IGH_FX"

# ───────────────────────────────────────────────────────────
section "17. next-spec-num.sh --kind adr|spec — ID 형식 회귀"
# ───────────────────────────────────────────────────────────
NS2_FX=$(mktemp -d)
mkdir -p "$NS2_FX/.ax/scripts/bash" "$NS2_FX/.ax/docs/adr" "$NS2_FX/.ax/docs/spec"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS2_FX/.ax/scripts/bash/"
ID_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]$'
: > "$NS2_FX/.ax/docs/adr/0003-x.md"
for k in adr spec ""; do
    OUT=$(CLAUDE_PROJECT_DIR=$NS2_FX bash "$NS2_FX/.ax/scripts/bash/next-spec-num.sh" ${k:+--kind "$k"} --json 2>&1)
    NEXT=$(echo "$OUT" | jq -r '.result.next' 2>/dev/null)
    printf '%s' "$NEXT" | grep -qE "$ID_RE" \
        && pass "next-spec-num ${k:+--kind $k}${k:-(--kind 생략 = spec)} — ID 형식 ($NEXT)" \
        || fail "next-spec-num ${k:-(기본)} 결과: $NEXT ($OUT)"
done
TODAY=$(date +%Y-%m-%d)
[ "$(CLAUDE_PROJECT_DIR=$NS2_FX bash "$NS2_FX/.ax/scripts/bash/next-spec-num.sh" | cut -c1-10)" = "$TODAY" ] \
    && pass "next-spec-num — ID 의 날짜는 오늘" || fail "next-spec-num — ID 날짜가 오늘이 아니에요"
rm -rf "$NS2_FX"


# ───────────────────────────────────────────────────────────
section "26. repo CLAUDE.md 의 개수 서술 ↔ 실제 일치"
# ───────────────────────────────────────────────────────────
# 문서에 박은 개수는 자산이 늘 때마다 조용히 틀려져요 (실제로 19→21 로 어긋나 있었음).
DOC_SK=$(grep -oE '`skills/<name>/SKILL\.md` — [0-9]+ skills' "$REPO/CLAUDE.md" | grep -oE '[0-9]+' | head -1)
REAL_SK=$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | grep -c . || true)
[ "${DOC_SK:-0}" = "${REAL_SK:-0}" ] \
    && pass "CLAUDE.md skill 개수 = $REAL_SK (실제와 일치)" \
    || fail "CLAUDE.md 는 ${DOC_SK} skills 라는데 실제는 ${REAL_SK}개"

DOC_SC=$(grep -oE 'deterministic shell tooling \([0-9]+ scripts\)' "$REPO/CLAUDE.md" | grep -oE '[0-9]+' | head -1)
REAL_SC=$(find "$REPO/templates/default/.ax/scripts/bash" -maxdepth 1 -name '*.sh' | grep -c . || true)
[ "${DOC_SC:-0}" = "${REAL_SC:-0}" ] \
    && pass "CLAUDE.md script 개수 = $REAL_SC (실제와 일치)" \
    || fail "CLAUDE.md 는 ${DOC_SC} scripts 라는데 실제는 ${REAL_SC}개"

# ───────────────────────────────────────────────────────────
section "29. tasks-plan — ready 집합 + [P] 주장 검증"
# ───────────────────────────────────────────────────────────
# wave(배리어) 가 아니라 항목별 ready 여야 해요 — "1차 전원 완료 → 2차" 는
# 가장 느린 하나가 나머지를 붙잡아요.
TP=$(mktemp -d)
mkdir -p "$TP"/.ax/scripts/bash "$TP"/.ax/docs/spec/012-x
cp "$REPO/templates/default/.ax/scripts/bash/"{common,tasks-plan}.sh "$TP/.ax/scripts/bash/"
cat > "$TP/.ax/docs/spec/012-x/tasks.md" <<'TPEOF'
- [x] T001 [AC1] a — files: x/A.kt
- [ ] T002 [P] [AC1] b — files: x/B.kt
      의존: 없음
- [ ] T003 [AC2] c — files: x/C.kt
      의존: T001
- [ ] T004 [AC2] d — files: x/D.kt
      의존: T003
- [ ] T005 [P] [AC3] e — files: x/E.kt
      의존: 없음
- [ ] T006 [P] [AC3] f — files: x/E.kt
      의존: 없음
TPEOF
TPO=$(GOAX_PROJECT_DIR="$TP" bash "$TP/.ax/scripts/bash/tasks-plan.sh" --spec 012-x --json 2>/dev/null)

echo "$TPO" | jq -e '.result.ready | index("T003")' >/dev/null 2>&1 \
    && pass "tasks-plan — 의존 완료된 task 가 ready" || fail "tasks-plan — ready 계산 오류"
echo "$TPO" | jq -e '.result.blocked | index("T004")' >/dev/null 2>&1 \
    && pass "tasks-plan — 미완료 의존이 있으면 blocked" || fail "tasks-plan — blocked 계산 오류"
# 항목별 승격이어야 — T003 은 T002 를 기다리지 않아요 (배리어 아님)
echo "$TPO" | jq -e '(.result.ready | length) >= 3' >/dev/null 2>&1 \
    && pass "tasks-plan — 항목별 ready (배리어 아님)" || fail "tasks-plan — 배리어처럼 동작"
# [P] 인데 파일이 겹치면 violation
echo "$TPO" | jq -e '.result.violations[0].file == "x/E.kt"' >/dev/null 2>&1 \
    && pass "tasks-plan — [P] 파일 충돌 검출 (주장 검증)" || fail "tasks-plan — [P] 충돌 미검출"
echo "$TPO" | jq -e '.status == "warning"' >/dev/null 2>&1 \
    && pass "tasks-plan — 충돌 시 warning" || fail "tasks-plan — 충돌인데 ok 반환"

# wave 라는 개념을 내보내면 안 돼요 (배리어 유혹)
echo "$TPO" | jq -e 'has("waves") or (.result|has("waves"))' >/dev/null 2>&1 \
    && fail "tasks-plan — wave 를 출력함 (배리어 모델)" \
    || pass "tasks-plan — wave 미출력 (파이프라인 모델 유지)"
rm -rf "$TP"

# ───────────────────────────────────────────────────────────
section "28. tasks-gate — 완료 게이트 4종"
# ───────────────────────────────────────────────────────────
# 완료 판정이 "빈 체크박스 0개" 뿐이면 (a) 수용 기준 미충족 (b) 미완료를 지워서
# 통과 를 구분 못 해요. 실사용 spec 21개 중 14개가 미완료를 남긴 채 끝나 있었음.
TG=$(mktemp -d)
mkdir -p "$TG"/.ax/scripts/bash "$TG"/.ax/docs/spec/012-x
cp "$REPO/templates/default/.ax/scripts/bash/"{common,tasks-gate}.sh "$TG/.ax/scripts/bash/"
echo '{}' > "$TG/.ax/state.json"
printf '## 3. \n- [ ] **AC1** a\n- [ ] **AC2** b\n' > "$TG/.ax/docs/spec/012-x/spec.md"
printf -- '- [x] T001 [AC1] a — files: a.kt\n- [ ] T002 [AC2] b — files: b.kt\n' > "$TG/.ax/docs/spec/012-x/tasks.md"

tg() { GOAX_PROJECT_DIR="$TG" bash "$TG/.ax/scripts/bash/tasks-gate.sh" --spec 012-x --json 2>/dev/null; }

tg | jq -e '.result.open == 1 and .result.complete == false' >/dev/null 2>&1 \
    && pass "tasks-gate G1 — 미완료 task 검출" || fail "tasks-gate G1 실패"

# [~] 보류는 미완료로 세지 않아야 (의도적 보류를 표현할 수단이 없으면 게이트가 우회 대상이 됨)
printf -- '- [x] T001 [AC1] a — files: a.kt\n- [~] T002 [AC2] b — files: b.kt\n      보류: 사유\n' > "$TG/.ax/docs/spec/012-x/tasks.md"
tg | jq -e '.result.open == 0 and .result.paused == 1 and .result.complete == true' >/dev/null 2>&1 \
    && pass "tasks-gate — [~] 보류는 미완료가 아님 (complete)" || fail "tasks-gate — 보류 처리 실패"

# G2 커버리지 — AC2 에 대응 task 가 없으면
printf -- '- [x] T001 [AC1] a — files: a.kt\n' > "$TG/.ax/docs/spec/012-x/tasks.md"
tg | jq -e '.result.ac_uncovered | index("AC2")' >/dev/null 2>&1 \
    && pass "tasks-gate G2 — 대응 task 없는 AC 검출" || fail "tasks-gate G2 실패"

# G3 orphan — 어떤 AC 도 참조 안 하는 task
printf -- '- [x] T001 [AC1] a — files: a.kt\n- [x] T002 [AC2] b — files: b.kt\n- [x] T009 무관 — files: z.kt\n' > "$TG/.ax/docs/spec/012-x/tasks.md"
tg >/dev/null 2>&1   # 봉인값 3 으로 갱신
tg | jq -e '.result.orphan_tasks | index("T009")' >/dev/null 2>&1 \
    && pass "tasks-gate G3 — AC 미참조 orphan task 검출" || fail "tasks-gate G3 실패"

# G4 유실 — task 를 지워서 통과시키려는 시도
printf -- '- [x] T001 [AC1] a — files: a.kt\n- [x] T002 [AC2] b — files: b.kt\n' > "$TG/.ax/docs/spec/012-x/tasks.md"
tg | jq -e '.result.task_count_drop == 1 and .result.complete == false' >/dev/null 2>&1 \
    && pass "tasks-gate G4 — task 삭제로 통과 시도 차단" || fail "tasks-gate G4 실패"

# exit 계약 — `1 = 위반` / `2 = 검사 못 함`. 둘을 같은 코드로 두면 호출자가
# "게이트가 막았다" 와 "게이트가 안 돌았다" 를 구분 못 해요 (예전엔 위반도 2 였어요).
GOAX_PROJECT_DIR="$TG" bash "$TG/.ax/scripts/bash/tasks-gate.sh" --spec 012-x --strict >/dev/null 2>&1
[ $? -eq 1 ] && pass "tasks-gate --strict — 위반 시 exit 1" || fail "tasks-gate --strict — exit code 부정확"
TG_NOPE=$(GOAX_PROJECT_DIR="$TG" bash "$TG/.ax/scripts/bash/tasks-gate.sh" --spec 999-nope --json 2>/dev/null); TG_NOPE_RC=$?
[ "$TG_NOPE_RC" -eq 2 ] && echo "$TG_NOPE" | jq -e '.status=="skipped"' >/dev/null 2>&1 \
    && pass "tasks-gate — 없는 spec 은 status:skipped + exit 2 (위반과 구분)" \
    || fail "tasks-gate — 없는 spec 이 exit $TG_NOPE_RC (기대 2): ${TG_NOPE:0:80}"

# G5 원장 — 체크박스를 채운 쪽과 검사받는 쪽이 같으면 게이트가 아니라 자기보고예요.
# 레인이 조용해진 것(idle)과 산출물을 받은 것(보고:)은 달라요 — 8 레인 idle 인데 24/36 이었어요.
echo '{}' > "$TG/.ax/state.json"      # G3/G4 가 올린 봉인값(3) 초기화 — 여기선 2 task fixture 라 G4 와 섞이면 안 돼요
printf -- '- [ ] T001 [AC1] a — files: a.kt\n      레인: A\n      디스패치: 2026-01-01T00:00Z\n- [x] T002 [AC2] b — files: b.kt\n' > "$TG/.ax/docs/spec/012-x/tasks.md"
tg | jq -e '(.result.dispatched_unreported | index("T001")) and .result.complete == false' >/dev/null 2>&1 \
    && pass "tasks-gate G5 — 보고 안 받은 디스패치는 미완료" || fail "tasks-gate G5 — dispatched_unreported 미검출"
printf -- '- [x] T001 [AC1] a — files: a.kt\n      레인: A\n      디스패치: 2026-01-01T00:00Z\n- [x] T002 [AC2] b — files: b.kt\n' > "$TG/.ax/docs/spec/012-x/tasks.md"
tg | jq -e '(.result.done_without_report | index("T001")) and .result.complete == false' >/dev/null 2>&1 \
    && pass "tasks-gate G5 — 보고 없이 켜진 체크박스는 미완료 (레인 자기보고 차단)" || fail "tasks-gate G5 — done_without_report 미검출"
printf -- '- [x] T001 [AC1] a — files: a.kt\n      레인: A\n      디스패치: 2026-01-01T00:00Z\n      보고: 2026-01-01T01:00Z\n- [x] T002 [AC2] b — files: b.kt\n' > "$TG/.ax/docs/spec/012-x/tasks.md"
tg | jq -e '.result.dispatched_unreported == [] and .result.done_without_report == [] and .result.complete == true' >/dev/null 2>&1 \
    && pass "tasks-gate G5 — 디스패치+보고 짝이 맞으면 통과" || fail "tasks-gate G5 — 정상 원장을 위반으로 봄"

# G6 evaluator verdict — 필수 여부는 활성 spec 의 size×risk (SSOT: tier-from-state.sh)
cp "$REPO/templates/default/.ax/scripts/bash/tier-from-state.sh" "$TG/.ax/scripts/bash/"
echo '{"phase":"implementing","spec_dir":".ax/docs/spec/012-x","size":"L","risk":"L1"}' > "$TG/.ax/current-task.json"
tg | jq -e '.result.review_required == true and .result.review_verdict == null and .result.complete == false' >/dev/null 2>&1 \
    && pass "tasks-gate G6 — L×L1 은 evaluator 필수, review.md 없으면 미완료" || fail "tasks-gate G6 — 필수 리뷰 부재를 통과시킴"
printf 'verdict: 진행\n\n## Evaluator Review\n발견 0건\n' > "$TG/.ax/docs/spec/012-x/review.md"
printf 'verdict: 진행\n' > "$TG/.ax/docs/spec/012-x/review-rules.md"   # G7 도 같은 필수 여부 — §65 가 따로 봐요
tg | jq -e '.result.review_verdict == "진행" and .result.complete == true' >/dev/null 2>&1 \
    && pass "tasks-gate G6 — verdict 진행 → complete" || fail "tasks-gate G6 — verdict 진행을 못 읽음"
printf 'verdict: 보강 필요\n' > "$TG/.ax/docs/spec/012-x/review.md"
tg | jq -e '.result.review_verdict == "보강 필요" and .result.complete == false' >/dev/null 2>&1 \
    && pass "tasks-gate G6 — verdict 보강 필요 → 미완료" || fail "tasks-gate G6 — 보강 필요를 통과시킴"
echo '{"phase":"implementing","spec_dir":".ax/docs/spec/012-x","size":"S","risk":"L0"}' > "$TG/.ax/current-task.json"
tg | jq -e '.result.review_required == false and .result.complete == false' >/dev/null 2>&1 \
    && pass "tasks-gate G6 — 선택이어도 받은 리뷰가 보강 필요면 미완료" || fail "tasks-gate G6 — 선택 리뷰의 지적을 무시함"
rm "$TG/.ax/docs/spec/012-x/review.md"
tg | jq -e '.result.review_required == false and .result.review_verdict == null and .result.complete == true' >/dev/null 2>&1 \
    && pass "tasks-gate G6 — S×L0 은 리뷰 없이 완료 가능" || fail "tasks-gate G6 — 선택 리뷰를 필수로 강제함"
echo '{"phase":"implementing","spec_dir":".ax/docs/spec/099-other","size":"L","risk":"L3"}' > "$TG/.ax/current-task.json"
tg | jq -e '.result.review_required == false' >/dev/null 2>&1 \
    && pass "tasks-gate G6 — 다른 spec 이 활성이면 필수 판정 안 함 (--all 안전)" || fail "tasks-gate G6 — 비활성 spec 에 필수를 적용함"
rm -rf "$TG"

# pre-commit 훅 — 활성 spec 없으면 조용해야 (커밋마다 떠들면 우회 대상이 됨)
TGH=$(mktemp -d)
mkdir -p "$TGH"/.ax/scripts/bash "$TGH"/.ax/hooks/pre-commit
cp "$REPO/templates/default/.ax/scripts/bash/"{common,tasks-gate}.sh "$TGH/.ax/scripts/bash/"
cp "$REPO/templates/default/.ax/hooks/pre-commit/spec-completion-gate.sh" "$TGH/.ax/hooks/pre-commit/"
echo '{"phase":"idle"}' > "$TGH/.ax/current-task.json"
OUT_H=$(CLAUDE_PROJECT_DIR=$TGH bash "$TGH/.ax/hooks/pre-commit/spec-completion-gate.sh" 2>&1)
[ -z "$OUT_H" ] && pass "spec-completion-gate — phase=idle 이면 조용히 통과" \
                || fail "spec-completion-gate — idle 인데 출력함: $OUT_H"

# phase=triaged 인데 spec_id/spec_dir 이 없으면 tasks-gate 가 status:skipped, result:{} 를
# 내는데, 예전엔 result.ac_uncovered 에 jq 가 null 을 못 돌아 매 커밋마다 jq 에러를 찍었어요
echo '{"phase":"triaged"}' > "$TGH/.ax/current-task.json"
OUT_H2=$(CLAUDE_PROJECT_DIR=$TGH bash "$TGH/.ax/hooks/pre-commit/spec-completion-gate.sh" 2>&1); RC_H2=$?
[ -z "$OUT_H2" ] && [ "$RC_H2" -eq 0 ] \
    && pass "spec-completion-gate — phase=triaged·spec 없음이면 jq 에러 없이 조용히 통과" \
    || fail "spec-completion-gate — triaged·spec 없음인데 출력함(exit $RC_H2): $OUT_H2"

# 스테이지 파일이 그 spec 에 안 걸리면 한 줄만 내고 통과 (mode=fail 에서도) — 커밋마다 같은 경고가
# 반복되면 아무도 안 읽어요. 걸리는 커밋(spec 디렉토리 · tasks.md files: 경로)만 자세히 말하고 막아요
mkdir -p "$TGH/.ax/docs/spec/012-x" "$TGH/src/feat"
printf '## 3. \n- [ ] **AC1** a\n- [ ] **AC2** b\n' > "$TGH/.ax/docs/spec/012-x/spec.md"
printf -- '```\n- [ ] T000 예시 — files: README.md\n```\n- [x] T001 [AC1] a — files: src/a.ts\n- [ ] T002 [AC2] b — files: ./src/feat/\n' > "$TGH/.ax/docs/spec/012-x/tasks.md"
echo '{"phase":"implementing","spec_dir":".ax/docs/spec/012-x"}' > "$TGH/.ax/current-task.json"
printf 'sensors:\n  mode: fail\n' > "$TGH/.ax/config.yml"
echo x > "$TGH/README.md"; echo x > "$TGH/src/a.ts"; echo x > "$TGH/src/feat/b.ts"; echo x > "$TGH/src/feature.ts"
git -C "$TGH" init -q 2>/dev/null
scg() { git -C "$TGH" reset -q 2>/dev/null; git -C "$TGH" add -- "$@" 2>/dev/null
        OUT_S=$(cd "$TGH" && CLAUDE_PROJECT_DIR=$TGH bash "$TGH/.ax/hooks/pre-commit/spec-completion-gate.sh" 2>&1); RC_S=$?; }
scg README.md src/feature.ts
if [ "$RC_S" -eq 0 ] && [ "$(printf '%s\n' "$OUT_S" | grep -c .)" -eq 1 ] && printf '%s' "$OUT_S" | grep -q '무관해 건너뛰어요'; then
    pass "spec-completion-gate — 무관한 커밋은 한 줄만 · mode=fail 에서도 통과 (펜스 안 예시 경로 · src/feat 접두 오인 없음)"
else fail "spec-completion-gate — 무관한 커밋인데 rc=$RC_S: $OUT_S"; fi
scg src/feat/b.ts
[ "$RC_S" -eq 2 ] && printf '%s' "$OUT_S" | grep -q '미완료 task' \
    && pass "spec-completion-gate — tasks.md files: 디렉토리 아래 파일을 스테이지하면 자세히 · 차단" \
    || fail "spec-completion-gate — files: 경로 커밋인데 rc=$RC_S: $OUT_S"
scg .ax/docs/spec/012-x/tasks.md
[ "$RC_S" -eq 2 ] && pass "spec-completion-gate — spec 디렉토리 파일을 스테이지하면 차단" \
    || fail "spec-completion-gate — spec 디렉토리 커밋인데 rc=$RC_S: $OUT_S"
rm -rf "$TGH"

# ───────────────────────────────────────────────────────────
section "27. mistake — model / session_ref 기록"
# ───────────────────────────────────────────────────────────
DM_FX=$(mktemp -d)
mkdir -p "$DM_FX"/.ax/scripts/bash "$DM_FX"/.ax/mistakes "$DM_FX"/.ax/_templates/mistakes
cp "$REPO/templates/default/.ax/scripts/bash/"{common,init-mistake-file,detect-model,slug-from-text}.sh \
   "$DM_FX/.ax/scripts/bash/" 2>/dev/null || true
chmod +x "$DM_FX"/.ax/scripts/bash/*.sh
cp "$REPO/templates/default/.ax/_templates/mistakes/mistake.md" "$DM_FX/.ax/_templates/mistakes/"

# 템플릿이 placeholder 를 갖고 있어야 치환이 가능해요
grep -q '{{MODEL}}' "$REPO/templates/default/.ax/_templates/mistakes/mistake.md" \
    && pass "mistake 템플릿 — {{MODEL}} placeholder 존재" \
    || fail "mistake 템플릿에 {{MODEL}} 없음 — 기록이 불가능"

(cd "$DM_FX" && GOAX_PROJECT_DIR="$DM_FX" bash .ax/scripts/bash/init-mistake-file.sh --json \
    --category process --slug smoke-model --severity low --detected-by user \
    --source skill --model claude-test-5 --one-line x >/dev/null 2>&1)
MK_FILE=$(ls "$DM_FX"/.ax/mistakes/2*.md 2>/dev/null | head -1)
if [ -n "$MK_FILE" ] && grep -q '^model: claude-test-5' "$MK_FILE"; then
    pass "init-mistake-file --model — frontmatter 에 기록"
else
    fail "init-mistake-file --model — model 미기록"
fi
# placeholder 가 그대로 남으면 안 돼요
[ -n "$MK_FILE" ] && grep -q '{{' "$MK_FILE" \
    && fail "mistake 파일에 치환 안 된 placeholder 잔존" \
    || pass "mistake 파일 — placeholder 전부 치환"

# 감지 실패해도 캡처를 막으면 안 돼요 (unknown 으로 진행)
rm -f "$DM_FX"/.ax/mistakes/2*.md
(cd "$DM_FX" && GOAX_PROJECT_DIR="$DM_FX" CLAUDE_PROJECT_DIR="$DM_FX" \
    bash .ax/scripts/bash/init-mistake-file.sh --json \
    --category process --slug smoke-unknown --severity low --detected-by user \
    --source skill --one-line x >/dev/null 2>&1)
MK2=$(ls "$DM_FX"/.ax/mistakes/2*.md 2>/dev/null | head -1)
[ -n "$MK2" ] && grep -q '^model: unknown' "$MK2" \
    && pass "model 감지 실패 시 unknown 으로 캡처 계속 (차단 안 함)" \
    || fail "model 감지 실패가 캡처를 막거나 필드가 비었음"

# session_ref 는 파일명만 — mistake 는 커밋되므로 절대경로가 들어가면 안 돼요
if [ -n "$MK2" ] && grep -qE '^session_ref: .*/' "$MK2"; then
    fail "session_ref 에 경로가 들어감 (파일명만이어야)"
else
    pass "session_ref — 경로 없이 파일명만"
fi
rm -rf "$DM_FX"

# ───────────────────────────────────────────────────────────
section "25. vendor — ADE 루트 ≠ 프로젝트 루트 (모노레포) 처리"
# ───────────────────────────────────────────────────────────
# .claude/skills 는 저장소 루트, .ax/ 는 projects/<app>/ 인 구조에서
# 조상 탐색만으로는 하네스를 못 찾아요 (.ax 가 *하위* 에 있으니까).
VN=$(mktemp -d)
mkdir -p "$VN/.claude" "$VN/projects/app/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,vendor-skills}.sh "$VN/projects/app/.ax/scripts/bash/"

# 포인터 없으면 저장소 루트에서 못 찾아야 (문제 재현)
if (cd "$VN" && GOAX_PROJECT_DIR= CLAUDE_PROJECT_DIR= bash -c \
      "source projects/app/.ax/scripts/bash/common.sh; find_project_root" >/dev/null 2>&1); then
    fail "vendor — 포인터 없이도 찾아짐 (테스트 전제가 깨짐)"
else
    pass "vendor — 포인터 없으면 저장소 루트에서 하네스 미발견 (전제 확인)"
fi

VN_OUT=$(cd "$VN/projects/app" && GOAX_PROJECT_DIR="$VN/projects/app" \
    bash .ax/scripts/bash/vendor-skills.sh --plugin-dir "$REPO" --json 2>/dev/null)
echo "$VN_OUT" | jq -e '.result.split == true and .result.pointer_written == true' >/dev/null 2>&1 \
    && pass "vendor — 루트 분리 감지 + .goax-root 포인터 작성" \
    || fail "vendor — 모노레포 분리 처리 실패: $VN_OUT"

[ -d "$VN/.claude/skills" ] && [ -d "$VN/.claude/agents" ] \
    && pass "vendor — skills/agents 가 ADE 루트의 .claude/ 로 동봉" \
    || fail "vendor — 동봉 위치가 ADE 루트가 아님"

# 포인터가 실제로 문제를 푸는가
VN_RESOLVED=$(cd "$VN" && GOAX_PROJECT_DIR= CLAUDE_PROJECT_DIR= bash -c \
    "source projects/app/.ax/scripts/bash/common.sh; find_project_root" 2>/dev/null)
[ "$VN_RESOLVED" = "$VN/projects/app" ] \
    && pass "vendor — 포인터로 저장소 루트에서 하네스 해결" \
    || fail "vendor — 포인터가 있어도 해결 실패 ($VN_RESOLVED)"

# 사용자 자기 스킬 보존
mkdir -p "$VN/.claude/skills/my-own" && echo mine > "$VN/.claude/skills/my-own/SKILL.md"
(cd "$VN/projects/app" && GOAX_PROJECT_DIR="$VN/projects/app" \
    bash .ax/scripts/bash/vendor-skills.sh --plugin-dir "$REPO" --json >/dev/null 2>&1)
[ "$(cat "$VN/.claude/skills/my-own/SKILL.md" 2>/dev/null)" = "mine" ] \
    && pass "vendor — 사용자가 만든 skill 보존" \
    || fail "vendor — 사용자 skill 을 덮어씀"

# stale 감지
echo "0.0.1" > "$VN/.claude/.goax-vendored"
(cd "$VN/projects/app" && GOAX_PROJECT_DIR="$VN/projects/app" \
    bash .ax/scripts/bash/vendor-skills.sh --check --plugin-dir "$REPO" --json 2>/dev/null) \
    | jq -e '.result.stale == true' >/dev/null 2>&1 \
    && pass "vendor --check — 낡은 동봉본 감지" \
    || fail "vendor --check — stale 미감지"
rm -rf "$VN"

# 단일 저장소면 포인터를 만들지 않아야 (불필요한 파일 금지)
VS=$(mktemp -d)
mkdir -p "$VS/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,vendor-skills}.sh "$VS/.ax/scripts/bash/"
(cd "$VS" && GOAX_PROJECT_DIR="$VS" bash .ax/scripts/bash/vendor-skills.sh \
    --plugin-dir "$REPO" --json >/dev/null 2>&1)
[ ! -f "$VS/.goax-root" ] \
    && pass "vendor — 단일 저장소엔 .goax-root 안 만듦" \
    || fail "vendor — 불필요한 .goax-root 생성"

# --dry-run 은 아무것도 쓰지 않아야
VD=$(mktemp -d)
mkdir -p "$VD/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,vendor-skills}.sh "$VD/.ax/scripts/bash/"
(cd "$VD" && GOAX_PROJECT_DIR="$VD" bash .ax/scripts/bash/vendor-skills.sh \
    --plugin-dir "$REPO" --dry-run --json >/dev/null 2>&1)
[ ! -d "$VD/.claude" ] \
    && pass "vendor --dry-run — 파일 생성 안 함" \
    || fail "vendor --dry-run 이 .claude/ 를 만듦"
rm -rf "$VS" "$VD"

# ───────────────────────────────────────────────────────────
section "24. Layer 2·3 자동 주입 (module-rules-inject)"
# ───────────────────────────────────────────────────────────
# 하네스 테제는 "환경으로 통제한다" 인데, Layer 2(module)·3(spec/ADR) 은
# 자동 주입 경로가 없어서 모델이 읽기로 *선택* 해야만 들어왔어요.
L23=$(mktemp -d)
mkdir -p "$L23"/.ax/hooks/pre-edit "$L23"/.ax/scripts/bash \
         "$L23"/.ax/modules/order "$L23"/.ax/docs/spec/012-x "$L23"/.ax/docs/adr
cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$L23/.ax/scripts/bash/"
cp "$REPO/templates/default/.ax/hooks/pre-edit/module-rules-inject.sh" "$L23/.ax/hooks/pre-edit/"
printf -- '---\nmodule: order\npaths:\n  - "services/order/**"\n---\n# order\n' > "$L23/.ax/modules/order/rules.md"
printf -- '# Spec\n.ax/docs/adr/0008-x.md 참고\n' > "$L23/.ax/docs/spec/012-x/spec.md"
: > "$L23/.ax/docs/adr/0008-x.md"
echo '{"phase":"implementing","spec_dir":".ax/docs/spec/012-x"}' > "$L23/.ax/current-task.json"

l23_ctx() {
    printf '{"tool_input":{"file_path":"%s"}}' "$1" \
      | CLAUDE_PROJECT_DIR=$L23 bash "$L23/.ax/hooks/pre-edit/module-rules-inject.sh" 2>/dev/null \
      | jq -r '.hookSpecificOutput.additionalContext // ""'
}

OUT_L2=$(l23_ctx "$L23/services/order/OrderService.kt")
echo "$OUT_L2" | grep -q 'Layer 2 · order' \
    && pass "Layer 2 — 편집 파일에 매칭되는 module rules 경로 주입" \
    || fail "Layer 2 — module rules 미주입"
echo "$OUT_L2" | grep -q 'Layer 3 · spec' \
    && pass "Layer 3 — 진행 중 spec 경로 주입" \
    || fail "Layer 3 — 활성 spec 미주입"
echo "$OUT_L2" | grep -q '0008-x.md' \
    && pass "Layer 3 — spec 이 인용한 ADR 만 주입" \
    || fail "Layer 3 — 인용 ADR 미주입"

# 본문이 아니라 경로만 (B-pointer) — 룰 전문이 들어가면 컨텍스트가 터져요
echo "$OUT_L2" | grep -q '^# order' \
    && fail "Layer 2 — 룰 본문이 통째로 주입됨 (경로만 넣어야)" \
    || pass "Layer 2·3 — 본문이 아니라 경로만 주입 (B-pointer)"

# 무관 파일은 Layer 2 가 안 붙어야
l23_ctx "$L23/web/other.ts" | grep -q 'Layer 2' \
    && fail "Layer 2 — 매칭 안 되는 파일에 주입됨" \
    || pass "Layer 2 — 무관 경로엔 주입 안 함"

# .ax/ 자기 자신 편집엔 주입 안 함
[ -z "$(l23_ctx "$L23/.ax/config.yml")" ] \
    && pass "Layer 2·3 — .ax/ 자체 편집엔 주입 안 함" \
    || fail "Layer 2·3 — 하네스가 자기 자신에 주입함"

# phase=idle 이면 Layer 3 는 빠지고 Layer 2 만
echo '{"phase":"idle"}' > "$L23/.ax/current-task.json"
IDLE_OUT=$(l23_ctx "$L23/services/order/OrderService.kt")
if echo "$IDLE_OUT" | grep -q 'Layer 2' && ! echo "$IDLE_OUT" | grep -q 'Layer 3'; then
    pass "Layer 3 — phase=idle 이면 주입 안 함 (Layer 2 는 유지)"
else
    fail "Layer 3 — idle 상태에서도 spec 을 주입함"
fi
rm -rf "$L23"

# 출고 자산이 주입에 필요한 paths: 를 실제로 담고 있는가
# (훅은 paths: 를 읽는데 템플릿·preset 이 그 필드를 안 담으면 주입이 영영 안 돌아요)
PATHS_MISSING=0
for f in "$REPO"/templates/presets/starter/.ax/spirit/rules/*.md; do
    awk '/^---$/{c++; if(c==2) exit} c==1 && /^paths:/{found=1} END{exit !found}' "$f" \
        || { fail "starter preset 룰에 paths: 없음 — 자동 주입 대상이 안 됨: $(basename "$f")"; PATHS_MISSING=1; }
done
for t in "$REPO"/templates/default/.ax/_templates/spirit/rule.md \
         "$REPO"/templates/default/.ax/_templates/module/rules.md; do
    awk '/^---$/{c++; if(c==2) exit} c==1 && /^paths:/{found=1} END{exit !found}' "$t" \
        || { fail "템플릿에 paths: 없음 — 사용자가 만든 룰이 주입 안 됨: $(basename "$(dirname "$t")")/$(basename "$t")"; PATHS_MISSING=1; }
done
[ "$PATHS_MISSING" -eq 0 ] && pass "출고 룰 템플릿·preset 전부 paths: 보유 (주입 가능 상태)"

# ───────────────────────────────────────────────────────────
section "23. 모든 skill 에 슬래시 트리거 표기"
# ───────────────────────────────────────────────────────────
# 자연어 트리거만으로는 안 잡히는 경우가 실제로 있었어요 — 프로덕션 사용자가
# 로컬 복사본에 '/adr'·'/spec-implement' 를 손으로 추가했음. autorouting 이
# 실패해도 사용자가 확실히 부를 수 있는 경로가 description 에 있어야 해요.
SLASH_MISSING=0
for sdir in "$REPO"/skills/*/; do
    sname=$(basename "$sdir")
    if ! sed -n '/^description:/p' "$sdir/SKILL.md" | grep -qF "'/$sname'"; then
        fail "skill description 에 슬래시 트리거 누락: $sname ('/$sname')"
        SLASH_MISSING=$((SLASH_MISSING+1))
    fi
done
[ "$SLASH_MISSING" -eq 0 ] && pass "모든 skill description 에 '/<name>' 트리거 존재"

# ───────────────────────────────────────────────────────────
section "22. agents/ 프롬프트 규율 — 검증자 성립 조건"
# ───────────────────────────────────────────────────────────
# 일을 한 에이전트가 자기 결과를 채점하면 리뷰가 무의미해지고,
# "틈을 찾으라"는 지시만 받은 리뷰어는 멀쩡한 일에도 뭔가를 만들어 내요.
# 두 규율이 evaluator 프롬프트에 실제로 적혀 있어야 해요.

if grep -q '새 컨텍스트' "$REPO/agents/evaluator.md"; then
    pass "evaluator — fresh context 성립 조건 명시"
else
    fail "evaluator — 구현 세션이 자기 결과를 평가하는 걸 막는 문구 없음"
fi

if grep -qE '0건|아무것도 없음' "$REPO/agents/evaluator.md"; then
    pass "evaluator — '발견 0건' 이 정상 결과임을 명시"
else
    fail "evaluator — 빈손 보고를 허용하지 않아 과잉 지적 유발"
fi

if grep -q '재현 시나리오' "$REPO/agents/evaluator.md"; then
    pass "evaluator — 지적에 재현 시나리오 요구"
else
    fail "evaluator — 근거 없는 인상평을 걸러낼 기준 없음"
fi

# 두 agent 모두 spirit 로드 선언이 있어야 (skills 와 동일 규약)
for a in architect evaluator; do
    grep -q '시작 전 필수' "$REPO/agents/$a.md" \
        && pass "agents/$a — 시작 전 필수 (spirit 로드) 선언" \
        || fail "agents/$a — 시작 전 필수 선언 누락"
done

# ───────────────────────────────────────────────────────────
section "21. spec-implement 완료 마킹이 실제 tasks.md 형식과 맞는가"
# ───────────────────────────────────────────────────────────
# 출고 템플릿은 `- [ ] **T001** — ...` (볼드) 인데, 마킹 sed 가 `- [ ] [T020]`
# (대괄호) 를 기대해서 서로 안 맞았음 — 출고된 마킹 명령이 동작하지 않았어요.
# 실사용 리포는 `**T002 [P]**` 형식까지 씀. 세 형식 모두 커버해야 해요.

MK_FX=$(mktemp -d)
cat > "$MK_FX/tasks.md" <<'MKEOF'
- [ ] **T001** — 출고 템플릿 형식 (볼드)
- [ ] **T002 [P]** — 실사용 형식 (P 마커)
- [ ] [T003] 구 대괄호 형식
- [ ] **T0011** — 자리수 다른 별개 task
MKEOF

mark_task() {   # $1 = TASK_ID, $2 = file — SKILL.md 에 적힌 것과 동일한 식
    sed -E "/^- \[ \] .*$1([^0-9A-Za-z]|\$)/ s/^- \[ \]/- [x]/" "$2"
}

MK_OK=1
for tid in T001 T002 T003; do
    mark_task "$tid" "$MK_FX/tasks.md" | grep -qE "^- \[x\] .*$tid" \
        || { fail "완료 마킹 — $tid 형식 매칭 실패"; MK_OK=0; }
done
# 접두 오매칭 방지: T001 마킹이 T0011 을 건드리면 안 됨
if mark_task T001 "$MK_FX/tasks.md" | grep -qE '^- \[x\] \*\*T0011'; then
    fail "완료 마킹 — T001 이 T0011 을 잘못 체크함"; MK_OK=0
fi
[ "$MK_OK" -eq 1 ] && pass "spec-implement 완료 마킹 — 볼드/대괄호/[P] 3형식 + 접두 오매칭 방지"

# 하드코딩된 예시 ID 가 실행 위치에 남아 있으면 안 돼요 (그대로 복사될 위험)
if grep -qE "^sed .*\[T[0-9]{3}\]" "$REPO/skills/spec-implement/SKILL.md"; then
    fail "spec-implement — 마킹 sed 에 하드코딩된 task ID 잔존"
else
    pass "spec-implement — 마킹 sed 가 TASK_ID 변수 사용"
fi
rm -rf "$MK_FX"

# ───────────────────────────────────────────────────────────
section '20. MANIFEST `->` = stateful seed-only 계약'
# ───────────────────────────────────────────────────────────
# up 은 "install or idempotent update" 라 재실행이 destructive 하면 안 돼요.
# `->` 대상은 런타임 상태(state.json / current-task.json)이고, 덮어쓰면
# 진행 중인 phase·spec_dir 가 idle 로 리셋돼 작업 맥락이 사라져요.

# (1) 재실행이 런타임 상태·사용자 수정본을 보존하는가 — **실제로 두 번 돌려서** 확인.
#     예전엔 up/SKILL.md 를 grep 하는 문자열 매칭이었는데, 그건 "그 문장이 있다" 만
#     보증하고 "그렇게 동작한다" 는 보증 못 해요. 지금은 provision.sh 를 진짜 실행해요.
PROV_T=$(mktemp -d)
bash "$REPO/scripts/provision.sh" --target "$PROV_T" --json >/dev/null 2>&1
if [ -f "$PROV_T/.ax/current-task.json" ] && [ -f "$PROV_T/.ax/_templates/spec/spec.md" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq '.phase="implementing"' "$PROV_T/.ax/current-task.json" > "$PROV_T/ct.tmp" \
            && mv "$PROV_T/ct.tmp" "$PROV_T/.ax/current-task.json"
    else
        printf '{"phase":"implementing"}\n' > "$PROV_T/.ax/current-task.json"
    fi
    printf '\n## 팀 전용 섹션\n' >> "$PROV_T/.ax/_templates/spec/spec.md"

    bash "$REPO/scripts/provision.sh" --target "$PROV_T" --json >/dev/null 2>&1

    if grep -q 'implementing' "$PROV_T/.ax/current-task.json" 2>/dev/null; then
        pass "provision 재실행 — 진행 중 phase 보존 (MANIFEST \`->\` seed-only)"
    else
        fail "provision 재실행이 phase 를 리셋했어요 (진행 중 spec 이 추적에서 빠져요)"
    fi
    if grep -q '팀 전용 섹션' "$PROV_T/.ax/_templates/spec/spec.md" 2>/dev/null; then
        pass "provision 재실행 — _templates 사용자 수정본 보존"
    else
        fail "provision 재실행이 _templates 사용자 수정본을 덮었어요"
    fi
else
    fail "provision.sh 설치 실패 — current-task.json / _templates 미생성"
fi
rm -rf "$PROV_T"

# (2) `->` 대상은 전부 런타임 상태여야 해요 (.gitignore.template 에 등재).
#     seed-only 는 "덮지 않는다" 는 뜻이라, 갱신이 필요한 자산을 여기 넣으면
#     plugin 업데이트가 그 파일에 영원히 반영되지 않아요.
MF_SEED_BAD=0
while IFS= read -r mline; do
    case "$mline" in ''|\#*) continue ;; esac
    case "$mline" in *" -> "*) ;; *) continue ;; esac
    mdst="${mline##* -> }"
    if ! grep -qF "$mdst" "$REPO/templates/default/.gitignore.template"; then
        fail "MANIFEST \`->\` 대상이 런타임 상태가 아님: $mdst (.gitignore.template 에 없음)"
        MF_SEED_BAD=$((MF_SEED_BAD+1))
    fi
done < "$REPO/templates/default/MANIFEST"
[ "$MF_SEED_BAD" -eq 0 ] && pass "MANIFEST \`->\` 대상 전부 런타임 상태 (seed-only 적합)"

# (3) check-manifest-install.sh 도 같은 해석이어야 (drift 를 정상으로 취급)
grep -q 'stateful' "$REPO/templates/default/.ax/scripts/bash/check-manifest-install.sh" \
    && pass "check-manifest-install — \`->\` stateful 해석 일치" \
    || fail "check-manifest-install — \`->\` 를 stateful 로 취급하지 않음"

# ───────────────────────────────────────────────────────────
section "19. bash 호환 lint — macOS(3.2) 에선 통과하고 Linux(5.x) 에선 터지는 문법"
# ───────────────────────────────────────────────────────────
# `${#ARR[@]:-0}` 는 bash 3.2 가 조용히 0 을 반환해서 macOS 로컬에선 절대 안 보이고,
# bash 5.x(= CI ubuntu-latest) 에서만 "bad substitution" 으로 죽어요.
# 배열이 `ARR=()` 로 선언돼 있으면 `${#ARR[@]}` 만으로 두 버전 모두 안전해요.
BASHLINT=0
while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    fail "bash 호환 lint — \${#ARR[@]:-...} 는 bash 5.x 에서 bad substitution: $hit"
    BASHLINT=$((BASHLINT+1))
done < <(grep -rn '\${#[A-Za-z_][A-Za-z0-9_]*\[@\*\]:-' \
            "$REPO/templates" "$REPO/tests" "$REPO/.claude" \
            "$REPO/skills" "$REPO/commands" 2>/dev/null || true)
# 반대 방향(3.2 에서만 터지는 문법 — 예: $( ) 안의 case)은 §7·§30 의 `bash -n` 이
# macOS 매트릭스 잡에서 잡아요. 두 OS 를 다 돌리는 이유가 이 양방향이에요.
[ "$BASHLINT" -eq 0 ] && pass "bash 호환 lint — \${#ARR[@]:-...} 잔재 0"

# ───────────────────────────────────────────────────────────
section "18. 버전 마커 lint — 플러그인 문서/코드에 (NEW n.n)·(n.n.n)·n.n.n+ 잔재 금지"
# ───────────────────────────────────────────────────────────
# repo CLAUDE.md 컨벤션: 버전 마커는 changelog/ 에만 존재해야 함 (rot 방지).
# 정당한 외부 참조(예: 서드파티 이슈 트래커 버전)만 파일 단위로 예외 허용.
declare -a VERSION_LINT_EXEMPT_FILES=()

VLINT_OUT=$(grep -rEn '\(NEW [0-9]|\(0\.[0-9]+\.[0-9]+|[0-9]\.[0-9]+\.[0-9]+\+' \
    --include='*.md' --include='*.sh' \
    "$REPO/skills" "$REPO/commands" "$REPO/templates" "$REPO/docs" "$REPO/agents" 2>/dev/null || true)

vlint_violation_count=0
if [ -n "$VLINT_OUT" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        filepath="${line%%:*}"
        exempt=false
        if [ "${#VERSION_LINT_EXEMPT_FILES[@]}" -gt 0 ]; then
            for ex in "${VERSION_LINT_EXEMPT_FILES[@]}"; do
                [ "$filepath" = "$ex" ] && exempt=true && break
            done
        fi
        if [ "$exempt" = false ]; then
            fail "버전 마커 잔재: ${line#$REPO/}"
            vlint_violation_count=$((vlint_violation_count+1))
        fi
    done <<< "$VLINT_OUT"
fi
[ "$vlint_violation_count" -eq 0 ] && pass "버전 마커 lint — skills/commands/templates/docs/agents 잔재 0"

smoke_done
