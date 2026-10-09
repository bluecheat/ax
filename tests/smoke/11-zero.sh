#!/usr/bin/env bash
# tests/smoke/11-zero.sh — §42 — zero · onboarding 스크립트
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/11-zero.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "42. zero · onboarding 스크립트 — 조용한 성공이 데이터를 지우던 자리"
# ───────────────────────────────────────────────────────────
# 여기 6개는 전부 `status:"ok"` + exit 0 으로 끝나면서 데이터를 지우거나 아무것도 안
# 했어요. bash 문법 검사로는 안 잡혀요 (D6 은 런타임 bad substitution) — 실행만이 잡아요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§42 skip (jq 없음)"
else
    ZD=$(mktemp -d)
    mkdir -p "$ZD/.ax/scripts/bash" "$ZD/.ax/spirit/rules" "$ZD/.ax/mistakes" "$ZD/.ax/docs"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,zero-domain-risk,zero-ablation,zero-verify,constitution-apply,init-mistake-file,detect-model}.sh "$ZD/.ax/scripts/bash/"
    printf 'sensors:\n  mode: warning\ndomain_risk:\n  payment: L3\n  order: L2\n  product: L1\n  search: L0\ndefault_risk: L0\n' > "$ZD/.ax/config.yml"
    # macOS 면 /bin/bash (3.2) 로 불러요 — 이 회귀는 bash 3.2 × en_US collation 조합에서
    # 터졌고, `bash` 가 5.x 로 잡히는 환경에선 통과해 버려요.
    OLDBASH=/bin/bash; [ -x "$OLDBASH" ] || OLDBASH="$BASH"
    zdr() { GOAX_PROJECT_DIR="$ZD" "$OLDBASH" "$ZD/.ax/scripts/bash/zero-domain-risk.sh" "$@" 2>/dev/null; }
    zdr_keys() { zdr --show --json | jq -r '.result.before.keys'; }

    cp "$ZD/.ax/config.yml" "$ZD/config.before"
    zdr --set "Payment=L2" --json >/dev/null 2>&1; ZD_RC=$?
    [ "$ZD_RC" -eq 1 ] && cmp -s "$ZD/.ax/config.yml" "$ZD/config.before" && [ "$(zdr_keys)" = "4" ] \
        && pass "zero-domain-risk --set — 대문자 키는 exit 1 + domain_risk 4개 보존 ([a-z] collation)" \
        || fail "zero-domain-risk --set — 'Payment=L2' 가 exit $ZD_RC, keys=$(zdr_keys) (기대 1 / 4)"
    zdr --set "new=oops=L3" --json >/dev/null 2>&1; ZD_RC=$?
    [ "$ZD_RC" -eq 1 ] && cmp -s "$ZD/.ax/config.yml" "$ZD/config.before" \
        && pass "zero-domain-risk --set — 'new=oops=L3' 는 exit 1 + 파일 무변경" \
        || fail "zero-domain-risk --set — 깨진 입력이 exit $ZD_RC + 파일 변경"
    zdr --set "checkout=L2,orders-api=L3" --json >/dev/null 2>&1; ZD_RC=$?
    [ "$ZD_RC" -eq 0 ] && [ "$(zdr_keys)" = "2" ] \
        && pass "zero-domain-risk --set — 정상 입력은 반영 (checkout·orders-api)" || fail "zero-domain-risk --set — 정상 입력 실패 (exit $ZD_RC)"

    ca() { GOAX_PROJECT_DIR="$ZD" bash "$ZD/.ax/scripts/bash/constitution-apply.sh" "$@" 2>/dev/null; }
    printf '# X — Constitution\n\n## META — 핵심 가드레일\n\n🔴 **`AX:CRITICAL:001`** — 결제 API 는 멱등성 키 필수\n' > "$ZD/block.md"
    printf '# old\n\n## Database\n무관한 줄\n' > "$ZD/CLAUDE.md"
    CA_OUT=$(ca --scan-duplicates --block "$ZD/block.md" --target CLAUDE.md --json); CA_RC=$?
    [ "$CA_RC" -eq 0 ] && echo "$CA_OUT" | jq -e '.status=="ok" and .result.count==0 and .result.duplicates==[]' >/dev/null 2>&1 \
        && pass "constitution-apply --scan-duplicates — 중복 0건도 JSON (빈 grep 의 pipefail 로 죽지 않음)" \
        || fail "constitution-apply --scan-duplicates — 중복 0건에 exit $CA_RC / 출력 [${CA_OUT:0:80}]"
    ca --block "$ZD/block.md" --target CLAUDE.md --json >/dev/null 2>&1
    printf '# X — Constitution\n\n## META — 핵심 가드레일\n\n🔴 **`AX:CRITICAL:009`** — 새 룰\n' > "$ZD/block2.md"
    ca --block "$ZD/block2.md" --target CLAUDE.md --json | jq -e '.result.applied==true' >/dev/null 2>&1 \
        && pass "constitution-apply — 헤더가 같아도 룰 토큰이 새로우면 적용 (헤더로 판정 안 함)" \
        || fail "constitution-apply — 같은 헤더면 새 룰을 통째로 건너뜀"
    ca --block "$ZD/block2.md" --target CLAUDE.md --json >/dev/null 2>&1
    [ $? -eq 2 ] && pass "constitution-apply — 같은 블록 재적용은 exit 2 (idempotent 유지)" || fail "constitution-apply — 재적용을 막지 않음"

    za() { GOAX_PROJECT_DIR="$ZD" bash "$ZD/.ax/scripts/bash/zero-ablation.sh" "$@" 2>/dev/null; }
    printf -- '---\ncategory: ops\n---\n## SP-OPS-001: 원본\n' > "$ZD/.ax/spirit/rules/ops.md"
    za --off --json >/dev/null 2>&1
    printf -- '---\ncategory: ops\n---\n## SP-OPS-002: 사용자가 그 사이에 새로 쓴 것\n' > "$ZD/.ax/spirit/rules/ops.md"
    ZA_OUT=$(za --on --json)
    echo "$ZA_OUT" | jq -e '.status=="warning" and (.warnings|length)==1 and .result.active==["ops"]' >/dev/null 2>&1 \
        && grep -q 'SP-OPS-002' "$ZD/.ax/spirit/rules/ops.md" && [ -f "$ZD/.ax/spirit/rules/ops.md.ablated" ] \
        && pass "zero-ablation --on — 목적지가 생겼으면 덮지 않고 warning (.ablated 보존)" \
        || fail "zero-ablation --on — 사용자 편집을 덮어씀: $(echo "$ZA_OUT" | jq -c .result)"

    printf 'commands:\n  test: '"'"'test "a b" = "a b"'"'"'\n' > "$ZD/.ax/config.yml"
    GOAX_PROJECT_DIR="$ZD" bash "$ZD/.ax/scripts/bash/zero-verify.sh" --json 2>/dev/null \
        | jq -e '.result.passed==1 and (.result.checks[] | select(.name=="test") | .exit==0)' >/dev/null 2>&1 \
        && pass "zero-verify — 따옴표가 든 명령을 원형대로 실행 (tr -d 로 벗기지 않음)" \
        || fail "zero-verify — 따옴표를 지워서 명령이 깨짐"

    # zero-verify — 주석 파서 13종 회귀.
    # 값 첫 글자로 따옴표/주석을 가르는 sed t-분기가 13가지 입력에서 정확한지, 값이 통째로
    # 주석인 키가 PASSED 로 뒤집히지 않는지를 재요. 옛 파서는 `s/[[:space:]]*#.*$//` 하나라
    # `typecheck: 'grep -c "#" README.md'` 를 `grep -c "` 로 잘라놓고 "명령이 실패했다" 고
    # 보고했어요 — 게이트를 *읽다가* 깨진 건데요. 바로 위 tr -d 사고와 같은 계열이에요.
    # 이 블록은 §42 의 jq 가드 안이라 따로 감싸지 않아요.
    ZVC=$(mktemp -d)
    mkdir -p "$ZVC/.ax/scripts/bash"
    cp "$SCRIPTS_DIR/"{common,zero-verify}.sh "$ZVC/.ax/scripts/bash/"

    zvc_check() {
        local label="$1" key="$2" expect="$3" got
        got=$(GOAX_PROJECT_DIR="$ZVC" bash "$ZVC/.ax/scripts/bash/zero-verify.sh" --dry-run --json 2>/dev/null \
              | jq -r --arg k "$key" '.result.checks[] | select(.name==$k) | .cmd')
        [ "$got" = "$expect" ] && pass "zero-verify 주석 파서 — $label" \
            || fail "zero-verify 주석 파서 — $label (기대 [$expect], 실제 [$got])"
    }

    printf '%s\n' \
        'commands:' \
        '  typecheck: '"'"'grep -c "#" README.md'"'"'' \
        '  test: npm test  # 로컬만' \
        '  build: "make all # not-a-comment"  # 진짜 주석' \
        '  lint: eslint .' \
        > "$ZVC/.ax/config.yml"
    zvc_check "1 따옴표 안 # 보존" typecheck 'grep -c "#" README.md'
    zvc_check "2 따옴표 밖 주석 제거 + 우측 트림" test "npm test"
    zvc_check "3 따옴표 안팎 # 공존" build 'make all # not-a-comment'
    zvc_check "4 무변화" lint "eslint ."

    printf '%s\n' \
        'commands:' \
        "  typecheck: it's fine  # comment" \
        "  test: don't stop  # 주석" \
        '  build: eslint --grep=#123' \
        '  lint: curl http://x/#frag' \
        > "$ZVC/.ax/config.yml"
    zvc_check "5 평문 아포스트로피는 여는 따옴표가 아님" typecheck "it's fine"
    zvc_check "6 같은 계열" test "don't stop"
    zvc_check "7 공백 없는 #은 주석이 아님" build "eslint --grep=#123"
    zvc_check "8 URL 프래그먼트" lint "curl http://x/#frag"

    printf '%s\n' \
        'commands:' \
        '  typecheck: "tsc --noEmit"' \
        '  test: grep -c "#" x  # 주석' \
        '  build: sh -c '"'"'a  # 미종결' \
        '  lint:  # 아직 없음' \
        > "$ZVC/.ax/config.yml"
    zvc_check "9 바깥 따옴표 한 쌍만" typecheck "tsc --noEmit"
    zvc_check "10 인용된 #은 보존, 뒤 주석만 제거" test 'grep -c "#" x'
    zvc_check "11 짝 없는 따옴표는 평문 갈래" build "sh -c 'a"

    ZVC_LINT=$(GOAX_PROJECT_DIR="$ZVC" bash "$ZVC/.ax/scripts/bash/zero-verify.sh" --json 2>/dev/null)
    echo "$ZVC_LINT" | jq -e '(.result.checks[] | select(.name=="lint") | .cmd)=="" and .result.skipped>=1' >/dev/null 2>&1 \
        && pass "zero-verify 주석 파서 — 12 값이 통째로 주석인 키는 빈 값 + SKIPPED (PASSED 아님)" \
        || fail "zero-verify 주석 파서 — 12 lint 가 PASSED 로 뒤집힘: $(echo "$ZVC_LINT" | jq -c '.result')"

    printf '%s\n' \
        'commands:' \
        '  typecheck: "say \"hi\""' \
        '  test: eslint .' \
        '  build: eslint .' \
        '  lint: eslint .' \
        > "$ZVC/.ax/config.yml"
    # 기대값은 백슬래시 하나로 끝나는 `say \` 예요 — `[^"]*` 가 첫 `\"` 에서 멈춰요.
    zvc_check "13 이스케이프 따옴표는 첫 짝까지만 (의도된 축소)" typecheck "say \\"

    # grep -c 는 매치 0건이면 exit 1 이라 파이프라인 뒤에 다른 grep 을 물리면 pipefail
    # 아래서 전체가 실패로 뒤집혀요. 변수로 먼저 받아요.
    ZVC_OLD=$(grep -c 's/\[\[:space:\]\]\*#\.\*\$//' "$SCRIPTS_DIR/zero-verify.sh" || true)
    [ "$ZVC_OLD" = "0" ] \
        && pass "zero-verify — 따옴표를 못 보는 구형 주석 제거 sed 부재" \
        || fail "zero-verify — 구형 s/[[:space:]]*#.*\$// 잔존"

    rm -rf "$ZVC"

    IMF_OUT=$(GOAX_PROJECT_DIR="$ZD" "$OLDBASH" "$ZD/.ax/scripts/bash/init-mistake-file.sh" --category "" --json 2>&1); IMF_RC=$?
    [ "$IMF_RC" -eq 1 ] && echo "$IMF_OUT" | jq -e '.status=="error"' >/dev/null 2>&1 \
        && [ "$(find "$ZD/.ax/mistakes" -type f 2>/dev/null | wc -l | tr -d ' ')" = "0" ] \
        && pass "init-mistake-file — --category '' 는 exit 1 + 파일 미생성 (bad substitution 아님)" \
        || fail "init-mistake-file — 빈 --category 가 exit $IMF_RC: ${IMF_OUT:0:100}"
    rm -rf "$ZD"
fi

smoke_done
