#!/usr/bin/env bash
# tests/smoke/10-installer.sh — §41 — 설치기 · 훅 안전망
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/10-installer.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "41. 설치기 · 훅 안전망 — 심링크 · 시크릿 · 상위 경로 · jq 부재 · 인계 기한 · 이벤트 키"
# ───────────────────────────────────────────────────────────
# §15/§41 분담: 여기는 상위 경로(..) 계열 경고 5종 + 일상 rm 4종(무음) + jq 부재 담당이에요.
# git/원격/sudo 계열 경고 7종 + CATASTROPHIC 16종 + 무해 9종(무음)은 §15 담당 — 섞지 마세요.
# 안전망이 *조용히* 꺼진 상태가 제일 나빠요 — 아무도 모르니까요. 여기 6개는 전부
# "무경고로 통과했다" 가 회귀 내용이에요 (프로젝트 밖 쓰기 · 시크릿 9종 미탐 ·
# `rm -rf ../..` 무음 · jq 없으면 무음 · 영구 유효한 인계 노트 · 이벤트 키 무시).
if ! command -v jq >/dev/null 2>&1; then
    pass "§41 skip (jq 없음)"
else
    # C1 — .ax/hooks 가 프로젝트 밖 심링크면 밖으로 쓰지 않고 경고해요
    SYM_P=$(mktemp -d); SYM_OUT=$(mktemp -d)
    mkdir -p "$SYM_P/.ax"; ln -s "$SYM_OUT" "$SYM_P/.ax/hooks"
    SYM_R=$(bash "$REPO/scripts/provision.sh" --target "$SYM_P" --json 2>/dev/null)
    echo "$SYM_R" | jq -e '.status=="warning" and (.warnings|length)>0' >/dev/null 2>&1 \
        && [ "$(find "$SYM_OUT" -type f 2>/dev/null | wc -l | tr -d ' ')" = "0" ] && [ -L "$SYM_P/.ax/hooks" ] \
        && pass "provision — .ax/hooks 심링크: 밖에 파일 0 + warning + 링크 원형 보존" \
        || fail "provision — 심링크 너머로 씀: $(find "$SYM_OUT" -type f 2>/dev/null | wc -l | tr -d ' ')개"
    rm -rf "$SYM_P" "$SYM_OUT"

    # C3/C4 — 상위 경로 rm 과 jq 부재
    HK=$(mktemp -d)
    mkdir -p "$HK/.ax/scripts/bash" "$HK/.ax/hooks/pre-bash" "$HK/.ax/hooks/pre-edit"
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$HK/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-bash/block-destructive.sh" "$HK/.ax/hooks/pre-bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-edit/check-protected-paths.sh" "$HK/.ax/hooks/pre-edit/"
    bd_err() { printf '{"tool_input":{"command":"%s"}}' "$1" \
        | CLAUDE_PROJECT_DIR="$HK" bash "$HK/.ax/hooks/pre-bash/block-destructive.sh" 2>&1 >/dev/null; }
    # warning 모드라 exit 0 이에요 — stderr 유무로 판정해요
    parent_missed=0
    for pc in 'rm -rf ..' 'rm -rf ../*' 'rm -rf ../..' 'rm -rf ../../etc' 'rm -rf ../../../'; do
        [ -n "$(bd_err "$pc")" ] || { fail "block-destructive — '$pc' 무음 (더 위험한 쪽이 통과)"; parent_missed=$((parent_missed+1)); }
    done
    [ "$parent_missed" -eq 0 ] && pass "block-destructive — 상위 경로 rm 5종 전부 경고 (../.. 포함)" || true
    parent_fp=0
    for pc in 'rm -rf ./dist' 'rm -rf node_modules' 'rm -rf /tmp/build-cache' 'rm -rf build && cd ..'; do
        [ -z "$(bd_err "$pc")" ] || { fail "block-destructive — 일상 명령 '$pc' 오탐"; parent_fp=$((parent_fp+1)); }
    done
    [ "$parent_fp" -eq 0 ] && pass "block-destructive — 일상 rm 4종은 그대로 통과 (오탐 0 · 뒤 세그먼트의 cd .. 포함)" || true

    # PATH 에 `cat` 만 남겨요 — 훅은 stdin 을 읽어야 "jq 가 없다" 갈래에 도달해요.
    # bash·훅은 절대경로로 부르니 PATH 가 비어도 돌아요.
    NOJQ=$(mktemp -d); ln -s "$(command -v cat)" "$NOJQ/cat"
    JQ_E1=$(printf '{"tool_input":{"command":"rm -rf /etc"}}' \
        | PATH="$NOJQ" CLAUDE_PROJECT_DIR="$HK" "$BASH" "$HK/.ax/hooks/pre-bash/block-destructive.sh" 2>&1 >/dev/null)
    JQ_E2=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"'"$HK"'/.ax/config.yml"}}' \
        | PATH="$NOJQ" CLAUDE_PROJECT_DIR="$HK" "$BASH" "$HK/.ax/hooks/pre-edit/check-protected-paths.sh" 2>&1 >/dev/null)
    case "$JQ_E1$JQ_E2" in
        *"jq 없음"*"jq 없음"*) pass "훅 — jq 없는 PATH 에서 침묵하지 않고 '안전망 비활성' 을 알림 (fail-open 유지)" ;;
        *) fail "훅 — jq 부재를 조용히 통과: [$JQ_E1][$JQ_E2]" ;;
    esac
    rm -rf "$NOJQ" "$HK"

    # C5/C6 — 인계 노트 24시간 · 훅을 다른 이벤트로 옮기면 missing
    ST=$(mktemp -d)
    mkdir -p "$ST/.ax/scripts/bash" "$ST/.ax/hooks/stop" "$ST/.ax/docs/spec/014-x" "$ST/.claude"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,tasks-gate,tier-from-state,status-note,doctor-scan}.sh "$ST/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/stop/spec-gate.sh" "$ST/.ax/hooks/stop/"
    printf '# S\n## 3.\n- [ ] **AC1** a\n' > "$ST/.ax/docs/spec/014-x/spec.md"
    printf -- '- [ ] T001 [AC1] a — files: a.kt\n' > "$ST/.ax/docs/spec/014-x/tasks.md"
    echo '{"phase":"implementing","spec_dir":".ax/docs/spec/014-x","size":"M","risk":"L1"}' > "$ST/.ax/current-task.json"
    echo '{"hooks":{}}' > "$ST/.claude/settings.json"
    CLAUDE_PROJECT_DIR="$ST" bash "$ST/.ax/scripts/bash/status-note.sh" --set now "spec 014-x 에서 멈춤 — T001" --json >/dev/null 2>&1
    jq -r '.handoff.now_at' "$ST/.ax/current-task.json" 2>/dev/null | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z$' \
        && pass "status-note --set now — now_at 에 YYYY-MM-DDTHH:MMZ" || fail "status-note --set now — now_at 없음 (기한 판정 불가): $(jq -c '.handoff.now_at' "$ST/.ax/current-task.json" 2>/dev/null)"
    [ -z "$(printf '{"session_id":"f1","stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$ST" bash "$ST/.ax/hooks/stop/spec-gate.sh" 2>/dev/null)" ] \
        && pass "stop 게이트 — 방금 쓴 인계 노트는 인정 (통과)" || fail "stop 게이트 — 신선한 노트를 무시"
    # 시각만 과거로 바꿔요 — 노트 내용은 그대로인데 24시간이 지났어요
    jq '.handoff.now_at="2020-01-01T00:00Z"' "$ST/.ax/current-task.json" > "$ST/ct.tmp" && mv "$ST/ct.tmp" "$ST/.ax/current-task.json"
    printf '{"session_id":"f2","stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$ST" bash "$ST/.ax/hooks/stop/spec-gate.sh" 2>/dev/null \
        | jq -e '.decision=="block"' >/dev/null 2>&1 \
        && pass "stop 게이트 — 24시간 지난 인계 노트는 불인정 (영구 통과증 아님)" || fail "stop 게이트 — 오래된 노트로 영구 통과"

    # spec ID 로 적은 인계 노트도 인정 — 다른 스크립트의 --spec 처럼. 전체 이름만 찾던 때는
    # "spec 2026-10-03-1b92 implementing" 이라고 적어도 한 번 더 막았어요 (실측)
    sg() { printf '{"session_id":"%s","stop_hook_active":false}' "$1" | CLAUDE_PROJECT_DIR="$ST" bash "$ST/.ax/hooks/stop/spec-gate.sh" 2>/dev/null; }
    note() { CLAUDE_PROJECT_DIR="$ST" bash "$ST/.ax/scripts/bash/status-note.sh" --set now "$1" --json >/dev/null 2>&1; }
    note "spec 014 에서 멈춤 — T001"
    [ -z "$(sg i1)" ] && pass "stop 게이트 — 옛 순번 ID(014)로 적은 노트도 인정" || fail "stop 게이트 — 옛 순번 ID 노트를 무시"
    note "T0140 작업 중 · 2014 년 자료"
    sg i2 | jq -e '.decision=="block"' >/dev/null 2>&1 \
        && pass "stop 게이트 — ID 는 경계가 있을 때만 (T0140·2014 는 014 가 아니에요)" || fail "stop 게이트 — 014 가 T0140 에 걸림"
    mkdir -p "$ST/.ax/docs/spec/2026-10-03-1b92-sharing-web"
    cp "$ST/.ax/docs/spec/014-x/"{spec,tasks}.md "$ST/.ax/docs/spec/2026-10-03-1b92-sharing-web/"
    echo '{"phase":"implementing","spec_dir":".ax/docs/spec/2026-10-03-1b92-sharing-web","size":"M","risk":"L1"}' > "$ST/.ax/current-task.json"
    SG_R=$(sg i3 | jq -r '.reason // empty')
    case "$SG_R" in
        *'--set now "spec 2026-10-03-1b92 implementing'*'spec ID(2026-10-03-1b92)'*)
            pass "stop 게이트 — 안내 문구의 예시가 spec ID 로 (ID 로 적으면 통과한다고 알림)" ;;
        *) fail "stop 게이트 — 안내 문구에 ID 예시 없음: ${SG_R:0:200}" ;;
    esac
    note "spec 2026-10-03-1b92 implementing — T001 까지"
    I4=$(sg i4); note "2026-10-03-1b92에서 멈춤"; I5=$(sg i5)
    note "spec 2026-10-03-1b92-sharing-web 에서 멈춤"; I6=$(sg i6)
    [ -z "$I4" ] && [ -z "$I5" ] && [ -z "$I6" ] \
        && pass "stop 게이트 — 새 ID(YYYY-MM-DD-hex)·한글이 붙은 ID·전체 이름 노트 모두 인정" \
        || fail "stop 게이트 — 새 ID 노트 불인정: [${I4:0:40}][${I5:0:40}][${I6:0:40}]"
    note "spec 2026-10-03-1b93 implementing"
    sg i7 | jq -e '.decision=="block"' >/dev/null 2>&1 \
        && pass "stop 게이트 — 다른 spec 의 ID 는 불인정" || fail "stop 게이트 — 다른 spec ID 로 통과"
    echo '{"phase":"implementing","spec_dir":".ax/docs/spec/014-x","size":"M","risk":"L1"}' > "$ST/.ax/current-task.json"

    printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash .ax/hooks/stop/spec-gate.sh"}]}],"Stop":[]}}' > "$ST/.claude/settings.json"
    GOAX_PROJECT_DIR="$ST" bash "$ST/.ax/scripts/bash/doctor-scan.sh" --json --plugin-dir "$REPO" 2>/dev/null \
        | jq -e '.result.hooks.missing | index("Stop .ax/hooks/stop/spec-gate.sh")' >/dev/null 2>&1 \
        && pass "doctor-scan — 훅을 다른 이벤트로 옮기면 (이벤트,경로) 쌍이 missing" \
        || fail "doctor-scan — 경로만 보고 이벤트 키를 무시 (Stop 훅이 안 도는데 통과)"
    rm -rf "$ST"

    # C2 — 시크릿 검출. 옛 정규식은 `=` 와 따옴표를 둘 다 요구해서 실검체 9종을 전부 놓쳤어요.
    SEC=$(mktemp -d)
    pushd "$SEC" >/dev/null || fail "SEC pushd 실패"
    git init -q . >/dev/null 2>&1
    mkdir -p .ax/scripts/bash .ax/hooks/pre-commit fx
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" .ax/scripts/bash/
    cp "$REPO/templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh" .ax/hooks/pre-commit/
    printf '# C\n' > CLAUDE.md; printf 'sensors:\n  mode: fail\n' > .ax/config.yml
    # 토큰 형태 픽스처는 소스에 리터럴로 두지 않고 실행 시점에 이어 붙여요 — GitHub push protection 이 이 파일을 시크릿으로 막아요
    printf 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n'                         > fx/hit1.txt
    printf 'TOKEN=%s_%s\n' ghp 1234567890abcdefghijABCDEFGHIJ12               > fx/hit2.txt
    printf 'const t = "%s_%s";\n' ghp abcdefghij1234567890ABCDEFGHIJ         > fx/hit3.txt
    printf 'SLACK=%s-%s\n' xoxb 123456789012-abcdefghijkl                     > fx/hit4.txt
    printf 'stripe_key = %s_%s_%s\n' sk live abcdefghij1234567890ABCD          > fx/hit5.txt
    printf 'API_KEY=%s-%s\n' sk abcdefghij1234567890ABCDEFGH                   > fx/hit6.txt
    printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEow==\n'                   > fx/hit7.txt
    printf 'auth: %s.%s.%s\n' eyJhbGciOiJIUzI1NiJ9 eyJzdWIiOiIxMjM0NTY3ODkwIn0 abcdefg > fx/hit8.txt
    printf 'PASSWORD=hunter2xyz\n'                                            > fx/hit9.txt
    printf 'token_count = 0\nmax_tokens = 4096\n'                             > fx/miss1.txt
    printf 'secret: null\napi_key: null\n'                                    > fx/miss2.txt
    printf 'password: <from env>\ntoken: ${GITHUB_TOKEN}\n'                   > fx/miss3.txt
    printf 'The api key is rotated every quarter and the password policy is strict.\n' > fx/miss4.txt
    sec_missed=0
    for i in 1 2 3 4 5 6 7 8 9; do
        git reset -q >/dev/null 2>&1; git add "fx/hit$i.txt" >/dev/null 2>&1
        CLAUDE_PROJECT_DIR="$SEC" bash .ax/hooks/pre-commit/critical-rule-grep.sh >/dev/null 2>&1
        [ $? -eq 2 ] || sec_missed=$((sec_missed+1))
    done
    [ "$sec_missed" -eq 0 ] \
        && pass "critical-rule-grep — 시크릿 실검체 9종 (AKIA·ghp_ ×2·xox·sk_live·sk-·PEM·JWT·PASSWORD=) 전부 차단" \
        || fail "critical-rule-grep — 시크릿 $sec_missed/9종 미탐"
    git reset -q >/dev/null 2>&1; git add fx/miss1.txt fx/miss2.txt fx/miss3.txt fx/miss4.txt >/dev/null 2>&1
    CLAUDE_PROJECT_DIR="$SEC" bash .ax/hooks/pre-commit/critical-rule-grep.sh >/dev/null 2>&1
    [ $? -eq 0 ] && pass "critical-rule-grep — 오탐 4종 (token_count·null·\${ENV}·산문) 통과" || fail "critical-rule-grep — 오탐 차단"
    git reset -q >/dev/null 2>&1; git add fx/hit1.txt >/dev/null 2>&1
    SEC_ERR=$(CLAUDE_PROJECT_DIR="$SEC" bash .ax/hooks/pre-commit/critical-rule-grep.sh 2>&1 >/dev/null)
    printf '%s' "$SEC_ERR" | grep -q 'AKIAIOSFODNN7EXAMPLE' \
        && fail "critical-rule-grep — 매칭 줄을 그대로 출력 (시크릿이 컨텍스트·로그로 새요)" \
        || pass "critical-rule-grep — 위치(file:line)만 보고, 매칭 줄은 안 찍음"

    # kv-detect 는 키 이름 뒤 `:` 를 값의 시작으로 읽어서 TS 타입 자리까지 시크릿으로 잡았어요.
    # 실측(one-tenth): `token: string,` · `messageFor?(target: UserTarget, token: string, platform: Platform)`
    # 이 "CRITICAL 위반 1건" 이 됐고, 그 프로젝트는 sensors.mode 를 warning 으로 내렸어요.
    # 타입 자리(원시 타입 · `?:` · 시그니처/제네릭/유니온 안의 타입 이름)만 빼고, 값 대입은 그대로 잡아요.
    {
        printf 'export interface PushTarget {\n  token: string,\n  apiKey?: string;\n  password: Password;\n'
        printf '  messageFor?(target: UserTarget, token: string, platform: Platform): string;\n'
        printf '  secret: Record<string, string>;\n  accessKey: AccessKey | null;\n  tokens: TokenPair[];\n}\n'
        printf 'export function send(token: string, secret: SecretRef): void {}\n'
        printf 'const cache = new Map<string, { token: string | undefined }>();\n'
        printf 'val token: String\nlet password: String?\n'
    } > fx/ts-types.ts
    git reset -q >/dev/null 2>&1; git add -f fx/ts-types.ts >/dev/null 2>&1
    TS_ERR=$(CLAUDE_PROJECT_DIR="$SEC" bash .ax/hooks/pre-commit/critical-rule-grep.sh 2>&1 >/dev/null); TS_RC=$?
    [ "$TS_RC" -eq 0 ] \
        && pass "critical-rule-grep — TS·Kotlin·Swift 타입 선언 (token: string · ?: · 시그니처 인자 · 제네릭 · 유니온) 은 시크릿 아님" \
        || fail "critical-rule-grep — 타입 선언을 시크릿으로 차단 (rc=$TS_RC): $TS_ERR"
    printf 'const token: string = "%s";\n' abc123def456ghi            > fx/ts-hit1.ts
    printf 'const cfg = { token: "%s", user: User };\n' abc123def456   > fx/ts-hit2.ts
    printf 'const apiKey = "%s";\n' abc123def456ghi                    > fx/ts-hit3.ts
    printf 'password: %s\n' hunter2xyz                                 > fx/ts-hit4.yml
    printf 'secret: %s\n' Abc123Secret                                 > fx/ts-hit5.yml
    printf 'send({ token: "%s" }, token: string)\n' abc123def456ghi    > fx/ts-hit6.ts
    ts_missed=""
    for f in fx/ts-hit1.ts fx/ts-hit2.ts fx/ts-hit3.ts fx/ts-hit4.yml fx/ts-hit5.yml fx/ts-hit6.ts; do
        git reset -q >/dev/null 2>&1; git add -f "$f" >/dev/null 2>&1
        CLAUDE_PROJECT_DIR="$SEC" bash .ax/hooks/pre-commit/critical-rule-grep.sh >/dev/null 2>&1
        [ $? -eq 2 ] || ts_missed="$ts_missed $f"
    done
    [ -z "$ts_missed" ] \
        && pass "critical-rule-grep — 타입 옆 값 대입 6종 (: string = \"…\" · { token: \"…\" } · = \"…\" · YAML 2종 · 같은 줄 타입+값) 은 그대로 차단" \
        || fail "critical-rule-grep — 타입 자리를 빼다가 값 대입까지 놓침:$ts_missed"
    popd >/dev/null || true
    rm -rf "$SEC"

    # 출고 프로브가 자기 게이트에 대해 PASS 해야 해요 (예전엔 PROBE FAILED 였어요)
    PRB=$(mktemp -d)
    pushd "$PRB" >/dev/null || fail "PRB pushd 실패"
    git init -q . >/dev/null 2>&1
    bash "$REPO/scripts/provision.sh" --target "$PRB" --json >/dev/null 2>&1
    printf 'sensors:\n  mode: fail\n' > .ax/config.yml
    mkdir -p .ax/probes; cp "$REPO/templates/zero/probe/examples/secret-scan.sh" .ax/probes/
    if [ -x .git/hooks/pre-commit ]; then
        CLAUDE_PROJECT_DIR="$PRB" bash .ax/probes/secret-scan.sh >/dev/null 2>&1
        [ $? -eq 0 ] && [ ! -f .probe-secret.txt ] \
            && pass "probe/secret-scan.sh — 게이트가 프로브 검체를 차단 (PASS) + 픽스처 정리" \
            || fail "probe/secret-scan.sh — PROBE FAILED (secrets 게이트가 뚫림) 또는 픽스처 잔존"
        # 짝 프로브 — 타입 옆 값은 막고 타입 선언만은 통과 (kv-detect 오탐이 mode 를 warning 으로 내리게 했어요)
        cp "$REPO/templates/zero/probe/examples/secret-scan-typed.sh" .ax/probes/
        TYPED_OUT=$(CLAUDE_PROJECT_DIR="$PRB" bash .ax/probes/secret-scan-typed.sh 2>&1); TYPED_RC=$?
        [ "$TYPED_RC" -eq 0 ] && [ ! -f .probe-secret-typed.ts ] \
            && pass "probe/secret-scan-typed.sh — 타입 옆 시크릿 값은 차단 · 타입 선언만은 통과 (PASS) + 픽스처 정리" \
            || fail "probe/secret-scan-typed.sh — rc=$TYPED_RC: $TYPED_OUT"
    else
        fail "probe/secret-scan.sh — provision 이 .git/hooks/pre-commit 을 안 깔아서 프로브를 못 돌림"
    fi
    popd >/dev/null || true
    rm -rf "$PRB"

    # ── 시크릿 패턴 SSOT ─────────────────────────────────────────────
    # 패턴이 훅 상수와 common.sh 의 sed 두 곳에 있어서 여덟 축이 이미 갈라져 있었어요
    # (웹훅·pg_key 는 마스킹만, passwd·access_key 는 검출만, AWS·Stripe·JWT 정량자가 서로 달랐음).
    # 이제 `goax_secret_rules` 표 하나에서 검출과 마스킹이 같이 나와요.
    SR_ERR=$(bash -c 'source "'"$REPO"'/templates/default/.ax/scripts/bash/common.sh"
        goax_secret_rules | awk -F"\t" "
            NF!=4                          {print \"NF:\" NR; e=1}
            \$3 ~ /#/ || \$4 ~ /#/         {print \"HASH:\" NR; e=1}
            \$4 ~ /&/                      {print \"AMP:\" NR; e=1}
            \$1==\"detect\" && \$4!=\"-\"  {print \"DUMMY:\" NR; e=1}
            END{exit e+0}"' 2>&1)
    [ -z "$SR_ERR" ] \
        && pass "goax_secret_rules — 4열 · ERE/치환문에 # 없음 · 치환문에 & 없음 · detect 행은 - 고정" \
        || fail "goax_secret_rules — 표 불변식 위반: $SR_ERR"

    # 파일 하나만 봐요 — common.sh 의 `_GOAX_SECRET_KV_KEYS` 가 `SECRET_KV` 를 부분
    # 문자열로 담고 있어서, templates 전체에 걸면 SSOT 자신이 빨개져요.
    SR_INLINE=$(grep -cE 'SECRET_SHAPES|SECRET_KV|AKIA|gh\[|xox|eyJ|AIza' \
        "$REPO/templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh" || true)
    [ "${SR_INLINE:-1}" -eq 0 ] \
        && pass "critical-rule-grep — 인라인 시크릿 패턴 0 (표가 유일한 출처)" \
        || fail "critical-rule-grep — 패턴 문자열이 다시 인라인됨 (${SR_INLINE}건)"

    # 검출·마스킹이 같은 검체에 같은 답을 내는가. 여섯은 예전에 한쪽만 잡았어요.
    SSOT=$(mktemp -d)
    pushd "$SSOT" >/dev/null || fail "SSOT pushd 실패"
    git init -q . >/dev/null 2>&1
    mkdir -p .ax/scripts/bash .ax/hooks/pre-commit fx
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" .ax/scripts/bash/
    cp "$REPO/templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh" .ax/hooks/pre-commit/
    printf '# C\n' > CLAUDE.md; printf 'sensors:\n  mode: fail\n' > .ax/config.yml
    # 픽스처는 소스에 리터럴로 두지 않고 실행 시점에 이어 붙여요 (GitHub push protection)
    printf 'url = https://hooks.slack.com/services/%s/%s/%s\n' T00000000 B00000000 abcdefghij0123456789 > fx/n1.txt
    printf 'auth: %s.%s.%s\n' eyJhbGciOiJIUzI1NiJ9 eyJzdWIiOiIxMjM0NTY3ODkwIn0 abcdefg               > fx/n2.txt
    printf -- '-----BEGIN PRIVATE KEY-----\nMIIEow==\n'                                              > fx/n3.txt
    printf 'Api_Key=%s\n' abcdefgh12345678                                                           > fx/n4.txt
    printf 'passwd=%s\n' abcdefgh12345678                                                            > fx/n5.txt
    printf 'access_key=%s\n' abcdefgh12345678                                                        > fx/n6.txt
    printf 'pg_key=%s\n' abcdefgh12345678                                                            > fx/n7.txt
    ssot_miss=""; ssot_keep=""
    for i in 1 2 3 4 5 6 7; do
        git reset -q >/dev/null 2>&1; git add -f "fx/n$i.txt" >/dev/null 2>&1
        CLAUDE_PROJECT_DIR="$SSOT" bash .ax/hooks/pre-commit/critical-rule-grep.sh >/dev/null 2>&1
        [ $? -eq 2 ] || ssot_miss="$ssot_miss n$i"
        RED=$(bash -c 'source "'"$SSOT"'/.ax/scripts/bash/common.sh" && redact_secrets' < "fx/n$i.txt")
        [ "$RED" = "$(cat "fx/n$i.txt")" ] && ssot_keep="$ssot_keep n$i"
    done
    [ -z "$ssot_miss" ] \
        && pass "critical-rule-grep — 신규 7종 (웹훅·3세그 JWT·수식어 없는 PEM·Api_Key·passwd·access_key·pg_key) 전부 차단" \
        || fail "critical-rule-grep — 신규 검체 미탐:$ssot_miss"
    [ -z "$ssot_keep" ] \
        && pass "redact_secrets — 같은 7종을 마스킹도 함 (검출·마스킹 폭 일치)" \
        || fail "redact_secrets — 검출은 되는데 마스킹 안 됨:$ssot_keep (SSOT 갈라짐)"
    popd >/dev/null || true
    rm -rf "$SSOT"

    # common.sh 가 없으면 검출할 패턴이 없어요 — 조용히 통과하면 안전망이 꺼진 걸 아무도 몰라요
    NOC=$(mktemp -d)
    pushd "$NOC" >/dev/null || fail "NOC pushd 실패"
    git init -q . >/dev/null 2>&1
    mkdir -p .ax/hooks/pre-commit fx
    cp "$REPO/templates/default/.ax/hooks/pre-commit/critical-rule-grep.sh" .ax/hooks/pre-commit/
    printf '# C\n' > CLAUDE.md; printf 'sensors:\n  mode: fail\n' > .ax/config.yml
    printf 'AWS_ACCESS_KEY_ID=%s%s\n' AKIA IOSFODNN7EXAMPLE > fx/hit.txt
    git add -f fx/hit.txt >/dev/null 2>&1
    NOC_ERR=$(CLAUDE_PROJECT_DIR="$NOC" bash .ax/hooks/pre-commit/critical-rule-grep.sh 2>&1 >/dev/null); NOC_RC=$?
    { [ "$NOC_RC" -eq 0 ] && printf '%s' "$NOC_ERR" | grep -q '안전망 비활성'; } \
        && pass "critical-rule-grep — common.sh 부재를 '안전망 비활성' 으로 말하고 통과 (무성 skip 아님)" \
        || fail "critical-rule-grep — common.sh 부재를 조용히 통과 (rc=$NOC_RC): $NOC_ERR"
    popd >/dev/null || true
    rm -rf "$NOC"

    # check-mistake-secrets 도 같은 규약 — common.sh(redact_secrets) 가 없으면 말하고 통과
    NOM=$(mktemp -d)
    pushd "$NOM" >/dev/null || fail "NOM pushd 실패"
    git init -q . >/dev/null 2>&1
    mkdir -p .ax/hooks/pre-commit .ax/mistakes
    cp "$REPO/templates/default/.ax/hooks/pre-commit/check-mistake-secrets.sh" .ax/hooks/pre-commit/
    printf 'sensors:\n  mode: fail\n' > .ax/config.yml
    printf -- '---\ncategory: ops\n---\nAWS_ACCESS_KEY_ID=%s%s\n' AKIA IOSFODNN7EXAMPLE > .ax/mistakes/2026-01-01-leak.md
    git add -f .ax/mistakes/2026-01-01-leak.md >/dev/null 2>&1
    NOM_ERR=$(CLAUDE_PROJECT_DIR="$NOM" bash .ax/hooks/pre-commit/check-mistake-secrets.sh 2>&1 >/dev/null); NOM_RC=$?
    { [ "$NOM_RC" -eq 0 ] && printf '%s' "$NOM_ERR" | grep -q '안전망 비활성'; } \
        && pass "check-mistake-secrets — common.sh 부재를 '안전망 비활성' 으로 말하고 통과 (무성 skip 아님)" \
        || fail "check-mistake-secrets — common.sh 부재를 조용히 통과 (rc=$NOM_RC): $NOM_ERR"
    popd >/dev/null || true
    rm -rf "$NOM"

    # 패턴 확대(AWS {16,}·Stripe {16,}·JWT 2세그)의 대가 — 기존 mistake 본문이 계속 통과하는가
    MS=$(mktemp -d)
    mkdir -p "$MS/.ax/scripts/bash" "$MS/.ax/hooks/pre-commit" "$MS/.ax/mistakes"
    ( cd "$MS" && git init -q . >/dev/null 2>&1 )
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" "$MS/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/hooks/pre-commit/check-mistake-secrets.sh" "$MS/.ax/hooks/pre-commit/"
    printf 'sensors:\n  mode: fail\n' > "$MS/.ax/config.yml"
    { printf -- '---\ncategory: parser\nseverity: medium\n---\n\n# 무엇이 일어났나\n'
      printf 'token_count = 0 인 응답을 성공으로 셌어요.\n\n# 왜 발생 (5 Whys 기법)\n'
      printf '1. 왜? → max_tokens = 4096 인데 잘림을 안 봤어요\n2. 왜? → api_key: null 과 구분이 없었어요\n'
      printf '3. 왜? → password 정책 문서를 안 읽었어요\n4. 왜? → secret: null 을 빈 값으로 봤어요\n'
      printf '5. 왜? → 검증 명령이 exit code 만 봤어요\n\n# 영향 (Cost)\n- 재작성 3파일\n\n## 이력\n'
    } > "$MS/.ax/mistakes/2026-01-01-parser-x.md"
    ( cd "$MS" && git add .ax/mistakes/2026-01-01-parser-x.md >/dev/null 2>&1 )
    if CLAUDE_PROJECT_DIR="$MS" bash "$MS/.ax/hooks/pre-commit/check-mistake-secrets.sh" >/dev/null 2>&1; then
        pass "check-mistake-secrets — 기존 mistake 본문 형태는 확대된 표에서도 통과 (오탐 0)"
    else
        fail "check-mistake-secrets — 패턴 확대가 평범한 mistake 본문을 막음"
    fi
    rm -rf "$MS"
fi

smoke_done
