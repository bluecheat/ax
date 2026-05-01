# lib/discover.sh — 기존 프로젝트 자산 스캔 (변경 0)

# 결과는 환경변수에 저장 — 호출자가 참조
DISCOVER_REPO_SHAPE=""
DISCOVER_MODULE_COUNT=0
DISCOVER_MODULES=""
DISCOVER_CLAUDE_MD_LINES=0
DISCOVER_CLAUDE_MD_RULES=0
DISCOVER_EXTERNAL_SPECS=""
DISCOVER_ACTIVE_HOOKS=""
DISCOVER_AI_REVIEW=""
DISCOVER_STACK=""
DISCOVER_DOMAINS=""

discover_run() {
    local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

    discover_repo_shape "$root"
    discover_constitution "$root"
    discover_external_specs "$root"
    discover_active_hooks "$root"
    discover_ai_review "$root"
    discover_stack "$root"
    discover_domain_keywords "$root"
}

# 1. 모노레포 vs 싱글
discover_repo_shape() {
    local root="$1"
    local module_dirs=""

    # 흔한 모노레포 마커
    if [ -f "$root/pnpm-workspace.yaml" ] || [ -f "$root/lerna.json" ]; then
        DISCOVER_REPO_SHAPE="모노레포 (pnpm/lerna)"
    elif [ -f "$root/package.json" ] && grep -q '"workspaces"' "$root/package.json" 2>/dev/null; then
        DISCOVER_REPO_SHAPE="모노레포 (npm/yarn workspaces)"
    elif [ -f "$root/settings.gradle.kts" ] || [ -f "$root/settings.gradle" ]; then
        if grep -qE 'include\s*\(' "$root/settings.gradle.kts" "$root/settings.gradle" 2>/dev/null; then
            DISCOVER_REPO_SHAPE="모노레포 (Gradle multi-module)"
        else
            DISCOVER_REPO_SHAPE="싱글 (Gradle)"
        fi
    elif [ -d "$root/apps" ] || [ -d "$root/packages" ] || [ -d "$root/projects" ]; then
        DISCOVER_REPO_SHAPE="모노레포 (디렉토리 기반)"
    else
        DISCOVER_REPO_SHAPE="싱글"
    fi

    # 모듈 디렉토리 추정
    for d in apps packages projects modules; do
        [ -d "$root/$d" ] || continue
        for sub in "$root/$d"/*/; do
            [ -d "$sub" ] || continue
            local name=$(basename "$sub")
            module_dirs="$module_dirs $name"
            DISCOVER_MODULE_COUNT=$((DISCOVER_MODULE_COUNT + 1))
        done
    done
    DISCOVER_MODULES="$(echo "$module_dirs" | sed 's/^ //; s/  / /g')"
}

# 2. CLAUDE.md 분석 + 룰 추출
discover_constitution() {
    local root="$1"
    if [ -f "$root/CLAUDE.md" ]; then
        DISCOVER_CLAUDE_MD_LINES=$(wc -l < "$root/CLAUDE.md" | tr -d ' ')
        # 룰 추정: 🔴/🟡/🔵 emoji 또는 "##" 헤더 또는 "- " 불릿 + 키워드
        DISCOVER_CLAUDE_MD_RULES=$(grep -cE '^(🔴|🟡|🔵|## |- (NEVER|Always|MUST|반드시|금지|필수))' "$root/CLAUDE.md" 2>/dev/null || echo 0)
    fi
}

# 3. 외부 spec 디렉토리 (../sibling 또는 ./spec, ./docs/specs 등)
discover_external_specs() {
    local root="$1"
    local found=""

    # 같은 부모 아래 sibling 디렉토리
    local parent=$(dirname "$root")
    for sib in "$parent"/*/; do
        [ -d "$sib" ] || continue
        local name=$(basename "$sib")
        # spec/specs/governance 같은 이름 + adr 또는 specs 하위 디렉토리
        if echo "$name" | grep -qE '(spec|governance|standards)' && [ -d "$sib/adr" -o -d "$sib/specs" -o -d "$sib/policies" ]; then
            found="$found $name"
        fi
    done

    # 자기 안의 spec 디렉토리
    for cand in spec specs governance; do
        if [ -d "$root/$cand" ] && { [ -d "$root/$cand/adr" ] || [ -d "$root/$cand/specs" ]; }; then
            found="$found $cand/"
        fi
    done

    DISCOVER_EXTERNAL_SPECS="$(echo "$found" | sed 's/^ //')"
}

# 4. 활성 hooks (husky, pre-commit, lint-staged)
discover_active_hooks() {
    local root="$1"
    local active=""
    [ -d "$root/.husky" ] && active="$active husky"
    [ -f "$root/.pre-commit-config.yaml" ] && active="$active pre-commit-framework"
    [ -f "$root/.lintstagedrc" ] && active="$active lint-staged"
    [ -f "$root/.lintstagedrc.json" ] && active="$active lint-staged"
    if [ -f "$root/package.json" ] && grep -q '"lint-staged"' "$root/package.json" 2>/dev/null; then
        active="$active lint-staged"
    fi
    DISCOVER_ACTIVE_HOOKS="$(echo "$active" | sed 's/^ //; s/  / /g')"
}

# 5. AI 리뷰 도구
discover_ai_review() {
    local root="$1"
    local ai=""
    [ -f "$root/.coderabbit.yaml" ] && ai="$ai CodeRabbit"
    [ -f "$root/.coderabbit.yml" ] && ai="$ai CodeRabbit"
    [ -f "$root/.codiumai.yml" ] && ai="$ai CodiumAI"
    [ -f "$root/.cursorrules" ] && ai="$ai Cursor"
    [ -d "$root/.cursor" ] && ai="$ai Cursor"
    DISCOVER_AI_REVIEW="$(echo "$ai" | sed 's/^ //; s/  / /g')"
}

# 6. Stack 추정
discover_stack() {
    local root="$1"
    local stack=""
    [ -f "$root/package.json" ] && stack="$stack Node"
    [ -f "$root/Cargo.toml" ] && stack="$stack Rust"
    [ -f "$root/go.mod" ] && stack="$stack Go"
    [ -f "$root/pyproject.toml" ] && stack="$stack Python"
    [ -f "$root/requirements.txt" ] && stack="$stack Python"
    [ -f "$root/build.gradle.kts" ] && stack="$stack Kotlin/Gradle"
    [ -f "$root/build.gradle" ] && stack="$stack Java/Kotlin/Gradle"
    [ -f "$root/Gemfile" ] && stack="$stack Ruby"
    [ -f "$root/composer.json" ] && stack="$stack PHP"
    DISCOVER_STACK="$(echo "$stack" | sed 's/^ //; s/  / /g')"
}

# 7. 도메인 추정 (모듈명/디렉토리에서 키워드 추출)
discover_domain_keywords() {
    local root="$1"
    local domains=""

    # 모듈명에서 도메인 키워드 추출
    for m in $DISCOVER_MODULES; do
        # 흔한 prefix 제거
        local clean=$(echo "$m" | sed -E 's/^(commerce-|app-|svc-|service-|pkg-|@.+\/)//')
        domains="$domains $clean"
    done

    # commerce-monorepo 류: 디렉토리 내부도 스캔
    for cand in "$root"/commerce-core/src/main/kotlin/com/*/commerce/* \
                "$root"/projects/*/commerce-core/src/main/kotlin/com/*/commerce/* \
                "$root"/src/main/kotlin/com/*/* \
                "$root"/apps/api/src/* \
                "$root"/src/services/*; do
        [ -d "$cand" ] || continue
        local name=$(basename "$cand")
        # 흔한 비도메인 이름 제외
        case "$name" in
            common|util|utils|helper|shared|lib|infra|config|test) continue ;;
        esac
        domains="$domains $name"
    done

    # 중복 제거 + 정렬
    DISCOVER_DOMAINS="$(echo "$domains" | tr ' ' '\n' | grep -v '^$' | sort -u | head -10 | tr '\n' ' ' | sed 's/ $//')"
}

# 결과 출력 (보기용)
discover_print() {
    cat <<EOF
🔍 Discover

  레포 형태:        ${DISCOVER_REPO_SHAPE:-(미상)}
  모듈:             ${DISCOVER_MODULE_COUNT}개${DISCOVER_MODULES:+ — $DISCOVER_MODULES}
  CLAUDE.md:        $([ "$DISCOVER_CLAUDE_MD_LINES" -gt 0 ] && echo "${DISCOVER_CLAUDE_MD_LINES}줄, 룰 \~${DISCOVER_CLAUDE_MD_RULES}개 추정" || echo "(없음)")
  외부 spec:        ${DISCOVER_EXTERNAL_SPECS:-(없음)}
  활성 hooks:       ${DISCOVER_ACTIVE_HOOKS:-(없음)}
  AI 리뷰:          ${DISCOVER_AI_REVIEW:-(없음)}
  Stack:            ${DISCOVER_STACK:-(미상)}
  추정 도메인:       ${DISCOVER_DOMAINS:-(미상)}
EOF
}
