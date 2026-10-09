#!/usr/bin/env bash
# tests/smoke/01-structure.sh — §1–§8 — manifest · skills · agents · templates · MANIFEST · HUD · 문법
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/01-structure.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

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

# changelog 최신 ↔ VERSION — 위 검사의 반대 방향.
# 위는 VERSION → changelog 만 봐요. changelog/<새 버전>.md 를 넣고 스탬프를 안 올리면
# 네 스탬프끼리는 여전히 일치해서 CI 가 초록이에요 — 실제로 0.5.8 이 그렇게 나갔어요.
# 그러면 배포가 멈춰요: 플러그인 캐시는 버전 문자열로 디렉토리를 나눠서
# (cache/goax/goax/<ver>/), 스탬프가 그대로면 marketplace update + install 을 돌려도
# 새 디렉토리가 안 생기고 사용자는 옛 버전을 계속 써요.
CHANGELOG_MAX=$(find "$REPO/changelog" -maxdepth 1 -name '*.md' 2>/dev/null \
    | sed 's|.*/||; s|\.md$||' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[ -n "$CHANGELOG_MAX" ] && [ "$CHANGELOG_MAX" = "$VER_FILE" ] \
    && pass "changelog 최신 ↔ VERSION (=$VER_FILE)" \
    || fail "changelog 최신/VERSION 불일치 (changelog=$CHANGELOG_MAX vs VERSION=$VER_FILE) — 스탬프를 안 올리면 배포가 멈춰요"

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
    # model 이 없으면 부모 세션 모델을 상속해요 — 상위 모델 세션에선 리뷰어 라운드마다 그 모델로 돌아요 (#44)
    has_model=$(awk 'NR==1{next} /^---/{exit} /^model: (opus|sonnet|haiku|fable|inherit)$/{n++} END{print n+0}' "$f")
    if [ "$has_name" -ge 1 ] && [ "$has_desc" -ge 1 ] && [ "$has_model" -ge 1 ]; then
        pass "agents/$agent.md (frontmatter name+description+model OK)"
    else
        fail "agents/$agent.md frontmatter 누락 (name=$has_name, description=$has_desc, model=$has_model)"
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
    templates/default/.ax/hooks/subagent-start/harness-pointer.sh \
    templates/default/.ax/hooks/stop/spec-gate.sh \
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

# .gitignore.template — runtime 엔트리 5종 모두 포함하는지 검증.
# `*.lock/` 는 슬래시가 **필수**예요 — `goax_lock` 은 mkdir + 안에 pid 파일이라 디렉토리
# 전용이고, 슬래시를 빼면 남의 프로젝트의 `Cargo.lock`·`Gemfile.lock` 이 조용히 사라져요.
GI_TPL="$REPO/templates/default/.gitignore.template"
if [ -f "$GI_TPL" ]; then
    missing=0
    for entry in ".ax/state.json" ".ax/current-task.json" ".ax/*.suggested" ".ax/.onboarding-pending" "*.lock/" \
                 ".ax/docs/spec/*/.review-round" ".ax/docs/spec/*/.review-snapshot/" ".ax/docs/spec/*/review-spec.architect.md" ".ax/docs/spec/*/review-spec.evaluator.md"; do
        grep -qxF "$entry" "$GI_TPL" || { fail ".gitignore.template 누락 엔트리: $entry"; missing=$((missing+1)); }
    done
    [ "$missing" -eq 0 ] && pass ".gitignore.template — runtime 엔트리 5종 + spec 리뷰 원장·리뷰어 파일 4종 포함"
fi

# 중첩 .suggested 가 실제로 무시되는가 — 엔트리 존재가 아니라 git 동작으로.
# `.ax/*.suggested` 는 한 단계만 잡아요. provision 은 `.ax/spirit/`·`.ax/mistakes/`·
# `.ax/_templates/spec/` 밑에도 .suggested 를 만들어서, 그것들이 git status 에 ?? 로
# 새어나가 실수로 커밋될 수 있었어요. 위 엔트리 검사는 리터럴 grep 이라 못 봤어요 —
# 다섯 줄이 다 있어도 중첩은 안 잡히니까요. 그래서 동작으로 봐요.
if [ -f "$GI_TPL" ]; then
    GIT_T=$(mktemp -d)
    git -C "$GIT_T" init -q >/dev/null 2>&1
    cp "$GI_TPL" "$GIT_T/.gitignore"
    mkdir -p "$GIT_T/.ax/spirit" "$GIT_T/.ax/mistakes" "$GIT_T/.ax/_templates/spec"
    gi_miss=0
    for p in ".ax/config.yml.suggested" ".ax/spirit/tone.md.suggested" \
             ".ax/mistakes/README.md.suggested" ".ax/_templates/spec/spec.md.suggested"; do
        git -C "$GIT_T" check-ignore -q "$p" 2>/dev/null \
            || { fail ".gitignore.template — $p 가 무시되지 않음 (git status 로 샘)"; gi_miss=$((gi_miss+1)); }
    done
    [ "$gi_miss" -eq 0 ] && pass ".gitignore.template — 중첩 .suggested 4종 모두 무시 (동작 검증)"
    rm -rf "$GIT_T"
fi

# 잔재 검증 — spirit/rules/output-style.md (plugin meta로 분류되어 출고에서 제거됨)
[ -f "$REPO/templates/default/.ax/spirit/rules/output-style.md" ] \
    && fail "spirit/rules/output-style.md — plugin 출고 제거됐어야 함 (plugin meta)" \
    || pass "spirit/rules/output-style.md 출고 제거됨"

# ───────────────────────────────────────────────────────────
section "4.1 settings.json.template ↔ .ax/hooks/ 양방향 cross-check"
# ───────────────────────────────────────────────────────────
# 정방향: settings.json.template 이 참조하는 .ax/... 경로가 실제로 존재하는지.
# 역방향: .ax/hooks/{session-start,pre-compact,user-prompt,pre-bash,pre-edit,post-edit,subagent-start,stop}/*.sh 가 모두 등록됐는지
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
for phase in ["session-start", "pre-compact", "user-prompt", "pre-bash", "pre-edit", "post-edit", "subagent-start", "stop"]:
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
# 루프가 fail 을 냈는데 뒤에서 무조건 pass 를 찍으면 초록이 거짓말을 해요 — 루프 결과로 게이팅.
[ "$ok_skills" -eq "$total_skills" ] \
    && pass "skill frontmatter ($ok_skills/$total_skills)" \
    || fail "skill frontmatter — description 누락 $((total_skills - ok_skills))개 ($ok_skills/$total_skills)"
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
section "8. state.json 마무리 — skill 마다 update-state.sh --skill <자기 이름> (인라인 jq 는 writer 계약이 막아요)"
# ───────────────────────────────────────────────────────────
# 예전엔 SKILL.md 12곳이 `jq '.last_skill = … | .skill_calls += 1' state.json > tmp && mv` 를 인라인으로 들고 있었고
# 여기서 그 jq 문법만 검사했어요. 무락이라 tasks-gate.sh(task_seal) 와 경합하면 한쪽이 사라져서 update-state.sh
# `--skill` 로 흡수했어요 — 이제 검사할 건 "각 skill 이 자기 이름으로 부르는가" 예요.
sk_bad=0
for sk in lane mistake spec spec-validate triage doctor audit zero up spec-tasks spec-implement onboarding; do
    grep -qE "update-state\.sh --skill ${sk}([[:space:]]|$)" "$REPO/skills/$sk/SKILL.md" \
        || { sk_bad=$((sk_bad+1)); fail "$sk — 'update-state.sh --skill $sk' 호출 없음 (last_skill·skill_calls 갱신 끊김)"; }
done
grep -q -- '--skill mistake --last-mistake "\$FILE"' "$REPO/skills/mistake/SKILL.md" \
    || { sk_bad=$((sk_bad+1)); fail "mistake — --last-mistake \"\$FILE\" 없음 (last_mistake_file 갱신 끊김)"; }
[ "$sk_bad" -eq 0 ] && pass "update-state.sh --skill — 12 skill 전부 자기 이름으로 호출 (+ mistake 의 --last-mistake)"

smoke_done
