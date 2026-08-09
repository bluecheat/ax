#!/usr/bin/env bash
# .claude/skills/goax-release/bump-version.sh
# goax 버전 3중(4곳) 동기화 bump + 검증 — 릴리즈 스킬의 결정론 파트.
#   4곳: VERSION · .claude-plugin/plugin.json · marketplace.json(top + plugins[0])
# formatting 보존을 위해 jq rewrite 대신 version 필드만 targeted sed.
#
# 사용:
#   bump-version.sh 0.2.3          # 명시 버전으로 bump
#   bump-version.sh --next patch   # 현재 VERSION 에서 patch++ 계산 후 bump
#   bump-version.sh --next minor   # minor++ (patch=0)
#   bump-version.sh --next major   # major++ (minor=patch=0)
#   bump-version.sh --check        # bump 안 함 — 4곳 일치만 검증
#   bump-version.sh ... --dry-run  # 계산만, 파일 안 씀
#   bump-version.sh ... --json     # JSON 출력
#   bump-version.sh --help
#
# exit: 0 ok / 1 error / 2 skipped(검증만)

set -euo pipefail

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; CHECK=false
TARGET=""; NEXT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --check) CHECK=true ;;
        --next) shift; [ $# -eq 0 ] && { echo "[goax] ERROR: --next requires patch|minor|major" >&2; exit 1; }; NEXT="$1" ;;
        --help|-h) SHOW_HELP=true ;;
        -*) echo "[goax] ERROR: unknown option: $1" >&2; exit 1 ;;
        *) TARGET="$1" ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
VFILE="VERSION"
PJSON=".claude-plugin/plugin.json"
MJSON=".claude-plugin/marketplace.json"
for f in "$VFILE" "$PJSON" "$MJSON"; do
    [ -f "$f" ] || { echo "[goax] ERROR: $f 없음 — goax repo 루트에서 실행하세요" >&2; exit 1; }
done

CUR=$(tr -d ' \n' < "$VFILE")

# 현재 4곳 값 수집
pj=$(grep -E '"version"' "$PJSON" | head -1 | sed -E 's/.*"version": *"([^"]+)".*/\1/')
mj_top=$(jq -r '.version' "$MJSON" 2>/dev/null || echo "?")
mj_p0=$(jq -r '.plugins[0].version' "$MJSON" 2>/dev/null || echo "?")

emit() {
    # $1 status, $2 old, $3 new, $4 next_step
    if [ "$JSON_MODE" = true ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -nc --arg s "$1" --arg o "$2" --arg n "$3" --arg ns "$4" \
                --arg pj "$pj" --arg mt "$mj_top" --arg mp "$mj_p0" \
                '{status:$s, result:{old:$o, new:$n, files:{VERSION:$o, plugin:$pj, marketplace_top:$mt, marketplace_plugin:$mp}}, next_step:$ns}'
        else
            printf '{"status":"%s","result":{"old":"%s","new":"%s"},"next_step":"%s"}\n' "$1" "$2" "$3" "$4"
        fi
    else
        printf '[goax] %s: %s → %s — %s\n' "$1" "$2" "$3" "$4" >&2
    fi
}

# --check: 4곳 일치 검증만
if [ "$CHECK" = true ]; then
    if [ "$CUR" = "$pj" ] && [ "$CUR" = "$mj_top" ] && [ "$CUR" = "$mj_p0" ]; then
        emit "ok" "$CUR" "$CUR" "4곳 모두 일치 ($CUR)"
        exit 0
    else
        echo "[goax] MISMATCH — VERSION=$CUR plugin=$pj mkt.top=$mj_top mkt[0]=$mj_p0" >&2
        [ "$JSON_MODE" = true ] && emit "error" "$CUR" "$CUR" "버전 불일치"
        exit 1
    fi
fi

# 대상 버전 결정
NEW=""
if [ -n "$TARGET" ]; then
    NEW="$TARGET"
elif [ -n "$NEXT" ]; then
    case "$CUR" in
        [0-9]*.[0-9]*.[0-9]*) ;;
        *) echo "[goax] ERROR: 현재 VERSION '$CUR' 가 X.Y.Z 형식 아님" >&2; exit 1 ;;
    esac
    MA=${CUR%%.*}; rest=${CUR#*.}; MI=${rest%%.*}; PA=${rest#*.}
    case "$NEXT" in
        patch) PA=$((PA+1)) ;;
        minor) MI=$((MI+1)); PA=0 ;;
        major) MA=$((MA+1)); MI=0; PA=0 ;;
        *) echo "[goax] ERROR: --next 는 patch|minor|major" >&2; exit 1 ;;
    esac
    NEW="$MA.$MI.$PA"
else
    echo "[goax] ERROR: 버전 인자 또는 --next 필요 (예: bump-version.sh 0.2.3 / --next patch)" >&2
    exit 1
fi

# semver 형식 검증
case "$NEW" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "[goax] ERROR: '$NEW' 는 X.Y.Z 형식 아님" >&2; exit 1 ;;
esac

if [ "$NEW" = "$CUR" ]; then
    echo "[goax] WARN: 새 버전이 현재와 동일 ($CUR) — 이미 bump 됐거나 잘못된 인자" >&2
fi

if [ "$DRY_RUN" = true ]; then
    emit "ok" "$CUR" "$NEW" "dry-run — 파일 안 씀 (4곳 일괄 변경 예정)"
    exit 0
fi

# ── targeted sed bump (formatting 보존) ──
SED_RE='s/("version": ")[0-9]+\.[0-9]+\.[0-9]+(")/\1'"$NEW"'\2/'
printf '%s\n' "$NEW" > "$VFILE"
# BSD/GNU sed 호환: -i 차이 → tmp 파일 경유
sed -E "$SED_RE" "$PJSON" > "$PJSON.tmp.$$" && mv "$PJSON.tmp.$$" "$PJSON"
sed -E "$SED_RE" "$MJSON" > "$MJSON.tmp.$$" && mv "$MJSON.tmp.$$" "$MJSON"

# JSON 유효성 + 4곳 일치 재검증
if command -v jq >/dev/null 2>&1; then
    jq -e . "$PJSON" >/dev/null || { echo "[goax] ERROR: plugin.json 깨짐" >&2; exit 1; }
    jq -e . "$MJSON" >/dev/null || { echo "[goax] ERROR: marketplace.json 깨짐" >&2; exit 1; }
fi
n_v=$(tr -d ' \n' < "$VFILE")
n_pj=$(grep -E '"version"' "$PJSON" | head -1 | sed -E 's/.*"version": *"([^"]+)".*/\1/')
n_mt=$(jq -r '.version' "$MJSON" 2>/dev/null || echo "?")
n_mp=$(jq -r '.plugins[0].version' "$MJSON" 2>/dev/null || echo "?")
pj="$n_pj"; mj_top="$n_mt"; mj_p0="$n_mp"
if [ "$n_v" = "$NEW" ] && [ "$n_pj" = "$NEW" ] && [ "$n_mt" = "$NEW" ] && [ "$n_mp" = "$NEW" ]; then
    emit "ok" "$CUR" "$NEW" "4곳 bump 완료 — 다음: changelog/$NEW.md 작성 → smoke → commit"
    exit 0
else
    echo "[goax] ERROR: bump 후 불일치 VERSION=$n_v plugin=$n_pj mkt.top=$n_mt mkt[0]=$n_mp" >&2
    exit 1
fi
