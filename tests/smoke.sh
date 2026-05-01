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
for s in bin/ax-first bin/ax-first-init bin/ax-first-triage bin/ax-first-audit bin/ax-first-doctor bin/ax-first-update; do
    [ -x "$REPO/$s" ] && pass "$s 실행 가능" || fail "$s 부재 또는 실행 불가"
done

# bash 문법 검사
for s in bin/ax-first bin/ax-first-* lib/*.sh templates/default/.claude/hooks/*/*.sh install.sh; do
    if [ -f "$REPO/$s" ]; then
        bash -n "$REPO/$s" && pass "syntax OK: $s" || fail "syntax error: $s"
    fi
done

# 필수 템플릿 파일
required=(
    "templates/default/CLAUDE.md.template"
    "templates/default/.ax-first/config.yml"
    "templates/default/.ax-first/mistakes/README.md"
    "templates/default/.claude/skills/_index.md"
    "templates/default/.claude/skills/global/triage/SKILL.md"
    "templates/default/.claude/skills/global/critical-rules/SKILL.md"
    "templates/default/.claude/skills/global/steering-loop/SKILL.md"
    "templates/default/.claude/skills/workflows/adr-write/SKILL.md"
    "templates/default/.claude/skills/workflows/skill-audit/SKILL.md"
    "templates/default/.claude/agents/architect.md"
    "templates/default/.claude/agents/evaluator.md"
    "templates/default/.claude/hooks/pre-bash/block-destructive.sh"
    "templates/default/.claude/hooks/pre-edit/check-protected-paths.sh"
    "templates/default/.claude/hooks/post-edit/lint-changed.sh"
    "templates/default/.claude/hooks/pre-commit/critical-rule-grep.sh"
    "templates/default/.claude/settings.json.template"
    "templates/default/docs/adr/0000-template.md"
    "templates/presets/ax/CLAUDE.md.overlay"
    "templates/presets/ax/README.md"
    "docs/concepts.md"
    "docs/customization.md"
    "docs/examples/crou-mono.md"
    "docs/examples/commerce.md"
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
section "2. ax-first init — 빈 프로젝트"
# ───────────────────────────────────────────────────────────
INIT_DIR="$TMP/proj1"
mkdir -p "$INIT_DIR"
cd "$INIT_DIR"

AX_ROOT="$REPO" AX_LIB="$REPO/lib" AX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/ax-first-init" >/dev/null 2>&1 \
  && pass "init 성공" || fail "init 실패"

[ -f CLAUDE.md ] && pass "CLAUDE.md 생성됨" || fail "CLAUDE.md 누락"
[ -f .ax-first/config.yml ] && pass ".ax-first/config.yml 생성됨" || fail "config 누락"
[ -d .claude/skills/global/triage ] && pass "triage skill 디렉토리" || fail "triage 누락"
[ -x .claude/hooks/pre-bash/block-destructive.sh ] && pass "hooks 실행 가능" || fail "hooks 권한 문제"

# ───────────────────────────────────────────────────────────
section "3. ax-first init --preset ax"
# ───────────────────────────────────────────────────────────
INIT2="$TMP/proj2"
mkdir -p "$INIT2"
cd "$INIT2"

AX_ROOT="$REPO" AX_LIB="$REPO/lib" AX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/ax-first-init" --preset ax >/dev/null 2>&1 \
  && pass "init --preset ax 성공" || fail "preset ax 실패"

grep -q "AX 프리셋" CLAUDE.md && pass "preset overlay 병합됨" || fail "overlay 누락"

# ───────────────────────────────────────────────────────────
section "4. doctor — 건강 검진"
# ───────────────────────────────────────────────────────────
cd "$INIT2"
AX_ROOT="$REPO" AX_LIB="$REPO/lib" AX_TEMPLATES="$REPO/templates" \
  bash "$REPO/bin/ax-first-doctor" >/dev/null 2>&1 \
  && pass "doctor 정상 실행" || fail "doctor 실패"

# ───────────────────────────────────────────────────────────
section "5. block-destructive hook 동작"
# ───────────────────────────────────────────────────────────
HOOK="$REPO/templates/default/.claude/hooks/pre-bash/block-destructive.sh"
CLAUDE_BASH_COMMAND="rm -rf /" bash "$HOOK" 2>/dev/null \
  && fail "rm -rf / 가 통과됨 — 차단 안 됨" \
  || pass "rm -rf / 차단됨"

CLAUDE_BASH_COMMAND="ls -la" bash "$HOOK" 2>/dev/null \
  && pass "ls -la 정상 통과" \
  || fail "정상 명령이 차단됨"

# ───────────────────────────────────────────────────────────
section "✓ 모든 smoke 테스트 통과"
# ───────────────────────────────────────────────────────────
