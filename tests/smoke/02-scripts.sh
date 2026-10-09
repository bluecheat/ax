#!/usr/bin/env bash
# tests/smoke/02-scripts.sh — §9–§14 — 핵심 스크립트 e2e · mistake · spirit 주입 · update-state · drift · promote
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/02-scripts.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "9. .ax/scripts/bash/ 핵심 스크립트 — 문법 + 실행권한 + e2e JSON"
# ───────────────────────────────────────────────────────────
for s in common next-spec-num tier-from-state init-spec-dir add-spec-files \
         check-spec-clarity slug-from-text check-templates-drift check-manifest-install promote-mistake \
         check-rule-enforcement check-sensor-liveness \
         build-memory spirit-lint rules-index doctor-scan status-note update-task update-state constitution-apply \
         tasks-plan tasks-gate lanes-hotfiles lanes-dispatch spec-review rules-audit-scope \
         zero-init zero-probe zero-verify zero-domain-risk design-caps screen-measure screen-report-check; do
    f="$SCRIPTS_DIR/$s.sh"
    if [ -f "$f" ]; then
        # bash -n 통과
        if bash -n "$f" 2>/dev/null; then
            pass "scripts/bash/$s.sh"
        else
            fail "scripts/bash/$s.sh bash -n FAIL"
        fi
        # 실행권한
        [ -x "$f" ] || fail "scripts/bash/$s.sh 실행권한 X"
    else
        fail "scripts/bash/$s.sh 누락"
    fi
done

# end-to-end JSON validity (임시 프로젝트에서)
# pushd/popd 는 서브셸을 만들지 않으므로 pass/fail 이 fail_count 를 정상 갱신함
# (이전엔 `( cd … )` 서브셸 안에서 호출돼 카운트가 유실됐음).
TMP_E2E=$(mktemp -d)
mkdir -p "$TMP_E2E/.ax/_templates/spec"
cp -R "$REPO/templates/default/.ax/_templates/spec/." "$TMP_E2E/.ax/_templates/spec/" 2>/dev/null
cp "$REPO/templates/default/.ax/current-task.json.template" "$TMP_E2E/.ax/current-task.json" 2>/dev/null
mkdir -p "$TMP_E2E/.ax/mistakes"

pushd "$TMP_E2E" >/dev/null || fail "TMP_E2E pushd 실패"
for cmd in \
    "next-spec-num.sh --json" \
    "tier-from-state.sh --json" \
    "tier-from-state.sh --json --size L --risk L3" \
    "tier-from-state.sh --json --size M --risk L3" \
    "tier-from-state.sh --json --size L --risk L1" \
    "init-spec-dir.sh --json --tier standard --slug e2e-test --dry-run" \
    "slug-from-text.sh --json 'End To End Test'" \
    "check-templates-drift.sh --json" \
    "check-manifest-install.sh --json --plugin-dir $REPO" \
    "check-rule-enforcement.sh --json" \
    "check-sensor-liveness.sh --json" \
    "promote-mistake.sh --json" \
    "build-memory.sh --json" \
    "spirit-lint.sh --json" \
    "rules-index.sh --json" \
    "doctor-scan.sh --json --plugin-dir $REPO" \
    "status-note.sh --show --json" \
    "update-task.sh --phase spec --dry-run --json" \
    "update-task.sh --phase --json" \
    "design-caps.sh --json" \
    "screen-measure.sh --json --image nope.png --logical-width 390 --x 10" \
    "screen-report-check.sh --json"; do
    out=$(bash "$REPO/templates/default/.ax/scripts/bash/"$cmd 2>/dev/null) || true
    if echo "$out" | jq -e '.status' >/dev/null 2>&1; then
        pass "$cmd → valid JSON"
    else
        fail "$cmd → invalid JSON: ${out:0:120}"
    fi
done
popd >/dev/null || true
rm -rf "$TMP_E2E"

# --help 는 헤더 주석 블록 전체 — 손으로 든 `sed -n '2,NNp'` 는 헤더가 자라면 잘리고(Exit: 계약 유실) 줄면
# `set -euo pipefail` 까지 찍었어요 (실측 19/37). goax_help 하나로 통일했으니 줄 번호 방식은 다시 못 들어와요.
# 큰따옴표(`sed -n "2,33p"`)도, goax_help 와 같은 awk 를 스크립트 안에 사설로 복사한 것도 막아요 — 둘 다 아래 per-script
# 검사의 눈 밖이라 (goax_help 문자열이 없어서) 헤더가 자라도 아무도 못 봐요.
HELP_SED=$(grep -lE "sed -n ['\"]2,[0-9]+p|awk 'NR ?>= ?2 .*sub\(/\^# \?/" "$SCRIPTS_DIR"/*.sh 2>/dev/null | grep -v '/common\.sh$' || true)
[ -z "$HELP_SED" ] && pass "--help — 하드코딩 줄 범위(sed -n '2,NNp' · \"2,NNp\") · 사설 awk 0개 (goax_help 통일)" \
                   || fail "--help — 줄 범위/사설 awk 를 든 스크립트: $(echo "$HELP_SED" | xargs -n1 basename | tr '\n' ' ')"
help_bad=0
for hf in "$SCRIPTS_DIR"/*.sh; do
    [ "$(basename "$hf")" = common.sh ] && continue   # 헬퍼 정의 자체 — CLI 아님
    grep -q 'goax_help "${BASH_SOURCE\[0\]}"' "$hf" || continue
    h_last=$(awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/,""); print}' "$hf" | tail -1)
    h_out=$(bash "$hf" --help 2>/dev/null | tail -1)
    [ "$h_out" = "$h_last" ] || { help_bad=$((help_bad+1)); fail "$(basename "$hf") --help — 마지막 줄이 헤더 끝('$h_last')이 아님: '$h_out'"; }
done
[ "$help_bad" -eq 0 ] && pass "--help — goax_help 스크립트 전부 헤더 끝까지 정확히 (set -euo 누출 없음)"

# zero-* 4개는 오래 §9 명시 목록 밖이라 실행권한·`--help`·JSON 계약 검사를 못 받았어요
# (`bash -n` 은 §7 의 glob 이 이미 훑고 있었고요). 실행 계약까지 여기서 고정해요.
TMP_Z=$(mktemp -d)
mkdir -p "$TMP_Z/.ax/scripts/bash"
cp "$SCRIPTS_DIR/"{common,zero-init,zero-probe,zero-verify,zero-domain-risk}.sh "$TMP_Z/.ax/scripts/bash/"
printf 'sensors:\n  mode: warning\ndomain_risk:\n  payment: L3\ndefault_risk: L0\n' > "$TMP_Z/.ax/config.yml"
for zc in "zero-init.sh --json --dry-run" "zero-probe.sh --json" "zero-verify.sh --json" "zero-domain-risk.sh --show --json"; do
    zname="${zc%% *}"
    # --help 은 `# Exit:` 계약 줄까지 보여줘야 해요 (sed 범위가 짧으면 계약이 잘려요)
    bash "$TMP_Z/.ax/scripts/bash/$zname" --help 2>/dev/null | grep -q '^Exit:' \
        && pass "$zname --help — Exit: 계약 노출" || fail "$zname --help — Exit: 줄 없음 (sed 범위 확인)"
    zout=$(GOAX_PROJECT_DIR="$TMP_Z" bash "$TMP_Z/.ax/scripts/bash/"$zc 2>/dev/null) || true
    echo "$zout" | jq -e 'has("status") and has("result") and has("next_step") and (.warnings|type=="array") and (.errors|type=="array")' >/dev/null 2>&1 \
        && pass "$zc → {status,result,next_step,warnings,errors}" \
        || fail "$zc → --json 스키마 불일치: ${zout:0:120}"
done
rm -rf "$TMP_Z"

[ -e "$SCRIPTS_DIR/build-index.sh" ] && fail "build-index.sh — 제거됐어야 함 (BM25 분기 폐기)" || pass "build-index.sh 제거됨 (되살릴 조건: .ax/docs 2,000 파일 실측)"
grep -q 'build-index' "$REPO/templates/default/.ax/scripts/bash/triage-search.sh" \
    && fail "triage-search.sh 에 build-index 분기 잔재" || pass "triage-search.sh — BM25 union 분기 제거"

# ───────────────────────────────────────────────────────────
section "10. init-mistake-file.sh 런타임 — race-free ID + idempotent + redactor"
# ───────────────────────────────────────────────────────────
# Plugin은 실제로 사용자 프로젝트에 설치되어 동작 → 임시 fixture에서 e2e.
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/.ax/_templates/mistakes"
cp -R "$REPO/templates/default/.ax/scripts" "$FIXTURE/.ax/"
cp -R "$REPO/templates/default/.ax/mistakes" "$FIXTURE/.ax/"
cp "$REPO/templates/default/.ax/_templates/mistakes/mistake.md" "$FIXTURE/.ax/_templates/mistakes/"
cp "$REPO/templates/default/.ax/config.yml" "$FIXTURE/.ax/"
( cd "$FIXTURE" && git init -q 2>/dev/null && git config user.email "smoke@local" && git config user.name "smoke" )

# 10.1 race-free ID — 5병렬 호출 → 5개 고유 파일 (다른 카테고리)
( cd "$FIXTURE" && \
  for i in 1 2 3 4 5; do
      CLAUDE_PROJECT_DIR=$FIXTURE bash .ax/scripts/bash/init-mistake-file.sh \
          --category "race$i" --slug "parallel-$i" \
          --severity medium --detected-by self --source skill \
          --json >/dev/null 2>&1 &
  done
  wait )
RACE_COUNT=$(find "$FIXTURE/.ax/mistakes" -maxdepth 1 -type f -name "*.md" ! -name "README.md" | wc -l | tr -d ' ')
[ "$RACE_COUNT" -eq 5 ] && pass "race-free ID — 5병렬 호출 → 5개 파일" \
                       || fail "race-free ID — 5병렬에 $RACE_COUNT 파일만 생성 (충돌)"

# 10.2 idempotent — 같은 (DATE, CATEGORY, SLUG) 재호출 → 새 파일 X, ## 이력 append
rm -f "$FIXTURE/.ax/mistakes"/[0-9]*.md
CLAUDE_PROJECT_DIR=$FIXTURE bash "$FIXTURE/.ax/scripts/bash/init-mistake-file.sh" \
    --category secrets --slug pg-key-leak \
    --severity high --detected-by reviewer --source skill --json >/dev/null 2>&1
COUNT_BEFORE=$(find "$FIXTURE/.ax/mistakes" -maxdepth 1 -type f -name "*-secrets-*.md" | wc -l | tr -d ' ')
CLAUDE_PROJECT_DIR=$FIXTURE bash "$FIXTURE/.ax/scripts/bash/init-mistake-file.sh" \
    --category secrets --slug pg-key-leak \
    --severity high --detected-by reviewer --source skill --json >/dev/null 2>&1
COUNT_AFTER=$(find "$FIXTURE/.ax/mistakes" -maxdepth 1 -type f -name "*-secrets-*.md" | wc -l | tr -d ' ')
if [ "$COUNT_BEFORE" = "1" ] && [ "$COUNT_AFTER" = "1" ]; then
    pass "init-mistake-file — idempotent (재호출 시 새 파일 X)"
else
    fail "idempotent 실패: before=$COUNT_BEFORE after=$COUNT_AFTER"
fi

# 10.3 redact_secrets — known-prefix tokens (common.sh 함수 직접 검증)
PREFIX_TEST=$(printf 'leak: AKIAIOSFODNN7EXAMPLE and ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789a here\n' \
              | bash -c "source $REPO/templates/default/.ax/scripts/bash/common.sh && redact_secrets")
echo "$PREFIX_TEST" | grep -q "\[REDACTED:aws\]" && echo "$PREFIX_TEST" | grep -q "\[REDACTED:github\]" \
    && pass "redact_secrets — AWS/GitHub known-prefix 치환" \
    || fail "redact_secrets — known-prefix 누락: $PREFIX_TEST"

# 10.4 redact_secrets — 짧은 값(<12자)·식별자는 보존 (false positive guard)
FP_TEST=$(printf 'pw=ok123 and password_field stays\n' \
          | bash -c "source $REPO/templates/default/.ax/scripts/bash/common.sh && redact_secrets")
if echo "$FP_TEST" | grep -q "ok123" && echo "$FP_TEST" | grep -q "password_field"; then
    pass "redact_secrets — 짧은 값·식별자 false positive 없음"
else
    fail "redact_secrets — false positive: $FP_TEST"
fi

# ───────────────────────────────────────────────────────────
section "11. spirit-rules-inject.sh — hook-based path-scoped (Design B)"
# ───────────────────────────────────────────────────────────
HOOK_PATH="$REPO/templates/default/.ax/hooks/pre-edit/spirit-rules-inject.sh"
[ -f "$HOOK_PATH" ] && pass "hooks/pre-edit/spirit-rules-inject.sh 존재" \
                   || fail "hooks/pre-edit/spirit-rules-inject.sh 누락"

[ -x "$HOOK_PATH" ] && pass "spirit-rules-inject.sh 실행권한" \
                    || fail "spirit-rules-inject.sh 실행권한 X"

bash -n "$HOOK_PATH" 2>/dev/null && pass "spirit-rules-inject.sh 문법 OK" \
                                 || fail "spirit-rules-inject.sh 문법 오류"

# settings.json.template에 hook 등록됐는지
grep -q 'spirit-rules-inject\.sh' "$REPO/templates/default/.claude/settings.json.template" \
    && pass "settings.json.template에 hook 등록됨" \
    || fail "settings.json.template에 spirit-rules-inject.sh 미등록"

# 런타임 e2e — fixture에서 매칭/미매칭 검증
HOOK_FX=$(mktemp -d)
mkdir -p "$HOOK_FX/.ax/spirit/rules" "$HOOK_FX/.ax/hooks/pre-edit"
cp "$HOOK_PATH" "$HOOK_FX/.ax/hooks/pre-edit/"
cat > "$HOOK_FX/.ax/spirit/rules/scoped.md" <<'MD'
---
category: domain
paths:
  - "**/domain/**"
  - "**/*Entity*.kt"
---
# Scoped
## SP-DOM-001: x
MD
cat > "$HOOK_FX/.ax/spirit/rules/universal.md" <<'MD'
---
category: ops
applies_to: [code]
---
# Universal
## SP-OPS-001: x
MD

# (1) 매칭되는 path → additionalContext 출력
OUT1=$(echo "{\"tool_input\":{\"file_path\":\"$HOOK_FX/some/domain/Order.kt\"}}" \
       | CLAUDE_PROJECT_DIR=$HOOK_FX bash "$HOOK_FX/.ax/hooks/pre-edit/spirit-rules-inject.sh" 2>&1)
if echo "$OUT1" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
    && echo "$OUT1" | grep -q 'spirit/rules/scoped.md'; then
    pass "hook 매칭 — domain path → scoped.md additionalContext"
else
    fail "hook 매칭 실패: $OUT1"
fi

# (2) Entity 파일명 매칭
OUT2=$(echo "{\"tool_input\":{\"file_path\":\"$HOOK_FX/x/UserEntity.kt\"}}" \
       | CLAUDE_PROJECT_DIR=$HOOK_FX bash "$HOOK_FX/.ax/hooks/pre-edit/spirit-rules-inject.sh" 2>&1)
echo "$OUT2" | grep -q 'spirit/rules/scoped.md' \
    && pass "hook 매칭 — *Entity*.kt 파일명 패턴" \
    || fail "hook 매칭 실패 (Entity): $OUT2"

# (3) 매칭 없는 path → silent (빈 출력)
OUT3=$(echo "{\"tool_input\":{\"file_path\":\"$HOOK_FX/random/Foo.txt\"}}" \
       | CLAUDE_PROJECT_DIR=$HOOK_FX bash "$HOOK_FX/.ax/hooks/pre-edit/spirit-rules-inject.sh" 2>&1)
[ -z "$OUT3" ] && pass "hook 비매칭 — silent 출력" \
              || fail "hook 비매칭에 출력 발생: $OUT3"

# (4) universal 룰(paths 없음)은 매칭 안 됨
OUT4=$(echo "{\"tool_input\":{\"file_path\":\"$HOOK_FX/anywhere/file.kt\"}}" \
       | CLAUDE_PROJECT_DIR=$HOOK_FX bash "$HOOK_FX/.ax/hooks/pre-edit/spirit-rules-inject.sh" 2>&1)
echo "$OUT4" | grep -q 'spirit/rules/universal.md' \
    && fail "universal 룰이 잘못 매칭됨: $OUT4" \
    || pass "hook — paths 없는 universal 룰은 매칭 안 됨"

rm -rf "$HOOK_FX"

# register-spirit-hook.sh — settings.json idempotent 머지
REG_SCRIPT="$REPO/templates/default/.ax/scripts/bash/register-spirit-hook.sh"
[ -f "$REG_SCRIPT" ] && pass "scripts/bash/register-spirit-hook.sh 존재" \
                     || fail "scripts/bash/register-spirit-hook.sh 누락"
[ -x "$REG_SCRIPT" ] && pass "register-spirit-hook.sh 실행권한" \
                     || fail "register-spirit-hook.sh 실행권한 X"
bash -n "$REG_SCRIPT" 2>/dev/null && pass "register-spirit-hook.sh 문법 OK" \
                                  || fail "register-spirit-hook.sh 문법 오류"

REG_FX=$(mktemp -d)
mkdir -p "$REG_FX/.ax/scripts/bash" "$REG_FX/.claude"
cp "$REG_SCRIPT" "$REPO/templates/default/.ax/scripts/bash/common.sh" "$REG_FX/.ax/scripts/bash/"

# (1) PreToolUse 없는 settings.json — 신규 entry 추가
echo '{"hooks":{"UserPromptSubmit":[]}}' > "$REG_FX/.claude/settings.json"
CLAUDE_PROJECT_DIR=$REG_FX bash "$REG_FX/.ax/scripts/bash/register-spirit-hook.sh" >/dev/null 2>&1
if grep -q 'spirit-rules-inject\.sh' "$REG_FX/.claude/settings.json"; then
    pass "register — PreToolUse 없는 settings.json에 신규 entry 추가"
else
    fail "register — 신규 entry 추가 실패"
fi

# (2) idempotent — 재실행 시 중복 안 됨
CLAUDE_PROJECT_DIR=$REG_FX bash "$REG_FX/.ax/scripts/bash/register-spirit-hook.sh" >/dev/null 2>&1
COUNT=$(grep -c 'spirit-rules-inject\.sh' "$REG_FX/.claude/settings.json")
[ "$COUNT" -eq 1 ] && pass "register — idempotent (재실행 시 중복 X)" \
                  || fail "register — idempotent 실패 ($COUNT 회 등록)"

# (3) 기존 Edit|Write|MultiEdit entry 보존하며 append
echo '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"bash existing.sh"}]}]}}' \
    > "$REG_FX/.claude/settings.json"
CLAUDE_PROJECT_DIR=$REG_FX bash "$REG_FX/.ax/scripts/bash/register-spirit-hook.sh" >/dev/null 2>&1
EXIST_KEPT=$(grep -c "existing\.sh" "$REG_FX/.claude/settings.json")
INJ_ADDED=$(grep -c "spirit-rules-inject\.sh" "$REG_FX/.claude/settings.json")
if [ "$EXIST_KEPT" -eq 1 ] && [ "$INJ_ADDED" -eq 1 ]; then
    pass "register — 기존 hook 보존 + spirit-rules-inject append"
else
    fail "register — 머지 실패 (existing=$EXIST_KEPT, inject=$INJ_ADDED)"
fi

# (4) 백업 파일 생성 검증
BAK_COUNT=$(find "$REG_FX/.claude" -name "settings.json.bak.*" 2>/dev/null | wc -l | tr -d ' ')
[ "$BAK_COUNT" -ge 1 ] && pass "register — settings.json 백업 자동 생성" \
                       || fail "register — 백업 미생성"

rm -rf "$REG_FX"

# ───────────────────────────────────────────────────────────
section "12. update-state.sh — state.json 시그널 카운트 정확성"
# ───────────────────────────────────────────────────────────
# 실제 설치본 위에서 — 설치본의 룰 파일은 AGENTS.md 예요 (CLAUDE.md 는 그걸 import). 예전 손 fixture 는
# CLAUDE.md 에 룰을 넣어 셌는데, 설치본에선 그 파일을 아예 안 읽어요. 룰 파일만 셀 수 있는 내용으로 바꿔요.
fx_install US_FX || US_FX=$(mktemp -d)
mkdir -p "$US_FX/.ax/spirit/rules"
cat > "$US_FX/AGENTS.md" <<'MD'
🔴 **`X:CRITICAL:001`** rule a
🔴 **`X:CRITICAL:002`** rule b
🟡 **`X:MANDATORY:001`** rule c
🔵 **`X:CONVENTION:001`** rule d
MD
cat > "$US_FX/.ax/spirit/rules/foo.md" <<'MD'
## SP-FOO-001: a
## SP-FOO-002: b
MD

CLAUDE_PROJECT_DIR=$US_FX bash "$US_FX/.ax/scripts/bash/update-state.sh" >/dev/null 2>&1

if command -v jq >/dev/null 2>&1; then
    CRIT=$(jq -r '.layers.L1_constitution.signals.critical' "$US_FX/.ax/state.json")
    MAND=$(jq -r '.layers.L1_constitution.signals.mandatory' "$US_FX/.ax/state.json")
    CONV=$(jq -r '.layers.L1_constitution.signals.convention' "$US_FX/.ax/state.json")
    L1_ACTIVE=$(jq -r '.layers.L1_constitution.active' "$US_FX/.ax/state.json")

    [ "$CRIT" = "2" ] && pass "update-state — CRITICAL=2 (AGENTS.md inline)" \
                      || fail "update-state — CRITICAL=$CRIT (expected 2)"
    [ "$MAND" = "1" ] && pass "update-state — MANDATORY=1" \
                      || fail "update-state — MANDATORY=$MAND (expected 1)"
    # CONV: inline 1 (AGENTS.md) + spirit heading 2 = 3
    [ "$CONV" = "3" ] && pass "update-state — CONVENTION=3 (1 inline + 2 spirit heading)" \
                      || fail "update-state — CONVENTION=$CONV (expected 3, heading 패턴 합산)"
    [ "$L1_ACTIVE" = "true" ] && pass "update-state — L1 active (rules > 0)" \
                              || fail "update-state — L1 active=$L1_ACTIVE"
    # --skill — last_skill·skill_calls(+1 누적)·(mistake) last_mistake_file 을 같은 락·같은 쓰기 안에서
    CLAUDE_PROJECT_DIR=$US_FX bash "$US_FX/.ax/scripts/bash/update-state.sh" --skill triage >/dev/null 2>&1
    CLAUDE_PROJECT_DIR=$US_FX bash "$US_FX/.ax/scripts/bash/update-state.sh" --skill mistake --last-mistake ".ax/mistakes/x.md" >/dev/null 2>&1
    jq -e '.last_skill=="mistake" and .skill_calls==2 and .last_mistake_file==".ax/mistakes/x.md" and .layers.L1_constitution.rules>0' "$US_FX/.ax/state.json" >/dev/null 2>&1 \
        && pass "update-state --skill — last_skill · skill_calls 누적 · --last-mistake · derived 도 같은 쓰기" \
        || fail "update-state --skill — 불일치: $(jq -c '{last_skill,skill_calls,last_mistake_file}' "$US_FX/.ax/state.json" 2>/dev/null)"
    US_B=$(cat "$US_FX/.ax/state.json"); us_bad=0
    for a in "--skill" "--skill --json" "--skill 'a b'" "--last-mistake" "--bogus"; do
        # shellcheck disable=SC2086
        eval CLAUDE_PROJECT_DIR=$US_FX bash "$US_FX/.ax/scripts/bash/update-state.sh" $a >/dev/null 2>&1 && { us_bad=$((us_bad+1)); fail "update-state '$a' 가 exit 0"; }
    done
    [ "$us_bad" -eq 0 ] && [ "$(cat "$US_FX/.ax/state.json")" = "$US_B" ] \
        && pass "update-state --skill 검증 5종 — exit 1 + 파일 불변" || fail "update-state --skill 검증 — 실패 뒤 파일 변동"
    CLAUDE_PROJECT_DIR=$US_FX bash "$US_FX/.ax/scripts/bash/update-state.sh" --json --skill zzz >/dev/null 2>&1
    [ "$(cat "$US_FX/.ax/state.json")" = "$US_B" ] && pass "update-state --json --skill — stdout 만, 파일 불변" || fail "update-state --json --skill 이 파일을 씀"
fi
rm -rf "$US_FX"

# ───────────────────────────────────────────────────────────
section "13. check-templates-drift.sh — 3-state coverage"
# ───────────────────────────────────────────────────────────
DR_FX=$(mktemp -d)
mkdir -p "$DR_FX/.ax/_templates/spec/contracts" "$DR_FX/.ax/_templates/spec/checklists" "$DR_FX/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/"{common.sh,check-templates-drift.sh} "$DR_FX/.ax/scripts/bash/"
# 최소 _templates 파일들 (sha 비교 대상)
cp -R "$REPO/templates/default/.ax/_templates/spec/." "$DR_FX/.ax/_templates/spec/" 2>/dev/null

# (1) origin_present=false 상태 — up 첫 호출이라 .origin 없음
OUT=$(CLAUDE_PROJECT_DIR=$DR_FX bash "$DR_FX/.ax/scripts/bash/check-templates-drift.sh" --json 2>&1)
if echo "$OUT" | jq -e '.result.origin_present == false' >/dev/null 2>&1; then
    pass "drift — .origin 부재 시 origin_present=false"
else
    fail "drift — origin_present 잘못: $OUT"
fi

# (2) pristine state — .origin 만들고 검사
( cd "$DR_FX/.ax/_templates/spec" && \
  find . -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
    ! -name '.origin' ! -name '.tier' | sort | xargs shasum -a 256 2>/dev/null \
) > "$DR_FX/.ax/_templates/spec/.origin"
echo "# goax_version: 0.1.8" >> "$DR_FX/.ax/_templates/spec/.origin"

OUT=$(CLAUDE_PROJECT_DIR=$DR_FX bash "$DR_FX/.ax/scripts/bash/check-templates-drift.sh" --json 2>&1)
if echo "$OUT" | jq -e '.result.user_modified == false and .result.plugin_updated == false' >/dev/null 2>&1; then
    pass "drift — pristine state (user_modified=false, plugin_updated=false)"
else
    fail "drift — pristine 검출 실패: $OUT"
fi

# (3) user-modified — 파일 한 개 수정 후 검사
echo "USER MODIFIED" >> "$DR_FX/.ax/_templates/spec/spec.md"
OUT=$(CLAUDE_PROJECT_DIR=$DR_FX bash "$DR_FX/.ax/scripts/bash/check-templates-drift.sh" --json 2>&1)
if echo "$OUT" | jq -e '.result.user_modified == true' >/dev/null 2>&1; then
    pass "drift — user-modified 검출"
else
    fail "drift — user-modified 검출 실패: $OUT"
fi
rm -rf "$DR_FX"

# ───────────────────────────────────────────────────────────
section "14. promote-mistake.sh — candidate + --apply (CLAUDE.md 무수정)"
# ───────────────────────────────────────────────────────────
PM_FX=$(mktemp -d)
mkdir -p "$PM_FX/.ax/mistakes" "$PM_FX/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/"{common.sh,promote-mistake.sh} "$PM_FX/.ax/scripts/bash/"
cat > "$PM_FX/CLAUDE.md" <<'MD'
# Test Constitution
MD

# (1) 빈 mistakes — candidates 0
OUT=$(CLAUDE_PROJECT_DIR=$PM_FX bash "$PM_FX/.ax/scripts/bash/promote-mistake.sh" --json --threshold 2 2>&1)
if echo "$OUT" | jq -e '.result.candidates | length == 0' >/dev/null 2>&1; then
    pass "promote — 빈 mistakes에서 candidates=0"
else
    fail "promote — 빈 검출 실패: $OUT"
fi

# (2) 같은 카테고리 3개 → threshold=2면 candidate 1개
for i in 1 2 3; do
    cat > "$PM_FX/.ax/mistakes/2026-01-0$i-secrets.md" <<EOF
---
category: secrets
severity: high
---
# Test $i
EOF
done
OUT=$(CLAUDE_PROJECT_DIR=$PM_FX bash "$PM_FX/.ax/scripts/bash/promote-mistake.sh" --json --threshold 2 2>&1)
CAND_CAT=$(echo "$OUT" | jq -r '.result.candidates[0].category' 2>/dev/null)
CAND_CNT=$(echo "$OUT" | jq -r '.result.candidates[0].count' 2>/dev/null)
if [ "$CAND_CAT" = "secrets" ] && [ "$CAND_CNT" = "3" ]; then
    pass "promote — 3건 누적 → candidate (secrets:3)"
else
    fail "promote — candidate 검출 실패: cat=$CAND_CAT cnt=$CAND_CNT"
fi

# (3) --apply — mistake 에 promoted_to 마킹만, CLAUDE.md 는 건드리지 않음.
# 룰 본문 작성은 LLM 책임 (audit SKILL 안에서 spirit/rules 직접 Edit).
# stderr는 분리 — goax_log가 stdout JSON과 섞이면 jq 파싱 실패.
OUT=$(CLAUDE_PROJECT_DIR=$PM_FX bash "$PM_FX/.ax/scripts/bash/promote-mistake.sh" \
    --apply --json --token "TEST:CRITICAL:001" \
    --category secrets 2>/dev/null)
MARKED=$(echo "$OUT" | jq -r '.result.marked_count' 2>/dev/null)
if [ "$MARKED" = "3" ] \
    && grep -q '^promoted_to: TEST:CRITICAL:001' "$PM_FX/.ax/mistakes/2026-01-01-secrets.md" \
    && ! grep -q 'TEST:CRITICAL:001' "$PM_FX/CLAUDE.md"; then
    pass "promote --apply — 3건 promoted_to 마킹 + CLAUDE.md 무수정"
else
    fail "promote --apply 결과 부정확: marked=$MARKED, claude.md_polluted=$(grep TEST $PM_FX/CLAUDE.md || echo no)"
fi

# (4) 재실행 — promoted_to 있는 mistake는 candidate에서 제외 (idempotent)
OUT=$(CLAUDE_PROJECT_DIR=$PM_FX bash "$PM_FX/.ax/scripts/bash/promote-mistake.sh" --json --threshold 2 2>&1)
if echo "$OUT" | jq -e '.result.candidates | length == 0' >/dev/null 2>&1; then
    pass "promote — promoted_to 마킹된 mistake 재후보 제외 (idempotent)"
else
    fail "promote — idempotent 실패: $OUT"
fi

# (5) --archive — SP 토큰이 spirit/rules 에 없으면 거부 (사전 검증)
mkdir -p "$PM_FX/.ax/spirit/rules"
OUT=$(CLAUDE_PROJECT_DIR=$PM_FX bash "$PM_FX/.ax/scripts/bash/promote-mistake.sh" \
    --archive --json --token TEST:CRITICAL:001 2>/dev/null)
if echo "$OUT" | jq -e '.status == "error"' >/dev/null 2>&1 \
    && echo "$OUT" | jq -r '.errors[0]' | grep -q "not found in .ax/spirit/rules"; then
    pass "promote --archive — SP 토큰 부재 시 거부 (사전 검증)"
else
    fail "promote --archive — SP 토큰 부재인데 진행: $OUT"
fi

# (6) --archive — SP 토큰 spirit/rules 에 추가 후 happy path
echo "## TEST:CRITICAL:001: secrets" > "$PM_FX/.ax/spirit/rules/test-secrets.md"
OUT=$(CLAUDE_PROJECT_DIR=$PM_FX bash "$PM_FX/.ax/scripts/bash/promote-mistake.sh" \
    --archive --json --token TEST:CRITICAL:001 2>/dev/null)
ARCHIVED=$(echo "$OUT" | jq -r '.result.archived_count' 2>/dev/null)
ARCHIVE_DIR=$(echo "$OUT" | jq -r '.result.archive_dir' 2>/dev/null)
ROOT_LEFT=$(find "$PM_FX/.ax/mistakes" -maxdepth 1 -name "*.md" ! -name "README.md" | wc -l | tr -d ' ')
ARCH_FILES=$(find "$PM_FX/$ARCHIVE_DIR" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$ARCHIVED" = "3" ] && [ "$ROOT_LEFT" = "0" ] && [ "$ARCH_FILES" = "3" ]; then
    pass "promote --archive — 3건 mv → _archive/YYYY/MM/ + root 잔재 0"
else
    fail "promote --archive 결과: archived=$ARCHIVED root_left=$ROOT_LEFT arch_files=$ARCH_FILES"
fi

rm -rf "$PM_FX"

smoke_done
