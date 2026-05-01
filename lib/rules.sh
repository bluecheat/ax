# lib/rules.sh — 룰 토큰 검색·인덱싱
# v0.3: spirit/rules/* 도 함께 스캔 + --source / --category 필터

# Constitution 토큰 형식: `<scope>:<LEVEL>:<id>` (예: AX:CRITICAL:001)
RULE_TOKEN_REGEX='`[A-Za-z*][A-Za-z0-9_-]*:(CRITICAL|MANDATORY|CONVENTION):[0-9]{3}`'
# Spirit 토큰 형식: SP-<CATEGORY>-<id> (예: SP-SEC-001)
SPIRIT_TOKEN_REGEX='SP-[A-Z]+-[0-9]{3}'

rules_find_constitution_files() {
    local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    find "$root" -name "CLAUDE.md" \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" 2>/dev/null
}

rules_find_spirit_files() {
    local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    [ -d "$root/.ax/spirit/rules" ] || return 0
    find "$root/.ax/spirit/rules" -name "*.md" -type f -not -name "_*" 2>/dev/null
}

# Constitution 토큰 추출
rules_extract_constitution_tokens() {
    local f="$1"
    grep -nE "$RULE_TOKEN_REGEX" "$f" 2>/dev/null \
        | while IFS=: read -r lineno line; do
            local token=$(echo "$line" | grep -oE "$RULE_TOKEN_REGEX" | head -1 | tr -d '`')
            [ -z "$token" ] && continue
            local after=$(echo "$line" | sed -E "s/.*\`$token\`\*?\*?[[:space:]]*//; s/^[[:space:]]*//")
            printf 'constitution|%s|%s|%s|%s\n' "$token" "$f" "$lineno" "$after"
        done
}

# Spirit 토큰 추출 (SP-<CAT>-<id>)
rules_extract_spirit_tokens() {
    local f="$1"
    local category=$(basename "$f" .md)
    # 헤더(## SP-XXX-NNN: ...)만 인식
    grep -nE "^## $SPIRIT_TOKEN_REGEX" "$f" 2>/dev/null \
        | while IFS=: read -r lineno line; do
            local token=$(echo "$line" | grep -oE "$SPIRIT_TOKEN_REGEX" | head -1)
            [ -z "$token" ] && continue
            local after=$(echo "$line" | sed -E "s/.*$token:?[[:space:]]*//; s/^[[:space:]]*//")
            printf 'spirit|%s|%s|%s|%s\n' "$token" "$f" "$lineno" "$after"
        done
}

rules_list() {
    local filter_level="" filter_scope="" filter_source="" filter_category="" module=""
    JSON=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --level) filter_level=$(echo "$2" | tr 'a-z' 'A-Z'); shift 2 ;;
            --scope) filter_scope="$2"; shift 2 ;;
            --source) filter_source="$2"; shift 2 ;;
            --category) filter_category="$2"; shift 2 ;;
            --module) module="$2"; shift 2 ;;
            --json) JSON=1; shift ;;
            *) shift ;;
        esac
    done

    local root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    [ -n "$module" ] && root="$root/$module"

    local count=0
    [ "$JSON" = "1" ] && echo "["
    local first=1

    # Constitution 스캔
    if [ -z "$filter_source" ] || [ "$filter_source" = "constitution" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            while IFS='|' read -r src token file line text; do
                [ -z "$token" ] && continue
                local scope=$(echo "$token" | cut -d: -f1)
                local level=$(echo "$token" | cut -d: -f2)
                local id=$(echo "$token" | cut -d: -f3)

                [ -n "$filter_level" ] && [ "$level" != "$filter_level" ] && continue
                [ -n "$filter_scope" ] && [ "$scope" != "$filter_scope" ] && continue

                local rel_file="${file#$(git rev-parse --show-toplevel 2>/dev/null || pwd)/}"

                if [ "$JSON" = "1" ]; then
                    [ "$first" = "0" ] && echo ","
                    printf '  {"source":"constitution","token":"%s","scope":"%s","level":"%s","id":"%s","file":"%s","line":%s,"text":%s}' \
                        "$token" "$scope" "$level" "$id" "$rel_file" "$line" \
                        "$(echo "$text" | sed 's/\\/\\\\/g; s/"/\\"/g; s/.*/"&"/')"
                    first=0
                else
                    local emoji
                    case "$level" in
                        CRITICAL)  emoji='🔴' ;;
                        MANDATORY) emoji='🟡' ;;
                        CONVENTION) emoji='🔵' ;;
                    esac
                    printf '%s [Const] %-32s %s:%s\n         %s\n' "$emoji" "$token" "$rel_file" "$line" "$text"
                fi
                count=$((count + 1))
            done < <(rules_extract_constitution_tokens "$f")
        done < <(rules_find_constitution_files "$root")
    fi

    # Spirit 스캔
    if [ -z "$filter_source" ] || [ "$filter_source" = "spirit" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            local file_cat=$(basename "$f" .md)
            [ -n "$filter_category" ] && [ "$file_cat" != "$filter_category" ] && continue
            while IFS='|' read -r src token file line text; do
                [ -z "$token" ] && continue
                local rel_file="${file#$(git rev-parse --show-toplevel 2>/dev/null || pwd)/}"

                if [ "$JSON" = "1" ]; then
                    [ "$first" = "0" ] && echo ","
                    printf '  {"source":"spirit","token":"%s","category":"%s","file":"%s","line":%s,"text":%s}' \
                        "$token" "$file_cat" "$rel_file" "$line" \
                        "$(echo "$text" | sed 's/\\/\\\\/g; s/"/\\"/g; s/.*/"&"/')"
                    first=0
                else
                    printf '🌟 [Spirit] %-25s %s:%s\n         %s\n' "$token" "$rel_file" "$line" "$text"
                fi
                count=$((count + 1))
            done < <(rules_extract_spirit_tokens "$f")
        done < <(rules_find_spirit_files "$root")
    fi

    [ "$JSON" = "1" ] && echo "" && echo "]"

    if [ "$JSON" != "1" ]; then
        echo
        echo "총 $count 룰"
        [ -n "$filter_level" ] && echo "  필터: level=$filter_level"
        [ -n "$filter_scope" ] && echo "  필터: scope=$filter_scope"
        [ -n "$filter_source" ] && echo "  필터: source=$filter_source"
        [ -n "$filter_category" ] && echo "  필터: category=$filter_category"
        [ -n "$module" ] && echo "  모듈: $module"
    fi
}

rules_find_by_id() {
    local id="$1"
    [ -z "$id" ] && { echo "사용: goax find <token>" >&2; return 1; }

    local root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    local found=0

    # Constitution 검색
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        while IFS='|' read -r src token file line text; do
            [ -z "$token" ] && continue
            if [ "$token" = "$id" ]; then
                local rel="${file#$root/}"
                printf '\n🔍 [Constitution] %s\n' "$token"
                printf '   위치: %s:%s\n' "$rel" "$line"
                printf '   본문: %s\n\n' "$text"
                printf '본문 (다음 5줄까지):\n'
                tail -n +"$line" "$file" | head -6 | sed 's/^/  /'
                printf '\n'
                local adr=$(tail -n +"$line" "$file" | head -10 | grep -oE 'docs/adr/[a-zA-Z0-9_/-]+\.md' | head -1)
                [ -n "$adr" ] && [ -f "$root/$adr" ] && printf '관련 ADR: %s\n  %s\n' "$adr" "$(head -3 "$root/$adr" | head -1)"
                found=1
            fi
        done < <(rules_extract_constitution_tokens "$f")
    done < <(rules_find_constitution_files "$root")

    # Spirit 검색
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        while IFS='|' read -r src token file line text; do
            [ -z "$token" ] && continue
            if [ "$token" = "$id" ]; then
                local rel="${file#$root/}"
                printf '\n🌟 [Spirit] %s\n' "$token"
                printf '   위치: %s:%s\n' "$rel" "$line"
                printf '   본문: %s\n\n' "$text"
                printf '본문 (다음 5줄까지):\n'
                tail -n +"$line" "$file" | head -6 | sed 's/^/  /'
                found=1
            fi
        done < <(rules_extract_spirit_tokens "$f")
    done < <(rules_find_spirit_files "$root")

    [ "$found" = "0" ] && { echo "❌ 찾을 수 없음: $id" >&2; return 1; }
    return 0
}

rules_find_untokenized() {
    local root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    local found=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local rel="${f#$root/}"
        grep -nE '🔴|🟡|🔵' "$f" 2>/dev/null | while IFS=: read -r lineno line; do
            if ! echo "$line" | grep -qE "$RULE_TOKEN_REGEX"; then
                printf '  %s:%s  %s\n' "$rel" "$lineno" "$(echo "$line" | head -c 80)"
                found=1
            fi
        done
    done < <(rules_find_constitution_files "$root")
    [ "$found" = "0" ] && echo "✓ 모든 Constitution 룰에 토큰 있음"
}
