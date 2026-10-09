# tests/lib/harness.sh — smoke 조각이 같이 쓰는 출력 · 실패 집계 · fixture
#
# 조각(tests/smoke/NN-*.sh)은 맨 위에서 이 파일을 source 하고 맨 끝에서 smoke_done 을 불러요.
# 조각 하나만 돌릴 때: bash tests/smoke/12-locks.sh — 전체는 bash tests/smoke.sh 가 병렬로 돌려요.
#
# fixture — 손으로 만든 .ax/ 는 실제 설치본과 달라서 거짓 양성이 났어요 (update-state 자가 복구:
# 템플릿을 손으로 넣어 통과했는데 MANIFEST 가 그 템플릿을 설치하지 않았어요). 상태 파일을 쓰는
# 스크립트 테스트는 fx_install 로 실제 설치본 위에서 돌려요. 손복사 fixture 개수는 §67 이 상한으로 막아요.

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO/templates/default/.ax/scripts/bash"   # 출고 스크립트 원본
fail_count=0
pass() { printf '\033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$1"; fail_count=$((fail_count+1)); }
section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# 조각의 마지막 줄 — 러너는 이 표식이 없으면 "끝까지 안 돌았다" 로 셉니다 (중간 exit · set -u 사망).
smoke_done() {
    printf '@@smoke-part-done fail=%s\n' "$fail_count"
    [ "$fail_count" -eq 0 ]
    exit $?
}

# fx_install <변수> [--git] — scripts/provision.sh 로 새 임시 디렉터리에 실제 설치본을 깔고 경로를 <변수> 에 넣어요.
#   --git 은 git init 뒤 설치본을 커밋까지 해요 (fx_fresh_worktree 의 원본이 되려면 필요해요).
#   실패하면 fail 하나를 세고 1 — 호출자는 `fx_install X || …` 로 받아요. $(…) 로 부르면 fail 이 안 세져요.
fx_install() {
    local _var="$1" _git=false _d _out
    [ "${2:-}" = --git ] && _git=true
    _d=$(mktemp -d) || { fail "fx_install — mktemp 실패"; return 1; }
    if [ "$_git" = true ]; then git -C "$_d" init -q 2>/dev/null || { fail "fx_install — git init 실패"; return 1; }; fi
    _out=$(bash "$REPO/scripts/provision.sh" --target "$_d" --json 2>/dev/null)
    if ! printf '%s\n' "$_out" | grep -q '"status":"ok"'; then
        fail "fx_install — provision.sh 실패: $(printf '%s' "$_out" | head -c 200)"; rm -rf "$_d"; return 1
    fi
    if [ "$_git" = true ]; then
        git -C "$_d" add -A >/dev/null 2>&1
        # 설치본이 깐 pre-commit 훅은 fixture 커밋엔 필요 없어요 (설치본 전체를 스캔해 몇 초씩 걸려요)
        git -C "$_d" -c core.hooksPath=/dev/null -c user.name=smoke -c user.email=smoke@example.invalid \
            commit -qm install >/dev/null 2>&1 || { fail "fx_install — 설치본 커밋 실패"; rm -rf "$_d"; return 1; }
    fi
    printf -v "$_var" '%s' "$_d"
}

# fx_fresh_worktree <변수> <fx_install --git 한 디렉터리> — 그 저장소에서 `git worktree add` 로 새 워크트리를 떠요.
#   gitignore 대상(current-task.json · state.json · tasks/ · .session/ …)이 없는 바로 그 상태예요 — 손으로 지워 흉내 내지 않아요.
fx_fresh_worktree() {
    local _var="$1" _src="$2" _d
    _d=$(mktemp -d) || { fail "fx_fresh_worktree — mktemp 실패"; return 1; }
    rmdir "$_d"
    git -C "$_src" worktree add -q --detach "$_d" >/dev/null 2>&1 || { fail "fx_fresh_worktree — git worktree add 실패"; return 1; }
    printf -v "$_var" '%s' "$_d"
}

# fx_tree_sum <디렉터리> — .git 을 뺀 모든 파일(gitignore 대상 포함)의 경로+내용 해시 한 줄. "아무것도 안 썼다" 비교용.
fx_tree_sum() {
    (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s ' "$f"; cksum < "$f"
    done) | cksum
}

# fx_timeout <초> <명령…> — macOS 엔 timeout(1) 이 없어요. 시간이 지나면 SIGALRM 으로 끝나요 (exit 142).
fx_timeout() { perl -e 'alarm shift; exec @ARGV or exit 127' "$@"; }
