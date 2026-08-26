---
name: onboarding
description: "/up (install or update) 직후 또는 사용자가 'goax 분석/마무리/세팅' 등을 말할 때 발동. .ax/.onboarding-pending 마커가 있으면 우선 처리. 프로젝트의 CLAUDE.md·모듈·도메인·외부 spec을 실제로 읽고 도메인 위험도(L0~L3) 매핑·hooks 강도·룰 분류를 사용자와 대화하며 .ax/config.yml과 adoption-plan.md에 기록. 트리거: '/onboarding', 'goax 도입 마무리', 'goax 분석', 'goax 마무리', '하네스 onboarding'."
---

# onboarding — 프로젝트 분석 + 4가지 결정

## 언제 발동하는가

다음 중 하나면 **반드시** 이 skill을 따라요:

1. `.ax/.onboarding-pending` 파일이 존재할 때 (사용자 메시지와 무관하게 우선)
2. 사용자가 "goax 도입", "goax 마무리", "goax 세팅", "goax 분석" 등을 말할 때
3. `goax up` 직후 첫 사용자 메시지일 때

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 따라요. 출력은 clack 스타일 (◆/│/├/└ + ●/○ + 시맨틱 이모지) — 표준은 §3.0 참조.

## 왜 bash가 아니라 Claude가 하는가

bash 휴리스틱(정규식·glob)은 모듈 의존을 못 읽고 도메인 noise(`ad`, `ba` 같은 짧은 prefix)만 잡아내요.
실제 분석은 코드를 읽어야 가능해요. 그래서 이 단계를 Claude가 맡아요.

## 1. 마커 읽기

`.ax/.onboarding-pending` 이 있으면 그 안의 raw discovery 결과를 출발점으로 써요.
형식 (key=value):

```
repo_shape=...
module_count=...
claude_md_lines=...
claude_md_path=CLAUDE.md
external_specs=...
active_hooks=...
stack=...
```

## 2. 깊이 분석 (Claude가 직접 코드를 본다)

다음을 실제 파일로 확인해요. **추측 금지 — 파일로 확인 못 한 건 사용자에게 물어요.**

### 2.0 사전 bash 스캔 — 큰 프로젝트 대비

LLM이 파일을 모두 읽기 전 bash로 **자산 인벤토리**를 확보:

```bash
# 모노레포 형태
ls settings.gradle.kts pnpm-workspace.yaml lerna.json package.json 2>/dev/null

# 모듈 카운트 (Gradle)
grep -E '^include\s*\(' settings.gradle.kts 2>/dev/null \
 | sed -E 's/.*"([^"]+)".*/\1/' | sed 's|^:||' | head -30

# 모듈 카운트 (디렉토리 기반)
ls -d apps/*/ packages/*/ projects/*/ modules/*/ 2>/dev/null | head -20

# CLAUDE.md 통계 (root + 모듈별)
echo "root CLAUDE.md: $(wc -l < CLAUDE.md 2>/dev/null) 줄, 시그널 $(grep -cE '🔴|🟡|🔵' CLAUDE.md 2>/dev/null)건"
find . -maxdepth 4 -name CLAUDE.md -not -path "./.*" 2>/dev/null

# 외부 spec 후보
ls -d ../*-spec ../*-governance ../*-standards 2>/dev/null

# 활성 hooks
ls .pre-commit-config.yaml .husky 2>/dev/null

# AI 리뷰 도구
ls .coderabbit.yaml .coderabbit.yml .cursorrules .cursor 2>/dev/null

# 도메인 키워드 후보 (Kotlin/Java 패키지에서)
find . -type d -path "*/src/main/kotlin/com/*/<project>/*" 2>/dev/null \
 | sed 's|.*/||' | sort -u | head -30
```

이 결과를 `📍 발견` 섹션 출력의 1차 자료로 써요. LLM이 코드를 읽을 때도 이 인벤토리에서 시작.

### 2.1 모듈 구조
- 모노레포면 각 모듈의 `CLAUDE.md` 유무 확인
- Gradle: `settings.gradle.kts`에서 `include(...)`
- pnpm/yarn: `pnpm-workspace.yaml` / `package.json#workspaces`
- 모듈 간 의존을 적어도 표면적으로 파악 (build.gradle.kts의 `implementation(project(":x"))` 등)

### 2.2 도메인 식별
- 모듈명·패키지 트리·도메인 디렉토리(`com.<org>.<project>.<domain>` 형태 등)에서 **의미 있는 도메인 단어**만 추출
- 짧은 prefix(`ad`, `ba`)·일반 단어(`common`, `util`)는 제외
- 5~12개 정도로 정리

**큰 모노레포 (도메인 후보 50+개) 처리 규칙**:

<project>-* 같은 큰 모노레포에선 패키지 200+개가 발견될 수 있어요. 모두 매핑 X — 다음 우선순위로 추리기:

1. **돈 흐름이 직접 닿는 키워드 우선**: payment, billing, refund, settlement, balance → 자동으로 후보
2. **사용자 자산·권한**: order, cart, auth, session, coupon, reward, delivery → 후보
3. **도메인 명사가 명확한 것**: catalog, product, store, search, notification → 후보
4. **제외 대상**:
   - 짧은 prefix (`ad`, `ba`, `cs`) — 단독으로 의미 모호. 단 사용자가 명시 확인하면 포함 가능
   - 인프라 단어: `adapter`, `aggregator`, `bigquery`, `client`, `gateway` — Layer가 아닌 기술 슬라이스
   - 일반 명사: `common`, `util`, `core`, `main` — 도메인이 아님
   - 알리아스 변형: `adaptor` vs `adapter` — 하나만
5. **개수 가이드**: 도메인 ≤ 15개면 모두 매핑, 초과면 핵심 5~10개 + `default: L1` 명시

**큰 프로젝트 시 사용자에게 보여줄 박스**:

```
📍 도메인 후보 N개 발견 (큰 프로젝트 — 의미 있는 것만 추렸어요)

분류 제안 (L3/L2/L1)
 L3 돈/PG  payment, settlement, billing, balance
 L2 자산   order, coupon, reward, cart, delivery, auth, session
 L1 일반   catalog, product, store, search, notification, ad

제외한 것 — 이유
 ad/ba/cs (짧은 prefix, 모호)
 adapter/aggregator/gateway (기술 슬라이스, 도메인 X)
 common/util/core (일반 명사)

[a] 이대로 매핑 (default: L1)        ✓ 권장
[b] 추가 도메인 매핑 — 어떤 거?
[c] 제외 항목 일부 다시 포함
```

### 2.3 도메인 위험도 매핑
실제 코드 동작을 기준으로 L0~L3를 부여해요:

| 레벨 | 기준 | 예시 |
|---|---|---|
| **L3** | 결제·정산·잔고 — 돈/PG 호출이 직접 흐름 | payment, settlement, billing, balance |
| **L2** | 주문·인증·세션 — 사용자 자산/권한 영향 | order, auth, session, coupon, reward |
| **L1** | 일반 도메인 — 데이터 수정 가능 | catalog, product, search, notification |
| **L0** | 문서/내부/관측 — 영향 적음 | docs, monitoring, internal-tools |

### 2.4 CLAUDE.md 룰 분류
기존 `CLAUDE.md`의 각 룰을 다음 카테고리로 분류:
`security · naming · testing · pr · error-handling · concurrency · observability · architecture · data · uncategorized`

### 2.4.1 시그널 분류 기준 (CRITICAL/MANDATORY/CONVENTION)

**카테고리(2.4)는 "무엇에 관한 룰인가", 시그널은 "얼마나 강제되는가"** — 직교 축이에요. 시그널 오분류는 시스템 신뢰를 깨므로 다음 기준을 엄격히 적용해요.

| 시그널 | 기준 | 검증 주체 |
|---|---|---|
| 🔴 CRITICAL | hooks(grep/regex/정적분석)가 **실제 차단 가능**한 룰 | 자동 — hook 파일 경로 명시 의무 |
| 🟡 MANDATORY | 사람 승인이 들어가야 통과되는 룰 (ADR, cross-team 변경 등) | 사람 게이트 |
| 🔵 CONVENTION | 권장이지만 차단 안 함 — 코드리뷰·LLM 행동 가이드 | 자동·수동 모두 OK |

**🔴 CRITICAL 분류 가드 (가장 흔한 실수)**

CRITICAL로 분류하기 전에 **그 룰을 막는 hook 파일 경로**를 정할 수 있어야 해요. 못 정하면 MANDATORY로 강등.

| 룰 예시 | 차단 가능? | 시그널 | 근거 |
|---|---|---|---|
| 파괴적 명령 (`rm -rf /`, `git push --force`) | ✅ | 🔴 | `pre-bash/block-destructive.sh` grep |
| 보호 경로(`CLAUDE.md`, `.ax/`) 무단 수정 | ✅ | 🔴 | `pre-edit/check-protected-paths.sh` |
| DDL 파일명 `V{타임스탬프}__*.sql` | ✅ | 🔴 | `pre-commit/critical-rule-grep.sh`에 추가 |
| 신규 테스트 = Kotest+MockK | ✅ (부분) | 🔴 또는 🟡 | import grep 가능. 단 hook 등록 필수 |
| Spring 테스트 = `@Tags("Integration")` | ✅ | 🔴 | grep으로 `@SpringBootTest` ↔ `@Tags` 매칭 |
| **모듈 의존 단방향** (`Core → Adapter` 금지) | ❌ | 🟡 | grep으로 못 잡음 — ArchUnit/Konsist 빌드 게이트 필요. 게이트 없으면 사람 리뷰 = MANDATORY |
| 순환 의존 금지 | ❌ | 🟡 | 정적 분석 도구 없으면 MANDATORY |
| Cross-domain 변경 시 2nd 리뷰어 | ❌ | 🟡 | 본질적 사람 게이트 |
| ADR 작성 의무 | ❌ | 🟡 | 사람 판단 |

**원칙**:
1. CRITICAL 룰 옆엔 `enforced_by: hook:.ax/hooks/<sub>/<name>.sh` (또는 `external:archunit` 등) inline 표기. schema: `.ax/docs/reference/rule-enforcement.md`
2. hook 미등록 룰은 CRITICAL 금지 (I1) — "나중에 등록할 거니까"는 거짓 약속. 🟡 MANDATORY + `enforced_by: TODO:<deadline>` 로 시작 → hook 작성 후 🔴 승급.
3. ArchUnit·Konsist·Modulith 같은 빌드 타임 검증이 이미 있으면 `enforced_by: external:archunit` 으로 명시하고 CRITICAL 가능. 없으면 MANDATORY + ADR로 "자동화 미도입" 기록.
4. **deadline 절대화** (I2): `TODO:+4w` 같은 상대 형식은 onboarding 이 즉시 absolute date 로 변환해서 박음. doctor 가 동적 해석 안 함 (deadline 기준일 표류 차단).

**🟡 MANDATORY 분류 가드 — "사람 승인 필요"가 진짜인가?**

MANDATORY는 **사람의 판단·승인·리뷰가 게이트로 들어가는 룰**만. 단순 실행 안내·작업 위치 지정·도구 사용법은 **MANDATORY가 아님** — `## Commands` 또는 `.ax/config.yml`의 `commands` 섹션으로 이동.

| 룰 예시 | 사람 게이트? | 결론 |
|---|---|---|
| 신규 도메인 추가 시 ADR 작성 | ✅ 결정 근거 검토 필요 | 🟡 MANDATORY |
| Cross-domain 변경 시 2nd 리뷰어 | ✅ 두 번째 사람 | 🟡 MANDATORY |
| 보안 민감 코드 변경 시 보안팀 검토 | ✅ 게이트 | 🟡 MANDATORY |
| 신규 의존성 추가 시 라이선스 확인 | ✅ 사람 판단 | 🟡 MANDATORY |
| **Gradle 명령은 `projects/X/`에서 실행** | ❌ 안내일 뿐 | `## Commands`로 이동 |
| **테스트는 Kotest+MockK로 작성** | ❌ 자동 grep 가능 | 🔴 CRITICAL (hook 등록 시) |
| **DDL 파일명 컨벤션** | ❌ 자동 grep 가능 | 🔴 CRITICAL |
| 모듈 의존 단방향 (ArchUnit 미도입) | ✅ 코드리뷰가 게이트 | 🟡 MANDATORY |

**판별 질문**: "이 룰이 어겨졌을 때, **사람이 승인 결정**을 내려야 통과되는가?"
- Yes → MANDATORY
- No, 자동 검증 가능 → CRITICAL (hook 등록 후)
- No, 그냥 가이드 → CONVENTION
- No, 실행 안내 → `## Commands` 또는 `.ax/config.yml`

**adoption-plan.md에 분류 시 의무 기재** (schema: `.ax/docs/reference/rule-enforcement.md`):
```yaml
- id: COMMERCE:CRITICAL:001
  rule: DDL 파일명 V{타임스탬프}__*.sql
  enforced_by: hook:.ax/hooks/pre-commit/critical-rule-grep.sh
  enforced_kind: block

- id: COMMERCE:MANDATORY:001
  rule: 모듈 의존 단방향
  enforced_by: human:pr-review
  enforced_kind: human

- id: COMMERCE:MANDATORY:002          # deferred 예시 — hook 작성 전까지
  rule: ArchUnit 도입 후 자동 검증
  enforced_by: TODO:2026-06-01        # absolute date 필수 (I2)
  enforced_kind: missing
```

**invariant** (doctor 가 매 호출 검증):
- I1. 🔴 CRITICAL 의 `enforced_by` 는 `hook:*` / `external:*` 만. `TODO:*`/`human:*`/`script:*` 면 자동으로 🟡 MANDATORY 강등 제안.
- I2. `TODO:*` 는 deadline (`YYYY-MM-DD` 또는 `+Nd/+Nw`) 필수. 상대 형식은 즉시 절대화.
- I3. doctor 가 deadline 임박(≤7일)·초과를 보고. 초과는 강등 권장 (자동 X).
- I5. `enforced_by: hook:<path>` 면 (a) 파일 실제 존재 (b) `.claude/settings.json` 에 등록. 둘 다 OK 여야 enforce 보장.

### 2.5 외부 spec
sibling 디렉토리(`<repo>-spec` 등)나 자기 안의 `spec/` `specs/` `governance/`가 의미 있는 결정 문서를 가지고 있으면 후보로 보여줘요.

### 2.6 CLI 환경 자동 감지 (Pre-flight)

Q1 박스를 그리기 전 사용 중인 AI CLI 를 감지해서 자산 install 범위를 결정해요. 사용자에게 별도 질문 박스 없이 발견 박스에 표시.

```bash
# 자동 감지 — 양립 가능 (둘 다 쓰는 사용자도 정상)
HAS_CLAUDE=false
HAS_OPENCODE=false
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || [ -n "${CLAUDE_SKILL_DIR:-}" ] && HAS_CLAUDE=true
[ -n "${OPENCODE_CONFIG_DIR:-}" ] && HAS_OPENCODE=true
[ -d ".opencode" ] || [ -d "$HOME/.config/opencode" ] && HAS_OPENCODE=true
command -v opencode >/dev/null 2>&1 && HAS_OPENCODE=true
```

| 감지 | 결과 | 자산 install 범위 |
|---|---|---|
| Claude Code 만 | claude | AGENTS.md + CLAUDE.md (alias) + .claude/settings.json |
| OpenCode 만 | opencode | AGENTS.md + CLAUDE.md (alias, fallback 용) + opencode.json + install-git-hooks 안내 |
| 둘 다 | both | 양쪽 자산 모두 |
| 미감지 | unknown | greenfield 가정 — 양쪽 모두 install + 사용자 알림 |

이 결과를 Q1 박스 `📍 발견` 의 첫 줄에 prepend: `CLI 환경: <감지결과>`.

OpenCode 감지 시 Q5 [a] 끝에 추가 안내: "Hook 시스템은 OpenCode 에선 PreToolUse 미지원 — `bash .ax/scripts/bash/install-git-hooks.sh` 로 git pre-commit 보전 권장 (CATASTROPHIC·secrets 검출)."

## 3. 사용자와 4가지 결정

분석 결과를 정리해 보여주고, 4 가지를 자연어로 물어요. **한 번에 하나씩**, 디폴트는 권장값.

### 3.0 질문 출력 패턴 (clack 스타일, 모든 Q에 적용)

이 skill의 clack 스타일 표준 — 핵심 글리프: `◆`(헤더) `│`(좌측 bar) `├─ ─`(섹션) `└`(끝) `●/○`(옵션 상태) `▸`(입력 마커). 시맨틱 이모지: `📍 발견` `🎯 목표` `📂 영향` `⚡ 큰 변경` `✓ 장점` `⚠ 위험·주의`.

표준 박스:

```
◆  Q<N>/5   <짧은 제목>                          · <이전 답 요약 (Q2부터)>
│
│  📍 발견  <사실 1~3줄, 추측 X>
│
│  🎯 목표  <의도 1~2줄>
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  <한 줄 요약>                                  ✓ 권장
│      📂 <영향 — 예: ".ax/file.md 신규 (96줄)">
│      ⚠  <위험·단점 — 있을 때만>
│
│  ○  [b]  <옵션>
│      📂 <영향>
│
│  ○  [c]  <보류·skip>
│
└  ▸  답해주세요   [a] / [b] / [c]
```

**필수 규칙**:
- 권장 옵션 `●` + 우측 `✓ 권장`, 미선택 `○`
- 위험 옵션엔 `⚠` 부가 줄 (예: 기존 파일 덮어쓰기)
- 옵션 사이 빈 줄 (`│`만) 1개로 시각 분리
- Q2부터 헤더 우측에 이전 답 요약: `· Q1=a · Q2=a`
- "수정 없음"이면 `📂` 라인 생략 (안전 신호 = 라인 없음)

### 3.0.1 시그널 라벨 — 처음 만날 때 한 번 설명

Q1에서 "라벨이 없다"고 발견 보고할 때, 사용자가 시그널을 모를 수 있어 짧게 설명해요:

```
시그널 의미:
 🔴 CRITICAL 자동 차단 — hooks가 막아요. 우회 불가.
 🟡 MANDATORY 사람 게이트 — 명시적 승인 필요.
 🔵 CONVENTION 가이드 — 권장이지만 차단은 안 함.
```

이후 Q들에선 이미 알고 있다고 가정. 한 번만 보여줘요.

### 3.0.2 답 처리 + 확정 메시지 (clack 스타일)

사용자가 [a]/[b]/[c]를 응답하면:

**1단계 — 행동 직전 안전 재확인** (한 줄):
```
<선택> 진행할게요. <안 건드리는 것> 그대로 두고 <할 것>.
```

**2단계 — 실제 작업** (Write/Edit/Bash tool)

**3단계 — ✓ 확정 메시지** (clack 스타일):
```
◆  Q<N> 완료   <한 줄 요약>
│  📂 <생성·수정 파일>
│  ✓  <보존된 것>
└  → 다음: <다음 단계 안내>
```

예:
```
◆  Q1 완료   CLAUDE.md 룰 자동 분류
│  📂 .ax/adoption-plan.md (96줄)
│  ✓  CLAUDE.md는 그대로
└  → 다음: Q2 도메인 위험도 매핑
```

### Q1. Constitution (AGENTS.md / CLAUDE.md) 처리

```
◆  Q1/5   Constitution 룰 처리   (AGENTS.md SSOT)
│
│  📍 발견
│   CLI 환경: <claude | opencode | both | unknown> (§2.6 자동 감지)
│   기존 CLAUDE.md 룰 N개 — 카테고리 정리됨, 시그널 라벨 없음
│   AGENTS.md: <존재 / 부재>
│   "비협상"(예: 모듈 의존) + "권장"(예: 테스트 컨벤션)이 한 파일에 섞임
│
│  ℹ Constitution SSOT 정책
│   AGENTS.md = SSOT (multi-CLI). CLAUDE.md = @AGENTS.md import alias.
│   기존 CLAUDE.md 본문이 customize 됐으면 .ax/CLAUDE.md.suggested 로 보존됨 (up 이 처리).
│   Q1=[a] 선택 시 룰 라벨링·prepend 는 AGENTS.md 본문에 적용 (CLAUDE.md 는 alias 라 그대로).
│
│   시그널 의미
│   🔴 CRITICAL    자동 차단 (hooks가 막음, 우회 불가)
│   🟡 MANDATORY   사람 게이트 (명시적 승인 필요)
│   🔵 CONVENTION  가이드 (권장, 차단 X)
│
│  🎯 목표
│   Layer 1  root CLAUDE.md      비협상 3~5개만 (🔴/🟡)
│   Spirit   .ax/spirit/rules/   권장 룰 (🔵, 카테고리별)
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  자동 분류                                       ✓ 권장
│      📂 .ax/adoption-plan.md 신규 (라벨 제안 + 카테고리 매핑표)
│      ✓  CLAUDE.md 그대로 — 검토 후 사용자가 수동 적용
│
│  ○  [b]  가이드만
│      📂 없음 — 채팅에 분류표만 출력
│
│  ○  [c]  보류 — Q2로 건너뛰기
│
└  ▸  답해주세요   [a] / [b] / [c]
```

선택 [a] → adoption-plan.md 마크다운 작성.

### Q2. 도메인 위험도

도메인이 많으면(>15개) **핵심만 매핑하고 default를 정의**해요. 모두 매핑하지 않아요.

⚠ **카운트 pre-emit 강제** — Q2 박스를 출력하기 *전에* 매핑한 키 수를 awk로 실측한 뒤 그 값을 박스에 박아. 시각적/대략 카운트 금지.

```bash
# 박스에 들어가는 "L3=N L2=M ..." 숫자는 이 명령의 결과만 사용:
# 주의: awk '/start/,/end/' range는 start 라인이 end 패턴에도 매칭되면 첫 줄에서 collapse → count=0.
# domain_risk: 자체가 ^[^[:space:]] 매칭이라 그 함정에 걸림. NR-guard로 우회.
KEYS=$(awk '/^domain_risk:/{found=1;next} found && /^[^[:space:]]/{exit} found' .ax/config.yml.draft \
        | grep -E '^[[:space:]]+[a-z][a-z0-9_-]*:[[:space:]]*L[0-3]' \
        | wc -l | tr -d ' ')
# 레벨별:
for L in L0 L1 L2 L3; do
    awk '/^domain_risk:/{found=1;next} found && /^[^[:space:]]/{exit} found' .ax/config.yml.draft \
        | grep -cE "^[[:space:]]+[a-z][a-z0-9_-]*:[[:space:]]*$L\\b"
done
```

박스에 "30 keys" 같은 추정값 박은 뒤 사후 정정하는 형태 금지 — 추정→정정 흐름은 사용자에게 보고하는 숫자의 신뢰도를 침식.

```
[Q2/5] 도메인 위험도 매핑 (이전: Q1=a)

 📍 발견
  도메인 N개 식별 (<project> 패키지 기준)
  >15개면 핵심만 매핑 + default L1 정책 권장

 🎯 목표
  .ax/config.yml의 domain_risk 채우기
  → triage가 작업 진입 시 도메인 키워드로 위험도 자동 결정

 레벨 기준
  L3 돈/PG 직접 흐름  payment, settlement, billing, balance
  L2 사용자 자산·권한 영향 order, auth, session, coupon, reward
  L1 일반 도메인   catalog, product, search, notification
  L0 문서·내부·관측   docs, monitoring, internal-tools

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ 다음 매핑으로 기록       [권장]
  L3: payment, settlement
  L2: order, coupon, delivery, shipment, cart
  L1: catalog, product, store, review, search, ad, notification
  L0: experiment, featureflag, log
  default: L1 (매핑 안 한 도메인은 L1로 처리)

  근거 (왜 이 레벨인가)
   • settlement L3 셀러 정산 → 환불·차감 발생, 결제와 동급
   • coupon L2  포인트성 자산, 결제 트랜잭션 안에서 동작 (L3 승급 여지)
   • delivery vs shipment 배송 상태 / 출고 분리. 둘 다 L2
   • subscription/discount default(L1) — 의견 따라 L2 승급 검토

  생성 없음
  수정 .ax/config.yml (domain_risk 섹션 + default)
  영향 파일 1개 수정

  ❗ 키 작성 규칙 (필수)
   - 키는 영문 kebab-case만 (예: payment, store-profile)
   - 한글은 주석으로만 (예: payment: L3 # 결제, PG, 환불)
   - 같은 도메인을 영문/한글 별도 키로 두지 않음 (중복 금지)
   - triage가 사용자 메시지의 한글을 영문 키로 LLM이 의역해서 매칭함

 [b] 사용자가 수정·교체 후 [a] 적용
  → 어떤 도메인을 어느 레벨로 옮길지 알려주세요
  (예: "delivery는 L2 그대로 좋아요. ad는 L0로 내려주세요")
  반영 후 다시 [a]로 확정 가능

 [c] 비워두기 — 나중에 직접 채우기 (.ax/config.yml 사용자 수정)

 ▸ 답해주세요 [a] / [b] (수정 내용 같이) / [c]
```

**작성 규칙**
- 도메인 ≤ 15개 → 모두 매핑 (default 생략 가능)
- 도메인 > 15개 → 핵심 5~10개만 매핑 + `default: L1` 명시
- 근거 메모는 **단일 단어로 결정 못 하는 케이스만** (settlement·coupon 같은 경계선)
- 매핑 결정 못 한 도메인은 `[b]` 옵션으로 사용자 의견 받기

### Q3. hooks 강도

```
[Q3/5] hooks 강도 (이전: Q1=a, Q2=a)

 📍 발견 기존 활성 hooks: <name> (또는 없음)
 🎯 목표 goax hooks가 위반을 어떻게 다룰지 결정 → .ax/config.yml의 sensors.mode

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ warning         [권장 — 안전]
  동작 메시지만 출력, 작업 차단 X
  이유 팀이 룰을 학습하는 동안 친절하게
  수정 .ax/config.yml (sensors.mode = warning)

 [b] ⚠ fail
  동작 CRITICAL 위반 시 작업 즉시 차단
  이유 룰이 안정화된 팀에 적합
  수정 .ax/config.yml (sensors.mode = fail)

 [c] 비활성
  동작 hooks 등록 자체 안 함
  수정 .claude/settings.json → settings.json.disabled

 ▸ 답해주세요 [a] / [b] / [c]
```

### Q4. 외부 spec (있을 때만)

```
[Q4/5] 외부 spec 처리 (이전: Q1=a, Q2=a, Q3=a)

 📍 발견 sibling 디렉토리: <name> (예: <repo>-spec)
   specs/ N개, policies/ M개, adr/ K개

 🎯 목표 Layer 3 (Spec/ADR)에서 외부 spec을 어떻게 다룰지 결정

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ 링크만         [권장 — 변경 0]
  생성 .ax/docs/external-specs.md (참조 인덱스 한 줄)
  수정 없음
  영향 외부 spec은 그대로 — 팀이 별도 관리, SSOT 단일

 [b] ★ SDD 포맷 변환 흡수       [추천 — 4계층 통합]
  생성 .ax/docs/spec/NNN-<slug>/{spec, plan, ...}.md (SDD 형식)
    + .ax/docs/spec/imported/<name>/ (원본 snapshot)
    + .ax/docs/adr/NNNN-*.md (외부 ADR 재번호)
  수정 없음
  영향 ⚠ 파일 N개. 우리 SDD 템플릿 헤더로 wrap, 본문 보존
  장점 spec-validate, triage 게이팅이 외부 spec까지 인식
  sync 외부 변경 시 .snapshot-meta로 diff 가능

 [c] snapshot만 (raw copy, 변환 X)
  생성 .ax/docs/spec/imported/<name>/
  수정 없음
  영향 파일 N개 복사 — 포맷 통일 X, 검색만 가능

 [d] 무시 — 손대지 않음

 ▸ 답해주세요 [a] / [b] / [c] / [d]
```

**[b] SDD 포맷 변환 규칙**

각 외부 파일을 우리 SDD 형식으로 변환:

| 원본 | 변환 후 | 변환 방식 |
|---|---|---|
| `<src>/specs/<name>.md` | `.ax/docs/spec/NNN-<name>/spec.md` | 원본을 spec.md template `## Specification` 섹션 본문으로. frontmatter (status, source) 추가 |
| `<src>/policies/<name>.md` | `.ax/docs/spec/NNN-<name>/policy.md` 또는 spec.md `## Policy` 섹션 | 정책 카테고리로 wrap |
| `<src>/adr/<name>.md` | `.ax/docs/adr/NNNN-<name>.md` | ADR 다음 번호로 재할당. `imported_from:` frontmatter |
| `<src>/docs/<name>.md` | `.ax/docs/spec/NNN-<name>/research.md` | 배경 문서로 |
| 원본 전체 | `.ax/docs/spec/imported/<name>/` snapshot | re-sync용 보관 |

각 변환 파일 frontmatter 명시:
```yaml
---
imported_from: ../<src>/specs/<name>.md
imported_at: 2026-05-02
status: imported # draft / accepted / superseded 로 사용자가 갱신
---
```

`.snapshot-meta`에 원본 파일별 SHA256 기록 → 다음 onboarding/audit 시 외부 변경 감지.

### Q5. Layer 1-3 활성화 (핵심)

> "도구가 깔린 것"과 "4계층이 작동하는 것"은 달라요.
> Q1~Q4는 자산을 *준비*했고, Q5가 그걸 *활성화*해요.

```
[Q5/5] 4계층 활성화        (이전: Q1=a, Q2=a, Q3=a, Q4=b)

│  📍 발견
│   Q1=a → adoption-plan.md 생성됨, 룰 11개 분류 제안 대기
│   Q2~Q4 완료 → .ax/config.yml, .ax/docs/spec/ 채워짐
│   root CLAUDE.md는 아직 시그널 라벨 없음 (Layer 1 비활성)
│   ADR 0개 (Layer 3은 template만)
│   ※ Layer 2 (.ax/modules/<name>/rules.md): Q2에서 매핑한 L2/L3 도메인 모듈만 stub 자동 생성
│        keywords frontmatter만 채우고 본문은 비워둠 — triage가 grep 매칭으로 자동 참조
│
│  🎯 목표  Layer 1 + Layer 2 + Layer 3 활성화
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  Layer 1 + Layer 3 활성화                       ✓ 권장
│      📂 .ax/spirit/rules/{architecture, data, testing, ops}.md 신설 (4 카테고리)
│      📂 CLAUDE.md prepend (🔴/🟡/🔵 시그널 섹션 + 4계층 인덱스 append)
│      📂 .ax/docs/adr/0001-goax-adoption.md 자동 생성 (Q2~Q4 결정 기록)
│      📂 .ax/modules/<name>/rules.md — Q2에서 매핑한 L2/L3 도메인만 stub
│           (keywords frontmatter는 도메인명+한글 동의어 자동, 본문은 빈 템플릿)
│      ✓  정리: .ax/CLAUDE.md.suggested + .ax/adoption-plan.md 삭제 (적용 완료)
│
│  ○  [b]  Layer 1만 (시그널화 + spirit/rules)
│      📂 위 [a]의 Layer 1 부분만, Layer 3 ADR은 보류
│
│  ○  [c]  보류 — 사용자가 직접 진행
│      후속 안내: "adoption-plan.md 적용 도와줘" / "module CLAUDE.md 만들어줘"
│
└  ▸  답해주세요   [a] / [b] / [c]
```

**[a] 적용 세부**

Layer 1 — CLAUDE.md 시그널화:
1. adoption-plan.md의 `Layer 1 (root)` 섹션 룰을 root CLAUDE.md 상단에 prepend. **다음 5개 블록을 모두 포함**:

 **(a) 헤더 + 룰 토큰 컨벤션 (1줄)**:
 ```
 # <PROJECT_NAME> — Constitution

 > AI 에이전트의 비협상 룰. 룰 토큰: `<scope>:<TIER>:<NNN>` — `.ax/docs/reference/rules-tokens.md` 참조.
 ```

 **(b) META — 핵심 가드레일 (AGENTS.md.template 과 항상 동일 문구)**:
 ```
 ## META — 핵심 가드레일

 - **Triage First** — 새 작업·기능·수정·리팩토링·버그 fix 요청 받자마자 `goax:triage` 1회 호출. **`EnterPlanMode` 진입 전·직후에도 필수** (plan mode 와 triage 는 직교 — 도구 제약이 Skill 호출을 막지 않음). "사용자가 '계획' 단어 썼으니 plan mode 직행" 은 anti-pattern.

 > lean 원칙: 일반 행동 원칙(추측 금지·단순성 우선·요청 범위 준수·검증 후 종료)은 frontier
 > 모델의 기본 행동이라 상시 주입하지 않아요 — 중복 지시는 토큰 낭비 + 과잉 검증 유발.
 > `config.yml` `model_tier: standard`(경량·타사 모델) 프로젝트는
 > `.ax/_templates/spirit/behavioral-baseline.md` 를 복원해요.
 ```

 **(c) 시그널 의미 (항상 동일 문구)**:
 ```
 ## 시그널 의미

 - 🔴 **CRITICAL** *(auto-enforce)* — hooks가 자동 차단. 우회 불가. 룰 옆에 hook 경로 명시.
 - 🟡 **MANDATORY** *(human-in-the-loop)* — 사람 승인 게이트. ADR·리뷰어 동의 필요.
 - 🔵 **CONVENTION** *(human-on-the-loop)* — 권장 가이드. 차단 X. PR 리뷰에서 인용용.
 ```

 **(d) 시그널별 룰 본문 (adoption-plan.md에서 채움)**:
 ```
 ## CRITICAL — 자동 검증 (Sensors가 막는다)

 🔴 **`<scope>:CRITICAL:001`** ... — `<hook 경로>`

 ## MANDATORY — 사람 승인 필요

 🟡 **`<scope>:MANDATORY:001`** ...
 ```

 **(d.1) 프로젝트별 CRITICAL 룰의 hook 등록 시점 — 룰별 사용자 동의**:

 § 2.4.1 가드: CRITICAL 룰은 **막는 hook이 없으면 거짓 약속**. project-specific CRITICAL 룰을 prepend하기 전 사용자에게 hook 작성 시점을 묻기.

 **universal best practice 룰**(secrets, 파괴 명령, 보호 경로)은 이미 `templates/default/.ax/hooks/`에 사전 등록 — 이 단계에서 묻지 않아요. 사용자 정의 CRITICAL 룰만 묻기.

 ```
 ◆  새 CRITICAL 룰 N개 — hook 등록 시점

 │  📍 발견  사용자 정의 CRITICAL 룰 N개 (universal hooks 외)
 │            예: COMMERCE:CRITICAL:001 DDL V타임스탬프
 │
 │  🎯 목표  거짓 약속 차단 — CRITICAL은 막는 hook이 있어야 진짜 CRITICAL
 │
 ├─ 옵션 (룰마다 개별 선택 가능) ───────────────────────────
 │
 │  ●  [a]  지금 hook 작성                                  ✓ 권장 (검증된 패턴)
 │      📂 .ax/hooks/pre-commit/<rule>-grep.sh 또는
 │           critical-rule-grep.sh에 패턴 추가 (LLM이 작성, 사용자 검토)
 │      ✓  enforced_by 채워짐, CRITICAL 진짜 효력
 │
 │  ○  [b]  나중에 — 🟡 MANDATORY 로 깔고 enforced_by: TODO:<deadline>   ✓ CRITICAL 보다 권장
 │      📂 라벨을 🟡 MANDATORY 로 시작. CLAUDE.md 에 enforced_by: TODO:YYYY-MM-DD
 │            (사용자 입력 — 기본 +4w = absolute date 로 즉시 변환, I2)
 │      📋 ADR 0001 에 checklist 추가:
 │            "- [ ] <YYYY-MM-DD> hook <name> 작성 또는 강등 (룰 ID: <scope>:MANDATORY:NNN)"
 │      ✓  거짓 약속 차단 (🔴 + TODO 는 I1 위반). 작성 후 🔴 승급이 정직.
 │      ⚠  doctor 가 매 호출마다 deadline 추적. 임박/초과 시 다음 단계 옵션 제시.
 │
 │  ○  [c]  CRITICAL 포기 — MANDATORY 또는 CONVENTION으로 강등
 │      📂 시그널만 바꿔서 prepend (사람 게이트로 충분)
 │      ✓  거짓 약속 없음, 솔직한 분류
 │
 │  ○  [d]  이 룰 자체를 보류 — adoption-plan.md에 keep, prepend X
 │
 └  ▸  답해주세요   [a/b/c/d] (룰마다 개별)
 ```

 **[a] 지금 작성 흐름**:
 1. 룰 패턴 이름·grep regex 사용자에게 받음 (예: "DDL은 V숫자__이름.sql")
 2. LLM이 `.ax/hooks/pre-commit/critical-rule-grep.sh`의 패턴 배열에 추가 또는 룰별 sensor 파일 신설
 3. 작성 후 사용자에게 diff 보여주고 적용 동의

 **[b] 나중 흐름** (deadline 강제 + ADR checklist):
 1. **deadline 입력 받기**: "언제까지 작성? (기본 +4w = `<absolute date YYYY-MM-DD>`)"
    - 상대 형식(`+Nw`/`+Nd`) 입력 받으면 onboarding 이 즉시 absolute date 로 변환해서 박음 (I2 — doctor 가 나중에 동적 해석하지 않음)
 2. **라벨 강제 강등**: 사용자 의도가 🔴 였어도 hook 미작성이면 🟡 MANDATORY 로 박음 (I1 위반 차단). 사용자가 🔴 고집하면 ADR 에 거짓 약속 인지 섹션 자동 생성 — `## 거짓 약속 위험 인지` + 강등 트리거 명시.
 3. **CLAUDE.md inline 형식**:
    ```
    🟡 **`<scope>:MANDATORY:NNN`** *(deferred — hook 작성 전까지 임시)*
    - enforced_by: TODO:<absolute-YYYY-MM-DD>
    - enforced_kind: missing
    - 해야 할 일: `.ax/hooks/pre-commit/<name>.sh` 작성 후 🔴 승급
    ```
 4. **ADR 0001 checklist 항목 자동 추가**:
    ```markdown
    ## 4주 후 점검 checklist (자동 생성 — onboarding)
    - [ ] <YYYY-MM-DD> hook <name>.sh 작성 또는 룰 강등 (<scope>:MANDATORY:NNN)
    ```
    doctor 가 ADR 의 `- [ ]` 라인을 grep + deadline 비교 → 임박/초과 보고.
 5. **`.ax/mistakes/auto-todo-hooks.md`** 존재할 때만 함께 갱신 — doctor 는 ADR checklist 를 우선 참조.

 **[c] 강등 흐름**:
 - 시그널을 🟡 또는 🔵로 변경해서 prepend
 - ADR 0001에 "ArchUnit 등 자동화 미도입 → MANDATORY로 분류" 명시

 **(e) CONVENTION 처리 — 사용자에게 옵션 제시**:
 ```
 ◆  CONVENTION 처리 방식
 │
 │  📍 spirit/rules에 4개 카테고리(architecture/data/testing/ops) 생성됨
 │  🎯 root CLAUDE.md에서 어떻게 참조할지
 │
 ├─ 옵션 ────────────────────────────────────────────────
 │
 │  ●  [a]  @import — Claude Code 자동 로드                ✓ 권장
 │      📂 ## CONVENTION 섹션에:
 │           @.ax/spirit/rules/architecture.md
 │           @.ax/spirit/rules/data.md
 │           @.ax/spirit/rules/testing.md
 │           @.ax/spirit/rules/ops.md
 │      ✓  변경 시 자동 반영, root는 한 줄씩만 (상대경로는 CLAUDE.md 기준 해석, 최대 5 hop 재귀)
 │      ⚠  *external* import (프로젝트 외부 경로, 예: `@~/.claude/foo.md`)는 첫 실행 시
 │           approval dialog가 한 번 뜸 → 'allow' 권장. 위 4개 라인은 모두 프로젝트 내부
 │           상대경로라 dialog 대상 아님. 거절 시 imports 비활성 유지 + dialog 재출현 X —
 │           공식 문서에 documented된 자동 복구 메서드 없음. 'allow' 선택을 권장.
 │           (정적 경로 차단이 필요하면 `.claude/settings.json` 의 `permissions.deny`도 별도 옵션 — 예: `"deny": ["Edit(./.ax/config.yml)"]`)
 │
 │  ○  [b]  핵심 3-5개를 인라인 ID로 부여
 │      📂 🔵 **`<scope>:CONVENTION:001`** ... 형식
 │      ✓  PR 리뷰에서 인용 편함, grep 가능
 │
 │  ○  [c]  링크 한 줄만 (참조만)
 │      ⚠  검색 불가, ID 인용 불가 — 비권장
 │
 └  ▸  답해주세요   [a] / [b] / [c]
 ```
 → 선택 결과를 ## CONVENTION 섹션에 반영.

2. 기존 CLAUDE.md 본문은 보존 (`---`로 구분)

2.5. **중복 룰 제거 (필수)** — 신 시그널 블록과 구 본문이 같은 룰을 두 번 말하면 drift 시한폭탄. prepend 직후 자동 스캔:

 **자동 감지 매칭** — 신 룰의 핵심 키워드를 추출해 구 본문에서 grep:
 ```
 신: 🔴 COMMERCE:CRITICAL:001 DDL SQL ... V{UTC타임스탬프}__<설명>.sql
 키워드: ["V{UTC타임스탬프}", "db/migration"]
 → 구 본문 hit: ## Database Schema 변경 → "파일명 규칙: V{UTC타임스탬프}__..."
 ```

 **사용자 확인 박스** (clack 스타일):
 ```
 ◆  중복 감지   N개 룰이 두 곳에 등장
 │
 │  📍 발견
 │   COMMERCE:CRITICAL:001 ↔ ## Database Schema 변경 (정확 일치)
 │   COMMERCE:MANDATORY:002 ↔ ## Development Patterns "Kotest DescribeSpec + MockK" (정확 일치)
 │   COMMERCE:MANDATORY:003 ↔ ## Development Patterns "@Tags("Integration")" (정확 일치)
 │
 │  🎯 목표  drift 방지 — 한 룰 = 한 곳
 │
 ├─ 옵션 ────────────────────────────────────────────────
 │
 │  ●  [a]  정확 일치만 자동 삭제                         ✓ 권장
 │      📂 CLAUDE.md (구 섹션 3개 줄 삭제, 신 시그널 블록만 남김)
 │      ✓  부분 일치는 사용자 확인 후 처리
 │
 │  ○  [b]  하나씩 보면서 결정
 │      각 중복마다 [keep구/keep신/keep양쪽] 선택
 │
 │  ○  [c]  손대지 않음 — 사용자가 나중에 수동 정리
 │      ⚠  drift 위험 명시
 │
 └  ▸  답해주세요   [a] / [b] / [c]
 ```

 **자동 삭제 규칙**:
 - 정확 일치(룰 텍스트 ⊇ 구 본문 줄, normalize 후) → [a]에서 자동 삭제
 - 부분 일치(의미 겹침, 표현 다름) → 항상 사용자 확인 (예: 신 룰에 "수정 금지" 추가, 구 본문은 안 함)
 - "Database Schema 변경" 같은 H2 섹션 전체 삭제는 사용자 확인 필수 — 본문에 다른 컨텍스트(예: 적용 절차)가 있을 수 있어요

 ⚠ **반드시 박스를 출력하고 사용자 답을 기다린 뒤에 적용할 것.** "정확 일치만 자동 삭제"는
 사용자가 [a]를 *고른 다음에만* 실행됨. prepend·중복정리를 한 번에 묶어서 사후 보고하는
 형태(예: "정확 일치 N건 자동 통합했어요")는 결정 게이트를 건너뛰는 것 — 금지.
 보호경로 hook 트리거 비용·중복 step 회피는 **결정 우회의 정당화 사유가 아니다**.

3. 끝부분에 4계층 인덱스 append (`.ax/CLAUDE.md.suggested`의 표)
4. adoption-plan의 `Spirit rules` → `.ax/spirit/rules/{architecture,data,testing,ops}.md` 생성
5. 각 파일 frontmatter:
 ```yaml
 ---
 category: architecture
 description: 모듈 의존 방향, 레이어 분리 룰
 # paths: (선택) — 특정 경로에서만 자동 로드되는 path-scoped 룰의 경우 선언.
 # 빈 배열 또는 생략 시 universal — CLAUDE.md @import으로 모든 작업에 적용.
 # paths:
 #   - "**/domain/**"
 #   - "**/*Entity*.kt"
 ---
 ```

 > **path-scoped 룰**: 위 frontmatter의 `paths:`를 채우면, `.ax/hooks/pre-edit/spirit-rules-inject.sh` (`.claude/settings.json`에 PreToolUse 로 등록됨) 가 **해당 path 작업 시에만** 룰을 additionalContext로 안내해요. universal 룰(ops/architecture/data/testing 류)은 paths 생략 — CLAUDE.md @import으로 매 turn 주입. 도메인·레이어 특화 룰(예: <project>-domain, <project>-presenter)은 paths를 채워 token cost·adherence 둘 다 개선.

Layer 2 — 모듈 도메인 룰 stub 생성 (`.ax/modules/<name>/rules.md`):

5.5. Q2의 도메인 위험도 매핑에서 **L2/L3 위험도 도메인이면서 모듈로 식별된 항목**만 자동 stub. L0/L1 도메인은 stub 생성 X (모노레포 noise 방지).

 - 디렉토리: `.ax/modules/<module-name>/`
 - 파일: `.ax/_templates/module/rules.md` cp 후 frontmatter만 채움 (본문은 비워둠)
   ```yaml
   ---
   module: payment
   keywords: [payment, refund, settlement, 결제, 환불, 정산]   # Q2 매핑 + 한글 동의어
   applies_to: [code, pr, review]
   ---
   ```
 - 본문은 사용자가 후속에 채우거나, `audit`이 mistakes N회 반복 카테고리를 자동 promote
 - **사용자에게 보고**: "L3/L2 도메인 N개에 stub 만들었어요. 룰은 비어있고 keywords만 채웠으니 triage가 매칭은 가능. 본문은 필요할 때 채우세요."

> Layer 2 *자동 stub* 정책: **L2/L3 모듈 위험도면 stub, L0/L1은 X**. 사용자가 L0/L1에도 룰 필요하면 `.ax/_templates/module/rules.md`를 cp해서 직접 추가. triage는 매 작업 진입 시 `.ax/modules/*/rules.md`의 `keywords:` frontmatter를 grep해 사용자 메시지와 매칭, 매칭 모듈 룰을 *Required reading*으로 자동 첨부.

Layer 3 — 첫 ADR (0000-template.md 사용 — `adr`와 동일 양식):

6. `.ax/docs/adr/0001-goax-adoption.md` 자동 작성:
 ```bash
 cp .ax/_templates/adr/0000-template.md .ax/docs/adr/0001-goax-adoption.md
 ```
 템플릿 구조 그대로 두고 메타·본문만 채움:
 - **메타**: ADR ID=0001, 작성일=오늘, 상태=승인, 관련 spec=(없음)
 - **컨텍스트**: 도입 이유 — 코드 품질 일관성·반복 실수 차단·AI 결과 일관성
 - **검토된 대안**: A. 도입 안 함 / B. PRD-first / C. 4-Layer 하네스 (채택)
 - **결정**: 4계층 + Cross-cut 채택, hooks=warning(Q3 결과), domain_risk=Q2 매핑, 외부 spec=Q4 결과
 - **결과**:
  - 단기: spirit 자동 주입, triage 게이팅
  - 장기: mistakes loop으로 룰 진화, ADR 누적
  - 후속: 1주 후 doctor + audit 검토, 2주 후 룰 승격 시도
  - 측정: 메트릭=mistakes 발생률, 임계치=주 5건↓, 검토=1개월
 - **변경 이력**: 오늘 초안+승인

정리:
7. `.ax/CLAUDE.md.suggested` 삭제 (root에 흡수됨)
8. `.ax/adoption-plan.md` 삭제 (적용 완료)
9. `.ax/.onboarding-pending` 삭제 (마커 정리)

State 초기화 (HUD용):
10. `.ax/hud/state.json.template`을 `.ax/state.json`로 cp
11. `doctor` 한 번 실행해 canonical 갱신 (Layer 활성도, mistakes 수 등)
12. `.ax/current-task.json`은 up 이 이미 깔아놨음. 첫 triage가 이 파일에 작업 컨텍스트를 채워요. `.ax/scripts/bash/`도 up 이 복사함 (결정론 스크립트 일체)

statusline 활성 제안 (Sub-Q4 — **항상 박스를 출력하고 답을 받을 것**):
14. 기존 `.claude/settings.json` 의 statusLine 상태를 먼저 검사하고, 그 결과를 박스에 표시한 뒤 사용자가 명시적으로 닫게 함. **이미 활성이라고 임의 skip 금지** — 사용자는 무엇이 결정됐는지 알 권리가 있다.
 ```
 🪝 Sub-Q4: statusline (HUD) 활성?
 매 응답 위에 4계층 활성도·도메인·위험도가 한 줄로 표시돼요.

 (현재 상태: <검사 결과로 채움 — 예: "없음" / ".ax/hud/statusline.sh 가리키는 중" / "다른 도구 (omc/...)">)

 [a] ✓ 활성화         [기존 statusLine 없을 때 권장]
   수정 .claude/settings.json
   결과 triage: M×L3 | harness: 🌟 | ☄2

 [b] ⚠ 합치기 — 기존 statusLine과 둘 다
   다른 도구(omc 등)가 이미 statusLine을 점유하고 있을 때 권장

 [c] 이미 .ax/hud/statusline.sh 가리키는 중 — 변경 없이 ✓
   skip이 아니라 *명시적으로 OK 받고 닫는* 옵션

 [d] 나중에 — /hud setup 으로 활성화
 ```
 → 답이 [a]/[b]면 hud skill 위임. [c]/[d]면 변경 없이 ✓ 보고만.

statusline 활성 제안 (Sub-Q5 — `.ax/settings.json.suggested` 머지):

15. up 이 기존 `.claude/settings.json` 발견 시 만든 `.ax/settings.json.suggested` 가 있으면, 사용자에게 머지 여부를 명시적으로 묻기. **Sub-Q5는 SKILL.md 정식 step** — 임기응변 X.
 ```
 🔧 Sub-Q5: hooks 등록 — .ax/settings.json.suggested 머지?
 up 이 기존 .claude/settings.json 보존 + suggested 만들었어요.
 hooks (UserPromptSubmit, PreToolUse:Bash, PreToolUse:Edit, PostToolUse:Edit) 머지해야
 triage-nudge·block-destructive·spirit-check·protected-paths 등 sensors 작동.

 (현재 상태: <suggested 존재 — 머지 필요> / <이미 머지됨 — 변경 불필요>)

 [a] ✓ 머지 — 기존 settings.json + suggested              [권장]
   명령 jq -s '.[0] * .[1]' .claude/settings.json .ax/settings.json.suggested \
        > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
   결과 hooks 등록 + suggested 삭제

 [b] 보류 — 사용자가 나중에 수동 머지
   ⚠ 머지 안 하면 hooks 등록 안 됨 — sensors 작동 X
 ```
 → [a] 시 jq merge + `rm -f .ax/settings.json.suggested` 정리.
 → [b] 시 suggested 그대로 두고 사용자에게 다음 단계 안내.

## 4. 적용

사용자가 [a]/[b]/[c]/[d] 응답하면 실제 파일을 수정해요. **각 단계를 ✓로 보고**:

```
✓ Q1 — .ax/adoption-plan.md 생성 (96줄). CLAUDE.md는 그대로.
✓ Q2 — .ax/config.yml domain_risk 30 keys + default L1
✓ Q3 — .ax/config.yml sensors.mode = warning
✓ Q4 — .ax/docs/spec/ 4개 SDD 변환 + adr/ 3개 재번호 + imported/<name>/ snapshot
✓ Q5 — Layer 1 시그널화 (CLAUDE.md 8개 룰, spirit/rules 4 카테고리)
  Layer 2 stub (.ax/modules/<L2/L3 도메인>/rules.md — keywords frontmatter만)
  Layer 3 ADR 0001 작성
  정리 (suggested·adoption-plan·marker 삭제)
```

⚠ **카운트 검증 — 사용자에게 보고하는 숫자는 grep raw count가 아니라 의미 단위 count**:
- 시그널 카운트: `🔴 N` 식의 표기는 **legend(범례) 라인 제외, 실제 룰 라인만** 카운트.
  올바른 메서드: `grep -E '^🔴|^🟡|^🔵' CLAUDE.md` 가 아니라
  `grep -E 'COMMERCE:(CRITICAL|MANDATORY|CONVENTION):[0-9]+' CLAUDE.md | sort -u | wc -l` 같이 **유니크 룰 토큰** 기준.
- domain_risk key 카운트: 인덴트 `-` prefix 라인이 아니라 **실제 키 라인 수**(주석/구분자 제외):
  `awk '/^domain_risk:/{found=1;next} found && /^[^[:space:]]/{exit} found' .ax/config.yml | grep -E '^[[:space:]]+[a-z][a-z0-9_-]*:' | wc -l`
  (구 패턴 `awk '/start/,/end/'` 는 domain_risk: 자체가 end에도 매칭돼 첫 줄에서 collapse — count=0 버그)
- 룰 토큰 카운트: 출현 횟수(occurrences)와 유니크 ID 개수를 헷갈리지 않기. "토큰 N개"는 *unique* 가 정상 의미.

이 검증을 하지 않으면 사용자에게 보고하는 숫자가 raw grep 노이즈를 포함해 신뢰가 깎인다.

## 5. 마무리 — 마커 정리 + Spec 디렉토리 안내

onboarding이 끝나면 **마커만 삭제**해요. plugin skill 자체는 plugin 설치 디렉토리에 있어 사용자 프로젝트에서 자가 삭제 불가능 — 마커로만 "완료" 신호를 표시해요. 다음 세션에서 onboarding이 다시 자동 발동되지 않도록.

```bash
# 마커 삭제
rm -f .ax/.onboarding-pending
```

그 다음, 사용자에게 spec 디렉토리 두 위치의 역할 차이를 정확히 안내해요. **`_templates/spec/`을 "프로젝트 SSOT"로 부르지 말 것** — 작업 spec SSOT는 `.ax/docs/spec/NNN-<slug>/spec.md`. `_templates/`는 이름 그대로 *템플릿*. 두 개념을 혼동시키면 사용자가 spec을 templates 디렉토리에 직접 쓰는 워크플로 misroute가 발생함.

```
🥳 onboarding 완료. .ax/.onboarding-pending 마커 정리했어요.

📐 Spec 디렉토리 구조
 .ax/docs/spec/NNN-<slug>/  ← 작업 spec SSOT (spec-new가 여기에 생성)
                              spec.md / tasks.md 인스턴스 (full tier 면 + research/data-model/...)

 .ax/_templates/spec/  ← 템플릿 (도메인에 맞게 수정 가능, doctor가 drift 감지)

📂 .ax/ runtime 파일은 .gitignore 자동 처리됨
 .ax/state.json, .ax/current-task.json — per-machine 상태, PR에 들어가지 않음
 → 누락 entry가 있으면 doctor가 안내해요.

📋 Mistake Loop — 주 1회 audit 권장
 실수는 "실수 기록해줘" 로 사용자가 의도적으로 캡처해요 (.ax/mistakes/), audit_cadence_days=7 (config.yml)에 따라 주기적 회고 필요
 수동 호출: "goax audit"
 자동화 옵션: Claude Routine 등록 → fresh clone에서 weekly로 promote-mistake.sh 실행 → 후보 PR 생성
 HUD ☄ 마커가 누적된 mistakes 카운트 표시

다음 한 줄을 시도해보세요:

 "결제 환불 정책 변경 작업 계획 세워줘"
 → triage → spec 게이팅 (L3) → spirit·룰·페르소나 자동 주입
```

## 절대 금지

- 추측만으로 `domain_risk`나 위험도를 박아넣지 않아요. 모르면 사용자에게 물어요.
- bash 휴리스틱이 추정한 값을 **검증 없이** 그대로 쓰지 않아요. 한 번씩 코드를 직접 보고 확인해요.
- 한 번에 4 가지를 다 묻지 않아요. 한 결정씩, 사용자 답을 받고 다음으로 진행.
- **plugin shipped hook 파일을 직접 수정하지 않아요.** 프로젝트별 CRITICAL 룰의 `enforced_by` hook은 *반드시 새 파일*로 추가해요 — `.ax/hooks/pre-commit/<project>-<rule>.sh` 같이. `pre-bash/grep-on-commit.sh`가 `pre-commit/*.sh` 를 자동 chain하므로 새 파일은 즉시 picked up. 이유: plugin 갱신 시 shipped 파일은 출고본으로 회귀하므로 직접 수정한 패턴이 silently clobber됨. (예외: plugin 자체 버그 fix는 이 plugin source repo에 PR로.)

  **신규 project hook 작성 6가지 가드** — 아래 코드 블록을 *그대로 카피-페이스트* 해서 시작:

  ```bash
  #!/usr/bin/env bash
  # [project-specific] Generated by goax onboarding — not a shipped plugin artifact   ← Guard #1 헤더 마커
  # <PROJECT>:CRITICAL:NNN — <룰 한 줄 설명>
  set -uo pipefail   # ← Guard #5: -e 없이 (grep no-match가 hook 본체 abort하는 trap 회피)

  # Bootstrap guard — up 호출 중간이거나 .ax/ 부분 정리 시 silent skip
  [ -d "${CLAUDE_PROJECT_DIR:-$(pwd)}/.ax/hooks" ] || exit 0

  PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  COMMON="$PROJECT_ROOT/.ax/scripts/bash/common.sh"

  SENSOR_MODE="warning"
  [ -f "$COMMON" ] && { source "$COMMON"; SENSOR_MODE=$(goax_mode 2>/dev/null || echo warning); }
  [ "$SENSOR_MODE" = "off" ] && exit 0

  STAGED=$(git diff --cached --name-only 2>/dev/null || true)
  [ -z "$STAGED" ] && exit 0

  VIOLATIONS=0
  while IFS= read -r f; do
      [ -z "$f" ] || [ ! -f "$f" ] && continue

      # ── Guard #2: annotation class 화이트리스트 (Spring 테스트 검증류용) ──
      case "$f" in
          *test/context/*|*test/*/base/*|*test/*/support/*) continue ;;
      esac

      # ── 룰 본문 ── 예: Kotlin 테스트의 JUnit5 import 검출
      if [[ "$f" == *.kt ]] && [[ "$f" == *src/test/* ]]; then
          # Guard #3: import static 옵션 modifier 처리 — Assertions.assertEquals 같이 흔한 static import 형태 모두 catch
          if grep -qE '^import[[:space:]]+(static[[:space:]]+)?org\.junit\.jupiter\.' "$f" 2>/dev/null; then
              echo "  ⚠ $f: JUnit5 import 금지 — Kotest DescribeSpec 사용" >&2
              VIOLATIONS=$((VIOLATIONS + 1))
          fi
      fi
  done <<< "$STAGED"

  if [ "$VIOLATIONS" -gt 0 ]; then
      [ "$SENSOR_MODE" = "fail" ] && exit 2
      echo "[goax] ⚠ $VIOLATIONS 위반 — 경고만 (mode=$SENSOR_MODE)" >&2
  fi
  exit 0
  ```

  5가지 가드 점검 (위 코드에 모두 박혀 있음):
  1. **헤더 마커** (line 2) — `# [project-specific]` 주석. drift 감지가 plugin 출고본과 헷갈리지 않게.
  2. **annotation class 화이트리스트** — `case "$f" in *test/context/*) continue ;; esac` 로 메타 어노테이션 정의 디렉토리 skip. 안 그러면 `annotation class CommerceMySqlDataJpaTest`가 false-positive.
  3. **`import static` 처리** — `^import[[:space:]]+(static[[:space:]]+)?org\.junit\.jupiter\.` regex. `Assertions.assertEquals` 같이 static import 로 들어오는 가장 흔한 형태도 catch.
  4. **`set -uo pipefail` (no `-e`)** — `grep -qE` 가 no-match로 exit 1 리턴할 때 `set -e`가 hook 본체를 silent abort 하는 trap 회피. plugin shipped hooks도 동일 컨벤션.
  5. **plugin shipped 파일 append 금지** — `ops.md` 같은 출고본에 사용자 프로젝트 룰 append X. 별도 파일(`.ax/spirit/rules/<project>-<category>.md`)로 만들고 root CLAUDE.md의 CONVENTION 섹션에 `@.ax/spirit/rules/<project>-<category>.md` import. plugin 갱신 시 clobber 방지.

  > Mistake 기록은 hook 자동 capture 가 아니라 사용자 명시 `mistake` skill 호출로만. hook 은 차단/경고만, 위반 패턴 기록은 사용자 의도적 capture.

- **CONVENTION 형식은 한 가지로 통일.** 두 가지 옵션 중 하나 선택:
  - (a) **인라인 정의**: root CLAUDE.md에 `🔵 **\`<scope>:CONVENTION:NNN\`** ...` 형태로 박음 → grep/citation 용이, `update-state.sh`의 `^🔵 \*\*` 패턴이 카운트
  - (b) **@import 위임**: `.ax/spirit/rules/<category>.md` 에 `SP-<CAT>-NNN` 형식으로 박고 root에 `@.ax/spirit/rules/<category>.md` 한 줄 — 본문 분리, 카테고리별 관리
  두 형태 혼합 금지 — body에 `(\`<scope>:CONVENTION:001\`)` 식 인용은 `🔵 **` 정의가 아니라 단순 참조라 카운트에 안 잡혀 사용자에게 헷갈림. 정의는 한 자리에만.
- **카운트는 pre-emit으로 검증.** "N 키", "M개 룰" 식의 박스 표시는 awk/grep으로 실측한 값을 박은 후 박스를 출력. 사후 정정 형태 금지 — Q2 가이드 참고.

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- 전체 (Q5 마지막 단계에서 doctor 호출)

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
# canonical 갱신 — Q5 [a] 후 layer.active 등 모두 derived
bash .ax/scripts/bash/update-state.sh

# 메타데이터만
jq '.last_skill = "onboarding" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
