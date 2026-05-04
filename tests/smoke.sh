#!/usr/bin/env bash
# tests/smoke.sh — goax Plugin 구조 검증
# 검증: 파일 구조·JSON 유효성·skill frontmatter·shell 문법·jq syntax·hook 경로
#       + scripts/bash/ 8개·current-task.json.template (NEW)

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
fail_count=0
pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$1"; fail_count=$((fail_count+1)); }
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# ───────────────────────────────────────────────────────────
section "1. Plugin manifest"
# ───────────────────────────────────────────────────────────
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
    if [ -f "$REPO/$f" ]; then
        if python3 -c "import json; json.load(open('$REPO/$f'))" 2>/dev/null; then
            pass "$f (JSON valid)"
        else
            fail "$f (JSON invalid)"
        fi
    else
        fail "$f 누락"
    fi
done

PLUGIN_NAME=$(python3 -c "import json; print(json.load(open('$REPO/.claude-plugin/plugin.json'))['name'])" 2>/dev/null)
[ "$PLUGIN_NAME" = "goax" ] && pass "plugin.json name=goax" || fail "plugin.json name 불일치"

VER_FILE=$(cat "$REPO/VERSION" 2>/dev/null | tr -d '\n')
VER_PLUGIN=$(python3 -c "import json; print(json.load(open('$REPO/.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
VER_MARKET=$(python3 -c "import json; d=json.load(open('$REPO/.claude-plugin/marketplace.json')); print(d['version'])" 2>/dev/null)
[ "$VER_FILE" = "$VER_PLUGIN" ] && pass "VERSION ↔ plugin.json (=$VER_FILE)" || fail "VERSION/plugin.json 불일치 ($VER_FILE vs $VER_PLUGIN)"
[ "$VER_FILE" = "$VER_MARKET" ] && pass "VERSION ↔ marketplace.json (=$VER_FILE)" || fail "VERSION/marketplace.json 불일치 ($VER_FILE vs $VER_MARKET)"

# ───────────────────────────────────────────────────────────
section "2. 핵심 skills (12개)"
# ───────────────────────────────────────────────────────────
for skill in install onboarding doctor rules \
             spec spec-validate audit spirit hud \
             spec-plan spec-tasks spec-implement; do
    f="$REPO/skills/$skill/SKILL.md"
    if [ -f "$f" ]; then
        if head -5 "$f" | grep -qE "^name: $skill\$"; then
            pass "skills/$skill/SKILL.md (frontmatter OK)"
        else
            fail "skills/$skill/SKILL.md frontmatter name 불일치"
        fi
    else
        fail "skills/$skill/SKILL.md 누락"
    fi
done

# 제거된 skill이 잔재로 남지 않았는지 확인 (옛 구조)
for removed in skills/global skills/workflows \
               skills/global/goax-critical-rules skills/global/goax-steering-loop \
               skills/personas skills/meta; do
    if [ -e "$REPO/$removed" ]; then
        fail "$removed — 제거됐어야 함 (잔재)"
    else
        pass "$removed 제거됨"
    fi
done

# ───────────────────────────────────────────────────────────
section "2.5 Slash commands (15개 — 'goax-' prefix 컨벤션)"
# ───────────────────────────────────────────────────────────
# commands는 `goax-<name>.md` 형태 + `goax.md` 인덱스 alias 1개
for cmd in goax goax-install goax-onboarding goax-doctor goax-audit goax-rules goax-hud goax-spirit \
           goax-triage goax-adr goax-spec goax-spec-validate goax-spec-plan goax-spec-tasks goax-spec-implement; do
    f="$REPO/commands/$cmd.md"
    if [ -f "$f" ]; then
        if head -5 "$f" | grep -qE "^name: $cmd\$"; then
            pass "commands/$cmd.md (frontmatter OK)"
        else
            fail "commands/$cmd.md frontmatter name 불일치"
        fi
    else
        fail "commands/$cmd.md 누락"
    fi
done

# ───────────────────────────────────────────────────────────
section "2.6 HUD assets"
# ───────────────────────────────────────────────────────────
for f in templates/default/.ax/hud/statusline.sh templates/default/.ax/hud/state.json.template; do
    [ -f "$REPO/$f" ] && pass "$f" || fail "$f 누락"
done
[ -x "$REPO/templates/default/.ax/hud/statusline.sh" ] && pass "statusline.sh executable" || fail "statusline.sh 실행권한 X"
python3 -c "import json; json.load(open('$REPO/templates/default/.ax/hud/state.json.template'))" 2>/dev/null \
    && pass "state.json.template JSON valid" || fail "state.json.template JSON invalid"

# ───────────────────────────────────────────────────────────
section "3. agents/"
# ───────────────────────────────────────────────────────────
for a in evaluator architect; do
    if [ -f "$REPO/agents/$a.md" ]; then
        pass "agents/$a.md"
    else
        fail "agents/$a.md 누락"
    fi
done

# ───────────────────────────────────────────────────────────
section "4. templates/default — installer가 사용자 프로젝트로 복사할 자산"
# ───────────────────────────────────────────────────────────
for f in \
    templates/default/CLAUDE.md.template \
    templates/default/.claude/settings.json.template \
    templates/default/.gitignore.template \
    templates/default/.ax/spirit/values.md \
    templates/default/.ax/spirit/tone.md \
    templates/default/.ax/docs/_templates/spirit/rule.md \
    templates/default/.ax/docs/_templates/module/rules.md \
    templates/default/.ax/config.yml \
    templates/default/.ax/mistakes/README.md \
    templates/default/.ax/hooks/pre-bash/block-destructive.sh \
    templates/default/.ax/hooks/pre-edit/check-protected-paths.sh \
    templates/default/.ax/hooks/pre-edit/spirit-check.sh \
    templates/default/.ax/hooks/post-edit/lint-changed.sh \
    templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh \
    templates/default/.ax/docs/_templates/adr/0000-template.md \
    templates/default/.ax/docs/_templates/spec/spec.md \
    templates/default/.ax/docs/_templates/spec/plan.md \
    templates/default/.ax/docs/_templates/spec/tasks.md \
    templates/default/.ax/docs/_templates/spec/checklists/requirements.md \
    templates/default/.ax/docs/_templates/spec/research.md \
    templates/default/.ax/docs/_templates/spec/data-model.md \
    templates/default/.ax/docs/_templates/spec/contracts/api.yaml \
    templates/default/.ax/docs/_templates/spec/contracts/events.md \
    templates/default/.ax/docs/_templates/spec/quickstart.md \
    templates/default/.ax/docs/_templates/spec/README.md \
    templates/default/.ax/current-task.json.template \
    templates/default/.ax/scripts/bash/README.md \
    templates/default/.ax/scripts/bash/common.sh \
    templates/default/.ax/scripts/bash/next-spec-num.sh \
    templates/default/.ax/scripts/bash/tier-from-state.sh \
    templates/default/.ax/scripts/bash/init-spec-dir.sh \
    templates/default/.ax/scripts/bash/add-spec-files.sh \
    templates/default/.ax/scripts/bash/slug-from-text.sh \
    templates/default/.ax/scripts/bash/check-templates-drift.sh \
    templates/default/.ax/scripts/bash/promote-mistake.sh
do
    [ -f "$REPO/$f" ] && pass "$f" || fail "$f 누락"
done

python3 -c "import json; json.load(open('$REPO/templates/default/.claude/settings.json.template'))" 2>/dev/null \
    && pass "settings.json.template JSON valid" \
    || fail "settings.json.template JSON invalid"

python3 -c "import json; json.load(open('$REPO/templates/default/.ax/current-task.json.template'))" 2>/dev/null \
    && pass "current-task.json.template JSON valid" \
    || fail "current-task.json.template JSON invalid"

# .gitignore.template — 0.1.8 신규. runtime 엔트리 4종 모두 포함하는지 검증.
GI_TPL="$REPO/templates/default/.gitignore.template"
if [ -f "$GI_TPL" ]; then
    missing=0
    for entry in ".ax/state.json" ".ax/current-task.json" ".ax/*.suggested" ".ax/.onboarding-pending"; do
        grep -qxF "$entry" "$GI_TPL" || { fail ".gitignore.template 누락 엔트리: $entry"; missing=$((missing+1)); }
    done
    [ "$missing" -eq 0 ] && pass ".gitignore.template — runtime 엔트리 4종 모두 포함"
fi

# 0.1.8 잔재 검증 — spirit/rules/output-style.md (plugin meta로 분류되어 0.1.8에서 출고 제거)
[ -f "$REPO/templates/default/.ax/spirit/rules/output-style.md" ] \
    && fail "spirit/rules/output-style.md — 0.1.8에서 plugin 출고 제거됐어야 함 (plugin meta)" \
    || pass "spirit/rules/output-style.md 출고 제거됨 (0.1.8)"

# ───────────────────────────────────────────────────────────
section "4.1 settings.json.template — 참조 hook 파일 실존"
# ───────────────────────────────────────────────────────────
HOOK_REFS=$(python3 -c "
import json
d = json.load(open('$REPO/templates/default/.claude/settings.json.template'))
hooks = d.get('hooks', {})
for phase, items in hooks.items():
    for item in items:
        cmd = item.get('command', '')
        if cmd.startswith('.ax/'):
            print(cmd[4:])
" 2>/dev/null)
echo "$HOOK_REFS" | while IFS= read -r relpath; do
    [ -z "$relpath" ] && continue
    full="$REPO/templates/default/.ax/$relpath"
    if [ -f "$full" ]; then
        pass "settings.json → .ax/$relpath (실존)"
    else
        fail "settings.json → .ax/$relpath 누락 (런타임 깨짐)"
    fi
done

# ───────────────────────────────────────────────────────────
section "5. SKILL frontmatter — 모든 skill의 description"
# ───────────────────────────────────────────────────────────
total_skills=0
ok_skills=0
while IFS= read -r f; do
    total_skills=$((total_skills+1))
    if head -10 "$f" | grep -q "^description:"; then
        ok_skills=$((ok_skills+1))
    else
        fail "frontmatter description 누락: ${f#$REPO/}"
    fi
done < <(find "$REPO/skills" -name SKILL.md)
pass "skill frontmatter ($ok_skills/$total_skills)"
[ "$total_skills" -eq 14 ] && pass "skill 카운트 = 14" || fail "skill 카운트 $total_skills"

# ───────────────────────────────────────────────────────────
section "6. HUD statusline 우주 이모지 + spec/ADR 진척 (팩트 기반)"
# ───────────────────────────────────────────────────────────
if grep -q "🪐\|🌟\|⭐\|✦" "$REPO/templates/default/.ax/hud/statusline.sh"; then
    pass "statusline.sh 우주 이모지 (별·행성)"
else
    fail "statusline.sh 우주 이모지 누락"
fi
# 자가 점수 prefix 잔재 검사 (제거됐어야 함)
LEFT=$(grep -rl "응답 prefix 이모지\|prefix 자가 점수\|하네스 자가 점수" \
       "$REPO/templates/default/.ax/spirit" "$REPO/skills" "$REPO/agents" 2>/dev/null || true)
if [ -z "$LEFT" ]; then
    pass "자가 점수 prefix 제거 완료 (spirit/skills/agents 잔재 0)"
else
    fail "자가 점수 prefix 잔재: $(echo $LEFT | tr '\n' ' ')"
fi
# stdin JSON 처리 (Claude Code statusline 사양)
if grep -q "workspace.current_dir" "$REPO/templates/default/.ax/hud/statusline.sh"; then
    pass "statusline.sh stdin JSON 처리 (workspace.current_dir)"
else
    fail "statusline.sh stdin JSON 처리 누락"
fi
# spec/ADR 진척 e2e — 임시 .ax/ 만들고 multi-line 출력 검증
if command -v jq >/dev/null 2>&1; then
    HUD_TMP=$(mktemp -d)
    mkdir -p "$HUD_TMP/.ax/docs/spec/005-test"
    cat > "$HUD_TMP/.ax/state.json" <<JSON
{"layers":{"L0_triage":{"active":true},"L1_constitution":{"active":true},"L2_module":{"active":false},"L3_spec_adr":{"active":true,"specs":1}},
"cross_cut":{"spirit":{"active":true},"mistakes":{"active":false,"count":0,"due_in_days":7}},
"current_task":{"domain":"test","risk":"L1"},"hud_preset":"full"}
JSON
    cat > "$HUD_TMP/.ax/current-task.json" <<JSON
{"spec_id":"005","spec_dir":".ax/docs/spec/005-test","spec_tier":"standard","phase":"implementing"}
JSON
    cat > "$HUD_TMP/.ax/docs/spec/005-test/spec.md" <<MD
# Spec
Related: ADR-0006
MD
    printf -- "- [x] T001\n- [x] T002\n- [ ] T003\n" > "$HUD_TMP/.ax/docs/spec/005-test/tasks.md"
    OUT=$(echo "{\"workspace\":{\"current_dir\":\"$HUD_TMP\"}}" | bash "$REPO/templates/default/.ax/hud/statusline.sh" 2>&1)
    # compact preset 기본 — triage 라벨 + harness 우주 이모지 + 혜성(mistakes) 검증
    if echo "$OUT" | grep -q "triage:" && echo "$OUT" | grep -qE "🪐|🌟|⭐|✦" && echo "$OUT" | grep -q "☄"; then
        pass "statusline e2e — triage + harness 이모지 + 혜성 출력"
    else
        fail "statusline e2e 출력 누락: $OUT"
    fi
    rm -rf "$HUD_TMP"
fi

# ───────────────────────────────────────────────────────────
section "7. shell script 문법 검사 — bash -n"
# ───────────────────────────────────────────────────────────
sh_count=0
sh_ok=0
while IFS= read -r f; do
    sh_count=$((sh_count+1))
    if bash -n "$f" 2>/dev/null; then
        sh_ok=$((sh_ok+1))
    else
        fail "bash 문법 오류: ${f#$REPO/}"
    fi
done < <(find "$REPO/templates/default/.ax/hooks" "$REPO/templates/default/.ax/hud" \
              "$REPO/templates/default/.ax/scripts" -name "*.sh" 2>/dev/null)
[ "$sh_count" -gt 0 ] && pass "shell 문법 $sh_ok/$sh_count" || fail "shell script 0개 검사"

# ───────────────────────────────────────────────────────────
section "8. jq syntax 검사 — state.json 갱신 패턴"
# ───────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
    pass "jq 미설치 — section 8 skip"
else
    jq_count=0
    jq_ok=0
    while IFS= read -r f; do
        # SKILL.md에서 jq state 갱신 line 추출
        line=$(grep -E "^jq '\.last_skill" "$f" 2>/dev/null | head -1)
        [ -z "$line" ] && continue
        jq_count=$((jq_count+1))
        # jq filter 부분만 추출 (작은따옴표 안)
        filter=$(echo "$line" | sed -E "s/^jq '([^']+)' .*/\1/")
        if echo '{"last_skill":"x","skill_calls":0,"updated_at":"x"}' | jq "$filter" >/dev/null 2>&1; then
            jq_ok=$((jq_ok+1))
        else
            fail "jq syntax 오류: ${f#$REPO/} → $filter"
        fi
    done < <(find "$REPO/skills" -name SKILL.md)
    [ "$jq_count" -gt 0 ] && pass "jq syntax $jq_ok/$jq_count" || fail "jq pattern 0개 발견"
fi

# ───────────────────────────────────────────────────────────
section "9. .ax/scripts/bash/ 8개 + --json + --help (NEW)"
# ───────────────────────────────────────────────────────────
SCRIPTS_DIR="$REPO/templates/default/.ax/scripts/bash"
for s in common next-spec-num tier-from-state init-spec-dir add-spec-files \
         slug-from-text check-templates-drift promote-mistake; do
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
TMP_E2E=$(mktemp -d)
mkdir -p "$TMP_E2E/.ax/docs/_templates/spec"
cp -R "$REPO/templates/default/.ax/docs/_templates/spec/." "$TMP_E2E/.ax/docs/_templates/spec/" 2>/dev/null
cp "$REPO/templates/default/.ax/current-task.json.template" "$TMP_E2E/.ax/current-task.json" 2>/dev/null
mkdir -p "$TMP_E2E/.ax/mistakes"
(
    cd "$TMP_E2E" || exit 1
    for cmd in \
        "next-spec-num.sh --json" \
        "tier-from-state.sh --json" \
        "tier-from-state.sh --json --size L --risk L3" \
        "init-spec-dir.sh --json --tier basic --slug e2e-test --dry-run" \
        "slug-from-text.sh --json 'End To End Test'" \
        "check-templates-drift.sh --json" \
        "promote-mistake.sh --json"; do
        out=$(bash "$REPO/templates/default/.ax/scripts/bash/"$cmd 2>/dev/null) || true
        if echo "$out" | jq -e '.status' >/dev/null 2>&1; then
            pass "$cmd → valid JSON"
        else
            fail "$cmd → invalid JSON: ${out:0:120}"
        fi
    done
)
rm -rf "$TMP_E2E"

# ───────────────────────────────────────────────────────────
section "10. capture-mistake.sh 런타임 — race-free ID + redactor (NEW 0.1.8)"
# ───────────────────────────────────────────────────────────
# Plugin은 실제로 사용자 프로젝트에 설치되어 동작 → 임시 fixture에서 e2e.
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/.ax"
cp -R "$REPO/templates/default/.ax/scripts" "$FIXTURE/.ax/"
cp -R "$REPO/templates/default/.ax/mistakes" "$FIXTURE/.ax/"
cp "$REPO/templates/default/.ax/config.yml" "$FIXTURE/.ax/"
( cd "$FIXTURE" && git init -q 2>/dev/null && git config user.email "smoke@local" && git config user.name "smoke" )

# 10.1 race-free ID — 5병렬 호출 → 5개 고유 파일
( cd "$FIXTURE" && \
  for i in 1 2 3 4 5; do
      CLAUDE_PROJECT_DIR=$FIXTURE bash .ax/scripts/bash/capture-mistake.sh "race-$i" "병렬 캡처 $i" "detail $i" >/dev/null 2>&1 &
  done
  wait )
RACE_COUNT=$(find "$FIXTURE/.ax/mistakes" -maxdepth 1 -type f -name "*.md" ! -name "README.md" | wc -l | tr -d ' ')
[ "$RACE_COUNT" -eq 5 ] && pass "race-free ID — 5병렬 호출 → 5개 파일" \
                       || fail "race-free ID — 5병렬에 $RACE_COUNT 파일만 생성 (충돌)"

# 10.2 redactor — DETAILS의 secret 패턴이 [REDACTED]로
rm -f "$FIXTURE/.ax/mistakes"/2026-*.md "$FIXTURE/.ax/mistakes"/[0-9]*.md
CLAUDE_PROJECT_DIR=$FIXTURE bash "$REPO/templates/default/.ax/scripts/bash/capture-mistake.sh" \
    "secrets" "PG 키 누출 의심" "config: API_KEY=abcdef1234567890XYZ leaked" >/dev/null 2>&1
LATEST=$(ls -t "$FIXTURE/.ax/mistakes"/*.md 2>/dev/null | grep -v README | head -1)
if [ -n "$LATEST" ] && grep -q "API_KEY=\[REDACTED\]" "$LATEST" 2>/dev/null; then
    pass "redactor — DETAILS의 API_KEY=... → [REDACTED]"
else
    fail "redactor — secret 미치환: $(grep API_KEY "$LATEST" 2>/dev/null || echo 'no match')"
fi

# 10.3 title 보존 — ONE_LINE은 redact되지 않아야 함 (시그널 손실 방지)
if [ -n "$LATEST" ] && grep -q "^# PG 키 누출 의심" "$LATEST" 2>/dev/null; then
    pass "title 보존 — ONE_LINE은 redact 미적용"
else
    fail "title 보존 실패: $(grep '^# ' "$LATEST" 2>/dev/null | head -1)"
fi

# 10.4 known-prefix tokens
PREFIX_TEST=$(printf 'leak: AKIAIOSFODNN7EXAMPLE and ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789a here\n' \
              | bash -c "source $REPO/templates/default/.ax/scripts/bash/common.sh && redact_secrets")
echo "$PREFIX_TEST" | grep -q "\[REDACTED:aws\]" && echo "$PREFIX_TEST" | grep -q "\[REDACTED:github\]" \
    && pass "redactor — AWS/GitHub known-prefix 치환" \
    || fail "redactor — known-prefix 누락: $PREFIX_TEST"

# 10.5 false positive guard — 짧은 값(<12자)이나 식별자는 보존
FP_TEST=$(printf 'pw=ok123 and password_field stays\n' \
          | bash -c "source $REPO/templates/default/.ax/scripts/bash/common.sh && redact_secrets")
if echo "$FP_TEST" | grep -q "ok123" && echo "$FP_TEST" | grep -q "password_field"; then
    pass "redactor — 짧은 값·식별자 false positive 없음"
else
    fail "redactor — false positive: $FP_TEST"
fi

# ───────────────────────────────────────────────────────────
section "✨ 결과"
# ───────────────────────────────────────────────────────────
if [ "$fail_count" -eq 0 ]; then
    printf '\033[32m✓ 모든 smoke 검증 통과\033[0m\n'
    exit 0
else
    printf '\033[31m✗ %s개 실패\033[0m\n' "$fail_count"
    exit 1
fi
