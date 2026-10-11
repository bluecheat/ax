#!/usr/bin/env bash
# .ax/scripts/bash/lib/lock.sh — 파일 쓰기 락 — goax_lock · goax_unlock
# common.sh 가 source 해요. 직접 source 하지 않아요.
# shellcheck disable=SC2034  # 여기서 정의한 변수는 common.sh 를 source 한 스크립트가 써요

# ─── 파일 쓰기 락 ───────────────────────────────────────────────────
# goax_lock <lockdir> [timeout_s]  ·  goax_unlock <lockdir>  ·  goax_unlock_all
#   read → 변환 → tmp → mv 를 통째로 감싸요. `mv` 는 원자적이어도 lost-update 는 못 막아요
#   (실측: 레인 원장 동시 보고 30회 중 30회 유실). mkdir 은 POSIX 원자적이라 flock 없이 macOS 에서도 돼요.
#
#   같은 `tmp.$$` && `mv` 패턴을 쓰는 스크립트는 전부 이 헬퍼를 거쳐야 해요:
#     lanes-dispatch · tasks-gate · status-note · update-task · tier-from-state(--reset) · register-spirit-hook ·
#     build-memory · zero-init · zero-domain-risk · constitution-apply · update-state
#
# Usage:
#   goax_lock "$FILE.lock" || fail "다른 프로세스가 원장을 쓰는 중이에요"
#   ... 읽고 바꾸고 mv ...
#   goax_unlock "$FILE.lock"
#
# 이미 EXIT trap 을 건 스크립트는 그 trap 안에서 goax_unlock_all 을 같이 부르세요 —
# goax_lock 이 거는 trap 이 기존 trap 을 덮어써요.
GOAX_LOCKS_HELD=""                              # 개행 구분 (경로에 공백이 있어도 안전)
GOAX_LOCK_STALE="${GOAX_LOCK_STALE:-60}"        # pid 파일이 없는 락을 회수하기까지의 나이 (살아 있는 홀더는 대상 아님)

goax_lock() {
    local dir="${1:-}" timeout="${2:-10}" waited=0 iv="0.05" inc=5 now mt age pid
    [ -n "$dir" ] || return 1
    while :; do
        if mkdir "$dir" 2>/dev/null; then
            printf '%s\n' "$$" > "$dir/pid" 2>/dev/null || true
            GOAX_LOCKS_HELD="${GOAX_LOCKS_HELD}${dir}
"
            trap 'goax_unlock_all' EXIT INT TERM
            return 0
        fi
        # stale 회수 — 2초 넘게 기다린 뒤에만 검사해요 (빠른 경합에서 stat/date 를 안 띄우려고).
        # **살아 있는 홀더는 아무리 오래 잡고 있어도 안 뺏어요** — 타임아웃까지 기다리다 실패해요.
        # 예전엔 디렉토리 mtime 이 60초 넘으면 무조건 회수했는데, mtime 은 잡는 동안 갱신되지 않아서
        # 정당한 홀더(큰 파일·머신 슬립)를 뺏고 둘이 동시에 락을 가진 셈이 됐어요. 회수하는 건 둘뿐이에요:
        #   · pid 파일이 있는데 그 프로세스가 죽었음 (5초 뒤부터)
        #   · pid 파일이 없음 (손으로 만든 락 · mkdir 직후 죽음) 이고 GOAX_LOCK_STALE 을 넘김
        # kill -0 이 "not permitted" 로 실패하면 다른 사용자의 살아 있는 프로세스예요 — 죽은 게 아니에요.
        if [ "$waited" -ge 200 ]; then
            now=$(date +%s)
            mt=$(stat -c %Y "$dir" 2>/dev/null || stat -f %m "$dir" 2>/dev/null || echo "$now")   # GNU 먼저 (위 goax_inject_fresh 주석)
            case "$mt" in ''|*[!0-9]*) mt="$now" ;; esac
            age=$((now - mt))
            pid=$(cat "$dir/pid" 2>/dev/null || true)
            alive=""
            if [ -n "$pid" ]; then
                if kill -0 "$pid" 2>/dev/null; then alive=1
                elif kill -0 "$pid" 2>&1 | grep -qi 'permitted'; then alive=1
                fi
            fi
            if [ -n "$alive" ]; then
                :   # 홀더 생존 — 회수 안 함
            elif [ -n "$pid" ] && [ "$age" -gt 5 ]; then
                goax_warn "stale 락 회수: $dir (${age}s · pid $pid 없음)"
                rm -rf "$dir" 2>/dev/null || true
                continue
            elif [ -z "$pid" ] && [ "$age" -gt "$GOAX_LOCK_STALE" ]; then
                goax_warn "stale 락 회수: $dir (${age}s · pid 파일 없음)"
                rm -rf "$dir" 2>/dev/null || true
                continue
            fi
        fi
        if [ "$waited" -ge $((timeout * 100)) ]; then
            goax_warn "락 대기 시간 초과: $dir (${timeout}s)"
            return 1
        fi
        sleep "$iv" 2>/dev/null || sleep 1
        waited=$((waited + inc))
        if [ "$iv" = "0.05" ]; then iv="0.1"; inc=10
        elif [ "$iv" = "0.1" ]; then iv="0.2"; inc=20; fi
    done
}

goax_unlock() {
    local dir="${1:-}" keep="" d oldIFS
    [ -n "$dir" ] || return 0
    rm -rf "$dir" 2>/dev/null || true
    oldIFS="$IFS"; IFS='
'
    for d in $GOAX_LOCKS_HELD; do
        [ -z "$d" ] && continue
        [ "$d" = "$dir" ] && continue
        keep="${keep}${d}
"
    done
    IFS="$oldIFS"
    GOAX_LOCKS_HELD="$keep"
    return 0
}

goax_unlock_all() {
    local d oldIFS
    oldIFS="$IFS"; IFS='
'
    for d in $GOAX_LOCKS_HELD; do
        [ -n "$d" ] && rm -rf "$d" 2>/dev/null
    done
    IFS="$oldIFS"
    GOAX_LOCKS_HELD=""
    return 0
}
