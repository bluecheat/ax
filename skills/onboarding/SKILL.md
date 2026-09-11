---
name: onboarding
description: "/up (install or update) 직후 또는 사용자가 'goax 분석/마무리/세팅' 등을 말할 때 발동. .ax/.onboarding-pending 마커가 있으면 우선 처리. 프로젝트의 CLAUDE.md·모듈·도메인·외부 spec을 실제로 읽고 도메인 위험도(L0~L3) 매핑·hooks 강도·룰 분류를 사용자와 대화하며 .ax/config.yml과 adoption-plan.md에 기록. 트리거: '/onboarding', 'goax 도입 마무리', 'goax 분석', 'goax 마무리', '하네스 onboarding'."
---

# onboarding — 프로젝트 분석 + 5가지 결정

## 언제 발동하는가

다음 중 하나면 **반드시** 이 skill을 따라요:

1. `.ax/.onboarding-pending` 파일이 존재할 때 (사용자 메시지와 무관하게 우선)
2. 사용자가 "goax 도입", "goax 마무리", "goax 세팅", "goax 분석" 등을 말할 때
3. `goax up` 직후 첫 사용자 메시지일 때

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 따라요. 출력은 clack 스타일 (◆/│/├/└ + ●/○ + 시맨틱 이모지).

이 문서는 **흐름과 결정**만 담아요. 그 Q 를 출력하기 직전에 필요한 절만 읽어요:

| 파일 | 언제 |
|---|---|
| `references/boxes.md` | 사용자에게 보여줄 박스 원문 — 각 Q · Sub-Q · 중복 감지 · 완료 안내 |
| `references/signal-guide.md` | 룰을 🔴/🟡/🔵 로 가를 때 (§2.4) · hook 등록 시점 후속 · 프로젝트 hook 작성 가드 |
| `references/import-spec.md` | Q4 에서 [b] SDD 변환을 골랐을 때만 |

## 왜 bash가 아니라 Claude가 하는가

bash 휴리스틱(정규식·glob)은 모듈 의존을 못 읽고 도메인 noise(`ad`, `ba` 같은 짧은 prefix)만 잡아요. 실제 분석은 코드를 읽어야 해요. 그래서 이 단계를 Claude가 맡고, 파일 조작(prepend·인덱스·카운트)은 스크립트가 해요.

## 1. 마커 읽기

`.ax/.onboarding-pending` 이 있으면 그 안의 raw discovery 결과를 출발점으로 써요. 형식 (key=value): `repo_shape` `module_count` `claude_md_lines` `claude_md_path` `external_specs` `active_hooks` `stack`.

## 2. 깊이 분석 — 추측 금지, 파일로 확인 못 한 건 물어요

### 2.0 사전 bash 스캔 — 큰 프로젝트 대비

```bash
ls settings.gradle.kts pnpm-workspace.yaml lerna.json package.json 2>/dev/null           # 모노레포 형태
grep -E '^include\s*\(' settings.gradle.kts 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' | sed 's|^:||' | head -30
ls -d apps/*/ packages/*/ projects/*/ modules/*/ 2>/dev/null | head -20                    # 디렉토리 기반 모듈
echo "root CLAUDE.md: $(wc -l < CLAUDE.md 2>/dev/null) 줄, 시그널 $(grep -cE '🔴|🟡|🔵' CLAUDE.md 2>/dev/null)건"
find . -maxdepth 4 -name CLAUDE.md -not -path "./.*" 2>/dev/null
ls -d ../*-spec ../*-governance ../*-standards 2>/dev/null                                 # 외부 spec 후보
ls .pre-commit-config.yaml .husky .coderabbit.yaml .coderabbit.yml .cursorrules .cursor 2>/dev/null
```

이 인벤토리가 `📍 발견` 의 1차 자료예요. 코드를 읽을 때도 여기서 시작해요.

### 2.1 모듈 구조
Gradle `include(...)` / `pnpm-workspace.yaml` / `package.json#workspaces`. 모듈 간 의존은 표면적으로라도 (`implementation(project(":x"))`).

### 2.2 도메인 식별
모듈명·패키지 트리에서 **의미 있는 도메인 단어**만 5~12개. 짧은 prefix(`ad`, `ba`)·일반 단어(`common`, `util`)·기술 슬라이스(`adapter`, `gateway`) 제외.

큰 모노레포(후보 50+)는 돈 흐름(payment·billing·settlement) → 사용자 자산·권한(order·auth·coupon) → 명확한 명사(catalog·search) 순으로 추리고, 도메인 > 15개면 핵심 5~10개 + `default: L1`. 박스: `boxes.md` §큰 프로젝트.

### 2.3 도메인 위험도

| 레벨 | 기준 | 예시 |
|---|---|---|
| **L3** | 결제·정산·잔고 — 돈/PG 호출이 직접 흐름 | payment, settlement, billing, balance |
| **L2** | 주문·인증·세션 — 사용자 자산/권한 영향 | order, auth, session, coupon, reward |
| **L1** | 일반 도메인 — 데이터 수정 가능 | catalog, product, search, notification |
| **L0** | 문서/내부/관측 — 영향 적음 | docs, monitoring, internal-tools |

### 2.4 룰 분류 + 시그널

기존 Constitution 의 룰을 카테고리(`security · naming · testing · pr · error-handling · concurrency · observability · architecture · data · uncategorized`)로 나누고, 각각 시그널을 정해요. **판별 질문 하나**: "어겨졌을 때 *사람이 승인 결정*을 내려야 통과되는가?" — Yes → 🟡. No 인데 자동 검증 가능 → 🔴 (hook 등록 후). No 인데 가이드 → 🔵. 실행 안내면 룰이 아니라 `## Commands`.

🔴 로 두려면 **막는 hook 파일 경로**를 지금 댈 수 있어야 해요. 못 대면 🟡 + `enforced_by: TODO:<absolute date>`. 판별표·가드·invariant(I1/I2/I3/I5)·adoption-plan 기재 형식: `references/signal-guide.md`.

### 2.5 외부 spec
sibling(`<repo>-spec`)이나 자기 안의 `spec/` `specs/` `governance/` 에 결정 문서가 있으면 후보로.

### 2.6 CLI 환경 자동 감지 (Pre-flight)

```bash
HAS_CLAUDE=false; HAS_OPENCODE=false
{ [ -n "${CLAUDE_PROJECT_DIR:-}" ] || [ -n "${CLAUDE_SKILL_DIR:-}" ]; } && HAS_CLAUDE=true
{ [ -n "${OPENCODE_CONFIG_DIR:-}" ] || [ -d ".opencode" ] || [ -d "$HOME/.config/opencode" ]; } && HAS_OPENCODE=true
command -v opencode >/dev/null 2>&1 && HAS_OPENCODE=true
```

| 감지 | 자산 install 범위 |
|---|---|
| Claude Code 만 | AGENTS.md + CLAUDE.md (alias) + .claude/settings.json |
| OpenCode 만 | AGENTS.md + CLAUDE.md (fallback) + opencode.json + `install-git-hooks.sh` 안내 |
| 둘 다 / 미감지 | 양쪽 모두 (미감지는 사용자 알림) |

Q1 박스 `📍 발견` 첫 줄에 `CLI 환경: <결과>`. OpenCode 면 Q5 [a] 끝에 "PreToolUse 미지원 — `install-git-hooks.sh` 로 git pre-commit 보전" 을 붙여요.

## 3. 다섯 결정 — 한 번에 하나씩, 디폴트는 권장값

박스 표준·답 처리 3단계(재확인 → 작업 → ✓ 확정)는 `boxes.md` §0. 필수 규칙: 권장 `●` + `✓ 권장`, 위험 옵션엔 `⚠`, 옵션 사이 빈 줄, Q2 부터 헤더 우측에 이전 답 요약, "수정 없음" 이면 `📂` 생략.

### Q1. Constitution — `boxes.md` §Q1
- [a] 자동 분류 → `.ax/adoption-plan.md` 작성 (라벨 제안 + 카테고리 매핑). Constitution 은 그대로. ✓ 권장
- [b] 가이드만 (채팅에 분류표) · [c] 보류 → Q2

AGENTS.md 가 SSOT, CLAUDE.md 는 `@AGENTS.md` alias. 라벨링·prepend 는 AGENTS.md 본문에.

### Q2. 도메인 위험도 — `boxes.md` §Q2

박스에 들어가는 숫자는 **실측**이에요. 초안을 `.ax/config.yml` 에 쓰기 전엔 제안 목록으로, 쓴 뒤엔 스크립트로 세요:

```bash
bash .ax/scripts/bash/zero-domain-risk.sh --show --json    # result.before.keys · result.default_risk
```

"30 keys" 같은 추정을 박고 사후 정정하는 흐름은 금지 — 보고 숫자의 신뢰를 깎아요. 작성 규칙: 도메인 ≤ 15 → 모두 매핑, > 15 → 핵심 5~10 + `default: L1`. 근거 메모는 경계선 케이스(settlement·coupon)만. 키는 영문 kebab-case, 한글은 주석으로만.

- [a] 제안대로 기록 ✓ 권장 · [b] 사용자 수정 후 [a] · [c] 비워두기

### Q3. hooks 강도 — `boxes.md` §Q3
- [a] `warning` (메시지만) ✓ 권장 · [b] `fail` (CRITICAL 위반 시 차단) · [c] 비활성 → `.ax/config.yml sensors.mode`

### Q4. 외부 spec — 있을 때만, `boxes.md` §Q4
- [a] 링크만 (`.ax/docs/external-specs.md`) ✓ 권장 · [b] SDD 변환 흡수 (규칙: `references/import-spec.md`) · [c] snapshot 만 · [d] 무시

### Q5. 4계층 활성화 — `boxes.md` §Q5

> Q1~Q4 는 자산을 *준비*했고, Q5 가 *활성화*해요. "도구가 깔린 것" 과 "4계층이 작동하는 것" 은 달라요.

- [a] Layer 1 + 2 + 3 활성화 ✓ 권장 · [b] Layer 1 만 · [c] 보류

**[a] 적용 순서**

1. **Layer 1 블록 작성** — adoption-plan 의 `Layer 1 (root)` 룰로 임시 파일(예: `.ax/.constitution-block.md`)에 다섯 블록을 써요:
   (a) `# <PROJECT> — Constitution` 헤더 + 룰 토큰 컨벤션 한 줄 · (b) `## META — 핵심 가드레일` (**AGENTS.md.template 의 문구 그대로** — Triage First + lean 원칙) · (c) `## 시그널 의미` (템플릿 문구 그대로) · (d) `## CRITICAL` / `## MANDATORY` 룰 본문 (`🔴 **\`<scope>:CRITICAL:NNN\`** … — <hook 경로>`) · (e) `## CONVENTION`.
   - (d) 의 **사용자 정의 CRITICAL 은 룰마다 hook 등록 시점을 물어요** — `boxes.md` §(d.1), 후속은 `signal-guide.md` §hook 등록 시점. universal(secrets·파괴 명령·보호 경로)은 이미 hook 이 있어 안 물어요.
   - (e) 는 `boxes.md` §(e) 로 물어요 — [a] `@.ax/spirit/rules/<cat>.md` import ✓ 권장 · [b] 인라인 ID 3~5개 · [c] 링크만.
2. **적용은 스크립트로** — 기존 본문은 `---` 아래 보존돼요:
   ```bash
   BLOCK=.ax/.constitution-block.md
   bash .ax/scripts/bash/constitution-apply.sh --block "$BLOCK" --dry-run --json      # 무엇이 어디에 들어가는지
   bash .ax/scripts/bash/constitution-apply.sh --block "$BLOCK" --json                # prepend (이미 적용이면 exit 2)
   bash .ax/scripts/bash/constitution-apply.sh --scan-duplicates --block "$BLOCK" --json   # 정확 일치 목록 → 박스
   ```
3. **중복 룰 정리 — 박스를 먼저** (`boxes.md` §중복 감지). 신 블록과 구 본문이 같은 룰을 두 번 말하면 drift 시한폭탄이에요. 사용자가 [a] 를 고른 *뒤에만*:
   ```bash
   bash .ax/scripts/bash/constitution-apply.sh --drop-exact --block "$BLOCK" --json   # 정확 일치만. 부분 일치·H2 통삭제는 사용자 확인
   bash .ax/scripts/bash/constitution-apply.sh --append-index --json                  # 4계층 인덱스 (이미 있으면 exit 2)
   rm -f "$BLOCK"
   ```
4. **spirit/rules** — adoption-plan 의 `Spirit rules` → `.ax/spirit/rules/{architecture,data,testing,ops}.md`. frontmatter:
   ```yaml
   ---
   category: architecture
   description: 모듈 의존 방향, 레이어 분리 룰
   # paths: 를 채우면 spirit-rules-inject.sh 가 그 경로 편집 때만 주입해요 (path-scoped). 비우면 universal — @import 로 매 turn
   ---
   ```
5. **Layer 2 stub** — Q2 의 **L2/L3 도메인이면서 모듈로 식별된 것만** `.ax/modules/<name>/rules.md` (`_templates/module/rules.md` cp, `keywords:` frontmatter만 채움 — 도메인명 + 한글 동의어, 본문은 빈 템플릿). L0/L1 은 stub X. 보고: "L3/L2 도메인 N개에 stub. keywords 만 채웠으니 triage 매칭은 되고 본문은 필요할 때."
6. **Layer 3 첫 ADR** — `cp .ax/_templates/adr/0000-template.md .ax/docs/adr/0001-goax-adoption.md`. 메타(0001 · 오늘 · 승인) · 컨텍스트(도입 이유) · 대안(A 도입 안 함 / B PRD-first / C 4-Layer 채택) · 결정(hooks=Q3 · domain_risk=Q2 · 외부 spec=Q4) · 결과(단기 spirit 주입·triage 게이팅 / 장기 mistakes 루프 / 후속 1주 doctor+audit / 측정 mistakes 주 5건↓ · 1개월 검토).
7. **정리** — `rm -f .ax/CLAUDE.md.suggested .ax/adoption-plan.md .ax/.onboarding-pending`
8. **State** — `bash .ax/scripts/bash/update-state.sh` 후 `doctor` 한 번 (canonical 갱신 + 도달 지도 확인).
9. **인계 노트** — 다음 세션이 처음 읽을 것을 적어요:
   ```bash
   bash .ax/scripts/bash/status-note.sh --add next "첫 spec: <가장 위험한 도메인> — \"spec 만들어줘 — <slug>\"" --json
   bash .ax/scripts/bash/status-note.sh --add open "<Q2 에서 미룬 도메인 레벨 결정>" --json     # 있을 때만
   ```

**Sub-Q4 statusline** (`boxes.md` §Sub-Q4) — 기존 `.claude/settings.json` 의 statusLine 을 먼저 검사해 박스에 표시하고 사용자가 명시적으로 닫게 해요. 이미 활성이라고 임의 skip 금지. [a]/[b] 면 `hud` skill 위임.

**Sub-Q5 settings.json.suggested 머지** (`boxes.md` §Sub-Q5) — up 이 기존 settings.json 을 보존하며 만든 `.ax/settings.json.suggested` 가 있으면 머지 여부를 물어요. 정식 step 이에요 — 임기응변 X.

## 4. 적용 보고

```
✓ Q1 — .ax/adoption-plan.md 생성 (96줄). Constitution 은 그대로.
✓ Q2 — .ax/config.yml domain_risk 30 keys + default L1
✓ Q3 — .ax/config.yml sensors.mode = warning
✓ Q4 — .ax/docs/spec/ 4개 SDD 변환 + adr/ 3개 재번호 + imported/<name>/ snapshot
✓ Q5 — Layer 1 시그널화 (룰 8개, spirit/rules 4 카테고리) · Layer 2 stub N개 · Layer 3 ADR 0001 · 정리
```

**보고하는 숫자는 raw grep 이 아니라 의미 단위예요**:
- 시그널 카운트: 범례 라인 제외, **유니크 룰 토큰** — `grep -oE '<SCOPE>:(CRITICAL|MANDATORY|CONVENTION):[0-9]+' AGENTS.md | sort -u | wc -l`. 또는 `rules-index.sh --json` 의 `counts`.
- domain_risk 키: `zero-domain-risk.sh --show --json` 의 `result.before.keys`.
- 출현 횟수와 유니크 ID 를 헷갈리지 않기 — "토큰 N개" 는 유니크가 정상 의미.

## 5. 마무리

```bash
rm -f .ax/.onboarding-pending
```

plugin skill 은 plugin 디렉토리에 있어 자가 삭제가 안 돼요 — 마커로만 완료를 표시해 다음 세션에서 재발동을 막아요. 완료 안내는 `boxes.md` §완료 안내. `_templates/spec/` 을 "프로젝트 SSOT" 라 부르지 마세요 — 작업 spec SSOT 는 `.ax/docs/spec/NNN-<slug>/spec.md` 고 `_templates/` 는 템플릿이에요.

## 절대 금지

- 추측만으로 `domain_risk` 를 박지 않아요. 모르면 물어요.
- bash 휴리스틱 값을 검증 없이 쓰지 않아요. 코드를 직접 한 번 봐요.
- 한 번에 다섯을 다 묻지 않아요. 한 결정씩.
- **plugin shipped hook 파일을 직접 수정하지 않아요.** 프로젝트별 CRITICAL 의 hook 은 새 파일 — 가드 템플릿은 `signal-guide.md` §hook 작성 가드. plugin 갱신 시 출고본으로 회귀하니까요.
- **CONVENTION 형식은 한 가지로** — 인라인 정의 또는 @import 위임. 혼합 금지 (`signal-guide.md` 끝).
- **카운트는 pre-emit 실측.** 사후 정정 형태 금지.
- **prepend·중복 정리를 묶어 사후 보고하지 않아요.** 중복 박스에서 사용자가 [a] 를 고른 뒤에만 `--drop-exact`.
- Mistake 는 hook 자동 capture 가 아니라 사용자 명시 `mistake` skill 호출로만.

## state.json 갱신

```bash
bash .ax/scripts/bash/update-state.sh --skill onboarding   # canonical — Q5 [a] 후 layer.active 등 derived + last_skill·skill_calls
```
