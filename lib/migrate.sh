# lib/migrate.sh — 기존 CLAUDE.md 룰을 spirit/rules 카테고리로 분류

# 키워드 → 카테고리 매핑 (간단 휴리스틱)
migrate_classify_line() {
    local line="$1"
    local lower=$(echo "$line" | tr 'A-Z가-힣' 'a-z가-힣')

    # security
    if echo "$lower" | grep -qE 'secret|api[_-]?key|token|password|credential|auth|권한|인증|보안'; then
        echo "security"; return
    fi
    # naming
    if echo "$lower" | grep -qE 'naming|kebab|camelcase|prefix|suffix|이름|명명|네이밍'; then
        echo "naming"; return
    fi
    # testing
    if echo "$lower" | grep -qE 'test|spec|integration|@tag|jest|vitest|kotest|junit|테스트|커버리지'; then
        echo "testing"; return
    fi
    # pr
    if echo "$lower" | grep -qE 'pr |pull request|commit|review|템플릿|커밋|리뷰'; then
        echo "pr"; return
    fi
    # error-handling
    if echo "$lower" | grep -qE 'throw|catch|error|exception|panic|에러|예외|핸들링'; then
        echo "error-handling"; return
    fi
    # concurrency
    if echo "$lower" | grep -qE 'thread|race|lock|atomic|timeout|concurren|coroutine|동시성|레이스|타임아웃'; then
        echo "concurrency"; return
    fi
    # observability
    if echo "$lower" | grep -qE 'log|metric|trace|alert|로그|메트릭|관측'; then
        echo "observability"; return
    fi
    # architecture (모듈 의존)
    if echo "$lower" | grep -qE 'depend|import|module|architect|layer|의존|아키|레이어|모듈'; then
        echo "architecture"; return
    fi
    # data
    if echo "$lower" | grep -qE 'ddl|migration|schema|sql|entity|마이그레이션|스키마'; then
        echo "data"; return
    fi

    echo "uncategorized"
}

# CLAUDE.md를 읽고 분류 결과를 stdout으로 출력
migrate_classify_file() {
    local f="$1"
    [ -f "$f" ] || return 0

    local in_rule=0
    local current_rule=""
    while IFS= read -r line; do
        # 🔴/🟡/🔵 시작 또는 ## 헤더
        if echo "$line" | grep -qE '^(🔴|🟡|🔵|## |- (NEVER|Always|MUST|반드시|금지|필수))'; then
            if [ -n "$current_rule" ]; then
                local cat=$(migrate_classify_line "$current_rule")
                printf '%s|%s\n' "$cat" "$current_rule"
            fi
            current_rule="$line"
        elif [ -n "$current_rule" ] && [ -n "$line" ]; then
            current_rule="$current_rule $line"
        fi
    done < "$f"
    # 마지막 룰
    if [ -n "$current_rule" ]; then
        local cat=$(migrate_classify_line "$current_rule")
        printf '%s|%s\n' "$cat" "$current_rule"
    fi
}

# adoption-plan.md 생성
migrate_emit_plan() {
    local root="$1"
    local out="$root/adoption-plan.md"

    cat > "$out" <<HEAD
# Adoption Plan — goax 도입 제안

> goax up이 자동 생성. 머지 전 사람이 검토하고 카테고리를 조정하세요.
> 휴리스틱 키워드 매칭이라 정확도 \~80%. 분류 오차는 직접 카테고리 수정.

## 분류 결과

HEAD

    if [ ! -f "$root/CLAUDE.md" ]; then
        echo "(CLAUDE.md 없음 — 분류 대상 없음)" >> "$out"
        echo "$out"
        return
    fi

    declare -A category_buckets
    while IFS='|' read -r cat rule; do
        [ -z "$cat" ] && continue
        category_buckets["$cat"]="${category_buckets["$cat"]:-}\n- $rule"
    done < <(migrate_classify_file "$root/CLAUDE.md")

    for cat in "${!category_buckets[@]}"; do
        printf '\n### %s → `.ax/spirit/rules/%s.md`\n' "$cat" "$cat" >> "$out"
        printf '%b\n' "${category_buckets["$cat"]}" >> "$out"
    done

    cat >> "$out" <<TAIL

---

## 검토 체크리스트

- [ ] 각 룰이 올바른 카테고리에 분류됐는지 검토
- [ ] uncategorized 항목은 카테고리 수정 또는 삭제
- [ ] 새 카테고리 필요하면 \`goax spirit add <name>\` 실행
- [ ] 분류 확정 후, 이 PR을 머지하고 goax가 spirit/rules로 옮김

## 머지 후 다음 단계

\`\`\`bash
goax spirit lint    # frontmatter 검증
goax rules          # 통합 인덱스 확인
goax doctor         # 결손 검사
\`\`\`
TAIL

    echo "$out"
}
