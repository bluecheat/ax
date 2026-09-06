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
               skills/personas skills/meta skills/spirit skills/rules skills/parallel; do
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
# scripts/provision.sh §5~§6.7 이 실제로 처리하는 조건부(manifest 외) 파일 목록.
# 이 목록과 provision.sh 가 벌어지면 이 테스트도 같이 갱신해야 함.
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
# 하드코딩 대신 실제 디렉토리 수와 대조 — skill 추가 때마다 이 줄을 고치는 건
# 계약이 아니라 잡일이에요. 여기서 잡고 싶은 건 "SKILL.md 없는 빈 디렉토리" 예요.
expected_skills=$(find "$REPO/skills" -mindepth 1 -maxdepth 1 -type d | grep -c . || true)
[ "$total_skills" -eq "${expected_skills:-0}" ] \
    && pass "skill 카운트 = $total_skills (디렉토리 수와 일치)" \
    || fail "skill 디렉토리 ${expected_skills}개인데 SKILL.md 는 ${total_skills}개 — 빈 skill 디렉토리 존재"

# 컨텍스트 예산 — SKILL.md 는 500줄 안, description 은 1,536자 안이 공식 권장이에요. compaction 뒤엔
# skill 당 앞 5,000토큰만 남아서 긴 본문은 뒤가 잘려요 (onboarding 이 1006줄일 때 Q3 이후가 잘렸어요).
# 본문에서 가리키는 references/<x>.md 는 실재해야 해요 — 포인터가 죽으면 그 절이 통째로 사라져요.
budget_bad=0
while IFS= read -r f; do
    sname=$(basename "$(dirname "$f")")
    lines=$(wc -l < "$f" | tr -d ' ')
    if [ "$lines" -gt 500 ]; then
        fail "skills/$sname/SKILL.md ${lines}줄 — 500줄 상한 초과 (references/ 로 분리)"; budget_bad=$((budget_bad+1))
    fi
    dlen=$(python3 -c "import re,sys; t=open(sys.argv[1],encoding='utf-8').read().split('\n---',2)[1] if open(sys.argv[1],encoding='utf-8').read().startswith('---') else ''; m=re.search(r'^description:\\s*(.*)$',t,re.M); print(len(m.group(1).strip().strip('\"')) if m else 0)" "$f" 2>/dev/null || echo 0)
    if [ "${dlen:-0}" -gt 1536 ]; then
        fail "skills/$sname description ${dlen}자 — 1,536자 상한 초과"; budget_bad=$((budget_bad+1))
    fi
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        [ -f "$(dirname "$f")/$ref" ] || { fail "skills/$sname/SKILL.md → $ref 없음 (죽은 references 포인터)"; budget_bad=$((budget_bad+1)); }
    done < <(grep -oE 'references/[a-z0-9-]+\.md' "$f" | sort -u)
done < <(find "$REPO/skills" -name SKILL.md)
[ "$budget_bad" -eq 0 ] && pass "skill 컨텍스트 예산 — 500줄 · description 1,536자 · references 포인터 실재"

# ───────────────────────────────────────────────────────────
section "6. HUD statusline — 하네스 위치 한 줄 (OMC 문법)"
# ───────────────────────────────────────────────────────────
# 이전 HUD 의 세 조각(행성 이모지·S×R·혜성)은 작업 중에 안 변했어요. 지금은 phase 로 체인이 움직여요.
SL="$REPO/templates/default/.ax/hud/statusline.sh"
if grep -qE "🪐|🌟|⭐|✦|☄" "$SL"; then
    fail "statusline.sh — 우주 이모지 잔재 (행성·혜성은 폐기)"
else
    pass "statusline.sh — 행성·혜성 이모지 0"
fi
grep -q "workspace.current_dir" "$SL" && pass "statusline.sh stdin JSON 처리 (workspace.current_dir)" || fail "statusline.sh stdin JSON 처리 누락"
if grep -qE 'bash .*\.sh' "$SL" | grep -v '^#' ; then fail "statusline.sh 가 스크립트를 호출함 (300ms 예산)"; else pass "statusline.sh — 스크립트 호출 없음 (파일 읽기만)"; fi

if command -v jq >/dev/null 2>&1; then
    HUD_FX=$(mktemp -d)
    mkdir -p "$HUD_FX/.ax/hud" "$HUD_FX/.ax/docs/spec/014-pay" "$HUD_FX/.ax/docs/adr" "$HUD_FX/.ax/mistakes"
    cp "$SL" "$HUD_FX/.ax/hud/"
    cp "$REPO/templates/default/.ax/hud/state.json.template" "$HUD_FX/.ax/state.json"
    cp "$REPO/templates/default/.ax/config.yml" "$HUD_FX/.ax/config.yml"
    printf 'goax: 0.5.1\n' > "$HUD_FX/.ax/version"
    printf -- '- [x] T001 [AC1] a\n- [x] T002 [AC1] b\n- [ ] T003 [AC2] c\n' > "$HUD_FX/.ax/docs/spec/014-pay/tasks.md"
    touch "$HUD_FX/.ax/mistakes/a.md" "$HUD_FX/.ax/mistakes/b.md" "$HUD_FX/.ax/mistakes/README.md"
    hud_render() { printf '{"workspace":{"current_dir":"%s"}}' "$HUD_FX" | bash "$HUD_FX/.ax/hud/statusline.sh" 2>/dev/null | sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g'; }

    echo '{"phase":"idle"}' > "$HUD_FX/.ax/current-task.json"
    OUT=$(hud_render)
    echo "$OUT" | grep -q '\[goax#0.5.1\]' && echo "$OUT" | grep -q 'idle' && echo "$OUT" | grep -q 'mistakes:2' \
        && pass "HUD idle — 버전 태그 + idle + mistakes:2 (README 제외)" || fail "HUD idle 출력: $OUT"

    echo '{"phase":"triaged","size":"S","risk":"L1","domain":"search"}' > "$HUD_FX/.ax/current-task.json"
    hud_render | grep -q '즉시 작업' && pass "HUD S×L1 — 즉시 작업 (체인 없음)" || fail "HUD S 사이즈 체인 오표시"

    echo '{"phase":"implementing","size":"M","risk":"L2","domain":"payment","spec_tier":"standard","spec_dir":".ax/docs/spec/014-pay"}' > "$HUD_FX/.ax/current-task.json"
    OUT=$(hud_render)
    echo "$OUT" | grep -q 'M×L2' && echo "$OUT" | grep -q 'spec ✓' && echo "$OUT" | grep -q 'tasks ✓' && echo "$OUT" | grep -q 'impl ●' && echo "$OUT" | grep -q '2/3' \
        && pass "HUD M×L2 implementing — spec ✓ › tasks ✓ › impl ● 2/3" || fail "HUD 체인 오표시: $OUT"
    echo "$OUT" | grep -q 'review' && fail "HUD — review_required 없는데 review 단계 표시" || pass "HUD — review 단계는 필수일 때만"

    jq '.hud.review_required="required" | .hud.cached_at=(now|todate)' "$HUD_FX/.ax/state.json" > "$HUD_FX/s" && mv "$HUD_FX/s" "$HUD_FX/.ax/state.json"
    jq '.phase="review" | .spec_tier="full" | .size="L" | .risk="L3"' "$HUD_FX/.ax/current-task.json" > "$HUD_FX/ct" && mv "$HUD_FX/ct" "$HUD_FX/.ax/current-task.json"
    printf '# ADR — spec 014\n' > "$HUD_FX/.ax/docs/adr/0001-x.md"
    OUT=$(hud_render)
    echo "$OUT" | grep -q 'adr ✓' && echo "$OUT" | grep -q 'impl ✓' && echo "$OUT" | grep -q 'review ●' \
        && pass "HUD L×L3 full review — adr ✓ · impl ✓ · review ●" || fail "HUD full tier/review 오표시: $OUT"
    echo "$OUT" | grep -q '(stale)' && fail "HUD — 캐시가 방금인데 stale" || pass "HUD — 캐시 신선하면 stale 없음"

    jq '.hud.cached_at="2026-01-01T00:00:00Z" | .hud.plugin_version="0.9.0"' "$HUD_FX/.ax/state.json" > "$HUD_FX/s" && mv "$HUD_FX/s" "$HUD_FX/.ax/state.json"
    OUT=$(hud_render)
    echo "$OUT" | grep -q '(stale)' && pass "HUD — 캐시 30분 초과면 (stale)" || fail "HUD — stale 미표시: $OUT"
    echo "$OUT" | grep -q -- '-> 0.9.0 goax up' && pass "HUD — plugin 이 새로우면 '-> X goax up' 힌트" || fail "HUD — 업데이트 힌트 없음: $OUT"

    jq '.phase="spec_blocked"' "$HUD_FX/.ax/current-task.json" > "$HUD_FX/ct" && mv "$HUD_FX/ct" "$HUD_FX/.ax/current-task.json"
    hud_render | grep -q 'spec ●' && pass "HUD spec_blocked — spec ● (노랑)" || fail "HUD spec_blocked 오표시"

    sed -i.bak 's/^  preset: focused/  preset: full/' "$HUD_FX/.ax/config.yml" && rm -f "$HUD_FX/.ax/config.yml.bak"
    N=$(hud_render | grep -c .)
    [ "$N" -eq 2 ] && pass "HUD preset full — 2줄 (둘째 줄에 spec·tier·다음)" || fail "HUD full 프리셋 줄 수 $N"
    sed -i.bak 's/^  preset: full/  preset: minimal/' "$HUD_FX/.ax/config.yml" && rm -f "$HUD_FX/.ax/config.yml.bak"
    OUT=$(hud_render)
    [ "$(echo "$OUT" | grep -c .)" -eq 1 ] && ! echo "$OUT" | grep -q 'tasks' \
        && pass "HUD preset minimal — 1줄, 현재 단계만" || fail "HUD minimal 프리셋 출력: $OUT"

    RAW=$(printf '{"workspace":{"current_dir":"%s"}}' "$HUD_FX" | bash "$HUD_FX/.ax/hud/statusline.sh" 2>/dev/null)
    [ "$(printf '%s' "$RAW" | tail -c 1 | od -An -c | tr -d ' ')" != "" ] || true
    printf '{"workspace":{"current_dir":"%s"}}' "$HUD_FX" | bash "$HUD_FX/.ax/hud/statusline.sh" 2>/dev/null | tail -c 1 | od -An -tx1 | grep -q '0a' \
        && pass "HUD — 출력이 개행으로 끝남 (합치기 안전)" || fail "HUD — 마지막 개행 없음"

    LONG=$(COLUMNS=40 hud_render | head -1)
    [ "${#LONG}" -le 40 ] && pass "HUD — COLUMNS=40 이면 ' | ' 경계에서 잘림 (${#LONG}자)" || fail "HUD — 폭 초과 (${#LONG}자)"
    rm -rf "$HUD_FX"
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
              "$REPO/templates/default/.ax/scripts" "$REPO/scripts" -name "*.sh" 2>/dev/null)
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
         build-memory spirit-lint rules-index doctor-scan status-note constitution-apply \
         tasks-plan tasks-gate lanes-hotfiles lanes-dispatch spec-review; do
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
    "status-note.sh --show --json"; do
    out=$(bash "$REPO/templates/default/.ax/scripts/bash/"$cmd 2>/dev/null) || true
    if echo "$out" | jq -e '.status' >/dev/null 2>&1; then
        pass "$cmd → valid JSON"
    else
        fail "$cmd → invalid JSON: ${out:0:120}"
    fi
done
popd >/dev/null || true
rm -rf "$TMP_E2E"
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

# 원장 semantics — 한 번 쓴 번호는 실물을 지워도 회수되지 않아요
# (ADR 템플릿 "폐기된 ADR 도 ID 재사용 안 함" 과 같은 규약).
rm -rf "$NS_FX/.ax/docs/spec/999-existing"
OUT=$(CLAUDE_PROJECT_DIR=$NS_FX bash "$NS_FX/.ax/scripts/bash/next-spec-num.sh" --json 2>&1) || true
if echo "$OUT" | jq -e '.status == "error"' >/dev/null 2>&1; then
    pass "next-spec-num — 실물 삭제해도 번호 회수 안 됨 (영구 원장)"
else
    fail "next-spec-num — 삭제된 999 를 재사용함: $OUT"
fi

# 정상 케이스 — 998이면 999 반환 (원장이 없는 새 fixture)
NS_FX2=$(mktemp -d)
mkdir -p "$NS_FX2/.ax/scripts/bash" "$NS_FX2/.ax/docs/spec/998-existing"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_FX2/.ax/scripts/bash/"
NEXT=$(CLAUDE_PROJECT_DIR=$NS_FX2 bash "$NS_FX2/.ax/scripts/bash/next-spec-num.sh" 2>&1)
[ "$NEXT" = "999" ] && pass "next-spec-num — 998 → 999 정상" \
                    || fail "next-spec-num — 998 다음이 999 아님: $NEXT"

# 동시 예약 경합 — 같은 번호가 두 번 나오면 안 돼요 (실사용 ADR 7 쌍 충돌의 회귀 테스트)
NS_RACE=$(mktemp -d)
mkdir -p "$NS_RACE/.ax/scripts/bash" "$NS_RACE/.ax/docs/spec"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_RACE/.ax/scripts/bash/"
for i in 1 2 3 4 5 6 7 8; do
    CLAUDE_PROJECT_DIR=$NS_RACE bash "$NS_RACE/.ax/scripts/bash/next-spec-num.sh" \
        --reserve --slug "feat$i" --json >/dev/null 2>&1 &
done
wait
RACE_TOT=$(ls "$NS_RACE/.ax/docs/spec" 2>/dev/null | grep -cE '^[0-9]' || true)
RACE_UNIQ=$(ls "$NS_RACE/.ax/docs/spec" 2>/dev/null | grep -E '^[0-9]' | sed -E 's/^([0-9]+).*/\1/' | sort -u | grep -c . || true)
if [ "${RACE_TOT:-0}" -eq 8 ] && [ "${RACE_TOT:-0}" = "${RACE_UNIQ:-0}" ]; then
    pass "next-spec-num --reserve — 8개 동시 예약에서 번호 충돌 0"
else
    fail "next-spec-num --reserve — 동시 예약 충돌 (생성 ${RACE_TOT}, 고유 ${RACE_UNIQ})"
fi

# --reserve 는 실물까지 만들고, --dry-run 은 만들지 않아야
NS_DR=$(mktemp -d)
mkdir -p "$NS_DR/.ax/scripts/bash" "$NS_DR/.ax/docs/adr"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_DR/.ax/scripts/bash/"
CLAUDE_PROJECT_DIR=$NS_DR bash "$NS_DR/.ax/scripts/bash/next-spec-num.sh" --kind adr \
    --reserve --slug ghost --dry-run --json >/dev/null 2>&1
[ -z "$(ls "$NS_DR/.ax/docs/adr"/[0-9]*.md 2>/dev/null)" ] \
    && pass "next-spec-num --reserve --dry-run — 실물 생성 안 함" \
    || fail "next-spec-num --dry-run 이 파일을 생성함"
CLAUDE_PROJECT_DIR=$NS_DR bash "$NS_DR/.ax/scripts/bash/next-spec-num.sh" --kind adr \
    --reserve --slug real --json >/dev/null 2>&1
[ -f "$NS_DR/.ax/docs/adr/0001-real.md" ] \
    && pass "next-spec-num --reserve — ADR 실물 생성" \
    || fail "next-spec-num --reserve — ADR 실물 미생성"

# --reserve 는 --slug 없이 거부돼야
CLAUDE_PROJECT_DIR=$NS_DR bash "$NS_DR/.ax/scripts/bash/next-spec-num.sh" --reserve --json >/dev/null 2>&1
[ $? -ne 0 ] && pass "next-spec-num --reserve — --slug 누락 시 error" \
             || fail "next-spec-num --reserve — --slug 없이 통과됨"

# --check-duplicates — 예약 도입 이전 충돌을 진단으로 노출 (자동 수정 안 함)
NS_DUP=$(mktemp -d)
mkdir -p "$NS_DUP/.ax/scripts/bash" "$NS_DUP/.ax/docs/adr"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_DUP/.ax/scripts/bash/"
: > "$NS_DUP/.ax/docs/adr/0001-a.md"; : > "$NS_DUP/.ax/docs/adr/0001-b.md"; : > "$NS_DUP/.ax/docs/adr/0003-c.md"
DUP_OUT=$(CLAUDE_PROJECT_DIR=$NS_DUP bash "$NS_DUP/.ax/scripts/bash/next-spec-num.sh" \
    --kind adr --check-duplicates --json 2>/dev/null)
if echo "$DUP_OUT" | jq -e '.result.duplicate_count == 1 and (.result.duplicates | index("0001"))' >/dev/null 2>&1; then
    pass "next-spec-num --check-duplicates — 중복 번호 검출"
else
    fail "next-spec-num --check-duplicates — 검출 실패: $DUP_OUT"
fi
# 진단·dry-run 은 읽기 전용이어야 해요 (사용자 리포에 원장을 몰래 만들면 안 됨)
CLAUDE_PROJECT_DIR=$NS_DUP bash "$NS_DUP/.ax/scripts/bash/next-spec-num.sh" \
    --kind adr --reserve --slug ghost --dry-run --json >/dev/null 2>&1
[ ! -d "$NS_DUP/.ax/docs/adr/.numbers" ] \
    && pass "next-spec-num — --check-duplicates/--dry-run 은 원장을 쓰지 않음" \
    || fail "next-spec-num — 읽기 전용 모드가 .numbers 를 생성함"
rm -rf "$NS_DUP"

rm -rf "$NS_FX2" "$NS_RACE" "$NS_DR"

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

# init-spec-dir 동시 실행 — 실제 호출 경로의 번호 경합 (E2E).
# next-spec-num 단위 테스트만으로는 못 잡아요: --reserve 가 디렉토리를 만드는데
# init-spec-dir 의 "already exists" 가드가 자기 예약에 걸리는 버그가 여기서 나왔어요.
ISR_FX=$(mktemp -d)
mkdir -p "$ISR_FX/.ax/scripts/bash" "$ISR_FX/.ax/docs/spec"
cp "$REPO/templates/default/.ax/scripts/bash/"*.sh "$ISR_FX/.ax/scripts/bash/"
cp -R "$REPO/templates/default/.ax/_templates" "$ISR_FX/.ax/_templates"
for i in 1 2 3 4 5 6; do
    CLAUDE_PROJECT_DIR=$ISR_FX bash "$ISR_FX/.ax/scripts/bash/init-spec-dir.sh" \
        --json --tier standard --slug "race-$i" >/dev/null 2>&1 &
done
wait
ISR_DIRS=$(ls "$ISR_FX/.ax/docs/spec" 2>/dev/null | grep -E '^[0-9]' || true)
ISR_TOT=$(printf '%s\n' "$ISR_DIRS" | grep -c . || true)
ISR_UNIQ=$(printf '%s\n' "$ISR_DIRS" | sed -E 's/^([0-9]+).*/\1/' | sort -u | grep -c . || true)
ISR_SPEC=$(find "$ISR_FX/.ax/docs/spec" -name spec.md 2>/dev/null | grep -c . || true)
if [ "${ISR_TOT:-0}" -eq 6 ] && [ "${ISR_TOT:-0}" = "${ISR_UNIQ:-0}" ] && [ "${ISR_SPEC:-0}" -eq 6 ]; then
    pass "init-spec-dir — 6개 동시 생성: 번호 충돌 0 + spec.md 전부 생성"
else
    fail "init-spec-dir 동시 실행 (dir=${ISR_TOT} 고유=${ISR_UNIQ} spec.md=${ISR_SPEC}, 기대 6/6/6)"
fi
rm -rf "$ISR_FX"

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

# --strict 는 exit 2
GOAX_PROJECT_DIR="$TG" bash "$TG/.ax/scripts/bash/tasks-gate.sh" --spec 012-x --strict >/dev/null 2>&1
[ $? -eq 2 ] && pass "tasks-gate --strict — 위반 시 exit 2" || fail "tasks-gate --strict — exit code 부정확"

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

# ───────────────────────────────────────────────────────────
section "30. SKILL.md 인라인 bash 문법 검사 — skills/ 는 §7 의 사각지대"
# ───────────────────────────────────────────────────────────
# §7 은 `templates/**/*.sh` **파일** 만 봐요. 그런데 up(266줄)·doctor(228줄) 처럼
# SKILL.md 안에 사는 bash 가 그보다 많고, 파일이 아니라서 어떤 lint 도 안 닿았어요.
# 하필 사용자가 제일 먼저 돌리는 설치 코드가 거기 있어요.
# ```bash 블록을 뽑아 bash -n. 블록 단위라 변수 미정의는 못 잡지만 문법은 잡아요.
INLINE_DIR=$(mktemp -d)
inline_total=0
inline_bad=0
while IFS= read -r sf; do
    [ -f "$sf" ] || continue
    sname=$(basename "$(dirname "$sf")")
    awk -v out="$INLINE_DIR/$sname" 'BEGIN{i=0}
        /^```(bash|sh)[[:space:]]*$/ { inb=1; i=i+1; f=out"-"i".sh"; next }
        /^```/ { inb=0; next }
        inb { print >> f }
    ' "$sf"
done < <(find "$REPO/skills" "$REPO/commands" -name '*.md' 2>/dev/null)
for bf in "$INLINE_DIR"/*.sh; do
    [ -f "$bf" ] || continue
    inline_total=$((inline_total+1))
    if ! bash -n "$bf" 2>/dev/null; then
        inline_bad=$((inline_bad+1))
        fail "SKILL.md 인라인 bash 문법 오류: $(basename "$bf")"
    fi
done
rm -rf "$INLINE_DIR"
if [ "$inline_total" -eq 0 ]; then
    fail "SKILL.md 인라인 bash 블록 0개 — 추출 로직이 깨졌어요"
elif [ "$inline_bad" -eq 0 ]; then
    pass "SKILL.md 인라인 bash — $inline_total 블록 문법 OK"
fi

# ───────────────────────────────────────────────────────────
section "31. triage-search — specs 본문 랭킹 + 대소문자 무시 재채점"
# ───────────────────────────────────────────────────────────
# 두 결함의 회귀 방어:
#  (a) specs 를 디렉토리 *이름* 으로만 매칭 → 슬러그에 없고 본문에만 있는 spec 누락.
#      슬러그가 영문 kebab-case 규약이라 한국어 프로젝트에선 "정산" 같은 도메인어로
#      아무것도 못 찾았어요.
#  (b) 후보는 grep -ril(대소문자 무시)로 뽑고 재채점은 grep -cE(구분)로 해서,
#      키워드가 대문자로만 나오는 문서가 점수 0 으로 조용히 탈락했어요.
if ! command -v jq >/dev/null 2>&1; then
    pass "triage-search 검증 skip (jq 없음)"
else
    TS_T=$(mktemp -d)
    mkdir -p "$TS_T/.ax/scripts/bash" "$TS_T/.ax/docs/adr" "$TS_T/.ax/docs/spec/imported"
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" \
       "$REPO/templates/default/.ax/scripts/bash/triage-search.sh" "$TS_T/.ax/scripts/bash/" 2>/dev/null
    : > "$TS_T/CLAUDE.md"

    mkdir -p "$TS_T/.ax/docs/spec/003-payment-coupon"      # 슬러그 매칭
    printf '# 쿠폰\n중복 적용 정책\n' > "$TS_T/.ax/docs/spec/003-payment-coupon/spec.md"
    mkdir -p "$TS_T/.ax/docs/spec/007-checkout"            # 본문에만 payment
    printf '# 체크아웃\npayment 흐름 재작성\n' > "$TS_T/.ax/docs/spec/007-checkout/spec.md"
    mkdir -p "$TS_T/.ax/docs/spec/009-settlement"          # 본문이 한국어
    printf '# 정산\n정산 배치가 읽어요\n' > "$TS_T/.ax/docs/spec/009-settlement/spec.md"
    printf '# PG\nPayment gateway 이중화\n' > "$TS_T/.ax/docs/adr/0002-pg.md"   # 대문자만
    printf '# 외부\npayment 외부 스펙\n' > "$TS_T/.ax/docs/spec/imported/legacy.md"

    TS_OUT=$(cd "$TS_T" && bash .ax/scripts/bash/triage-search.sh --keywords "payment" --json 2>/dev/null)
    TS_SPECS=$(printf '%s' "$TS_OUT" | jq -r '[.result.specs[].path] | join(" ")' 2>/dev/null)
    TS_ADRS=$(printf '%s' "$TS_OUT" | jq -r '[.result.adrs[].path]  | join(" ")' 2>/dev/null)

    case "$TS_SPECS" in
        *007-checkout*) pass "triage-search — 본문에만 있는 spec 도 매칭 (슬러그 한계 해소)" ;;
        *) fail "triage-search — 본문 매칭 spec 누락: [$TS_SPECS]" ;;
    esac
    case "$TS_ADRS" in
        *0002-pg*) pass "triage-search — 대문자만 등장하는 문서도 점수 유지 (재채점 -i)" ;;
        *) fail "triage-search — 대소문자 재채점 불일치로 ADR 탈락: [$TS_ADRS]" ;;
    esac
    case "$TS_SPECS" in
        *imported*) fail "triage-search — imported 가 specs 에 섞였어요 (별도 카테고리여야)" ;;
        *) pass "triage-search — imported 는 specs 에서 제외" ;;
    esac

    # 한국어 도메인어 — 슬러그가 영문이어도 본문으로 잡혀야 해요
    TS_KO=$(cd "$TS_T" && bash .ax/scripts/bash/triage-search.sh --keywords "정산" --json 2>/dev/null \
            | jq -r '[.result.specs[].path] | join(" ")' 2>/dev/null)
    case "$TS_KO" in
        *009-settlement*) pass "triage-search — 한국어 키워드로 영문 슬러그 spec 매칭" ;;
        *) fail "triage-search — 한국어 키워드 매칭 실패: [$TS_KO]" ;;
    esac
    rm -rf "$TS_T"
fi

# ───────────────────────────────────────────────────────────
section "32. lanes-dispatch — 디스패치 원장 (assign / dispatch / report / status)"
# ───────────────────────────────────────────────────────────
# 코디네이터의 "누구에게 뭘 보냈더라" 는 컨텍스트 안에만 있어서 압축·세션 종료로 사라져요.
# 원장이 tasks.md 에 있어야 tasks-gate G5 가 읽고, dispatch 는 파일 소유 충돌을 거부해야 해요.
LDX=$(mktemp -d)
mkdir -p "$LDX"/.ax/scripts/bash "$LDX"/.ax/docs/spec/012-x
cp "$REPO/templates/default/.ax/scripts/bash/"{common,lanes-dispatch}.sh "$LDX/.ax/scripts/bash/"
cat > "$LDX/.ax/docs/spec/012-x/tasks.md" <<'LDEOF'
- [ ] T001 [AC1] 배럴 — files: ui/index.ts
      의존: 없음
- [ ] T010 [P] [AC1] 카드 — files: ui/Card.tsx
      의존: T001
      검증: pnpm test Card
- [ ] T011 [P] [AC2] 필 — files: ui/Pill.tsx
      의존: T001
- [ ] T021 [AC3] 스크린 — files: app/Result.tsx, ui/Card.tsx
LDEOF
ld() { GOAX_PROJECT_DIR="$LDX" bash "$LDX/.ax/scripts/bash/lanes-dispatch.sh" --spec 012-x "$@" 2>/dev/null; }

ld --json | jq -e '.result.lanes == [] and (.result.unassigned_open | length) == 4' >/dev/null 2>&1 \
    && pass "lanes-dispatch — 배정 없으면 lanes 비고 전부 unassigned" || fail "lanes-dispatch — 초기 status 오류"

# assign: T010(A) 와 T021(B) 가 ui/Card.tsx 를 공유 → 충돌
ld --assign "T010=A,T011=A,T021=B" --json | jq -e '.status == "warning" and (.result.lane_file_conflicts | length) == 1
    and .result.lane_file_conflicts[0].file == "ui/Card.tsx"' >/dev/null 2>&1 \
    && pass "lanes-dispatch --assign — 원장 기록 + 파일 소유 충돌 검출" || fail "lanes-dispatch --assign — 충돌 미검출"
grep -qE '^[[:space:]]+레인: A$' "$LDX/.ax/docs/spec/012-x/tasks.md" \
    && pass "lanes-dispatch --assign — tasks.md 에 레인: 필드가 continuation 으로 기록" || fail "lanes-dispatch --assign — 레인: 필드 미기록"

# dispatch: 충돌 레인은 거부 (exit 1)
ld --dispatch B --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "lanes-dispatch --dispatch — 파일 소유 충돌이면 거부 (exit 1)" || fail "lanes-dispatch --dispatch — 충돌인데 디스패치함"

# 재배정은 --force 필요
ld --assign "T021=A" --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "lanes-dispatch --assign — 다른 레인으로 옮기려면 --force" || fail "lanes-dispatch --assign — 무단 재배정 허용"
ld --assign "T021=A" --force --json | jq -e '.result.lane_file_conflicts == []' >/dev/null 2>&1 \
    && pass "lanes-dispatch --assign --force — 재배정 후 충돌 해소" || fail "lanes-dispatch --assign --force 실패"

# dry-run 은 파일을 안 건드려요
ld --dispatch A --dry-run --json | jq -e '.result.dry_run == true and .result.changed == 3' >/dev/null 2>&1 \
    && ! grep -q '디스패치:' "$LDX/.ax/docs/spec/012-x/tasks.md" \
    && pass "lanes-dispatch --dry-run — 변경 예정 수만 보고, 파일 불변" || fail "lanes-dispatch --dry-run — 파일을 건드림"

# dispatch → dispatched_unreported 3
ld --dispatch A --json | jq -e '(.result.dispatched_unreported | length) == 3 and .status == "warning"' >/dev/null 2>&1 \
    && pass "lanes-dispatch --dispatch — 디스패치: 기록 + 보고 대기 3" || fail "lanes-dispatch --dispatch 실패"

# report 일부 → 남은 것만 대기
ld --report T010 --json | jq -e '.result.dispatched_unreported == ["T011","T021"]' >/dev/null 2>&1 \
    && pass "lanes-dispatch --report <ID> — 일부 보고 반영" || fail "lanes-dispatch --report <ID> 실패"
ld --report A --json | jq -e '.result.dispatched_unreported == []' >/dev/null 2>&1 \
    && pass "lanes-dispatch --report <레인> — 레인 전체 보고 반영" || fail "lanes-dispatch --report <레인> 실패"

# 디스패치 기록 없는 task 보고 → warning (기록은 하되 원장 밖 전달을 드러냄)
ld --report T001 --json | jq -e '(.warnings | length) == 1' >/dev/null 2>&1 \
    && pass "lanes-dispatch --report — 디스패치 기록 없는 보고는 warning" || fail "lanes-dispatch --report — 원장 밖 보고를 조용히 통과시킴"

# 없는 task
ld --assign "T999=A" --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "lanes-dispatch --assign — 없는 task 는 error" || fail "lanes-dispatch --assign — 없는 task 를 통과시킴"

# tier-from-state 의 evaluator 필드 (tasks-gate G6 의 SSOT) — 프로젝트 루트는 fixture 로 고정
cp "$REPO/templates/default/.ax/scripts/bash/tier-from-state.sh" "$LDX/.ax/scripts/bash/"
ev() { GOAX_PROJECT_DIR="$LDX" bash "$LDX/.ax/scripts/bash/tier-from-state.sh" --json --size "$1" --risk "$2" 2>/dev/null | jq -r '.result.evaluator // empty'; }
EV_M3=$(ev M L3); EV_S0=$(ev S L0); EV_XL=$(ev XL L0); EV_L1=$(ev L L1); EV_M2=$(ev M L2)
[ "$EV_M3" = "required" ] && [ "$EV_S0" = "optional" ] && [ "$EV_XL" = "required" ] \
    && [ "$EV_L1" = "required" ] && [ "$EV_M2" = "optional" ] \
    && pass "tier-from-state — evaluator 필수 매트릭스 (M×L3·L·XL 필수, 나머지 선택)" \
    || fail "tier-from-state — evaluator 필드 오류 (M×L3=$EV_M3, S×L0=$EV_S0, XL=$EV_XL, L×L1=$EV_L1, M×L2=$EV_M2)"
rm -rf "$LDX"

# 엣지가 실제로 연결됐는가 — 보내는 쪽만 적고 받는 쪽이 모르면 산문 약속이에요.
grep -q 'lanes-dispatch.sh' "$REPO/skills/spec-implement/SKILL.md" \
    && grep -q 'goax:lane-worker' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — 레인 모드가 원장·lane-worker 를 실제로 호출" \
    || fail "spec-implement — lane 이 넘긴 레인을 받는 코드가 없음"
grep -q 'goax:evaluator' "$REPO/skills/spec-implement/SKILL.md" \
    && grep -q 'review_required' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — 완료 시 evaluator 엣지 연결" \
    || fail "spec-implement — evaluator 를 호출하는 곳이 없음 (triage 매트릭스만 약속)"
grep -q '^verdict:' "$REPO/agents/evaluator.md" \
    && pass "evaluator — review.md 첫 줄 verdict 계약 명시" \
    || fail "evaluator — verdict 계약 없음 (게이트가 읽을 것이 없음)"

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

for sz in S:none M:optional L:required XL:required; do
    got=$(GOAX_PROJECT_DIR="$SR" bash "$SR/.ax/scripts/bash/tier-from-state.sh" --json --size "${sz%%:*}" --risk L2 2>/dev/null | jq -r '.result.spec_review')
    [ "$got" = "${sz##*:}" ] || fail "tier-from-state spec_review — ${sz%%:*} 가 $got (기대 ${sz##*:})"
done
pass "tier-from-state — spec_review 는 Size 축만 (S none · M optional · L/XL required)"

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
rm -rf "$SR"

# 엣지 연결 — 보내는 쪽만 적고 받는 쪽이 모르면 산문 약속이에요.
grep -q 'spec-review.sh' "$REPO/skills/spec-validate/SKILL.md" && grep -q 'goax:architect' "$REPO/skills/spec-validate/SKILL.md" \
    && pass "spec-validate — 합의 리뷰가 spec-review.sh + architect 를 실제로 호출" || fail "spec-validate — 합의 리뷰 엣지 없음"
grep -q '^verdict:' "$REPO/agents/architect.md" && grep -q 'review-spec.architect.md' "$REPO/agents/architect.md" \
    && pass "architect — spec 리뷰 verdict 파일 계약 명시" || fail "architect — spec 리뷰 계약 없음"
grep -q 'review-spec.evaluator.md' "$REPO/agents/evaluator.md" \
    && pass "evaluator — spec 모드 파일 계약 명시" || fail "evaluator — spec 모드 없음"
grep -q '\.phase = "implementing"' "$REPO/skills/spec-implement/SKILL.md" && grep -q '\.phase = "review"' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — phase implementing/review 를 실제로 씀 (HUD 가 움직이는 조건)" || fail "spec-implement — phase 기록 없음 (HUD 가 tasks 에 멈춤)"
grep -q 'hud' "$REPO/templates/default/.ax/hud/state.json.template" && grep -q 'hud.plugin_version' "$REPO/docs/state-ownership.md" \
    && pass "state.json hud 캐시 — template · ownership 문서 동기화" || fail "state.json hud 캐시 3-way 동기화 누락"

# ───────────────────────────────────────────────────────────
section "34. 폐기·스크립트화 — spirit-lint · rules-index · doctor-scan · status-note · constitution-apply"
# ───────────────────────────────────────────────────────────
# rules·spirit skill 은 "grep 해서 찍어라" 산문이었고, doctor 3.6~3.8 은 SKILL.md 안의 bash 였어요.
# 스크립트가 됐으니 픽스처로 판정을 고정해요. 인계 노트(STATUS.md)는 형식이 고정돼야 다음 세션이 파싱해요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§34 skip (jq 없음)"
else
    RS=$(mktemp -d)
    mkdir -p "$RS/.ax/scripts/bash" "$RS/.ax/spirit/rules" "$RS/.ax/modules/order" "$RS/.ax/_templates/spirit" \
             "$RS/.ax/docs/spec/003-x/checklists" "$RS/.ax/hooks/pre-edit" "$RS/.claude"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,spirit-lint,rules-index,doctor-scan,status-note,constitution-apply}.sh "$RS/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/spirit/"{values,tone}.md "$RS/.ax/spirit/"
    cp "$REPO/templates/default/.ax/_templates/spirit/rule.md" "$RS/.ax/_templates/spirit/"
    printf -- '---\ncategory: security\n---\n## SP-SEC-001: 시크릿 커밋 금지\n## SP-SEC-002: 토큰 로그 금지\n' > "$RS/.ax/spirit/rules/security.md"
    printf -- '---\ncategory: naming\npaths:\n  - "**/*.kt"\n---\n## SP-NAM-001: kebab-case\n## 잘못된 헤더\n' > "$RS/.ax/spirit/rules/naming.md"
    printf -- '---\nmodule: order\nkeywords: [order]\n---\n## SP-SEC-001: 중복 토큰\n## SP-ORD-001: 주문은 멱등\n' > "$RS/.ax/modules/order/rules.md"
    printf '# X\n\n## CRITICAL\n\n🔴 **`AX:CRITICAL:001`** — 결제 API 는 멱등성 키 필수\n\n## MANDATORY\n\n🟡 **`AX:MANDATORY:001`** ADR 필수\n\n## CONVENTION\n\n@.ax/spirit/rules/security.md\n' > "$RS/AGENTS.md"
    touch "$RS/.ax/docs/spec/003-x/README.md"; printf '.ax/state.json\n' > "$RS/.gitignore"
    echo '{"hooks":{}}' > "$RS/.claude/settings.json"
    rs() { GOAX_PROJECT_DIR="$RS" bash "$RS/.ax/scripts/bash/$1" "${@:2}" 2>/dev/null; }

    # spirit-lint — 비표준 헤더 · 교차 중복 · 카운트
    SLJ=$(rs spirit-lint.sh --json)
    echo "$SLJ" | jq -e '.status=="warning" and (.result.bad_headers|length)==1 and .result.bad_headers[0].line==7' >/dev/null \
        && pass "spirit-lint — 비표준 ## 헤더를 파일:줄 로 지목" || fail "spirit-lint — 비표준 헤더 검출 실패: $(echo "$SLJ" | head -c 200)"
    echo "$SLJ" | jq -e '.result.duplicates[0].token=="SP-SEC-001" and (.result.duplicates[0].files|length)==2' >/dev/null \
        && pass "spirit-lint — spirit ↔ modules 교차 중복 토큰 검출" || fail "spirit-lint — 교차 중복 미검출"
    echo "$SLJ" | jq -e '.result.rules_count==5 and .result.rules_files==2 and .result.files.values==true' >/dev/null \
        && pass "spirit-lint — 토큰 5 · 카테고리 2 · 필수 파일 OK" || fail "spirit-lint — 카운트 불일치"
    rs spirit-lint.sh --json --strict >/dev/null; [ $? -eq 1 ] && pass "spirit-lint --strict — finding 있으면 exit 1" || fail "spirit-lint --strict 가 exit 0"

    # rules-index — 세 소스 · 필터 · find
    RIJ=$(rs rules-index.sh --json)
    echo "$RIJ" | jq -e '.result.counts.critical==1 and .result.counts.mandatory==1 and .result.counts.convention==5 and .result.constitution_file=="AGENTS.md"' >/dev/null \
        && pass "rules-index — Constitution + Spirit + Module 세 소스 집계 (1/1/5)" || fail "rules-index — 집계 불일치: $(echo "$RIJ" | jq -c .result.counts)"
    [ "$(rs rules-index.sh --json --source module | jq -r '[.result.rules[].token]|join(",")')" = "SP-SEC-001,SP-ORD-001" ] \
        && pass "rules-index --source module — 모듈 룰만" || fail "rules-index --source 필터 실패"
    [ "$(rs rules-index.sh --json --find AX:CRITICAL:001 | jq -r '.result.rules[0].line')" = "5" ] \
        && pass "rules-index --find — 토큰 정확 매칭 + 줄 번호" || fail "rules-index --find 실패"
    rs rules-index.sh --json --find NOPE:X:999 | jq -e '.status=="warning" and .result.counts.total==0' >/dev/null \
        && pass "rules-index --find — 없는 토큰은 warning" || fail "rules-index — 없는 토큰을 ok 로"
    rs rules-index.sh | grep -q '📍 AGENTS.md:5' && pass "rules-index 텍스트 — 원문 + 📍 위치" || fail "rules-index 텍스트 출력 형식"

    # doctor-scan — 잔재 · hook 등록 · 도달 지도
    DSJ=$(rs doctor-scan.sh --json --plugin-dir "$REPO")
    echo "$DSJ" | jq -e '(.result.migration.gitignore_missing|index(".ax/current-task.json"))!=null and (.result.migration.spec_readme_stale|length)==1 and (.result.migration.spec_empty_dirs|length)==1' >/dev/null \
        && pass "doctor-scan — .gitignore 누락 · spec README · 빈 dir 잔재" || fail "doctor-scan — 마이그레이션 잔재 검출 실패"
    echo "$DSJ" | jq -e '.result.hooks.checked==true and .result.hooks.total>=7 and .result.hooks.registered_n==0' >/dev/null \
        && pass "doctor-scan — template SSOT 기준 hook 등록 검사 (하드코딩 없음)" || fail "doctor-scan — hook 등록 검사 실패"
    echo "$DSJ" | jq -e '[.result.reach[]|select(.source=="constitution")][0].reached==false' >/dev/null \
        && pass "doctor-scan 도달 지도 — AGENTS.md 만 있고 CLAUDE.md 없음 → Constitution 이 어디에도 안 감" || fail "doctor-scan — AGENTS.md-only 를 도달로 봄"
    echo "$DSJ" | jq -e '[.result.reach[]|select(.source=="spirit-universal")][0].reached==true and [.result.reach[]|select(.source=="spirit-scoped")][0].reached==false' >/dev/null \
        && pass "doctor-scan 도달 지도 — @import 된 universal 룰은 도달 · paths 룰은 hook 미등록이라 미도달" || fail "doctor-scan — spirit 도달 판정 불일치"
    printf '@AGENTS.md\n' > "$RS/CLAUDE.md"
    rs doctor-scan.sh --json | jq -e '[.result.reach[]|select(.source=="constitution")][0].reached==true' >/dev/null \
        && pass "doctor-scan 도달 지도 — CLAUDE.md 가 @AGENTS.md 를 import 하면 도달" || fail "doctor-scan — @AGENTS.md import 를 미도달로 봄"

    # status-note — 형식 고정 · 중복 무시 · done · 상한
    rs status-note.sh --add next "1순위 가정 검증" --json | jq -e '.result.added==true' >/dev/null \
        && pass "status-note --add — 4절 골격 생성 + 항목 추가" || fail "status-note --add 실패"
    rs status-note.sh --add next "1순위 가정 검증" --json | jq -e '.result.added==false and .result.reason=="duplicate"' >/dev/null \
        && pass "status-note --add — 같은 줄은 무시 (idempotent)" || fail "status-note — 중복 줄 추가됨"
    rs status-note.sh --set now "spec 014 구현 중\n- T010 halt" --json >/dev/null
    rs status-note.sh --show --json | jq -e '(.result.sections.now|length)==2 and .result.sections.next==["- 1순위 가정 검증"]' >/dev/null \
        && pass "status-note --show — 절별 파싱 (여러 줄 --set 포함)" || fail "status-note --show 파싱 불일치"
    rs status-note.sh --done next "가정 검증" --json | jq -e '.result.removed==1' >/dev/null \
        && pass "status-note --done — 끝난 항목 제거" || fail "status-note --done 실패"
    for i in $(seq 1 40); do rs status-note.sh --add open "q$i" >/dev/null; done
    rs status-note.sh --show --json | jq -e '.status=="warning" and .result.over_cap==true' >/dev/null \
        && pass "status-note — 40줄 상한 초과 warning" || fail "status-note — 상한 초과를 ok 로"
    grep -q '^## 이번에 바뀐 이름' "$RS/.ax/docs/STATUS.md" && pass "status-note — 4절 헤더 형식 고정" || fail "status-note — 절 헤더 누락"

    # constitution-apply — prepend 보존 · 중복 스캔은 구 본문만 · drop 은 [a] 뒤 · 인덱스
    printf '# X — Constitution\n\n## META — 핵심 가드레일\n\n🔴 **`AX:CRITICAL:001`** — 결제 API 는 멱등성 키 필수\n' > "$RS/block.md"
    printf '# old\n\n## Database\n파일명 규칙: 결제 API 는 멱등성 키 필수\n짧은줄\n' > "$RS/CLAUDE.md"
    rs constitution-apply.sh --block "$RS/block.md" --target CLAUDE.md --json | jq -e '.result.applied==true and .result.preserved_lines==5' >/dev/null \
        && pass "constitution-apply — prepend + 기존 본문 --- 아래 보존" || fail "constitution-apply prepend 실패"
    rs constitution-apply.sh --block "$RS/block.md" --target CLAUDE.md --json >/dev/null; [ $? -eq 2 ] \
        && pass "constitution-apply — 이미 적용이면 exit 2 (idempotent)" || fail "constitution-apply — 재적용을 막지 않음"
    rs constitution-apply.sh --scan-duplicates --block "$RS/block.md" --target CLAUDE.md --json | jq -e '.result.count==1 and (.result.duplicates[0].old_text|test("파일명 규칙"))' >/dev/null \
        && pass "constitution-apply --scan-duplicates — 구 본문의 정확 일치만 (블록 자신은 제외)" || fail "constitution-apply — 중복 스캔 불일치"
    rs constitution-apply.sh --drop-exact --block "$RS/block.md" --target CLAUDE.md --json | jq -e '.result.dropped==1' >/dev/null \
        && grep -q '^짧은줄$' "$RS/CLAUDE.md" && ! grep -q '^파일명 규칙' "$RS/CLAUDE.md" \
        && pass "constitution-apply --drop-exact — 정확 일치 줄만 제거, 나머지 보존" || fail "constitution-apply --drop-exact 실패"
    rs constitution-apply.sh --append-index --target CLAUDE.md --plugin-dir "$REPO" --json | jq -e '.result.applied==true' >/dev/null \
        && grep -q '^## 4계층 인덱스' "$RS/CLAUDE.md" && [ "$(tail -1 "$RS/CLAUDE.md")" != "---" ] \
        && pass "constitution-apply --append-index — 템플릿에서 인덱스 절만 (끝 구분선 제외)" || fail "constitution-apply --append-index 실패"
    rm -rf "$RS"
fi

# 엣지 연결 — 폐기된 skill 의 트리거를 누가 받는지, 새 스크립트를 누가 부르는지 파일에 적혀 있어야 해요.
grep -q 'spirit-lint.sh' "$REPO/skills/doctor/SKILL.md" && grep -q 'rules-index.sh' "$REPO/skills/doctor/SKILL.md" && grep -q 'doctor-scan.sh' "$REPO/skills/doctor/SKILL.md" \
    && pass "doctor — spirit-lint · rules-index · doctor-scan 을 실제로 호출" || fail "doctor — 스크립트 호출 엣지 없음"
grep -q 'spirit 점검' "$REPO/skills/doctor/SKILL.md" && grep -q 'rules 보여줘' "$REPO/skills/doctor/SKILL.md" \
    && pass "doctor — 폐기된 spirit·rules 트리거를 description 에서 받음" || fail "doctor — spirit/rules 트리거 미인수 (자연어 라우팅 끊김)"
grep -q 'rules-index.sh' "$REPO/commands/goax.md" && grep -q 'spirit-lint.sh' "$REPO/commands/goax.md" \
    && pass "/goax 인덱스 — rules·spirit 행이 스크립트를 가리킴" || fail "/goax 인덱스 — 폐기 skill 잔재"
grep -q 'status-note.sh --show' "$REPO/skills/triage/SKILL.md" && grep -q 'STATUS.md' "$REPO/skills/triage/SKILL.md" \
    && pass "triage — STATUS.md 를 MEMORY.md 보다 먼저 읽음" || fail "triage — 인계 노트 선독 없음"
grep -q 'status-note.sh' "$REPO/skills/spec-implement/SKILL.md" && grep -q 'references/lane-mode.md' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — halt·완료 시 status-note 갱신 + 레인 루프는 references" || fail "spec-implement — 인계 노트/레인 참조 없음"
grep -q 'status-note.sh --add renamed' "$REPO/skills/spec-implement/references/lane-mode.md" \
    && pass "lane-mode — 레인 보고의 바뀐 이름을 인계 노트로" || fail "lane-mode — renamed 인계 없음"
grep -q 'status-note.sh' "$REPO/skills/zero/SKILL.md" && pass "zero — STATUS 개설을 스크립트로" || fail "zero — STATUS 를 손으로 씀"
grep -qE '^disallowedTools:.*Write.*Edit' "$REPO/agents/lane-scout.md" \
    && pass "lane-scout — disallowedTools 로 편집 금지 (allowlist 아님)" || fail "lane-scout — 편집 금지가 산문뿐"
grep -qE '^tools:' "$REPO/agents/lane-scout.md" && fail "lane-scout — tools: allowlist 사용 (한 항목이라도 안 풀리면 에이전트가 안 뜸)" || true
grep -q 'constitution-apply.sh' "$REPO/skills/onboarding/SKILL.md" && grep -q 'zero-domain-risk.sh --show' "$REPO/skills/onboarding/SKILL.md" \
    && pass "onboarding — Q5 prepend 와 Q2 카운트가 스크립트" || fail "onboarding — 산문 prepend/awk 카운트 잔재"
[ -f "$REPO/templates/default/.ax/scripts/bash/build-index.sh" ] || grep -q 'search-index' "$REPO/templates/default/.gitignore.template" \
    && fail ".gitignore.template 에 .search-index 잔재" || pass ".gitignore.template — .search-index 제거"

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
