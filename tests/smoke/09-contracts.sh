#!/usr/bin/env bash
# tests/smoke/09-contracts.sh — §38–§40 — 원장 계약 · 계약 표면 · 룰 집행
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/09-contracts.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "38. lanes-dispatch 원장 계약 — 트랜잭션 · 경로 정규화 · 재디스패치"
# ───────────────────────────────────────────────────────────
# 원장이 반쯤 적히면 "누구에게 뭘 보냈나" 를 아무도 못 믿어요. 그리고 같은 파일을
# `./src/a.ts` 와 `src/a.ts` 로 적으면 소유 충돌 검사가 조용히 꺼졌어요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§38 skip (jq 없음)"
else
    LDG=$(mktemp -d)
    mkdir -p "$LDG"/.ax/scripts/bash "$LDG"/.ax/docs/spec/040-x
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,lanes-dispatch}.sh "$LDG/.ax/scripts/bash/"
    LT="$LDG/.ax/docs/spec/040-x/tasks.md"
    cat > "$LT" <<'LGEOF'
- [ ] T001 [AC1] a — files: ./src/a.ts
      의존: 없음
- [ ] T002 [AC1] b — files: src/a.ts
      의존: 없음
- [ ] T003 [AC2] c — files: src/c.ts
      의존: 없음
LGEOF
    lg() { GOAX_PROJECT_DIR="$LDG" bash "$LDG/.ax/scripts/bash/lanes-dispatch.sh" --spec 040-x "$@" 2>/dev/null; }

    # 트랜잭션 — 하나라도 거부되면 아무것도 안 써요 (반영분 + 거부분이 섞이면 안 돼요)
    cp "$LT" "$LDG/before.md"
    lg --assign "T001=A,T999=B" --json > "$LDG/out.json" 2>&1; LG_RC=$?
    [ "$LG_RC" -eq 1 ] && jq -e '.status=="error" and .result.applied==[] and (.result.rejected|length)==1 and .result.rejected[0].task=="T999"' "$LDG/out.json" >/dev/null 2>&1 \
        && cmp -s "$LT" "$LDG/before.md" \
        && pass "lanes-dispatch --assign — 하나라도 거부되면 exit 1 + 파일 무변경 (2패스)" \
        || fail "lanes-dispatch --assign — 부분 적용 (exit=$LG_RC, 파일 변경 여부 확인)"

    # 경로 정규화 — `./src/a.ts` 와 `src/a.ts` 는 같은 파일이에요
    lg --assign "T001=A,T002=B,T003=A" --json | jq -e '.status=="warning" and (.result.lane_file_conflicts|length)==1
        and .result.lane_file_conflicts[0].file=="src/a.ts"' >/dev/null 2>&1 \
        && pass "lanes-dispatch --assign — ./src/a.ts 와 src/a.ts 를 같은 파일로 (충돌 검출)" \
        || fail "lanes-dispatch --assign — 경로 표기 차이로 충돌 검사가 꺼짐"

    # 성공한 디스패치는 status ok — 방금 보낸 걸 경고하면 warning 이 신호를 잃어요
    lg --assign "T002=A" --force --json >/dev/null 2>&1
    lg --dispatch A --json | jq -e '.status=="ok" and (.result.dispatched_unreported|length)==3' >/dev/null 2>&1 \
        && pass "lanes-dispatch --dispatch — 정상 디스패치는 status ok" || fail "lanes-dispatch --dispatch — 성공인데 warning"

    # 보고까지 받은 task 는 재전송 안 해요 (--dispatch 가 보고 기록을 지우던 회귀)
    lg --report T001 --json >/dev/null 2>&1
    lg --dispatch A --json | jq -e '.result.changed==2 and (.next_step|test("T001"))' >/dev/null 2>&1 \
        && grep -q '^      보고:' "$LT" \
        && pass "lanes-dispatch --dispatch — 보고까지 받은 task 는 건너뜀 (보고 기록 보존)" \
        || fail "lanes-dispatch --dispatch — 보고된 task 를 재전송하거나 보고를 지움"
    lg --dispatch A --force --json | jq -e '.result.changed==3' >/dev/null 2>&1 \
        && pass "lanes-dispatch --dispatch --force — 보고된 것까지 재전송" || fail "lanes-dispatch --force — 재전송 안 함"

    # task 목록 디스패치 — 라운드에 실제로 맡긴 task 만 적어요. 레인 이름으로 보내면 안 맡긴 task 까지
    # "보고 안 받은 디스패치" 에 섞였어요 (실측 4건)
    cat > "$LT" <<'LGEOF'
- [ ] T001 [AC1] a — files: src/a.ts
      레인: A
- [ ] T002 [AC1] b — files: src/b.ts
      레인: A
- [ ] T003 [AC2] c — files: src/c.ts
      레인: A
- [x] T004 [AC2] d — files: src/d.ts
      레인: A
- [ ] T005 [AC3] e — files: src/e.ts
      레인: B
- [ ] T006 [AC3] f — files: src/f.ts
LGEOF
    lg --dispatch T001,T002 --json | jq -e '.status=="ok" and .result.changed==2 and .result.dispatched_unreported==["T001","T002"]
        and .warnings==[] and (.next_step|test("레인 .A."))' >/dev/null 2>&1 \
        && [ "$(grep -c '^      디스패치:' "$LT")" = 2 ] \
        && pass "lanes-dispatch --dispatch T001,T002 — 목록의 task 만 디스패치 (T003 은 그대로)" \
        || fail "lanes-dispatch --dispatch <task 목록> — 목록 밖 task 에도 시각을 찍거나 거부함"
    cp "$LT" "$LDG/before.md"; LG_BAD=""
    for bad in T001,T005 T004 T006 T999; do
        lg --dispatch "$bad" --json >/dev/null 2>&1 && LG_BAD="$LG_BAD $bad(exit0)"
    done
    [ -z "$LG_BAD" ] && cmp -s "$LT" "$LDG/before.md" \
        && pass "lanes-dispatch --dispatch <task 목록> — 여러 레인 · 완료 · 레인 없음 · 없는 ID 는 exit 1 + 파일 무변경" \
        || fail "lanes-dispatch --dispatch <task 목록> — 잘못된 목록을 받아들임:${LG_BAD:- (파일 변경)}"
    lg --report T001 --json >/dev/null 2>&1
    lg --dispatch "T001, T003,T003" --json | jq -e '.result.changed==2 and (.warnings|length)==1 and (.warnings[0]|test("T001"))
        and (.warnings[0]|test("T003")|not)' >/dev/null 2>&1 \
        && ! grep -q '^      보고:' "$LT" \
        && pass "lanes-dispatch --dispatch <task 목록> — 재디스패치는 시각 갱신 · 보고 지움 · warnings (중복 ID 는 한 번)" \
        || fail "lanes-dispatch --dispatch <task 목록> — 재디스패치가 경고 없이 지나가거나 보고를 남김"
    rm -rf "$LDG"
fi

# ───────────────────────────────────────────────────────────
section "39. 계약 표면 — spec-review tier/sha/라운드 · tasks-gate --all · --dry-run"
# ───────────────────────────────────────────────────────────
# `--dry-run` 이 파일을 쓰면 그건 dry-run 이 아니에요. sha 가 spec.md 만 보면
# tasks.md 를 전면 재작성해도 "리뷰 유효" 가 되고요. 빈 상태 파일에 죽으면 안 되고.
if ! command -v jq >/dev/null 2>&1; then
    pass "§39 skip (jq 없음)"
else
    SRV=$(mktemp -d)
    mkdir -p "$SRV"/.ax/scripts/bash "$SRV"/.ax/docs/spec/020-a "$SRV"/.ax/docs/spec/021-b
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,spec-review,tasks-gate,tier-from-state}.sh "$SRV/.ax/scripts/bash/"
    printf '# S\n## 3.\n- [ ] **AC1** a\n' > "$SRV/.ax/docs/spec/020-a/spec.md"
    printf -- '- [ ] T001 [AC1] a — files: a.kt\n' > "$SRV/.ax/docs/spec/020-a/tasks.md"
    printf '# S\n## 3.\n- [ ] **AC1** b\n' > "$SRV/.ax/docs/spec/021-b/spec.md"
    printf -- '- [x] T001 [AC1] b — files: b.kt\n' > "$SRV/.ax/docs/spec/021-b/tasks.md"
    echo '{}' > "$SRV/.ax/state.json"; echo '{"phase":"idle"}' > "$SRV/.ax/current-task.json"
    srv() { GOAX_PROJECT_DIR="$SRV" bash "$SRV/.ax/scripts/bash/spec-review.sh" --spec 020-a "$@" 2>/dev/null; }
    TIER="$SRV/.ax/docs/spec/020-a/.tier"

    # 비활성 spec 은 SSOT(current-task.json)를 못 써요 → `.tier` 로 보수 판정
    echo 'tier: full' > "$TIER"
    srv --status --json | jq -e '.result.required=="required" and (.result.required_source|test("full"))' >/dev/null 2>&1 \
        && pass "spec-review — 비활성 spec + .tier=full → required (.tier 를 실제로 읽음)" || fail "spec-review — .tier 무시 (size 오보)"
    echo 'tier: standard' > "$TIER"
    srv --status --json | jq -e '.result.required=="optional"' >/dev/null 2>&1 \
        && pass "spec-review — .tier=standard → optional" || fail "spec-review — standard 를 required 로"
    rm -f "$TIER"
    srv --status --json | jq -e '.result.required=="required" and (.result.required_source|test("보수"))' >/dev/null 2>&1 \
        && pass "spec-review — .tier 를 못 읽으면 보수적으로 required (모르면 닫아요)" || fail "spec-review — 모를 때 열어줌"
    echo 'tier: full' > "$TIER"

    # sha 는 spec.md + tasks.md 둘 다 — tasks.md 만 바꿔도 리뷰가 낡아요
    SHA_1=$(srv --snapshot --json | jq -r '.result.sha')
    printf -- '- [ ] T002 [AC1] b — files: b.kt\n' >> "$SRV/.ax/docs/spec/020-a/tasks.md"
    srv --status --json | jq -e --arg s "$SHA_1" '.result.sha != $s and (.result.changed_files|index("tasks.md"))' >/dev/null 2>&1 \
        && pass "spec-review — tasks.md 만 바뀌어도 sha 불일치 + changed_files 로 어디가 바뀌었는지" \
        || fail "spec-review — sha 가 spec.md 만 봐서 tasks.md 재작성을 못 잡음"

    # 라운드 상한 — 리뷰어가 본 라운드만 세요. 3 번 보고 4 번째 스냅샷이면 warning (차단은 아니에요, exit 0 유지)
    srv_seen() { local sha; sha=$(srv --status --json | jq -r '.result.sha'); printf 'verdict: 보강 필요\nsha: %s\n' "$sha" | tee "$SRV/.ax/docs/spec/020-a/review-spec.architect.md" > "$SRV/.ax/docs/spec/020-a/review-spec.evaluator.md"; }
    srv --snapshot --json >/dev/null 2>&1          # 안 본 SHA_1 자리를 교체 → round 1
    srv_seen; printf 'r2\n' >> "$SRV/.ax/docs/spec/020-a/spec.md"; srv --snapshot --json >/dev/null 2>&1   # round 2
    srv_seen; printf 'r3\n' >> "$SRV/.ax/docs/spec/020-a/spec.md"; srv --snapshot --json >/dev/null 2>&1   # round 3
    srv_seen; printf 'r4\n' >> "$SRV/.ax/docs/spec/020-a/spec.md"
    SRV_OUT=$(srv --snapshot --json); SRV_RC=$?
    echo "$SRV_OUT" | jq -e '.status=="warning" and .result.round==4 and .result.round_exceeded==true and (.warnings|length)==1' >/dev/null 2>&1 && [ "$SRV_RC" -eq 0 ] \
        && pass "spec-review --snapshot — 리뷰된 3 라운드 뒤 4 번째는 warning (exit 0 유지)" || fail "spec-review — 라운드 상한이 침묵 또는 오산: $(echo "$SRV_OUT" | jq -c '{status,round:.result.round}')"

    # --dry-run 은 어떤 파일도 안 만들어요
    cp "$SRV/.ax/docs/spec/020-a/.review-round" "$SRV/round.before"
    srv --snapshot --dry-run --json >/dev/null 2>&1
    srv --merge --dry-run --json >/dev/null 2>&1
    printf 'dry\n' >> "$SRV/.ax/docs/spec/020-a/spec.md"
    srv --snapshot --dry-run --json >/dev/null 2>&1
    srv --delta --dry-run --json >/dev/null 2>&1
    cmp -s "$SRV/.ax/docs/spec/020-a/.review-round" "$SRV/round.before" && [ ! -f "$SRV/.ax/docs/spec/020-a/review-spec.md" ] \
        && ! grep -q 'dry' "$SRV/.ax/docs/spec/020-a/.review-snapshot/current/spec.md" && [ ! -f "$SRV/.ax/docs/spec/020-a/.review-snapshot/delta.diff" ] \
        && pass "spec-review --dry-run — .review-round · .review-snapshot · delta.diff 불변 + 합본 미생성" || fail "spec-review --dry-run — 파일을 씀"

    # 빈 상태 파일에 죽지 않아요 (jq --argjson 이 빈 문자열로 터지던 회귀)
    : > "$SRV/.ax/docs/spec/020-a/.review-round"
    SRV_OUT=$(srv --status --json); SRV_RC=$?
    echo "$SRV_OUT" | jq -e '.result.round==0' >/dev/null 2>&1 && [ "$SRV_RC" -eq 0 ] \
        && pass "spec-review — 빈 .review-round 도 JSON (round 0)" || fail "spec-review — 빈 상태 파일에 죽음: ${SRV_OUT:0:80}"

    # tasks-gate --all — 합계만 주면 어느 spec 이 문제인지 몰라요
    GOAX_PROJECT_DIR="$SRV" bash "$SRV/.ax/scripts/bash/tasks-gate.sh" --all --json 2>/dev/null \
        | jq -e '.result.spec_count==2 and (.result.specs|length)==2 and (.result.specs|map(.spec)|sort)==["020-a","021-b"] and .result.total==3' >/dev/null 2>&1 \
        && pass "tasks-gate --all — result.specs 배열 + 합계" || fail "tasks-gate --all — spec별 내역 없음"

    # tasks-gate --dry-run 은 봉인값을 안 올려요 (dry-run 이 G4 기준선을 오염시키던 회귀)
    echo '{}' > "$SRV/.ax/state.json"
    GOAX_PROJECT_DIR="$SRV" bash "$SRV/.ax/scripts/bash/tasks-gate.sh" --spec 020-a --dry-run --json >/dev/null 2>&1
    jq -e '(.task_seal // {}) == {}' "$SRV/.ax/state.json" >/dev/null 2>&1 \
        && pass "tasks-gate --dry-run — task_seal 갱신 없음" || fail "tasks-gate --dry-run — 봉인값을 씀"
    GOAX_PROJECT_DIR="$SRV" bash "$SRV/.ax/scripts/bash/tasks-gate.sh" --spec 020-a --json >/dev/null 2>&1
    jq -e '.task_seal["020-a"] == 2' "$SRV/.ax/state.json" >/dev/null 2>&1 \
        && pass "tasks-gate — 일반 실행은 봉인값 기록 (dry-run 과 구분)" || fail "tasks-gate — 일반 실행도 기록 안 함"

    # init-spec-dir --dry-run 은 예약하지 않아요.
    # --reserve 는 디렉토리 생성까지 하는 쓰기라, 호출부가 --dry-run 을 안 넘기면
    # "안 만든다" 고 보고해놓고 빈 spec 디렉토리를 남겨요.
    # next-spec-num 쪽 가드는 §15.x 가 이미 보는데, 그걸 부르는 이 호출부가 사각지대였어요.
    ISD=$(mktemp -d)
    mkdir -p "$ISD/.ax/scripts/bash" "$ISD/.ax/_templates/spec" "$ISD/.ax/docs/spec"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,next-spec-num,init-spec-dir,slug-from-text}.sh \
       "$ISD/.ax/scripts/bash/" 2>/dev/null
    cp -R "$REPO/templates/default/.ax/_templates/spec/." "$ISD/.ax/_templates/spec/" 2>/dev/null
    CLAUDE_PROJECT_DIR="$ISD" bash "$ISD/.ax/scripts/bash/init-spec-dir.sh" \
        --slug ghost --tier standard --dry-run --json >/dev/null 2>&1
    isd_dirs=$(ls -d "$ISD"/.ax/docs/spec/[0-9]* 2>/dev/null | wc -l | tr -d ' ')
    { [ "$isd_dirs" = "0" ] && [ ! -d "$ISD/.ax/docs/spec/.numbers" ]; } \
        && pass "init-spec-dir --dry-run — 디렉토리·번호 원장 둘 다 안 만듦" \
        || fail "init-spec-dir --dry-run — 예약이 샘 (dirs=$isd_dirs, ledger=$([ -d "$ISD/.ax/docs/spec/.numbers" ] && echo yes || echo no))"
    # dry-run 이 보고하는 ID 는 새 형식이어야 하고, 아무것도 안 남겨야 해요 (날짜+난수라 소모될 번호 자체가 없어요)
    isd_a=$(CLAUDE_PROJECT_DIR="$ISD" bash "$ISD/.ax/scripts/bash/init-spec-dir.sh" --slug ghost --tier standard --dry-run --json 2>/dev/null | jq -r '.result.spec_id')
    printf '%s' "$isd_a" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0123456789abcdef]{4}$' \
        && [ "$(ls -d "$ISD"/.ax/docs/spec/[0-9]* 2>/dev/null | wc -l | tr -d ' ')" = 0 ] \
        && pass "init-spec-dir --dry-run — 새 ID 형식으로 보고하고 아무것도 안 만듦 ($isd_a)" \
        || fail "init-spec-dir --dry-run — ID 형식/부작용 이상 ($isd_a)"
    # 일반 실행은 여전히 만들어야 해요 (dry-run 가드가 본 기능을 끄면 안 돼요)
    CLAUDE_PROJECT_DIR="$ISD" bash "$ISD/.ax/scripts/bash/init-spec-dir.sh" \
        --slug real-one --tier standard --json >/dev/null 2>&1
    ls "$ISD"/.ax/docs/spec/*-real-one/spec.md >/dev/null 2>&1 \
        && pass "init-spec-dir — 일반 실행은 <id>-<slug>/spec.md 생성 (dry-run 과 구분)" \
        || fail "init-spec-dir — 일반 실행이 생성 안 함"
    rm -rf "$ISD"
    rm -rf "$SRV"
fi

# ───────────────────────────────────────────────────────────
section "40. 룰 집행 · zero 가드 — severity 를 읽는가, 갓 설치가 CI 초록인가"
# ───────────────────────────────────────────────────────────
# I1(🔴 은 hook/external 만) 검사가 spirit/module 룰 전체에서 죽어 있었어요 — 추출기가
# label 을 "convention" 리터럴로 고정해서 `severity: critical` 이 아예 안 읽혔거든요.
# 반대로 갓 설치한 프로젝트는 출고 예시(`<...>`) 때문에 `--strict` 가 항상 빨간불이라
# CI 에 켤 수가 없었고요. 둘 다 실행으로 고정해요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§40 skip (jq 없음)"
else
    RE=$(mktemp -d)
    mkdir -p "$RE/.ax/scripts/bash" "$RE/.ax/spirit/rules"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,check-rule-enforcement}.sh "$RE/.ax/scripts/bash/"
    printf '# X\n' > "$RE/AGENTS.md"
    printf -- '---\ncategory: sec\nseverity: critical\nenforced_by: human:code-review\n---\n## SP-SEC-001: 시크릿 금지\n' > "$RE/.ax/spirit/rules/sec.md"
    GOAX_PROJECT_DIR="$RE" bash "$RE/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null \
        | jq -e '(.result.i1_violations|length)==1 and .result.i1_violations[0].rule_id=="SPIRIT:SEC"' >/dev/null 2>&1 \
        && pass "check-rule-enforcement I1 — spirit frontmatter 의 severity: critical 을 실제로 읽음" \
        || fail "check-rule-enforcement I1 — severity 미파싱 (frontmatter 룰 전체가 사각지대)"
    printf -- '---\ncategory: sec\nseverity: mandatory\nenforced_by: human:code-review\n---\n## SP-SEC-001: 시크릿 금지\n' > "$RE/.ax/spirit/rules/sec.md"
    GOAX_PROJECT_DIR="$RE" bash "$RE/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null \
        | jq -e '.result.i1_violations == []' >/dev/null 2>&1 \
        && pass "check-rule-enforcement I1 — 🟡 로 낮추면 human:* 허용" || fail "check-rule-enforcement I1 — mandatory 도 잡음"
    rm -rf "$RE"

    # I5 배선 판정 — .ax/hooks/pre-commit/*.sh 는 settings.json 에 개별 등록되지 않아요.
    # grep-on-commit.sh(에이전트 커밋)와 git chain wrapper(사람 커밋)가 디렉토리째 glob 하는데
    # basename 리터럴로만 찾던 탓에 배선이 멀쩡해도 늘 미등록으로 나왔어요. 반대로 디스패처가
    # 둘 다 없으면 여전히 잡혀야 하고요 — 오탐을 지우려다 거짓 음성을 만들면 더 나빠요.
    i5_reg_n() {   # i5_reg_n <project-dir> → I5 미등록 건수
        GOAX_PROJECT_DIR="$1" bash "$1/.ax/scripts/bash/check-rule-enforcement.sh" --json 2>/dev/null \
            | jq -r '.result.i5_not_registered|length'
    }
    i5_rule() {    # i5_rule <project-dir> <hook-relpath>
        printf -- '---\ncategory: ops\nseverity: critical\nenforced_by: hook:%s\n---\n## SP-OPS-001: 팀 룰\n' \
            "$2" > "$1/.ax/spirit/rules/ops.md"
    }
    I5T=$(mktemp -d)
    git -C "$I5T" init -q >/dev/null 2>&1
    mkdir -p "$I5T/.ax/scripts/bash" "$I5T/.ax/spirit/rules" "$I5T/.ax/hooks/pre-commit" \
             "$I5T/.ax/hooks/pre-edit" "$I5T/.claude"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,check-rule-enforcement}.sh "$I5T/.ax/scripts/bash/"
    printf '# X\n' > "$I5T/AGENTS.md"
    printf '#!/usr/bin/env bash\n' > "$I5T/.ax/hooks/pre-commit/team-rules.sh"
    i5_rule "$I5T" ".ax/hooks/pre-commit/team-rules.sh"

    printf '{"hooks":{}}\n' > "$I5T/.claude/settings.json"
    [ "$(i5_reg_n "$I5T")" = "1" ] \
        && pass "check-rule-enforcement I5 — 디스패처가 하나도 없으면 pre-commit hook 도 미배선으로 잡음" \
        || fail "check-rule-enforcement I5 — 디스패처 없는데 통과 (거짓 음성)"

    printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash .ax/hooks/pre-bash/grep-on-commit.sh"}]}]}}\n' \
        > "$I5T/.claude/settings.json"
    [ "$(i5_reg_n "$I5T")" = "0" ] \
        && pass "check-rule-enforcement I5 — grep-on-commit.sh 등록이면 pre-commit hook 은 배선됨" \
        || fail "check-rule-enforcement I5 — glob 디스패처를 못 보고 오탐"

    printf '{"hooks":{}}\n' > "$I5T/.claude/settings.json"
    printf '#!/usr/bin/env bash\n#goax-pre-commit-chain\n' > "$I5T/.git/hooks/pre-commit"
    chmod +x "$I5T/.git/hooks/pre-commit"
    [ "$(i5_reg_n "$I5T")" = "0" ] \
        && pass "check-rule-enforcement I5 — git chain wrapper 만 있어도 배선 인정 (사람 커밋 경로)" \
        || fail "check-rule-enforcement I5 — .git/hooks/pre-commit 을 안 봄 (rule-enforcement.md I5 명세 위반)"

    printf '#!/usr/bin/env bash\n' > "$I5T/.ax/hooks/pre-edit/guard.sh"
    i5_rule "$I5T" ".ax/hooks/pre-edit/guard.sh"
    [ "$(i5_reg_n "$I5T")" = "1" ] \
        && pass "check-rule-enforcement I5 — pre-commit 밖 hook 은 여전히 settings.json 등록 필요" \
        || fail "check-rule-enforcement I5 — 예외가 pre-commit 밖으로 샘"
    rm -rf "$I5T"

    # 갓 provision 한 프로젝트가 --strict 초록이어야 CI 예시(harness job)를 켤 수 있어요
    STRICT_T=$(mktemp -d)
    bash "$REPO/scripts/provision.sh" --target "$STRICT_T" --json >/dev/null 2>&1
    STRICT_OUT=$(GOAX_PROJECT_DIR="$STRICT_T" bash "$STRICT_T/.ax/scripts/bash/check-rule-enforcement.sh" --json --strict 2>/dev/null); STRICT_RC=$?
    [ "$STRICT_RC" -eq 0 ] && echo "$STRICT_OUT" | jq -e '(.result.i1_violations|length)==0 and (.result.i2_violations|length)==0 and (.result.placeholder_rules|length)>0' >/dev/null 2>&1 \
        && pass "check-rule-enforcement --strict — 갓 설치는 exit 0 (출고 예시는 placeholder_rules 로)" \
        || fail "check-rule-enforcement --strict — 갓 설치가 exit $STRICT_RC (CI 에 켤 수 없음)"
    rm -rf "$STRICT_T"

    # zero-guard-bash — 실행은 막고 *언급* 은 통과. 언급까지 막으면 룰을 문서에 못 적어요.
    ZGP=$(mktemp -d); mkdir -p "$ZGP/.ax/hooks"
    zg_rc() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$1" \
        | CLAUDE_PROJECT_DIR="$ZGP" bash "$REPO/templates/zero/hooks/zero-guard-bash.sh" >/dev/null 2>&1; echo $?; }
    zg_block() { [ "$(zg_rc "$1")" = "2" ] && pass "zero-guard-bash 차단: $2" || fail "zero-guard-bash 미차단: $2"; }
    zg_pass()  { [ "$(zg_rc "$1")" = "0" ] && pass "zero-guard-bash 통과: $2" || fail "zero-guard-bash 오탐 차단: $2"; }
    zg_block '"git add -A"'                                  'git add -A'
    zg_block '"git add --all"'                               'git add --all'
    zg_block '"cd x && git add -A"'                          '세그먼트 뒤 git add -A'
    zg_pass  '"git commit -m \"docs: never git add -A\""'    '커밋 메시지 안의 인용'
    zg_pass  '"echo \"git add -A\""'                         'echo 인용'
    zg_pass  '"grep -rn \"git add -A\" docs/"'               'grep 인자 인용'
    zg_pass  '"# git add -A"'                                '# 주석'
    rm -rf "$ZGP"
fi

smoke_done
