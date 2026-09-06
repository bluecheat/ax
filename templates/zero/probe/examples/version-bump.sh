#!/usr/bin/env bash
# probe: 릴리즈 없이 버전 필드만 올리면 게이트가 막는가
#
# 계약: 게이트가 막았으면 exit 0 · 못 막았으면 exit 1 · 돌릴 수 없으면 exit 2
#
# "나중에 낼 거니까 버전만 먼저 올려 두자" 는 릴리즈 노트·태그와 버전을 어긋나게 만들어요.
# 어긋난 뒤엔 어느 커밋이 어느 버전인지 아무도 모릅니다.
#
# 짝이 되는 게이트는 프로젝트가 깔아요 — pre-commit 에서 "버전이 올랐는데 그 버전의
# changelog 항목(또는 태그)이 없으면 막는다". 이 프로브는 **그 게이트가 아직 막는지**만 재요.
#
# 워킹 트리를 건드리므로 파일·스테이지를 반드시 되돌려요 (다른 세션이 같은 트리에
# 있을 수 있어요). 커밋은 만들지 않아요 — pre-commit 훅만 부릅니다.

set -uo pipefail

# 버전 필드가 있는 파일 — 프로젝트에 맞게 고치세요 (package.json·gradle.properties 등)
VERSION_FILE="${GOAX_VERSION_FILE:-VERSION}"

command -v git >/dev/null 2>&1 || { echo "git 없음 — skip"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "git 저장소 아님 — skip"; exit 2; }
[ -f "$VERSION_FILE" ] || { echo "$VERSION_FILE 없음 — skip (GOAX_VERSION_FILE 로 지정하세요)"; exit 2; }
HOOK="$(git rev-parse --git-dir)/hooks/pre-commit"
[ -x "$HOOK" ] || { echo "pre-commit 훅 미설치 — skip (install-git-hooks.sh)"; exit 2; }

CUR=$(head -1 "$VERSION_FILE" | tr -d '[:space:]')
case "$CUR" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "$VERSION_FILE 이 semver 가 아니에요 ($CUR) — skip"; exit 2 ;;
esac

ORIG=$(mktemp)
cleanup() {
    cp "$ORIG" "$VERSION_FILE" 2>/dev/null || true
    git reset -q -- "$VERSION_FILE" 2>/dev/null || true
    unlink "$ORIG" 2>/dev/null || true
}
trap cleanup EXIT
cp "$VERSION_FILE" "$ORIG"

# 1. 일부러 위반 만들기 — changelog 항목도 태그도 없이 patch 만 올려요
NEXT=$(printf '%s' "$CUR" | awk -F. '{ printf "%s.%s.%d", $1, $2, $3 + 1 }')
printf '%s\n' "$NEXT" > "$VERSION_FILE"
git add -f "$VERSION_FILE" 2>/dev/null || { echo "스테이지 실패 — skip"; exit 2; }

# 2. 훅만 직접 실행 — 커밋을 만들지 않아요. 파이프 없이
"$HOOK" > /dev/null 2>&1
code=$?

# 3. 판정
if [ "$code" -ne 0 ]; then
    echo "pre-commit 이 릴리즈 없는 버전 증가를 차단했어요 ($CUR → $NEXT, exit $code)"
    exit 0
fi

echo "PROBE FAILED — $CUR → $NEXT 이 그대로 통과했어요. 릴리즈 없이 버전만 올라갑니다"
echo "  게이트 예: pre-commit 에서 버전이 오르면 같은 버전의 changelog 항목·태그를 요구"
exit 1
