# tests/lib/zsh-traps.awk — smoke §69 가 SKILL.md 등의 bash 펜스 블록에 돌려요 (사용자 셸은 대개 zsh)
# 입력: bash 펜스 블록 한 파일. 출력: "<줄번호>\t<사유>\t<원문>"
# zsh 가 bash 와 다르게 읽는 두 모양만 봐요 (따옴표 안 · [[ ]] · (( )) · 주석은 지우고):
#   1) = 로 시작하는 단어 — zsh 의 EQUALS 확장이 `=cmd` 를 명령 경로로 바꿔요. `[ "$a" == b ]` · `echo ===` 가 "= not found"
#   2) echo 로 변수를 jq 에 넘김 — zsh echo 는 문자열 속 \n 을 진짜 줄바꿈으로 풀어 JSON 이 깨져요
{
    raw = $0; s = $0
    if (s ~ /^[ \t]*echo[ \t]+(-[[:alpha:]]+[ \t]+)?"?\$\{?[[:alpha:]_][[:alnum:]_]*\}?"?[ \t]*\|[ \t]*jq/ \
        || s ~ /[;&|(][ \t]*echo[ \t]+(-[[:alpha:]]+[ \t]+)?"?\$\{?[[:alpha:]_][[:alnum:]_]*\}?"?[ \t]*\|[ \t]*jq/)
        printf "%d\techo-jq\t%s\n", NR, raw
    gsub(/'[^']*'/, "''", s)
    gsub(/"([^"\\]|\\.)*"/, "\"\"", s)
    gsub(/\[\[[^]]*\]\]/, "", s)
    gsub(/\(\([^)]*\)\)/, "", s)
    sub(/(^|[ \t])#.*$/, "", s)
    n = split(s, w, /[ \t;|&()<>]+/)
    for (i = 1; i <= n; i++) if (w[i] ~ /^=[^ \t]/) { printf "%d\tequals\t%s\n", NR, raw; break }
}
