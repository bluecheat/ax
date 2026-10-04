#!/usr/bin/env bash
# .ax/scripts/bash/design-caps.sh — 화면 작업에 쓸 수 있는 도구를 슬롯별로 찾아요 (screen skill 이 진입할 때)
#
# screen skill 은 이 도구들 없이도 끝까지 돌아요 — 지식은 skill 안에 다 있고, 여기서 찾는 건 **있으면 빨라지는 것**뿐이에요.
# 왜: 디자인 도구는 사람·머신마다 달라요 (Figma·Mobbin·uibowl MCP, ui-ux-pro-max, 브라우저 자동화, 시뮬레이터).
#   에이전트가 이름을 기억으로 가정하면 없는 도구를 부르거나 있는 도구를 놓쳐요. 그래서 **설정과 파일에 적힌 것만** 읽어
#   슬롯마다 후보를 내요. MCP 는 설정에 등록된 서버 이름만 봐요 — 이 세션에 실제로 떠 있는지는 모델이 자기 도구 목록
#   (`mcp__<서버>__*`)으로 한 번 더 확인해요. 비밀값은 읽지도 출력하지도 않아요.
#
# 슬롯 (앞에 있을수록 먼저 써요 — 프로젝트 자체 디자인 시스템이 늘 외부보다 먼저예요):
#   tokens      프로젝트 토큰·테마 파일 → 디자인 시스템·Figma MCP (없으면 screen skill 의 내장 스케일)
#   components  프로젝트 레지스트리(components.json)·Storybook → 디자인 시스템 MCP(shadcn·SEED·Chakra·magic)
#   reference   레퍼런스 MCP(mobbin·uibowl·figma) — 없으면 비어요 (웹 검색은 모델 몫)
#   render      agent-browser · playwright · xcrun simctl · adb
#   measure     python3 + Pillow (screen-measure.sh) · impeccable
#
# Usage:
#   bash design-caps.sh [--json] [--help]
#
# Output (--json):
#   {"status":"ok","result":{
#     "stack":"web|react-native|expo|lynx|flutter|swiftui|android|unknown",
#     "slots":{"tokens":[{"provider":"file","detail":"src/theme/tokens.ts"},…],"components":[…],"reference":[…],
#              "render":[…],"measure":[…]},
#     "spec":"docs/design/design-spec.md"|null,
#     "empty":["reference",…]},…}
#   provider: file · mcp:<서버 이름> · cli:<명령> · python:pillow
# Exit: 0 ok · 1 error · 2 skipped (jq 없음)
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi
    goax_error "알 수 없는 옵션: $1"; exit "$EXIT_ERROR"
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
if ! command -v jq >/dev/null 2>&1; then
    [ "$JSON_MODE" = true ] && json_skip "jq 가 필요해요 — brew install jq 또는 apt-get install jq"
    goax_warn "jq 가 없어 skip"; exit "$EXIT_SKIPPED"
fi
PROJECT_ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$PROJECT_ROOT"

ROWS=""   # slot<TAB>provider<TAB>detail
add() { ROWS="${ROWS}$1	$2	$3
"; }

# ── 스택 — 프로젝트 루트와 한 단계 아래(모노레포 apps/*)의 매니페스트 ──
STACK=unknown
# `| head -1` 가 먼저 닫으면 앞 명령이 SIGPIPE(141)로 끝나요 — pipefail 아래선 `|| true` 로 받아요
pkg_has() { { find . -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null \
              | xargs grep -lE "\"$1\"" 2>/dev/null | head -1; } || true; }
first() { "$@" 2>/dev/null | head -1 || true; }
if [ -n "$(pkg_has '@lynx-js/[[:alnum:]-]+')" ]; then STACK=lynx
elif [ -n "$(pkg_has expo)" ]; then STACK=expo
elif [ -n "$(pkg_has react-native)" ]; then STACK=react-native
elif [ -n "$(first find . -maxdepth 3 -name pubspec.yaml -not -path '*/node_modules/*')" ]; then STACK=flutter
elif [ -n "$(first find . -maxdepth 3 -name '*.xcodeproj')" ] && [ -z "$(pkg_has react)" ]; then STACK=swiftui
elif [ -n "$(first find . -maxdepth 3 \( -name build.gradle -o -name build.gradle.kts \) -not -path '*/node_modules/*')" ] \
     && [ -z "$(pkg_has react)" ]; then STACK=android
elif [ -n "$(pkg_has 'next|react|vue|svelte|astro|solid-js')" ]; then STACK=web
fi

# ── tokens · components: 프로젝트 파일 ──
while IFS= read -r f; do [ -n "$f" ] && add tokens file "${f#./}"; done < <(
    find . -maxdepth 7 \( -path '*/node_modules' -o -path './.git' -o -path './.ax' -o -path '*/dist' -o -path '*/build' \) -prune -o \
        -type f \( -iname 'tokens.*' -o -iname 'theme.*' -o -iname '*-theme.*' -o -iname 'design-tokens.*' -o -path '*/theme/index.*' -o -name 'tailwind.config.*' \
                   -o -name 'MASTER.md' -path '*design-system*' -o -name 'colors.xml' -path '*res/values*' \) -print 2>/dev/null | sort | head -8)
[ -f components.json ] && add components file components.json
while IFS= read -r f; do [ -n "$f" ] && add components file "${f#./}"; done < <(
    find . -maxdepth 3 -type d -name .storybook -not -path '*/node_modules/*' 2>/dev/null | head -2)
while IFS= read -r f; do [ -n "$f" ] && add components file "${f#./}"; done < <(
    find . -maxdepth 4 -type d \( -path '*/components/ui' -o -path '*/design-system' -o -path '*/shared/ui' \) \
        -not -path '*/node_modules/*' 2>/dev/null | head -4)
SPEC=""; for c in docs/design/design-spec.md design-system/design-spec.md; do [ -f "$c" ] && { SPEC="$c"; break; }; done

# ── MCP 서버 이름 — 프로젝트 .mcp.json · ~/.claude.json(전역 + 이 프로젝트) · 설치된 플러그인의 .mcp.json ──
MCP_NAMES=$( {
    [ -f .mcp.json ] && jq -r '.mcpServers // {} | keys[]' .mcp.json 2>/dev/null
    CJ="${HOME}/.claude.json"
    if [ -f "$CJ" ]; then
        jq -r --arg p "$PROJECT_ROOT" '(.mcpServers // {} | keys[]), (.projects[$p].mcpServers // {} | keys[])' "$CJ" 2>/dev/null
    fi
    find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" -maxdepth 6 -name .mcp.json -not -path '*/.trash/*' 2>/dev/null \
        | while IFS= read -r m; do jq -r '(.mcpServers // .) | keys[]' "$m" 2>/dev/null; done
} | tr '[:upper:]' '[:lower:]' | sort -u ) || true   # 플러그인 디렉토리가 없으면 find 가 1 — 이름이 없을 뿐이에요
while IFS= read -r n; do
    [ -n "$n" ] || continue
    case "$n" in
        *seed*|*chakra*|*storybook*|*mantine*|*mui*) add components "mcp:$n" "디자인 시스템 문서·컴포넌트"
                                       add tokens "mcp:$n" "디자인 시스템 토큰 이름" ;;
        *figma*)                       add tokens "mcp:$n" "get_variable_defs · search_design_system (Figma 파일 키 필요)"
                                       add reference "mcp:$n" "get_screenshot" ;;
        *shadcn*|*magic*|*21st*)       add components "mcp:$n" "레지스트리 검색·설치" ;;
        *mobbin*|*uibowl*|*refero*|*lazyweb*) add reference "mcp:$n" "화면·패턴 레퍼런스" ;;
        *playwright*|*chrome-devtools*) add render "mcp:$n" "브라우저 렌더·evaluate" ;;
        *ios-simulator*|*xcodebuild*|*mcp-connect*) add render "mcp:$n" "시뮬레이터 캡처" ;;
    esac
done <<< "$MCP_NAMES"

# ── render · measure: 명령 ──
command -v agent-browser >/dev/null 2>&1 && add render cli:agent-browser "웹 스크린샷 · 픽셀 diff"
{ [ -x node_modules/.bin/playwright ] || command -v playwright >/dev/null 2>&1; } && add render cli:playwright "웹 스크린샷 · toHaveScreenshot"
command -v xcrun >/dev/null 2>&1 && xcrun simctl help >/dev/null 2>&1 && add render cli:simctl "iOS 시뮬레이터 캡처 · 딥링크"
command -v adb >/dev/null 2>&1 && add render cli:adb "Android 캡처 · 딥링크"
if goax_py_ok && python3 -c 'import PIL' >/dev/null 2>&1; then add measure python:pillow "screen-measure.sh (스캔라인 · 전후 diff)"; fi
command -v impeccable >/dev/null 2>&1 && add measure cli:impeccable "impeccable detect --json"

RESULT=$(printf '%s' "$ROWS" | jq -Rn --arg stack "$STACK" --arg spec "$SPEC" '
    [inputs | select(length > 0) | split("\t") | {slot: .[0], provider: .[1], detail: .[2]}] as $r
    | ["tokens","components","reference","render","measure"] as $slots
    | {stack: $stack,
       slots: (reduce $slots[] as $s ({}; .[$s] = [$r[] | select(.slot == $s) | {provider, detail}])),
       spec: (if $spec == "" then null else $spec end),
       empty: [$slots[] as $s | select(([$r[] | select(.slot == $s)] | length) == 0) | $s]}')

if [ "$JSON_MODE" = true ]; then
    EMPTY=$(printf '%s' "$RESULT" | jq -r '.empty | join(", ")')
    json_output ok "$RESULT" "스택 ${STACK}${EMPTY:+ · 빈 슬롯: $EMPTY (screen skill 의 references/capabilities.md 대체 수단으로)}"
else
    printf '[goax] design-caps — 스택 %s · spec %s\n' "$STACK" "${SPEC:-없음}"
    printf '%s' "$RESULT" | jq -r '.slots | to_entries[] | "  \(.key): " + (if (.value | length) == 0 then "(없음)" else (.value | map(if .provider == "file" then .detail else .provider end) | join(", ")) end)'
fi
exit "$EXIT_OK"
