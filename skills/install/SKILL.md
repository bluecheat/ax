---
name: install
description: "goax 프로젝트 도입 — '/setup', 'goax 도입', 'goax 설치', 'goax 셋업', '하네스 적용', 'goax up' 등 자연어 트리거. 프로젝트를 분석하고 사용자 동의 후 .ax/와 CLAUDE.md를 설치. brownfield면 onboarding skill로 이어감. plugin 설치 후 첫 세팅을 담당."
---

# goax installer — 4계층 하네스 도입

## 언제 발동하는가

다음 중 하나면 이 skill을 따라요:
- 사용자가 "/setup", "goax 도입", "goax 설치", "goax 셋업" 등을 입력
- 사용자가 "하네스 적용해줘" 같은 표현을 사용
- 프로젝트에 `.ax/`가 없는데 사용자가 goax 관련 작업을 요청

이미 `.ax/`가 있으면 — `goax doctor` 의도로 해석하고 doctor skill로 위임.

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
- `CLAUDE.md` 존재·줄 수·룰 수 추정
- 모듈별 `<module>/CLAUDE.md`
- 외부 spec 디렉토리(sibling `*-spec`, 자기 안 `spec/`, `governance/`)
- 활성 hooks (`.husky/`, `.pre-commit-config.yaml`, `lint-staged`)
- AI 리뷰 도구 (`.coderabbit.yaml`, `.cursorrules`)
- Stack 추정 (`build.gradle.kts`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`)

### 1.3 도메인 후보
모듈명·패키지 트리(`com.x.commerce.payment` 등)·디렉토리에서 의미 있는 도메인만 식별.
**짧은 prefix(`ad`, `ba`)나 일반 단어(`common`, `util`)는 제외**.

## 2. Plan 출력 — 사용자에게 보여주기

분석 결과를 다음 형식으로:

```
🔍 Discover
 레포 형태 : 모노레포 (Gradle multi-module)
 모듈 :  N개 — commerce-core, commerce-rest, ...
 CLAUDE.md : X줄, 룰 ~Y개 추정 (또는 없음)
 외부 spec : commerce-spec (또는 없음)
 활성 hooks : pre-commit-framework (또는 없음)
 Stack :  Kotlin/Gradle
 도메인 후보 : payment, order, catalog, ...

📐 Plan — 4계층 + Cross-cut으로 깔릴 자산
 Layer 0 — Triage:  plugin이 이미 제공 (skills/triage/)
 Layer 1 — Constitution: CLAUDE.md (기존 보존, .ax/CLAUDE.md.suggested 생성)
       또는 신규 CLAUDE.md
 Layer 2 — Module Rules: <module>/CLAUDE.md (사용자가 작성)
 Layer 3 — Spec/ADR: .ax/docs/{adr, spec}/ (템플릿 포함)
 Cross-cut Spirit:  .ax/spirit/{values, tone, rules}
 Cross-cut Mistake Loop:.ax/mistakes/
 Sensors (Hooks):  .ax/hooks/*.sh + .claude/settings.json

추가 (brownfield):
 onboarding skill 임시 활성화 → 도메인·룰 자동 분류
```

## 3. 단일 동의 프롬프트

```
이대로 설치할까요? (Y/n)
```

`Y`(또는 `네`, `ㅇ`) → 진행. 그 외 → 취소(파일 변경 0).

## 4. 설치 — Bash tool로 cp (MANIFEST 기반)

plugin의 `templates/default/MANIFEST`를 읽어 사용자 프로젝트로 복사. 열거 hardcode 대신 manifest를 SSOT로 사용 — template에 디렉토리 추가 시 MANIFEST만 갱신하면 installer가 자동으로 따라감.

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
    cd .ax/docs/_templates/spec && \
    find . -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) \
        ! -name '.origin' | sort | xargs shasum -a 256 2>/dev/null
) > .ax/docs/_templates/spec/.origin
GOAX_VER=$(cat "$PLUGIN_ROOT/VERSION" 2>/dev/null || echo "unknown")
echo "# goax_version: $GOAX_VER" >> .ax/docs/_templates/spec/.origin

# 5. CLAUDE.md — 조건부 (manifest 외)
if [ -f CLAUDE.md ]; then
    cp "$TPL/CLAUDE.md.template" .ax/CLAUDE.md.suggested
else
    cp "$TPL/CLAUDE.md.template" CLAUDE.md
fi

# 6. .claude/settings.json — 조건부 (manifest 외)
if [ -f .claude/settings.json ]; then
    cp "$TPL/.claude/settings.json.template" .ax/settings.json.suggested
else
    cp "$TPL/.claude/settings.json.template" .claude/settings.json
fi

# 6.5 .ax/config.yml — 조건부 (manifest 외, 사용자 customizations 보존)
# 0.1.8부터 conditional 처리: 기존 .ax/config.yml의 domain_risk·commands·sensors 등
# 사용자 변경을 plugin re-install이 clobber하지 않도록.
if [ -f .ax/config.yml ]; then
    cp "$TPL/.ax/config.yml" .ax/config.yml.suggested
else
    mkdir -p .ax
    cp "$TPL/.ax/config.yml" .ax/config.yml
fi

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
# 0.1.8부터 conditional: 사용자가 mistake 캡처/심사 정책을 README에 추가했을 때
# plugin re-install이 clobber하지 않도록.
mkdir -p .ax/mistakes
if [ -f .ax/mistakes/README.md ]; then
    cp "$TPL/.ax/mistakes/README.md" .ax/mistakes/README.md.suggested
else
    cp "$TPL/.ax/mistakes/README.md" .ax/mistakes/README.md
fi

# 6.9 .claude/rules/ shim 생성 (path-scoped rule loading)
# 0.1.8부터 도입: spirit/rules/<name>.md의 frontmatter `paths:` 가 있는 룰만
# .claude/rules/<name>.md 로 shim 생성 → Claude Code 네이티브 path-scoped loading.
# paths 없으면 universal — CLAUDE.md @import 그대로 동작.
mkdir -p .claude/rules
bash .ax/scripts/bash/generate-rule-shims.sh 2>/dev/null || \
    echo "ⓘ generate-rule-shims.sh — paths 선언된 spirit/rules가 아직 없음 (universal로 시작)"

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

다음에 시도해보세요:
 "결제 환불 정책 변경 작업 계획 세워줘"
 → triage skill이 Size×Risk 분류 → spirit·룰·페르소나 자동 주입
```

## 7. CLAUDE.md 병합 가이드 (기존 CLAUDE.md 있을 때)

```
📝 CLAUDE.md 병합 가이드

기존 CLAUDE.md는 손대지 않았어요. 제안본:
 .ax/CLAUDE.md.suggested

병합 전략:
 1. 시그널 도입 — 기존 룰에 🔴 CRITICAL / 🟡 MANDATORY / 🔵 CONVENTION 라벨
 2. 상위 3~5개만 root에 — Layer 1은 "비협상 룰"만. 나머지는 .ax/spirit/rules/
 3. 4계층 인덱스 추가 — 제안본 끝부분 표를 root에 prepend/append
 4. onboarding이 룰 카테고리 분류를 도와줘요

비교: diff CLAUDE.md .ax/CLAUDE.md.suggested
완료 후: rm .ax/CLAUDE.md.suggested
```

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
