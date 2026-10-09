#!/usr/bin/env bash
# tests/smoke/12-locks.sh — §43 — 파일 쓰기 락
# smoke 조각이에요. 혼자 돌려도 돼요: bash tests/smoke/12-locks.sh — 전체는 bash tests/smoke.sh
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# ───────────────────────────────────────────────────────────
section "43. 파일 쓰기 락 — 같은 파일을 두 프로세스가 쓸 때"
# ───────────────────────────────────────────────────────────
# §36 이 원장(tasks.md·state.json)을 봤다면 여기는 나머지 넷이에요 — current-task.json(handoff) ·
# .claude/settings.json · AGENTS.md · .ax/config.yml. 락 창이 `mv` 가 아니라 **"바꿀지 정하는
# 첫 읽기"** 부터여야 멱등 프로브가 보호돼요. 실측(수정 전): zero-init 5개 동시 실행이 같은
# 훅을 3번 등록했고, status-note --add 동시 2개는 10회 중 10회 한쪽을 잃었어요.
# **결과가 1회분인 것과 함께 각 프로세스의 exit 0 도 봐요** — zero-init 은 --plugin-dir 이
# 없으면, constitution-apply --append-index 는 인덱스 원본이 없으면 아무것도 안 쓰고 exit 2 라
# 결과 어서션만으로는 공허하게 초록이에요.
if ! command -v jq >/dev/null 2>&1; then
    pass "§43 skip (jq 없음)"
else
    LK=$(mktemp -d)
    mkdir -p "$LK/.ax/scripts/bash" "$LK/.ax/docs" "$LK/.claude"
    cp "$REPO/templates/default/.ax/scripts/bash/"{common,status-note,update-task,tier-from-state,register-spirit-hook,build-memory,zero-init,constitution-apply,zero-domain-risk}.sh "$LK/.ax/scripts/bash/"
    LKB="$LK/.ax/scripts/bash"
    # 최소 대상 — 출고 AGENTS.md 는 이미 `## 4계층 인덱스` 와 AX 토큰을 담고 있어서
    # prepend·index 두 모드가 전부 skip(exit 2) 로 빠져요. 경합을 재려면 둘 다 없어야 해요.
    seed_lk() {
        printf '{"hooks":{}}\n' > "$LK/.claude/settings.json"
        printf '# 픽스처 — Constitution\n\n## 개요\n\n회귀용 최소 대상이에요.\n' > "$LK/AGENTS.md"
        printf 'default_risk: L1\ndomain_risk:\n  payment: L3\n  search: L1\n  billing: L2\n  auth: L3\n' > "$LK/.ax/config.yml"
        echo '{"phase":"idle"}' > "$LK/.ax/current-task.json"
        rm -rf "$LK"/*.lock "$LK"/.ax/*.lock "$LK"/.claude/*.lock "$LK"/.ax/docs/*.lock
    }
    printf '## FIXTURE — 회귀용 가드레일\n\n🔴 **`AX:CRITICAL:901`** — 시크릿을 커밋하지 않아요.\n' > "$LK/block.md"
    printf '## 4계층 인덱스\n\n- Layer 1 — Constitution\n' > "$LK/.ax/AGENTS.md.suggested"
    lkrun() { local s="$1"; shift; GOAX_PROJECT_DIR="$LK" bash "$LKB/$s" "$@"; }

    # 1) 동일 스크립트 동시 실행 — 멱등 프로브가 락 안에 있는가
    seed_lk
    rc1=""
    for i in 1 2 3 4 5; do ( lkrun register-spirit-hook.sh --json >/dev/null 2>&1; echo $? > "$LK/rc.$i" ) & done
    wait
    for i in 1 2 3 4 5; do rc1="$rc1$(cat "$LK/rc.$i")"; done
    [ "$(grep -c 'spirit-rules-inject\.sh' "$LK/.claude/settings.json")" -eq 1 ] && [ "$rc1" = "00000" ] \
        && pass "register-spirit-hook ×5 동시 — 훅 정확히 1회 등록 (전부 exit 0)" \
        || fail "register-spirit-hook ×5 동시 — 등록 $(grep -c 'spirit-rules-inject\.sh' "$LK/.claude/settings.json")회 / rc=$rc1"

    seed_lk
    rc2=""; zi_skip=0; zi_ok=0
    for i in 1 2 3 4 5; do ( lkrun zero-init.sh --plugin-dir "$REPO" --json >/dev/null 2>&1; echo $? > "$LK/rc.$i" ) & done
    wait
    for i in 1 2 3 4 5; do
        r=$(cat "$LK/rc.$i"); rc2="$rc2$r"
        [ "$r" = 2 ] && zi_skip=$((zi_skip+1))
        [ "$r" = 0 ] && zi_ok=$((zi_ok+1))
    done
    # exit 2 는 "--plugin-dir 을 못 찾아 아무것도 안 썼다" 라서 하나라도 섞이면 이 어서션이 공허해요.
    # 다섯 다 exit 0 이어야 해요 — 리눅스 GNU cp 가 같은 템플릿을 동시에 복사하다 "File exists" 로
    # 죽던 copy_one 의 TOCTOU 는 "목적지가 이미 있으면 설치됨" 으로 흡수했어요.
    [ "$(grep -c 'zero-guard-bash\.sh' "$LK/.claude/settings.json")" -eq 1 ] && [ "$zi_skip" -eq 0 ] && [ "$zi_ok" -eq 5 ] \
        && pass "zero-init ×5 동시 — 훅 정확히 1회 등록 · 전부 exit 0 (복사 경합 허용)" \
        || fail "zero-init ×5 동시 — 등록 $(grep -c 'zero-guard-bash\.sh' "$LK/.claude/settings.json")회 / rc=$rc2"

    seed_lk
    for i in 1 2; do ( lkrun constitution-apply.sh --block "$LK/block.md" --target AGENTS.md --json >/dev/null 2>&1 ) & done
    wait
    [ "$(grep -c 'AX:CRITICAL:901' "$LK/AGENTS.md")" -eq 1 ] \
        && pass "constitution-apply prepend ×2 동시 — 블록이 한 번만 실림" \
        || fail "constitution-apply prepend ×2 동시 — $(grep -c 'AX:CRITICAL:901' "$LK/AGENTS.md")회 실림"

    seed_lk
    rc4=""
    for i in 1 2 3 4 5; do ( lkrun status-note.sh --init --json >/dev/null 2>&1; echo $? > "$LK/rc.$i" ) & done
    wait
    for i in 1 2 3 4 5; do rc4="$rc4$(cat "$LK/rc.$i")"; done
    jq -e '.handoff | keys == ["next","now","now_at","open","renamed"]' "$LK/.ax/current-task.json" >/dev/null 2>&1 \
        && jq -e '.phase=="idle"' "$LK/.ax/current-task.json" >/dev/null 2>&1 && [ "$rc4" = "00000" ] \
        && pass "status-note --init ×5 동시 — handoff 키 5개 정확히 · phase 보존 (전부 exit 0)" \
        || fail "status-note --init ×5 동시 — $(jq -c '{keys:(.handoff|keys?),phase}' "$LK/.ax/current-task.json" 2>/dev/null) / rc=$rc4"

    # 2) 교차 실행 — 락 경로가 갈리면 여기서 빨개져요
    lost=0
    for i in 1 2 3 4 5 6 7 8 9 10; do
        seed_lk; lkrun status-note.sh --init --json >/dev/null 2>&1
        ( lkrun status-note.sh --add next "항목A" --json >/dev/null 2>&1 ) &
        ( lkrun status-note.sh --add next "항목B" --json >/dev/null 2>&1 ) &
        wait
        jq -e '.handoff.next | (index("- 항목A")!=null and index("- 항목B")!=null)' "$LK/.ax/current-task.json" >/dev/null 2>&1 || lost=$((lost+1))
    done
    [ "$lost" -eq 0 ] && pass "status-note --add 동시 10회 — 항목 유실 0 (수정 전 10/10 유실)" \
                      || fail "status-note --add 동시 10회 — ${lost}회 유실"

    both=0
    for i in 1 2 3 4 5; do
        seed_lk
        ( lkrun register-spirit-hook.sh --json >/dev/null 2>&1; echo $? > "$LK/rc.a" ) &
        ( lkrun zero-init.sh --plugin-dir "$REPO" --json >/dev/null 2>&1; echo $? > "$LK/rc.b" ) &
        wait
        [ "$(grep -c 'spirit-rules-inject\.sh' "$LK/.claude/settings.json")" -ge 1 ] \
            && [ "$(grep -c 'zero-guard-bash\.sh' "$LK/.claude/settings.json")" -ge 1 ] \
            && [ "$(cat "$LK/rc.a")" = 0 ] && [ "$(cat "$LK/rc.b")" = 0 ] && both=$((both+1))
    done
    [ "$both" -eq 5 ] && pass "register-spirit-hook ‖ zero-init 5회 — 두 훅 다 생존 (락 경로 문자열 동일)" \
                      || fail "register-spirit-hook ‖ zero-init — $both/5회만 둘 다 생존"

    # current-task.json 을 쓰는 두 스크립트 — status-note 의 handoff 추가와 tier-from-state 의 task 필드 리셋이
    # 같은 락을 잡아야 해요. seed 는 implementing — idle 로 심으면 phase 판정이 공허해요.
    ct_both=0
    for i in 1 2 3 4 5; do
        seed_lk; echo '{"phase":"implementing"}' > "$LK/.ax/current-task.json"
        ( lkrun status-note.sh --add next "항목$i" --json >/dev/null 2>&1 ) &
        ( lkrun tier-from-state.sh --reset --json >/dev/null 2>&1 ) &
        wait
        jq -e --arg i "- 항목$i" '(.handoff.next|index($i))!=null and .phase=="idle"' "$LK/.ax/current-task.json" >/dev/null 2>&1 && ct_both=$((ct_both+1))
    done
    [ "$ct_both" -eq 5 ] && pass "status-note --add ‖ tier-from-state --reset 5회 — 둘 다 생존 (락 경로 문자열 동일)" \
                         || fail "status-note --add ‖ tier-from-state --reset — $ct_both/5회만 둘 다 생존"

    # update-task(phase) ‖ status-note(handoff) — 예전엔 phase 쪽이 SKILL.md 인라인 jq 라 무락이었고, 이 조합이
    # handoff 항목을 잃던 자리예요. 이제 셋이 같은 락이라 둘 다 살아야 해요.
    ut_both=0
    for i in 1 2 3 4 5; do
        seed_lk
        ( lkrun update-task.sh --phase implementing --set "domain=d$i" --json >/dev/null 2>&1 ) &
        ( lkrun status-note.sh --add open "질문$i" --json >/dev/null 2>&1 ) &
        wait
        jq -e --arg i "- 질문$i" --arg d "d$i" '(.handoff.open|index($i))!=null and .phase=="implementing" and .domain==$d' "$LK/.ax/current-task.json" >/dev/null 2>&1 && ut_both=$((ut_both+1))
    done
    [ "$ut_both" -eq 5 ] && pass "update-task --phase ‖ status-note --add 5회 — 둘 다 생존 (인라인 jq 시절의 lost-update 자리)" \
                         || fail "update-task ‖ status-note — $ut_both/5회만 둘 다 생존"

    survive=0
    for i in 1 2 3 4 5; do
        seed_lk
        ( lkrun constitution-apply.sh --append-index --target AGENTS.md --json >/dev/null 2>&1; echo $? > "$LK/rc.a" ) &
        ( lkrun constitution-apply.sh --block "$LK/block.md" --target AGENTS.md --json >/dev/null 2>&1; echo $? > "$LK/rc.b" ) &
        wait
        [ "$(grep -c '^## 4계층 인덱스' "$LK/AGENTS.md")" -ge 1 ] \
            && [ "$(grep -c 'AX:CRITICAL:901' "$LK/AGENTS.md")" -ge 1 ] \
            && [ "$(cat "$LK/rc.a")" = 0 ] && [ "$(cat "$LK/rc.b")" = 0 ] && survive=$((survive+1))
    done
    [ "$survive" -eq 5 ] && pass "constitution-apply --append-index ‖ --block 5회 — 인덱스·prepend 둘 다 생존" \
                         || fail "constitution-apply --append-index ‖ --block — $survive/5회만 둘 다 생존"

    seed_lk
    rc8=""
    for i in 1 2 3 4 5; do ( lkrun zero-domain-risk.sh --set "payment=L3,search=L1,billing=L2,auth=L3" --json >/dev/null 2>&1; echo $? > "$LK/rc.$i" ) & done
    wait
    for i in 1 2 3 4 5; do rc8="$rc8$(cat "$LK/rc.$i")"; done
    dr_n=$(awk '/^domain_risk:/{f=1;next} f && /^[^[:space:]]/{f=0} f && NF' "$LK/.ax/config.yml" | grep -c ':')
    [ "$dr_n" -eq 4 ] && [ "$rc8" = "00000" ] \
        && pass "zero-domain-risk ×5 동시 — domain_risk 4개 보존 (전부 exit 0)" \
        || fail "zero-domain-risk ×5 동시 — domain_risk ${dr_n}개 / rc=$rc8"

    seed_lk
    for i in 1 2; do ( lkrun build-memory.sh --json >/dev/null 2>&1 ) & done
    wait
    case "$(head -1 "$LK/.ax/MEMORY.md" 2>/dev/null)" in
        '#'*) [ "$(find "$LK/.ax" -name 'MEMORY.md.tmp.*' | wc -l | tr -d ' ')" -eq 0 ] \
                && pass "build-memory ×2 동시 — MEMORY.md 온전 · .tmp.\$\$ 잔존 0" \
                || fail "build-memory ×2 동시 — .tmp.\$\$ 잔존물" ;;
        *) fail "build-memory ×2 동시 — MEMORY.md 반쪽" ;;
    esac

    # 3) 계약 — dry-run 은 락도 파일도 안 만들어요
    seed_lk
    lkrun status-note.sh --add next "드라이" --dry-run --json >/dev/null 2>&1
    lkrun status-note.sh --set now "드라이" --dry-run --json >/dev/null 2>&1
    lkrun update-task.sh --phase spec --dry-run --json >/dev/null 2>&1
    lkrun register-spirit-hook.sh --dry-run --json >/dev/null 2>&1
    lkrun build-memory.sh --dry-run --json >/dev/null 2>&1
    lkrun zero-init.sh --plugin-dir "$REPO" --dry-run --json >/dev/null 2>&1
    lkrun constitution-apply.sh --block "$LK/block.md" --target AGENTS.md --dry-run --json >/dev/null 2>&1
    lkrun zero-domain-risk.sh --set "payment=L3" --dry-run --json >/dev/null 2>&1
    [ "$(find "$LK" -name '*.lock' | wc -l | tr -d ' ')" -eq 0 ] && jq -e 'has("handoff")|not' "$LK/.ax/current-task.json" >/dev/null 2>&1 \
        && pass "--dry-run 8종 — .lock 을 안 만들고 handoff 도 안 만듦" \
        || fail "--dry-run — .lock $(find "$LK" -name '*.lock' | wc -l | tr -d ' ')개 / handoff $(jq -r 'has("handoff")' "$LK/.ax/current-task.json" 2>/dev/null)"

    # 4) 계약 — 이미 잡힌 락 앞에서는 exit 1 + {"status":"error"} (기본 10s 를 기다리지 않게 =1)
    seed_lk
    lkrun status-note.sh --init --json >/dev/null 2>&1
    mkdir -p "$LK/.ax/current-task.json.lock" "$LK/.claude/settings.json.lock" "$LK/.ax/MEMORY.md.lock" \
             "$LK/AGENTS.md.lock" "$LK/.ax/config.yml.lock"
    lock_bad=0
    check_locked() {   # check_locked <라벨> <스크립트> [인자…]
        local label="$1" script="$2"; shift 2
        local out rc st
        out=$(GOAX_LOCK_TIMEOUT=1 GOAX_PROJECT_DIR="$LK" bash "$LKB/$script" "$@" 2>/dev/null); rc=$?
        st=$(printf '%s' "$out" | tail -1 | jq -r '.status' 2>/dev/null || echo '-')
        if [ "$rc" -ne 1 ] || [ "$st" != "error" ]; then
            lock_bad=$((lock_bad+1)); fail "락 대기 초과 — $label 이 exit=$rc status=$st (기대 1/error)"
        fi
    }
    check_locked status-note        status-note.sh --add next "락테스트" --json
    check_locked register-spirit    register-spirit-hook.sh --json
    check_locked build-memory       build-memory.sh --json
    check_locked zero-init          zero-init.sh --plugin-dir "$REPO" --json
    check_locked constitution-apply constitution-apply.sh --block "$LK/block.md" --target AGENTS.md --force --json
    check_locked zero-domain-risk   zero-domain-risk.sh --set "payment=L2" --json
    check_locked tier-from-state    tier-from-state.sh --reset --json
    check_locked update-task        update-task.sh --phase spec --json
    [ "$lock_bad" -eq 0 ] && pass "락 대기 초과 8종 — exit 1 + {\"status\":\"error\"} 봉투 (GOAX_LOCK_TIMEOUT=1)"
    # 손으로 만든 락엔 pid 파일이 없고 stale 문턱에 닿기 전에 타임아웃 나서, 뺏기지 않아요
    [ "$(find "$LK" -name '*.lock' -type d | wc -l | tr -d ' ')" -eq 5 ] \
        && pass "락 대기 초과 — 남의 락을 뺏지 않음 (5개 그대로)" \
        || fail "락 대기 초과 — 손으로 만든 락 5개 중 $(find "$LK" -name '*.lock' -type d | wc -l | tr -d ' ')개만 남음"

    # stale 회수 — 살아 있는 홀더는 mtime 이 아무리 오래돼도 안 뺏고, 죽은 pid 의 락만 회수
    LSD="$LK/stale-test.lock"; rm -rf "$LSD"; mkdir "$LSD"
    sleep 30 & LS_PID=$!
    printf '%s\n' "$LS_PID" > "$LSD/pid"; touch -t 202001010000 "$LSD"
    GOAX_LOCK_STALE=1 bash -c "source '$REPO/templates/default/.ax/scripts/bash/common.sh'; goax_lock '$LSD' 3" >/dev/null 2>&1; ls_rc=$?
    { [ "$ls_rc" -ne 0 ] && [ -d "$LSD" ]; } \
        && pass "goax_lock — 살아 있는 홀더의 락은 mtime 이 오래돼도 안 뺏음 (타임아웃 exit 1)" \
        || fail "goax_lock — 살아 있는 홀더의 락을 뺏음 (rc=$ls_rc, dir=$([ -d "$LSD" ] && echo 있음 || echo 없음))"
    kill "$LS_PID" 2>/dev/null; wait "$LS_PID" 2>/dev/null || true
    touch -t 202001010000 "$LSD"
    GOAX_LOCK_STALE=1 bash -c "source '$REPO/templates/default/.ax/scripts/bash/common.sh'; goax_lock '$LSD' 5" >/dev/null 2>&1; ls_rc=$?
    [ "$ls_rc" -eq 0 ] \
        && pass "goax_lock — 죽은 pid 의 락은 회수 (5초 지난 것)" \
        || fail "goax_lock — 죽은 pid 의 락을 회수 못 함 (rc=$ls_rc)"
    rm -rf "$LSD"

    rm -rf "$LK"
fi

smoke_done
