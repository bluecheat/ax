#!/usr/bin/env bash
# tests/smoke/13-rules.sh — §44–§49 — awk clip · 룰 패턴 · eval 미러 · I6 · goax_mktemp · git 훅 경로
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/13-rules.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "44. GOAX_AWK_CLIP — macOS BWK awk 바이트 절단 회귀 (clip 단위 · build-memory.sh 통합 · 자기 점검)"
# ───────────────────────────────────────────────────────────
# macOS 기본 awk(BWK 20200816)는 length/substr 가 바이트 단위라, 한글을 substr(s,1,N) 으로
# 자르면 글자를 반으로 갈라 깨진 UTF-8 을 만들고 뒤이은 정규식이
# `awk: towc: multibyte conversion failure` 로 awk 를 통째로 중단시켜요. 리눅스는 gawk(문자 단위)도
# mawk(바이트 단위지만 towc 검사 없음)도 죽지 않아요. CI 매트릭스에 macOS 가 있는데도 못 잡은 건
# 180바이트를 넘는 한글 룰 픽스처가 smoke 에 없어서예요 — 이 섹션이 그 자리예요. clip() 은
# 공백(낱말) 경계에서만 끊어 이 결함을 피해가요 — 44.1 은 그 계약, 44.2 는 build-memory.sh 가
# 실제로 그 계약을 쓰는지, 44.3 은 렌더가 죽었을 때 자기 점검이 조용히 넘어가지 않는지를 검증해요.
CLIP_SCRIPTS_DIR="$REPO/templates/default/.ax/scripts/bash"
HAVE_PY3=false
command -v python3 >/dev/null 2>&1 && HAVE_PY3=true

# 44.1 clip() 단위 — (a) 상한 이하 (b) 한글 긴 문장 (c) 공백 없는 긴 한글 덩어리
clip_run() {
    ( . "$CLIP_SCRIPTS_DIR/common.sh"
      printf '%s' "$1" | awk -v n="$2" "$GOAX_AWK_CLIP"'{ print clip($0, n) }' )
}

CLIP_A_IN="안녕하세요 상태 확인 중입니다"
CLIP_A_OUT=$(clip_run "$CLIP_A_IN" 180)
[ "$CLIP_A_OUT" = "$CLIP_A_IN" ] \
    && pass "clip() — 상한 이하는 원문 그대로" \
    || fail "clip() — 상한 이하가 변형됨: got='$CLIP_A_OUT'"

# 상한(180)을 **바이트로도 문자로도** 넘겨야 해요. macOS awk 는 length 가 바이트,
# gawk 는 문자라서, 한글 141자(349바이트) 같은 값은 macOS 에서만 잘려요 — 그러면
# 리눅스 CI 에서 "안 잘림" 으로 빨개져요. awk 종류를 감지해 분기하지 않고 픽스처를 키웠어요.
CLIP_B_IN="사용자 노출 카피의 안전선을 어기지 않는다 이가 병기 금지 원전을 앞세운 인용과 원용체 금지 안 보이는 명사인 기운이나 힘이 실려요 같은 표현도 쓰지 않는다 내부 용어인 포커스나 델타 같은 말도 노출 금지 헤드라인은 데이터와 연결된 구체 문장만 허용한다 사용자 노출 카피의 안전선을 어기지 않는다 이가 병기 금지 원전을 앞세운 인용과 원용체 금지 안 보이는 명사인 기운이나 힘이 실려요 같은 표현도 쓰지 않는다 내부 용어인 포커스나 델타 같은 말도 노출 금지 헤드라인은 데이터와 연결된 구체 문장만 허용한다"
CLIP_B_OUT=$(clip_run "$CLIP_B_IN" 180)
[ "$CLIP_B_OUT" != "$CLIP_B_IN" ] \
    && pass "clip() — 상한 초과 한글 문장은 실제로 잘림" \
    || fail "clip() — 상한 초과인데 안 잘림 (cap=180, bytes=$(printf '%s' "$CLIP_B_IN" | wc -c | tr -d ' '))"
case "$CLIP_B_OUT" in
    *' …') pass "clip() — 잘린 결과가 ' …' 로 끝남" ;;
    *) fail "clip() — 잘린 결과가 ' …' 로 안 끝남: '$CLIP_B_OUT'" ;;
esac
if [ "$HAVE_PY3" = true ]; then
    if printf '%s' "$CLIP_B_OUT" | python3 -c "import sys; sys.stdin.buffer.read().decode('utf-8')" 2>/dev/null; then
        pass "clip() — 잘린 결과가 유효한 UTF-8 (글자 안 갈라짐)"
    else
        fail "clip() — 잘린 결과가 깨진 UTF-8"
    fi
else
    pass "clip() UTF-8 유효성 검증 skip (python3 없음)"
fi

CLIP_C_WORD="가나다라마바사아자차카타파하"
CLIP_C_IN=""
# 14자 × 16 = 224자 — gawk(문자)에서도 상한을 넘겨야 "첫 낱말이 상한 초과" 경로를 실제로 타요
for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do CLIP_C_IN="${CLIP_C_IN}${CLIP_C_WORD}"; done
CLIP_C_OUT=$(clip_run "$CLIP_C_IN" 180)
[ "$CLIP_C_OUT" = "$CLIP_C_IN" ] \
    && pass "clip() — 공백 없는 긴 한글 덩어리는 안 자르고 그대로 (깨지는 것보다 긴 게 나음)" \
    || fail "clip() — 공백 없는 덩어리를 건드림: got='$CLIP_C_OUT'"

if ! command -v jq >/dev/null 2>&1; then
    pass "§44.2/44.3 skip (jq 없음)"
else
    # 44.2 build-memory.sh 통합 — 긴 한글 🔴/🟡 룰 → towc 없이 렌더, 목록 수 = 머리말 수
    BM_FX=$(mktemp -d)
    cat > "$BM_FX/AGENTS.md" <<'EOF'
# Test Constitution

🔴 **`TEST:CRIT:001`** 사용자 노출 카피의 안전선을 지킨다 — 이(가) 병기 금지, 원전을 앞세운 인용과 원용체 금지, 안 보이는 명사인 기운이나 힘이 실려요 같은 표현 금지, 내부 용어인 포커스나 델타 노출 금지, 헤드라인은 데이터와 연결된 구체 문장만 허용한다 절대 예외 없다
- enforced_by: external:vitest
- enforced_kind: test

🔴 **`TEST:CRIT:002`** 패키지 의존 방향을 지킨다 — apps 는 ui 와 api 만 참조하고 core 는 React 나 네트워크나 플랫폼 API 를 절대 import 하지 않는다 위반 시 빌드가 자동으로 막히고 리뷰어 승인도 소용이 없다
- enforced_by: external:eslint
- enforced_kind: lint

🟡 **`TEST:MAND:001`** 얼굴 이미지는 리딩 생성 목적의 일시 처리에 한해 외부 API 로 전송할 수 있다 전송 전 얼굴 크롭과 다운스케일과 EXIF 제거가 필수이고 서버나 제3자 저장은 금지되며 사전 승인 없이는 정식 출시를 금지한다
- enforced_by: human:pr-review
EOF
    BM_OUT=$(CLAUDE_PROJECT_DIR="$BM_FX" bash "$CLIP_SCRIPTS_DIR/build-memory.sh" --json --full 2>"$BM_FX/stderr.log")

    if grep -q 'towc' "$BM_FX/stderr.log" 2>/dev/null; then
        fail "build-memory.sh — 긴 한글 룰에서 towc 충돌: $(tr '\n' ' ' < "$BM_FX/stderr.log")"
    else
        pass "build-memory.sh — 긴 한글 🔴/🟡 룰에서 towc 충돌 없음"
    fi

    echo "$BM_OUT" | jq -e '.status == "ok"' >/dev/null 2>&1 \
        && pass "build-memory.sh — 정상 렌더는 status:ok" \
        || fail "build-memory.sh — status 불일치: $BM_OUT"

    BM_MEM="$BM_FX/.ax/MEMORY.md"
    if [ -f "$BM_MEM" ]; then
        BM_DECLARED=$(grep -oE '^## 🔴 CRITICAL 룰 \([0-9]+\)' "$BM_MEM" | grep -oE '[0-9]+')
        BM_LISTED=$(awk '
            /^## 🔴 CRITICAL 룰 \(/ { on=1; next }
            on && /^## / { exit }
            on && /^- / { c++ }
            END { print c+0 }
        ' "$BM_MEM")
        [ "${BM_DECLARED:-0}" -eq 2 ] && [ "${BM_LISTED:-0}" -eq "${BM_DECLARED:-0}" ] \
            && pass "build-memory.sh — 🔴 CRITICAL 룰 (${BM_DECLARED}) 목록 수 일치 (listed=${BM_LISTED})" \
            || fail "build-memory.sh — 🔴 CRITICAL 룰 머리말(${BM_DECLARED:-0})과 목록(${BM_LISTED:-0}) 불일치 — awk 가 죽어 목록만 사라짐"
    else
        fail "build-memory.sh — .ax/MEMORY.md 안 씀"
    fi
    rm -rf "$BM_FX"

    # 44.3 build-memory.sh 자기 점검 — 렌더가 죽으면(목록 0) status:warning + warnings[] 비지 않음.
    # clip() 을 즉시 중단하는 판으로 바꿔치기해 렌더를 일부러 죽여요 (build-memory.sh 원본은 안 건드림).
    #
    # 옛 byte-substr 판을 복원하는 방식은 쓰지 않아요 — gawk 는 substr 가 문자 단위라 안 깨지고, mawk 는
    # 바이트로 깨지되 towc 검사가 없어 안 죽어서, 리눅스에선 프로브가 아무것도 재지 않고 status:ok 가
    # 정상이 돼요 (실제로 CI 를 빨갛게 만들었어요).
    # 자기 점검이 잡아야 할 건 "awk 가 어떻게 죽었나" 가 아니라 "머리말은 N인데 목록이 비었다" 라서,
    # awk 를 확실히 중단시키는 쪽이 어느 구현에서도 같은 상태를 재현해요.
    BM_BROKEN=$(mktemp -d)
    cp "$CLIP_SCRIPTS_DIR/build-memory.sh" "$BM_BROKEN/build-memory.sh"
    chmod +x "$BM_BROKEN/build-memory.sh"
    cat > "$BM_BROKEN/common.sh" <<EOF
#!/usr/bin/env bash
. "$CLIP_SCRIPTS_DIR/common.sh"
GOAX_AWK_CLIP='
function clip(s, n) {
    exit 2
}
'
EOF
    chmod +x "$BM_BROKEN/common.sh"

    BM_NEG_FX=$(mktemp -d)
    cat > "$BM_NEG_FX/AGENTS.md" <<'EOF'
# Test Constitution

🟡 **`TEST:MAND:001`** 얼굴 이미지는 리딩 생성 목적의 일시 처리에 한해 외부 API 로 전송할 수 있다 전송 전 얼굴 크롭과 다운스케일과 EXIF 제거가 필수이고 서버나 제3자 저장은 금지되며 사전 승인 없이는 정식 출시를 금지한다
- enforced_by: human:pr-review
EOF
    BM_NEG_OUT=$(CLAUDE_PROJECT_DIR="$BM_NEG_FX" bash "$BM_BROKEN/build-memory.sh" --json --full 2>/dev/null)

    echo "$BM_NEG_OUT" | jq -e '.status == "warning"' >/dev/null 2>&1 \
        && pass "build-memory.sh 자기 점검 — 렌더가 죽어 목록이 비면 status:warning" \
        || fail "build-memory.sh 자기 점검 — 렌더 실패인데 status 가 warning 이 아님: $BM_NEG_OUT"
    echo "$BM_NEG_OUT" | jq -e '(.warnings | type == "array") and (.warnings | length > 0)' >/dev/null 2>&1 \
        && pass "build-memory.sh 자기 점검 — warnings[] 비지 않음" \
        || fail "build-memory.sh 자기 점검 — warnings[] 비어 있음: $BM_NEG_OUT"

    rm -rf "$BM_BROKEN" "$BM_NEG_FX"
fi

# ───────────────────────────────────────────────────────────
section "45. 룰 패턴 집행 — 마커 파싱 · 훅 차단 · 프로브 · I7 · rules-index"
# 두 룰 템플릿의 `<!-- 검출 패턴: -->` 은 오래 장식이었어요 — 읽는 쪽이 없었어요. 여기는 그 마커가
# (a) common.sh 파서로 읽히고 (b) critical-rule-grep.sh 가 staged 파일을 실제로 막고
# (c) zero-probe.sh 가 ❌/✅ 예시로 패턴을 검증하고 (d) check-rule-enforcement.sh I7 이 빈 약속을 잡는지 봐요.
if command -v jq >/dev/null 2>&1; then
    RP=$(mktemp -d)
    pushd "$RP" >/dev/null || fail "RP pushd 실패"
    git init -q . >/dev/null 2>&1
    mkdir -p .ax/scripts/bash .ax/hooks/pre-commit .ax/spirit/rules .ax/modules/pay src/main src/test
    for sc in common.sh zero-probe.sh check-rule-enforcement.sh check-sensor-liveness.sh rules-index.sh; do
        cp "$REPO/templates/default/.ax/scripts/bash/$sc" .ax/scripts/bash/
    done
    cp "$REPO/templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh" .ax/hooks/pre-commit/
    printf '# C\n' > CLAUDE.md; printf '# A\n' > AGENTS.md; printf 'sensors:\n  mode: fail\n' > .ax/config.yml
    # 디스패처 등록 — I5(미등록) 가 같이 잡히면 아래 --strict 검증이 I7 과 무관하게 exit 1 이라 허위 통과예요
    mkdir -p .claude && printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"bash .ax/hooks/pre-bash/grep-on-commit.sh"}]}]}}\n' > .claude/settings.json

    # (a) 파서 — 헤더 귀속 · 펜스 무시 · 자리표시자 무시 · 다중 마커 · 예시 추출
    cat > .ax/spirit/rules/fx.md <<'EOF'
---
category: fx
severity: critical
paths:
  - "**/*.kt"
enforced_by:
  - hook:.ax/hooks/pre-commit/critical-rule-grep.sh
enforced_kind: grep
---
<!-- 검출 패턴: orphan-before-header -->
## SP-FX-001: 첫 룰 — PII 로그 금지
- 위반 예: `log.info("email=" + email)`, `log.debug("phone: " + phone)`
- 대안: `log.info("userId=" + userId)`
<!-- 검출 패턴: log\.(info|debug|warn)\(.*(email|phone) -->
```
## SP-FX-999: 펜스 안
<!-- 검출 패턴: fenced -->
❌ fenced bad
```
## SP-FX-002: 둘째 룰
❌ import org.junit.jupiter.api.Test
✅ import io.kotest.core.spec.style.DescribeSpec
<!-- 검출 패턴: ^import[[:space:]]+(static[[:space:]]+)?org\.junit\.jupiter\. -->
<!--  검출 패턴:   second   -->
## SP-FX-003: 자리표시자
❌ <나쁜 예>
<!-- 검출 패턴: <regex> -->
## SP-FX-004: 예시 없음
<!-- 검출 패턴: whatever -->
## SP-FX-005: ERE 자리표시자
<!-- 검출 패턴: <ERE> -->
~~~
## SP-FX-998: 물결 펜스 안
<!-- 검출 패턴: tilde-fenced -->
~~~
EOF
    # shellcheck disable=SC1091
    RP_PATS=$(bash -c 'source .ax/scripts/bash/common.sh; goax_rule_patterns .ax/spirit/rules/fx.md')
    [ "$(printf '%s\n' "$RP_PATS" | grep -c .)" -eq 4 ] && ! printf '%s\n' "$RP_PATS" | grep -q 'SP-FX-005\|SP-FX-998' \
        && pass "goax_rule_patterns — 마커 4개 (헤더 앞 orphan · \`\`\`/~~~ 펜스 안 · <regex>/<ERE> 자리표시자는 제외)" \
        || fail "goax_rule_patterns — 기대 4행(FX-005·FX-998 제외), 실제: $RP_PATS"
    RP_OPS=$(bash -c 'source .ax/scripts/bash/common.sh; goax_rule_patterns "$0"' "$REPO/templates/default/.ax/_templates/spirit/ops.md")
    [ -z "$RP_OPS" ] \
        && pass "goax_rule_patterns — 출고 ops.md 는 패턴 0건 (SP-OPS-001 의 산문 주석이 마커로 안 읽힘)" \
        || fail "goax_rule_patterns — 출고 ops.md 에서 패턴을 읽음 (산문이 정규식으로 집행됨): $RP_OPS"
    printf '%s\n' "$RP_PATS" | grep -q $'^SP-FX-002\tsecond$' \
        && pass "goax_rule_patterns — 다중 마커 + 앞뒤 공백 trim" \
        || fail "goax_rule_patterns — 둘째 마커 trim 실패: $RP_PATS"
    RP_EX=$(bash -c 'source .ax/scripts/bash/common.sh; goax_rule_examples .ax/spirit/rules/fx.md')
    [ "$(printf '%s\n' "$RP_EX" | grep -c $'^SP-FX-001\tbad\t')" -eq 2 ] \
        && [ "$(printf '%s\n' "$RP_EX" | grep -c $'^SP-FX-002\tgood\t')" -eq 1 ] \
        && ! printf '%s\n' "$RP_EX" | grep -q 'SP-FX-003' \
        && pass "goax_rule_examples — 백틱 span 별 bad 2 · ✅ good 1 · <나쁜 예> 자리표시자 제외" \
        || fail "goax_rule_examples — 예시 추출 불일치: $RP_EX"
    RP_GF=$(printf 'a/b.kt\nc.ts\nx.kt\n' | bash -c 'source .ax/scripts/bash/common.sh; goax_glob_filter "**/*.kt"' | tr '\n' ' ')
    [ "$RP_GF" = "a/b.kt x.kt " ] \
        && pass "goax_glob_filter — stdin 경로 목록을 글롭으로 거름 (python 1회)" \
        || fail "goax_glob_filter — 기대 'a/b.kt x.kt ', 실제 '$RP_GF'"

    # (b) 훅 — AC1 critical 차단 · AC2 paths 불일치 통과 · AC3 mandatory 경고만 · AC6 룰 파일 자신 · AC5 출고 템플릿
    cat > .ax/modules/pay/rules.md <<'EOF'
---
module: pay
severity: mandatory
paths:
  - "src/main/**"
---
## SP-PAY-001: Double 금지
❌ val amount: Double = 1.0
<!-- 검출 패턴: :[[:space:]]*Double -->
EOF
    printf 'import org.junit.jupiter.api.Test\nclass FooTest\n' > src/test/FooTest.kt
    printf 'import org.junit.jupiter.api.Test\n' > src/test/Not.ts
    printf 'val amount: Double = 1.0\n' > src/main/Pay.kt
    printf 'class A\nimport org.junit.jupiter.api.Test\n' > 'src/test/한글:이름.kt'
    rp_hook() { git reset -q >/dev/null 2>&1; git add "$@" >/dev/null 2>&1; CLAUDE_PROJECT_DIR="$RP" bash .ax/hooks/pre-commit/critical-rule-grep.sh 2>&1 >/dev/null; }
    RP_OUT=$(rp_hook src/test/FooTest.kt); RP_RC=$?
    [ "$RP_RC" -eq 2 ] && printf '%s' "$RP_OUT" | grep -q 'src/test/FooTest.kt:1 — SP-FX-002' \
        && pass "critical-rule-grep — critical 패턴 위반 .kt stage → exit 2 + file:line + 토큰" \
        || fail "critical-rule-grep — 기대 exit 2 + 'FooTest.kt:1 — SP-FX-002', 실제 rc=$RP_RC: $RP_OUT"
    printf '%s' "$RP_OUT" | grep -q 'org.junit.jupiter' \
        && fail "critical-rule-grep — 매칭 줄 본문을 그대로 출력 (내용이 로그로 새요)" \
        || pass "critical-rule-grep — file:line 만 보고, 매칭 줄 본문은 안 찍음"
    RP_OUT=$(rp_hook 'src/test/한글:이름.kt'); RP_RC=$?
    [ "$RP_RC" -eq 2 ] && printf '%s' "$RP_OUT" | grep -q 'src/test/한글:이름.kt:2 — SP-FX-002' \
        && pass "critical-rule-grep — 비ASCII·콜론 파일명도 검사 (quotePath=false) 하고 file:line 이 안 깨짐" \
        || fail "critical-rule-grep — 한글/콜론 파일명 rc=$RP_RC: $RP_OUT"
    RP_OUT=$(rp_hook src/test/Not.ts); RP_RC=$?
    [ "$RP_RC" -eq 0 ] && ! printf '%s' "$RP_OUT" | grep -q 'SP-FX-002' \
        && pass "critical-rule-grep — paths 에 안 맞는 .ts 는 패턴에 걸려도 통과" \
        || fail "critical-rule-grep — paths 밖 파일을 검사함 rc=$RP_RC: $RP_OUT"
    RP_OUT=$(rp_hook src/main/Pay.kt); RP_RC=$?
    [ "$RP_RC" -eq 0 ] && printf '%s' "$RP_OUT" | grep -q 'SP-PAY-001' && printf '%s' "$RP_OUT" | grep -q '차단 안 함' \
        && pass "critical-rule-grep — mandatory 파일의 패턴은 mode=fail 이어도 경고만 (exit 0)" \
        || fail "critical-rule-grep — mandatory 가 차단하거나 경고가 없음 rc=$RP_RC: $RP_OUT"
    RP_OUT=$(rp_hook .ax/spirit/rules/fx.md .ax/modules/pay/rules.md); RP_RC=$?
    [ "$RP_RC" -eq 0 ] && ! printf '%s' "$RP_OUT" | grep -q 'SP-FX-\|SP-PAY-' \
        && pass "critical-rule-grep — 룰 파일 자신(❌ 예시 포함)을 stage 해도 .ax/ 제외로 위반 0" \
        || fail "critical-rule-grep — 룰 파일의 예시가 자기 패턴에 걸림 rc=$RP_RC: $RP_OUT"
    cat > .ax/spirit/rules/broken.md <<'EOF'
---
category: broken
severity: convention
paths: ["**/*.kt"]
---
## SP-BRK-001: 깨진 정규식
<!-- 검출 패턴: ([unclosed -->
EOF
    RP_OUT=$(rp_hook src/test/FooTest.kt); RP_RC=$?
    [ "$RP_RC" -eq 2 ] && printf '%s' "$RP_OUT" | grep -q 'SP-BRK-001 — 검출 패턴 문법 오류' \
        && pass "critical-rule-grep — 깨진 ERE 는 경고 후 그 패턴만 생략, 다른 critical 은 여전히 차단" \
        || fail "critical-rule-grep — 깨진 패턴 처리 rc=$RP_RC: $RP_OUT"
    rm .ax/spirit/rules/broken.md

    # (c) 프로브 — ok/skip · ❌ 미검출 fail · ✅ 오탐 fail
    RP_PR=$(bash .ax/scripts/bash/zero-probe.sh --json 2>/dev/null); RP_RC=$?
    [ "$RP_RC" -eq 0 ] && echo "$RP_PR" | jq -e '.result.probes[] | select(.name=="pattern-rules") | .ok == true' >/dev/null 2>&1 \
        && echo "$RP_PR" | jq -e '[.result.probes[] | select(.name=="pattern-rules") | .tail_lines[] | select(startswith("ok   SP-FX-001") or startswith("ok   SP-FX-002") or startswith("ok   SP-PAY-001"))] | length == 3' >/dev/null 2>&1 \
        && pass "zero-probe pattern-rules — ❌ 걸리고 ✅ 안 걸리는 룰 3개 ok — 마커 2개(SP-FX-002)는 OR (프로브 파일 없이 내장 실행)" \
        || fail "zero-probe pattern-rules — 정상 케이스 판정 실패 rc=$RP_RC: $RP_PR"
    echo "$RP_PR" | jq -e '[.result.probes[] | select(.name=="pattern-rules") | .tail_lines[] | select(startswith("skip SP-FX-004"))] | length == 1' >/dev/null 2>&1 \
        && pass "zero-probe pattern-rules — ❌/✅ 없는 룰(SP-FX-004)은 skip 으로 보고, ok 로 안 셈" \
        || fail "zero-probe pattern-rules — 예시 없는 룰이 skip 이 아님: $RP_PR"
    sed -i.bak 's/(email|phone) -->/(nomatch) -->/' .ax/spirit/rules/fx.md && rm -f .ax/spirit/rules/fx.md.bak
    RP_PR=$(bash .ax/scripts/bash/zero-probe.sh --json 2>/dev/null); RP_RC=$?
    [ "$RP_RC" -eq 1 ] && echo "$RP_PR" | jq -e '.result.failed == 1' >/dev/null 2>&1 \
        && echo "$RP_PR" | jq -e '[.result.probes[] | select(.name=="pattern-rules") | .tail_lines[] | select(startswith("FAIL SP-FX-001") and contains("❌ 예시가 패턴에 안 걸려요"))] | length >= 1' >/dev/null 2>&1 \
        && pass "zero-probe pattern-rules — ❌ 예시를 못 잡는 패턴은 FAIL + exit 1" \
        || fail "zero-probe pattern-rules — ❌ 미검출을 통과시킴 rc=$RP_RC: $RP_PR"
    sed -i.bak 's/log\\.(info|debug|warn)\\(.\*(nomatch) -->/log\\.info -->/' .ax/spirit/rules/fx.md && rm -f .ax/spirit/rules/fx.md.bak
    RP_PR=$(bash .ax/scripts/bash/zero-probe.sh --json 2>/dev/null); RP_RC=$?
    [ "$RP_RC" -eq 1 ] && echo "$RP_PR" | jq -e '[.result.probes[] | select(.name=="pattern-rules") | .tail_lines[] | select(startswith("FAIL SP-FX-001") and contains("오탐"))] | length == 1' >/dev/null 2>&1 \
        && pass "zero-probe pattern-rules — ✅ 예시까지 잡는 패턴은 오탐 FAIL" \
        || fail "zero-probe pattern-rules — 오탐을 통과시킴 rc=$RP_RC: $RP_PR"
    sed -i.bak 's/<!-- 검출 패턴: log\\.info -->/<!-- 검출 패턴: log\\.(info|debug|warn)\\(.*(email|phone) -->/' .ax/spirit/rules/fx.md && rm -f .ax/spirit/rules/fx.md.bak

    # (d) I7 — grep-kind 인데 패턴 없음 · 패턴 있는데 paths 없음 · --strict exit 1
    cat > .ax/spirit/rules/nopaths.md <<'EOF'
---
category: nopaths
severity: mandatory
enforced_by:
  - human:pr-review
---
## SP-NP-001: 패턴은 있는데 paths 없음
<!-- 검출 패턴: baz -->
EOF
    RP_RE=$(bash .ax/scripts/bash/check-rule-enforcement.sh --json 2>/dev/null)
    echo "$RP_RE" | jq -e '[.result.i7_grep_without_pattern[] | .rule_id] == ["SP-FX-003","SP-FX-005"]' >/dev/null 2>&1 \
        && pass "check-rule-enforcement I7 — grep-kind 파일의 마커 없는 룰(SP-FX-003) + <ERE> 자리표시자 룰(SP-FX-005) 이 i7_grep_without_pattern" \
        || fail "check-rule-enforcement I7 — no_pattern 판정 불일치: $(echo "$RP_RE" | jq -c '.result.i7_grep_without_pattern')"
    echo "$RP_RE" | jq -e '[.result.i7_pattern_without_paths[] | .rule_id] == ["SP-NP-001"]' >/dev/null 2>&1 \
        && pass "check-rule-enforcement I7 — 패턴 있는데 paths 빈 룰(SP-NP-001)만 i7_pattern_without_paths" \
        || fail "check-rule-enforcement I7 — no_paths 판정 불일치: $(echo "$RP_RE" | jq -c '.result.i7_pattern_without_paths')"
    bash .ax/scripts/bash/check-rule-enforcement.sh --strict >/dev/null 2>&1; RP_RC=$?
    [ "$RP_RC" -eq 1 ] && echo "$RP_RE" | jq -e '(.result.i5_not_registered | length) == 0 and (.next_step | test("^3 violations"))' >/dev/null 2>&1 \
        && pass "check-rule-enforcement I7 — 다른 위반 0 인 상태에서 I7 3건만으로 --strict exit 1 (CI 게이트)" \
        || fail "check-rule-enforcement I7 — --strict rc=$RP_RC, next_step=$(echo "$RP_RE" | jq -r .next_step), i5=$(echo "$RP_RE" | jq -c .result.i5_not_registered)"

    # (e) liveness C1 · rules-index pattern 필드
    RP_LV=$(bash .ax/scripts/bash/check-sensor-liveness.sh --json 2>/dev/null)
    echo "$RP_LV" | jq -e '.result.pattern_rules == 5 and .result.grep_scaffold_unfilled == false' >/dev/null 2>&1 \
        && pass "check-sensor-liveness — 패턴 룰이 있으면 C1(스캐폴드 미작성)은 finding 이 아니고 pattern_rules 를 셈" \
        || fail "check-sensor-liveness — pattern_rules/C1 불일치: $(echo "$RP_LV" | jq -c '.result | {pattern_rules, grep_scaffold_unfilled}')"
    RP_RI=$(bash .ax/scripts/bash/rules-index.sh --json 2>/dev/null)
    echo "$RP_RI" | jq -e '([.result.rules[] | select(.pattern == true) | .token] | sort) == ["SP-FX-001","SP-FX-002","SP-FX-004","SP-NP-001","SP-PAY-001"]' >/dev/null 2>&1 \
        && pass "rules-index — 마커 있는 룰만 pattern:true" \
        || fail "rules-index — pattern 필드 불일치: $(echo "$RP_RI" | jq -c '[.result.rules[] | {token, pattern}]')"

    popd >/dev/null || true
    rm -rf "$RP"
else
    pass "§45 — jq 없음, skip"
fi

# ───────────────────────────────────────────────────────────
section "46. eval hook 미러 — tests/eval-hook-shim/hooks/hooks.json ↔ settings.json.template"
# ───────────────────────────────────────────────────────────
# `claude plugin eval` 샌드박스는 프로젝트 .claude/settings.json 을 읽지 않아요 (실측 — 던지기 config 에
# cwd 의 trust 기록이 없음). 그래서 goax 가 등록하는 hook 을 플러그인 hook 으로 미러한 shim 을
# scaffold 케이스가 같이 로드해요 (tests/eval-hook-shim/README.md). 미러가 템플릿과 어긋나면 eval 은
# "설치되는 hook" 이 아니라 "옛 hook" 을 재고, shim 을 plugins: 에 빠뜨리면 hook 없이 돌아 Δ 가 조용히 0 이 돼요.
SHIM="$REPO/tests/eval-hook-shim/hooks/hooks.json"
SHIM_TPL="$REPO/templates/default/.claude/settings.json.template"
if command -v jq >/dev/null 2>&1; then
    if [ -f "$SHIM" ] && jq -e . "$SHIM" >/dev/null 2>&1; then
        if [ "$(jq -S .hooks "$SHIM")" = "$(jq -S .hooks "$SHIM_TPL")" ]; then
            pass "eval-hook-shim hooks.json .hooks == settings.json.template .hooks"
        else
            fail "eval-hook-shim hooks.json 이 템플릿과 달라요 — jq '{hooks: .hooks}' templates/default/.claude/settings.json.template > tests/eval-hook-shim/hooks/hooks.json"
        fi
    else
        fail "tests/eval-hook-shim/hooks/hooks.json 없음 또는 JSON 아님"
    fi
    SHIM_MISS=0
    for sc in "$REPO"/evals/*/scaffold.sh; do
        [ -f "$sc" ] || continue
        grep -q 'provision\.sh' "$sc" || continue          # .ax/ 를 설치하는 scaffold 만 대상
        cy="$(dirname "$sc")/case.yaml"
        if ! grep -q 'tests/eval-hook-shim' "$cy" 2>/dev/null; then
            fail "$(basename "$(dirname "$sc")")/case.yaml — provision.sh 로 .ax/ 를 깔면서 plugins: 에 eval-hook-shim 이 없어요"
            SHIM_MISS=1
        fi
    done
    [ "$SHIM_MISS" -eq 0 ] && pass "provision.sh 를 쓰는 scaffold 케이스는 전부 plugins: 에 eval-hook-shim 포함"
else
    pass "§46 — jq 없음, skip"
fi

# ───────────────────────────────────────────────────────────
section "47. I6 출고 훅 제외 목록 ↔ templates/default/.ax/hooks/pre-commit/ — 갓 설치에서 external 룰이 '트리거 있음' 으로 새면 안 돼요"
# ───────────────────────────────────────────────────────────
# check-rule-enforcement.sh I6 는 goax wrapper 를 트리거로 안 치고, 출고 훅 *이외의* pre-commit 훅이 있을 때만
# 트리거로 인정해요. 그 "출고 훅" 목록이 리터럴이라 새 훅(spec-completion-gate.sh)이 출고되면서 목록에서 빠졌고,
# 그동안 갓 설치한 모든 프로젝트에서 I6 가 영원히 통과했어요 (evals/doctor-i6 스캐폴드가 잡음). 여기서 둘을 대조하고,
# 실제 트리로 "출고 훅만 = I6 발화 / 프로젝트 훅 추가 = 해제" 를 고정해요.
CRE="$REPO/templates/default/.ax/scripts/bash/check-rule-enforcement.sh"
I6_LIST=$(grep -oE '^[[:space:]]*[a-z-]+\.sh(\|[a-z-]+\.sh)*\) ;;' "$CRE" | head -1 | tr -d ' )' | sed 's/;;$//' | tr '|' '\n' | sort)
SHIPPED=$(ls "$REPO/templates/default/.ax/hooks/pre-commit/"*.sh | xargs -n1 basename | sort)
if [ -n "$I6_LIST" ] && [ "$I6_LIST" = "$SHIPPED" ]; then
    pass "I6 출고 훅 제외 목록 == pre-commit/ 출고 파일 ($(printf '%s' "$SHIPPED" | tr '\n' ' '))"
else
    fail "I6 제외 목록이 출고 훅과 달라요 — 목록: [$(printf '%s' "$I6_LIST" | tr '\n' ' ')] 출고: [$(printf '%s' "$SHIPPED" | tr '\n' ' ')]"
fi
if command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    I6T=$(mktemp -d)
    mkdir -p "$I6T/.ax/scripts/bash" "$I6T/.ax/hooks/pre-commit" "$I6T/.claude"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,check-rule-enforcement}.sh "$I6T/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-commit/"*.sh "$I6T/.ax/hooks/pre-commit/"
    git -C "$I6T" init -q
    printf '#!/usr/bin/env bash\n#goax-pre-commit-chain\nexit 0\n' > "$I6T/.git/hooks/pre-commit"; chmod +x "$I6T/.git/hooks/pre-commit"
    printf '# X\n\n## CRITICAL\n\n🔴 **`EVL:CRITICAL:001`** 카피 안전선\n- enforced_by: external:vitest\n- enforced_kind: test\n' > "$I6T/AGENTS.md"
    I6R=$(GOAX_PROJECT_DIR="$I6T" bash "$I6T/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null)
    echo "$I6R" | jq -e '(.result.i6_no_trigger|length)==1 and .result.i6_no_trigger[0].rule_id=="EVL:CRITICAL:001"' >/dev/null 2>&1 \
        && pass "I6 — wrapper + 출고 훅만 있는 갓 설치에서 external:vitest 가 no_trigger 로 잡힘" \
        || fail "I6 — 갓 설치에서 external 룰이 안 잡혀요: $(echo "$I6R" | jq -c '{i6: .result.i6_no_trigger, surfaces: .result.trigger_surfaces}')"
    printf '#!/usr/bin/env bash\nnpx vitest run\n' > "$I6T/.ax/hooks/pre-commit/run-vitest.sh"; chmod +x "$I6T/.ax/hooks/pre-commit/run-vitest.sh"
    I6R=$(GOAX_PROJECT_DIR="$I6T" bash "$I6T/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null)
    echo "$I6R" | jq -e '(.result.i6_no_trigger|length)==0' >/dev/null 2>&1 \
        && pass "I6 — 프로젝트 전용 pre-commit 훅을 추가하면 트리거로 인정돼 해제" \
        || fail "I6 — 프로젝트 훅 추가 후에도 no_trigger: $(echo "$I6R" | jq -c '.result.i6_no_trigger')"
    rm -rf "$I6T"
else
    pass "§47 실행 검사 — jq/git 없음, skip"
fi

# ───────────────────────────────────────────────────────────
section "48. goax_mktemp — 임시 파일 실패가 초록불이 되면 안 돼요 (샌드박스 \$TMPDIR 쓰기 금지 실측)"
# ───────────────────────────────────────────────────────────
# claude plugin eval 샌드박스에서 `mktemp` 가 죽자 check-rule-enforcement.sh 가 빈 경로로 계속 가 룰 0건 검사 →
# "all invariants pass" 를 찍었어요. 이제 스크립트는 goax_mktemp 만 쓰고, 그건 .ax/.session/tmp 로 폴백하거나
# error 로 끝나요. macOS mktemp 는 TMPDIR 이 뭐든 Darwin temp 로 떨어져서 밖에선 못 죽이니 가짜 mktemp 로 흉내내요.
BARE_MKTEMP=$(grep -lE '^[^#]*(\$\([[:space:]]*mktemp|`[[:space:]]*mktemp)' "$REPO/templates/default/.ax/scripts/bash/"*.sh "$REPO/templates/default/.ax/hooks/"*/*.sh "$REPO/scripts/"*.sh 2>/dev/null | grep -v '/common\.sh$' || true)
if [ -z "$BARE_MKTEMP" ]; then
    pass "출고 스크립트·훅·provision.sh 에 맨 \$(mktemp) 없음 — 전부 goax_mktemp (provision 은 mktemp 가 죽으면 백업이 / 에 떨어지고 MANIFEST 복사가 사용자 템플릿을 덮어썼어요)"
else
    fail "맨 \$(mktemp) 사용 — goax_mktemp \"\$ROOT\" || { goax_error …; exit } 로: $(echo "$BARE_MKTEMP" | xargs -n1 basename | tr '\n' ' ')"
fi
if command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    MT=$(mktemp -d)
    trap 'chmod -R u+w "$MT" 2>/dev/null; rm -rf "$MT"' EXIT   # chmod a-w 뒤 중단돼도 /tmp 에 못 지우는 트리를 안 남겨요
    mkdir -p "$MT/.ax/scripts/bash" "$MT/fakebin"
    printf '#!/bin/sh\nexit 1\n' > "$MT/fakebin/mktemp"; chmod +x "$MT/fakebin/mktemp"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,check-rule-enforcement}.sh "$MT/.ax/scripts/bash/"
    git -C "$MT" init -q
    printf '# X\n\n## CRITICAL\n\n🔴 **`EVL:CRITICAL:001`** 카피\n- enforced_by: external:vitest\n- enforced_kind: test\n' > "$MT/AGENTS.md"
    MTR=$(GOAX_PROJECT_DIR="$MT" PATH="$MT/fakebin:$PATH" bash "$MT/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null)
    if echo "$MTR" | jq -e '.result.rule_count == 1' >/dev/null 2>&1 && [ -d "$MT/.ax/.session/tmp" ]; then
        pass "mktemp 실패 → .ax/.session/tmp 폴백, 룰 1건 그대로 검사"
    else
        fail "mktemp 실패 폴백이 안 돼요: $(echo "$MTR" | jq -c '{status, rule_count: .result.rule_count}' 2>/dev/null)"
    fi
    if [ "$(id -u)" -ne 0 ]; then   # root 는 chmod a-w 를 무시해서 이 단정이 조용히 뒤집혀요
        rm -rf "$MT/.ax/.session"; chmod a-w "$MT/.ax"
        MTR=$(GOAX_PROJECT_DIR="$MT" PATH="$MT/fakebin:$PATH" bash "$MT/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null); MTRC=$?
        chmod u+w "$MT/.ax"
        if [ "$MTRC" -eq 1 ] && echo "$MTR" | jq -e '.status == "error"' >/dev/null 2>&1; then
            pass "mktemp 실패 + 폴백 불가 → status error · exit 1 (초록불 아님)"
        else
            fail "임시 파일을 못 만드는데 통과를 찍어요: rc=$MTRC $(echo "$MTR" | jq -c '{status, rule_count: .result.rule_count}' 2>/dev/null)"
        fi
    else
        pass "§48 폴백 불가 단정 — root 라 skip"
    fi
    rm -rf "$MT"; trap - EXIT
else
    pass "§48 실행 검사 — jq/git 없음, skip"
fi

# ───────────────────────────────────────────────────────────
section "49. goax_git_hook_path — git 이 못 돌아도 pre-commit 훅을 봐야 해요 (샌드박스 xcrun 셔틀 실측)"
# ───────────────────────────────────────────────────────────
# 샌드박스에서 `/usr/bin/git rev-parse --git-path` 가 죽자 check-sensor-liveness C2 가 "pre-commit 미설치" 오탐,
# check-rule-enforcement I6 가 프로젝트 훅을 못 봤어요. 헬퍼는 git 이 실패하면 .git(디렉토리·gitdir 포인터)과
# .git/config 의 core.hooksPath 를 직접 읽어요.
BARE_GITPATH=$(grep -l '^[^#]*rev-parse --git-path' "$REPO/templates/default/.ax/scripts/bash/"*.sh 2>/dev/null | grep -v '/common\.sh$' || true)
if [ -z "$BARE_GITPATH" ]; then
    pass "출고 스크립트에 맨 rev-parse --git-path 없음 — 전부 goax_git_hook_path"
else
    fail "맨 rev-parse --git-path 사용 — goax_git_hook_path 로: $(echo "$BARE_GITPATH" | xargs -n1 basename | tr '\n' ' ')"
fi
if command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
    GT=$(cd "$(mktemp -d)" && pwd -P)   # realpath — git 이 worktree 포인터에 realpath 를 써요 (macOS /var → /private/var)
    mkdir -p "$GT/.ax/scripts/bash" "$GT/fakebin"
    printf '#!/bin/sh\nexit 128\n' > "$GT/fakebin/git"; chmod +x "$GT/fakebin/git"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,check-sensor-liveness}.sh "$GT/.ax/scripts/bash/"
    git -C "$GT" init -q
    printf '#!/usr/bin/env bash\nexit 0\n' > "$GT/.git/hooks/pre-commit"; chmod +x "$GT/.git/hooks/pre-commit"
    GTR=$(GOAX_PROJECT_DIR="$GT" PATH="$GT/fakebin:$PATH" bash "$GT/.ax/scripts/bash/check-sensor-liveness.sh" --json 2>/dev/null)
    echo "$GTR" | jq -e '.result.git_precommit_installed == true' >/dev/null 2>&1 \
        && pass "git 죽음 + .git/hooks/pre-commit 있음 → C2 설치됨 (오탐 없음)" \
        || fail "git 이 죽으면 C2 가 미설치로 오탐: $(echo "$GTR" | jq -c '.result.git_precommit_installed' 2>/dev/null)"
    # core.hooksPath (husky v9) — 파일로 해석. 상대경로는 워킹트리 기준
    printf '\thooksPath = .husky/_\n' >> "$GT/.git/config"
    HP=$(bash -c "source '$GT/.ax/scripts/bash/common.sh'; PATH='$GT/fakebin:$PATH' goax_git_hook_path '$GT' pre-commit")
    [ "$HP" = "$GT/.husky/_/pre-commit" ] \
        && pass "git 죽음 + core.hooksPath → 파일로 해석 ($HP)" \
        || fail "core.hooksPath 폴백이 틀려요: $HP"
    # 따옴표·주석 — git 은 둘 다 벗겨요
    sed -i.bak 's|hooksPath = .husky/_|hooksPath = "my hooks" ; why|' "$GT/.git/config"; rm -f "$GT/.git/config.bak"
    HP=$(bash -c "source '$GT/.ax/scripts/bash/common.sh'; PATH='$GT/fakebin:$PATH' goax_git_hook_path '$GT' pre-commit")
    [ "$HP" = "$GT/my hooks/pre-commit" ] \
        && pass "git 죽음 + hooksPath 큰따옴표·주석 → 벗겨서 해석" \
        || fail "hooksPath 의 따옴표·주석을 못 벗겨요: $HP"
    sed -i.bak 's|hooksPath = "my hooks" ; why|hooksPath = .husky/_|' "$GT/.git/config"; rm -f "$GT/.git/config.bak"
    # 실제 linked worktree — gitdir 은 .git/worktrees/<name>, config·hooks 는 commondir 너머 공용 .git 에
    git -C "$GT" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git -C "$GT" worktree add -q "$GT/wt2" -b wt2 2>/dev/null
    HP=$(bash -c "source '$GT/.ax/scripts/bash/common.sh'; PATH='$GT/fakebin:$PATH' goax_git_hook_path '$GT/wt2' pre-commit")
    [ "$HP" = "$GT/wt2/.husky/_/pre-commit" ] \
        && pass "git 죽음 + linked worktree → commondir 따라 공용 config 의 hooksPath 해석" \
        || fail "linked worktree 폴백이 틀려요 (기대 $GT/wt2/.husky/_/pre-commit): $HP"
    sed -i.bak '/hooksPath/d' "$GT/.git/config"; rm -f "$GT/.git/config.bak"
    HP=$(bash -c "source '$GT/.ax/scripts/bash/common.sh'; PATH='$GT/fakebin:$PATH' goax_git_hook_path '$GT/wt2' pre-commit")
    [ "$HP" = "$GT/.git/hooks/pre-commit" ] \
        && pass "git 죽음 + linked worktree, hooksPath 없음 → 공용 .git/hooks" \
        || fail "linked worktree 의 공용 hooks 경로가 틀려요 (기대 $GT/.git/hooks/pre-commit): $HP"
    rm -rf "$GT"
else
    pass "§49 실행 검사 — jq/git 없음, skip"
fi

smoke_done
