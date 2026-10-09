#!/usr/bin/env bash
# tests/smoke/15-gate-regress.sh — §55–§57 — 게이트 리뷰 회귀 · ade-settings · 표시 기호
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/15-gate-regress.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "55. 게이트 리뷰 회귀 — 주석 · here-string · 깨진 python · 한글 룰 이름 · 심링크 · compaction · spec 모호성"
# ───────────────────────────────────────────────────────────
# 새 컨텍스트 리뷰가 실행으로 재현한 결함들이에요. 하나라도 되살아나면 게이트가 조용히 빠지거나 엉뚱한 걸 막아요.
if command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 && python3 -c 'import shlex' >/dev/null 2>&1; then
    RV=$(mktemp -d)
    mkdir -p "$RV/.ax/scripts/bash" "$RV/.ax/hooks/pre-bash" "$RV/.ax/hooks/pre-edit" "$RV/.ax/hooks/session-start" \
             "$RV/.ax/spirit/rules" "$RV/src/pay" "$RV/fakebin"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,session-brief}.sh "$RV/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-bash/"{block-hook-bypass,destructive-facts}.sh "$RV/.ax/hooks/pre-bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-edit/rule-read-gate.sh" "$RV/.ax/hooks/pre-edit/"
    cp "$REPO/templates/default/.ax/hooks/session-start/session-brief.sh" "$RV/.ax/hooks/session-start/"
    : > "$RV/src/pay/a.kt"
    rv_bash() { jq -nc --arg c "$2" --arg s "${3:-s1}" --arg d "$RV" '{tool_input:{command:$c},session_id:$s,cwd:$d}' \
        | CLAUDE_PROJECT_DIR="$RV" bash "$RV/.ax/hooks/pre-bash/$1.sh" >/dev/null 2>&1; echo $?; }
    RV_MISS=0; k=0
    for c in "$(printf '# commit\ngit commit --no-verify -m x')" 'n=${#a}; git push --no-verify' \
             'git log --format=%H#%s && git commit --no-verify' "$(printf 'jq . <<< foo\ngit commit --no-verify -m x')" \
             'export HUSKY=0 && git commit -m x' 'SKIP=eslint git commit -m x' 'LEFTHOOK_EXCLUDE=lint git push'; do
        [ "$(rv_bash block-hook-bypass "$c")" = 2 ] || { fail "block-hook-bypass 미차단 (리뷰 회귀): $c"; RV_MISS=1; }
    done
    for c in 'git status # --no-verify' 'git commit -m "#123 fix"' 'SKIP=1 ./gradlew test'; do
        [ "$(rv_bash block-hook-bypass "$c")" = 0 ] || { fail "block-hook-bypass 오탐 (리뷰 회귀): $c"; RV_MISS=1; }
    done
    [ "$RV_MISS" -eq 0 ] && pass "block-hook-bypass — 주석 · \${#a} · here-string · export/SKIP/LEFTHOOK_EXCLUDE 우회 차단, 주석·메시지 속 # 는 오탐 0"
    RV_MISS=0
    for c in "$(printf '# clean\nrm -rf src')" 'rm -rf src 2>&1' 'git checkout src/pay/a.kt' 'git switch -f main' \
             'git worktree remove --force ../wt' 'git -C src reset --hard'; do
        k=$((k+1)); [ "$(rv_bash destructive-facts "$c" "d$k")" = 2 ] || { fail "destructive-facts 미차단 (리뷰 회귀): $c"; RV_MISS=1; }
    done
    for c in 'git -C /tmp reset --hard' 'git checkout main' 'rm -rf build > /dev/null 2>&1' \
             'rm -rf node_modules .next .svelte-kit storybook-static Pods .dart_tool .terraform cmake-build-debug x.egg-info'; do
        [ "$(rv_bash destructive-facts "$c" fp)" = 0 ] || { fail "destructive-facts 오탐 (리뷰 회귀): $c"; RV_MISS=1; }
    done
    [ "$RV_MISS" -eq 0 ] && pass "destructive-facts — 주석 뒤 · 리다이렉션 · checkout <파일> · switch -f · worktree --force 차단, 다른 리포(-C 밖)·여러 생태계 재생성 디렉토리는 통과"
    [ "$(rv_bash destructive-facts 'rm -rf generated/api' g1)" = 2 ] \
        && printf 'sensors:\n  regenerable_paths: ["generated/**"]\n' > "$RV/.ax/config.yml" \
        && [ "$(rv_bash destructive-facts 'rm -rf generated/api' g2)" = 0 ] \
        && pass "destructive-facts — sensors.regenerable_paths 로 프로젝트가 재생성 경로를 선언해요 (스택 목록을 늘리지 않고)" \
        || fail "destructive-facts — regenerable_paths 가 안 먹어요"
    rm -f "$RV/.ax/config.yml"

    # 깨진 python3 (있는데 실패 — macOS xcrun shim) → 판정 못 했다고 통과시키면 안 돼요
    printf '#!/bin/sh\necho "xcrun: error" >&2; exit 1\n' > "$RV/fakebin/python3"; chmod +x "$RV/fakebin/python3"
    rv_broken() { jq -nc --arg c "$2" --arg s "${3:-b1}" --arg d "$RV" '{tool_input:{command:$c},session_id:$s,cwd:$d}' \
        | PATH="$RV/fakebin:$PATH" CLAUDE_PROJECT_DIR="$RV" bash "$RV/.ax/hooks/pre-bash/$1.sh" >/dev/null 2>&1; echo $?; }
    [ "$(rv_broken block-hook-bypass 'git commit --no-verify -m x')" = 2 ] && [ "$(rv_broken destructive-facts 'rm -rf src' b2)" = 2 ] \
        && pass "깨진 python3 — bypass · destructive 둘 다 간이 판정으로 막아요 (조용한 통과 0)" \
        || fail "깨진 python3 에서 게이트가 통과해요"

    # 한글 룰 파일 이름 — 하나만 읽고 다른 하나까지 읽은 걸로 치면 안 돼요
    printf -- '---\npaths:\n  - "src/pay/**"\n---\n## SP-PAY-001: x\n' > "$RV/.ax/spirit/rules/결제.md"
    printf -- '---\npaths:\n  - "src/pay/**"\n---\n## SP-DLV-001: y\n' > "$RV/.ax/spirit/rules/배송.md"
    rv_edit() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"session_id":"%s"}' "$1" "$2" "$3" \
        | CLAUDE_PROJECT_DIR="${4:-$RV}" bash "$RV/.ax/hooks/pre-edit/rule-read-gate.sh" 2>&1 >/dev/null; }
    rv_edit Read "$RV/.ax/spirit/rules/결제.md" k1 >/dev/null
    RVE=$(rv_edit Edit "$RV/src/pay/a.kt" k1)
    printf '%s' "$RVE" | grep -q '배송.md' && ! printf '%s' "$RVE" | grep -q '결제.md' \
        && pass "rule-read-gate — 한글 룰 이름끼리 Read 기록이 섞이지 않아요 (결제 읽음 → 배송만 요구)" \
        || fail "rule-read-gate 한글 이름 기록이 섞여요: $RVE"

    # 심링크 — 루트가 다른 이름(/tmp ↔ /private/tmp)으로 와도 게이트가 빠지면 안 돼요
    ln -s "$RV" "$RV.lnk" 2>/dev/null
    RVE=$(rv_edit Edit "$RV/src/pay/a.kt" k2 "$RV.lnk")
    printf '%s' "$RVE" | grep -q '결제.md' \
        && pass "rule-read-gate — 프로젝트 루트가 심링크 이름으로 와도 판정해요" \
        || fail "rule-read-gate — 심링크 루트에서 빠져요: $RVE"
    rm -f "$RV.lnk"

    # compaction — 룰 본문이 컨텍스트에서 빠지면 다시 읽게
    rv_edit Read "$RV/.ax/spirit/rules/결제.md" k3 >/dev/null; rv_edit Read "$RV/.ax/spirit/rules/배송.md" k3 >/dev/null
    RVE1=$(rv_edit Edit "$RV/src/pay/a.kt" k3)
    printf '{"session_id":"k3","source":"compact"}' | CLAUDE_PROJECT_DIR="$RV" bash "$RV/.ax/hooks/session-start/session-brief.sh" >/dev/null 2>&1
    RVE2=$(rv_edit Edit "$RV/src/pay/a.kt" k3)
    [ -z "$RVE1" ] && printf '%s' "$RVE2" | grep -q '결제.md' \
        && pass "rule-read-gate — SessionStart(source=compact) 뒤엔 Read 기록이 지워져 다시 읽게 해요" \
        || fail "compaction 초기화가 안 돼요 (before='$RVE1' after='$RVE2')"
    rm -rf "$RV"
else
    pass "§55 — jq/python3 없음, skip"
fi
# spec 모호성 — 새 ID 는 날짜로 시작해서 `--spec 2026-09-25` 가 같은 날 spec 여럿에 걸려요. 첫 번째를 고르면 안 돼요.
SA=$(mktemp -d)
mkdir -p "$SA/.ax/scripts/bash" "$SA/.ax/docs/spec/2026-09-25-aaaa-one" "$SA/.ax/docs/spec/2026-09-25-bbbb-two"
cp -R "$REPO/templates/default/.ax/_templates" "$SA/.ax/_templates"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,add-spec-files,check-spec-clarity}.sh "$SA/.ax/scripts/bash/"
: > "$SA/.ax/docs/spec/2026-09-25-aaaa-one/spec.md"; : > "$SA/.ax/docs/spec/2026-09-25-bbbb-two/spec.md"
CLAUDE_PROJECT_DIR="$SA" bash "$SA/.ax/scripts/bash/add-spec-files.sh" --spec 2026-09-25 --add research --json >/dev/null 2>&1; SA1=$?
CLAUDE_PROJECT_DIR="$SA" bash "$SA/.ax/scripts/bash/check-spec-clarity.sh" --spec 2026-09-25 --json >/dev/null 2>&1; SA2=$?
CLAUDE_PROJECT_DIR="$SA" bash "$SA/.ax/scripts/bash/add-spec-files.sh" --spec bbbb --add research --json >/dev/null 2>&1; SA3=$?
[ "$SA1" -ne 0 ] && [ "$SA2" -ne 0 ] && [ "$SA3" -eq 0 ] && [ -f "$SA/.ax/docs/spec/2026-09-25-bbbb-two/research.md" ] \
    && [ ! -f "$SA/.ax/docs/spec/2026-09-25-aaaa-one/research.md" ] \
    && pass "add-spec-files · check-spec-clarity — 모호한 --spec 은 멈추고, 난수로 정확히 찾아요" \
    || fail "spec 모호성 처리 (add=$SA1 clarity=$SA2 bbbb=$SA3)"
rm -rf "$SA"

# ───────────────────────────────────────────────────────────
section "56. ade-settings — 모노레포 루트 settings 의 goax 훅은 템플릿에서 생성해요"
# ───────────────────────────────────────────────────────────
# 실측(commerce-monorepo): 루트 settings 를 손으로 써서 env CLAUDE_PROJECT_DIR 로 감쌌는데, 템플릿에 훅이 늘어도
# 안 따라와 4개가 빠져 있었어요. 루트에서 연 세션은 루트 settings 의 훅만 돌아요.
if command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    AD=$(mktemp -d)
    mkdir -p "$AD/.claude" "$AD/projects/app/.ax/scripts/bash" "$AD/projects/web/.ax/scripts/bash"
    git -C "$AD" init -q 2>/dev/null
    for p in app web; do cp "$REPO/templates/default/.ax/scripts/bash/"{common,ade-settings}.sh "$AD/projects/$p/.ax/scripts/bash/"; done
    # 손으로 쓴 옛 배선 (훅 1개) + 사용자 자체 훅 + permissions
    cat > "$AD/.claude/settings.json" <<'ADJ'
{"permissions":{"allow":["Bash(ls:*)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
 {"type":"command","command":"env CLAUDE_PROJECT_DIR=\"${CLAUDE_PROJECT_DIR}/projects/app\" bash \"${CLAUDE_PROJECT_DIR}/projects/app/.ax/hooks/pre-bash/block-destructive.sh\""},
 {"type":"command","command":"echo user-own"}]}]}}
ADJ
    ad() { (cd "$AD/projects/${P:-app}" && bash .ax/scripts/bash/ade-settings.sh --plugin-dir "$REPO" --json "$@" 2>/dev/null); }
    TPL_N=$(jq -r '[.hooks[][].hooks[].command | select(test("\\.ax/hooks/"))] | length' "$REPO/templates/default/.claude/settings.json.template")
    ADC=$(ad --check)
    [ "$(echo "$ADC" | jq -r .status)" = warning ] && [ "$(echo "$ADC" | jq -r '.result.missing | length')" = "$((TPL_N - 1))" ] \
        && pass "ade-settings --check — 손으로 쓴 루트 settings 의 누락을 템플릿 기준으로 셈 ($((TPL_N - 1))개)" \
        || fail "ade-settings --check: $ADC"
    ad --apply --dry-run >/dev/null; [ "$(ls "$AD/.claude" | grep -c .)" = 1 ] \
        && pass "ade-settings --apply --dry-run — 아무것도 안 써요" || fail "ade-settings dry-run 이 썼어요"
    ad --apply >/dev/null
    AS="$AD/.claude/settings.json"
    [ "$(ad --check | jq -r .status)" = ok ] \
        && [ "$(jq -r '.permissions.allow[0]' "$AS")" = 'Bash(ls:*)' ] \
        && [ "$(jq -r '[.hooks[][].hooks[].command | select(. == "echo user-own")] | length' "$AS")" = 1 ] \
        && jq -r '.hooks.SessionStart[].hooks[].command' "$AS" | grep -qF 'env CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR}/projects/app" bash "${CLAUDE_PROJECT_DIR}/projects/app/.ax/hooks/session-start/session-brief.sh"' \
        && pass "ade-settings --apply — 템플릿대로 배선, permissions · 사용자 훅 보존, env CLAUDE_PROJECT_DIR 형식" \
        || fail "ade-settings --apply 결과가 이상해요: $(jq -c . "$AS" | cut -c1-300)"
    [ "$(jq -r '[.hooks[][].hooks[].command | select(contains("/projects/app/.ax/hooks/pre-bash/block-destructive"))] | length' "$AS")" = 1 ] \
        && [ "$(ad --apply | jq -r .result.changed)" = false ] \
        && pass "ade-settings --apply — 멱등 (옛 수동 항목은 교체, 두 번째 적용은 변화 없음)" \
        || fail "ade-settings --apply 가 중복을 남기거나 멱등이 아니에요"
    P=web ad --apply >/dev/null
    [ "$(ad --check | jq -r .status)" = ok ] && [ "$(P=web ad --check | jq -r .status)" = ok ] \
        && [ "$(jq -r '[.hooks[][].hooks[].command | select(test("/\\.ax/hooks/"))] | length' "$AS")" = "$((TPL_N * 2))" ] \
        && pass "ade-settings — 한 저장소의 goax 프로젝트 둘이 각자 자기 몫만 (서로 안 지워요)" \
        || fail "ade-settings — 프로젝트 둘 공존 실패"
    SG=$(mktemp -d); mkdir -p "$SG/.ax/scripts/bash"; git -C "$SG" init -q 2>/dev/null
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,ade-settings}.sh "$SG/.ax/scripts/bash/"
    # 단일 저장소 — `jq -s '.[0] * .[1]'` 머지는 배열을 통째로 바꿔 사용자 훅을 지웠어요. 손으로 쓴 옛 형태
    # ("$CLAUDE_PROJECT_DIR"/.ax/hooks/…, 맨 .ax/hooks/…)도 goax 몫으로 알아보고 바꿔요. 백업 파일은 안 만들어요.
    mkdir -p "$SG/.claude"
    cat > "$SG/.claude/settings.json" <<'SGJ'
{"permissions":{"allow":["Bash(ls:*)"]},"statusLine":{"type":"command","command":"echo hud"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[
 {"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.ax/hooks/pre-bash/block-destructive.sh"},
 {"type":"command","command":"bash ./.ax/hooks/pre-bash/grep-on-commit.sh"},
 {"type":"command","command":"bash \"${CLAUDE_PROJECT_DIR}/.ax/hooks/pre-bash/zero-guard-bash.sh\""},
 {"type":"command","command":"echo user-own"}]}]}}
SGJ
    sg() { (cd "$SG" && bash .ax/scripts/bash/ade-settings.sh --plugin-dir "$REPO" --json "$@" 2>/dev/null); }
    SGC=$(sg --check)
    [ "$(echo "$SGC" | jq -r '.result.project_rel')" = "" ] && [ "$(echo "$SGC" | jq -r '.result.stale | length')" = 0 ] \
        && [ "$(echo "$SGC" | jq -r '.result.missing | length')" = "$((TPL_N - 2))" ] \
        && pass "ade-settings 단일 저장소 --check — 손으로 쓴 옛 형태(\"\$CLAUDE_PROJECT_DIR\"/ · ./)도 goax 몫, 템플릿 밖 zero-guard 는 남의 몫" \
        || fail "ade-settings 단일 저장소 --check: $SGC"
    sg --apply >/dev/null
    SS="$SG/.claude/settings.json"
    [ "$(sg --check | jq -r .status)" = ok ] && [ "$(sg --apply | jq -r .result.changed)" = false ] \
        && [ "$(jq -r '.permissions.allow[0]' "$SS")" = 'Bash(ls:*)' ] && [ "$(jq -r '.statusLine.command' "$SS")" = 'echo hud' ] \
        && [ "$(jq -r '[.hooks[][].hooks[].command | select(. == "echo user-own")] | length' "$SS")" = 1 ] \
        && [ "$(jq -r '[.hooks[][].hooks[].command | select(test("zero-guard-bash"))] | length' "$SS")" = 1 ] \
        && [ "$(jq -r '[.hooks[][].hooks[].command | select(test("grep-on-commit"))] | length' "$SS")" = 1 ] \
        && jq -r '.hooks.SessionStart[].hooks[].command' "$SS" | grep -qF 'bash "${CLAUDE_PROJECT_DIR}/.ax/hooks/session-start/session-brief.sh"' \
        && [ "$(ls -A "$SG/.claude" | grep -c .)" = 1 ] \
        && pass "ade-settings 단일 저장소 --apply — 사용자 훅·zero-guard·permissions·statusLine 보존, ./ 형태는 중복 없이 교체, 멱등, 백업 파일 없음" \
        || fail "ade-settings 단일 저장소 --apply 결과가 이상해요: $(ls -A "$SG/.claude") $(jq -c . "$SS" | cut -c1-300)"
    rm -rf "$AD" "$SG"
else
    pass "§56 — jq/git 없음, skip"
fi

# ───────────────────────────────────────────────────────────
section "57. 표시 기호 — 사용자에게 보이는 문서는 symbols.md 어휘만"
# ───────────────────────────────────────────────────────────
# 섹션마다 다른 그림 이모지가 붙어 정작 ❌·❗ 가 안 보였어요 (doctor 한 파일에 서로 다른 이모지 20종).
# VS16(⚠️ ℹ️ ⚙️)은 터미널마다 폭이 갈려 박스 줄이 어긋나고, ✓ ✗ ⚠ 는 너무 작아요.
# 예외: HUD 체인 줄(›) · triage 의 MEMORY.md ★ 표지 설명 · 어휘 SSOT(symbols.md) 자체.
EMO_OUT=$(cd "$REPO" && python3 - skills/*/SKILL.md skills/*/references/*.md agents/*.md commands/*.md \
    docs/reference/*.md templates/default/*.template <<'PYE' 2>&1
import re, sys
allow = set("✅❗❌⛔📍🎯📂👉🔴🟡🔵")
rx = re.compile("[☀-➿⬀-⯿\U0001F000-\U0001FAFF]|️")
bad = []
for f in sys.argv[1:]:
    if f.endswith("docs/reference/symbols.md"):
        continue
    for n, line in enumerate(open(f, encoding="utf-8"), 1):
        if "›" in line or "★ 표시" in line:
            continue
        hit = sorted({m for m in rx.findall(line) if m not in allow})
        if hit:
            bad.append("%s:%d %s" % (f, n, " ".join("U+FE0F" if h == "️" else h for h in hit)))
print("\n".join(bad[:15]))
print("COUNT=%d" % len(bad))
PYE
)
if echo "$EMO_OUT" | grep -q '^COUNT=0$'; then
    pass "사용자 대면 문서 — 어휘 밖 이모지 · VS16 · 폭 1칸 상태 기호 0건"
else
    fail "어휘 밖 이모지 ($(echo "$EMO_OUT" | grep '^COUNT=' | cut -d= -f2)줄) — docs/reference/symbols.md 참고:
$(echo "$EMO_OUT" | grep -v '^COUNT=')"
fi
grep -q 'symbols.md' "$REPO/templates/default/.ax/spirit/tone.md" \
    && pass "tone.md 가 표시 기호 SSOT(symbols.md)를 가리켜요" || fail "tone.md 에 symbols.md 포인터가 없어요"

smoke_done
