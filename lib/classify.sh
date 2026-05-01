# goax classify — Size × Risk 분류 로직
# config.yml에서 도메인별 위험도 매트릭스를 읽어 작업 설명을 분류

# 키워드 매칭 헬퍼 (대소문자 무시, 한국어 OK)
_match_any() {
    local text="$1"; shift
    for kw in "$@"; do
        if echo "$text" | grep -qiE -- "$kw"; then
            return 0
        fi
    done
    return 1
}

# YAML에서 단순 'key: value' 또는 'list' 추출 (yq 없이 grep)
_yaml_get() {
    local file="$1" key="$2"
    grep -E "^[[:space:]]*$key:" "$file" 2>/dev/null | head -1 | sed -E "s/^[[:space:]]*$key:[[:space:]]*//; s/[[:space:]]*$//"
}

_yaml_section() {
    # 'section:' 라벨 아래 들여쓰기된 'name: value' 라인을 출력
    local file="$1" section="$2"
    awk -v s="$section" '
        $0 ~ "^"s":" { inside=1; next }
        inside && /^[^[:space:]]/ { inside=0 }
        inside && /:/ { print }
    ' "$file"
}

classify() {
    local desc="$1" config="$2"

    # ── domain 추론 (config.yml의 domains 섹션과 키워드 매칭)
    local matched_domains=""
    local default_risk
    default_risk="$(_yaml_get "$config" "default_risk")"
    [ -z "$default_risk" ] && default_risk="L0"

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local domain risk_level
        domain="$(echo "$line" | awk -F: '{print $1}' | sed 's/[[:space:]]//g')"
        risk_level="$(echo "$line" | awk -F: '{print $2}' | sed 's/[[:space:]]//g')"
        if _match_any "$desc" "$domain"; then
            matched_domains="$matched_domains $domain"
            # 가장 위험한 등급 보존
            case "$risk_level" in
                L3) default_risk="L3" ;;
                L2) [ "$default_risk" != "L3" ] && default_risk="L2" ;;
                L1) [ "$default_risk" = "L0" ] && default_risk="L1" ;;
            esac
        fi
    done < <(_yaml_section "$config" "domain_risk")

    matched_domains="$(echo "$matched_domains" | sed 's/^[[:space:]]*//')"
    [ -z "$matched_domains" ] && matched_domains="(unmatched)"

    # ── size 추론 (간단한 키워드 휴리스틱)
    local size="M"
    if _match_any "$desc" "리팩토링|refactor|마이그레이션|migration|부트스트랩|bootstrap|도메인 추가|새 도메인|new domain"; then
        size="XL"
    elif _match_any "$desc" "여러|cross|통합|orchestrate|across|across|동시"; then
        size="L"
    elif _match_any "$desc" "오타|색상|버튼|문구|copy|typo|텍스트|label|색"; then
        size="S"
    fi

    # ── path 추천
    local path="task-machine (1\~2 그룹)"
    case "$size" in
        S) path="즉시 작업 + commit skill" ;;
        M) path="task-machine 1\~2 그룹 + commerce-tester (해당 시)" ;;
        L) path="task-machine 5-parallel + 도메인 페르소나 + ADR 강제" ;;
        XL) path="단계 분할 + 사람 architect 게이트 + 단계당 ADR" ;;
    esac

    # ── sensors
    local sensors="ktlint, eslint, tsc (스택에 따라)"
    case "$default_risk" in
        L2|L3) sensors="$sensors, structural-check, integration tag, traffic estimation" ;;
    esac

    # ── human gate
    local gate="false"
    case "$size$default_risk" in
        L*L2|L*L3|XL*) gate="true" ;;
    esac

    # ── spirit context 매칭 (v0.3)
    local project_root
    project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    local spirit_dir="$project_root/.ax/spirit"
    local spirit_status=""
    local spirit_rules_matched=""

    if [ ! -f "$spirit_dir/values.md" ] || [ ! -f "$spirit_dir/tone.md" ]; then
        spirit_status="MISSING"
    else
        spirit_status="OK"
        # rules/ 안에서 카테고리별 매칭 (간단 휴리스틱)
        if [ -d "$spirit_dir/rules" ]; then
            for rf in "$spirit_dir/rules"/*.md; do
                [ -f "$rf" ] || continue
                local cat
                cat=$(basename "$rf" .md)
                # 모든 룰 일단 포함 (matching은 v0.3.1에서 정교화)
                spirit_rules_matched="$spirit_rules_matched .ax/spirit/rules/$cat.md"
            done
        fi
    fi

    # ── 출력
    cat <<EOF
🔍 goax triage

  설명:    $desc
  size:    $size
  risk:    $default_risk
  domain:  $matched_domains
  path:    $path
  sensors: $sensors
  human gate: $gate
  spirit:  $spirit_status$([ -n "$spirit_rules_matched" ] && echo " (rules: $(echo $spirit_rules_matched | wc -w | tr -d " ")개 매칭)")

권장 다음 단계:
EOF
    case "$size" in
        S) echo "  → 즉시 작업. hooks가 자동 검증." ;;
        M) echo "  → /speckit-specify (있으면) 또는 task-machine. 변경 파일 테스트 필수." ;;
        L) echo "  → /adr-write 로 ADR 초안 → task-machine 5-parallel → /evaluator." ;;
        XL) echo "  → 단계 분할 plan 작성 → 단계당 PR + ADR. architect 사람 게이트." ;;
    esac

    if [ "$gate" = "true" ]; then
        echo
        echo "  ⚠ MANDATORY: 사람 architect 승인 필요한 작업"
    fi

    # size=L/XL 또는 risk=L2/L3 → spec 우선 작성 권장
    case "$size" in
        L|XL)
            echo
            echo "  📋 SPEC 우선 작성 권장 — \`goax spec new <name>\`"
            echo "     (size $size: spec.md/plan.md 게이팅 후 implement)"
            ;;
    esac
    case "$default_risk" in
        L2|L3)
            if [ "$size" != "L" ] && [ "$size" != "XL" ]; then
                echo
                echo "  📋 SPEC 우선 작성 권장 — \`goax spec new <name>\`"
                echo "     (risk $default_risk: spec으로 의도 명문화)"
            fi
            ;;
    esac

    # spirit MISSING 시 강제 차단 (옵션 4-B fail)
    if [ "$spirit_status" = "MISSING" ]; then
        echo ""
        echo "  ✗ \033[31m.ax/spirit/ 누락\033[0m — values.md 또는 tone.md 없음"
        echo "    복구: goax up --force"
        return 1
    fi
}
