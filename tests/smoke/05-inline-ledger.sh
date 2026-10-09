#!/usr/bin/env bash
# tests/smoke/05-inline-ledger.sh — §30–§32 — SKILL 인라인 bash · triage-search · lanes-dispatch
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/05-inline-ledger.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "30. SKILL.md 인라인 bash 문법 검사 — skills/ 는 §7 의 사각지대"
# ───────────────────────────────────────────────────────────
# §7 은 `templates/**/*.sh` **파일** 만 봐요. 그런데 up(266줄)·doctor(228줄) 처럼
# SKILL.md 안에 사는 bash 가 그보다 많고, 파일이 아니라서 어떤 lint 도 안 닿았어요.
# 하필 사용자가 제일 먼저 돌리는 설치 코드가 거기 있어요.
# ```bash 블록을 뽑아 bash -n. 블록 단위라 변수 미정의는 못 잡지만 문법은 잡아요.
INLINE_DIR=$(mktemp -d)
inline_total=0
inline_bad=0
while IFS= read -r sf; do
    [ -f "$sf" ] || continue
    sname=$(basename "$(dirname "$sf")")
    awk -v out="$INLINE_DIR/$sname" 'BEGIN{i=0}
        /^```(bash|sh)[[:space:]]*$/ { inb=1; i=i+1; f=out"-"i".sh"; next }
        /^```/ { inb=0; next }
        inb { print >> f }
    ' "$sf"
done < <(find "$REPO/skills" "$REPO/commands" -name '*.md' 2>/dev/null)
for bf in "$INLINE_DIR"/*.sh; do
    [ -f "$bf" ] || continue
    inline_total=$((inline_total+1))
    if ! bash -n "$bf" 2>/dev/null; then
        inline_bad=$((inline_bad+1))
        fail "SKILL.md 인라인 bash 문법 오류: $(basename "$bf")"
    fi
done
rm -rf "$INLINE_DIR"
if [ "$inline_total" -eq 0 ]; then
    fail "SKILL.md 인라인 bash 블록 0개 — 추출 로직이 깨졌어요"
elif [ "$inline_bad" -eq 0 ]; then
    pass "SKILL.md 인라인 bash — $inline_total 블록 문법 OK"
fi

# ───────────────────────────────────────────────────────────
section "31. triage-search — specs 본문 랭킹 + 대소문자 무시 재채점"
# ───────────────────────────────────────────────────────────
# 두 결함의 회귀 방어:
#  (a) specs 를 디렉토리 *이름* 으로만 매칭 → 슬러그에 없고 본문에만 있는 spec 누락.
#      슬러그가 영문 kebab-case 규약이라 한국어 프로젝트에선 "정산" 같은 도메인어로
#      아무것도 못 찾았어요.
#  (b) 후보는 grep -ril(대소문자 무시)로 뽑고 재채점은 grep -cE(구분)로 해서,
#      키워드가 대문자로만 나오는 문서가 점수 0 으로 조용히 탈락했어요.
if ! command -v jq >/dev/null 2>&1; then
    pass "triage-search 검증 skip (jq 없음)"
else
    TS_T=$(mktemp -d)
    mkdir -p "$TS_T/.ax/scripts/bash" "$TS_T/.ax/docs/adr" "$TS_T/.ax/docs/spec/imported"
    cp "$REPO/templates/default/.ax/scripts/bash/common.sh" \
       "$REPO/templates/default/.ax/scripts/bash/triage-search.sh" "$TS_T/.ax/scripts/bash/" 2>/dev/null
    : > "$TS_T/CLAUDE.md"

    mkdir -p "$TS_T/.ax/docs/spec/003-payment-coupon"      # 슬러그 매칭
    printf '# 쿠폰\n중복 적용 정책\n' > "$TS_T/.ax/docs/spec/003-payment-coupon/spec.md"
    mkdir -p "$TS_T/.ax/docs/spec/007-checkout"            # 본문에만 payment
    printf '# 체크아웃\npayment 흐름 재작성\n' > "$TS_T/.ax/docs/spec/007-checkout/spec.md"
    mkdir -p "$TS_T/.ax/docs/spec/009-settlement"          # 본문이 한국어
    printf '# 정산\n정산 배치가 읽어요\n' > "$TS_T/.ax/docs/spec/009-settlement/spec.md"
    printf '# PG\nPayment gateway 이중화\n' > "$TS_T/.ax/docs/adr/0002-pg.md"   # 대문자만
    printf '# 외부\npayment 외부 스펙\n' > "$TS_T/.ax/docs/spec/imported/legacy.md"

    TS_OUT=$(cd "$TS_T" && bash .ax/scripts/bash/triage-search.sh --keywords "payment" --json 2>/dev/null)
    TS_SPECS=$(printf '%s' "$TS_OUT" | jq -r '[.result.specs[].path] | join(" ")' 2>/dev/null)
    TS_ADRS=$(printf '%s' "$TS_OUT" | jq -r '[.result.adrs[].path]  | join(" ")' 2>/dev/null)

    case "$TS_SPECS" in
        *007-checkout*) pass "triage-search — 본문에만 있는 spec 도 매칭 (슬러그 한계 해소)" ;;
        *) fail "triage-search — 본문 매칭 spec 누락: [$TS_SPECS]" ;;
    esac
    case "$TS_ADRS" in
        *0002-pg*) pass "triage-search — 대문자만 등장하는 문서도 점수 유지 (재채점 -i)" ;;
        *) fail "triage-search — 대소문자 재채점 불일치로 ADR 탈락: [$TS_ADRS]" ;;
    esac
    case "$TS_SPECS" in
        *imported*) fail "triage-search — imported 가 specs 에 섞였어요 (별도 카테고리여야)" ;;
        *) pass "triage-search — imported 는 specs 에서 제외" ;;
    esac

    # 한국어 도메인어 — 슬러그가 영문이어도 본문으로 잡혀야 해요
    TS_KO=$(cd "$TS_T" && bash .ax/scripts/bash/triage-search.sh --keywords "정산" --json 2>/dev/null \
            | jq -r '[.result.specs[].path] | join(" ")' 2>/dev/null)
    case "$TS_KO" in
        *009-settlement*) pass "triage-search — 한국어 키워드로 영문 슬러그 spec 매칭" ;;
        *) fail "triage-search — 한국어 키워드 매칭 실패: [$TS_KO]" ;;
    esac
    rm -rf "$TS_T"
fi

# ───────────────────────────────────────────────────────────
section "32. lanes-dispatch — 디스패치 원장 (assign / dispatch / report / status)"
# ───────────────────────────────────────────────────────────
# 코디네이터의 "누구에게 뭘 보냈더라" 는 컨텍스트 안에만 있어서 압축·세션 종료로 사라져요.
# 원장이 tasks.md 에 있어야 tasks-gate G5 가 읽고, dispatch 는 파일 소유 충돌을 거부해야 해요.
LDX=$(mktemp -d)
mkdir -p "$LDX"/.ax/scripts/bash "$LDX"/.ax/docs/spec/012-x
cp "$REPO/templates/default/.ax/scripts/bash/"{common,lanes-dispatch}.sh "$LDX/.ax/scripts/bash/"
cat > "$LDX/.ax/docs/spec/012-x/tasks.md" <<'LDEOF'
- [ ] T001 [AC1] 배럴 — files: ui/index.ts
      의존: 없음
- [ ] T010 [P] [AC1] 카드 — files: ui/Card.tsx
      의존: T001
      검증: pnpm test Card
- [ ] T011 [P] [AC2] 필 — files: ui/Pill.tsx
      의존: T001
- [ ] T021 [AC3] 스크린 — files: app/Result.tsx, ui/Card.tsx
LDEOF
ld() { GOAX_PROJECT_DIR="$LDX" bash "$LDX/.ax/scripts/bash/lanes-dispatch.sh" --spec 012-x "$@" 2>/dev/null; }

ld --json | jq -e '.result.lanes == [] and (.result.unassigned_open | length) == 4' >/dev/null 2>&1 \
    && pass "lanes-dispatch — 배정 없으면 lanes 비고 전부 unassigned" || fail "lanes-dispatch — 초기 status 오류"

# assign: T010(A) 와 T021(B) 가 ui/Card.tsx 를 공유 → 충돌
ld --assign "T010=A,T011=A,T021=B" --json | jq -e '.status == "warning" and (.result.lane_file_conflicts | length) == 1
    and .result.lane_file_conflicts[0].file == "ui/Card.tsx"' >/dev/null 2>&1 \
    && pass "lanes-dispatch --assign — 원장 기록 + 파일 소유 충돌 검출" || fail "lanes-dispatch --assign — 충돌 미검출"
grep -qE '^[[:space:]]+레인: A$' "$LDX/.ax/docs/spec/012-x/tasks.md" \
    && pass "lanes-dispatch --assign — tasks.md 에 레인: 필드가 continuation 으로 기록" || fail "lanes-dispatch --assign — 레인: 필드 미기록"

# dispatch: 충돌 레인은 거부 (exit 1)
ld --dispatch B --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "lanes-dispatch --dispatch — 파일 소유 충돌이면 거부 (exit 1)" || fail "lanes-dispatch --dispatch — 충돌인데 디스패치함"

# 재배정은 --force 필요
ld --assign "T021=A" --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "lanes-dispatch --assign — 다른 레인으로 옮기려면 --force" || fail "lanes-dispatch --assign — 무단 재배정 허용"
ld --assign "T021=A" --force --json | jq -e '.result.lane_file_conflicts == []' >/dev/null 2>&1 \
    && pass "lanes-dispatch --assign --force — 재배정 후 충돌 해소" || fail "lanes-dispatch --assign --force 실패"

# dry-run 은 파일을 안 건드려요
ld --dispatch A --dry-run --json | jq -e '.result.dry_run == true and .result.changed == 3' >/dev/null 2>&1 \
    && ! grep -q '디스패치:' "$LDX/.ax/docs/spec/012-x/tasks.md" \
    && pass "lanes-dispatch --dry-run — 변경 예정 수만 보고, 파일 불변" || fail "lanes-dispatch --dry-run — 파일을 건드림"

# dispatch → dispatched_unreported 3. status 는 ok — 방금 보낸 걸 "보고 안 받았다" 고
# 경고하면 성공 경로가 항상 warning 이라 경고가 신호를 잃어요 (배열은 사실대로 3).
ld --dispatch A --json | jq -e '(.result.dispatched_unreported | length) == 3 and .status == "ok"' >/dev/null 2>&1 \
    && pass "lanes-dispatch --dispatch — 디스패치: 기록 + 보고 대기 3 (성공은 status ok)" || fail "lanes-dispatch --dispatch 실패"

# report 일부 → 남은 것만 대기
ld --report T010 --json | jq -e '.result.dispatched_unreported == ["T011","T021"]' >/dev/null 2>&1 \
    && pass "lanes-dispatch --report <ID> — 일부 보고 반영" || fail "lanes-dispatch --report <ID> 실패"
ld --report A --json | jq -e '.result.dispatched_unreported == []' >/dev/null 2>&1 \
    && pass "lanes-dispatch --report <레인> — 레인 전체 보고 반영" || fail "lanes-dispatch --report <레인> 실패"

# 디스패치 기록 없는 task 보고 → warning (기록은 하되 원장 밖 전달을 드러냄)
ld --report T001 --json | jq -e '(.warnings | length) == 1' >/dev/null 2>&1 \
    && pass "lanes-dispatch --report — 디스패치 기록 없는 보고는 warning" || fail "lanes-dispatch --report — 원장 밖 보고를 조용히 통과시킴"

# 없는 task
ld --assign "T999=A" --json >/dev/null 2>&1; [ $? -eq 1 ] \
    && pass "lanes-dispatch --assign — 없는 task 는 error" || fail "lanes-dispatch --assign — 없는 task 를 통과시킴"

# tier-from-state 의 evaluator 필드 (tasks-gate G6 의 SSOT) — 프로젝트 루트는 fixture 로 고정
cp "$REPO/templates/default/.ax/scripts/bash/tier-from-state.sh" "$LDX/.ax/scripts/bash/"
ev() { GOAX_PROJECT_DIR="$LDX" bash "$LDX/.ax/scripts/bash/tier-from-state.sh" --json --size "$1" --risk "$2" 2>/dev/null | jq -r '.result.evaluator // empty'; }
EV_M3=$(ev M L3); EV_S0=$(ev S L0); EV_XL=$(ev XL L0); EV_L1=$(ev L L1); EV_M2=$(ev M L2)
[ "$EV_M3" = "required" ] && [ "$EV_S0" = "optional" ] && [ "$EV_XL" = "required" ] \
    && [ "$EV_L1" = "required" ] && [ "$EV_M2" = "optional" ] \
    && pass "tier-from-state — evaluator 필수 매트릭스 (M×L3·L·XL 필수, 나머지 선택)" \
    || fail "tier-from-state — evaluator 필드 오류 (M×L3=$EV_M3, S×L0=$EV_S0, XL=$EV_XL, L×L1=$EV_L1, M×L2=$EV_M2)"
rm -rf "$LDX"

# 엣지가 실제로 연결됐는가 — 보내는 쪽만 적고 받는 쪽이 모르면 산문 약속이에요.
grep -q 'lanes-dispatch.sh' "$REPO/skills/spec-implement/SKILL.md" \
    && grep -q 'goax:lane-worker' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — 레인 모드가 원장·lane-worker 를 실제로 호출" \
    || fail "spec-implement — lane 이 넘긴 레인을 받는 코드가 없음"
grep -q 'goax:evaluator' "$REPO/skills/spec-implement/SKILL.md" \
    && grep -q 'review_required' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — 완료 시 evaluator 엣지 연결" \
    || fail "spec-implement — evaluator 를 호출하는 곳이 없음 (triage 매트릭스만 약속)"
grep -q '^verdict:' "$REPO/agents/evaluator.md" \
    && pass "evaluator — review.md 첫 줄 verdict 계약 명시" \
    || fail "evaluator — verdict 계약 없음 (게이트가 읽을 것이 없음)"

smoke_done
