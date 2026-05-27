---
name: up
description: "goax 프로젝트 install or idempotent update — '/up', 'goax up', '/setup', 'goax 도입', 'goax 설치', 'goax 셋업', '하네스 적용' 등 자연어 트리거. 프로젝트를 분석하고 사용자 동의 후 .ax/ + AGENTS.md (Constitution SSOT) + CLAUDE.md (Claude Code alias) 를 설치. multi-CLI 지원 — Claude Code/OpenCode 환경 자동 감지, OpenCode 환경에선 opencode.json 추가 설치. brownfield 면 onboarding skill 로 이어감."
---

# goax up — install or idempotent update (4계층 하네스 도입)

> 이름이 `up` 인 이유: 동작이 install + update 둘 다라서. 첫 호출 = install, 두 번째부터 = idempotent update (plugin 갱신 후 재호출). doctor → up 흐름이 normal path 라 destructive 면 안 되어요. 사용자 customize 자산 (`.ax/spirit/{values,tone,README}.md`, `.ax/config.yml`, `.ax/mistakes/README.md`, `CLAUDE.md`, `.claude/settings.json`) 은 `.suggested` 패턴으로 보존.

## 언제 발동하는가

다음 중 하나면 이 skill을 따라요:
- 사용자가 "/up", "goax up", "/setup", "goax 도입", "goax 설치", "goax 셋업" 등을 입력
- 사용자가 "하네스 적용해줘" 같은 표현을 사용
- 프로젝트에 `.ax/`가 없는데 사용자가 goax 관련 작업을 요청
- doctor 가 plugin 갱신 감지 후 재호출 안내 (`/up` 으로 idempotent backfill)

이미 `.ax/`가 있으면 — 기본 동작은 idempotent update. doctor 진단부터 원하면 `/doctor` 호출.

## 시작 전 필수 — Spirit 자동 주입

`.ax/spirit/values.md`, `tone.md`가 사용자 프로젝트에 이미 있으면 그것을 따라요.
없으면(아직 설치 전이면), plugin 내 `templates/default/.ax/spirit/`를 참조해요.

## 1. 프로젝트 분석 (LLM이 직접)

bash 휴리스틱이 아니라 **Claude가 코드를 직접 읽어** 다음을 파악해요:

### 1.1 형태
- 모노레포인가 싱글인가
 - `pnpm-workspace.yaml`, `package.json#workspaces` → pnpm/npm 모노레포
 - `settings.gradle.kts` 의 `include(...)` → Gradle multi-module
 - `apps/`, `packages/`, `projects/` 디렉토리 → 디렉토리 기반
- 모듈 목록 (실제 build 단위)

### 1.2 기존 자산
- `AGENTS.md` 존재·줄 수 (0.2.0+ 신규 SSOT)
- `CLAUDE.md` 존재·줄 수·룰 수 추정 (alias 형태인지 customize 본문인지 판별)
- `opencode.json` 또는 `.opencode/` 디렉토리 (OpenCode 환경 신호)
- 모듈별 `<module>/CLAUDE.md` 또는 `<module>/AGENTS.md`
- 외부 spec 디렉토리(sibling `*-spec`, 자기 안 `spec/`, `governance/`)
- 활성 hooks (`.husky/`, `.pre-commit-config.yaml`, `lint-staged`)
- AI 리뷰 도구 (`.coderabbit.yaml`, `.cursorrules`)
- Stack 추정 (`build.gradle.kts`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`)

### 1.4 사용 중인 CLI 자동 감지

다음 시그널로 판별 (양립 가능 — 두 CLI 모두 쓰는 사용자도 정상):
- **Claude Code**: `${CLAUDE_PROJECT_DIR}` 또는 `${CLAUDE_SKILL_DIR}` set (up 스킬 자체가 Claude Code 안에서 돌면 항상 해당)
- **OpenCode**: `${OPENCODE_CONFIG_DIR}` set OR `.opencode/` 디렉토리 OR `$HOME/.config/opencode/` OR `command -v opencode` 성공
- **unknown**: 위 둘 다 음성 → greenfield 추정, 양쪽 자산 모두 install + 사용자 알림

### 1.3 도메인 후보
모듈명·패키지 트리(`com.<org>.<project>.<domain>` 형태 등)·디렉토리에서 의미 있는 도메인만 식별.
**짧은 prefix(`ad`, `ba`)나 일반 단어(`common`, `util`)는 제외**.

## 2. Plan 출력 — 사용자에게 보여주기

분석 결과를 다음 형식으로:

```
🔍 Discover
 레포 형태 : 모노레포 (Gradle multi-module)
 모듈 :  N개 — <module-1>, <module-2>, ...
 CLAUDE.md : X줄, 룰 ~Y개 추정 (또는 없음)
 외부 spec : <repo>-spec (또는 없음)
 활성 hooks : pre-commit-framework (또는 없음)
 Stack :  Kotlin/Gradle
 도메인 후보 : payment, order, catalog, ...

📐 Plan — 4계층 + Cross-cut으로 깔릴 자산
 Target CLI :  <claude | opencode | both | unknown> (자동 감지)
 Layer 0 — Triage:  plugin이 이미 제공 (skills/triage/)
 Layer 1 — Constitution: AGENTS.md (multi-CLI SSOT) + CLAUDE.md (@AGENTS.md alias)
       기존 파일 customize 됐으면 .ax/<name>.suggested 보존
 Layer 2 — Module Rules: <module>/CLAUDE.md 또는 <module>/AGENTS.md (사용자가 작성)
 Layer 3 — Spec/ADR: .ax/docs/{adr, spec}/ (템플릿 포함)
 Cross-cut Spirit:  .ax/spirit/{values, tone, rules}
 Cross-cut Mistake Loop:.ax/mistakes/
 Sensors (Hooks):  .ax/hooks/*.sh
       Claude Code → .claude/settings.json 자동 등록
       OpenCode → install-git-hooks.sh 안내 (PreToolUse 미지원, commit 시점 보전)
 OpenCode config :  opencode.json (OpenCode 환경 감지 시만)

추가 (brownfield):
 onboarding skill 임시 활성화 → 도메인·룰 자동 분류
```

## 3. 단일 동의 프롬프트

```
이대로 설치할까요? (Y/n)
```

`Y`(또는 `네`, `ㅇ`) → 진행. 그 외 → 취소(파일 변경 0).

## 4. 설치 — Bash tool로 cp (MANIFEST 기반)

plugin의 `templates/default/MANIFEST`를 읽어 사용자 프로젝트로 복사. 열거 hardcode 대신 manifest를 SSOT로 사용 — template에 디렉토리 추가 시 MANIFEST만 갱신하면 up 호출 시 자동으로 따라감.

```bash
# 0. plugin root 검출 — Claude Code 표준 ${CLAUDE_SKILL_DIR} 우선,
#    ${CLAUDE_PLUGIN_ROOT}는 비표준이라 호환용 fallback에만 둠.
if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
    PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    echo "[goax] ERROR: \${CLAUDE_SKILL_DIR} \${CLAUDE_PLUGIN_ROOT} 둘 다 미설정." >&2
    echo "       이 SKILL은 plugin 컨텍스트(/plugin install goax 후)에서만 동작해요." >&2
    exit 1
fi

TPL="$PLUGIN_ROOT/templates/default"
MANIFEST="$TPL/MANIFEST"
[ ! -f "$MANIFEST" ] && { echo "[goax] ERROR: MANIFEST 부재 — $MANIFEST" >&2; exit 1; }

# 1. 기본 디렉토리
mkdir -p .claude

# 2. MANIFEST 읽고 항목별 복사
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ''|\#*) continue ;;  # 주석·빈 줄 skip
    esac

    # "source -> dest" 또는 "source"
    if [[ "$line" == *" -> "* ]]; then
        SRC="${line% -> *}"
        DST="${line##* -> }"
    else
        SRC="$line"
        DST="$line"
    fi

    case "$SRC" in
        */)  # 디렉토리 재귀
            mkdir -p "$DST"
            cp -R "$TPL/${SRC}." "$DST"
            ;;
        *)   # 단일 파일
            mkdir -p "$(dirname "$DST")"
            cp "$TPL/$SRC" "$DST"
            ;;
    esac
done < "$MANIFEST"

# 3. 실행 권한 (bash 스크립트)
chmod +x .ax/scripts/bash/*.sh 2>/dev/null || true
find .ax/hooks -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
chmod +x .ax/hud/statusline.sh 2>/dev/null || true

# 4. _templates 출고본 sha 기록 (drift 감지용 — doctor가 비교)
(
    cd .ax/_templates/spec && \
    find . -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
        ! -name '.origin' | sort | xargs shasum -a 256 2>/dev/null
) > .ax/_templates/spec/.origin
GOAX_VER=$(cat "$PLUGIN_ROOT/VERSION" 2>/dev/null || echo "unknown")
echo "# goax_version: $GOAX_VER" >> .ax/_templates/spec/.origin

# 5. AGENTS.md — Constitution SSOT (multi-CLI, manifest 외 조건부)
# AGENTS.md 가 0.2.0+ 의 SSOT. Claude Code 는 CLAUDE.md 의 @AGENTS.md import,
# OpenCode 는 AGENTS.md 직접 인식.
if [ -f AGENTS.md ]; then
    cp "$TPL/AGENTS.md.template" .ax/AGENTS.md.suggested
else
    cp "$TPL/AGENTS.md.template" AGENTS.md
fi

# 5.1 CLAUDE.md — Claude Code alias (manifest 외 조건부)
# 본문이 @AGENTS.md import 1줄 + Claude Code 안내. 0.1.x 사용자가 본문을 customize
# 했으면 .suggested 로 보존 (§7 마이그레이션 안내).
if [ -f CLAUDE.md ]; then
    # 이미 alias 형태인지 (1줄 @AGENTS.md 포함 + 20줄 미만) 판별 → 출고본으로 drift 갱신
    if grep -qE '^@AGENTS\.md\b' CLAUDE.md && [ "$(wc -l < CLAUDE.md | tr -d ' ')" -lt 20 ]; then
        cp "$TPL/CLAUDE.md.template" CLAUDE.md
    else
        # 0.1.x customize 본문 → 보존 + 마이그레이션 안내 (§7)
        cp "$TPL/CLAUDE.md.template" .ax/CLAUDE.md.suggested
    fi
else
    cp "$TPL/CLAUDE.md.template" CLAUDE.md
fi

# 5.5 opencode.json — OpenCode 환경 감지 시만 (manifest 외 조건부)
HAS_OPENCODE=false
if [ -n "${OPENCODE_CONFIG_DIR:-}" ] \
   || [ -d ".opencode" ] || [ -d "$HOME/.config/opencode" ] \
   || command -v opencode >/dev/null 2>&1; then
    HAS_OPENCODE=true
fi
if [ "$HAS_OPENCODE" = true ]; then
    if [ -f opencode.json ]; then
        cp "$TPL/opencode.json.template" .ax/opencode.json.suggested
    else
        cp "$TPL/opencode.json.template" opencode.json
    fi
    echo "✓ OpenCode 환경 감지 — opencode.json 설치"
    echo "  Hook 시스템 보전: bash .ax/scripts/bash/install-git-hooks.sh"
fi

# 6. .claude/settings.json — Claude Code mode 한정 (manifest 외 조건부)
# Claude Code 가 set 한 env (CLAUDE_PROJECT_DIR / CLAUDE_SKILL_DIR) 있으면 무조건 등록.
# 없으면 (순수 OpenCode 사용자) 건너뜀 — .claude/settings.json 은 OpenCode 에서 무의미.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] || [ -n "${CLAUDE_SKILL_DIR:-}" ] || [ -d ".claude" ]; then
    mkdir -p .claude
    if [ -f .claude/settings.json ]; then
        cp "$TPL/.claude/settings.json.template" .ax/settings.json.suggested
    else
        cp "$TPL/.claude/settings.json.template" .claude/settings.json
    fi
fi

# 6.5 .ax/config.yml — 조건부 (manifest 외, 사용자 customizations 보존)
# conditional 처리: 기존 .ax/config.yml의 domain_risk·commands·sensors 등
# 사용자 변경을 plugin re-install이 clobber하지 않도록.
if [ -f .ax/config.yml ]; then
    cp "$TPL/.ax/config.yml" .ax/config.yml.suggested
else
    mkdir -p .ax
    cp "$TPL/.ax/config.yml" .ax/config.yml
fi

# 6.6 plugin 메타 reference — cp from PLUGIN_ROOT/docs/reference
# rules-tokens, critical-rules, glossary, triage-matrix, rule-enforcement 등.
# CLAUDE.md / spirit/rules / modules/README.md 가 `.ax/docs/reference/*` 경로로 참조 →
# 사용자 프로젝트에 깔려야 그 참조가 valid. 사용자 customize 안 하는 read-only 자료라
# plugin 갱신 시 항상 덮어쓰기 OK (drift 위험 없음).
# MANIFEST 에 안 박은 이유: docs/reference 는 plugin repo 루트의 SSOT (templates/default 외).
mkdir -p .ax/docs
cp -R "$PLUGIN_ROOT/docs/reference" .ax/docs/reference
echo "✓ .ax/docs/reference: $(ls .ax/docs/reference | wc -l | tr -d ' ')개 reference 파일"

# 6.7 .gitignore — append-if-missing (manifest 외)
# runtime 파일(.ax/state.json, .ax/current-task.json)·임시본(.ax/*.suggested) 등이
# PR diff에 들어가 노이즈가 되는 걸 방지. 기존 .gitignore가 있으면 누락된 줄만 추가.
GITIGNORE_TPL="$TPL/.gitignore.template"
if [ -f "$GITIGNORE_TPL" ]; then
    if [ -f .gitignore ]; then
        # 기존 .gitignore — 누락 entry만 append (idempotent)
        added=0
        while IFS= read -r line; do
            case "$line" in ''|\#*) continue ;; esac
            grep -qxF "$line" .gitignore || { printf '%s\n' "$line" >> .gitignore; added=$((added+1)); }
        done < "$GITIGNORE_TPL"
        [ "$added" -gt 0 ] && echo "✓ .gitignore: $added 줄 추가 (goax runtime 보호)"
    else
        cp "$GITIGNORE_TPL" .gitignore
        echo "✓ .gitignore: 신규 생성"
    fi
fi

# 6.8 .ax/mistakes/README.md — 조건부 (manifest 외, 사용자 팀 정책 보존)
# conditional: 사용자가 mistake 캡처/심사 정책을 README에 추가했을 때
# plugin re-install이 clobber하지 않도록.
mkdir -p .ax/mistakes
if [ -f .ax/mistakes/README.md ]; then
    cp "$TPL/.ax/mistakes/README.md" .ax/mistakes/README.md.suggested
else
    cp "$TPL/.ax/mistakes/README.md" .ax/mistakes/README.md
fi

# 6.10 .ax/spirit/{values,tone,README}.md — 조건부 (manifest 외)
# spirit 은 cross-cut Spirit (공유 agent personality) — 팀 가치·톤은 회사·팀별로
# customize 되는 게 정상. plugin 재호출 이나 doctor → up 흐름에서 사용자
# 자산을 도자기처럼 깨면 안 됨. 기존 파일이 있으면 `.suggested` 로 옆에 두고 사용자가
# diff 후 머지 결정. spirit/rules/ 는 plugin 이 출고하는 파일 자체가 없음 (사용자 큐레이션).
mkdir -p .ax/spirit
for SPF in values.md tone.md README.md; do
    if [ -f ".ax/spirit/$SPF" ]; then
        cp "$TPL/.ax/spirit/$SPF" ".ax/spirit/$SPF.suggested"
    else
        cp "$TPL/.ax/spirit/$SPF" ".ax/spirit/$SPF"
    fi
done

# 6.9 path-scoped rule injection
# spirit/rules/<name>.md 의 frontmatter `paths:` 와 편집 대상 파일 path를 매칭해
# `.ax/hooks/pre-edit/spirit-rules-inject.sh` 가 hook 시점에 additionalContext로 안내.
# settings.json.template 가 hook을 PreToolUse(Edit|Write|MultiEdit)에 자동 등록.
echo "✓ path-scoped rule loading — .ax/hooks/pre-edit/spirit-rules-inject.sh"

# 7. 메타 정보
cat > .ax/version <<META
goax: $GOAX_VER
preset: default
installed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
META
```

각 단계마다 `✓` 출력으로 진행 상황 알려요.

> **변수 컨벤션** — `$CLAUDE_PROJECT_DIR`(사용자 프로젝트 루트)·`${CLAUDE_SKILL_DIR}`(skill 자체 위치, plugin root는 `${CLAUDE_SKILL_DIR}/../..`)는 Claude Code 공식 변수예요. `$CLAUDE_PLUGIN_ROOT`는 비표준 — 과거 호환용 fallback에만 둘 것. `$PLUGIN_DIR` 같은 임의 변수는 정의되지 않아요.

> **MANIFEST 갱신 규칙** — `templates/default/`에 새 디렉토리·파일을 추가할 때 `templates/default/MANIFEST`도 같이 갱신. doctor가 MANIFEST vs 사용자 프로젝트 실제 설치 상태를 diff해서 누락 감지. 조건부 복사(CLAUDE.md, .claude/settings.json)는 manifest 외 — installer §5/§6에서 별도 처리.

## 5. brownfield면 — onboarding으로 위임

기존 자산이 있으면(CLAUDE.md, hooks, modules > 1, external spec 중 하나라도) `.ax/.onboarding-pending` 마커를 작성하고 onboarding skill로 자연스럽게 이어가요:

```
✓ 골격 설치 완료.
이제 onboarding으로 이어갈게요. 도메인과 룰을 함께 정리해요...
```

→ onboarding skill 발동.

## 6. greenfield면 — 안내만

```
🥳 goax 도입 완료.

📂 .ax/ runtime — .gitignore 자동 처리됨
 .ax/state.json, .ax/current-task.json — 매 호출마다 변경되는 상태 (per-machine)
 .ax/*.suggested — install/onboarding 머지 임시본
 → PR diff 노이즈 방지 위해 .gitignore에 자동 추가 (또는 기존 .gitignore에 누락 줄 append)

📋 Mistake Loop — 주기적 audit 권장
 hook 위반·실수가 .ax/mistakes/에 자동 누적 (race-free + redact 보호)
 audit_cadence_days=7 (.ax/config.yml) — 주 1회 회고 권장
 실행: "goax audit" 또는 "실수 회고" — 카테고리 N회 누적 시 CRITICAL/MANDATORY 룰 승격 후보 제시
 자동화: Claude Routine으로 weekly cron 등록하면 PR 형태로 audit 결과 받기 가능

다음에 시도해보세요:
 "결제 환불 정책 변경 작업 계획 세워줘"
 → triage skill이 Size×Risk 분류 → spirit·룰·페르소나 자동 주입
```

## 7. AGENTS.md / CLAUDE.md 마이그레이션 가이드 (0.1.x → 0.2.0)

### Case A — 기존 CLAUDE.md 본문이 customize 됐을 때

```
📝 Constitution 마이그레이션 가이드 (CLAUDE.md → AGENTS.md SSOT)

기존 CLAUDE.md 는 customize 본문이라 손대지 않았어요. 제안본:
 .ax/CLAUDE.md.suggested  — 1줄 @AGENTS.md alias + Claude Code 안내
 AGENTS.md (신규)          — Constitution SSOT (multi-CLI)

권장 마이그레이션 (수동, 또는 onboarding 이 도와줌):
 1. 기존 CLAUDE.md 본문 → AGENTS.md 로 mv (customize 영역 보존)
 2. CLAUDE.md 본문 → .ax/CLAUDE.md.suggested 내용으로 교체 (@AGENTS.md alias)
 3. AGENTS.md 안에서 시그널 도입 — 🔴 CRITICAL / 🟡 MANDATORY / 🔵 CONVENTION
 4. 상위 3~5개만 SSOT 에 — Layer 1 은 "비협상 룰"만. 나머지는 .ax/spirit/rules/
 5. 4계층 인덱스 추가 — 제안본 끝부분 표 그대로

비교: diff CLAUDE.md .ax/CLAUDE.md.suggested
완료 후: rm .ax/CLAUDE.md.suggested

OpenCode 사용자: AGENTS.md 자동 인식. CLAUDE.md alias 도 fallback 으로 동작.
Claude Code 사용자: CLAUDE.md → @AGENTS.md import 체인. 차이 없이 동작.
```

### Case B — 기존 AGENTS.md 가 customize 됐을 때

```
📝 AGENTS.md 가 이미 customize 됐어요. 제안본 (출고본) 만 보존:
 .ax/AGENTS.md.suggested

diff 후 누락된 META / 4계층 인덱스 / 시그널 의미 섹션만 머지 권장.
```

### Case C — 기존 CLAUDE.md 가 이미 alias 형태일 때

자동: 출고본으로 교체 (drift 방지). 별도 안내 없음.

## 절대 금지

- 사용자 동의 없이 설치하지 않아요. 동의 받기 전엔 변경 0.
- 도메인 위험도(L0~L3)를 **추측만으로** 박지 않아요. onboarding이 사용자와 같이 정해요.
- 한 번에 모든 결정을 묶지 않아요. 동의 → 설치 → onboarding으로 이어지는 흐름이에요.

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- 전체 (onboarding으로 위임 시 마지막에)

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
# canonical 갱신 — derived value + updated_at
bash .ax/scripts/bash/update-state.sh

# 메타데이터만
jq '.last_skill = "install" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
