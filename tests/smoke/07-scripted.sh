#!/usr/bin/env bash
# tests/smoke/07-scripted.sh — §34 — 폐기·스크립트화
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/07-scripted.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "34. 폐기·스크립트화 — spirit-lint · rules-index · doctor-scan · status-note · constitution-apply"
# ───────────────────────────────────────────────────────────
# rules·spirit skill 은 "grep 해서 찍어라" 산문이었고, doctor 3.6~3.8 은 SKILL.md 안의 bash 였어요.
# 스크립트가 됐으니 픽스처로 판정을 고정해요. 인계 노트(current-task.json handoff)는 형식이 고정돼야 다음 세션이 파싱해요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§34 skip (jq 없음)"
else
    RS=$(mktemp -d)
    mkdir -p "$RS/.ax/scripts/bash" "$RS/.ax/spirit/rules" "$RS/.ax/modules/order" "$RS/.ax/_templates/spirit" \
             "$RS/.ax/docs/spec/003-x/checklists" "$RS/.ax/hooks/pre-edit" "$RS/.claude"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,spirit-lint,rules-index,doctor-scan,status-note,update-task,tier-from-state,reset-task,constitution-apply}.sh "$RS/.ax/scripts/bash/"
    cp "$REPO/templates/default/.ax/spirit/"{values,tone}.md "$RS/.ax/spirit/"
    cp "$REPO/templates/default/.ax/_templates/spirit/rule.md" "$RS/.ax/_templates/spirit/"
    printf -- '---\ncategory: security\n---\n## SP-SEC-001: 시크릿 커밋 금지\n## SP-SEC-002: 토큰 로그 금지\n' > "$RS/.ax/spirit/rules/security.md"
    printf -- '---\ncategory: naming\npaths:\n  - "**/*.kt"\n---\n## SP-NAM-001: kebab-case\n## 잘못된 헤더\n' > "$RS/.ax/spirit/rules/naming.md"
    printf -- '---\nmodule: order\nkeywords: [order]\n---\n## SP-SEC-001: 중복 토큰\n## SP-ORD-001: 주문은 멱등\n' > "$RS/.ax/modules/order/rules.md"
    printf '# X\n\n## CRITICAL\n\n🔴 **`AX:CRITICAL:001`** — 결제 API 는 멱등성 키 필수\n\n## MANDATORY\n\n🟡 **`AX:MANDATORY:001`** ADR 필수\n\n## CONVENTION\n\n@.ax/spirit/rules/security.md\n' > "$RS/AGENTS.md"
    touch "$RS/.ax/docs/spec/003-x/README.md"; printf '.ax/state.json\n' > "$RS/.gitignore"
    echo '{"hooks":{}}' > "$RS/.claude/settings.json"
    echo '{"phase":"idle"}' > "$RS/.ax/current-task.json"
    rs() { GOAX_PROJECT_DIR="$RS" bash "$RS/.ax/scripts/bash/$1" "${@:2}" 2>/dev/null; }

    # spirit-lint — 비표준 헤더 · 교차 중복 · 카운트
    SLJ=$(rs spirit-lint.sh --json)
    echo "$SLJ" | jq -e '.status=="warning" and (.result.bad_headers|length)==1 and .result.bad_headers[0].line==7' >/dev/null \
        && pass "spirit-lint — 비표준 ## 헤더를 파일:줄 로 지목" || fail "spirit-lint — 비표준 헤더 검출 실패: $(echo "$SLJ" | head -c 200)"
    echo "$SLJ" | jq -e '.result.duplicates[0].token=="SP-SEC-001" and (.result.duplicates[0].files|length)==2' >/dev/null \
        && pass "spirit-lint — spirit ↔ modules 교차 중복 토큰 검출" || fail "spirit-lint — 교차 중복 미검출"
    echo "$SLJ" | jq -e '.result.rules_count==5 and .result.rules_files==2 and .result.files.values==true' >/dev/null \
        && pass "spirit-lint — 토큰 5 · 카테고리 2 · 필수 파일 OK" || fail "spirit-lint — 카운트 불일치"
    rs spirit-lint.sh --json --strict >/dev/null; [ $? -eq 1 ] && pass "spirit-lint --strict — finding 있으면 exit 1" || fail "spirit-lint --strict 가 exit 0"

    # rules-index — 세 소스 · 필터 · find
    RIJ=$(rs rules-index.sh --json)
    echo "$RIJ" | jq -e '.result.counts.critical==1 and .result.counts.mandatory==1 and .result.counts.convention==5 and .result.constitution_file=="AGENTS.md"' >/dev/null \
        && pass "rules-index — Constitution + Spirit + Module 세 소스 집계 (1/1/5)" || fail "rules-index — 집계 불일치: $(echo "$RIJ" | jq -c .result.counts)"
    [ "$(rs rules-index.sh --json --source module | jq -r '[.result.rules[].token]|join(",")')" = "SP-SEC-001,SP-ORD-001" ] \
        && pass "rules-index --source module — 모듈 룰만" || fail "rules-index --source 필터 실패"
    [ "$(rs rules-index.sh --json --find AX:CRITICAL:001 | jq -r '.result.rules[0].line')" = "5" ] \
        && pass "rules-index --find — 토큰 정확 매칭 + 줄 번호" || fail "rules-index --find 실패"
    rs rules-index.sh --json --find NOPE:X:999 | jq -e '.status=="warning" and .result.counts.total==0' >/dev/null \
        && pass "rules-index --find — 없는 토큰은 warning" || fail "rules-index — 없는 토큰을 ok 로"
    rs rules-index.sh | grep -q '📍 AGENTS.md:5' && pass "rules-index 텍스트 — 원문 + 📍 위치" || fail "rules-index 텍스트 출력 형식"

    # contract: — 짝 테스트가 막는 룰을 추적해요 (스칼라+주석 · 블록 목록 · contract_ids)
    mkdir -p "$RS/apps"; printf "it('SP-UI-001: x')\nit('SP-CPY-002: y')\n" > "$RS/apps/ui.test.ts"
    printf -- '---\ncategory: ui\ncontract: apps/ui.test.ts  # 테스트가 막아요\n---\n## SP-UI-001: a\n## SP-UI-002: b\n' > "$RS/.ax/spirit/rules/ui.md"
    printf -- '---\ncategory: cpy\ncontract:\n  - apps/ui.test.ts\n  - apps/none.test.ts\ncontract_ids: [SP-CPY-002, SP-CPY-003]\n---\n## SP-CPY-002: a\n## SP-CPY-003: b\n' > "$RS/.ax/spirit/rules/cpy.md"
    SLC=$(rs spirit-lint.sh --json)
    echo "$SLC" | jq -e '[.result.contracts[]|select(.file==".ax/spirit/rules/cpy.md")][0] | .missing==["apps/none.test.ts"] and .covered==["SP-CPY-002"] and .uncovered==["SP-CPY-003"] and .explicit_ids==true' >/dev/null \
        && pass "spirit-lint F6 — contract: 파일 없음 · contract_ids 중 테스트에 없는 ID 를 지목" || fail "spirit-lint F6 — 계약 검사 불일치: $(echo "$SLC" | jq -c .result.contracts)"
    echo "$SLC" | jq -e '[.result.contracts[]|select(.file==".ax/spirit/rules/ui.md")][0] | .covered==["SP-UI-001"] and .uncovered==["SP-UI-002"] and .explicit_ids==false' >/dev/null \
        && pass "spirit-lint F6 — contract_ids 가 없으면 파일의 모든 SP-ID 를 대상으로 (주석 붙은 스칼라 경로)" || fail "spirit-lint F6 — 스칼라 contract 해석 실패"
    [ "$(echo "$SLC" | jq -r '.result.findings')" -eq "$(( $(echo "$SLJ" | jq -r '.result.findings') + 2 ))" ] \
        && pass "spirit-lint F6 — finding 은 없는 파일 + 직접 적은 ID 만 (전체 대상의 빈 칸은 알림만)" || fail "spirit-lint F6 — finding 수 불일치"
    [ "$(rs rules-index.sh --json | jq -r '[.result.rules[]|select(.contract)|.token]|sort|join(",")')" = "SP-CPY-002,SP-UI-001" ] \
        && rs rules-index.sh | grep -q 'SP-UI-001 — a \[Spirit/ui\] 🧪' \
        && pass "rules-index — 계약이 막는 룰에 contract:true · 🧪" || fail "rules-index — contract 표시 실패"
    rm -rf "$RS/apps" "$RS/.ax/spirit/rules/ui.md" "$RS/.ax/spirit/rules/cpy.md"

    # doctor-scan — 잔재 · hook 등록 · 도달 지도
    DSJ=$(rs doctor-scan.sh --json --plugin-dir "$REPO")
    echo "$DSJ" | jq -e '(.result.migration.gitignore_missing|index(".ax/current-task.json"))!=null and (.result.migration.spec_readme_stale|length)==1 and (.result.migration.spec_empty_dirs|length)==1' >/dev/null \
        && pass "doctor-scan — .gitignore 누락 · spec README · 빈 dir 잔재" || fail "doctor-scan — 마이그레이션 잔재 검출 실패"
    echo "$DSJ" | jq -e '.result.hooks.checked==true and .result.hooks.total>=7 and .result.hooks.registered_n==0' >/dev/null \
        && pass "doctor-scan — template SSOT 기준 hook 등록 검사 (하드코딩 없음)" || fail "doctor-scan — hook 등록 검사 실패"
    echo "$DSJ" | jq -e '[.result.reach[]|select(.source=="constitution")][0].reached==false' >/dev/null \
        && pass "doctor-scan 도달 지도 — AGENTS.md 만 있고 CLAUDE.md 없음 → Constitution 이 어디에도 안 감" || fail "doctor-scan — AGENTS.md-only 를 도달로 봄"
    echo "$DSJ" | jq -e '[.result.reach[]|select(.source=="spirit-universal")][0].reached==true and [.result.reach[]|select(.source=="spirit-scoped")][0].reached==false' >/dev/null \
        && pass "doctor-scan 도달 지도 — @import 된 universal 룰은 도달 · paths 룰은 hook 미등록이라 미도달" || fail "doctor-scan — spirit 도달 판정 불일치"
    printf '@AGENTS.md\n' > "$RS/CLAUDE.md"
    rs doctor-scan.sh --json | jq -e '[.result.reach[]|select(.source=="constitution")][0].reached==true' >/dev/null \
        && pass "doctor-scan 도달 지도 — CLAUDE.md 가 @AGENTS.md 를 import 하면 도달" || fail "doctor-scan — @AGENTS.md import 를 미도달로 봄"

    # status-note — 형식 고정 · 중복 무시 · done · 상한
    rs status-note.sh --add next "1순위 가정 검증" --json | jq -e '.result.added==true' >/dev/null \
        && pass "status-note --add — 4절 골격 생성 + 항목 추가" || fail "status-note --add 실패"
    rs status-note.sh --add next "1순위 가정 검증" --json | jq -e '.result.added==false and .result.reason=="duplicate"' >/dev/null \
        && pass "status-note --add — 같은 줄은 무시 (idempotent)" || fail "status-note — 중복 줄 추가됨"
    rs status-note.sh --set now "spec 014 구현 중\n- T010 halt" --json >/dev/null
    rs status-note.sh --show --json | jq -e '(.result.sections.now|length)==2 and .result.sections.next==["- 1순위 가정 검증"]' >/dev/null \
        && pass "status-note --show — 절별 파싱 (여러 줄 --set 포함)" || fail "status-note --show 파싱 불일치"
    rs status-note.sh --done next "가정 검증" --json | jq -e '.result.removed==1' >/dev/null \
        && pass "status-note --done — 끝난 항목 제거" || fail "status-note --done 실패"
    for i in $(seq 1 40); do rs status-note.sh --add open "q$i" >/dev/null; done
    rs status-note.sh --show --json | jq -e '.status=="warning" and .result.over_cap==true' >/dev/null \
        && pass "status-note — 40개 상한 초과 warning" || fail "status-note — 상한 초과를 ok 로"
    jq -e '.handoff | keys == ["next","now","now_at","open","renamed"] and .now_at != null' "$RS/.ax/current-task.json" >/dev/null \
        && jq -e '.phase=="idle"' "$RS/.ax/current-task.json" >/dev/null \
        && pass "status-note — handoff 키 5개 고정 + now_at 스탬프 + 다른 키 보존" \
        || fail "status-note — handoff 형식/스탬프/키 보존 불일치: $(jq -c '{keys:(.handoff|keys?),now_at:.handoff.now_at,phase}' "$RS/.ax/current-task.json" 2>/dev/null)"
    # now_at 이 바뀌는 건 --set now 뿐이에요 — --add now 가 갱신하면 Stop 게이트의 24시간 침묵 창이 넓어져요
    BEFORE=$(jq -r .handoff.now_at "$RS/.ax/current-task.json")
    rs status-note.sh --add now "x" --json >/dev/null
    [ "$(jq -r .handoff.now_at "$RS/.ax/current-task.json")" = "$BEFORE" ] \
        && pass "status-note --add now — now_at 불변 (게이트 침묵 창 불변)" \
        || fail "status-note --add now — now_at 이 바뀜 ($BEFORE → $(jq -r .handoff.now_at "$RS/.ax/current-task.json"))"
    rs status-note.sh --done now "x" --json >/dev/null
    jq -e --arg b "$BEFORE" '(.handoff.now|length)==2 and .handoff.now_at==$b' "$RS/.ax/current-task.json" >/dev/null \
        && pass "status-note --done now — 남은 줄이 있으면 now_at 유지" \
        || fail "status-note --done now — now/now_at 불일치: $(jq -c '.handoff|{now,now_at}' "$RS/.ax/current-task.json" 2>/dev/null)"
    rs status-note.sh --clear now --json >/dev/null
    jq -e '.handoff.now==[] and .handoff.now_at==null' "$RS/.ax/current-task.json" >/dev/null \
        && pass "status-note --clear now — now 비움 + now_at null" \
        || fail "status-note --clear now — now/now_at 잔존: $(jq -c '.handoff|{now,now_at}' "$RS/.ax/current-task.json" 2>/dev/null)"

    # update-task — SKILL.md 인라인 jq 5곳을 흡수한 writer. in-place 라 handoff · 모르는 키가 살아요.
    jq '.unknown_key = "keep"' "$RS/.ax/current-task.json" > "$RS/ct.tmp" && mv "$RS/ct.tmp" "$RS/.ax/current-task.json"
    UT=$(rs update-task.sh --start --phase triaged --set task_id=T-1 --set "description=두 줄
째" --set size=M --set risk=L2 --set domain=payment --merge-intent '{"why":"a"}' --json)
    echo "$UT" | jq -e '.status=="ok" and .result.phase=="triaged" and (.result.changed|index("started_at"))!=null' >/dev/null \
        && jq -e '.phase=="triaged" and .size=="M" and .risk=="L2" and .domain=="payment" and .task_id=="T-1" and (.description|test("\n"))
                  and .intent_notes.why=="a" and (.started_at|test("^[0-9]{4}-")) and (.updated_at|test("Z$")) and .unknown_key=="keep"
                  and (.handoff.open|length)>=40' "$RS/.ax/current-task.json" >/dev/null \
        && pass "update-task — triage 모양(--start·--set×5·--merge-intent) in-place · handoff·미지 키 보존 · 값 안 줄바꿈 생존" \
        || fail "update-task — triage 모양 불일치: $(echo "$UT" | jq -c .result) $(jq -c '{phase,size,unknown_key,open:(.handoff.open|length)}' "$RS/.ax/current-task.json")"
    rs update-task.sh --merge-intent '{"scope":"b"}' --json >/dev/null
    jq -e '.intent_notes=={"why":"a","scope":"b"}' "$RS/.ax/current-task.json" >/dev/null \
        && rs update-task.sh --merge-intent '{}' --json | jq -e '.result.changed==["updated_at"]' >/dev/null \
        && pass "update-task --merge-intent — 얕은 병합 (기존 키 유지) · '{}' 는 changed 에 안 뜸" || fail "update-task --merge-intent — 병합 불일치: $(jq -c .intent_notes "$RS/.ax/current-task.json")"
    rs update-task.sh --phase spec_blocked --blocked-by '["spec.md:42 NEEDS"]' --json >/dev/null
    rs update-task.sh --phase spec_checked --blocked-by '[]' --json >/dev/null
    jq -e '.phase=="spec_checked" and .blocked_by==[]' "$RS/.ax/current-task.json" >/dev/null \
        && pass "update-task --blocked-by — 통째 교체 · '[]' 로 비움" || fail "update-task --blocked-by 불일치: $(jq -c '{phase,blocked_by}' "$RS/.ax/current-task.json")"
    # 값 검증 — 하나라도 틀리면 아무것도 안 써요. [a-z] 범위가 아니라 enum 이라 'Medium'·'l1' 이 못 지나가요
    UT_B=$(cat "$RS/.ax/current-task.json"); ut_bad=0
    for args in "--phase Done" "--phase idle" "--phase ''" "--phase" "--set --json" "--blocked-by ''" "--merge-intent ''" "--set size=Medium" "--set risk=l1" "--set spec_tier=Full" "--set friction=yolo" "--set foo=bar" "--set domain=" "--set nokv" "--blocked-by 5" "--merge-intent 5" "--json"; do
        # shellcheck disable=SC2086
        out=$(rs update-task.sh $args --json); rc=$?
        { [ "$rc" -eq 1 ] && printf '%s' "$out" | jq -e '.status=="error"' >/dev/null; } || { ut_bad=$((ut_bad+1)); fail "update-task 검증 — '$args' 가 exit=$rc (기대 1/error)"; }
    done
    [ "$ut_bad" -eq 0 ] && [ "$(cat "$RS/.ax/current-task.json")" = "$UT_B" ] \
        && pass "update-task 검증 실패 17종 — exit 1 + error 봉투 + 파일 불변 (빈 값 · 옵션 토큰 · idle · friction enum 포함)" || fail "update-task 검증 — 실패 뒤 파일이 바뀜"
    # friction — 사용자가 이 task 에 미리 준 확인 강도. triage 가 적고 spec-implement 가 읽고 reset 이 비워요
    rs update-task.sh --set friction=autopilot --json | jq -e '.status=="ok" and (.result.changed|index("friction"))!=null' >/dev/null \
        && [ "$(jq -r .friction "$RS/.ax/current-task.json")" = autopilot ] \
        && pass "update-task --set friction=autopilot — 기록" || fail "update-task — friction 키를 못 씀: $(jq -c .friction "$RS/.ax/current-task.json")"
    rs tier-from-state.sh --reset --json >/dev/null 2>&1
    jq -e '.friction==null and .phase=="idle"' "$RS/.ax/current-task.json" >/dev/null \
        && pass "tier-from-state --reset — friction 도 비움 (task 하나에 한한 승인)" || fail "tier-from-state --reset — friction 잔존: $(jq -c .friction "$RS/.ax/current-task.json")"
    rs update-task.sh --phase spec_checked --json >/dev/null 2>&1
    grep -q '"friction": null' "$REPO/templates/default/.ax/current-task.json.template" \
        && grep -q 'friction' "$REPO/skills/spec-implement/SKILL.md" && grep -q 'friction=' "$REPO/skills/triage/SKILL.md" \
        && grep -q 'Rule C0' "$REPO/docs/reference/confirmation-policy.md" \
        && pass "friction — template 키 · triage 기록 · spec-implement 읽기 · 정책 C0 네 곳 동기화" || fail "friction — 쓰는 곳/읽는 곳/정책 중 누락"
    # 자연어로 받는 값이라 두 규율이 글로 있어야 해요 — 확신 없으면 안 적음(오판 비용 비대칭) · 적으면 되묻지 않고 되비춤(거부권).
    # 되비추는 줄은 적는 쪽(triage)과 물려받는 쪽(spec-implement 진입) 둘 다, 그리고 Phase 경계마다 다시 읽어야 도중 변경이 먹어요.
    grep -q '확신이 없으면 적지 않아요' "$REPO/skills/triage/SKILL.md" && grep -q '로 이해했어요' "$REPO/skills/triage/SKILL.md" \
        && grep -q 'triage 사전 승인' "$REPO/skills/spec-implement/SKILL.md" && grep -q 'Phase 경계마다' "$REPO/skills/spec-implement/SKILL.md" \
        && grep -q '확신이 없으면 적지 않아요' "$REPO/docs/reference/confirmation-policy.md" \
        && pass "friction — 확신 없으면 안 적음 · 되묻지 않고 되비춤(triage · spec-implement 진입) · Phase 경계 재읽기" \
        || fail "friction — 자연어 수신 규율(확신·되비춤·재읽기) 누락"
    rs update-task.sh --phase review --dry-run --json | jq -e '.result.dry_run==true and .result.phase=="review"' >/dev/null \
        && [ "$(jq -r .phase "$RS/.ax/current-task.json")" = spec_checked ] && [ ! -d "$RS/.ax/current-task.json.lock" ] \
        && pass "update-task --dry-run — 바뀔 키만 답하고 파일·락 안 건드림" || fail "update-task --dry-run — 파일/락 변동"
    # reset — 파일이 없으면 만들지 않아요 (설치본엔 템플릿이 없고, 최소 파일은 /up 의 seed 를 막아요)
    mv "$RS/.ax/current-task.json" "$RS/ct.bak"
    out=$(rs reset-task.sh --json); rc=$?
    [ "$rc" -eq 1 ] && printf '%s' "$out" | jq -e '.status=="error"' >/dev/null && [ ! -f "$RS/.ax/current-task.json" ] \
        && pass "reset-task — current-task.json 없으면 exit 1 · 파일 안 만듦 (템플릿 fallback 제거)" \
        || fail "reset-task — 파일 없을 때 exit=$rc / 생성=$([ -f "$RS/.ax/current-task.json" ] && echo yes || echo no)"
    mv "$RS/ct.bak" "$RS/.ax/current-task.json"

    # constitution-apply — prepend 보존 · 중복 스캔은 구 본문만 · drop 은 [a] 뒤 · 인덱스
    printf '# X — Constitution\n\n## META — 핵심 가드레일\n\n🔴 **`AX:CRITICAL:001`** — 결제 API 는 멱등성 키 필수\n' > "$RS/block.md"
    printf '# old\n\n## Database\n파일명 규칙: 결제 API 는 멱등성 키 필수\n짧은줄\n' > "$RS/CLAUDE.md"
    rs constitution-apply.sh --block "$RS/block.md" --target CLAUDE.md --json | jq -e '.result.applied==true and .result.preserved_lines==5' >/dev/null \
        && pass "constitution-apply — prepend + 기존 본문 --- 아래 보존" || fail "constitution-apply prepend 실패"
    rs constitution-apply.sh --block "$RS/block.md" --target CLAUDE.md --json >/dev/null; [ $? -eq 2 ] \
        && pass "constitution-apply — 이미 적용이면 exit 2 (idempotent)" || fail "constitution-apply — 재적용을 막지 않음"
    rs constitution-apply.sh --scan-duplicates --block "$RS/block.md" --target CLAUDE.md --json | jq -e '.result.count==1 and (.result.duplicates[0].old_text|test("파일명 규칙"))' >/dev/null \
        && pass "constitution-apply --scan-duplicates — 구 본문의 정확 일치만 (블록 자신은 제외)" || fail "constitution-apply — 중복 스캔 불일치"
    rs constitution-apply.sh --drop-exact --block "$RS/block.md" --target CLAUDE.md --json | jq -e '.result.dropped==1' >/dev/null \
        && grep -q '^짧은줄$' "$RS/CLAUDE.md" && ! grep -q '^파일명 규칙' "$RS/CLAUDE.md" \
        && pass "constitution-apply --drop-exact — 정확 일치 줄만 제거, 나머지 보존" || fail "constitution-apply --drop-exact 실패"
    rs constitution-apply.sh --append-index --target CLAUDE.md --plugin-dir "$REPO" --json | jq -e '.result.applied==true' >/dev/null \
        && grep -q '^## 4계층 인덱스' "$RS/CLAUDE.md" && [ "$(tail -1 "$RS/CLAUDE.md")" != "---" ] \
        && pass "constitution-apply --append-index — 템플릿에서 인덱스 절만 (끝 구분선 제외)" || fail "constitution-apply --append-index 실패"
    rm -rf "$RS"
fi

# writer 계약 — 상태 파일 둘(current-task.json · state.json)은 정해진 출고 스크립트만 써요. 셋/둘이 같은 락 문자열을
# 잡고 in-place 로 쓰는데, SKILL.md·agents 가 인라인 jq 로 직접 쓰면 (a) 무락이라 두 세션에서 항목이 lost-update 되고
# (b) 객체를 통째로 재조립하면 모르는 키(handoff 등)가 사라져요. 그래서 skills·agents 에서는 리다이렉트든 `.tmp` 든
# **어떤 쓰기도** 금지 — 산문에 `<파일>.tmp` 를 적어도 걸려요 (의도한 거예요: 그 문자열이 SKILL.md 에 있을 이유가 없어요).
# 출고 스크립트는 허용 목록 밖에서 금지인데, 경로를 변수에 담아 쓰는 것(`F=.ax/state.json; jq … > "$F.tmp"`)도 잡아요 —
# 실제 writer 둘 다 그렇게 쓰고 있어서 직접 경로만 보면 허용 목록이 한 번도 안 걸려요.
writer_contract() {   # writer_contract <파일명> <허용 스크립트 정규식(basename)>
    local fname="$1" allow="$2" hits="" f vars v
    hits=$(grep -rnE "${fname//./\\.}\\.tmp|>[[:space:]]*\"?[^\" ]*${fname//./\\.}\"?([[:space:]]|\$)" "$REPO/skills" "$REPO/agents" 2>/dev/null || true)
    [ -z "$hits" ] && pass "$fname writer — skills·agents 는 직접 안 씀 (스크립트 경유)" \
                   || fail "$fname writer — skills/agents 가 직접 씀 (무락·미지 키 유실): $hits"
    hits=""
    for f in "$SCRIPTS_DIR"/*.sh; do
        printf '%s' "$(basename "$f")" | grep -qE "^(${allow})\.sh$" && continue
        # (a) 직접 경로
        hits="$hits$(grep -nE ">[[:space:]]*\"?[^\" ]*${fname//./\\.}(\\.tmp(\\.\\\$\\\$)?)?\"?([[:space:]]|\$)" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$(basename "$f"):|" || true)"
        # (b) 변수에 담은 경로 — 그 변수로 리다이렉트·mv 하면 쓰기예요
        # 대입 뒤에 `; REL=…` 나 `# 주석` 이 붙은 줄도 대입이에요 — 줄 끝 앵커만 보면 update-task.sh 의 `FILE=…; REL=…` 꼴이
        # 새 스크립트로 복사될 때 빠져나가요. `(` 를 빼는 건 `X=$(jq … .json …)` 명령 치환을 대입으로 안 보려고요.
        vars=$(grep -oE "^[[:space:]]*(local[[:space:]]+)?[[:alpha:]_][[:alnum:]_]*=[^=;#(]*${fname//./\\.}\"?([[:space:];#]|\$)" "$f" | sed -E 's/^[[:space:]]*(local[[:space:]]+)?([[:alpha:]_][[:alnum:]_]*)=.*/\2/' | sort -u || true)
        for v in $vars; do
            hits="$hits$(grep -nE ">[[:space:]]*\"?\\\$\\{?${v}([^[:alnum:]_]|\$)|mv[[:space:]].*\"?\\\$\\{?${v}([^[:alnum:]_]|\$)" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$(basename "$f"):(\$$v) |" || true)"
        done
    done
    [ -z "$hits" ] && pass "$fname writer — 출고 스크립트는 ${allow//|/ · } 만 (변수 경로 포함)" \
                   || fail "$fname writer — 허용 목록 밖 스크립트가 씀 (락 문자열 계약 밖): $hits"
}
writer_contract current-task.json 'update-task|status-note|tier-from-state'
writer_contract state.json        'update-state|tasks-gate'
ut_edge=0
for pair in "triage|--start --phase triaged" "triage|--merge-intent" "spec|--phase spec " "spec-validate|--phase spec_checked" "spec-validate|--phase spec_blocked" "spec-tasks|--phase tasks" "spec-implement|--phase implementing" "spec-implement|--phase review"; do
    sk="${pair%%|*}"; needle="${pair#*|}"
    grep -qF "update-task.sh $needle" "$REPO/skills/$sk/SKILL.md" 2>/dev/null \
        || { ut_edge=$((ut_edge+1)); fail "$sk — 'update-task.sh ${needle}' 호출 없음 (phase 전이 엣지 끊김)"; }
done
[ "$ut_edge" -eq 0 ] && pass "update-task.sh 호출 엣지 8곳 — triage(triaged·intent) · spec · spec-validate(checked·blocked) · spec-tasks · spec-implement(implementing·review)"

# 엣지 연결 — 폐기된 skill 의 트리거를 누가 받는지, 새 스크립트를 누가 부르는지 파일에 적혀 있어야 해요.
grep -q 'spirit-lint.sh' "$REPO/skills/doctor/SKILL.md" && grep -q 'rules-index.sh' "$REPO/skills/doctor/SKILL.md" && grep -q 'doctor-scan.sh' "$REPO/skills/doctor/SKILL.md" \
    && pass "doctor — spirit-lint · rules-index · doctor-scan 을 실제로 호출" || fail "doctor — 스크립트 호출 엣지 없음"
grep -q 'spirit 점검' "$REPO/skills/doctor/SKILL.md" && grep -q 'rules 보여줘' "$REPO/skills/doctor/SKILL.md" \
    && pass "doctor — 폐기된 spirit·rules 트리거를 description 에서 받음" || fail "doctor — spirit/rules 트리거 미인수 (자연어 라우팅 끊김)"
grep -q 'rules-index.sh' "$REPO/commands/goax.md" && grep -q 'spirit-lint.sh' "$REPO/commands/goax.md" \
    && pass "/goax 인덱스 — rules·spirit 행이 스크립트를 가리킴" || fail "/goax 인덱스 — 폐기 skill 잔재"
grep -q 'status-note.sh --show' "$REPO/skills/triage/SKILL.md" && grep -q 'handoff' "$REPO/skills/triage/SKILL.md" \
    && pass "triage — 인계 노트를 MEMORY.md 보다 먼저 읽음" || fail "triage — 인계 노트 선독 없음"
grep -q 'status-note.sh' "$REPO/skills/spec-implement/SKILL.md" && grep -q 'references/lane-mode.md' "$REPO/skills/spec-implement/SKILL.md" \
    && pass "spec-implement — halt·완료 시 status-note 갱신 + 레인 루프는 references" || fail "spec-implement — 인계 노트/레인 참조 없음"
grep -q 'status-note.sh --add renamed' "$REPO/skills/spec-implement/references/lane-mode.md" \
    && pass "lane-mode — 레인 보고의 바뀐 이름을 인계 노트로" || fail "lane-mode — renamed 인계 없음"
grep -q 'status-note.sh' "$REPO/skills/zero/SKILL.md" && pass "zero — 인계 노트 개설을 스크립트로" || fail "zero — 인계 노트를 손으로 씀"
grep -qE '^disallowedTools:.*Write.*Edit' "$REPO/agents/lane-scout.md" \
    && pass "lane-scout — disallowedTools 로 편집 금지 (allowlist 아님)" || fail "lane-scout — 편집 금지가 산문뿐"
grep -qE '^tools:' "$REPO/agents/lane-scout.md" && fail "lane-scout — tools: allowlist 사용 (한 항목이라도 안 풀리면 에이전트가 안 뜸)" || true
grep -q 'constitution-apply.sh' "$REPO/skills/onboarding/SKILL.md" && grep -q 'zero-domain-risk.sh --show' "$REPO/skills/onboarding/SKILL.md" \
    && pass "onboarding — Q5 prepend 와 Q2 카운트가 스크립트" || fail "onboarding — 산문 prepend/awk 카운트 잔재"
[ -f "$REPO/templates/default/.ax/scripts/bash/build-index.sh" ] || grep -q 'search-index' "$REPO/templates/default/.gitignore.template" \
    && fail ".gitignore.template 에 .search-index 잔재" || pass ".gitignore.template — .search-index 제거"

smoke_done
