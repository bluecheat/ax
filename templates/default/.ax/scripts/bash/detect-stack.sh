#!/usr/bin/env bash
# .ax/scripts/bash/detect-stack.sh — 프로젝트가 **선언한** 빌드·테스트·lint 진입점에서 config.yml commands 후보를 뽑아요
#
# 왜: 모델이 기억으로 명령을 지으면 다른 패키지 매니저·없는 스크립트가 들어가요. 그래서 프로젝트에 적힌 것만 읽어요 —
#   package.json scripts·lockfile · Makefile/justfile/Taskfile 타깃 · gradlew·mvnw · 언어 매니페스트와 거기 선언된 도구.
#   모르는 생태계는 후보가 비어요 (그때는 사람에게 물어요). 후보는 제안이고, 적용은 사용자 확인 뒤 config-set.sh 로.
#
# Usage:
#   bash detect-stack.sh [--json] [--help]
#
# Output (--json):
#   {"status":"ok","result":{
#     "manifests":["package.json","pnpm-lock.yaml",…],            # 루트에서 본 매니페스트·래퍼
#     "workspace":{"monorepo":true,"signals":["pnpm-workspace.yaml",…],"members":["apps/web",…]},   # 최대 20
#     "candidates":{"build":["pnpm build"],"test":[…],"lint":[…],"typecheck":[…],
#                   "lint_file":["**/*.ts => pnpm exec eslint --quiet {file}",…]},
#     "current":{"build":"…","test":"…","lint":"…","typecheck":"…"}},…}
#   candidates 는 앞에 있을수록 프로젝트가 직접 적은 것(스크립트·타깃)이고, 뒤로 갈수록 매니페스트 관례예요.
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
command -v jq >/dev/null 2>&1 || { [ "$JSON_MODE" = true ] && json_skip "jq 없음"; exit "$EXIT_SKIPPED"; }
ROOT=$(find_project_root) || exit "$EXIT_ERROR"
cd "$ROOT"

MANIFESTS=(); SIGNALS=(); MEMBERS=()
B=(); T=(); L=(); TC=(); LF=()
has() { [ -e "$1" ]; }
add() { local arr="$1"; shift; eval "$arr+=(\"\$*\")"; }
note() { MANIFESTS+=("$1"); }

# ── Node — package.json scripts 가 1순위 ─────────────────────────────
if has package.json && jq -e . package.json >/dev/null 2>&1; then
    note package.json
    PM=npm; RUN="npm run"; EXEC="npx"
    if has pnpm-lock.yaml; then PM=pnpm; RUN="pnpm"; EXEC="pnpm exec"; note pnpm-lock.yaml
    elif has yarn.lock; then PM=yarn; RUN="yarn"; EXEC="yarn"; note yarn.lock
    elif has bun.lockb || has bun.lock; then PM=bun; RUN="bun run"; EXEC="bunx"; note bun.lock
    elif has package-lock.json; then note package-lock.json; fi
    : "$PM"
    while IFS= read -r s; do
        case "$s" in
            build|build:*) add B "$RUN $s" ;;
            test|test:unit|test:ci) add T "$RUN $s" ;;
            lint|lint:*) add L "$RUN $s" ;;
            typecheck|type-check|tsc|check-types|types) add TC "$RUN $s" ;;
        esac
    done < <(jq -r '(.scripts // {}) | keys[]' package.json 2>/dev/null)
    DEPS=$(jq -r '[(.dependencies // {}), (.devDependencies // {})] | add | keys[]?' package.json 2>/dev/null || true)
    if printf '%s\n' "$DEPS" | grep -qx eslint; then
        for e in ts tsx js jsx; do add LF "**/*.$e => $EXEC eslint --quiet {file}"; done
    fi
    if printf '%s\n' "$DEPS" | grep -qx '@biomejs/biome'; then
        for e in ts tsx js jsx json; do add LF "**/*.$e => $EXEC biome check {file}"; done
    fi
    if [ "${#TC[@]}" -eq 0 ] && printf '%s\n' "$DEPS" | grep -qx typescript && has tsconfig.json; then add TC "$EXEC tsc --noEmit"; fi
    ws=$(jq -r '(.workspaces | if type == "object" then .packages else . end) // [] | .[]?' package.json 2>/dev/null || true)
    [ -n "$ws" ] && SIGNALS+=("package.json workspaces")
fi
for f in pnpm-workspace.yaml lerna.json nx.json turbo.json rush.json go.work; do has "$f" && SIGNALS+=("$f"); done

# ── 사람이 적은 작업 러너 — Makefile · justfile · Taskfile ────────────
targets() {   # targets <file> <regex> → 타깃 이름들
    grep -E "$2" "$1" 2>/dev/null | sed -E 's/^([[:alnum:]_.-]+).*/\1/' | sort -u
}
for mf in Makefile makefile GNUmakefile; do
    has "$mf" || continue; note "$mf"
    while IFS= read -r t; do
        case "$t" in build) add B "make build" ;; test|check) add T "make $t" ;; lint) add L "make lint" ;; typecheck|type-check) add TC "make $t" ;; esac
    done < <(targets "$mf" '^[[:alnum:]_.-]+:([^=]|$)')
    break
done
for jf in justfile Justfile .justfile; do
    has "$jf" || continue; note "$jf"
    while IFS= read -r t; do
        case "$t" in build) add B "just build" ;; test) add T "just test" ;; lint) add L "just lint" ;; typecheck) add TC "just typecheck" ;; esac
    done < <(targets "$jf" '^[[:alnum:]_-]+( [^:]*)?:')
    break
done
for tf in Taskfile.yml Taskfile.yaml; do
    has "$tf" || continue; note "$tf"
    while IFS= read -r t; do
        case "$t" in build) add B "task build" ;; test) add T "task test" ;; lint) add L "task lint" ;; typecheck) add TC "task typecheck" ;; esac
    done < <(grep -E '^  [[:alnum:]_-]+:[[:space:]]*$' "$tf" | sed -E 's/^  ([[:alnum:]_-]+):.*/\1/')
    break
done

# ── 빌드 래퍼 · 언어 매니페스트 — 관례 명령 ───────────────────────────
if has gradlew; then
    note gradlew; add B "./gradlew build"; add T "./gradlew test"; add L "./gradlew check"
    for s in settings.gradle.kts settings.gradle; do
        has "$s" || continue
        grep -qE '^[[:space:]]*include' "$s" && SIGNALS+=("$s include")
        break
    done
    GB=(); for g in build.gradle.kts build.gradle gradle/libs.versions.toml; do has "$g" && GB+=("$g"); done
    if [ "${#GB[@]}" -gt 0 ]; then
        grep -qs 'ktlint' "${GB[@]}" && add L "./gradlew ktlintCheck"
        grep -qs 'detekt' "${GB[@]}" && add L "./gradlew detekt"
    fi
elif has build.gradle.kts || has build.gradle; then note build.gradle; add B "gradle build"; add T "gradle test"; fi
if has mvnw; then note mvnw; add B "./mvnw -q package -DskipTests"; add T "./mvnw -q test"; add L "./mvnw -q verify"
elif has pom.xml; then note pom.xml; add B "mvn -q package -DskipTests"; add T "mvn -q test"; fi
if has pom.xml && grep -q '<modules>' pom.xml 2>/dev/null; then SIGNALS+=("pom.xml modules"); fi
if has go.mod; then note go.mod; add B "go build ./..."; add T "go test ./..."; add L "go vet ./..."
    has .golangci.yml || has .golangci.yaml && add L "golangci-lint run"; fi
if has Cargo.toml; then note Cargo.toml; add B "cargo build"; add T "cargo test"; add L "cargo clippy -- -D warnings"
    grep -q '^\[workspace\]' Cargo.toml && SIGNALS+=("Cargo.toml [workspace]"); fi
if has pyproject.toml; then
    note pyproject.toml; PY=""
    if has uv.lock; then PY="uv run "; note uv.lock; elif has poetry.lock; then PY="poetry run "; note poetry.lock; fi
    grep -qE '^\[tool\.pytest|pytest' pyproject.toml && add T "${PY}pytest"
    if grep -qE '^\[tool\.ruff|ruff' pyproject.toml || has ruff.toml; then add L "${PY}ruff check ."; add LF "**/*.py => ${PY}ruff check {file}"; fi
    grep -qE '^\[tool\.mypy|mypy' pyproject.toml && add TC "${PY}mypy ."
    grep -qE '^\[tool\.pyright|pyright' pyproject.toml && add TC "${PY}pyright"
fi
if has Gemfile; then note Gemfile; add T "bundle exec rake test"
    grep -q rubocop Gemfile 2>/dev/null && { add L "bundle exec rubocop"; add LF "**/*.rb => bundle exec rubocop {file}"; }; fi
if has composer.json && jq -e . composer.json >/dev/null 2>&1; then
    note composer.json
    while IFS= read -r s; do case "$s" in test) add T "composer test" ;; lint|cs|phpstan) add L "composer $s" ;; esac
    done < <(jq -r '(.scripts // {}) | keys[]' composer.json 2>/dev/null)
fi
if ls ./*.sln >/dev/null 2>&1 || ls ./*.csproj >/dev/null 2>&1; then note "*.sln|*.csproj"; add B "dotnet build"; add T "dotnet test"; add L "dotnet format --verify-no-changes"; fi
if has pubspec.yaml; then note pubspec.yaml; add T "flutter test"; add L "flutter analyze"; fi
if has Package.swift; then note Package.swift; add B "swift build"; add T "swift test"; fi
if has mix.exs; then note mix.exs; add B "mix compile"; add T "mix test"; add L "mix format --check-formatted"; fi
if has deno.json || has deno.jsonc; then note deno.json; add T "deno test"; add L "deno lint"; add TC "deno check ."; fi
if has CMakeLists.txt; then note CMakeLists.txt; add B "cmake --build build"; add T "ctest --test-dir build"; fi

# ── 모노레포 멤버 — 하위 2단계까지 매니페스트가 있는 디렉토리 (최대 20) ─────
while IFS= read -r d; do
    MEMBERS+=("$d")
done < <(find . -mindepth 2 -maxdepth 3 \( -name node_modules -o -name .git -o -name build -o -name target -o -name dist -o -name .ax \) -prune -o \
             -type f \( -name package.json -o -name build.gradle.kts -o -name build.gradle -o -name pom.xml -o -name go.mod \
                        -o -name Cargo.toml -o -name pyproject.toml -o -name '*.csproj' -o -name pubspec.yaml \) -print 2>/dev/null \
         | sed -E 's|^\./||; s|/[^/]*$||' | sort -u | head -20)
MONO=false
{ [ "${#SIGNALS[@]}" -gt 0 ] || [ "${#MEMBERS[@]}" -ge 2 ]; } && MONO=true

arr() { if [ $# -eq 0 ]; then echo '[]'; else printf '%s\n' "$@" | awk '!seen[$0]++' | jq -R . | jq -sc .; fi; }
cur() {   # zero-verify.sh 와 같은 읽기 — 따옴표 값 안의 `#` 은 주석이 아니에요
    grep -E "^[[:space:]]+$1:" "$ROOT/.ax/config.yml" 2>/dev/null | head -1 \
        | sed -E "s/^[[:space:]]+$1:[[:space:]]*//" \
        | sed -E -e 's/^"([^"]*)".*$/\1/' -e t -e "s/^'([^']*)'.*\$/\1/" -e t -e 's/^#.*$//' -e t -e 's/[[:space:]]+#.*$//' -e 's/[[:space:]]+$//'
}
RESULT=$(jq -nc \
    --argjson m "$(arr ${MANIFESTS[@]+"${MANIFESTS[@]}"})" --argjson s "$(arr ${SIGNALS[@]+"${SIGNALS[@]}"})" \
    --argjson mem "$(arr ${MEMBERS[@]+"${MEMBERS[@]}"})" --argjson mono "$MONO" \
    --argjson b "$(arr ${B[@]+"${B[@]}"})" --argjson t "$(arr ${T[@]+"${T[@]}"})" --argjson l "$(arr ${L[@]+"${L[@]}"})" \
    --argjson tc "$(arr ${TC[@]+"${TC[@]}"})" --argjson lf "$(arr ${LF[@]+"${LF[@]}"})" \
    --arg cb "$(cur build)" --arg ct "$(cur test)" --arg cl "$(cur lint)" --arg ctc "$(cur typecheck)" \
    '{manifests:$m, workspace:{monorepo:$mono, signals:$s, members:$mem},
      candidates:{build:$b, test:$t, lint:$l, typecheck:$tc, lint_file:$lf},
      current:{build:$cb, test:$ct, lint:$cl, typecheck:$ctc}}')

if [ "$JSON_MODE" = true ]; then
    NEXT=""
    [ "${#MANIFESTS[@]}" -eq 0 ] && NEXT="알아본 매니페스트가 없어요 — 빌드·테스트 명령을 사용자에게 물어서 config-set.sh 로 적어요"
    [ -z "$NEXT" ] && NEXT="후보를 사용자에게 보여주고 고른 것만 config-set.sh commands.<key> \"<명령>\" 으로 적어요"
    json_output ok "$RESULT" "$NEXT"
else
    printf '%s' "$RESULT" | jq -r '
        "매니페스트: " + (.manifests | join(", ")),
        "모노레포: \(.workspace.monorepo)" + (if (.workspace.signals|length) > 0 then " (" + (.workspace.signals|join(", ")) + ")" else "" end),
        (.candidates | to_entries[] | select(.value | length > 0) | "  \(.key): " + (.value | join("  |  ")))'
fi
exit "$EXIT_OK"
