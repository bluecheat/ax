# common.sh — say/warn/die 공통 함수
say() { printf "\033[36m[ax-first]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[ax-first]\033[0m %s\n" "$*" >&2; }
die() { printf "\033[31m[ax-first]\033[0m %s\n" "$*" >&2; exit 1; }
