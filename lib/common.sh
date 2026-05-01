# common.sh — say/warn/die 공통 함수
say() { printf "\033[36m[goax]\033[0m %s\n" "$*"; }
warn() { printf "\033[33m[goax]\033[0m %s\n" "$*" >&2; }
die() { printf "\033[31m[goax]\033[0m %s\n" "$*" >&2; exit 1; }
