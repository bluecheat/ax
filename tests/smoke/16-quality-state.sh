#!/usr/bin/env bash
# tests/smoke/16-quality-state.sh — §58–§61 — 품질 설정 게이트 · mark-task · 위반 위치 · 작업별 상태
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/16-quality-state.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "58. 품질 설정 게이트 · 압축 스냅샷 · lint_file · detect-stack · config-set · plan_doc · 상시 로드 예산"
# ───────────────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    S58="$REPO/templates/default/.ax"
    Q=$(mktemp -d); mkdir -p "$Q/.ax/scripts/bash" "$Q/.ax/hooks" "$Q/src" "$Q/.husky" "$Q/config/lint" "$Q/.ax/docs/spec/2026-09-25-ab12-x" "$Q/.ax/mistakes"
    cp "$S58/scripts/bash/"*.sh "$Q/.ax/scripts/bash/"; cp -R "$S58/hooks/"* "$Q/.ax/hooks/"
    cp "$S58/config.yml" "$Q/.ax/config.yml"; cp "$S58/current-task.json.template" "$Q/.ax/current-task.json"
    git -C "$Q" init -q; git -C "$Q" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
    echo '{}' > "$Q/.eslintrc.json"; touch "$Q/src/a.ts" "$Q/.husky/pre-commit" "$Q/config/lint/x.xml"

    # 품질 설정 게이트 — 기존 파일 첫 편집만 막고, 같은 파일 재편집·새 파일·일반 파일은 통과
    qg() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' "$1" "$2" "${3-q1}" \
        | CLAUDE_PROJECT_DIR="$Q" bash "$Q/.ax/hooks/pre-edit/quality-config-gate.sh" 2>/dev/null; echo $?; }
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh --add sensors.quality_configs 'config/lint/**' >/dev/null)
    R1=$(qg Edit "$Q/.eslintrc.json"); R2=$(qg Edit "$Q/.eslintrc.json"); R3=$(qg Edit "$Q/src/a.ts"); R4=$(qg Write "$Q/biome.json")
    R5=$(qg Edit "$Q/.husky/pre-commit"); R6=$(qg Edit "$Q/config/lint/x.xml"); R7=$(qg Edit "$Q/.eslintrc.json" "")
    [ "$R1$R2$R3$R4$R5$R6$R7" = "2000220" ] \
        && pass "quality-config-gate — 기존 품질 설정 첫 편집만 막고 재편집·새 파일·일반 파일 통과, .husky/·quality_configs 글롭 적용, 세션 없으면 경고만" \
        || fail "quality-config-gate 판정: $R1$R2$R3$R4$R5$R6$R7 (기대 2000220)"

    # 압축 스냅샷 — PreCompact 가 사실을 적고, compact 직후 SessionStart 가 한 번만 앞에 붙여요
    printf -- '- [x] T001 a\n- [ ] T002 환불 API\n' > "$Q/.ax/docs/spec/2026-09-25-ab12-x/tasks.md"
    (cd "$Q" && bash .ax/scripts/bash/update-task.sh --phase implementing --set spec_dir=.ax/docs/spec/2026-09-25-ab12-x --set plan_doc=.omc/plans/p.md >/dev/null)
    printf '{"session_id":"C1","trigger":"auto"}' | CLAUDE_PROJECT_DIR="$Q" bash "$Q/.ax/hooks/pre-compact/snapshot.sh"
    SB1=$(printf '{"session_id":"C1","source":"compact"}' | CLAUDE_PROJECT_DIR="$Q" bash "$Q/.ax/hooks/session-start/session-brief.sh" | jq -r '.hookSpecificOutput.additionalContext')
    SB2=$(printf '{"session_id":"C1","source":"compact"}' | CLAUDE_PROJECT_DIR="$Q" bash "$Q/.ax/hooks/session-start/session-brief.sh" | jq -r '.hookSpecificOutput.additionalContext // ""')
    echo "$SB1" | grep -q '압축 직전: spec .ax/docs/spec/2026-09-25-ab12-x — tasks 1/2 · 다음: T002 환불 API' \
        && echo "$SB1" | grep -q '압축 직전: 커밋 안 된 변경' && ! echo "$SB2" | grep -q '압축 직전' \
        && pass "PreCompact 스냅샷 — tasks 진행률·바뀐 파일을 적고 compact 직후 한 번만 브리핑 앞에" \
        || fail "압축 스냅샷: $SB1 / 두 번째: $SB2"
    [ "$(jq -r .plan_doc "$Q/.ax/current-task.json")" = ".omc/plans/p.md" ] \
        && pass "update-task.sh --set plan_doc — 외부 계획 문서 경로를 정식 필드로" || fail "plan_doc 이 안 적혔어요"

    # 재발 — 미처리 mistakes 중 같은 category 2건 이상
    for i in 1 2 3; do printf -- '---\ncategory: process\nstatus: open\n---\n' > "$Q/.ax/mistakes/2026-09-2$i-x.md"; done
    printf -- '---\ncategory: api\nstatus: open\n---\n' > "$Q/.ax/mistakes/2026-09-24-y.md"
    (cd "$Q" && bash .ax/scripts/bash/session-brief.sh --json) | jq -r '.result.lines[]' | grep -q '같은 종류 실수 재발: process ×3 —' \
        && pass "session-brief — 같은 category 재발(≥2)만 알려요" || fail "session-brief 재발 줄이 없어요"

    # lint_file — 첫 매칭 글롭만, 실패하면 additionalContext, 비면 아무것도 안 함
    lf() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_PROJECT_DIR="$Q" bash "$Q/.ax/hooks/post-edit/lint-changed.sh"; }
    [ -z "$(lf "$Q/src/a.ts")" ] || fail "lint_file 비었는데 lint-changed 가 뭔가 했어요"
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh --add commands.lint_file '**/*.ts => grep -q ok {file}' >/dev/null)
    LO=$(lf "$Q/src/a.ts"); echo ok > "$Q/src/a.ts"; LO2=$(lf "$Q/src/a.ts")
    [ "$(echo "$LO" | jq -r .hookSpecificOutput.hookEventName)" = PostToolUse ] \
        && echo "$LO" | jq -r .hookSpecificOutput.additionalContext | grep -q 'lint 실패 — src/a.ts' && [ -z "$LO2" ] \
        && pass "lint-changed — commands.lint_file 로만 돌고 실패는 additionalContext 로 모델에게 (스택 추측 없음)" \
        || fail "lint-changed: $LO / $LO2"

    # config-set — 없는 키 거부 · 스칼라 · 리스트 add/clear 왕복
    cp "$S58/config.yml" "$Q/.ax/config.yml"
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh commands.nope x >/dev/null 2>&1); CSR=$?
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh commands.test "pnpm test" >/dev/null \
        && bash .ax/scripts/bash/config-set.sh --add commands.lint_file 'a => 1' >/dev/null \
        && bash .ax/scripts/bash/config-set.sh --add commands.lint_file 'b => 2' >/dev/null \
        && bash .ax/scripts/bash/config-set.sh --add commands.lint_file 'a => 1' >/dev/null)
    CSL=$( (cd "$Q" && source .ax/scripts/bash/common.sh && goax_yaml_list .ax/config.yml lint_file) | paste -sd '|' -)
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh --clear commands.lint_file >/dev/null && bash .ax/scripts/bash/config-set.sh commands.test "" >/dev/null)
    [ "$CSR" = 1 ] && [ "$CSL" = "a => 1|b => 2" ] && diff <(sed 's/^  test: .*/  test:/' "$S58/config.yml") <(sed 's/^  test: .*/  test:/' "$Q/.ax/config.yml") >/dev/null \
        && pass "config-set — 없는 키 거부, 리스트 add(중복 무시)·clear, 원래 파일로 왕복" \
        || fail "config-set: rc=$CSR list=$CSL $(diff "$S58/config.yml" "$Q/.ax/config.yml" | head -5)"

    # 리뷰 회귀 — 백슬래시 값 보존(awk -v 금지) · 스칼라/리스트 형태가 다르면 거부 · 따옴표로 끝나는 명령 · & 들어간 파일명
    cp "$S58/config.yml" "$Q/.ax/config.yml"
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh commands.lint 'ruff --select E\d src\new' >/dev/null)
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh --add sensors.disabled_hooks spec-gate >/dev/null)
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh sensors.disabled_hooks x >/dev/null 2>&1); T1=$?
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh --add commands.test foo >/dev/null 2>&1); T2=$?
    (cd "$Q" && bash .ax/scripts/bash/config-set.sh --add commands.lint_file '**/*.ts => printf "%s" {file} > lintarg; test "x" = "y"' >/dev/null)
    grep -qxF '  lint: "ruff --select E\d src\new"' "$Q/.ax/config.yml" && [ "$T1" = 1 ] && [ "$T2" = 1 ] \
        && [ "$( (cd "$Q" && source .ax/scripts/bash/common.sh && goax_yaml_list .ax/config.yml disabled_hooks) )" = spec-gate ] \
        && pass "config-set — 백슬래시 보존, 리스트에 set · 스칼라에 --add 는 거부 (항목이 고아로 남지 않아요)" \
        || fail "config-set 회귀: $(grep -n '  lint:' "$Q/.ax/config.yml") T1=$T1 T2=$T2"
    mkdir -p "$Q/src/R&D"; : > "$Q/src/R&D/b c.ts"
    LO3=$(lf "$Q/src/R&D/b c.ts")
    [ "$(cat "$Q/lintarg" 2>/dev/null)" = 'src/R&D/b c.ts' ] && echo "$LO3" | grep -q 'lint 실패' \
        && pass "lint-changed — & · 공백 든 파일명이 한 인자로 ({file} 치환, patsub_replacement), 따옴표로 끝나는 명령도 그대로" \
        || fail "lint-changed 파일명 인용: arg=$(cat "$Q/lintarg" 2>/dev/null) out=$LO3"

    # detect-stack — 선언된 것에서만
    printf '{"scripts":{"build":"x","test":"y"},"devDependencies":{"eslint":"9"}}' > "$Q/package.json"; touch "$Q/pnpm-lock.yaml"
    printf 'lint:\n\techo\n' > "$Q/Makefile"
    DS=$( (cd "$Q" && bash .ax/scripts/bash/detect-stack.sh --json) )
    [ "$(echo "$DS" | jq -r '.result.candidates.build[0]')" = "pnpm build" ] && [ "$(echo "$DS" | jq -r '.result.candidates.lint[0]')" = "make lint" ] \
        && [ "$(echo "$DS" | jq -r '.result.candidates.typecheck | length')" = 0 ] \
        && echo "$DS" | jq -r '.result.candidates.lint_file[]' | grep -qx '\*\*/\*.ts => pnpm exec eslint --quiet {file}' \
        && pass "detect-stack — package.json scripts·lockfile·Makefile 타깃·선언된 도구에서만 후보 (없는 typecheck 는 안 지어요)" \
        || fail "detect-stack: $(echo "$DS" | jq -c .result.candidates)"

    # doctor-scan 상시 로드 예산 — CLAUDE.md 의 @import 를 따라가요
    printf '@AGENTS.md\n' > "$Q/CLAUDE.md"; head -c 40000 /dev/zero | tr '\0' 'x' > "$Q/AGENTS.md"; printf '\n@.ax/spirit/big.md\n' >> "$Q/AGENTS.md"
    mkdir -p "$Q/.ax/spirit"; head -c 1000 /dev/zero | tr '\0' 'y' > "$Q/.ax/spirit/big.md"
    BU=$( (cd "$Q" && bash .ax/scripts/bash/doctor-scan.sh --json 2>/dev/null) | jq -c '.result.budget')
    [ "$(echo "$BU" | jq -r '.files | length')" = 3 ] && [ "$(echo "$BU" | jq -r .over)" = true ] \
        && pass "doctor-scan budget — CLAUDE.md → @AGENTS.md → @import 를 따라 바이트 합산, 경고 선 초과 표시" \
        || fail "doctor-scan budget: $BU"
    rm -rf "$Q"
else
    pass "§58 — jq/git 없음, skip"
fi

# ───────────────────────────────────────────────────────────
section "59. mark-task — 체크박스는 줄 앞 ID 만, 펜스 밖에서만, 하나만 켜요"
# ───────────────────────────────────────────────────────────
# 인라인 sed(`.*T013`)는 본문에 다른 task 를 언급한 줄까지 켰어요 (실측 3건). 템플릿 펜스 안 예시는 --next 가 집었어요.
MT=$(mktemp -d); mkdir -p "$MT/.ax/scripts/bash" "$MT/.ax/docs/spec/2026-09-25-ab12-x"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,mark-task}.sh "$MT/.ax/scripts/bash/"
MTF="$MT/.ax/docs/spec/2026-09-25-ab12-x/tasks.md"
cat > "$MTF" <<'MTE'
## 한 줄 형식
```
- [ ] T001 [P] [AC2] <한 줄 설명>
```
- [x] T005 결제 상수
- [ ] T008 T005 의 상수와 맞춤
- [ ] **T009** — 환불 API
- [ ] T010 T009 가 셋 다 해소
- [ ] T0091 다른 것
MTE
mt() { (cd "$MT" && bash .ax/scripts/bash/mark-task.sh --spec 2026-09-25-ab12-x "$@" 2>/dev/null); }
N1=$(mt --next --json | jq -r .result.task)
mt --task T009 --json >/dev/null; R1=$?
mt --task T009 --json | jq -r .result.changed > "$MT/c2"
mt --task T0091 --state '~' --json >/dev/null
[ "$N1" = T008 ] && [ "$R1" = 0 ] && [ "$(cat "$MT/c2")" = false ] \
    && grep -qxF -- '- [x] **T009** — 환불 API' "$MTF" && grep -qxF -- '- [ ] T010 T009 가 셋 다 해소' "$MTF" \
    && grep -qxF -- '- [ ] T008 T005 의 상수와 맞춤' "$MTF" && grep -qxF -- '- [~] T0091 다른 것' "$MTF" \
    && grep -qxF -- '- [ ] T001 [P] [AC2] <한 줄 설명>' "$MTF" && [ ! -e "$MTF.lock" ] \
    && pass "mark-task — 줄 앞 ID 만 켜고 본문 언급·펜스 예시·T0091 은 그대로, 재실행은 변화 없음, --next 는 펜스 밖, 락 해제" \
    || fail "mark-task: next=$N1 rc=$R1 $(cat "$MTF" | tr '\n' '|')"
mt --task T404 --json >/dev/null; [ $? = 1 ] && pass "mark-task — 없는 ID 는 exit 1 (조용히 성공하지 않아요)" || fail "mark-task 없는 ID 가 성공했어요"
# 여러 ID — 트랜잭션: 하나라도 없으면 아무것도 안 켜고, 이미 켜진 것은 건너뛰어요
cp "$MTF" "$MT/before"
mt --task T008,T404 --json >/dev/null; MR=$?
[ "$MR" = 1 ] && cmp -s "$MTF" "$MT/before" \
    && pass "mark-task --task T008,T404 — 하나라도 없으면 exit 1 + 파일 무변경" || fail "mark-task 다중 ID 가 부분 적용됨 (rc=$MR)"
mt --task "T009, T008,T010,T008" --json | jq -e '.result.changed==true and .result.changed_tasks==["T008","T010"]
    and .result.unchanged_tasks==["T009"] and (.result.done_after - .result.done_before)==2' >/dev/null 2>&1 \
    && grep -qxF -- '- [x] T008 T005 의 상수와 맞춤' "$MTF" && grep -qxF -- '- [x] T010 T009 가 셋 다 해소' "$MTF" \
    && grep -qxF -- '- [~] T0091 다른 것' "$MTF" && [ ! -e "$MTF.lock" ] \
    && pass "mark-task --task T009,T008,T010 — 미완료만 켜고 이미 켜진 건 unchanged, 중복 ID 는 한 번" \
    || fail "mark-task 다중 ID: $(tr '\n' '|' < "$MTF")"
rm -rf "$MT"

# ───────────────────────────────────────────────────────────
section "60. 위반 위치 — 어느 모드든 경고마다 file:line 과 걸린 규칙, 요약 줄에도"
# ───────────────────────────────────────────────────────────
# 실측(one-tenth): 한 커밋은 파일 이름이 나왔고, 다른 커밋은 "⚠ CRITICAL 위반 1건 — 경고만 (mode=warning)"
# 한 줄만 보여서 위치를 diff 에서 손으로 찾았어요. 시크릿은 줄 없이 파일 이름만 찍었고, 요약 줄엔 위치가
# 없어서 출력이 잘리거나 섞이면 위치가 사라졌어요. 이제 위반마다 `file:line — 규칙` 이고, 요약 줄도 위치를 담아요.
VL=$(mktemp -d)
pushd "$VL" >/dev/null || fail "VL pushd 실패"
git init -q . >/dev/null 2>&1
mkdir -p .ax/scripts/bash .ax/hooks/pre-commit .ax/spirit/rules .ax/mistakes src
cp "$REPO/templates/default/.ax/scripts/bash/common.sh" .ax/scripts/bash/
cp "$REPO/templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh" .ax/hooks/pre-commit/
cp "$REPO/templates/default/.ax/hooks/pre-commit/check-mistake-secrets.sh" .ax/hooks/pre-commit/
printf '# C\n' > CLAUDE.md
cat > .ax/spirit/rules/vl.md <<'EOF'
---
category: vl
severity: critical
paths:
  - "src/**"
---
## SP-VL-001: console.log 금지
<!-- 검출 패턴: console\.log\( -->
EOF
printf 'const a = 1;\nconst b = 2;\nconsole.log(a);\n' > src/log.ts
printf 'export const x = 1;\nexport const password = "%s";\n' hunter2xyz99 > src/cfg.ts
printf 'line one\nline two\npg_key=%s\n' abcdefgh12345678 > .ax/mistakes/2026-10-01-secrets.md
git add -f src/log.ts src/cfg.ts .ax/mistakes/2026-10-01-secrets.md >/dev/null 2>&1
for vm in warning fail; do
    printf 'sensors:\n  mode: %s\n' "$vm" > .ax/config.yml
    VL_ERR=$(CLAUDE_PROJECT_DIR="$VL" bash .ax/hooks/pre-commit/critical-rule-grep.sh 2>&1 >/dev/null)
    VL_LAST=$(printf '%s\n' "$VL_ERR" | tail -1)
    { printf '%s' "$VL_ERR" | grep -q 'src/cfg.ts:2 — secrets:kv-detect' \
        && printf '%s' "$VL_ERR" | grep -q 'src/log.ts:3 — SP-VL-001'; } \
        && pass "critical-rule-grep (mode=$vm) — 위반마다 file:line — 규칙 (시크릿도 줄까지, 내용은 안 찍음)" \
        || fail "critical-rule-grep (mode=$vm) — 위반 줄에 file:line·규칙 없음: $VL_ERR"
    { printf '%s' "$VL_LAST" | grep -q 'src/cfg.ts:2' && printf '%s' "$VL_LAST" | grep -q 'src/log.ts:3'; } \
        && pass "critical-rule-grep (mode=$vm) — 요약 줄 하나만 보여도 위치가 있어요" \
        || fail "critical-rule-grep (mode=$vm) — 요약 줄에 위치 없음: $VL_LAST"
    printf '%s' "$VL_ERR" | grep -q 'hunter2xyz99' \
        && fail "critical-rule-grep (mode=$vm) — 시크릿 값이 출력에 샘" || true
    VM_ERR=$(CLAUDE_PROJECT_DIR="$VL" bash .ax/hooks/pre-commit/check-mistake-secrets.sh 2>&1 >/dev/null)
    { printf '%s' "$VM_ERR" | grep -q '\.ax/mistakes/2026-10-01-secrets\.md:3' \
        && printf '%s\n' "$VM_ERR" | tail -1 | grep -q '2026-10-01-secrets\.md:3'; } \
        && pass "check-mistake-secrets (mode=$vm) — file:line 을 목록과 요약 줄에" \
        || fail "check-mistake-secrets (mode=$vm) — 줄 번호 없음: $VM_ERR"
done
# 위치가 많으면 요약 줄은 앞 3개 + "외 N건" 으로 줄여요 (요약이 화면을 덮지 않게)
printf 'console.log(1);\nconsole.log(2);\nconsole.log(3);\nconsole.log(4);\nconsole.log(5);\n' > src/many.ts
git reset -q >/dev/null 2>&1; git add -f src/many.ts >/dev/null 2>&1
VL_MANY=$(CLAUDE_PROJECT_DIR="$VL" bash .ax/hooks/pre-commit/critical-rule-grep.sh 2>&1 >/dev/null | tail -1)
{ printf '%s' "$VL_MANY" | grep -q 'src/many.ts:3' && printf '%s' "$VL_MANY" | grep -q '외 2건' \
    && ! printf '%s' "$VL_MANY" | grep -q 'src/many.ts:4'; } \
    && pass "critical-rule-grep — 요약 줄은 앞 3곳 + 외 N건" \
    || fail "critical-rule-grep — 요약 줄 축약 실패: $VL_MANY"
popd >/dev/null || true
rm -rf "$VL"

# ───────────────────────────────────────────────────────────
section "61. 작업별 상태 — .ax/tasks/<id>.json, 병렬 작업이 서로 덮지 않아요"
# ───────────────────────────────────────────────────────────
PT=$(mktemp -d)
mkdir -p "$PT/.ax/scripts/bash" "$PT/.ax/hooks/pre-commit" "$PT/.ax/docs/spec/sa" "$PT/.ax/docs/spec/sb" "$PT/src"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,update-task,tier-from-state,reset-task,session-brief,tasks-gate}.sh "$PT/.ax/scripts/bash/"
cp "$REPO/templates/default/.ax/hooks/pre-commit/spec-completion-gate.sh" "$PT/.ax/hooks/pre-commit/"
cp "$REPO/templates/default/.ax/current-task.json.template" "$PT/.ax/current-task.json"
echo '{}' > "$PT/.ax/state.json"
pt_u() { GOAX_PROJECT_DIR="$PT" bash "$PT/.ax/scripts/bash/update-task.sh" "$@" --json 2>/dev/null; }
pt_r() { GOAX_PROJECT_DIR="$PT" bash "$PT/.ax/scripts/bash/reset-task.sh" "$@" --json 2>/dev/null; }
pt_c() { jq -r "$1" "$PT/.ax/current-task.json"; }
pt_u --start --phase triaged --set task_id=A --set description=결제 >/dev/null
pt_u --phase implementing --set spec_dir=.ax/docs/spec/sa >/dev/null
pt_u --start --phase triaged --set task_id=B --set description=검색 >/dev/null
[ "$(pt_c .task_id)" = B ] && [ "$(jq -r '.phase + " " + .spec_dir' "$PT/.ax/tasks/A.json")" = "implementing .ax/docs/spec/sa" ] \
    && pass "update-task --start — 새 작업이 지금 작업이 되고 앞 작업은 .ax/tasks/A.json 에 남아요" \
    || fail "update-task --start — 앞 작업 유실: $(cat "$PT/.ax/current-task.json" | jq -c '{task_id,phase}')"
PTJ=$(pt_u --task A --phase review)
{ [ "$(printf '%s' "$PTJ" | jq -r '.result.active')" = false ] && [ "$(pt_c '.task_id + " " + .phase')" = "B triaged" ] \
    && [ "$(jq -r .phase "$PT/.ax/tasks/A.json")" = review ] && [ "$(pt_c '.handoff | type')" = object ]; } \
    && pass "update-task --task A — 지금 작업(B)·handoff 는 그대로, A 파일만 갱신" \
    || fail "update-task --task — 다른 작업을 덮음: $PTJ"
pt_u --task Z --phase review >/dev/null; [ $? -eq 1 ] && [ ! -f "$PT/.ax/tasks/Z.json" ] \
    && pass "update-task --task <없는 id> — exit 1 · 파일을 만들지 않아요" || fail "update-task — 없는 작업을 만들었어요"
# 진행 중 작업이 여럿인데 --task 가 없으면 어느 세션 것인지 몰라요 — 덮지 않고 되물어요
PTN=$(pt_u --phase implementing); [ "$(printf '%s' "$PTN" | jq -r .status)" = error ] && [ "$(pt_c .phase)" = triaged ] \
    && pass "update-task — 진행 중 작업이 여럿이면 --task 없는 갱신은 거부 (지금 작업 그대로)" || fail "update-task — --task 없이 덮었어요: $PTN"
pt_u --start --set task_id=A >/dev/null; [ "$(jq -r .description "$PT/.ax/tasks/A.json")" = 결제 ] && [ "$(pt_c .task_id)" = B ] \
    && pass "update-task --start — 이미 있는 id 는 거부 (옛 기록 위에 병합하지 않아요)" || fail "update-task --start — 같은 id 로 덮었어요"
[ "$(pt_u --task 'a/b' --phase spec | jq -r .status)" = error ] && [ "$(pt_u --task NOPE --phase spec --dry-run | jq -r .status)" = error ] \
    && pass "update-task — 잘못된 id 거부 · --dry-run 도 없는 작업은 error" || fail "update-task — id 검증/dry-run 대상 확인 실패"
pt_u --task B --set spec_dir=.ax/docs/spec/sb --phase implementing >/dev/null
SB_OUT=$(GOAX_PROJECT_DIR="$PT" bash "$PT/.ax/scripts/bash/session-brief.sh" --json 2>/dev/null)
printf '%s' "$SB_OUT" | jq -e '(.result.other_tasks | map(.task_id)) == ["A"] and (.result.lines | map(select(test("다른 진행 중 작업"))) | length) == 1' >/dev/null \
    && pass "session-brief — 병렬 작업(A)을 다른 진행 중 작업으로 알려요" || fail "session-brief — other_tasks 누락: $(printf '%s' "$SB_OUT" | jq -c .result.other_tasks)"
# 완료 게이트는 진행 중 작업 전부의 spec 을 봐요 — 지금 작업이 B 여도 A 의 spec 을 건드리는 커밋은 걸려요
printf '## 3. \n- [ ] **AC1** a\n' > "$PT/.ax/docs/spec/sa/spec.md"; printf -- '- [ ] T001 [AC1] a — files: src/a.ts\n' > "$PT/.ax/docs/spec/sa/tasks.md"
printf '## 3. \n- [ ] **AC1** a\n' > "$PT/.ax/docs/spec/sb/spec.md"; printf -- '- [ ] T001 [AC1] b — files: src/b.ts\n' > "$PT/.ax/docs/spec/sb/tasks.md"
echo x > "$PT/src/a.ts"; git -C "$PT" init -q 2>/dev/null; git -C "$PT" add src/a.ts 2>/dev/null
PG_OUT=$(cd "$PT" && CLAUDE_PROJECT_DIR="$PT" bash "$PT/.ax/hooks/pre-commit/spec-completion-gate.sh" 2>&1)
{ printf '%s' "$PG_OUT" | grep -q 'spec sa — 0/1 완료' && printf '%s' "$PG_OUT" | grep -q 'spec sb 미완료 1 — 이번 커밋과 무관해 건너뛰어요'; } \
    && pass "spec-completion-gate — 병렬 작업의 spec 도 봐요 (A 의 spec 은 자세히 · B 는 무관해 한 줄)" \
    || fail "spec-completion-gate — 병렬 작업 spec 판정 실패: $PG_OUT"
# G6 — 지금 작업이 아닌 spec 도 그 작업의 size×risk 로 evaluator 필수를 판정해요
pt_u --task A --set size=L --set risk=L2 >/dev/null
GOAX_PROJECT_DIR="$PT" bash "$PT/.ax/scripts/bash/tasks-gate.sh" --spec sa --json 2>/dev/null | jq -e '.result.review_required == true' >/dev/null \
    && pass "tasks-gate G6 — 병렬 작업(지금 작업 아님)의 spec 도 evaluator 필수 판정" || fail "tasks-gate G6 — 비활성 작업 spec 의 필수 판정이 빠짐"
# 오래 멈춘 작업 — 완료 게이트는 건너뛰고 session-brief 는 정리하라고 알려요
PG_OLD=$(cd "$PT" && GOAX_TASK_TTL_DAYS=0 CLAUDE_PROJECT_DIR="$PT" bash "$PT/.ax/hooks/pre-commit/spec-completion-gate.sh" 2>&1)
SB_OLD=$(GOAX_TASK_TTL_DAYS=0 GOAX_PROJECT_DIR="$PT" bash "$PT/.ax/scripts/bash/session-brief.sh" 2>/dev/null)
{ ! printf '%s' "$PG_OLD" | grep -q 'spec sa' && printf '%s' "$SB_OLD" | grep -q '오래 멈춘 작업: A'; } \
    && pass "TTL — 오래 멈춘 병렬 작업은 완료 게이트에서 빠지고 session-brief 가 정리를 권해요" || fail "TTL 처리 실패: $PG_OLD / $SB_OLD"
pt_u --task A --activate >/dev/null
[ "$(pt_c '.task_id + " " + .phase + " " + .description')" = "A review 결제" ] && [ "$(jq -r .phase "$PT/.ax/tasks/B.json")" = implementing ] \
    && pass "update-task --task A --activate — A 로 돌아가고 B 는 자기 파일에" || fail "update-task --activate 실패: $(pt_c '{task_id,phase}|tostring')"
[ "$(pt_r --task --json | jq -r .status 2>/dev/null)" != ok ] && [ -f "$PT/.ax/tasks/B.json" ] \
    && pass "reset-task --task 값 없음 — 다음 옵션을 id 로 삼키지 않아요" || fail "reset-task --task 가 --json 을 삼켰어요"
PR_J=$(pt_r --task B)
{ [ "$(printf '%s' "$PR_J" | jq -r '.result.active')" = false ] && [ ! -f "$PT/.ax/tasks/B.json" ] && [ "$(pt_c .task_id)" = A ]; } \
    && pass "reset-task --task B — B 파일만 지우고 지금 작업(A)은 그대로" || fail "reset-task --task — $PR_J"
pt_r >/dev/null
{ [ "$(pt_c .phase)" = idle ] && [ ! -f "$PT/.ax/tasks/A.json" ] && [ "$(pt_c '.handoff | type')" = object ]; } \
    && pass "reset-task — 지금 작업을 끝내면 파일도 지우고 idle · handoff 는 남아요" || fail "reset-task — 지금 작업 리셋 실패"
# 옛 형식 — task_id 가 있는 current-task.json 만 있고 작업 파일이 없으면 첫 갱신에 옮겨요
jq '.task_id = "OLD" | .phase = "spec" | .description = "옛"' "$PT/.ax/current-task.json" > "$PT/ct.tmp" && mv "$PT/ct.tmp" "$PT/.ax/current-task.json"
pt_u --phase tasks >/dev/null
[ "$(jq -r '.description + " " + .phase' "$PT/.ax/tasks/OLD.json" 2>/dev/null)" = "옛 tasks" ] && [ "$(pt_c .phase)" = tasks ] \
    && pass "update-task — 옛 형식(작업 파일 없음)은 첫 갱신에 .ax/tasks/ 로 옮겨요" || fail "update-task — 옛 형식 이전 실패"
grep -qxF '.ax/tasks/' "$REPO/templates/default/.gitignore.template" \
    && pass ".gitignore.template — .ax/tasks/ (런타임 상태)" || fail ".gitignore.template — .ax/tasks/ 누락"
rm -rf "$PT"

smoke_done
