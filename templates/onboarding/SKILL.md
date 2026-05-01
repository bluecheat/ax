---
name: goax-onboarding
description: "goax up 직후 또는 사용자가 'goax 분석/마무리/세팅/도입' 등을 말할 때 자동 발동. .ax/.onboarding-pending 마커가 있으면 우선 처리. 프로젝트의 CLAUDE.md·모듈·도메인·외부 spec을 실제로 읽고 도메인 위험도(L0~L3) 매핑·hooks 강도·룰 분류를 사용자와 대화하며 .ax/config.yml과 adoption-plan.md에 기록. 트리거: 'goax 도입', 'goax 마무리', 'goax 세팅', 'goax 분석', 'goax 셋업', 'onboarding', '하네스 적용'."
---

# goax-onboarding — 프로젝트 분석 + 4가지 결정

## 언제 발동하는가

다음 중 하나면 **반드시** 이 skill을 따라요:

1. `.ax/.onboarding-pending` 파일이 존재할 때 (사용자 메시지와 무관하게 우선)
2. 사용자가 "goax 도입", "goax 마무리", "goax 세팅", "goax 분석" 등을 말할 때
3. `goax up` 직후 첫 사용자 메시지일 때

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

다음을 실제 파일로 확인해요. **추측 금지, 추측 대신 질문(values §4)**.

### 2.1 모듈 구조
- 모노레포면 각 모듈의 `CLAUDE.md` 유무 확인
- Gradle: `settings.gradle.kts`에서 `include(...)`
- pnpm/yarn: `pnpm-workspace.yaml` / `package.json#workspaces`
- 모듈 간 의존을 적어도 표면적으로 파악 (build.gradle.kts의 `implementation(project(":x"))` 등)

### 2.2 도메인 식별
- 모듈명·패키지 트리·도메인 디렉토리(`com.x.commerce.payment` 등)에서 **의미 있는 도메인 단어**만 추출
- 짧은 prefix(`ad`, `ba`)·일반 단어(`common`, `util`)는 제외
- 5~12개 정도로 정리

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

### 2.5 외부 spec
sibling 디렉토리(`commerce-spec` 등)나 자기 안의 `spec/` `specs/` `governance/`가 의미 있는 결정 문서를 가지고 있으면 후보로 보여줘요.

## 3. 사용자와 4가지 결정

분석 결과를 정리해 보여주고, 4 가지를 자연어로 물어요. **한 번에 하나씩**, 디폴트는 권장값.

### Q1. CLAUDE.md 처리
> "CLAUDE.md에 룰 N개를 발견했어요. 자동 분류해서 `adoption-plan.md`로 정리할까요? (a 권장 / b 수동 / c 보류)"

선택 a면 `lib/migrate.sh::migrate_emit_plan` 호출 (또는 직접 마크다운 작성).

### Q2. 도메인 위험도
> "도메인 N개를 식별했어요. 다음 매핑을 `.ax/config.yml`에 기록할까요?
> - L3: payment, settlement
> - L2: order, auth
> - L1: catalog, search
> 수정·삭제할 게 있으면 알려주세요. 그대로면 'a'."

선택 a → 사용자가 수정한 매핑(또는 추정값)으로 `.ax/config.yml`의 `domain_risk` 섹션 업데이트.

### Q3. hooks 강도
> "기존 hooks: husky / pre-commit / lint-staged 가 있어요. goax hooks는 어떻게 시작할까요?
> a) warning — 메시지만, 차단 안 함 (안전, 권장)
> b) fail — CRITICAL 위반 시 차단
> c) 비활성 — settings.json 비활성화"

선택대로 `.ax/config.yml`의 `sensors.mode` 변경 또는 `.claude/settings.json` 처리.

### Q4. 외부 spec (있을 때만)
> "sibling 디렉토리에 `commerce-spec`이 있어요. 어떻게 할까요?
> a) 링크만 — `.ax/spirit/README.md`에 참조 추가
> b) 흡수 — `docs/spec/imported/commerce-spec/` 으로 복사
> c) 무시"

## 4. 적용

사용자가 'Y'/'네'/'적용' 등으로 확인하면 실제 파일을 수정해요. **각 단계를 ✓로 보고**:

```
✓ adoption-plan.md 생성 — 12개 룰 분류
✓ .ax/config.yml — domain_risk 7개 추가
✓ .ax/config.yml — sensors.mode = warning
✓ docs/spec/imported/commerce-spec/ 흡수 (132 파일)
```

## 5. 자가 삭제 (필수)

onboarding이 끝나면 **이 skill 자체와 마커를 모두 삭제**해요. 일회용이에요.
프로젝트 트리에 영구 잔재 금지.

```bash
# 1. 마커 삭제
rm -f .ax/.onboarding-pending

# 2. skill 자체 삭제 (이 파일이 들어있는 디렉토리)
rm -rf .claude/skills/global/goax-onboarding
```

마지막에 사용자에게 다음 메시지를 줘요:

```
🥳 onboarding 완료. onboarding skill·마커 모두 정리했어요.
다음 한 줄을 시도해보세요:

  "결제 환불 정책 변경 작업 계획 세워줘"
   → triage → spec 게이팅 (L3) → spirit·룰·페르소나 자동 주입
```

## 절대 금지

- 추측만으로 `domain_risk`나 위험도를 박아넣지 않아요. 모르면 사용자에게 물어요.
- bash 휴리스틱이 추정한 값을 **검증 없이** 그대로 쓰지 않아요. 한 번씩 코드를 직접 보고 확인해요.
- 한 번에 4 가지를 다 묻지 않아요. 한 결정씩, 사용자 답을 받고 다음으로 진행.
