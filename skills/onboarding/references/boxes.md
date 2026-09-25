# onboarding — 박스 전문 (clack 스타일)

> SKILL.md 는 흐름과 결정만 담아요. 사용자에게 실제로 보여줄 박스 원문은 여기예요.
> 읽는 시점: 해당 Q 를 출력하기 직전에 그 절만.

## 0. 표준 박스 + 답 처리

모든 질문·확정 박스는 이 한 모양이에요. 박스마다 모양이 다르면 사용자가 어디를 봐야 할지 매번 다시 찾아요.

핵심 글리프(이모지 아님): `◆`(헤더) `│`(좌측 bar) `├─ ─`(섹션) `└`(끝) `●/○`(권장 옵션/나머지) `▸`(입력 마커).
이모지는 `.ax/spirit/tone.md` §표시 기호 어휘만 써요 — 줄머리 표지 `📍 발견` `🎯 목표` `📂 영향` `👉 다음`,
상태 `✅ 권장·보존·완료` `❗ 위험·주의` `❌ 비권장` `⛔ 되돌릴 수 없음`. 그 밖의 그림 이모지는 붙이지 않아요.

```
◆  Q<N>/5   <짧은 제목>                          · <이전 답 요약 (Q2부터)>
│
│  📍 발견  <사실 1~3줄, 추측 X>
│
│  🎯 목표  <의도 1~2줄>
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  <한 줄 요약>                                  ✅ 권장
│      📂 <영향 — 예: ".ax/file.md 신규 (96줄)">
│      ❗ <위험·단점 — 있을 때만>
│
│  ○  [b]  <옵션>
│      📂 <영향>
│
│  ○  [c]  <보류·skip>
│
└  ▸  답해주세요   [a] / [b] / [c]
```

**시그널 라벨 설명 (Q1 에서 한 번만)** — 🔴🟡🔵 는 룰 시그널 전용이에요. 상태 표시에 섞지 않아요.
```
시그널 의미:
 🔴 CRITICAL 자동 차단 — hooks가 막아요. 우회 불가.
 🟡 MANDATORY 사람 게이트 — 명시적 승인 필요.
 🔵 CONVENTION 가이드 — 권장이지만 차단은 안 함.
```

**답 처리 3단계**:
1. 행동 직전 안전 재확인 (한 줄): `<선택> 진행할게요. <안 건드리는 것> 그대로 두고 <할 것>.`
2. 실제 작업 (Write/Edit/Bash)
3. 확정 박스:
```
◆  Q<N> 완료   <한 줄 요약>
│  📂 <생성·수정 파일>
│  ✅ <보존된 것>
└  👉 다음: <다음 단계 안내>
```

## 큰 프로젝트 — 도메인 후보 박스 (§2.2)

```
◆  도메인 후보 N개   큰 프로젝트 — 의미 있는 것만 추렸어요
│
│  📍 분류 제안 (L3/L2/L1)
│     L3 돈/PG  payment, settlement, billing, balance
│     L2 자산   order, coupon, reward, cart, delivery, auth, session
│     L1 일반   catalog, product, store, search, notification, ad
│
│  제외한 것 — 이유
│     ad/ba/cs (짧은 prefix, 모호)
│     adapter/aggregator/gateway (기술 슬라이스, 도메인 X)
│     common/util/core (일반 명사)
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  이대로 매핑 (default: L1)                     ✅ 권장
│  ○  [b]  추가 도메인 매핑 — 어떤 거?
│  ○  [c]  제외 항목 일부 다시 포함
│
└  ▸  답해주세요   [a] / [b] / [c]
```

## Q1. Constitution (AGENTS.md / CLAUDE.md) 처리

```
◆  Q1/5   Constitution 룰 처리   (AGENTS.md SSOT)
│
│  📍 발견
│   CLI 환경: <claude | opencode | both | unknown> (§2.6 자동 감지)
│   기존 CLAUDE.md 룰 N개 — 카테고리 정리됨, 시그널 라벨 없음
│   AGENTS.md: <존재 / 부재>
│   "비협상"(예: 모듈 의존) + "권장"(예: 테스트 컨벤션)이 한 파일에 섞임
│
│  Constitution SSOT 정책
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
│  ●  [a]  자동 분류                                       ✅ 권장
│      📂 .ax/adoption-plan.md 신규 (라벨 제안 + 카테고리 매핑표)
│      ✅ CLAUDE.md 그대로 — 검토 후 사용자가 수동 적용
│
│  ○  [b]  가이드만
│      📂 없음 — 채팅에 분류표만 출력
│
│  ○  [c]  보류 — Q2로 건너뛰기
│
└  ▸  답해주세요   [a] / [b] / [c]
```

## Q2. 도메인 위험도

박스의 숫자(L3=N …)는 `zero-domain-risk.sh --show --json` 실측값이에요. 추정치 금지.

```
◆  Q2/5   도메인 위험도 매핑                       · Q1=a
│
│  📍 발견  도메인 N개 식별 (<project> 패키지 기준)
│            >15개면 핵심만 매핑 + default L1 정책 권장
│
│  🎯 목표  .ax/config.yml 의 domain_risk 채우기
│            → triage 가 작업 진입 시 도메인 키워드로 위험도 자동 결정
│
│  레벨 기준
│   L3 돈/PG 직접 흐름       payment, settlement, billing, balance
│   L2 사용자 자산·권한 영향 order, auth, session, coupon, reward
│   L1 일반 도메인           catalog, product, search, notification
│   L0 문서·내부·관측        docs, monitoring, internal-tools
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  다음 매핑으로 기록                            ✅ 권장
│      L3: payment, settlement
│      L2: order, coupon, delivery, shipment, cart
│      L1: catalog, product, store, review, search, ad, notification
│      L0: experiment, featureflag, log
│      default: L1 (매핑 안 한 도메인은 L1로 처리)
│
│      근거 (왜 이 레벨인가)
│       · settlement L3 — 셀러 정산 → 환불·차감 발생, 결제와 동급
│       · coupon L2 — 포인트성 자산, 결제 트랜잭션 안에서 동작 (L3 승급 여지)
│       · delivery vs shipment — 배송 상태 / 출고 분리. 둘 다 L2
│       · subscription/discount default(L1) — 의견 따라 L2 승급 검토
│
│      📂 .ax/config.yml (domain_risk 섹션 + default) 수정 · 생성 없음
│      ❗ 키 작성 규칙 (필수)
│         - 키는 영문 kebab-case만 (예: payment, store-profile)
│         - 한글은 주석으로만 (예: payment: L3 # 결제, PG, 환불)
│         - 같은 도메인을 영문/한글 별도 키로 두지 않음 (중복 금지)
│         - triage 가 사용자 메시지의 한글을 영문 키로 의역해서 매칭함
│
│  ○  [b]  수정·교체 후 [a] 적용
│      어떤 도메인을 어느 레벨로 옮길지 알려주세요
│      (예: "delivery는 L2 그대로 좋아요. ad는 L0로 내려주세요")
│
│  ○  [c]  비워두기 — 나중에 .ax/config.yml 직접 채우기
│
└  ▸  답해주세요   [a] / [b] (수정 내용 같이) / [c]
```

## Q3. hooks 강도

```
◆  Q3/5   hooks 강도                                · Q1=a · Q2=a
│
│  📍 발견  기존 활성 hooks: <name> (또는 없음)
│
│  🎯 목표  goax hooks 가 위반을 어떻게 다룰지 → .ax/config.yml 의 sensors.mode
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  warning — 메시지만, 작업 차단 X               ✅ 권장 (안전)
│      팀이 룰을 학습하는 동안 친절하게
│      📂 .ax/config.yml (sensors.mode = warning)
│      ❗ 사실 확인 게이트 셋(룰 미독 편집 · 파괴 명령 · 훅 우회)은 warning 에서도 막아요 — 통과가 싸서예요
│
│  ○  [b]  fail — CRITICAL 위반 시 즉시 차단
│      룰이 안정화된 팀에 적합
│      📂 .ax/config.yml (sensors.mode = fail)
│
│  ○  [c]  비활성 — hooks 등록 자체 안 함
│      📂 .claude/settings.json → settings.json.disabled
│      ❌ 비권장 — 파괴 명령·시크릿 차단까지 꺼져요
│
└  ▸  답해주세요   [a] / [b] / [c]
```

## Q4. 외부 spec (있을 때만)

```
◆  Q4/5   외부 spec 처리                            · Q1=a · Q2=a · Q3=a
│
│  📍 발견  sibling 디렉토리: <name> (예: <repo>-spec)
│            specs/ N개, policies/ M개, adr/ K개
│
│  🎯 목표  Layer 3 (Spec/ADR) 에서 외부 spec 을 어떻게 다룰지
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  링크만 — 변경 0                               ✅ 권장
│      📂 .ax/docs/external-specs.md (참조 인덱스 한 줄)
│      ✅ 외부 spec 은 그대로 — 팀이 별도 관리, SSOT 단일
│
│  ○  [b]  SDD 포맷 변환 흡수 — 4계층 통합을 원할 때
│      📂 .ax/docs/spec/<id>-<slug>/{spec, plan, ...}.md (SDD 형식)
│         + .ax/docs/spec/imported/<name>/ (원본 snapshot)
│         + .ax/docs/adr/<id>-*.md (외부 ADR 새 ID)
│      ✅ spec-validate · triage 게이팅이 외부 spec 까지 인식, .snapshot-meta 로 diff
│      ❗ 파일 N개 생성. SDD 템플릿 헤더로 wrap, 본문 보존
│
│  ○  [c]  snapshot 만 (raw copy, 변환 X)
│      📂 .ax/docs/spec/imported/<name>/
│
│  ○  [d]  무시 — 손대지 않음
│
└  ▸  답해주세요   [a] / [b] / [c] / [d]
```

변환 규칙은 `references/import-spec.md`.

## Q5. Layer 1-3 활성화

```
◆  Q5/5   4계층 활성화                              · Q1=a · Q2=a · Q3=a · Q4=b

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
│  ●  [a]  Layer 1 + Layer 3 활성화                       ✅ 권장
│      📂 .ax/spirit/rules/{architecture, data, testing, ops}.md 신설 (4 카테고리)
│      📂 CLAUDE.md prepend (🔴/🟡/🔵 시그널 섹션 + 4계층 인덱스 append)
│      📂 .ax/docs/adr/<id>-goax-adoption.md 자동 생성 (Q2~Q4 결정 기록)
│      📂 .ax/modules/<name>/rules.md — Q2에서 매핑한 L2/L3 도메인만 stub
│      ✅ 정리: .ax/CLAUDE.md.suggested + .ax/adoption-plan.md 삭제 (적용 완료)
│
│  ○  [b]  Layer 1만 (시그널화 + spirit/rules)
│      📂 위 [a]의 Layer 1 부분만, Layer 3 ADR은 보류
│
│  ○  [c]  보류 — 사용자가 직접 진행
│      후속 안내: "adoption-plan.md 적용 도와줘" / "module CLAUDE.md 만들어줘"
│
└  ▸  답해주세요   [a] / [b] / [c]
```

## Q5 (d.1) — 사용자 정의 CRITICAL 룰의 hook 등록 시점 (룰마다)

universal 룰(secrets·파괴 명령·보호 경로)은 이미 hook 이 있어 묻지 않아요. 사용자 정의 CRITICAL 만.

```
◆  새 CRITICAL 룰 N개 — hook 등록 시점

│  📍 발견  사용자 정의 CRITICAL 룰 N개 (universal hooks 외)
│            예: COMMERCE:CRITICAL:001 DDL V타임스탬프
│
│  🎯 목표  거짓 약속 차단 — CRITICAL은 막는 hook이 있어야 진짜 CRITICAL
│
├─ 옵션 (룰마다 개별 선택 가능) ───────────────────────────
│
│  ●  [a]  지금 hook 작성                                  ✅ 권장 (검증된 패턴)
│      📂 .ax/hooks/pre-commit/<rule>-grep.sh 또는
│           critical-rule-grep.sh에 패턴 추가 (LLM이 작성, 사용자 검토)
│      ✅ enforced_by 채워짐, CRITICAL 진짜 효력
│
│  ○  [b]  나중에 — 🟡 MANDATORY 로 깔고 enforced_by: TODO:<deadline>   ✅ CRITICAL 보다 권장
│      📂 라벨을 🟡 MANDATORY 로 시작. CLAUDE.md 에 enforced_by: TODO:YYYY-MM-DD
│            (사용자 입력 — 기본 +4w = absolute date 로 즉시 변환, I2)
│      📂 goax 도입 ADR 에 checklist 추가:
│            "- [ ] <YYYY-MM-DD> hook <name> 작성 또는 강등 (룰 ID: <scope>:MANDATORY:NNN)"
│      ✅ 거짓 약속 차단 (🔴 + TODO 는 I1 위반). 작성 후 🔴 승급이 정직.
│      ❗ doctor 가 매 호출마다 deadline 추적. 임박/초과 시 다음 단계 옵션 제시.
│
│  ○  [c]  CRITICAL 포기 — MANDATORY 또는 CONVENTION으로 강등
│      📂 시그널만 바꿔서 prepend (사람 게이트로 충분)
│      ✅ 거짓 약속 없음, 솔직한 분류
│
│  ○  [d]  이 룰 자체를 보류 — adoption-plan.md에 keep, prepend X
│
└  ▸  답해주세요   [a/b/c/d] (룰마다 개별)
```

각 답의 후속 흐름은 `references/signal-guide.md` §hook 등록 시점.

## Q5 (e) — CONVENTION 처리

```
◆  CONVENTION 처리 방식
│
│  📍 spirit/rules에 4개 카테고리(architecture/data/testing/ops) 생성됨
│  🎯 root CLAUDE.md에서 어떻게 참조할지
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  @import — Claude Code 자동 로드                ✅ 권장
│      📂 ## CONVENTION 섹션에:
│           @.ax/spirit/rules/architecture.md
│           @.ax/spirit/rules/data.md
│           @.ax/spirit/rules/testing.md
│           @.ax/spirit/rules/ops.md
│      ✅ 변경 시 자동 반영, root는 한 줄씩만 (상대경로는 CLAUDE.md 기준 해석, 최대 5 hop 재귀)
│      ❗ *external* import (프로젝트 외부 경로, 예: `@~/.claude/foo.md`)는 첫 실행 시
│           approval dialog가 한 번 뜸 → 'allow' 권장. 위 4개 라인은 모두 프로젝트 내부
│           상대경로라 dialog 대상 아님. 거절 시 imports 비활성 유지 + dialog 재출현 X —
│           공식 문서에 documented된 자동 복구 메서드 없음.
│
│  ○  [b]  핵심 3-5개를 인라인 ID로 부여
│      📂 🔵 **`<scope>:CONVENTION:001`** ... 형식
│      ✅ PR 리뷰에서 인용 편함, grep 가능
│
│  ○  [c]  링크 한 줄만 (참조만)
│      ❗ 검색 불가, ID 인용 불가 — 비권장
│
└  ▸  답해주세요   [a] / [b] / [c]
```

## Q5 — 중복 감지 박스 (`constitution-apply.sh --scan-duplicates` 결과)

```
◆  중복 감지   N개 룰이 두 곳에 등장
│
│  📍 발견
│   COMMERCE:CRITICAL:001 ↔ ## Database Schema 변경 (정확 일치)
│   COMMERCE:MANDATORY:002 ↔ ## Development Patterns "Kotest DescribeSpec + MockK" (정확 일치)
│
│  🎯 목표  drift 방지 — 한 룰 = 한 곳
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  정확 일치만 자동 삭제                         ✅ 권장
│      📂 CLAUDE.md (구 섹션 줄 삭제, 신 시그널 블록만 남김) — constitution-apply.sh --drop-exact
│      ✅ 부분 일치는 사용자 확인 후 처리
│
│  ○  [b]  하나씩 보면서 결정
│      각 중복마다 [keep구/keep신/keep양쪽] 선택
│
│  ○  [c]  손대지 않음 — 사용자가 나중에 수동 정리
│      ❗ drift 위험 명시
│
└  ▸  답해주세요   [a] / [b] / [c]
```

❗ 박스를 출력하고 답을 기다린 *뒤에만* `--drop-exact`. prepend·중복정리를 묶어 사후 보고하는 형태는 결정 게이트를 건너뛰는 거예요 — 금지. H2 섹션 전체 삭제는 항상 사용자 확인.

## Sub-Q4 — statusline (HUD)

```
◆  Sub-Q4   statusline (HUD) 활성?
│
│  📍 발견  <검사 결과 — 예: "없음" / ".ax/hud/statusline.sh 가리키는 중" / "다른 도구 (omc/...)">
│
│  🎯 목표  매 응답 위에 하네스 위치 한 줄 — 설치 버전 · Size×Risk · spec › tasks › impl › review · mistakes
│            예: [goax#<ver>] | M×L3 · payment | spec ✓ › tasks ● › impl ○ | mistakes:2
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  활성화                                        ✅ 권장 (기존 statusLine 없을 때)
│      📂 .claude/settings.json
│
│  ○  [b]  합치기 — 기존 statusLine 과 둘 다
│      다른 도구(omc 등)가 이미 statusLine 을 쓰고 있을 때
│
│  ○  [c]  이미 .ax/hud/statusline.sh 가리키는 중 — 변경 없이 닫기
│      skip 이 아니라 *명시적으로 OK 받고 닫는* 옵션
│
│  ○  [d]  나중에 — /hud setup 으로 활성화
│
└  ▸  답해주세요   [a] / [b] / [c] / [d]
```
→ [a]/[b] 면 hud skill 위임. [c]/[d] 면 변경 없이 보고만.

## Sub-Q5 — `.ax/settings.json.suggested` 머지

```
◆  Sub-Q5   hooks 등록 — .ax/settings.json.suggested 머지?
│
│  📍 발견  up 이 기존 .claude/settings.json 을 보존하고 suggested 를 옆에 뒀어요
│            (현재: <suggested 존재 — 머지 필요> / <이미 머지됨 — 변경 불필요>)
│
│  🎯 목표  goax 훅 등록 — 안 하면 파괴 명령·룰 게이트·주입 훅이 하나도 안 돌아요
│
├─ 옵션 ────────────────────────────────────────────────
│
│  ●  [a]  머지 — 기존 settings.json + suggested            ✅ 권장
│      📂 .claude/settings.json (goax 훅만 템플릿대로) · suggested 삭제
│      ✅ 사용자 자신의 훅·permissions·statusLine 은 그대로
│
│  ○  [b]  보류 — 사용자가 나중에 수동 머지
│      ❗ 머지 전엔 hooks 등록 안 됨 — sensors 작동 X
│
└  ▸  답해주세요   [a] / [b]
```
→ [a] 시 `bash .ax/scripts/bash/ade-settings.sh --apply --plugin-dir "$PLUGIN_ROOT" --json` 후 `rm -f .ax/settings.json.suggested`. `jq -s '.[0] * .[1]'` 는 쓰지 않아요 — 배열을 통째로 바꿔 사용자 훅이 사라져요. [b] 시 suggested 그대로 + 다음 단계 안내.

## 완료 안내 (§5)

```
◆  onboarding 완료   .ax/.onboarding-pending 마커 정리했어요
│
│  📂 Spec 디렉토리
│     .ax/docs/spec/<id>-<slug>/  ← 작업 spec SSOT (spec 이 여기에 생성)
│     .ax/_templates/spec/        ← 템플릿 (도메인에 맞게 수정 가능, doctor 가 drift 감지)
│
│  📂 .ax/ runtime 파일은 .gitignore 자동 처리
│     .ax/state.json · .ax/current-task.json — per-machine 상태, PR 에 안 들어가요
│
│  📍 인계 노트 — .ax/current-task.json (handoff) · status-note.sh --show
│     다음 세션이 처음 읽는 자리예요. "다음" 절에 첫 할 일 1~3개가 들어갔어요.
│
│  📍 Mistake Loop — 주 1회 audit 권장
│     실수는 "실수 기록해줘" 로 캡처해요 (.ax/mistakes/). HUD 의 mistakes:N 이 누적을 보여줘요.
│
└  👉 다음 한 줄을 시도해보세요: "결제 환불 정책 변경 작업 계획 세워줘"
      → triage → spec 게이팅 (L3) → spirit·룰·페르소나 자동 주입
```
