#!/usr/bin/env bash
# tests/smoke/03-hook-safety.sh — §15 — 훅 안전망 (PR #1085 리뷰 회귀)
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/03-hook-safety.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "15. PR #1085 review fixes — security/correctness/escape"
# ───────────────────────────────────────────────────────────
# §15/§41 분담: 여기는 git/원격/sudo 계열 경고 7종 + CATASTROPHIC 24종 + 무해 16종(무음 · 세그먼트 범위 회귀 13종 포함).
# 상위 경로(..) 계열 경고 5종 · 일상 rm 4종(무음) · jq 부재는 §41 담당이에요 — 섞지 마세요.

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
assert_warned() {
    local cmd="$1"; local label="$2"; local err exit_code
    # local 선언과 대입을 나눠요 — `local err=$(...)` 로 합치면 $? 가 항상 0 이에요
    err=$(echo "{\"tool_input\":{\"command\":\"$cmd\"}}" \
        | CLAUDE_PROJECT_DIR=$BD_FX bash "$BD_FX/.ax/hooks/pre-bash/block-destructive.sh" 2>&1 >/dev/null)
    exit_code=$?
    if [ "$exit_code" -eq 0 ] && printf '%s' "$err" | grep -q '\[goax hook\]'; then
        pass "block-destructive 경고: $label ('$cmd')"
    else
        fail "block-destructive 경고 없음 (exit=$exit_code, stderr='$err'): $label ('$cmd')"
    fi
}
assert_passed() {
    local cmd="$1"; local label="$2"; local err exit_code
    err=$(echo "{\"tool_input\":{\"command\":\"$cmd\"}}" \
        | CLAUDE_PROJECT_DIR=$BD_FX bash "$BD_FX/.ax/hooks/pre-bash/block-destructive.sh" 2>&1 >/dev/null)
    exit_code=$?
    if [ "$exit_code" -eq 0 ] && [ -z "$err" ]; then
        pass "block-destructive 통과: $label ('$cmd')"
    else
        fail "block-destructive 잘못 차단/경고 (exit=$exit_code, stderr='$err'): $label ('$cmd')"
    fi
}

# CATASTROPHIC — 항상 차단
assert_blocked 'rm -rf /'    'rm -rf /'
assert_blocked 'rm -fr /'    'rm -fr / variant (fr 순서)'
assert_blocked 'rm -rfv /'   'rm -rfv / (verbose flag)'
assert_blocked 'rm -fvR /'   'rm -fvR / (대소문자 혼합)'
assert_blocked 'rm -r -f /'  'rm -r -f / (multi-chunk)'
assert_blocked 'rm -rf -- /' 'rm -rf -- / (end-of-options sentinel)'
assert_blocked 'mkfs.ext4 /dev/sda1' 'mkfs.* (디스크 포맷)'

# RECOVERABLE — warning mode에선 경고 (stderr `[goax hook]` + exit 0)
assert_warned 'git push --force'                      'EOL --force (이전 미매칭)'
assert_warned 'git push --force-with-lease'           '--force-with-lease (recoverable)'
assert_warned 'git push origin main --force'          'remote/ref 사이에 --force (이전 우회 케이스)'
assert_warned 'git push origin -f'                    'remote 다음 -f'
assert_warned 'git reset --hard origin/main'          'git reset --hard (히스토리 되돌리기)'
assert_warned 'git clean -xfd'                        'git clean -xfd (무시 파일까지 삭제)'
assert_warned 'sudo rm -rf /tmp/x'                    'sudo rm (권한 상승 삭제)'

# 안전 명령 — 통과 (stderr 무음까지)
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

# 세그먼트 범위 — 세 조건(rm · 재귀 · 루트 경로)을 명령 전체가 아니라 **rm 이 든 단순 명령 하나** 안에서 봐요.
# 실측(one-tenth): 디스크가 120MB 남은 상태에서 세션 스크래치패드의 20GB 빌드 캐시를 지우려던 명령이
# 뒤에 붙은 `df -h /` 의 ` /` 때문에 CATASTROPHIC 으로 막혔어요. heredoc 본문의 낱말에도 같은 일이 났어요.
SP=/private/tmp/claude-502/-Users-me-proj/0f1e2d3c-sess/scratchpad
assert_passed "cd $SP/ios-dd && rm -rf Build/Intermediates.noindex Index.noindex ModuleCache.noindex Logs; du -sh . ; df -h / | tail -1" \
    '실측 — 스크래치패드 빌드 캐시 삭제 + 뒤의 df -h /'
assert_passed "rm -rf $SP/ios-dd $SP/ios-dd2"                    '세션 스크래치패드 절대 경로'
assert_passed "rm -rf /tmp/claude-501/-p/s/scratchpad/x && ls /" '/tmp/claude-* 스크래치패드 + 뒤의 ls /'
assert_passed 'D=/private/tmp/claude-502/p/s/scratchpad/ios-dd; rm -rf $D/Build; df -h /' '변수 경로 + df -h /'
assert_passed 'cat > a.md <<EOF\nrm -rf 는 쓰지 마세요\n/ 루트도요\nEOF' 'heredoc 본문의 낱말'
# 같은 단순 명령 안이면 여전히 막아요
assert_blocked 'rm -rf / ; echo done'        'rm -rf / 뒤에 다른 명령'
assert_blocked 'ls && rm -rf /*'             '앞에 다른 명령 + rm -rf /*'
assert_blocked 'df -h / && sudo rm -rf /usr' 'sudo rm -rf /usr (앞에 df -h /)'
assert_blocked '(rm -rf ~)'                  'subshell 안 rm -rf ~'
assert_blocked 'cd / && rm -rf *'            'cd / 뒤 상대 글롭 — 실제로 루트를 지워요'
assert_blocked 'cd ~; rm -rf .'              'cd ~ 뒤 rm -rf .'
assert_blocked 'cd /usr && rm -rf ./*'       'cd /usr 뒤 rm -rf ./*'
assert_passed  'cd / && ls; cd /tmp/x && rm -rf *' '루트에 갔다가 다른 곳으로 cd 한 뒤 rm -rf *'
assert_blocked 'pushd / && rm -rf *'         'pushd / 뒤 상대 글롭 — cd 와 같아요'
# 줄 이어쓰기(`\` + 줄바꿈)는 한 명령이에요 — 세그먼트로 자르기 전에 붙여요 (줄바꿈이 든 명령은 jq 로 JSON 을 만들어요)
for bd_cont in $'rm -rf \\\n /' $'sudo rm -rf \\\n  ~' $'rm -rf \\\n  /usr'; do
    jq -nc --arg c "$bd_cont" '{tool_input:{command:$c}}' \
        | CLAUDE_PROJECT_DIR=$BD_FX bash "$BD_FX/.ax/hooks/pre-bash/block-destructive.sh" >/dev/null 2>&1
    bd_rc=$?
    if [ "$bd_rc" -eq 2 ]; then pass "block-destructive 차단: 줄 이어쓰기로 나눈 $(printf '%s' "$bd_cont" | tr '\n' ' ')"
    else fail "block-destructive 미차단 (exit=$bd_rc): 줄 이어쓰기로 나눈 $(printf '%s' "$bd_cont" | tr '\n' ' ')"; fi
done

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

# 15.3 next-spec-num — 날짜+난수 ID (순번은 브랜치마다 같은 번호를 받아요 — commerce 실측 spec 8·ADR 12 중복)
ID_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0123456789abcdef][0123456789abcdef][0123456789abcdef][0123456789abcdef]$'
NS_FX=$(mktemp -d)
mkdir -p "$NS_FX/.ax/scripts/bash" "$NS_FX/.ax/docs/spec/998-legacy"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_FX/.ax/scripts/bash/"
NEXT=$(CLAUDE_PROJECT_DIR=$NS_FX bash "$NS_FX/.ax/scripts/bash/next-spec-num.sh" 2>&1)
printf '%s' "$NEXT" | grep -qE "$ID_RE" \
    && pass "next-spec-num — 새 ID 는 YYYY-MM-DD-<4hex> (옛 998 이 있어도 999 가 아니에요): $NEXT" \
    || fail "next-spec-num — ID 형식이 아니에요: $NEXT"
OUT=$(CLAUDE_PROJECT_DIR=$NS_FX bash "$NS_FX/.ax/scripts/bash/next-spec-num.sh" --json 2>&1)
echo "$OUT" | jq -e '.result.reserved == false and .result.previous == "998-legacy" and .result.existing_count == 1' >/dev/null 2>&1 \
    && [ "$(ls "$NS_FX/.ax/docs/spec" | grep -c .)" = 1 ] \
    && pass "next-spec-num — 미리보기는 아무것도 안 만들고, previous 는 가장 최근 항목" \
    || fail "next-spec-num 미리보기: $OUT"
OUT=$(CLAUDE_PROJECT_DIR=$NS_FX bash "$NS_FX/.ax/scripts/bash/next-spec-num.sh" --reserve --slug feat --json 2>&1)
RID=$(echo "$OUT" | jq -r '.result.next' 2>/dev/null)
printf '%s' "$RID" | grep -qE "$ID_RE" && [ -d "$NS_FX/.ax/docs/spec/${RID}-feat" ] \
    && [ "$(echo "$OUT" | jq -r '.result.path')" = ".ax/docs/spec/${RID}-feat" ] \
    && pass "next-spec-num --reserve — spec 디렉토리 <id>-<slug>/ 생성 + path 반환" \
    || fail "next-spec-num --reserve spec: $OUT"
OUT=$(CLAUDE_PROJECT_DIR=$NS_FX bash "$NS_FX/.ax/scripts/bash/next-spec-num.sh" --json 2>&1)
[ "$(echo "$OUT" | jq -r '.result.previous')" = "${RID}-feat" ] \
    && pass "next-spec-num — 새 ID 가 옛 순번보다 최근으로 정렬돼요" \
    || fail "next-spec-num previous 정렬: $OUT"
[ ! -d "$NS_FX/.ax/docs/spec/.numbers" ] \
    && pass "next-spec-num --reserve — 옛 번호 원장(.numbers/)을 더 만들지 않아요" \
    || fail "next-spec-num — 아직 .numbers 원장을 써요"

# 동시 예약 — 같은 ID 가 두 번 나오면 안 돼요 (예전 실사용 ADR 7 쌍 충돌의 회귀 테스트)
NS_RACE=$(mktemp -d)
mkdir -p "$NS_RACE/.ax/scripts/bash" "$NS_RACE/.ax/docs/spec"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_RACE/.ax/scripts/bash/"
for i in 1 2 3 4 5 6 7 8; do
    CLAUDE_PROJECT_DIR=$NS_RACE bash "$NS_RACE/.ax/scripts/bash/next-spec-num.sh" \
        --reserve --slug "feat$i" --json >/dev/null 2>&1 &
done
wait
RACE_TOT=$(ls "$NS_RACE/.ax/docs/spec" 2>/dev/null | grep -cE '^[0-9]' || true)
RACE_UNIQ=$(ls "$NS_RACE/.ax/docs/spec" 2>/dev/null | grep -E '^[0-9]' | cut -c1-15 | sort -u | grep -c . || true)
if [ "${RACE_TOT:-0}" -eq 8 ] && [ "${RACE_TOT:-0}" = "${RACE_UNIQ:-0}" ]; then
    pass "next-spec-num --reserve — 8개 동시 예약에서 ID 충돌 0"
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
ls "$NS_DR/.ax/docs/adr/" 2>/dev/null | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0123456789abcdef]{4}-real\.md$' \
    && pass "next-spec-num --reserve — ADR 실물 <id>-<slug>.md 생성" \
    || fail "next-spec-num --reserve — ADR 실물 미생성: $(ls "$NS_DR/.ax/docs/adr/")"

# --reserve 는 --slug 없이 거부돼야
CLAUDE_PROJECT_DIR=$NS_DR bash "$NS_DR/.ax/scripts/bash/next-spec-num.sh" --reserve --json >/dev/null 2>&1
[ $? -ne 0 ] && pass "next-spec-num --reserve — --slug 누락 시 error" \
             || fail "next-spec-num --reserve — --slug 없이 통과됨"

# --check-duplicates — 옛 순번 중복을 진단 (자동 수정 안 함). 새 ID 가 "2026" 으로 뭉쳐 오탐하면 안 돼요 —
# 옛 ADR `0008-x` 와 새 ID `2026-09-25-…` 는 둘 다 "숫자 4개 + 하이픈" 으로 시작해요.
NS_DUP=$(mktemp -d)
mkdir -p "$NS_DUP/.ax/scripts/bash" "$NS_DUP/.ax/docs/adr"
cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num}.sh "$NS_DUP/.ax/scripts/bash/"
: > "$NS_DUP/.ax/docs/adr/0001-a.md"; : > "$NS_DUP/.ax/docs/adr/0001-b.md"; : > "$NS_DUP/.ax/docs/adr/0003-c.md"
: > "$NS_DUP/.ax/docs/adr/2026-09-25-aaaa-x.md"; : > "$NS_DUP/.ax/docs/adr/2026-09-25-bbbb-y.md"
DUP_OUT=$(CLAUDE_PROJECT_DIR=$NS_DUP bash "$NS_DUP/.ax/scripts/bash/next-spec-num.sh" \
    --kind adr --check-duplicates --json 2>/dev/null)
if echo "$DUP_OUT" | jq -e '.result.duplicate_count == 1 and (.result.duplicates | index("0001"))' >/dev/null 2>&1; then
    pass "next-spec-num --check-duplicates — 옛 순번 중복만 검출 (같은 날 새 ID 두 개는 중복 아님)"
else
    fail "next-spec-num --check-duplicates — 검출 틀림: $DUP_OUT"
fi
CLAUDE_PROJECT_DIR=$NS_DUP bash "$NS_DUP/.ax/scripts/bash/next-spec-num.sh" \
    --kind adr --reserve --slug ghost --dry-run --json >/dev/null 2>&1
[ ! -d "$NS_DUP/.ax/docs/adr/.numbers" ] && [ "$(ls "$NS_DUP/.ax/docs/adr" | grep -c .)" = 5 ] \
    && pass "next-spec-num — --check-duplicates/--dry-run 은 읽기 전용" \
    || fail "next-spec-num — 읽기 전용 모드가 뭔가를 만들었어요"

# goax_resolve_spec — 새 ID 는 날짜로 시작해서 앞부분 축약이 안 먹어요. 난수·slug 로도 찾아야 해요.
mkdir -p "$NS_DUP/.ax/docs/spec/2026-09-25-a3f1-refund-flow" "$NS_DUP/.ax/docs/spec/012-legacy"
RS=$(bash -c "source '$NS_DUP/.ax/scripts/bash/common.sh'; for w in a3f1 refund-flow 2026-09-25-a3f1 012; do goax_resolve_spec \"\$w\" '$NS_DUP/.ax/docs/spec'; echo; done")
[ "$RS" = "$(printf '2026-09-25-a3f1-refund-flow\n2026-09-25-a3f1-refund-flow\n2026-09-25-a3f1-refund-flow\n012-legacy')" ] \
    && pass "goax_resolve_spec — 난수 · slug · ID 앞부분 · 옛 번호 모두로 찾아요" \
    || fail "goax_resolve_spec 새 ID 해석: $RS"
rm -rf "$NS_DUP"

# build-memory 최신순 — `sub(/-.*/)` 로 번호를 뽑으면 새 ID 는 전부 "2026" 이 돼서 순서가 사라져요
NS_BM=$(mktemp -d)
mkdir -p "$NS_BM/.ax/docs/adr" "$NS_BM/.ax/scripts/bash"
cp "$REPO/templates/default/.ax/scripts/bash/"*.sh "$NS_BM/.ax/scripts/bash/"
for n in 0001-old 0042-bigger 2026-09-20-aaaa-new 2026-09-25-bbbb-newest; do printf '# ADR %s\n' "$n" > "$NS_BM/.ax/docs/adr/$n.md"; done
BM_ORDER=$(GOAX_PROJECT_DIR="$NS_BM" bash "$NS_BM/.ax/scripts/bash/build-memory.sh" --dry-run --full 2>/dev/null \
    | sed -n '/최근 ADR/,/^$/p' | grep -oE 'adr/[^ ]+\.md' | sed 's|adr/||; s|\.md||' | tr '\n' ' ')
[ "$BM_ORDER" = "2026-09-25-bbbb-newest 2026-09-20-aaaa-new 0042-bigger 0001-old " ] \
    && pass "build-memory — 새 ID(날짜순) → 옛 순번(번호순) 으로 최신순 정렬" \
    || fail "build-memory 최신순이 틀려요: $BM_ORDER"
rm -rf "$NS_BM"

rm -rf "$NS_RACE" "$NS_DR"

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
ISR_UNIQ=$(printf '%s\n' "$ISR_DIRS" | cut -c1-15 | sort -u | grep -c . || true)
ISR_SPEC=$(find "$ISR_FX/.ax/docs/spec" -name spec.md 2>/dev/null | grep -c . || true)
if [ "${ISR_TOT:-0}" -eq 6 ] && [ "${ISR_TOT:-0}" = "${ISR_UNIQ:-0}" ] && [ "${ISR_SPEC:-0}" -eq 6 ]; then
    pass "init-spec-dir — 6개 동시 생성: ID 충돌 0 + spec.md 전부 생성"
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

# 15.6 §15/§41 경계 — 절대 행이 아니라 section "…" 마커로 범위를 뽑아요.
# (절대 행 범위는 이 파일이 편집될 때마다 움직여서 어서션이 조용히 무효화돼요.)
# 절은 조각 파일(tests/smoke/*.sh)에 흩어져 있어요 — 다음 section 마커나 파일 끝에서 범위를 닫고,
# 그 절을 못 찾으면 @@no-section 을 찍어 실패로 만들어요 (빈 범위가 0건으로 통과하면 안 돼요).
s_range() {
    awk -v want="^section \"$1\\\\." 'FNR == 1 { f = 0 } $0 ~ want { f = 1; n++; next } /^section / { f = 0 } f
        END { if (!n) print "@@no-section" }' "$REPO"/tests/smoke/*.sh
}
S_RANGE_MISS=$( { s_range 15; s_range 41; } | grep -c '^@@no-section' || true)
[ "${S_RANGE_MISS:-0}" -eq 0 ] && pass "§15/§41 경계 — 두 절 모두 조각 파일에서 찾았어요" || fail "§15/§41 경계 — 절을 못 찾았어요 (조각 파일 이름·section 마커 확인)"
S15_PARENT_HITS=$(s_range 15 | grep -c 'rm -rf \.\.' || true)
if [ "${S15_PARENT_HITS:-0}" -eq 0 ]; then
    pass "§15/§41 경계 — §15 안에 상위 경로(..) 계열 명령 없음"
else
    fail "§15/§41 경계 — §15 안에 상위 경로(..) 계열 명령이 섞여 있음 (${S15_PARENT_HITS}건)"
fi
S41_PUSH_HITS=$(s_range 41 | grep -c 'git push' || true)
if [ "${S41_PUSH_HITS:-0}" -eq 0 ]; then
    pass "§15/§41 경계 — §41 안에 git push 문자열 없음"
else
    fail "§15/§41 경계 — §41 안에 git push 문자열이 섞여 있음 (${S41_PUSH_HITS}건)"
fi

smoke_done
