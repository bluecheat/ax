#!/usr/bin/env bash
# tests/smoke/22-review-axes.sh — §80 tasks-plan --lint · §81 rules-audit-scope --from-tasks · §82 리뷰 파일의 model 줄 · §83 리뷰 축 배선
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/22-review-axes.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

command -v jq >/dev/null 2>&1 || { pass "jq 없음 — §80–§83 건너뜀"; smoke_done; }

write_tasks() {
    cat <<'EOF'
```
- [ ] T009 파서 예시 — files: x/Example.kt
```
## Phase 1: 입력

- [ ] T001 [AC1] 주문 CSV 파서 추가 — files: order/Parser.kt
      의존: 없음
      검증: ParserTest (정상 3행)
- [ ] T002 [AC1] 상품 upsert — files: order/Repo.kt
      의존: T001
      검증: RepoTest — 중복 키면 갱신, 잘못된 가격은 거부
- [ ] T003 [AC2] 상태 조건부 갱신 — files: order/Svc.kt
      의존: 없음
- [x] T004 [AC2] parse 결과 저장 — files: order/Done.kt
      검증: ok
- [ ] T005 [AC3] 화면 문구 — files: web/Copy.tsx
      의존: 없음
      검증: 스냅샷
EOF
}

# ───────────────────────────────────────────────────────────
section "80. tasks-plan --lint — 입력을 거르는 task 의 검증에 거부 경로가 있어야 해요"
# ───────────────────────────────────────────────────────────
if fx_install TL; then
    SD="$TL/.ax/docs/spec/2026-10-11-ab34-order"; mkdir -p "$SD"; printf '# x\n' > "$SD/spec.md"; write_tasks > "$SD/tasks.md"
    tl() { (cd "$TL" && GOAX_PROJECT_DIR="$TL" bash .ax/scripts/bash/tasks-plan.sh --spec ab34 --json "$@" 2>/dev/null); }
    L=$(tl --lint); N=$(tl)
    printf '%s\n' "$L" | jq -e '.status == "warning" and ([.result.lint[].task] == ["T001", "T003"])
        and (.result.lint[1].reason | test("검증: 줄이 없어요"))' >/dev/null \
        && printf '%s\n' "$N" | jq -e '.status == "ok" and (.result | has("lint") | not)' >/dev/null \
        && pass "tasks-plan --lint — 성공 경로만 있는 파서 · 검증 없는 조건부 갱신만 지적, 완료·펜스·화면 task 는 제외, --lint 없으면 그대로" \
        || fail "tasks-plan --lint: $(printf '%s' "$L" | jq -c '[.status, .result.lint]')"
fi

# ───────────────────────────────────────────────────────────
section "81. rules-audit-scope --from-tasks — 계획 단계에서 task 파일에 걸리는 룰"
# ───────────────────────────────────────────────────────────
if fx_install RT; then
    SD="$RT/.ax/docs/spec/2026-10-11-cd56-order"; mkdir -p "$SD" "$RT/.ax/spirit/rules"; printf '# x\n' > "$SD/spec.md"; write_tasks > "$SD/tasks.md"
    printf -- '---\ncategory: order\npaths:\n  - "order/**"\n---\n## SP-ORD-001: 주문은 멱등이에요\n' > "$RT/.ax/spirit/rules/order.md"
    RJ=$(cd "$RT" && GOAX_PROJECT_DIR="$RT" bash .ax/scripts/bash/rules-audit-scope.sh --spec cd56 --from-tasks --json 2>/dev/null)
    BOTH=$(cd "$RT" && GOAX_PROJECT_DIR="$RT" bash .ax/scripts/bash/rules-audit-scope.sh --spec cd56 --from-tasks --files a.kt --json 2>/dev/null; echo "rc=$?")
    printf '%s\n' "$RJ" | jq -e '.status == "ok" and (.result.review_file | endswith("review-spec.evaluator.md"))
        and ([.result.files[].path] | sort == ["order/Parser.kt", "order/Repo.kt", "order/Svc.kt", "web/Copy.tsx"])
        and (.result.rule_files | index(".ax/spirit/rules/order.md")) != null
        and ([.result.files[] | select(.path == "web/Copy.tsx") | .rules[]] | index(".ax/spirit/rules/order.md")) == null
        and (.next_step | test("evaluator"))' >/dev/null \
        && case "$BOTH" in *rc=1) true ;; *) false ;; esac \
        && pass "rules-audit-scope --from-tasks — 미완료 task 의 files: 로 룰을 매칭, 완료 task 제외, --files 와 같이 쓰면 exit 1" \
        || fail "rules-audit-scope --from-tasks: $(printf '%s' "$RJ" | head -c 300) / both=$BOTH"
fi

# ───────────────────────────────────────────────────────────
section "82. 리뷰 파일 model 줄 — 어떤 모델이 리뷰를 썼는지 남아요"
# ───────────────────────────────────────────────────────────
if fx_install SM --git; then
    SD="$SM/.ax/docs/spec/2026-10-11-ef78-m"; mkdir -p "$SD"
    printf '# m\n\n## 3. 성공 기준\n- **AC1** a\n' > "$SD/spec.md"
    sr() { (cd "$SM" && GOAX_PROJECT_DIR="$SM" bash .ax/scripts/bash/spec-review.sh --spec ef78 --json "$@" 2>/dev/null); }
    SNAP=$(sr --snapshot); SHA=$(printf '%s\n' "$SNAP" | jq -r '.result.sha')
    printf 'verdict: 진행\nsha: %s\nmodel: opus\n\n## 반대안\n없음\n' "$SHA" > "$SD/review-spec.architect.md"
    printf 'verdict: 진행\nsha: %s\n\n## 종합\n발견 0건\n' "$SHA" > "$SD/review-spec.evaluator.md"
    ST=$(sr --status)
    printf '%s\n' "$SNAP" | jq -e '.result.header | length == 3 and (.[2] | startswith("model:"))' >/dev/null \
        && printf '%s\n' "$ST" | jq -e '.result.architect.model == "opus" and .result.evaluator.model == null and .result.pass' >/dev/null \
        && pass "spec-review — 스냅샷 헤더 셋째 줄 model, --status 가 리뷰어별 model 을 읽고 없으면 null (판정엔 영향 없음)" \
        || fail "spec-review model: snap=$(printf '%s' "$SNAP" | jq -c '.result.header') status=$(printf '%s' "$ST" | jq -c '.result | {a: .architect.model, e: .evaluator.model, pass}')"
fi

# ───────────────────────────────────────────────────────────
section "83. 리뷰 축 배선 — Phase 리뷰 · 룰·선례 · 원칙과 대안 · 확인/주장 구분"
# ───────────────────────────────────────────────────────────
E="$REPO/agents/evaluator.md"; A="$REPO/agents/architect.md"; SV="$REPO/skills/spec-validate/SKILL.md"
SI="$REPO/skills/spec-implement/SKILL.md"; PR="$REPO/skills/spec-implement/references/phase-review.md"; T="$REPO/templates/default/.ax/_templates/spec/spec.md"
{ grep -q '## Phase 모드' "$E" && grep -q 'review-phase-' "$E" && grep -q '거부 경로 테스트' "$E" && grep -q '룰·선례 대조' "$E" \
  && grep -q '^model: ' "$E" && grep -q '^model: ' "$A" && grep -q '^model: ' "$REPO/agents/rules-auditor.md" \
  && grep -q '§2.3 점검' "$A" && grep -q '\*\*원칙\*\*' "$T" && grep -q '\*\*결정 동인\*\*' "$T" && grep -q '적어도 2개' "$T" && grep -q '사전 부검' "$T" \
  && grep -q 'rules-audit-scope.sh --spec "$SPEC" --from-tasks' "$SV" && grep -q 'tasks-plan.sh --spec "$SPEC" --lint' "$SV" \
  && grep -q '직접 확인함' "$SV" && grep -q '리뷰어 주장' "$PR" && grep -q 'references/phase-review.md' "$SI" \
  && grep -q '선례 파일 경로' "$REPO/skills/spec-tasks/SKILL.md" && grep -q 'tasks-plan.sh --lint' "$REPO/skills/spec-tasks/SKILL.md"; } \
    && pass "evaluator Phase 모드 · 룰·선례 · 거부 경로, architect §2.3 점검, spec 템플릿 원칙·동인·대안 ≥2, spec-validate 브리프 · 보고 구분, spec-tasks 선례 경로" \
    || fail "리뷰 축 배선 누락"

smoke_done
