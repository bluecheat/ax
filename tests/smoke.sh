#!/usr/bin/env bash
# Smoke test — 기본 동작 검증
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# bash 호환성 (mktemp 출력)
[ -d "$TMP" ] || { echo "TMP dir 생성 실패"; exit 1; }

pass() { printf '\033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$*"; exit 1; }
section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# ───────────────────────────────────────────────────────────
section "1. 정적 검사"
# ───────────────────────────────────────────────────────────

# bin 스크립트 모두 존재 + 실행 가능
for s in bin/goax bin/goax-init bin/goax-triage bin/goax-audit bin/goax-doctor bin/goax-update; do
    [ -x "$REPO/$s" ] && pass "$s 실행 가능" || fail "$s 부재 또는 실행 불가"
done

# bash 문법 검사
for s in bin/goax bin/goax-* lib/*.sh templates/default/.ax/hooks/*/*.sh install.sh; do
    if [ -f "$REPO/$s" ]; then
        bash -n "$REPO/$s" && pass "syntax OK: $s" || fail "syntax error: $s"
    fi
done

# 필수 템플릿 파일
required=(
    "templates/default/CLAUDE.md.template"
    "templates/default/.ax/config.yml"
    "templates/default/.ax/mistakes/README.md"
    "templates/default/.claude/skills/_index.md"
    "templates/default/.claude/skills/global/triage/SKILL.md"
    "templates/default/.claude/skills/global/critical-rules/SKILL.md"
    "templates/default/.claude/skills/global/steering-loop/SKILL.md"
    "templates/default/.claude/skills/workflows/adr-write/SKILL.md"
    "templates/default/.claude/skills/personas/engineer-generalist/SKILL.md"
    "templates/default/.ax/spirit/README.md"
    "templates/default/.ax/spirit/values.md"
    "templates/default/.ax/spirit/tone.md"
    "templates/default/.claude/skills/meta/skill-audit/SKILL.md"
    "templates/default/.claude/skills/meta/skill-creator/SKILL.md"
    "templates/default/.claude/skills/global/triage/references/risk-matrix.md"
    "templates/default/.claude/skills/global/steering-loop/references/promotion-matrix.md"
    "docs/reference/rules-tokens.md"
    "docs/spirit.md"
    "templates/default/.claude/agents/evaluator.md"
    "templates/default/.ax/hooks/pre-bash/block-destructive.sh"
    "templates/default/.ax/hooks/pre-edit/check-protected-paths.sh"
    "templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh"
    "templates/default/.claude/settings.json.template"
    "templates/default/docs/adr/0000-template.md"
    "templates/default/docs/spec/_templates/spec.md"
    "templates/default/docs/spec/_templates/plan.md"
    "templates/default/docs/spec/_templates/tasks.md"
    "templates/default/docs/spec/_templates/checklists/requirements.md"
    "templates/default/docs/spec/_templates/research.md"
    "templates/default/docs/spec/_templates/data-model.md"
    "templates/default/docs/spec/_templates/contracts/api.yaml"
    "templates/default/docs/spec/_templates/contracts/events.md"
    "templates/default/docs/spec/_templates/quickstart.md"
    "templates/default/docs/spec/_templates/README.md"
    "docs/concepts.md"
    "docs/customization.md"
)
for f in "${required[@]}"; do
    [ -f "$REPO/$f" ] && pass "exists: $f" || fail "missing: $f"
done

# settings.json.template은 valid JSON
if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json; json.load(open('$REPO/templates/default/.claude/settings.json.template'))" \
      && pass "settings.json.template JSON valid" \
      || fail "settings.json.template JSON invalid"
fi

# ───────────────────────────────────────────────────────────
section "2. goax up — 빈 프로젝트"
# ───────────────────────────────────────────────────────────
INIT_DIR="$TMP/proj1"
mkdir -p "$INIT_DIR"
cd "$INIT_DIR"

GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" GOAX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/goax-init" >/dev/null 2>&1 \
  && pass "init 성공" || fail "init 실패"

[ -f CLAUDE.md ] && pass "CLAUDE.md 생성됨" || fail "CLAUDE.md 누락"
[ -f .ax/config.yml ] && pass ".ax/config.yml 생성됨" || fail "config 누락"
[ -d .claude/skills/global/triage ] && pass "triage skill 디렉토리" || fail "triage 누락"
[ -x .ax/hooks/pre-bash/block-destructive.sh ] && pass "hooks 실행 가능" || fail "hooks 권한 문제"

# ───────────────────────────────────────────────────────────
section "4. doctor — 건강 검진"
# ───────────────────────────────────────────────────────────
INIT2="$TMP/proj2"
mkdir -p "$INIT2"
cd "$INIT2"
GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" GOAX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/goax-init" >/dev/null 2>&1
GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" GOAX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/goax-doctor" >/dev/null 2>&1 \
  && pass "doctor 정상 실행" || fail "doctor 실패"

# ───────────────────────────────────────────────────────────
section "5. block-destructive hook 동작"
# ───────────────────────────────────────────────────────────
HOOK="$REPO/templates/default/.ax/hooks/pre-bash/block-destructive.sh"
CLAUDE_BASH_COMMAND="rm -rf /" bash "$HOOK" 2>/dev/null \
  && fail "rm -rf / 가 통과됨 — 차단 안 됨" \
  || pass "rm -rf / 차단됨"

CLAUDE_BASH_COMMAND="ls -la" bash "$HOOK" 2>/dev/null \
  && pass "ls -la 정상 통과" \
  || fail "정상 명령이 차단됨"

# ───────────────────────────────────────────────────────────
section "6. goax rules — preset starter 룰 인덱스"
# ───────────────────────────────────────────────────────────
INIT3="$TMP/proj3"
mkdir -p "$INIT3"
cd "$INIT3"
GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" GOAX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/goax-init" --preset starter >/dev/null 2>&1

rules_output=$(GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" bash "$REPO/bin/goax-rules" 2>/dev/null || true)
if echo "$rules_output" | grep -qE "(CRITICAL|MANDATORY|CONVENTION):[0-9]+"; then
    pass "rules 인덱스 동작"
else
    fail "rules 0개 매칭"
fi

if GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" \
   bash "$REPO/bin/goax-find" starter:CRITICAL:001 >/dev/null 2>&1; then
    pass "find 동작 (starter:CRITICAL:001)"
else
    fail "find 실패"
fi


# ───────────────────────────────────────────────────────────
section "7. goax spirit (v0.3) — 디렉토리 + lint + status"
# ───────────────────────────────────────────────────────────
INIT4="$TMP/proj4"
mkdir -p "$INIT4"
cd "$INIT4"
GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" GOAX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/goax-init" --preset starter >/dev/null 2>&1

# spirit/ 디렉토리 + 핵심 파일
[ -f .ax/spirit/values.md ] && pass "spirit/values.md 생성" || fail "values.md 누락"
[ -f .ax/spirit/tone.md ] && pass "spirit/tone.md 생성" || fail "tone.md 누락"
[ -d .ax/spirit/rules ] && pass "spirit/rules/ 디렉토리" || fail "rules/ 디렉토리 누락"

rules_count=$(ls .ax/spirit/rules/*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$rules_count" -ge "1" ]; then
    pass "spirit/rules/ 디렉토리 (default: _TEMPLATE.md)"
else
    fail "spirit rules 디렉토리 비어있음"
fi

# goax spirit lint
spirit_out=$(GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" bash "$REPO/bin/goax-spirit" lint 2>&1 || true)
if echo "$spirit_out" | grep -q "lint 통과"; then
    pass "spirit lint 통과"
else
    fail "spirit lint 실패: $spirit_out"
fi

# goax rules --source spirit
rules_out=$(GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" bash "$REPO/bin/goax-rules" --source spirit 2>/dev/null || true)
if echo "$rules_out" | grep -qE "SP-[A-Z]+-[0-9]+"; then
    pass "rules --source spirit 동작"
else
    fail "rules --source spirit 매칭 0"
fi

# goax find SP-SEC-001
if GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" bash "$REPO/bin/goax-find" SP-SEC-001 >/dev/null 2>&1; then
    pass "find SP-SEC-001 동작"
else
    fail "find SP-SEC-001 실패"
fi


# ───────────────────────────────────────────────────────────
section "8. goax up (v0.4) — discover + plan dry-run"
# ───────────────────────────────────────────────────────────
INIT5="$TMP/proj5"
mkdir -p "$INIT5/apps/api/src" "$INIT5/apps/web/src"
cd "$INIT5"
# 가짜 CLAUDE.md
cat > CLAUDE.md <<'FAKE'
# Test
- NEVER hardcode passwords
- naming: kebab-case
FAKE

# dry-run으로 discover + plan만 (apply 안 됨)
out=$(GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" GOAX_TEMPLATES="$REPO/templates" \
    bash "$REPO/bin/goax-up" --dry-run --auto a,a,a,a 2>&1 || true)
if echo "$out" | grep -qE "Discover|프로젝트 분석"; then pass "up Discover 동작"; else fail "Discover 누락"; fi
if echo "$out" | grep -qE "결정 4개|Plan"; then pass "up Plan 동작"; else fail "Plan 누락"; fi
if echo "$out" | grep -qE "모노레포|싱글"; then pass "discover 레포 형태 감지"; else fail "레포 형태 감지 실패"; fi
if echo "$out" | grep -q "DRY-RUN"; then pass "dry-run 모드 — apply 안 함"; else fail "dry-run 미작동"; fi


# ───────────────────────────────────────────────────────────
section "9. goax spec (v0.6) — SDD 워크플로우"
# ───────────────────────────────────────────────────────────
INIT5="$TMP/proj_spec"
mkdir -p "$INIT5"
cd "$INIT5"
GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" GOAX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/goax-init" >/dev/null 2>&1

# spec new
spec_out=$(GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" \
  bash "$REPO/bin/goax-spec" new test-feature 2>&1 || true)
if echo "$spec_out" | grep -q "001-test-feature"; then
    pass "spec new — 디렉토리 자동 생성"
else
    fail "spec new 실패"
fi

# spec list
list_out=$(GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" \
  bash "$REPO/bin/goax-spec" list 2>&1 || true)
if echo "$list_out" | grep -q "test-feature"; then
    pass "spec list — 등록된 spec 인식"
else
    fail "spec list 실패"
fi

# spec check (NEEDS CLARIFICATION 미해소 → fail 정상)
check_out=$(GOAX_ROOT="$REPO" GOAX_LIB="$REPO/lib" bash "$REPO/bin/goax-spec" check 2>&1 || true)
if echo "$check_out" | grep -q "NEEDS CLARIFICATION"; then
    pass "spec check — NEEDS CLARIFICATION 게이팅 동작"
else
    fail "spec check 게이팅 미작동"
fi

# ───────────────────────────────────────────────────────────
section "✓ 모든 smoke 테스트 통과"
# ───────────────────────────────────────────────────────────
