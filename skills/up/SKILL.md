---
name: up
description: "goax 프로젝트 install or idempotent update — '/up', 'goax up', 'goax 도입', 'goax 설치', 'goax 셋업', '하네스 적용' 등 자연어 트리거. 프로젝트를 분석하고 사용자 동의 후 .ax/ + AGENTS.md (Constitution SSOT) + CLAUDE.md (Claude Code alias) 를 설치. multi-CLI 지원 — Claude Code/OpenCode 환경 자동 감지, OpenCode 환경에선 opencode.json 추가 설치. brownfield 면 onboarding skill 로 이어감."
---

# goax up — install or idempotent update (4계층 하네스 도입)

> 이름이 `up` 인 이유: 동작이 install + update 둘 다라서. 첫 호출 = install, 두 번째부터 = idempotent update (plugin 갱신 후 재호출). doctor → up 흐름이 normal path 라 destructive 면 안 되어요. 사용자 customize 자산 (`.ax/spirit/{values,tone,README}.md`, `.ax/config.yml`, `.ax/mistakes/README.md`, `CLAUDE.md`, `.claude/settings.json`) 은 `.suggested` 패턴으로 보존.

## 언제 발동하는가

다음 중 하나면 이 skill을 따라요:
- 사용자가 "/up", "goax up", "/setup", "goax 도입", "goax 설치", "goax 셋업" 등을 입력
- 사용자가 "하네스 적용해줘" 같은 표현을 사용
- 프로젝트에 `.ax/`가 없는데 사용자가 goax 관련 작업을 요청
- doctor 가 plugin 갱신 감지 후 재호출 안내 (`/up` 으로 idempotent backfill)

**install 인지 update 인지는 `.ax/` 존재로 먼저 갈라요** (분석보다 먼저 봐요):

```bash
[ -d .ax ] && MODE=update || MODE=install
```

`MODE=update` 면 — 기본 동작은 idempotent update, brownfield 재판정 없이 곧장 §4 설치로 (§5 참고).
doctor 진단부터 원하면 `/doctor` 호출.

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
- `AGENTS.md` 존재·줄 수 (Constitution SSOT)
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
       모든 환경 → git pre-commit wrapper 설치 (install-git-hooks.sh, idempotent)
       (Claude Code PreToolUse 는 에이전트 커밋만 잡아요 — 사람 터미널 커밋은 git hook 이 커버)
 OpenCode config :  opencode.json (OpenCode 환경 감지 시만)

추가 (brownfield):
 onboarding skill 임시 활성화 → 도메인·룰 자동 분류
```

## 3. 단일 동의 프롬프트

```
이대로 설치할까요? (Y/n)
```

`Y`(또는 `네`, `ㅇ`) → 진행. 그 외 → 취소(파일 변경 0).

## 4. 설치 — `provision.sh` 위임

MANIFEST 를 SSOT 로 `templates/default/` 를 프로젝트에 복사해요. 열거를 hardcode 하지
않아서, template 에 디렉토리가 늘면 MANIFEST 만 갱신하면 따라와요.

로직은 전부 `scripts/provision.sh` 에 있어요. **여기 인라인하지 마세요** — 마크다운
안의 bash 는 파일이 아니라서 `bash -n` 도 CI 도 닿지 않아요. 하필 사용자가 제일 먼저
돌리는 코드예요.

```bash
# plugin root — Claude Code 표준 ${CLAUDE_SKILL_DIR} 우선,
# ${CLAUDE_PLUGIN_ROOT} 는 비표준이라 호환용 fallback 에만 둠.
if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
    PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    echo "[goax] ERROR: \${CLAUDE_SKILL_DIR} \${CLAUDE_PLUGIN_ROOT} 둘 다 미설정." >&2
    echo "       이 SKILL은 plugin 컨텍스트(/plugin install goax 후)에서만 동작해요." >&2
    exit 1
fi

RESULT=$(bash "$PLUGIN_ROOT/scripts/provision.sh" --json)

echo "$RESULT" | jq -r '"✓ 복사 \(.result.copied)건 · seed 유지 \(.result.seeded_kept)건 · reference \(.result.reference_files)개 · git hook \(.result.git_hooks)"'
echo "$RESULT" | jq -r '.warnings[]? | "⚠ \(.)"'
echo "$RESULT" | jq -r '.result.suggested[]? | "  · \(.) — 기존 파일 보존, plugin 최신본은 .suggested 로 옆에"'
echo "$RESULT" | jq -r '.result.preserved[]? | "  · _templates/\(.) 수정본 보존"'
```

설치 규칙은 3층이고 스크립트가 강제해요:

| 층 | 대상 | 재실행 시 |
|---|---|---|
| MANIFEST 무조건 | `.ax/scripts/`, `.ax/hooks/`, `_templates/` … | 덮어써요 (사용자 spec·ADR·mistake 은 `cp -R` merge 라 보존) |
| MANIFEST `src -> dst` | `state.json`, `current-task.json` | **안 건드려요** — 진행 중인 phase 를 idle 로 되돌리면 그 spec 이 추적에서 조용히 빠져요 |
| MANIFEST 외 조건부 | `CLAUDE.md`, `AGENTS.md`, `config.yml`, `spirit/*`, `settings.json` … | 내용이 다를 때만 `.suggested` 로 옆에. 같으면 아무것도 안 해요 |

`suggested` 가 비어있지 않으면 §7 마이그레이션 안내로 이어가세요.

> **변수 컨벤션** — `$CLAUDE_PROJECT_DIR`(사용자 프로젝트 루트)·`${CLAUDE_SKILL_DIR}`(skill 자체 위치, plugin root는 `${CLAUDE_SKILL_DIR}/../..`)는 Claude Code 공식 변수예요. `$CLAUDE_PLUGIN_ROOT`는 비표준 — 과거 호환용 fallback에만 둘 것. `$PLUGIN_DIR` 같은 임의 변수는 정의되지 않아요.

> **MANIFEST 갱신 규칙** — `templates/default/`에 새 디렉토리·파일을 추가할 때 `templates/default/MANIFEST`도 같이 갱신. doctor가 MANIFEST vs 사용자 프로젝트 실제 설치 상태를 diff해서 누락 감지. 조건부 복사(CLAUDE.md, .claude/settings.json 등)는 manifest 외 — `scripts/provision.sh` §5~§6.7 에서 처리해요.

## 5. brownfield면 — onboarding으로 위임

**`MODE=install` 일 때만 판정해요.** `MODE=update` 면 이 판정을 다시 하지 않아요 — 두 번째
호출부터는 goax 자신이 깐 `CLAUDE.md`(`@AGENTS.md` alias)·`.ax/hooks/`가 항상 존재해서, 판정
근거를 그대로 재사용하면 재호출마다 매번 brownfield 로 떨어져 onboarding 이 반복 발동해요.

판정 근거는 **§1 분석 시점의 기존 자산**이고 goax 산출물은 제외해요 — customize 안 된
`CLAUDE.md`(1줄 alias)나 `.ax/hooks/*.sh`(goax 가 이번에 깐 것) 는 brownfield 신호가 아니에요.
기존 자산이 있으면(§1 분석에서 발견한, goax 설치 이전부터 있던 CLAUDE.md, hooks, modules > 1,
external spec 중 하나라도) `.ax/.onboarding-pending` 마커를 작성하고 onboarding skill로 자연스럽게 이어가요:

```
✓ 골격 설치 완료.
이제 onboarding으로 이어갈게요. 도메인과 룰을 함께 정리해요...
```

→ onboarding skill 발동.

## 6. greenfield면 — `zero` 로 인계

빈 리포는 brownfield 판정 조건(CLAUDE.md · hooks · modules > 1 · external spec)을 하나도 안 만족해서
반드시 여기로 떨어져요. **그런데 0→1 은 결정 밀도가 가장 높은 구간이에요** — 안내만 하고 끝내면
`domain_risk` 가 출고 예시로 남고, triage 가 그걸 못 찾아 `default_risk`(L0)로 흘려서
"S/M × L0 = 즉시 작업, spec 불필요" 로 가요. 역면접도 발동 조건 미달로 스킵돼요.

그래서 아래 안내를 낸 뒤 **`zero` skill 로 넘겨요.**

```
🥳 goax 도입 완료.

📂 .ax/ runtime — .gitignore 자동 처리됨
 .ax/state.json, .ax/current-task.json — 매 호출마다 변경되는 상태 (per-machine)
 .ax/*.suggested — install/onboarding 머지 임시본
 → PR diff 노이즈 방지 위해 .gitignore에 자동 추가 (또는 기존 .gitignore에 누락 줄 append)

📋 Mistake Loop — 주기적 audit 권장
 실수는 "실수 기록해줘" 로 캡처해요 (사용자 의도적 capture, race-free + redact 보호)
 audit_cadence_days=7 (.ax/config.yml) — 주 1회 회고 권장
 실행: "goax audit" 또는 "실수 회고" — 카테고리 N회 누적 시 CRITICAL/MANDATORY 룰 승격 후보 제시
 자동화: Claude Routine으로 weekly cron 등록하면 PR 형태로 audit 결과 받기 가능

다음에 시도해보세요:
 "결제 환불 정책 변경 작업 계획 세워줘"
 → triage skill이 Size×Risk 분류 → spirit·룰·페르소나 자동 주입
```

---

**→ `zero` skill 을 이어서 발동해요.**

제품 정의 역면접 → PRD v0.1 → 되돌리기 비싼 결정 ADR → `domain_risk` 최초 설정 →
스캐폴드 → 집행 배관 + 네거티브 프로브 → 첫 배포 → 인계 노트 개설.
순서가 메시지예요 — **제품·비즈니스가 앞이고 기술이 뒤예요.**

사용자가 지금 당장 시작하지 않겠다고 하면 그대로 멈춰요. 나중에 `"새 프로젝트 시작"`·`/zero` 로
직접 부를 수 있고, `.ax/` 는 있는데 ADR 0개 + 코드 없음 상태에서도 스스로 발동해요.

## 7. AGENTS.md / CLAUDE.md 마이그레이션 가이드 (customize 본문 보존)

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
bash .ax/scripts/bash/update-state.sh --skill up   # canonical(derived·hud 캐시) + last_skill·skill_calls 를 같은 락 안에서
```
