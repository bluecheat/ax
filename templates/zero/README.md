# `templates/zero/` — zero to one 팩

`templates/default/` 가 **하네스 골격**(4계층·스크립트·훅)을 깐다면, 이 팩은
**아이디어를 제품으로 끌고 가는 데 필요한 것**을 깔아요 — 제품·비즈니스 워크시트,
결정 고정 템플릿, 그리고 **산문이 아니라 계약**으로 세운 정확도 장치.

`zero` skill 이 소비하고, 복사는 `.ax/scripts/bash/zero-init.sh` 가 해요
(MANIFEST 대상이 아니에요 — 조건부·선택 설치).

## 구성

```
product/          제품·비즈니스 워크시트 4종   → .ax/_templates/zero/product/
prd/              PRD v0.1 (결정 고정)         → .ax/_templates/zero/prd-v0.1.md
adr/              되돌리기 비싼 축 체크리스트   → .ax/_templates/zero/irreversible-axes.md
design/           시안 승인 게이트             → .ax/_templates/zero/sian-gate.md
checks/           계약 카탈로그 (핵심 문서)     → .ax/_templates/zero/checks.md
probe/            네거티브 프로브 계약 + 예시   → .ax/_templates/zero/{probe-recipes.md,probes/}
ci/               CI 워크플로 예시             → .ax/_templates/zero/ci-github-actions.yml
ablation.md       삭제 루틴 (6개월마다)        → .ax/_templates/zero/ablation.md
hooks/            계약 hook                   → .ax/hooks/pre-bash/ (+ settings.json 등록)
spirit/rules/     산문 룰 5개                 → .ax/spirit/rules/zero-baseline.md
```

설치:

```bash
bash .ax/scripts/bash/zero-init.sh --plugin-dir "${CLAUDE_SKILL_DIR}/../.." --json
bash .ax/scripts/bash/zero-init.sh --plugin-dir <path> --dry-run --json   # 무엇이 깔릴지만
```

같은 이름의 파일이 이미 있으면 **덮지 않고 건너뜁니다** (`result.skipped`).

## 1. 제품·비즈니스 워크시트

0→1 에서 가장 비싼 실수는 **틀린 걸 잘 만드는 것**이에요. 네 장이 그걸 막습니다.

| 워크시트 | 무엇을 정하나 | 없으면 |
|---|---|---|
| `product/value-hypothesis.md` | 가치 가설 · 반증 신호 · 위험 가정 순위 | 지표가 나빠도 나쁜 줄 몰라요 |
| `product/unit-economics.md` | 수익 모델 · 건당 원가 · 가격 · 한도 | 품질 결정이 비용 판단 없이 내려져요 |
| `product/success-and-stop.md` | 계속 기준 · 중단 기준 | 접어야 할 때 기능을 더 붙여요 |
| `product/first-users.md` | 처음 10명 · 다음 100명 · 첫 인상 자산 | 다 만들고 "누구한테 보여주지" 를 고민해요 |

`prd/prd-v0.1.md` 는 계산하는 자리가 아니라 **결론을 고정하는 자리**예요.
원문은 요약하지 않고 그대로 인용해요.

## 2. 되돌리기 비용이 판정 기준이에요

`adr/irreversible-axes.md` 는 축을 **제품 · 비즈니스 · 기술** 세 표로 나눠 놓았어요.
기준은 영역이 아니라 **"되돌리려면 무엇을 동시에 고쳐야 하나"** 하나예요.

실증 프로젝트는 제품명을 3번, 비주얼 방향을 3번 갈아엎었어요 — **코드가 아닌 결정이
코드 결정보다 비쌌어요.** 그리고 최대 실패는 그걸 혼자 정한 것이었어요
(파운더 원문: *"왜 내 인터뷰도 없이 너맘대로 만들엇어?"*, 비용 아이콘 재작업 4회 이상).

## 3. 정확도 장치는 산문이 아니라 계약으로

실증에서 뽑은 규율은 16개였는데, **그대로 깔지 않았어요.**

- **(가) 계약·기계 8개** — hook·스크립트·테스트·CI 로. 프롬프트 토큰 **0**
- **(나) 최소 산문 7개 → 4개로 합침** — 기계가 판정 못 하는데 없으면 틀리는 것
- **(다) 삭제 1개** — 지금 하네스가 이미 하는 일
- **(신규) 1개** — `SP-REV-001` 되돌리기 비용 판정

최종 산문은 `spirit/rules/zero-baseline.md` **5개**뿐이에요. 판정표와 근거는
`checks/README.md` 에 있어요 (Claude Code best-practices · Context Rot · IFScale ·
Harness-Bench · MAST).

기계로 간 것들:

| 장치 | 무엇을 막나 |
|---|---|
| `hooks/zero-guard-bash.sh` | `git add -A` 차단 · 게이트 명령 파이프 경고 |
| `zero-verify.sh` | 게이트를 파이프 없이 실행 + 안 돌린 항목까지 보고 |
| `zero-probe.sh` + `probe/examples/` | 차단이 아직 살아 있는지 **CI 에서 상시** 확인 |
| `ci/github-actions.yml.example` | 게이트·프로브·하네스 invariant 세 잡 |
| 기존 goax 도구 | `tasks-gate.sh`(완료 판정) · `spec-completion-gate.sh` · `check-rule-enforcement.sh` |

**hook 은 조용해야 해요** — 통과하면 무출력. hook 출력도 컨텍스트를 먹어서,
시끄러운 hook 은 (가)로 옮겨 아낀 토큰을 도로 씁니다.

## 4. 지우는 절차가 같이 들어 있어요

`ablation.md` — 6개월마다(또는 모델 세대가 바뀔 때) 룰을 **전부 끄고** 무엇이 실제로
깨지는지 재는 절차. `zero-ablation.sh --off` 로 한 명령이에요.

첫날 팩이 영구 부채가 되지 않게 하는 유일한 장치예요. 읽어 보고 판단하면 전부 그럴듯해
보여요 — 없이 돌려 봐야 알아요.

## 나중에 붙는 자리

`before` 상태·코퍼스·실기기가 생겨야 성립하는 것들. 조건이 생기면 **산문이 아니라 계약으로**
붙여요. 자리는 `spirit/rules/zero-baseline.md` 상단 주석에도 박혀 있어요.

| 자리 | 조건 | 어디로 |
|---|---|---|
| 폐기 어휘 lint | 대체된 시안·용어가 생긴 뒤 | pre-commit grep |
| 감사 스크립트 (전수 검사) | 검사 대상 코퍼스가 생긴 뒤 | `lint:*` 계열 |
| 스냅샷 짝비교 | `before` 렌더가 생긴 뒤 | 테스트 |
| 구조 증명 테스트 | 호출 경로가 생긴 뒤 | 테스트 |
| 회귀 기준선 (성능·크기·시간) | 첫 측정값이 생긴 뒤 | CI 게이트 |
| eval 임계값 | 첫 측정 분포가 나온 뒤 | CI 게이트 |
| 말뭉치 지문 (어휘·길이 분포) | 출력이 쌓인 뒤 | CI 게이트 |
| 절간 정합 (문서 절 모순) | 문서가 여러 절로 자란 뒤 | 스크립트 |
| 실기기 함정 목록 | 실기기에 한 번 올려 본 뒤 | 체크리스트 |
