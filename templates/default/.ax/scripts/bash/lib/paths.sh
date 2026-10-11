#!/usr/bin/env bash
# .ax/scripts/bash/lib/paths.sh — 경로·설정·스택 — 경로 정규화, yaml 목록, 글롭 매칭, 룰 매칭, 스택 파일, 작업 트리 지문
# common.sh 가 source 해요. 직접 source 하지 않아요.
# shellcheck disable=SC2034  # 여기서 정의한 변수는 common.sh 를 source 한 스크립트가 써요

# ─── 경로 정규화 / 경계 매칭 ────────────────────────────────────────
# 보호 경로 검사처럼 "이 경로가 저 경로 안에 있나" 를 판정하는 곳은 반드시 이 둘을
# 거쳐야 해요. 문자열 접두 비교만 하면 `./x`·`a/../x` 같은 표기 변형으로 우회되고,
# `CLAUDE.md.bak` 같은 무관 파일이 오탐돼요.
#
# goax_normalize_path <path> [base]
#   렉시컬 정규화 — `.`·`..`·중복 슬래시 해소 후 절대경로 출력.
#   파일시스템을 건드리지 않아요 (아직 없는 파일도 처리 — Write 는 새 파일을 만듦).
#   realpath 비의존 = macOS/Linux 동일 동작. bash 3.2 호환.
# 이번 스택의 기준 커밋을 내요 — base 인자(브랜치나 커밋)와 HEAD 의 merge-base 예요.
# 인자가 없으면 origin/HEAD, main, master 순서로 찾아요. 못 찾으면 아무것도 내지 않고 return 1 이에요.
goax_stack_base() {
    local root="${1:-}" arg="${2:-}" cand b
    git -C "$root" rev-parse --verify -q HEAD >/dev/null 2>&1 || return 1
    if [ -n "$arg" ]; then
        git -C "$root" merge-base HEAD "$arg" 2>/dev/null || return 1
        return 0
    fi
    for cand in origin/HEAD main master; do
        git -C "$root" rev-parse --verify -q "$cand" >/dev/null 2>&1 || continue
        b=$(git -C "$root" merge-base HEAD "$cand" 2>/dev/null || true)
        [ -n "$b" ] && { printf '%s\n' "$b"; return 0; }
    done
    return 1
}

# 이번 스택에서 바뀐 파일을 프로젝트 기준 상대 경로로 내요. `.ax/` 는 빼요. rules-audit-scope 와 lanes-dispatch 가 함께 써요.
# 범위: base...HEAD, 워킹 트리 변경(스테이징 포함), 추적 안 되는 새 파일. $3 에 "A" 를 주면 새로 생긴 파일만 내요
goax_stack_files() {
    local root="${1:-}" base="${2:-}" filt="${3:-ACMR}"
    { [ -n "$base" ] && git -C "$root" diff --relative --name-only --diff-filter="$filt" "$base" HEAD 2>/dev/null
      git -C "$root" diff --relative --name-only --diff-filter="$filt" HEAD 2>/dev/null
      git -C "$root" ls-files --others --exclude-standard 2>/dev/null; } | grep -v '^\.ax/' | awk 'NF && !s[$0]++' | LC_ALL=C sort || true
}

# config.yml commands.<key> 의 명령 문자열을 내요. zero-verify.sh 와 tasks-gate.sh G8 이 함께 써요.
# 규칙은 YAML 과 같아요.
#   - 값이 " 나 ' 로 시작하면 짝이 되는 따옴표까지가 값이에요. 따옴표 안의 # 은 값의 일부예요.
#   - 값이 # 로 시작하면 빈 값이에요.
#   - 그 밖에는 공백 다음 첫 # 앞까지가 값이에요.
goax_config_cmd() {
    local cfg="${1:-}" key="${2:-}"
    [ -f "$cfg" ] || return 0
    grep -E "^[[:space:]]+${key}:" "$cfg" 2>/dev/null | head -1 \
        | sed -E "s/^[[:space:]]+${key}:[[:space:]]*//" \
        | sed -E -e 's/^"([^"]*)".*$/\1/' -e t \
                 -e "s/^'([^']*)'.*\$/\1/" -e t \
                 -e 's/^#.*$//'            -e t \
                 -e 's/[[:space:]]+#.*$//' \
                 -e 's/[[:space:]]+$//'
}

# 작업 트리 내용 지문 — `.ax/` 를 뺀 프로젝트 파일 내용의 sha 앞 12자를 내요. 커밋해도 같고, 파일을 고치면 달라져요.
# 계산: HEAD 트리 목록에서 HEAD 와 다른 파일과 추적 안 되는 새 파일(ignore 제외)을 지금 내용으로 바꿔요. 파일을 쓰지 않아요.
# git 저장소가 아니거나 HEAD 가 없으면 `nogit` 을 내요. 호출하는 쪽은 이때 비교를 건너뛰어요.
goax_tree_fingerprint() {
    local root="${1:-}" f
    git -C "$root" rev-parse --verify -q HEAD >/dev/null 2>&1 || { printf 'nogit\n'; return 0; }
    {
        git -C "$root" ls-tree -r HEAD -- . 2>/dev/null | awk -F'\t' '{ n = split($1, a, " "); printf "%s\t0\t%s\n", $2, a[3] }'
        { git -C "$root" diff --name-only --relative HEAD -- . 2>/dev/null
          git -C "$root" ls-files --others --exclude-standard -- . 2>/dev/null; } | LC_ALL=C sort -u | while IFS= read -r f; do
            [ -n "$f" ] || continue
            if [ -f "$root/$f" ]; then
                printf '%s\t1\t%s\n' "$f" "$(git -C "$root" hash-object -- "$f" 2>/dev/null || echo '?')"
            else
                printf '%s\t1\t-\n' "$f"
            fi
        done
    } | awk -F'\t' '$1 !~ /^\.ax\// && $1 != ".ax"' | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n \
      | awk -F'\t' '{ v[$1] = $3; if (!($1 in seen)) { seen[$1] = 1; o[++n] = $1 } }
                     END { for (i = 1; i <= n; i++) if (v[o[i]] != "-") printf "%s\t%s\n", o[i], v[o[i]] }' \
      | { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi; } | cut -c1-12
}

goax_normalize_path() {
    local p="${1:-}" base="${2:-$PWD}" out="" seg oldIFS
    [ -z "$p" ] && return 0
    case "$p" in /*) ;; *) p="$base/$p" ;; esac
    oldIFS="$IFS"
    set -f                      # `set --` 시 glob 확장 방지
    IFS='/'
    # shellcheck disable=SC2086
    set -- $p
    IFS="$oldIFS"
    set +f
    for seg in "$@"; do
        case "$seg" in
            ''|'.') continue ;;
            '..')   out="${out%/*}" ;;
            *)      out="$out/$seg" ;;
        esac
    done
    printf '%s' "${out:-/}"
}

# goax_path_under <rel-path> <pattern>
#   rel 이 pattern 과 동일하거나 그 하위 경로면 0. 경로 경계(`/`)를 지켜서
#   `CLAUDE.md` 패턴이 `CLAUDE.md.bak` 을 잡지 않아요.
goax_path_under() {
    local rel="${1:-}" pat="${2:-}"
    [ -z "$pat" ] && return 1
    pat="${pat%/}"              # 후행 슬래시 정규화 (`.ax/hooks/` → `.ax/hooks`)
    [ "$rel" = "$pat" ] && return 0
    case "$rel" in "$pat"/*) return 0 ;; esac
    return 1
}

# goax_yaml_list <file> <key>
#   YAML 시퀀스를 들여쓰기 인식으로 추출 (awk range 연산자는 시작 라인이 종료
#   패턴에도 매칭되면 1줄로 붕괴해서 조용히 빈 값을 냄 — 보안 컨트롤에선 치명적).
#   블록 형식(`key:` + `  - v`) 과 flow 형식(`key: [a, b]`) 둘 다 지원.
goax_yaml_list() {
    local file="${1:-}" key="${2:-}"
    [ -f "$file" ] || return 0
    awk -v key="$key" '
        function ind(s,   i) { if (s ~ /^[ \t]*$/) return -1; i = match(s, /[^ \t]/); return i - 1 }
        BEGIN { inlist = 0; keyind = -1 }
        {
            t = $0; sub(/\r$/, "", t)
            if (t ~ /^[ \t]*#/ || t ~ /^[ \t]*$/) next
            i = ind(t)
            if (!inlist) {
                if (t ~ ("^[ \t]*" key ":[ \t]*$")) { inlist = 1; keyind = i; next }
                if (t ~ ("^[ \t]*" key ":[ \t]*\\[")) {
                    s = t; sub(/^[^[]*\[/, "", s); sub(/\].*$/, "", s)
                    n = split(s, arr, ",")
                    for (j = 1; j <= n; j++) {
                        v = arr[j]
                        gsub(/^[ \t\042\047]+|[ \t\042\047]+$/, "", v)
                        if (v != "") print v
                    }
                }
                next
            }
            if (i > keyind && t ~ /^[ \t]*-[ \t]+/) {
                v = t; sub(/^[ \t]*-[ \t]+/, "", v)
                sub(/[ \t]+$/, "", v)
                # 따옴표 한 쌍만 떼어요 — 끝 따옴표를 전부 지우면 `eslint --rule "x"` 가 `… "x` 로 깨져요.
                # 따옴표 값 뒤의 ` # 주석` 은 버리고, 맨 값은 ` #` 부터가 주석이에요 (YAML 과 같아요).
                q = substr(v, 1, 1)
                if (q == "\042" || q == "\047") {
                    e = length(v); while (e > 1 && substr(v, e, 1) != q) e--
                    if (e > 1) v = substr(v, 2, e - 2)
                } else sub(/[ \t]+#.*$/, "", v)
                if (v != "") print v
                next
            }
            if (i <= keyind) inlist = 0
        }
    ' "$file"
}

# _goax_yaml_list_multi <key> <file>...
#   goax_yaml_list 와 같은 규칙을 **awk 한 번**으로 여러 파일에 돌려요. 출력: `<file>\t<value>`.
#   룰 파일마다 goax_yaml_list 를 부르면 awk 가 파일 수만큼 떠요 — 모든 Edit/Read 에 걸리는 훅이라
#   룰 40개 + 모듈 10개에서 편집 한 번에 0.85초였어요 (리뷰 실측).
_goax_yaml_list_multi() {
    local key="${1:-}"; shift
    [ $# -gt 0 ] || return 0
    awk -v key="$key" '
        function ind(s,   i) { if (s ~ /^[ \t]*$/) return -1; i = match(s, /[^ \t]/); return i - 1 }
        FNR == 1 { inlist = 0; keyind = -1 }
        {
            t = $0; sub(/\r$/, "", t)
            if (t ~ /^[ \t]*#/ || t ~ /^[ \t]*$/) next
            i = ind(t)
            if (!inlist) {
                if (t ~ ("^[ \t]*" key ":[ \t]*$")) { inlist = 1; keyind = i; next }
                if (t ~ ("^[ \t]*" key ":[ \t]*\\[")) {
                    s = t; sub(/^[^[]*\[/, "", s); sub(/\].*$/, "", s)
                    n = split(s, arr, ",")
                    for (j = 1; j <= n; j++) {
                        v = arr[j]
                        gsub(/^[ \t\042\047]+|[ \t\042\047]+$/, "", v)
                        if (v != "") print FILENAME "\t" v
                    }
                }
                next
            }
            if (i > keyind && t ~ /^[ \t]*-[ \t]+/) {
                v = t; sub(/^[ \t]*-[ \t]+/, "", v)
                sub(/[ \t]+$/, "", v)
                # 따옴표 한 쌍만 떼어요 — 끝 따옴표를 전부 지우면 `eslint --rule "x"` 가 `… "x` 로 깨져요.
                # 따옴표 값 뒤의 ` # 주석` 은 버리고, 맨 값은 ` #` 부터가 주석이에요 (YAML 과 같아요).
                q = substr(v, 1, 1)
                if (q == "\042" || q == "\047") {
                    e = length(v); while (e > 1 && substr(v, e, 1) != q) e--
                    if (e > 1) v = substr(v, 2, e - 2)
                } else sub(/[ \t]+#.*$/, "", v)
                if (v != "") print FILENAME "\t" v
                next
            }
            if (i <= keyind) inlist = 0
        }
    ' "$@"
}

# goax_glob_match <glob> <path>
#   `**` 를 이해하는 glob 매칭. 0 = 매치.
#   path-scoped 룰 주입(Layer 2 module / Spirit rules)이 공유해요 —
#   훅마다 따로 구현하면 같은 룰이 훅에 따라 다르게 매칭돼요.
#   python3 가 있으면 정확히, 없으면 보수적 substring 으로 degrade.
goax_glob_match() {
    local pattern="${1:-}" path="${2:-}"
    [ -z "$pattern" ] && return 1
    if goax_py_ok; then
        python3 - "$pattern" "$path" <<'PYGLOB' 2>/dev/null
import sys, re
pattern, path = sys.argv[1], sys.argv[2]
def glob_to_regex(g):
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if c == '*':
            if i + 1 < n and g[i+1] == '*':
                out.append('.*'); i += 2
                if i < n and g[i] == '/': i += 1
                continue
            out.append('[^/]*')
        elif c == '?':
            out.append('[^/]')
        elif c in r'.+(){}[]|^$\\':
            out.append('\\' + c)
        else:
            out.append(c)
        i += 1
    return '^' + ''.join(out) + '$'
sys.exit(0 if re.match(glob_to_regex(pattern), path) else 1)
PYGLOB
        return $?
    fi
    # python3 없음 — 셸 case 글롭으로 먼저 봐요 (case 의 `*` 는 `/` 도 넘어서 `**/*.kt` 가 `src/a.kt` 에 맞아요).
    # 예전엔 substring 만 봐서 `**/*.kt` 를 글자 그대로 `*.kt` 로 찾다가 lint_file · quality_configs 가 조용히 꺼졌어요 (리뷰 실측).
    # shellcheck disable=SC2254
    case "$path" in $pattern) return 0 ;; esac
    # 그다음 `**/` 접두를 걷어낸 나머지로 substring 판정 (보수적)
    local tail="${pattern##*\*\*/}"
    case "$path" in *"$tail"*) return 0 ;; esac
    return 1
}

# goax_rules_matching <rules-dir> <rel-path>
#   frontmatter 의 `paths:` 글롭이 rel-path 에 매칭되는 룰 파일들의 상대 경로를 출력.
#   본문이 아니라 **경로만** 돌려줘요 (B-pointer) — 룰 전문을 컨텍스트에 밀어 넣으면
#   편집 한 번에 수천 토큰이 들어가고, 정작 필요 없는 룰까지 같이 들어와요.
goax_rules_matching() {
    local dir="${1:-}" rel="${2:-}" prefix="${3:-}" f
    [ -d "$dir" ] || return 0
    local files=()
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in README.md) continue ;; esac
        files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || return 0
    _goax_yaml_list_multi paths "${files[@]}" \
        | awk -F '\t' -v p="$prefix" '{ n = $1; sub(/.*\//, "", n); print p n "\t" $2 }' \
        | goax_glob_owners "$rel"
}

# goax_module_rules_matching <project-root> <rel-path>
#   `.ax/modules/<name>/rules.md` 중 `paths:` 가 rel-path 에 매칭되는 모듈 이름을 출력해요.
#   `applies_to` 에 `code` 가 없으면 편집 대상이 아니라 빼요 (pr/commit/review 전용 룰). 필드가 아예 없으면
#   하위호환으로 포함. module-rules-inject.sh(주입)와 rule-read-gate.sh(게이트)가 같이 써요 —
#   둘이 따로 매칭하면 "주입은 했는데 게이트는 안 거는" 룰이 생겨요.
goax_module_rules_matching() {
    local root="${1:-}" rel="${2:-}" f excl
    [ -d "$root/.ax/modules" ] || return 0
    local files=()
    for f in "$root"/.ax/modules/*/rules.md; do
        [ -f "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || return 0
    # applies_to 가 있는데 code 가 없는 파일은 빼요 (없으면 하위호환으로 포함)
    excl=$(_goax_yaml_list_multi applies_to "${files[@]}" \
        | awk -F '\t' '{ has[$1] = 1; if ($2 == "code") code[$1] = 1 } END { for (f in has) if (!(f in code)) print f }')
    _goax_yaml_list_multi paths "${files[@]}" \
        | GOAX_EXCL="$excl" awk -F '\t' '
            BEGIN { n = split(ENVIRON["GOAX_EXCL"], E, "\n"); for (i = 1; i <= n; i++) if (E[i] != "") X[E[i]] = 1 }
            !($1 in X) { m = $1; sub(/\/rules\.md$/, "", m); sub(/.*\//, "", m); print m "\t" $2 }' \
        | goax_glob_owners "$rel"
}

# goax_always_loaded <project-root>
#   세션 시작부터 컨텍스트에 실리는 파일의 프로젝트 기준 상대 경로를 실린 순서대로 출력해요.
#   CLAUDE.md · CLAUDE.local.md 에서 시작해 `@경로` import 를 5단계까지 따라가요 (포함한 파일 기준 상대경로).
#   프로젝트 밖 경로(`/`·`~` 시작)는 세지 않아요. doctor-scan.sh 와 rules-budget.sh 가 같이 써요.
goax_always_loaded() {
    local root="${1:-.}"
    ( cd "$root" 2>/dev/null || exit 0
      seen=""
      walk() {
          local f="$1" d="$2" dir inc
          [ -f "$f" ] || return 0
          case "
$seen" in *"
$f
"*) return 0 ;; esac
          seen="${seen}${f}
"
          printf '%s\n' "$f"
          [ "$d" -ge 5 ] && return 0
          dir=$(dirname "$f")
          while IFS= read -r inc; do
              [ -n "$inc" ] || continue
              case "$inc" in /*|~*) continue ;; esac
              if [ "$dir" = "." ]; then walk "$inc" $((d + 1)); else walk "$dir/$inc" $((d + 1)); fi
          done < <(sed -nE 's#^@(\./)?([^[:space:]]+)[[:space:]]*$#\2#p' "$f" 2>/dev/null)
      }
      for c in CLAUDE.md CLAUDE.local.md; do walk "$c" 0; done )
}

# goax_imported_paths <project-root>
#   CLAUDE.md · AGENTS.md 가 `@<경로>` 로 import 하는 파일의 프로젝트 기준 상대 경로를 출력해요.
#   이 파일들은 세션 시작부터 컨텍스트에 있어서 "Read 했나" 를 따질 필요가 없어요 (rule-read-gate).
goax_imported_paths() {
    local root="${1:-}" f
    for f in "$root/CLAUDE.md" "$root/AGENTS.md"; do
        [ -f "$f" ] || continue
        sed -nE 's#^@(\./)?([^[:space:]]+)[[:space:]]*$#\2#p' "$f"
    done | sort -u
}
