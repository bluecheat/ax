#!/usr/bin/env bash
# .ax/scripts/bash/screen-measure.sh — 스크린샷을 픽셀로 재요 (스캔라인 구간 · 전후 diff)
#
# 왜: "어색하다" 는 대개 같은 역할 부품이 화면마다 다른 수치예요 (주 버튼 40 과 52, 카드 안쪽 16·20).
#   눈대중 지적은 합의가 안 되고 숫자 지적은 바로 고쳐져요. 스크린샷은 물리 픽셀이라 논리 폭으로 배율부터 구해요.
#   도구가 줄여 보여 준 이미지가 아니라 **원본 파일**로 재요.
#
# Usage:
#   bash screen-measure.sh --image shot.png --logical-width 390 --x 25,60,195 [--y 120] [--min 2] [--json]
#       세로선(x)·가로선(y)을 따라 색이 바뀌는 구간을 pt 로 내요. 면(버튼·카드) 가장자리나 여백 위에 선을 그어요 —
#       글자 위를 지나면 잘게 쪼개져요. --min 보다 짧은 구간은 버려요 (안티에일리어싱).
#   bash screen-measure.sh --diff before.png after.png [--crop-top 140] [--crop-bottom 100] [--json]
#       두 스크린샷이 같은지 — 다르면 바뀐 영역(bbox, px). 상태바 시계·홈 인디케이터는 잘라내고 비교해요.
#
# Output (--json):
#   scan: {"status":"ok","result":{"image":"…","scale":3.0,"lines":[{"axis":"x","at":25,
#            "segments":[{"start":0.0,"length":59.0,"rgb":[255,255,255]},…]}]},…}
#   diff: {"status":"ok","result":{"same":false,"bbox":[x0,y0,x1,y1]|null,"size":[w,h]},…}
# Exit: 0 ok · 1 error (파일 없음 · 크기 다름 · 인자) · 2 skipped (python3 또는 Pillow 없음)
set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false
IMAGE=""; LW=""; XS=""; YS=""; MIN=2; DIFF_A=""; DIFF_B=""; CT=0; CB=0
while [ $# -gt 0 ]; do
    if parse_common_opts "$1"; then shift; continue; fi
    case "$1" in
        --image)         IMAGE="${2:-}"; shift 2 ;;
        --logical-width) LW="${2:-}"; shift 2 ;;
        --x)             XS="${2:-}"; shift 2 ;;
        --y)             YS="${2:-}"; shift 2 ;;
        --min)           MIN="${2:-}"; shift 2 ;;
        --diff)          DIFF_A="${2:-}"; DIFF_B="${3:-}"; shift 3 || { goax_error "--diff 는 파일 두 개예요"; exit "$EXIT_ERROR"; } ;;
        --crop-top)      CT="${2:-0}"; shift 2 ;;
        --crop-bottom)   CB="${2:-0}"; shift 2 ;;
        *) goax_error "알 수 없는 옵션: $1 — --help 로 사용법을 봐요"; exit "$EXIT_ERROR" ;;
    esac
done
if [ "$SHOW_HELP" = true ]; then goax_help "${BASH_SOURCE[0]}"; exit "$EXIT_OK"; fi
fail() { [ "$JSON_MODE" = true ] && json_error "$1"; goax_error "$1"; exit "$EXIT_ERROR"; }

if ! command -v jq >/dev/null 2>&1; then
    goax_warn "jq 가 필요해요 — brew install jq 또는 apt-get install jq"; exit "$EXIT_SKIPPED"
fi
if ! goax_py_ok || ! python3 -c 'import PIL' >/dev/null 2>&1; then
    MSG="python3 와 Pillow 가 있어야 재요 — pip install pillow. 없으면 스크린샷을 눈으로 보고 리포트에 \"실측 아님\" 으로 적어요"
    [ "$JSON_MODE" = true ] && json_skip "$MSG"
    goax_warn "$MSG"; exit "$EXIT_SKIPPED"
fi

num_list() { printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?(,[0-9]+(\.[0-9]+)?)*$'; }
if [ -n "$DIFF_A" ]; then
    [ -f "$DIFF_A" ] && [ -f "$DIFF_B" ] || fail "--diff 의 파일이 없어요: ${DIFF_A} ${DIFF_B}"
    case "$CT$CB" in *[!0-9]*) fail "--crop-top/--crop-bottom 은 px 정수예요" ;; esac
    MODE=diff
else
    [ -f "$IMAGE" ] || fail "--image 파일이 없어요: ${IMAGE:-(빈 값)} — 원본 스크린샷 경로를 줘요"
    num_list "$LW" || fail "--logical-width 는 기기 논리 폭(pt·dp·CSS px)이에요 — 예: iPhone 15 는 393, 웹 뷰포트는 그 폭"
    [ -n "$XS$YS" ] || fail "--x 나 --y 중 하나는 줘요 (pt, 쉼표 구분) — 예: --x 20,195"
    { [ -z "$XS" ] || num_list "$XS"; } && { [ -z "$YS" ] || num_list "$YS"; } || fail "--x/--y 는 쉼표로 구분한 숫자예요"
    num_list "$MIN" || fail "--min 은 숫자예요"
    MODE=scan
fi

RESULT=$(MODE="$MODE" IMG="$IMAGE" LW="$LW" XS="$XS" YS="$YS" MINLEN="$MIN" A="$DIFF_A" B="$DIFF_B" CT="$CT" CB="$CB" python3 - <<'PY'
import json, os, sys
from PIL import Image, ImageChops
e = os.environ
if e["MODE"] == "diff":
    a = Image.open(e["A"]).convert("RGB"); b = Image.open(e["B"]).convert("RGB")
    if a.size != b.size:
        print(json.dumps({"error": "크기가 달라요: %s vs %s — 같은 기기·뷰포트로 다시 찍어요" % (a.size, b.size)})); sys.exit(0)
    w, h = a.size; ct, cb = int(e["CT"]), int(e["CB"])
    box = (0, ct, w, max(ct, h - cb))
    bb = ImageChops.difference(a.crop(box), b.crop(box)).getbbox()
    if bb: bb = [bb[0], bb[1] + ct, bb[2], bb[3] + ct]
    print(json.dumps({"same": bb is None, "bbox": bb, "size": [w, h]})); sys.exit(0)
img = Image.open(e["IMG"]).convert("RGB"); W, H = img.size
s = W / float(e["LW"]); minlen = float(e["MINLEN"])
def scan(axis, at):
    n = H if axis == "x" else W
    px = (lambda i: img.getpixel((min(W - 1, int(at * s)), i))) if axis == "x" else (lambda i: img.getpixel((i, min(H - 1, int(at * s)))))
    segs, prev, start = [], None, 0
    for i in range(n + 1):
        key = None if i == n else tuple(v // 6 for v in px(i))   # 양자화 — 안티에일리어싱 노이즈를 줄여요
        if key != prev:
            if prev is not None and (i - start) / s >= minlen:
                segs.append({"start": round(start / s, 1), "length": round((i - start) / s, 1), "rgb": list(px(start))})
            prev, start = key, i
    return {"axis": axis, "at": at, "segments": segs}
lines = [scan("x", float(v)) for v in e["XS"].split(",") if v] + [scan("y", float(v)) for v in e["YS"].split(",") if v]
print(json.dumps({"image": e["IMG"], "scale": round(s, 3), "lines": lines}))
PY
) || fail "측정 스크립트가 실패했어요 — 이미지가 PNG/JPEG 인지 봐요"
ERR=$(printf '%s' "$RESULT" | jq -r '.error // empty')
[ -z "$ERR" ] || fail "$ERR"

if [ "$JSON_MODE" = true ]; then
    if [ "$MODE" = diff ]; then
        json_output ok "$RESULT" "$(printf '%s' "$RESULT" | jq -r 'if .same then "전후 픽셀 동일" else "바뀐 영역 \(.bbox) — 그 자리를 눈으로 봐요 (애니메이션·스피너면 무시)" end')"
    else
        json_output ok "$RESULT" "배율 $(printf '%s' "$RESULT" | jq -r .scale) — 같은 역할 부품을 다른 화면에서도 재서 비교해요"
    fi
elif [ "$MODE" = diff ]; then
    printf '%s' "$RESULT" | jq -r 'if .same then "[goax] 전후 픽셀 동일" else "[goax] 바뀐 영역 bbox=\(.bbox)" end'
else
    printf '%s' "$RESULT" | jq -r '"[goax] 배율 \(.scale)", (.lines[] | "\(.axis)=\(.at)", (.segments[] | "  \(.start) +\(.length)  rgb\(.rgb)"))'
fi
exit "$EXIT_OK"
