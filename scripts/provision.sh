#!/usr/bin/env bash
# scripts/provision.sh — templates/default/ 를 사용자 프로젝트로 설치 (up skill 의 실행부)
#
# Usage:
#   bash scripts/provision.sh [--target <dir>] [--json] [--dry-run] [--help]
#
# 왜 스크립트인가 — 이 로직은 원래 `skills/up/SKILL.md` 안에 266줄짜리 bash 블록으로
# 살았어요. 리포 규칙("재현 가능한 건 스크립트로, SKILL.md 는 트리거·대화·JSON 파싱만")
# 위반이었고, 더 나쁜 건 마크다운 안의 bash 는 *파일이 아니라서* `bash -n` 도 CI 도
# 닿지 않았다는 거예요. 하필 사용자가 제일 먼저 돌리는 코드가 거기 있었어요.
#
# 왜 `.ax/scripts/bash/` 가 아닌가 — 이 스크립트는 `.ax/` 를 *만드는* 쪽이에요.
# 실행 시점엔 아직 `.ax/` 가 없으니 거기 살 수 없어요. plugin 자산이에요.
#
# 설치 규칙 3층:
#   ① MANIFEST 무조건 복사   — `/` 로 끝나면 디렉토리 재귀 merge, 아니면 파일 덮어쓰기
#   ② MANIFEST `src -> dst`  — seed-only. 이미 있으면 안 건드려요 (진행 중인 런타임 상태)
#   ③ MANIFEST 외 조건부     — 사용자가 customize 하는 자산. 있으면 `.suggested` 로 옆에
#
# Output (--json):
#   {"status":"ok","result":{"target":"...","copied":N,"seeded_kept":N,
#     "suggested":[...],"preserved":[...],"opencode":false,
#     "git_hooks":"installed|skipped|no-git","reference_files":N,"version":"0.4.2"},
#    "next_step":"...","warnings":[],"errors":[]}
#
# Exit: 0 ok / 1 error
#
# `set -e` 없음 — 설치가 중간에 죽으면 반쪽짜리 트리가 남아요. 단계별로 개별 가드하고
# 실패는 warnings 에 모아서 보고해요. (scripts/bash/README.md 의 "의도적 편차" 와 같은 성격)
set -uo pipefail

SELF_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(CDPATH="" cd "$SELF_DIR/.." && pwd)"

JSON_MODE=false; DRY_RUN=false; SHOW_HELP=false; TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --json)    JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --target)  shift; TARGET="${1:-}" ;;
        --help|-h) SHOW_HELP=true ;;
        *) printf '[goax] unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

if [ "$SHOW_HELP" = true ]; then
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
fi

log()  { [ "$JSON_MODE" = true ] || printf '%s\n' "$*"; }
warn() { WARNINGS="${WARNINGS}$1"$'\n'; printf '[goax] %s\n' "$1" >&2; }
die()  {
    if [ "$JSON_MODE" = true ]; then
        printf '{"status":"error","result":null,"next_step":"","warnings":[],"errors":["%s"]}\n' \
            "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    else
        printf '[goax] ERROR: %s\n' "$1" >&2
    fi
    exit 1
}

WARNINGS=""; SUGGESTED=""; PRESERVED=""
COPIED=0; SEEDED_KEPT=0

TPL="$PLUGIN_ROOT/templates/default"
MANIFEST="$TPL/MANIFEST"
[ -f "$MANIFEST" ] || die "MANIFEST 부재 — $MANIFEST"

if [ -n "$TARGET" ]; then
    [ -d "$TARGET" ] || die "--target 디렉토리가 없어요: $TARGET"
    cd "$TARGET" || die "--target 진입 실패: $TARGET"
fi
PROJECT_DIR="$(pwd)"

GOAX_VER=$(cat "$PLUGIN_ROOT/VERSION" 2>/dev/null || echo unknown)

# ── 복사 프리미티브 (dry-run 을 한 곳에서만 처리) ────────────────────────
mk()  { [ "$DRY_RUN" = true ] || mkdir -p "$1" 2>/dev/null || warn "mkdir 실패: $1"; }
cpf() {   # cpf <src> <dst>
    if [ "$DRY_RUN" = true ]; then COPIED=$((COPIED+1)); return 0; fi
    if cp "$1" "$2" 2>/dev/null; then COPIED=$((COPIED+1)); else warn "복사 실패: $1 → $2"; fi
}
cpd() {   # cpd <src-dir-with-trailing-dot> <dst>
    if [ "$DRY_RUN" = true ]; then COPIED=$((COPIED+1)); return 0; fi
    if cp -R "$1" "$2" 2>/dev/null; then COPIED=$((COPIED+1)); else warn "재귀 복사 실패: $1 → $2"; fi
}
# 내용이 같으면 .suggested 를 만들 이유가 없어요. 재실행마다 동일본 9개가 쌓이면
# 사용자는 곧 전부 무시하게 되고, 그러면 정말 봐야 할 diff 도 같이 묻혀요.
same() { [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; }
# 조건부 자산: 있으면 .suggested(다를 때만), 없으면 설치
cond() {  # cond <tpl-relative-src> <dst>
    local src="$TPL/$1" dst="$2"
    [ -f "$src" ] || { warn "템플릿 부재: $1"; return 0; }
    mk "$(dirname "$dst")"
    if [ -e "$dst" ]; then
        same "$src" "$dst" && return 0
        cpf "$src" "$dst.suggested"
        SUGGESTED="${SUGGESTED}${dst}"$'\n'
    else
        cpf "$src" "$dst"
    fi
}

log "goax $GOAX_VER → $PROJECT_DIR"
[ "$DRY_RUN" = true ] && log "(dry-run — 아무것도 쓰지 않아요)"

# ── 1. 기본 디렉토리 ────────────────────────────────────────────────────
mk .claude

# ── 1-b. _templates 사용자 수정본 보호 ──────────────────────────────────
# `.ax/_templates/` 는 MANIFEST 재귀 복사 대상이라 그냥 두면 덮여요. 그런데 .origin 은
# "사용자가 도메인에 맞게 고친 템플릿"을 정상으로 인정하는 자산이에요
# (check-templates-drift 의 user_modified). 말없이 덮으면 그 작업이 사라져요.
USER_MODIFIED=""
if [ -f .ax/_templates/spec/.origin ]; then
    while IFS= read -r oline; do
        case "$oline" in ''|\#*) continue ;; esac
        osha="${oline%% *}"; ofile="${oline##* }"; ofile="${ofile#./}"
        [ -f ".ax/_templates/spec/$ofile" ] || continue
        csha=$(shasum -a 256 ".ax/_templates/spec/$ofile" 2>/dev/null | awk '{print $1}')
        [ "$csha" != "$osha" ] && USER_MODIFIED="$USER_MODIFIED$ofile"$'\n'
    done < .ax/_templates/spec/.origin
fi
UM_BACKUP=""
if [ -n "$USER_MODIFIED" ] && [ "$DRY_RUN" != true ]; then
    UM_BACKUP=$(mktemp -d)
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        mkdir -p "$UM_BACKUP/$(dirname "$f")"
        cp ".ax/_templates/spec/$f" "$UM_BACKUP/$f" 2>/dev/null || warn "백업 실패: $f"
    done <<< "$USER_MODIFIED"
fi

# ── 2. MANIFEST ─────────────────────────────────────────────────────────
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac

    SEED_ONLY=false
    if [ "${line#*" -> "}" != "$line" ]; then
        SRC="${line% -> *}"; DST="${line##* -> }"
        SEED_ONLY=true          # 런타임 상태 — 진행 중인 phase·spec_dir 를 idle 로 되돌리면 안 돼요
    else
        SRC="$line"; DST="$line"
    fi

    if [ "${SRC%/}" != "$SRC" ]; then
        # 디렉토리 재귀 (cp -R 은 merge — 사용자 spec/ADR/mistake 은 보존됨)
        mk "$DST"
        cpd "$TPL/${SRC}." "$DST"
    else
        mk "$(dirname "$DST")"
        if [ "$SEED_ONLY" = true ] && [ -e "$DST" ]; then
            SEEDED_KEPT=$((SEEDED_KEPT+1))
        else
            cpf "$TPL/$SRC" "$DST"
        fi
    fi
done < "$MANIFEST"

# ── 3. 실행 권한 ────────────────────────────────────────────────────────
if [ "$DRY_RUN" != true ]; then
    chmod +x .ax/scripts/bash/*.sh 2>/dev/null || true
    find .ax/hooks -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
    chmod +x .ax/hud/statusline.sh 2>/dev/null || true
fi

# ── 4. _templates 출고본 sha (drift 감지용 — doctor 가 비교) ────────────
# **plugin 원본**에서 계산해요. 방금 설치한 로컬에서 계산하면, 아래에서 사용자
# 수정본을 복원한 뒤 .origin 이 그 수정본을 "출고본"으로 기록해버려서
# user_modified 가 영원히 false 가 돼요 (드리프트 감지 실명).
if [ "$DRY_RUN" != true ] && [ -d "$TPL/.ax/_templates/spec" ]; then
    mkdir -p .ax/_templates/spec
    (
        cd "$TPL/.ax/_templates/spec" && \
        find . -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
            ! -name '.origin' | sort | xargs shasum -a 256 2>/dev/null
    ) > .ax/_templates/spec/.origin
    printf '# goax_version: %s\n' "$GOAX_VER" >> .ax/_templates/spec/.origin
fi

# ── 4-b. 사용자 수정본 복원 — plugin 최신본은 옆에 .suggested ───────────
if [ -n "$USER_MODIFIED" ] && [ -n "$UM_BACKUP" ] && [ "$DRY_RUN" != true ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        [ -f ".ax/_templates/spec/$f" ] && cp ".ax/_templates/spec/$f" ".ax/_templates/spec/$f.suggested"
        cp "$UM_BACKUP/$f" ".ax/_templates/spec/$f" 2>/dev/null \
            && PRESERVED="${PRESERVED}${f}"$'\n' \
            || warn "수정본 복원 실패: $f"
    done <<< "$USER_MODIFIED"
    rm -rf "$UM_BACKUP"
elif [ -n "$USER_MODIFIED" ]; then
    PRESERVED="$USER_MODIFIED"
fi

# ── 5. AGENTS.md — Constitution SSOT (multi-CLI, MANIFEST 외) ───────────
# AGENTS.md 가 SSOT. Claude Code 는 CLAUDE.md 의 @AGENTS.md import, OpenCode 는 직접 인식.
if [ -f AGENTS.md ]; then
    # 비교 기준은 [PROJECT_NAME] 을 치환한 쪽이에요. 원본 템플릿과 비교하면 신규 설치
    # 직후에도 늘 "다름"이 떠서 .suggested 가 영구히 붙어요.
    _agents_ref=$(mktemp)
    sed "s/\[PROJECT_NAME\]/$(basename "$PROJECT_DIR")/g" "$TPL/AGENTS.md.template" > "$_agents_ref" 2>/dev/null
    if ! same "$_agents_ref" AGENTS.md; then
        cpf "$TPL/AGENTS.md.template" .ax/AGENTS.md.suggested
        SUGGESTED="${SUGGESTED}AGENTS.md"$'\n'
    fi
    rm -f "$_agents_ref"
else
    cpf "$TPL/AGENTS.md.template" AGENTS.md
    # 신규 설치일 때만 [PROJECT_NAME] 치환 (tmp-mv — BSD/GNU sed 모두 호환)
    if [ "$DRY_RUN" != true ] && [ -f AGENTS.md ]; then
        PROJECT_NAME="$(basename "$PROJECT_DIR")"
        sed "s/\[PROJECT_NAME\]/$PROJECT_NAME/g" AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
    fi
fi

# ── 5.1 CLAUDE.md — Claude Code alias (MANIFEST 외) ─────────────────────
# 본문은 @AGENTS.md import 1줄 + 안내. 사용자가 customize 했으면 .suggested 로 보존.
if [ -f CLAUDE.md ]; then
    if grep -qE '^@AGENTS\.md\b' CLAUDE.md 2>/dev/null \
       && [ "$(wc -l < CLAUDE.md | tr -d ' ')" -lt 20 ]; then
        cpf "$TPL/CLAUDE.md.template" CLAUDE.md      # 이미 alias 형태 → 출고본으로 갱신
    else
        if ! same "$TPL/CLAUDE.md.template" CLAUDE.md; then
            cpf "$TPL/CLAUDE.md.template" .ax/CLAUDE.md.suggested
            SUGGESTED="${SUGGESTED}CLAUDE.md"$'\n'
        fi
    fi
else
    cpf "$TPL/CLAUDE.md.template" CLAUDE.md
fi

# ── 5.5 opencode.json — OpenCode 환경 감지 시만 ─────────────────────────
HAS_OPENCODE=false
if [ -n "${OPENCODE_CONFIG_DIR:-}" ] || [ -d ".opencode" ] \
   || [ -d "$HOME/.config/opencode" ] || command -v opencode >/dev/null 2>&1; then
    HAS_OPENCODE=true
fi
if [ "$HAS_OPENCODE" = true ]; then
    cond opencode.json.template opencode.json
    log "✓ OpenCode 환경 감지 — opencode.json 설치"
fi

# ── 5.6 git pre-commit wrapper — 모든 환경 ──────────────────────────────
# Claude Code 의 PreToolUse:Bash 는 "에이전트가 실행하는" git commit 만 잡아요.
# 사람이 터미널에서 직접 커밋하면 완전히 우회되므로 환경 불문 git hook 을 설치해요.
# 기존 pre-commit(goax marker 없음)이 있으면 스크립트가 exit 1 로 알리고 안 건드려요
# (--force 필요). husky 등 기존 훅 팀은 그게 정상이에요 (사용자 자산 보존).
GIT_HOOKS="no-git"
if [ -d .git ] || [ -f .git ]; then
    if [ "$DRY_RUN" = true ]; then
        GIT_HOOKS="dry-run"
    elif bash .ax/scripts/bash/install-git-hooks.sh >/dev/null 2>&1; then
        GIT_HOOKS="installed"
    else
        GIT_HOOKS="skipped"
        warn "git pre-commit — 기존 훅이 있어 건드리지 않았어요 (install-git-hooks.sh --force 로 덮어쓰기)"
    fi
fi

# ── 6. .claude/settings.json — Claude Code 한정 ─────────────────────────
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] || [ -n "${CLAUDE_SKILL_DIR:-}" ] || [ -d .claude ]; then
    mk .claude
    if [ -f .claude/settings.json ]; then
        if ! same "$TPL/.claude/settings.json.template" .claude/settings.json; then
            cpf "$TPL/.claude/settings.json.template" .ax/settings.json.suggested
            SUGGESTED="${SUGGESTED}.claude/settings.json"$'\n'
        fi
    else
        cpf "$TPL/.claude/settings.json.template" .claude/settings.json
    fi
fi

# ── 6.5 사용자 customize 자산 (MANIFEST 외 조건부) ──────────────────────
mk .ax
cond .ax/config.yml           .ax/config.yml            # domain_risk·commands·sensors
cond .ax/search-aliases.yml   .ax/search-aliases.yml    # triage-search 도메인 동의어
mk .ax/mistakes
cond .ax/mistakes/README.md   .ax/mistakes/README.md    # 팀 캡처·심사 정책
mk .ax/spirit
for SPF in values.md tone.md README.md; do              # 팀 가치·톤
    cond ".ax/spirit/$SPF" ".ax/spirit/$SPF"
done

# ── 6.6 docs/reference — plugin 루트 SSOT (templates/default 밖) ────────
# CLAUDE.md / spirit rules / modules README 가 `.ax/docs/reference/*` 로 참조해요.
# read-only 자료라 갱신 시 항상 덮어써도 안전 (drift 위험 없음).
REF_N=0
if [ -d "$PLUGIN_ROOT/docs/reference" ]; then
    mk .ax/docs/reference
    cpd "$PLUGIN_ROOT/docs/reference/." .ax/docs/reference/
    REF_N=$(find "$PLUGIN_ROOT/docs/reference" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    log "✓ .ax/docs/reference: ${REF_N}개"
else
    warn "docs/reference 부재 — CLAUDE.md 의 참조 경로가 깨져요"
fi

# ── 6.7 .gitignore — append-if-missing ──────────────────────────────────
# runtime 파일(.ax/state.json 등)·임시본(.ax/*.suggested)이 PR diff 노이즈가 되는 걸 방지.
GI_ADDED=0
GITIGNORE_TPL="$TPL/.gitignore.template"
if [ -f "$GITIGNORE_TPL" ]; then
    if [ -f .gitignore ]; then
        while IFS= read -r gline; do
            case "$gline" in ''|\#*) continue ;; esac
            if ! grep -qxF "$gline" .gitignore 2>/dev/null; then
                [ "$DRY_RUN" = true ] || printf '%s\n' "$gline" >> .gitignore
                GI_ADDED=$((GI_ADDED+1))
            fi
        done < "$GITIGNORE_TPL"
        [ "$GI_ADDED" -gt 0 ] && log "✓ .gitignore: ${GI_ADDED}줄 추가"
    else
        cpf "$GITIGNORE_TPL" .gitignore
        log "✓ .gitignore: 신규 생성"
    fi
fi

# ── 7. 메타 ─────────────────────────────────────────────────────────────
if [ "$DRY_RUN" != true ]; then
    mk .ax
    {
        printf 'goax: %s\n' "$GOAX_VER"
        printf 'preset: default\n'
        printf 'installed_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > .ax/version
fi

# ── 출력 ────────────────────────────────────────────────────────────────
NEXT="설치 완료 — brownfield 면 onboarding skill 로, greenfield 면 첫 spec 안내로 이어가세요"
[ -n "$SUGGESTED" ] && NEXT="$NEXT. .suggested 파일이 있어요 — diff 후 머지 결정 필요"

if [ "$JSON_MODE" = true ]; then
    # 빈 입력에서 grep 이 exit 1 → pipefail 로 `||` 까지 발화해 `[][]` 가 나와요.
    # 비었는지 먼저 확인하고 끝내요.
    jarr() {
        local v; v=$(printf '%s' "$1" | grep -v '^$' || true)
        [ -z "$v" ] && { printf '[]'; return 0; }
        printf '%s\n' "$v" | jq -Rn '[inputs]' 2>/dev/null || printf '[]'
    }
    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg t "$PROJECT_DIR" --argjson c "$COPIED" --argjson sk "$SEEDED_KEPT" \
            --argjson sg "$(jarr "$SUGGESTED")" --argjson pv "$(jarr "$PRESERVED")" \
            --argjson oc "$HAS_OPENCODE" --arg gh "$GIT_HOOKS" --argjson rf "${REF_N:-0}" \
            --arg v "$GOAX_VER" --argjson gi "$GI_ADDED" --argjson dr "$DRY_RUN" \
            --argjson w "$(jarr "$WARNINGS")" --arg ns "$NEXT" \
            '{status:(if ($w|length)>0 then "warning" else "ok" end),
              result:{target:$t,copied:$c,seeded_kept:$sk,suggested:$sg,preserved:$pv,
                      opencode:$oc,git_hooks:$gh,reference_files:$rf,gitignore_added:$gi,
                      dry_run:$dr,version:$v},
              next_step:$ns, warnings:$w, errors:[]}'
    else
        printf '{"status":"ok","result":{"target":"%s","copied":%s,"seeded_kept":%s,"version":"%s"},"next_step":"%s","warnings":[],"errors":[]}\n' \
            "$PROJECT_DIR" "$COPIED" "$SEEDED_KEPT" "$GOAX_VER" "$NEXT"
    fi
else
    log "✓ 복사 ${COPIED}건 · seed 유지 ${SEEDED_KEPT}건 · git hook ${GIT_HOOKS}"
    [ -n "$SUGGESTED" ] && log "  .suggested 대기: $(printf '%s' "$SUGGESTED" | tr '\n' ' ')"
    [ -n "$PRESERVED" ] && log "  _templates 수정본 보존: $(printf '%s' "$PRESERVED" | tr '\n' ' ')"
fi
exit 0
