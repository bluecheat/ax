---
name: zero
description: "zero to one — 아이디어 하나를 팔 수 있는 제품으로 끌고 가요. '/zero', 'zero to one', '0에서 시작', '새 제품 시작', '처음부터 만들자', '아이디어부터', 'PRD 부터', 'greenfield', '빈 리포에서 시작'. up 의 greenfield 분기가 넘겨받아요. 앞단(문제·대상·가치가설·안 만들 것·단위경제·성공중단기준·첫 사용자) → 중단(PRD·되돌리기 비싼 결정 ADR·시안 게이트) → 뒷단(domain_risk·스캐폴드·집행 배관·첫 배포·STATUS). 대신 정하지 않고 역면접으로 끌어내요."
---

# goax zero — 아이디어에서 팔 수 있는 것까지

> **빈 디렉터리를 세팅하는 스킬이 아니에요.** 아이디어 하나를 **제품과 비즈니스로** 끌고 가는
> 스킬이에요. 스캐폴드·CI 는 이 여정의 마지막 3분의 1이에요.
>
> goax 4계층은 `Triage → Spec → Implement → Verify` — **만들 것이 정해진 뒤**부터 시작해요.
> 그 앞의 하루를 이 skill 이 담당해요.

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 따라요. 둘 다 없으면 하네스가 아직 안 깔린 거예요 — `/up` 먼저.

## 발동 시점

- `up` 의 greenfield 분기가 넘겨줄 때
- 사용자가 `/zero`, "0에서 시작", "새 제품", "아이디어부터" 라고 말할 때
- `.ax/` 는 있는데 `.ax/docs/adr/` 이 비어 있고 제품 정의 문서가 없을 때

---

## 이 skill 의 두 가지 규율

### 1. 대신 정하지 않아요 — 역면접으로 끌어내요

실증 프로젝트 최대 실패가 이거였어요. 파운더 원문:

> *"왜 내 인터뷰도 없이 너맘대로 만들엇어?"* · *"UX 라이팅도 너맘대로 하고"*

비용은 아이콘 재작업 4회 이상. 5 Whys 근본 원인은
**"되돌리기 어려운 결정과 그렇지 않은 결정을 구분하지 않았다"** 였어요.
그래서 이 skill 의 골격이 그 구분이에요 — 되돌리기 비싼 것은 **전부 묻습니다.**
기술이냐 제품이냐는 기준이 아니에요.

**`AskUserQuestion` 이 기본 수단이에요.** 긴 계획 문서는 승인에서 멈춰요 (실측: `plans/*.md`
1건이 승인 대기로 정지). 선택지로 물은 라운드는 사이클이 **4.8시간 → 1.1시간**으로 줄었어요.

- 정보가 부족하면 정보를 모아 **선택지로 만들어** 다시 물어요. 임의로 채우지 않아요
- 추측한 값은 **"추측"** 이라고 표시해요. 시장·경쟁·가격은 특히
- "모르겠다" 도 유효한 답이에요 — PRD 열린 질문으로 옮기고 진행해요

### 2. 룰을 잔뜩 깔지 않아요 — 계약을 세워요

이 skill 은 산문 룰 팩을 붓지 않아요. 첫날 팩의 산문은 **5개**뿐이고, 나머지는 hook·스크립트·
테스트로 갑니다 (프롬프트 토큰 **0** — hook 정의는 `settings.json` 에 살아요).

근거: Claude Code 공식 best-practices — *"각 줄에 대해 물어라: 이걸 지우면 Claude 가 실수하게
되는가? 아니면 잘라라. 비대한 CLAUDE.md 는 Claude 가 실제 지시를 무시하게 만든다."* ·
*"CLAUDE.md 지시는 advisory 지만 hook 은 deterministic 하고 실행을 보장한다."*
정량으로도 — 지시 500개 밀도에서 최고 모델도 68% 준수(IFScale, arXiv 2507.11538),
distractor 하나만 있어도 성능 저하(Chroma, Context Rot 2025-07).

반대로 **하네스 자체는 지지받아요** — 같은 모델에서 하네스만 바꿔 76.2% vs 52.4%,
실패 1위가 contract/format violation 36.4%(Harness-Bench, arXiv 2605.27922).
그러니 **산문은 줄이고 계약을 늘려요.** 판정표: `.ax/_templates/zero/checks.md`.

**hook 은 조용해야 해요** — 통과하면 아무 말도 안 해요. hook 출력은 컨텍스트에 들어가서,
시끄러운 hook 은 아낀 토큰을 도로 씁니다.

---

# 앞단 — 제품·비즈니스

> 여기가 이 skill 의 본체예요. **코드 한 줄 없이** 끝나야 하고, 끝나면 무엇을 만들지와
> 왜 만드는지가 숫자로 남아요.

## 0. 사전 확인 + 첫날 팩 설치

```bash
[ -d .ax ] || echo "[goax] .ax/ 가 없어요 — /up 을 먼저 부르세요"

if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
    PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
else
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
fi

bash .ax/scripts/bash/zero-init.sh --plugin-dir "$PLUGIN_ROOT" --dry-run --json
bash .ax/scripts/bash/zero-init.sh --plugin-dir "$PLUGIN_ROOT" --json
```

**산출물**: 워크시트 4종 + PRD·ADR·시안·프로브 템플릿 + 산문 룰 5개 + 계약 hook 1개
**안 하면**: 뒤 단계가 매번 빈 종이에서 시작해요.

`result.skipped` 가 비어 있지 않으면 사용자에게 알려요 — 기존 파일을 보존한 거예요.

## 1. 문제와 대상

물을 것 (한 라운드 최대 5문, 선택지 우선 — 문항은
[`references/product-interview.md`](references/product-interview.md) A·B 축):

- 누구의 어떤 문제인가 — **한 사람을 떠올릴 수 있게**. "사용자" 는 답이 아니에요
- 지금 그 사람들은 **무엇으로 때우고 있나** (대안. "아무것도 안 한다" 도 유효)
- 왜 지금인가
- 명시적으로 **대상이 아닌** 사람은 누구인가

**산출물**: PRD 1·2장 초안 (파일 고정은 6단계에서 한 번에)
**안 하면**: 범위가 매 세션 다르게 해석돼요. 병렬 에이전트는 각자 다른 제품을 만들어요.

## 2. 가치 가설 + 위험 가정 순위

`.ax/_templates/zero/product/value-hypothesis.md` 를 함께 채워요.

- **가설 한 문장**: "<대상>이 <상황>에서 <행동>하면 <결과>를 얻는다"
- **반증 신호**: 무엇을 보면 틀린 건가 — 숫자와 기간으로. 없으면 가설이 아니라 소망이에요
- **위험 가정 순위**: (틀릴 가능성) × (틀렸을 때 잃는 것) 으로 줄 세우고,
  **1순위부터** 가장 싸게 검증할 방법을 정해요. 대개 코드가 아니에요

**산출물**: `.ax/docs/product/value-hypothesis.md`
**안 하면**: 지표가 나빠도 나쁜 줄 몰라요. 기준선이 없어서요.

## 3. 안 만들 것

범위를 여는 것보다 **닫는 게** 0→1 에서 더 중요해요.

- v0.1 에서 명시적으로 뺄 것 셋
- 그중 "요청이 와도 안 만든다" 는 어느 것인가
- 뺀 것을 나중에 넣을 조건

**산출물**: PRD 5장
**안 하면**: 거절의 근거가 사람의 기분이 되고, 가치가설이 무한히 커져요.

## 4. 비즈니스 형태 — 단위 경제

`.ax/_templates/zero/product/unit-economics.md` 를 함께 채워요.
**LLM·외부 API 를 쓰는 제품이면 이 단계를 건너뛰지 않아요.**

- 수익 모델과 언제 받는가
- **건당 원가** — 행위 1회 기준. 토큰 수는 재서 적고, 추정이면 추정이라고 표시해요.
  재시도·폴백 포함
- 감당 가능한 월 총액 → 거기서 나오는 **무료 한도**와 **비상 차단**
- 모델 폴백 조건

실증: 리딩 품질을 올리려고 근거를 여섯 자리로 늘리며 **건당 비용 약 1.7배**를 파운더가
명시적으로 감수한다고 ADR 에 적었어요. 상위 모델은 **p95 12.3초 · 비용 3.1배 · 게이트 실패**로
기각했고요. 둘 다 숫자가 있어서 **결정이 됐어요** — 첫날부터 이게 가능해야 해요.

**산출물**: `.ax/docs/product/unit-economics.md` + PRD 6장
**안 하면**: 품질 결정이 비용 판단 없이 내려지고, 나중에 청구서로 알게 돼요.

## 5. 성공·중단 기준 + 첫 사용자 경로

워크시트 둘을 같이 채워요 — `success-and-stop.md`, `first-users.md`.

- **계속 기준** 숫자 3개 이하 + 재는 방법 + 통과선
- **중단 기준** — 시간·돈·의지 셋 다. 셋 중 하나가 먼저 바닥나요
- **처음 10명** — 이름을 댈 수 있어야 해요. 못 대면 그게 1순위 위험 가정이에요
- **다음 100명** — 채널·비용·준비물
- 다음 검토일 (`.ax/docs/STATUS.md` 에 체크박스로 박아요)

**산출물**: `.ax/docs/product/{success-and-stop,first-users}.md`
**안 하면**: 접어야 할 때 접는 대신 기능을 더 붙여요. 그리고 다 만든 뒤에
"누구한테 보여주지" 를 고민하게 돼요.

---

# 중단 — 결정 고정

## 6. PRD v0.1

```bash
mkdir -p .ax/docs/prd
cp .ax/_templates/zero/prd-v0.1.md .ax/docs/prd/PRD-v0.1.md
```

**원문은 요약하지 않아요.** 파운더·의뢰인이 쓴 문장이 있으면 **0장에 그대로**. 오탈자도 그대로.
요약은 해석이고, 해석은 소유자가 바뀌는 일이에요. 없으면 그 사실을 적고 역면접 결과로 채워요 —
**없는 원문을 지어내지 않아요.**

1~5단계 결과를 옮기고, 못 정한 것은 7장 열린 질문으로 남겨요.

**산출물**: `.ax/docs/prd/PRD-v0.1.md`
**안 하면**: 결정이 채팅 로그에만 남아요. 다음 세션은 그걸 못 봐요.

## 7. 되돌리기 비싼 결정 → ADR

**여기가 이 skill 의 심장이에요.** 판정 기준 하나:
**"되돌리려면 무엇을 동시에 고쳐야 하나."** 답이 "전부" 면 지금 ADR 이에요.
**기술 결정만이 아니에요** — 제품명·톤·비주얼 방향·가격·수익 모델이 코드 결정보다 비쌌어요
(실증: 제품명 3번, 비주얼 방향 3번 갈아엎었고 전부 ADR 대체로 처리).

축 목록: `.ax/_templates/zero/irreversible-axes.md` (제품 · 비즈니스 · 기술 세 표)

절차:
1. 축을 훑고 이 제품에서 되돌리기 비싼 것만 고름 (보통 3~6개)
2. 축마다 **역면접으로** 대안 2~3개 + 기각 사유를 받음 — 기각 사유가 ADR 의 본체예요
3. 축 하나 = ADR 하나. 묶으면 하나를 뒤집을 때 나머지가 인질이 돼요
4. 안 고른 축은 "미결정" 에 이유와 재검토 시점을 적음

```bash
RESULT=$(bash .ax/scripts/bash/next-spec-num.sh --kind adr --reserve --slug "pricing-and-free-limit" --json)
ADR_PATH=$(echo "$RESULT" | jq -r '.result.path')
cp .ax/_templates/adr/0000-template.md "$ADR_PATH"
```

번호는 손으로 고르지 않아요 — 두 세션이 같은 `max+1` 을 받아 겹쳐요. 빈 상태 전용 분기가
있어서 첫 ADR 은 `0001` 로 나와요.

**산출물**: `.ax/docs/adr/0001-*.md` … (보통 3~6개) + 미결정 축 목록
**안 하면**: 첫 주 안에 되돌려야 하는 결정이 생기고, 그때는 코드가 이미 그 결정에 기대요.

## 8. 시안 승인 게이트 (화면이 있으면)

`.ax/_templates/zero/sian-gate.md`. 승인은 말이 아니라 **아티팩트**에 해요.
실증 — 이 게이트가 없어서 잘못된 버튼 모양으로 승인이 날 뻔했어요.

불변 넷: 승인 대상은 아티팩트 하나 · 소유자 하나 · **실기기와 같은 단위로 렌더** ·
승인 후 바이트 대조.

**산출물**: 승인 기록 표가 붙은 시안 아티팩트
**안 하면**: 승인한 것과 구현된 것이 다른 물건이 돼요.

---

# 뒷단 — 기술 배관

## 9. `domain_risk` 최초 설정

**건너뛰면 triage 가 영원히 L0 로 흘려요.** 사고 경로가 이래요:
빈 리포에서 `triage-search.sh` 는 전부 빈 배열을 돌려주고 → `domain_risk` 가 출고 예시뿐이라
`default_risk` 로 떨어지고 → 매트릭스가 "S/M × L0 = 즉시 작업, spec 불필요" 로 흘리고 →
역면접은 발동 조건(M×L2 이상) 미달로 스킵돼요.

1~4단계에서 나온 위험 도메인(돈·개인정보·안전·비가역 동작)을 키로 옮겨요.

```bash
bash .ax/scripts/bash/zero-domain-risk.sh --show --json
bash .ax/scripts/bash/zero-domain-risk.sh --set "photo-capture=L3,face-reading=L2,share=L1" \
     --default L1 --dry-run --json
bash .ax/scripts/bash/zero-domain-risk.sh --set "photo-capture=L3,face-reading=L2,share=L1" \
     --default L1 --json
```

`default_risk` 는 **L1 권장**. 출고 기본값 L0 는 "매핑이 아직 없음" 을 뜻해요.
L2/L3 도메인은 `.ax/modules/<name>/rules.md` stub 도 만들어 둬요 (frontmatter 만).

**산출물**: `.ax/config.yml` + before/after 카운트
**안 하면**: 이후 모든 triage 가 무마찰로 지나가요.

## 10. 스캐폴드

**goax 는 앱 코드를 모릅니다.** 사용자나 구현 에이전트에 위임하고, 이 skill 은
**결과가 ADR 과 맞는지 대조**만 해요.

```bash
ls -d */ | head -20
git log --oneline | head -5
```

**산출물**: 스캐폴드 + "ADR 대조 결과" 한 문단 (어긋남 0건이면 0건이라고 적어요)
**안 하면**: ADR 과 코드가 첫날부터 갈라져요.

## 11. 집행 배관 + 네거티브 프로브 ⚠ 건너뛸 수 없음

게이트를 **차단(fail) 모드**로 깔고, **일부러 위반을 만들어 exit ≠ 0 을 확인**해요.

```bash
bash .ax/scripts/bash/install-git-hooks.sh --json
cp .ax/_templates/zero/ci-github-actions.yml .github/workflows/gates.yml
mkdir -p .ax/probes && cp .ax/_templates/zero/probes/*.sh .ax/probes/

bash .ax/scripts/bash/zero-verify.sh --json    # 게이트를 파이프 없이 돌리고 증거를 냄
bash .ax/scripts/bash/zero-probe.sh --json     # 차단이 살아 있는지 확인
```

- `zero-verify.sh` — `config.yml` 의 `commands.*` 를 **파이프 없이** 돌리고 exit code 를 따로
  잡아요. **안 돌린 항목도 보고**해요 (안 돌린 건 통과가 아니에요)
- `zero-probe.sh` — `.ax/probes/*.sh` 를 돌려 "막아야 할 위반이 아직 막히는지" 확인.
  **첫날 1회로 끝내지 말고 CI 에 넣어요** — 실증으로 CI 가 설치 실패로 한 번도 안 돌면서
  초록이었고, policy-as-code 의 같은 함정이에요 (*undefined 는 denied 와 다르다*)
- 게이트를 하나 깔 때마다 프로브도 하나 늘려요 — **게이트와 프로브는 짝**이에요

**산출물**: pre-commit 체인 + CI 워크플로 + 프로브 결과 (명령과 exit code 를 기록에)
**안 하면**: "적혀 있지만 아무것도 막지 않는" 문서가 자라요.

## 12. 첫 배포

배포 경로를 첫날에 **한 번 끝까지** 통과시켜요. 내용은 빈 화면이어도 돼요.

성공을 **로그 줄**로 확인해요. "성공했습니다" 는 확인이 아니에요 — 실증으로
`xcodebuild | tail -5` 가 exit 65(서명 실패)를 성공으로 읽었어요. `zero-verify.sh` 를 쓰거나
파이프를 떼세요.

**산출물**: 배포 주소 또는 빌드 번호 + 그 로그 줄
**안 하면**: 심사·서명 같은 긴 리드타임을 출시 직전에 만나요.

## 13. STATUS 개설 + 다음 라운드 인계

`.ax/docs/STATUS.md` 는 **공용 인계 노트**예요 — zero 뿐 아니라 `triage` 가 매 작업 진입 때 먼저 읽고,
`spec-implement` 가 halt·완료·레인 보고 시점에 갱신해요. 손으로 쓰지 말고 스크립트로 적어요 (형식이
고정돼야 다음 세션이 파싱해요). **끝난 항목은 지웁니다.** 완료 사실의 SSOT 는 `git log` 와 ADR 이에요.

```bash
bash .ax/scripts/bash/status-note.sh --init --json
bash .ax/scripts/bash/status-note.sh --set now "첫날 완료 — 배포 <주소 또는 빌드 번호>" --json
bash .ax/scripts/bash/status-note.sh --add next "- [ ] <날짜> 1순위 위험 가정 \"<가정>\" 을 <방법>으로 검증" --json
bash .ax/scripts/bash/status-note.sh --add next "- [ ] <6개월 뒤 날짜> 룰 ablation 재검토 (.ax/_templates/zero/ablation.md)" --json
bash .ax/scripts/bash/status-note.sh --add open "<미룬 축 — 있을 때만>" --json
```

`## 다음` 의 두 체크박스(1순위 가정 검증 · ablation 재검토)는 빠지면 안 돼요 — 문서 안에만 있는
날짜는 아무도 안 봐요.

인계 출력:

```
🌱 zero to one — 첫날 완료

 제품      문제·대상 정의 · 가치가설 · 안 만들 것 <n>개
 비즈니스   <수익 모델> · 건당 원가 <값> · 무료 한도 <값>
 기준      계속 <n>개 · 중단 <n>개 · 다음 검토 <날짜>
 첫 사용자  10명 경로 <있음/없음> · 다음 100명 채널 <n>개
 PRD       .ax/docs/prd/PRD-v0.1.md
 ADR       <n>개 — <슬러그 목록> (제품 <n> · 비즈니스 <n> · 기술 <n>)
 도메인     L3 <n> · L2 <n> · L1 <n> (default_risk=<L?>)
 계약      산문 룰 5 · hook <n> · 프로브 <n> (CI 상시)
 배포      <주소 또는 빌드 번호>
 미결정     <미룬 축 — 없으면 "없음">

다음: 1순위 위험 가정 "<가정>" 을 <방법>으로 검증해요
```

---

## 절대 금지

- **대신 정하지 않아요.** 되돌리기 비싼 것은 제품·비즈니스·기술을 가리지 않고 물어요
- **앞단을 건너뛰고 스캐폴드로 가지 않아요.** 순서가 메시지예요 — 무엇을 왜 만드는지가
  숫자로 남기 전에는 코드가 부채예요
- **9단계를 건너뛰지 않아요.** 스킵하면 triage 가 영원히 L0 로 흘리고, 그 사실은
  아무 데도 표시되지 않아요
- **11단계를 "나중에" 로 미루지 않아요.** 코드가 쌓인 뒤 게이트를 깔면 기존 위반이
  쏟아져서 게이트를 끄게 돼요
- **산문 룰을 늘리지 않아요.** 새 룰이 필요하면 먼저 `checks.md` 의 3단계 판정을 돌려요 —
  기계로 옮길 수 있으면 (가), 모델이 이미 하면 (다)
- 원문을 요약해서 PRD 에 넣지 않아요. 인용이 정본이에요
- 프로브 없이 "게이트를 깔았어요" 라고 보고하지 않아요

## 다음 skill 로

첫날이 끝나면 평소 흐름: `triage` → `spec` → `spec-tasks` → `spec-implement`.
첫날에 못 깐 계약(폐기 어휘 lint · eval 임계값 · 스냅샷 짝비교 등)은 `before` 상태가 생기면
`audit` 이 mistake 에서 승격시켜요 — 자리는 `zero-baseline.md` 상단 주석과 `checks.md` 에 있어요.

## state.json 갱신

이 skill 이 끝날 때 `.ax/state.json` 갱신 항목: 전체 (Layer 1·3 + Spirit 이 여기서 생겨요).

```bash
bash .ax/scripts/bash/update-state.sh

jq '.last_skill = "zero" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
