#!/usr/bin/env bash
# tests/smoke/23-ade-config.sh — §84 ADE 루트 판정 하나로 · §85 config.yml 새 키 병합
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/23-ade-config.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

command -v jq >/dev/null 2>&1 || { pass "jq 없음 — §84–§85 건너뜀"; smoke_done; }

# ───────────────────────────────────────────────────────────
section "84. ADE 루트 — vendor-skills 와 ade-settings 가 같은 답을 내요 (단일 · 모노레포 · ade_root · --ade-root)"
# ───────────────────────────────────────────────────────────
# 모노레포 픽스처: git 루트에 .claude/ 와 .goax-root, projects/app/.ax/ 와 projects/app/.claude/settings.json
if fx_install AP; then
    MR=$(mktemp -d); MR=$(cd -P "$MR" && pwd -P); git -C "$MR" init -q
    mkdir -p "$MR/projects" "$MR/.claude/skills"; mv "$AP" "$MR/projects/app"
    APP="$MR/projects/app"; mkdir -p "$APP/.claude"; [ -f "$APP/.claude/settings.json" ] || echo '{}' > "$APP/.claude/settings.json"
    printf '# goax\nprojects/app\n' > "$MR/.goax-root"; echo "0.0.1" > "$MR/.claude/.goax-vendored"
    ade_v() { (cd "$1" && GOAX_PROJECT_DIR="$2" bash "$APP/.ax/scripts/bash/vendor-skills.sh" --check --json "${@:3}" 2>/dev/null) | jq -r '[.result.ade_root, .result.split, .result.vendored] | @tsv'; }
    ade_s() { (cd "$1" && GOAX_PROJECT_DIR="$2" bash "$APP/.ax/scripts/bash/ade-settings.sh" --check --plugin-dir "$REPO" --json "${@:3}" 2>/dev/null) | jq -r '.result.ade_root'; }
    V1=$(ade_v "$MR" "$APP"); S1=$(ade_s "$MR" "$APP")
    # ade_root: "." — 하위 프로젝트에서 세션을 여는 팀
    sed -i.bak 's/^ade_root: ""/ade_root: "."/' "$APP/.ax/config.yml" && rm -f "$APP/.ax/config.yml.bak"
    V2=$(ade_v "$MR" "$APP"); S2=$(ade_s "$MR" "$APP")
    # --ade-root 가 config 보다 먼저예요
    V3=$(ade_v "$MR" "$APP" --ade-root "$MR"); S3=$(ade_s "$MR" "$APP" --ade-root "$MR")
    # 디렉토리가 아닌 ade_root 는 오류
    sed -i.bak 's/^ade_root: "."/ade_root: "nope"/' "$APP/.ax/config.yml" && rm -f "$APP/.ax/config.yml.bak"
    (cd "$MR" && GOAX_PROJECT_DIR="$APP" bash "$APP/.ax/scripts/bash/vendor-skills.sh" --check --json >/dev/null 2>&1); BADV=$?
    [ "$V1" = "$MR	true	true" ] && [ "$S1" = "$MR" ] \
        && [ "$V2" = "$APP	false	false" ] && [ "$S2" = "$APP" ] \
        && [ "$V3" = "$MR	true	true" ] && [ "$S3" = "$MR" ] && [ "$BADV" = 1 ] \
        && pass "모노레포 — 기본은 git 최상위(projects/app/.claude 가 있어도), ade_root \".\" 면 프로젝트, --ade-root 가 먼저, 없는 경로는 exit 1 — 두 스크립트 같은 답" \
        || fail "모노레포 ADE 판정: v1=[$V1] s1=[$S1] v2=[$V2] s2=[$S2] v3=[$V3] s3=[$S3] bad=$BADV (want $MR)"
    rm -rf "$MR"
fi
if fx_install SG --git; then
    SGP=$(cd -P "$SG" && pwd -P)
    V=$(cd "$SG" && GOAX_PROJECT_DIR="$SG" bash .ax/scripts/bash/vendor-skills.sh --check --json 2>/dev/null | jq -r '[.result.ade_root, .result.split] | @tsv')
    S=$(cd "$SG" && GOAX_PROJECT_DIR="$SG" bash .ax/scripts/bash/ade-settings.sh --check --plugin-dir "$REPO" --json 2>/dev/null | jq -r '.result.ade_root')
    [ "$V" = "$SGP	false" ] && [ "$S" = "$SGP" ] \
        && pass "단일 저장소 — ADE 루트 = 프로젝트 루트, split=false (두 스크립트 같은 답)" || fail "단일 저장소 ADE 판정: v=[$V] s=[$S] want $SGP"
fi
grep -q '^goax_ade_root()' "$REPO/templates/default/.ax/scripts/bash/lib/paths.sh" \
    && ! grep -q 'rev-parse --show-toplevel' "$REPO/templates/default/.ax/scripts/bash/ade-settings.sh" \
    && grep -q 'goax_ade_root' "$REPO/templates/default/.ax/scripts/bash/ade-settings.sh" \
    && grep -q '^ade_root: ""' "$REPO/templates/default/.ax/config.yml" \
    && pass "goax_ade_root 한 곳 — ade-settings 가 자체 git 판정 없이 같은 함수를 써요, 템플릿에 ade_root" \
    || fail "ADE 판정이 두 곳으로 갈라졌어요"

# ───────────────────────────────────────────────────────────
section "85. config-merge — 템플릿에만 있는 키를 기본값으로 더하고 값은 건드리지 않아요"
# ───────────────────────────────────────────────────────────
if fx_install CM; then
    C="$CM/.ax/config.yml"; T="$REPO/templates/default/.ax/config.yml"
    # 옛 설치본 흉내 — 새 키를 지우고, 팀이 바꾼 값을 둬요
    awk '!/^  foreign_executors:/ && !/^  rule_lint_allow:/ && !/^ade_root:/' "$C" > "$C.n" && mv "$C.n" "$C"
    awk '/^agent_models:/{skip=1; next} skip && /^[^[:space:]]/{skip=0} !skip' "$C" > "$C.n" && mv "$C.n" "$C"
    sed -i.bak 's/^  mode: warning /  mode: fail /; s/^  payment: L3 /  wallet: L3 /' "$C" && rm -f "$C.bak"
    cm() { (cd "$CM" && GOAX_PROJECT_DIR="$CM" bash .ax/scripts/bash/config-merge.sh --template "$T" --json "$@" 2>/dev/null); }
    BEFORE=$(cksum < "$C"); D=$(cm --dry-run); AFTER_DRY=$(cksum < "$C")
    A=$(cm); R=$(cm)
    printf '%s\n' "$D" | jq -e '.result.dry_run and (.result.added | length) == 4' >/dev/null && [ "$BEFORE" = "$AFTER_DRY" ] \
        && printf '%s\n' "$A" | jq -e '(.result.added | sort) == ["ade_root", "agent_models", "sensors.foreign_executors", "sensors.rule_lint_allow"]' >/dev/null \
        && printf '%s\n' "$R" | jq -e '.result.added == []' >/dev/null \
        && grep -q '^  mode: fail ' "$C" && grep -q '^  wallet: L3 ' "$C" && ! grep -q '^  payment:' "$C" \
        && awk '/^sensors:/{s=1; next} s && /^[^[:space:]#]/{s=0} s && /^  foreign_executors:/{f=1} END{exit !f}' "$C" \
        && grep -q '^ade_root: ""' "$C" && grep -q '^agent_models:' "$C" && [ ! -e "$C.lock" ] \
        && [ "$(GOAX_PROJECT_DIR="$CM" bash -c 'source "$0/.ax/scripts/bash/common.sh"; goax_yaml_list "$0/.ax/config.yml" foreign_executors | wc -l' "$CM" | tr -d ' ')" = 0 ] \
        && pass "config-merge — dry-run 무기록, 빠진 키 4개(최상위 2 · sensors 2)를 제자리에, 두 번째는 0, 팀 값 · domain_risk 유지" \
        || fail "config-merge: dry=$(printf '%s' "$D" | jq -c .result) apply=$(printf '%s' "$A" | jq -c .result) again=$(printf '%s' "$R" | jq -c .result.added)"
    # config-set — 최상위 스칼라는 바꾸고, 값 없는 섹션 키는 거부해요
    CS1=$(cd "$CM" && GOAX_PROJECT_DIR="$CM" bash .ax/scripts/bash/config-set.sh ade_root "." --json 2>/dev/null | jq -c '[.status, .result.key, .result.after]')
    (cd "$CM" && GOAX_PROJECT_DIR="$CM" bash .ax/scripts/bash/config-set.sh agent_models x --json >/dev/null 2>&1); CS2=$?
    [ "$CS1" = '["ok","ade_root","."]' ] && [ "$CS2" = 1 ] && grep -q '^ade_root: "."' "$C" && grep -q '^agent_models:$' "$C" \
        && pass "config-set — 최상위 스칼라(ade_root)를 바꾸고, 값 없는 섹션 키(agent_models)는 exit 1" \
        || fail "config-set 최상위 키: cs1=$CS1 cs2=$CS2"
    # /up 재실행(provision)이 같은 병합을 해요
    awk '!/^  rule_lint_allow:/' "$C" > "$C.n" && mv "$C.n" "$C"
    PJ=$(bash "$REPO/scripts/provision.sh" --target "$CM" --json 2>/dev/null)
    printf '%s\n' "$PJ" | jq -e '.result.config_added == ["sensors.rule_lint_allow"]' >/dev/null && grep -q '^  rule_lint_allow:' "$C" \
        && pass "provision — 기존 config.yml 에 템플릿 새 키를 더하고 result.config_added 로 알려요" \
        || fail "provision config_added: $(printf '%s' "$PJ" | jq -c '.result.config_added')"
fi

smoke_done
