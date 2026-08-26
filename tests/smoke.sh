#!/usr/bin/env bash
# tests/smoke.sh — goax Plugin 구조 검증
# 검증: 파일 구조·JSON 유효성·skill/agent frontmatter·shell 문법·jq syntax·hook 경로 양방향
#       cross-check·MANIFEST 완전성·버전 마커 lint·scripts/bash 런타임 e2e

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
VER_MARKET_PLUGIN=$(python3 -c "import json; d=json.load(open('$REPO/.claude-plugin/marketplace.json')); print(d['plugins'][0]['version'])" 2>/dev/null)
[ "$VER_FILE" = "$VER_PLUGIN" ] && pass "VERSION ↔ plugin.json (=$VER_FILE)" || fail "VERSION/plugin.json 불일치 ($VER_FILE vs $VER_PLUGIN)"
[ "$VER_FILE" = "$VER_MARKET" ] && pass "VERSION ↔ marketplace.json (=$VER_FILE)" || fail "VERSION/marketplace.json 불일치 ($VER_FILE vs $VER_MARKET)"
[ "$VER_FILE" = "$VER_MARKET_PLUGIN" ] && pass "VERSION ↔ marketplace.json plugins[0].version (=$VER_FILE)" \
    || fail "VERSION/marketplace.json plugins[0].version 불일치 ($VER_FILE vs $VER_MARKET_PLUGIN)"

# changelog/<VERSION>.md 존재 — 릴리즈 시 CHANGELOG 기록 강제
CHANGELOG_FILE="$REPO/changelog/$VER_FILE.md"
[ -n "$VER_FILE" ] && [ -f "$CHANGELOG_FILE" ] \
    && pass "changelog/$VER_FILE.md 존재" \
    || fail "changelog/$VER_FILE.md 누락 (VERSION=$VER_FILE)"

# ───────────────────────────────────────────────────────────
section "2. skills/ — name: frontmatter가 디렉토리명과 일치하는지 (전체 동적 순회)"
# ───────────────────────────────────────────────────────────
skill_name_count=0
while IFS= read -r f; do
    skill_name_count=$((skill_name_count+1))
    skill="$(basename "$(dirname "$f")")"
    if head -5 "$f" | grep -qE "^name: $skill\$"; then
        pass "skills/$skill/SKILL.md (frontmatter name=$skill)"
    else
        fail "skills/$skill/SKILL.md frontmatter name 불일치 (디렉토리=$skill)"
    fi
done < <(find "$REPO/skills" -name SKILL.md | sort)
[ "$skill_name_count" -gt 0 ] || fail "skills/*/SKILL.md 0개 — skills/ 구조 확인 필요"

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
section "2.5 Slash commands — thin wrapper 폐기, /goax 인덱스 1개만 유지"
# ───────────────────────────────────────────────────────────
# 모든 skill 은 SKILL.md frontmatter 의 자연어 키워드 트리거로 호출. /goax 인덱스
# 1개만 discoverability 진입점으로 남김.
f="$REPO/commands/goax.md"
if [ -f "$f" ]; then
    head -5 "$f" | grep -qE '^name: goax$' \
        && pass "commands/goax.md (인덱스 frontmatter OK)" \
        || fail "commands/goax.md frontmatter name 불일치"
else
    fail "commands/goax.md 누락"
fi

# 폐기된 skill별 thin wrapper 가 잔재로 남지 않았는지 확인
for removed in goax-up goax-onboarding goax-doctor goax-audit goax-rules goax-hud goax-spirit \
               goax-triage goax-adr goax-spec goax-spec-validate goax-spec-tasks goax-spec-implement; do
    if [ -e "$REPO/commands/$removed.md" ]; then
        fail "commands/$removed.md — thin wrapper 폐기됐어야 함 (잔재)"
    fi
done
# 폐기 잔재 0 확인 후 단일 pass
pass "commands/ — thin wrapper 폐기 완료 (잔재 0)"

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

# agents/*.md frontmatter — name + description 필수 (동적 순회)
agent_fm_count=0
while IFS= read -r f; do
    agent_fm_count=$((agent_fm_count+1))
    agent="$(basename "$f" .md)"
    has_name=$(head -5 "$f" | grep -cE "^name: $agent\$" || true)
    has_desc=$(head -10 "$f" | grep -cE "^description:" || true)
    if [ "$has_name" -ge 1 ] && [ "$has_desc" -ge 1 ]; then
        pass "agents/$agent.md (frontmatter name+description OK)"
    else
        fail "agents/$agent.md frontmatter 누락 (name=$has_name, description=$has_desc)"
    fi
done < <(find "$REPO/agents" -name "*.md" | sort)
[ "$agent_fm_count" -gt 0 ] || fail "agents/*.md 0개 — agents/ 구조 확인 필요"

# ───────────────────────────────────────────────────────────
section "4. templates/default — up skill 이 사용자 프로젝트로 복사할 자산"
# ───────────────────────────────────────────────────────────
for f in \
    templates/default/AGENTS.md.template \
    templates/default/CLAUDE.md.template \
    templates/default/opencode.json.template \
    templates/default/.claude/settings.json.template \
    templates/default/.gitignore.template \
    templates/default/.ax/hooks/pre-commit/check-mistake-secrets.sh \
    templates/default/.ax/scripts/bash/install-git-hooks.sh \
    templates/default/.ax/spirit/values.md \
    templates/default/.ax/spirit/tone.md \
    templates/default/.ax/_templates/spirit/rule.md \
    templates/default/.ax/_templates/module/rules.md \
    templates/default/.ax/_templates/mistakes/mistake.md \
    templates/default/.ax/config.yml \
    templates/default/.ax/mistakes/README.md \
    templates/default/.ax/hooks/pre-bash/block-destructive.sh \
    templates/default/.ax/hooks/pre-edit/check-protected-paths.sh \
    templates/default/.ax/hooks/pre-edit/spirit-check.sh \
    templates/default/.ax/hooks/post-edit/lint-changed.sh \
    templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh \
    templates/default/.ax/_templates/adr/0000-template.md \
    templates/default/.ax/_templates/spec/spec.md \
    templates/default/.ax/_templates/spec/tasks.md \
    templates/default/.ax/_templates/spec/checklists/requirements.md \
    templates/default/.ax/_templates/spec/research.md \
    templates/default/.ax/_templates/spec/data-model.md \
    templates/default/.ax/_templates/spec/contracts/api.yaml \
    templates/default/.ax/_templates/spec/contracts/events.md \
    templates/default/.ax/_templates/spec/quickstart.md \
    templates/default/.ax/current-task.json.template \
    templates/default/.ax/scripts/bash/README.md \
    templates/default/.ax/scripts/bash/common.sh \
    templates/default/.ax/scripts/bash/next-spec-num.sh \
    templates/default/.ax/scripts/bash/tier-from-state.sh \
    templates/default/.ax/scripts/bash/init-spec-dir.sh \
    templates/default/.ax/scripts/bash/add-spec-files.sh \
    templates/default/.ax/scripts/bash/check-spec-clarity.sh \
    templates/default/.ax/scripts/bash/slug-from-text.sh \
    templates/default/.ax/scripts/bash/check-templates-drift.sh \
    templates/default/.ax/scripts/bash/check-manifest-install.sh \
    templates/default/.ax/scripts/bash/check-rule-enforcement.sh \
    templates/default/.ax/scripts/bash/check-sensor-liveness.sh \
    templates/default/.ax/scripts/bash/promote-mistake.sh
do
    [ -f "$REPO/$f" ] && pass "$f" || fail "$f 누락"
done

python3 -c "import json; json.load(open('$REPO/templates/default/.claude/settings.json.template'))" 2>/dev/null \
    && pass "settings.json.template JSON valid" \
    || fail "settings.json.template JSON invalid"

# opencode.json.template JSON valid + schema URL 검증
python3 -c "import json; d=json.load(open('$REPO/templates/default/opencode.json.template')); assert d['\$schema']=='https://opencode.ai/config.json', d['\$schema']" 2>/dev/null \
    && pass "opencode.json.template JSON valid + \$schema = opencode.ai/config.json" \
    || fail "opencode.json.template JSON invalid 또는 \$schema 불일치"

# opencode.json.template 의 instructions 에 AGENTS.md 포함
python3 -c "import json; d=json.load(open('$REPO/templates/default/opencode.json.template')); assert 'AGENTS.md' in d.get('instructions', []), d.get('instructions')" 2>/dev/null \
    && pass "opencode.json.template instructions[] 에 AGENTS.md 포함" \
    || fail "opencode.json.template instructions[] 에 AGENTS.md 누락"

# CLAUDE.md.template 이 @AGENTS.md import 한 줄 + 안내 (20줄 미만)
CLAUDE_LINES=$(wc -l < "$REPO/templates/default/CLAUDE.md.template" | tr -d ' ')
if [ "$CLAUDE_LINES" -lt 20 ] && grep -qE '^@AGENTS\.md\b' "$REPO/templates/default/CLAUDE.md.template"; then
    pass "CLAUDE.md.template — @AGENTS.md alias 형태 (${CLAUDE_LINES}줄 < 20)"
else
    fail "CLAUDE.md.template — alias 형태 아님 (${CLAUDE_LINES}줄, @AGENTS.md import 누락 가능)"
fi

# AGENTS.md.template 이 Constitution SSOT (META + 시그널 의미 + 4계층 인덱스)
if grep -q "META — 핵심 가드레일" "$REPO/templates/default/AGENTS.md.template" \
   && grep -q "시그널 의미" "$REPO/templates/default/AGENTS.md.template" \
   && grep -q "4계층 인덱스" "$REPO/templates/default/AGENTS.md.template"; then
    pass "AGENTS.md.template — META + 시그널 의미 + 4계층 인덱스 포함 (Constitution SSOT)"
else
    fail "AGENTS.md.template — Constitution 필수 섹션 누락"
fi

python3 -c "import json; json.load(open('$REPO/templates/default/.ax/current-task.json.template'))" 2>/dev/null \
    && pass "current-task.json.template JSON valid" \
    || fail "current-task.json.template JSON invalid"

# .gitignore.template — runtime 엔트리 4종 모두 포함하는지 검증.
GI_TPL="$REPO/templates/default/.gitignore.template"
if [ -f "$GI_TPL" ]; then
    missing=0
    for entry in ".ax/state.json" ".ax/current-task.json" ".ax/*.suggested" ".ax/.onboarding-pending"; do
        grep -qxF "$entry" "$GI_TPL" || { fail ".gitignore.template 누락 엔트리: $entry"; missing=$((missing+1)); }
    done
    [ "$missing" -eq 0 ] && pass ".gitignore.template — runtime 엔트리 4종 모두 포함"
fi

# 잔재 검증 — spirit/rules/output-style.md (plugin meta로 분류되어 출고에서 제거됨)
[ -f "$REPO/templates/default/.ax/spirit/rules/output-style.md" ] \
    && fail "spirit/rules/output-style.md — plugin 출고 제거됐어야 함 (plugin meta)" \
    || pass "spirit/rules/output-style.md 출고 제거됨"

# ───────────────────────────────────────────────────────────
section "4.1 settings.json.template ↔ .ax/hooks/ 양방향 cross-check"
# ───────────────────────────────────────────────────────────
# 정방향: settings.json.template 이 참조하는 .ax/... 경로가 실제로 존재하는지.
# 역방향: .ax/hooks/{user-prompt,pre-bash,pre-edit,post-edit}/*.sh 가 모두 등록됐는지
#         (pre-commit/ 은 grep-on-commit.sh + install-git-hooks.sh 체이닝으로 별도 등록되므로 예외).
# 실제 구조는 hooks[phase][n]['hooks'][m]['command'] 깊이이고 command 는
# `bash "${CLAUDE_PROJECT_DIR}/.ax/hooks/pre-bash/block-destructive.sh"` 형태라 .ax/ 부분만 추출.
# fail() 을 파이프 서브셸 밖(here-string)에서 호출해야 fail_count 가 유실되지 않음.
HOOK_XCHECK=$(python3 <<PYEOF
import json, os, re, glob
tpl = "$REPO/templates/default"
d = json.load(open(os.path.join(tpl, ".claude/settings.json.template")))
hooks = d.get("hooks", {})
registered = set()
for phase, items in hooks.items():
    for item in items:
        for h in item.get("hooks", []):
            cmd = h.get("command", "")
            m = re.search(r'\.ax/[^"\s]+\.sh', cmd)
            if m:
                registered.add(m.group(0))
lines = []
for path in sorted(registered):
    full = os.path.join(tpl, path)
    lines.append("FWD|%s|%d" % (path, 1 if os.path.isfile(full) else 0))
for phase in ["user-prompt", "pre-bash", "pre-edit", "post-edit"]:
    for f in sorted(glob.glob(os.path.join(tpl, ".ax/hooks", phase, "*.sh"))):
        rel = os.path.relpath(f, tpl)
        lines.append("REV|%s|%d" % (rel, 1 if rel in registered else 0))
print("\n".join(lines))
PYEOF
)
if [ -z "$HOOK_XCHECK" ]; then
    fail "4.1 hook cross-check — python 실행 실패 또는 settings.json.template 파싱 오류"
else
    while IFS='|' read -r kind relpath ok; do
        [ -z "$kind" ] && continue
        case "$kind" in
            FWD)
                if [ "$ok" = "1" ]; then
                    pass "settings.json → $relpath (실존)"
                else
                    fail "settings.json → $relpath 누락 (런타임 깨짐)"
                fi
                ;;
            REV)
                if [ "$ok" = "1" ]; then
                    pass "$relpath → settings.json.template 등록됨"
                else
                    fail "$relpath → settings.json.template 미등록 (hook 안 걸림)"
                fi
                ;;
        esac
    done <<< "$HOOK_XCHECK"
fi

# ───────────────────────────────────────────────────────────
section "4.2 MANIFEST 완전성 — templates/default 전체 파일이 MANIFEST 또는 조건부 복사로 커버되는지"
# ───────────────────────────────────────────────────────────
# skills/up/SKILL.md §5-§6 이 실제로 처리하는 조건부(manifest 외) 파일 목록.
# 이 목록과 up SKILL.md 본문이 벌어지면 이 테스트도 같이 갱신해야 함.
CONDITIONAL_COPIES="AGENTS.md.template CLAUDE.md.template opencode.json.template \
.claude/settings.json.template .ax/config.yml .ax/search-aliases.yml \
.ax/mistakes/README.md .ax/spirit/values.md .ax/spirit/tone.md .ax/spirit/README.md \
.gitignore.template"

MANIFEST_CHECK=$(python3 <<PYEOF
import os
tpl = "$REPO/templates/default"
manifest = os.path.join(tpl, "MANIFEST")
dirs = []
renames = {}
singles = []
with open(manifest) as fh:
    for line in fh:
        line = line.rstrip("\n")
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if " -> " in line:
            src, dst = line.split(" -> ", 1)
            renames[src.strip()] = dst.strip()
        elif line.endswith("/"):
            dirs.append(line)
        else:
            singles.append(line)

lines = []
# MANIFEST source 실존 검증
for d in dirs:
    full = os.path.join(tpl, d)
    lines.append("SRC|%s|%d" % (d, 1 if os.path.isdir(full) else 0))
for s in singles:
    full = os.path.join(tpl, s)
    lines.append("SRC|%s|%d" % (s, 1 if os.path.isfile(full) else 0))
for src in renames:
    full = os.path.join(tpl, src)
    lines.append("SRC|%s|%d" % (src, 1 if os.path.isfile(full) else 0))

conditional = set("$CONDITIONAL_COPIES".split())

def covered(relpath):
    if relpath in singles or relpath in renames:
        return True
    if relpath in conditional:
        return True
    for d in dirs:
        if relpath.startswith(d):
            return True
    return False

# 런타임/도구가 templates/ 안에 흘린 산출물은 MANIFEST 대상이 아니에요.
# (.omc/ 는 OMC 세션 상태, .git/ 는 worktree, 나머지는 흔한 캐시)
NOISE_DIRS = {".omc", ".git", "node_modules", "__pycache__", ".pytest_cache", ".venv"}
NOISE_FILES = {".DS_Store"}

orphans = []
for root, subdirs, files in os.walk(tpl):
    subdirs[:] = [d for d in subdirs if d not in NOISE_DIRS]
    for fn in files:
        if fn in NOISE_FILES:
            continue
        full = os.path.join(root, fn)
        rel = os.path.relpath(full, tpl)
        if rel == "MANIFEST":
            continue
        if not covered(rel):
            orphans.append(rel)

for o in sorted(orphans):
    lines.append("ORPHAN|%s|0" % o)

print("\n".join(lines))
PYEOF
)
if [ -z "$MANIFEST_CHECK" ]; then
    fail "4.2 MANIFEST 완전성 — python 실행 실패"
else
    manifest_src_missing=0
    manifest_orphan_count=0
    while IFS='|' read -r kind relpath ok; do
        [ -z "$kind" ] && continue
        case "$kind" in
            SRC)
                if [ "$ok" != "1" ]; then
                    fail "MANIFEST source 누락: $relpath"
                    manifest_src_missing=$((manifest_src_missing+1))
                fi
                ;;
            ORPHAN)
                fail "MANIFEST 미커버 (orphan): $relpath"
                manifest_orphan_count=$((manifest_orphan_count+1))
                ;;
        esac
    done <<< "$MANIFEST_CHECK"
    [ "$manifest_src_missing" -eq 0 ] && pass "MANIFEST 모든 source 경로 실존"
    [ "$manifest_orphan_count" -eq 0 ] && pass "templates/default/ 전체 파일이 MANIFEST/조건부 복사로 커버됨 (orphan 0)"
fi

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
"hud_preset":"full"}
JSON
    # .ax/current-task.json 이 triage(size/risk) SSOT — state.json.current_task 는 갖지 않음.
    # phase=idle(또는 size/risk 미채움)이면 statusline 이 triage fragment 를 숨기므로
    # phase!=idle + size/risk 둘 다 채워야 e2e 가 triage: 라벨을 검증할 수 있음.
    cat > "$HUD_TMP/.ax/current-task.json" <<JSON
{"spec_id":"005","spec_dir":".ax/docs/spec/005-test","spec_tier":"standard","phase":"implementing","size":"M","risk":"L1"}
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
section "9. .ax/scripts/bash/ 핵심 스크립트 — 문법 + 실행권한 + e2e JSON"
# ───────────────────────────────────────────────────────────
SCRIPTS_DIR="$REPO/templates/default/.ax/scripts/bash"
for s in common next-spec-num tier-from-state init-spec-dir add-spec-files \
         check-spec-clarity slug-from-text check-templates-drift check-manifest-install promote-mistake \
         check-rule-enforcement check-sensor-liveness \
         build-memory build-index; do
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
    "init-spec-dir.sh --json --tier standard --slug e2e-test --dry-run" \
    "slug-from-text.sh --json 'End To End Test'" \
    "check-templates-drift.sh --json" \
    "check-manifest-install.sh --json --plugin-dir $REPO" \
    "check-rule-enforcement.sh --json" \
    "check-sensor-liveness.sh --json" \
    "promote-mistake.sh --json" \
    "build-memory.sh --json" \
    "build-index.sh --json"; do
    out=$(bash "$REPO/templates/default/.ax/scripts/bash/"$cmd 2>/dev/null) || true
    if echo "$out" | jq -e '.status' >/dev/null 2>&1; then
        pass "$cmd → valid JSON"
    else
        fail "$cmd → invalid JSON: ${out:0:120}"
    fi
done
popd >/dev/null || true
rm -rf "$TMP_E2E"

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
US_FX=$(mktemp -d)
mkdir -p "$US_FX/.ax/spirit/rules" "$US_FX/.ax/scripts/bash" "$US_FX/.ax/modules" "$US_FX/.ax/docs/adr" "$US_FX/.ax/docs/spec"
cp "$REPO/templates/default/.ax/scripts/bash/"{common.sh,update-state.sh} "$US_FX/.ax/scripts/bash/"
cp "$REPO/templates/default/.ax/hud/state.json.template" "$US_FX/.ax/state.json"
cat > "$US_FX/CLAUDE.md" <<'MD'
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

    [ "$CRIT" = "2" ] && pass "update-state — CRITICAL=2 (CLAUDE.md inline)" \
                      || fail "update-state — CRITICAL=$CRIT (expected 2)"
    [ "$MAND" = "1" ] && pass "update-state — MANDATORY=1" \
                      || fail "update-state — MANDATORY=$MAND (expected 1)"
    # CONV: inline 1 (CLAUDE.md) + spirit heading 2 = 3
    [ "$CONV" = "3" ] && pass "update-state — CONVENTION=3 (1 inline + 2 spirit heading)" \
                      || fail "update-state — CONVENTION=$CONV (expected 3, heading 패턴 합산)"
    [ "$L1_ACTIVE" = "true" ] && pass "update-state — L1 active (rules > 0)" \
                              || fail "update-state — L1 active=$L1_ACTIVE"
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

# ───────────────────────────────────────────────────────────
section "15. PR #1085 review fixes — security/correctness/escape"
# ───────────────────────────────────────────────────────────

# 15.1 block-destructive — rm variants + git push variants
# capture-mistake.sh 폐기 후 — block-destructive 가 더 이상 호출 안 함.
BD_FX=$(mktemp -d)
mkdir -p "$BD_FX/.ax/scripts/bash" "$BD_FX/.ax/hooks/pre-bash"
cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$BD_FX/.ax/scripts/bash/"
cp "$REPO/templates/default/.ax/hooks/pre-bash/block-destructive.sh" "$BD_FX/.ax/hooks/pre-bash/"

assert_blocked() {
    local cmd="$1"; local label="$2"
    local exit_code
    echo "{\"tool_input\":{\"command\":\"$cmd\"}}" \
        | CLAUDE_PROJECT_DIR=$BD_FX bash "$BD_FX/.ax/hooks/pre-bash/block-destructive.sh" >/dev/null 2>&1
    exit_code=$?
    if [ "$exit_code" -eq 2 ]; then pass "block-destructive 차단: $label ('$cmd')"
    else fail "block-destructive 미차단 (exit=$exit_code): $label ('$cmd')"; fi
}
assert_passed() {
    local cmd="$1"; local label="$2"
    local exit_code
    echo "{\"tool_input\":{\"command\":\"$cmd\"}}" \
        | CLAUDE_PROJECT_DIR=$BD_FX bash "$BD_FX/.ax/hooks/pre-bash/block-destructive.sh" >/dev/null 2>&1
    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then pass "block-destructive 통과: $label ('$cmd')"
    else fail "block-destructive 잘못 차단 (exit=$exit_code): $label ('$cmd')"; fi
}

# CATASTROPHIC — 항상 차단
assert_blocked 'rm -rf /'    'rm -rf /'
assert_blocked 'rm -fr /'    'rm -fr / variant (fr 순서)'
assert_blocked 'rm -rfv /'   'rm -rfv / (verbose flag)'
assert_blocked 'rm -fvR /'   'rm -fvR / (대소문자 혼합)'
assert_blocked 'rm -r -f /'  'rm -r -f / (multi-chunk)'
assert_blocked 'rm -rf -- /' 'rm -rf -- / (end-of-options sentinel)'
assert_blocked 'mkfs.ext4 /dev/sda1' 'mkfs.* (디스크 포맷)'

# RECOVERABLE — warning mode에선 통과 (exit 0)
assert_passed 'git push --force'                      'EOL --force (이전 미매칭)'
assert_passed 'git push --force-with-lease'           '--force-with-lease (recoverable)'
assert_passed 'git push origin main --force'          'remote/ref 사이에 --force (이전 우회 케이스)'
assert_passed 'git push origin -f'                    'remote 다음 -f'

# 안전 명령 — 통과
assert_passed 'rm /tmp/x'    'rm 단일 파일 (no -r)'
assert_passed 'rm -v /tmp/x' 'rm -v 단일 파일 (verbose only)'
assert_passed 'ls -la'       'ls (무관)'

# CATASTROPHIC — 표기 변형 우회 (regression lock)
# `rm -rf /` 는 OS(rm --preserve-root)가 이미 거부해요. 실제로 통하는 건 아래 형태들이라
# 이쪽을 못 잡으면 안전망이 의미가 없어요. 한 번 뚫렸던 케이스이므로 고정합니다.
assert_blocked 'rm -rf /*'                 'rm -rf /* (루트 글롭 — OS 가 안 막는 실제 위험)'
assert_blocked 'rm -rf \"/\"'               'rm -rf \"/\" (따옴표 우회)'
assert_blocked 'rm -rf /usr /etc'          'rm -rf 시스템 디렉토리'
assert_blocked 'rm --recursive --force /'  'long option (--recursive/--force)'
assert_blocked 'rm -rf /System'            'macOS 시스템 디렉토리'
assert_blocked 'rm -rf ~'                  'rm -rf ~ (홈 전체)'
assert_blocked 'find / -delete'            'find / -delete'
assert_blocked 'find /usr -exec rm {} +'   'find -exec rm'
assert_blocked 'chmod -R 777 /'            'chmod -R 777 /'

# false positive 방지 — 일상 작업은 반드시 통과해야 함
assert_passed 'rm -rf node_modules'        'rm -rf node_modules (일상)'
assert_passed 'rm -rf /tmp/build-cache'    'rm -rf /tmp 하위 (루트 아님)'
assert_passed 'rm -rf ./dist'              'rm -rf ./dist'
assert_passed 'git rm -r --cached .intro'  'git rm -r --cached'
assert_passed 'find . -name x -delete'     'find . -delete (루트 아님)'
assert_passed 'grep -r / etc/hosts'        'grep -r (rm 아님)'

rm -rf "$BD_FX"

# 15.1b check-protected-paths — 경로 정규화 + 경계 매칭 + YAML 파싱
PP_FX=$(mktemp -d)
mkdir -p "$PP_FX/.ax/scripts/bash" "$PP_FX/.ax/hooks/pre-edit"
cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$PP_FX/.ax/scripts/bash/"
cp "$REPO/templates/default/.ax/hooks/pre-edit/check-protected-paths.sh" "$PP_FX/.ax/hooks/pre-edit/"

pp_config() { printf '%s' "$1" > "$PP_FX/.ax/config.yml"; }
assert_pp() {
    local want="$1" path="$2" label="$3" out got
    out=$(printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$path" | jq -Rs .)" \
        | CLAUDE_PROJECT_DIR=$PP_FX bash "$PP_FX/.ax/hooks/pre-edit/check-protected-paths.sh" 2>/dev/null)
    got=ALLOW; printf '%s' "$out" | grep -q '"deny"' && got=DENY
    if [ "$got" = "$want" ]; then pass "check-protected-paths $want: $label"
    else fail "check-protected-paths want=$want got=$got: $label ('$path')"; fi
}

pp_config 'sensors:
  mode: fail
  protected_paths:
    - CLAUDE.md
    - .ax/spirit
    - .ax/hooks/
'
# 표기 변형으로 보호를 우회할 수 없어야 함 (regression lock)
assert_pp DENY  "$PP_FX/CLAUDE.md"                'absolute path'
assert_pp DENY  'CLAUDE.md'                       'relative path'
assert_pp DENY  './CLAUDE.md'                     './ 접두'
assert_pp DENY  "$PP_FX/./CLAUDE.md"              '경로 내 ./'
assert_pp DENY  "$PP_FX/.ax/../CLAUDE.md"         '.. 경유 비정규화'
assert_pp DENY  "$PP_FX/.ax//spirit/values.md"    '중복 슬래시'
assert_pp DENY  "$PP_FX/.ax/hooks/pre-bash/x.sh"  '디렉토리 패턴 하위'
# 경계 검사 — 접두만 같은 무관 파일은 오탐되면 안 됨
assert_pp ALLOW "$PP_FX/CLAUDE.md.bak"            '경계 검사 (CLAUDE.md.bak 오탐 방지)'
assert_pp ALLOW "$PP_FX/.ax/spirit-notes.md"      '경계 검사 (spirit-notes 오탐 방지)'
assert_pp ALLOW "$PP_FX/src/main.ts"              '무관 파일'

# 최상위(들여쓰기 0) YAML 도 파싱돼야 함 — awk range 붕괴로 조용히 꺼지던 케이스
pp_config 'protected_paths:
  - CLAUDE.md
sensors:
  mode: fail
'
assert_pp DENY "$PP_FX/CLAUDE.md" 'top-level protected_paths (silent no-op 회귀 방지)'

rm -rf "$PP_FX"

# 15.1c common.sh 경로 헬퍼 단위 검증
assert_helper() {
    local want="$1" got="$2" label="$3"
    if [ "$got" = "$want" ]; then pass "common.sh $label"
    else fail "common.sh $label — want='$want' got='$got'"; fi
}
HELPER_OUT=$(bash -c "source '$REPO/templates/default/.ax/scripts/bash/common.sh'
    goax_normalize_path '/p/a/../b//c' /p")
assert_helper '/p/b/c' "$HELPER_OUT" 'goax_normalize_path — ../ 및 중복 슬래시 해소'
HELPER_OUT=$(bash -c "source '$REPO/templates/default/.ax/scripts/bash/common.sh'
    goax_normalize_path './x.md' /p")
assert_helper '/p/x.md' "$HELPER_OUT" 'goax_normalize_path — 상대경로 → 절대경로'
if bash -c "source '$REPO/templates/default/.ax/scripts/bash/common.sh'
    goax_path_under 'CLAUDE.md.bak' 'CLAUDE.md'" 2>/dev/null; then
    fail "common.sh goax_path_under — CLAUDE.md.bak 오탐"
else
    pass "common.sh goax_path_under — 경계 검사 (오탐 없음)"
fi

# 15.2 common.sh _goax_json_array — special char escape
COM_FX=$(mktemp -d)
mkdir -p "$COM_FX/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$COM_FX/.ax/scripts/bash/"

JSON_OUT=$(bash -c "
source $COM_FX/.ax/scripts/bash/common.sh
JSON_MODE=true
goax_error 'msg with \"q\" and \\\\b'
" 2>&1)
if echo "$JSON_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "_goax_json_array — quote/backslash 안전 escape"
else
    fail "_goax_json_array — JSON 깨짐: $JSON_OUT"
fi

# json_error/json_skip도 동일 보장
ERR_OUT=$(bash -c "
source $COM_FX/.ax/scripts/bash/common.sh
json_error 'err with \"x\" \\\\y'
" 2>&1)
echo "$ERR_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" >/dev/null 2>&1 \
    && pass "json_error — special char 안전" \
    || fail "json_error JSON 깨짐: $ERR_OUT"

rm -rf "$COM_FX"

# 15.3 next-spec-num — 999 overflow
NS_FX=$(mktemp -d)
mkdir -p "$NS_FX/.ax/scripts/bash" "$NS_FX/.ax/docs/spec/999-existing"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_FX/.ax/scripts/bash/"

OUT=$(CLAUDE_PROJECT_DIR=$NS_FX bash "$NS_FX/.ax/scripts/bash/next-spec-num.sh" --json 2>&1)
EXIT=$?
if [ "$EXIT" -eq 1 ] && echo "$OUT" | jq -e '.status == "error"' >/dev/null 2>&1; then
    pass "next-spec-num — 999 overflow → JSON error + exit 1"
else
    fail "next-spec-num — overflow 처리 부정확 (exit=$EXIT, out=$OUT)"
fi

# 정상 케이스 — 998이면 999 반환
mv "$NS_FX/.ax/docs/spec/999-existing" "$NS_FX/.ax/docs/spec/998-existing"
NEXT=$(CLAUDE_PROJECT_DIR=$NS_FX bash "$NS_FX/.ax/scripts/bash/next-spec-num.sh" 2>&1)
[ "$NEXT" = "999" ] && pass "next-spec-num — 998 → 999 정상" \
                    || fail "next-spec-num — 998 다음이 999 아님: $NEXT"

rm -rf "$NS_FX"

# 15.4 init-spec-dir — mandatory templates 누락 시 fail
IS_FX=$(mktemp -d)
mkdir -p "$IS_FX/.ax/scripts/bash" "$IS_FX/.ax/_templates/spec/checklists" "$IS_FX/.ax/_templates/spec/contracts" "$IS_FX/.ax/docs/spec"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,init-spec-dir,slug-from-text}.sh "$IS_FX/.ax/scripts/bash/"
# 의도적으로 template 안 채움 (standard 는 spec.md + tasks.md 필수)

OUT=$(CLAUDE_PROJECT_DIR=$IS_FX bash "$IS_FX/.ax/scripts/bash/init-spec-dir.sh" \
    --json --tier standard --slug missing-tpl 2>&1)
EXIT=$?
if [ "$EXIT" -ne 0 ] && echo "$OUT" | jq -e '.errors[0] | contains("mandatory")' >/dev/null 2>&1; then
    pass "init-spec-dir — mandatory template 누락 시 JSON error + exit ≠0"
else
    fail "init-spec-dir — silent continue 발생 (exit=$EXIT, out=${OUT:0:100})"
fi

rm -rf "$IS_FX"

# 15.5 slug-from-text — JSON escape
SL_FX=$(mktemp -d)
mkdir -p "$SL_FX/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,slug-from-text}.sh "$SL_FX/.ax/scripts/bash/"

# 입력에 quote, backslash, newline 포함
INPUT_TEXT='Order with "Refund" and \backslash and newline'
OUT=$(CLAUDE_PROJECT_DIR=$SL_FX bash "$SL_FX/.ax/scripts/bash/slug-from-text.sh" \
    --json "$INPUT_TEXT" 2>&1)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'original' in d.get('result',{})" 2>/dev/null; then
    pass "slug-from-text — JSON escape (quote/backslash 포함 input → valid JSON)"
else
    fail "slug-from-text — JSON 깨짐: $OUT"
fi

rm -rf "$SL_FX"

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
section "17. next-spec-num.sh --kind adr|spec — 번호 계산 회귀"
# ───────────────────────────────────────────────────────────
NS2_FX=$(mktemp -d)
mkdir -p "$NS2_FX/.ax/scripts/bash" "$NS2_FX/.ax/docs/adr" "$NS2_FX/.ax/docs/spec"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS2_FX/.ax/scripts/bash/"

# (1) --kind adr, 빈 adr/ → 0001
OUT=$(CLAUDE_PROJECT_DIR=$NS2_FX bash "$NS2_FX/.ax/scripts/bash/next-spec-num.sh" --kind adr --json 2>&1)
NEXT=$(echo "$OUT" | jq -r '.result.next' 2>/dev/null)
[ "$NEXT" = "0001" ] && pass "next-spec-num --kind adr — 빈 adr/ → 0001" \
                     || fail "next-spec-num --kind adr — 빈 adr/ 결과: $NEXT ($OUT)"

# (2) --kind adr, 0003-x.md 존재 → 0004
: > "$NS2_FX/.ax/docs/adr/0003-x.md"
OUT=$(CLAUDE_PROJECT_DIR=$NS2_FX bash "$NS2_FX/.ax/scripts/bash/next-spec-num.sh" --kind adr --json 2>&1)
NEXT=$(echo "$OUT" | jq -r '.result.next' 2>/dev/null)
[ "$NEXT" = "0004" ] && pass "next-spec-num --kind adr — 0003-x.md → 0004 (4자리 zero-pad)" \
                     || fail "next-spec-num --kind adr — 0003 다음 결과: $NEXT ($OUT)"

# (3) --kind spec (기본) — 기존 3자리 동작 그대로 (adr/ 존재해도 영향 없음)
OUT=$(CLAUDE_PROJECT_DIR=$NS2_FX bash "$NS2_FX/.ax/scripts/bash/next-spec-num.sh" --kind spec --json 2>&1)
NEXT=$(echo "$OUT" | jq -r '.result.next' 2>/dev/null)
[ "$NEXT" = "001" ] && pass "next-spec-num --kind spec — 빈 spec/ → 001 (3자리, 기존 동작 유지)" \
                    || fail "next-spec-num --kind spec 결과: $NEXT ($OUT)"

# (4) --kind 생략 시 기본값 spec — 동일 결과
OUT=$(CLAUDE_PROJECT_DIR=$NS2_FX bash "$NS2_FX/.ax/scripts/bash/next-spec-num.sh" --json 2>&1)
NEXT=$(echo "$OUT" | jq -r '.result.next' 2>/dev/null)
[ "$NEXT" = "001" ] && pass "next-spec-num — --kind 생략 시 기본값 spec 유지" \
                    || fail "next-spec-num --kind 생략 결과: $NEXT ($OUT)"

rm -rf "$NS2_FX"

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
