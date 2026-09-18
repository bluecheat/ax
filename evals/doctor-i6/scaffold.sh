#!/usr/bin/env bash
# doctor-i6 scaffold — "집행 실체가 없는" 설치를 실제 설치기로 만들어요.
# `--scaffold` 로만 실행되고, 샌드박스 밖에서 사용자 권한으로 돌아요.
#
# provision.sh 가 .ax/ · AGENTS.md · CLAUDE.md · settings.json 을 깔고, .git 이 있으니 install-git-hooks.sh 가
# 기본 wrapper(.git/hooks/pre-commit, #goax-pre-commit-chain) 까지 설치해요 — wrapper 는 .ax/hooks/pre-commit/*.sh 만
# chain 하지 external 도구를 돌리지 않아요. 그 위에 `enforced_by: external:vitest` 룰 하나를 두고 CI 워크플로·프로젝트
# 전용 훅·package.json 은 만들지 않아요. 정답은 "라벨은 있는데 자동 트리거가 없다 = 손으로 돌릴 때만" 이에요 (I6 / C3).
set -euo pipefail

CASE_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(CDPATH="" cd "$CASE_DIR/../.." && pwd)"
[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ] || { printf '[goax eval] plugin root 아님: %s\n' "$PLUGIN_ROOT" >&2; exit 1; }

git init -q
mkdir -p .claude
OUT=$(bash "$PLUGIN_ROOT/scripts/provision.sh" --target "$PWD" --json)
printf '%s' "$OUT" | jq -e '.status == "ok" or .status == "warning"' >/dev/null \
    || { printf '[goax eval] provision 실패: %s\n' "$OUT" >&2; exit 1; }
grep -q '#goax-pre-commit-chain' .git/hooks/pre-commit \
    || { printf '[goax eval] git pre-commit wrapper 가 설치되지 않았어요\n' >&2; exit 1; }

# CRITICAL 섹션의 자리표시자 룰 둘을 실제 값이 채워진 external 룰 하나로 바꿔요 — 값을 채우는 순간 I1·I5·I6 검사 대상이 돼요.
python3 - <<'PY'
import re
p='AGENTS.md'; s=open(p).read()
start=s.index('🔴 **`AX:CRITICAL:001`**')
end=s.index('> ⚠ hook 파일을 아직 못 만들었으면')
rule=('🔴 **`EVL:CRITICAL:001`** 사용자 노출 카피 안전선을 어기지 않는다\n'
      '- enforced_by: external:vitest\n'
      '- enforced_kind: test\n\n')
s=s[:start]+rule+s[end:]
open(p,'w').write(s)
PY
grep -q 'EVL:CRITICAL:001' AGENTS.md || { printf '[goax eval] AGENTS.md 룰 치환 실패\n' >&2; exit 1; }
