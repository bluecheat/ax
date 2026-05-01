# common.sh — say/warn/die + 박스/배너 헬퍼
say() { printf "\033[36m[goax]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[goax]\033[0m %s\n" "$*" >&2; }
die() { printf "\033[31m[goax]\033[0m %s\n" "$*" >&2; exit 1; }

# 색상 단축
c_dim()  { printf "\033[2m%s\033[0m" "$*"; }
c_b()    { printf "\033[1m%s\033[0m" "$*"; }
c_cyan() { printf "\033[36m%s\033[0m" "$*"; }
c_grn()  { printf "\033[32m%s\033[0m" "$*"; }
c_ylw()  { printf "\033[33m%s\033[0m" "$*"; }
c_red()  { printf "\033[31m%s\033[0m" "$*"; }
c_mag()  { printf "\033[35m%s\033[0m" "$*"; }

# 가로줄
hr() {
    local ch="${1:-─}" w="${2:-60}"
    local i=0 line=""
    while [ "$i" -lt "$w" ]; do line="$line$ch"; i=$((i+1)); done
    printf "\033[2m%s\033[0m\n" "$line"
}

# 섹션 헤더 — 이모지 + 굵은 제목 + 얇은 구분선
section() {
    local emoji="$1" title="$2"
    printf "\n\033[1m%s %s\033[0m\n" "$emoji" "$title"
    hr "─" 60
}

# 라벨: 값 정렬 (라벨 18자)
kv() {
    local label="$1" value="$2"
    printf "  \033[2m%-18s\033[0m %s\n" "$label" "$value"
}

# 체크/십자
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; }
dot()  { printf "  \033[2m·\033[0m %s\n" "$*"; }
