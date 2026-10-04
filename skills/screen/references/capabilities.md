# 도구 슬롯 — 있으면 빨라지고, 없어도 끝까지 가요

screen skill 은 **외부 의존 0** 으로 돌아요. 보는 눈 · 수치 · 부품 규격 · 문구 절차 · 기본 토큰 세트가 전부 이 skill 의 references 안에 있어요. MCP · 브라우저 자동화 · 시뮬레이터 · 이미지 라이브러리는 **있으면 빨라지는 가속기**예요. 무엇이 있는지는 기억으로 가정하지 않고 스크립트로 찾아요:

```bash
bash .ax/scripts/bash/design-caps.sh --json
```

`result.stack` (web · react-native · expo · lynx · flutter · swiftui · android · unknown), `result.slots.<슬롯>[]` (`provider` = `file` · `mcp:<서버>` · `cli:<명령>` · `python:pillow`), `result.spec` (지금 있는 design-spec 경로), `result.empty` (비어 있는 슬롯)를 읽어요.

MCP 는 설정 파일에 **등록된 이름**만 보여요. 이 세션에 실제로 떠 있는지는 자기 도구 목록(`mcp` 접두어가 붙은 그 서버 이름의 도구)으로 한 번 더 확인하고, 없으면 그 provider 는 없는 것으로 쳐요.

## 목차

1. 슬롯 표 — 찾으면 무엇에 쓰나 · 없으면 무엇으로 대신하나 · 2. 슬롯별 상세 (tokens · components · reference · render · measure) · 3. 우선순위 규칙 · 4. 리포트에 적는 법

---

## 1. 슬롯 표

| 슬롯 | 찾으면 (provider 예) | 무엇에 쓰나 | 없으면 (대체 수단) | 리포트 표기 |
|---|---|---|---|---|
| **tokens** | `file`: tokens.* · theme.* · tailwind.config.* · colors.xml · design-system 문서 / `mcp:`: 디자인 시스템 MCP · Figma MCP (변수 정의) | 표 0 의 진실 원천. 이름·값을 그대로 가져와요 | `color-type.md` §6~§11 기본 세트를 토큰 파일로 새로 만들어요 (§12 스택별 파일) | "tokens: src/theme/tokens.ts" / "tokens: 없음 → 기본 세트로 신설" |
| **components** | `file`: components.json(레지스트리) · .storybook · components/ui · design-system 디렉터리 / `mcp:`: 디자인 시스템 · 레지스트리 MCP | 이미 있는 부품을 재사용 — 새로 만들기 전에 찾아요 | `components.md` 16종 규격 + `component-systems.md` §12 기본값으로 공용 부품을 만들어요 (Button · Row · Chip … 하나씩, size prop) | "components: Storybook 18종 재사용" / "components: 없음 → Button·Row 신설" |
| **reference** | `mcp:`: 화면 레퍼런스 갤러리 MCP · Figma MCP (스크린샷) | 처음 나오는 화면 유형에서 같은 업종 화면 3~5개의 "왜" 를 봐요 | `screens.md` 의 정보 순서·핵심 정보 + 사용자가 준 스크린샷·URL + (있으면) 웹 검색. 레퍼런스 단계를 건너뛰어도 게이트는 그대로예요 | "reference: N건 — 가져온 이유 2~3줄" / "reference: 건너뜀 (슬롯 비어 있음, screens.md §N 기준)" |
| **render** | `cli:` 브라우저 자동화 CLI · playwright · simctl · adb / `mcp:` 브라우저 자동화 · 시뮬레이터 MCP | 스크린샷을 찍어요 (`measure.md` §1) | 사용자가 직접 띄워 캡처를 주도록 다음 행동을 적고, 코드 정적 검사로 게이트를 대신 돌려요 | 리포트 첫 줄 `verdict: 실측 아님` |
| **measure** | `python:pillow` (`screen-measure.sh`) · 정적 UI 검사 CLI | 스캔라인으로 pt 를 재고, 전후 diff | 스크린샷을 눈으로 보고 코드값과 대조 — 숫자는 "코드값 (실측 아님)" | 리포트 첫 줄 `verdict: 실측 아님` |

## 2. 슬롯별 상세

### tokens

- 프로젝트 파일이 늘 MCP 보다 먼저예요. 코드가 실제로 쓰는 값이 진실이고, 디자인 도구 변수는 어긋나 있을 수 있어요.
- 디자인 시스템 MCP 가 있으면 **토큰 이름을 찾는 데** 써요. 이름을 지어내지 않아요. 값은 프로젝트 토큰 파일에서 확인해요.
- Figma MCP 의 변수 정의는 파일 키(URL)가 있어야 해요. 사용자가 링크를 주지 않았으면 쓰지 않아요.
- 토큰 파일이 둘 이상이면 (예: theme.ts 와 tailwind.config) 어느 쪽이 런타임에서 이기는지 import 를 따라가 확인하고 리포트에 적어요.

### components

- 레지스트리(components.json)가 있으면 새 부품을 만들기 전에 레지스트리에서 찾고, 있는 부품은 그대로 설치·재사용해요.
- Storybook 이 있으면 부품의 size · variant 목록을 거기서 읽어요. 스토리의 기본 size 를 그대로 쓴 호출부가 "화면마다 다른 높이" 의 1순위 원인이에요.
- 공용 부품이 없으면 **같은 역할은 같은 부품 하나**로 만들어요 — 화면 파일 안에 버튼 스타일을 복사하지 않아요.

### reference

- 트리거: design-spec 에 아직 없는 화면 유형이 처음 나올 때만. 규칙이 이미 있는 화면 유형이면 건너뛰어요.
- 한 번의 호출에 조건(업종 · 화면 유형 · 지역)을 모두 걸어요. 3~5개면 충분해요.
- 뽑는 건 **정보 순서 · 핵심 정보 위치 · CTA 위치 · 상태 처리** 뿐이에요. 색 · 라운드 · 그림자는 옮기지 않아요 (`process.md` §6).
- 레퍼런스 MCP 가 유료·로그인 제한으로 일부만 보여 줘도, 보인 것만 적고 진행해요.

### render

- 웹: 브라우저 자동화로 375 · 390 · 430 (+ 데스크톱 1280) 뷰포트.
- RN · Expo · Lynx · Flutter · SwiftUI: iOS 시뮬레이터 (`xcrun simctl`), 없으면 Android 에뮬레이터 (`adb`).
- 시뮬레이터 캡처 MCP 가 있으면 그걸 써도 되지만, 재는 건 **원본 PNG 파일**이에요 — 도구가 줄여 보여 준 이미지로 재지 않아요.
- 빌드가 실패하면 고치는 건 이 skill 의 일이 아니에요. 실패 로그 첫 줄을 적고 §1 의 대체 수단으로.

### measure

- `screen-measure.sh` 는 python3 + Pillow 만 있으면 돌아요. exit 2 = 없음.
- 정적 UI 검사 CLI 가 있으면 보조로 돌려 결과를 리포트 "파일" 절에 붙여요. 그 결과가 스크린샷 측정을 대신하지는 않아요.

## 3. 우선순위 규칙

1. **프로젝트 자체 > 외부.** 프로젝트 토큰·부품·design-spec 이 있으면 MCP 보다 먼저예요.
2. **있는 걸 쓰고, 없는 걸 기다리지 않아요.** 빈 슬롯 때문에 멈추거나 사용자에게 설치를 요구하지 않아요 — 대체 수단으로 진행하고 리포트에 적어요.
3. **이름을 기억으로 가정하지 않아요.** `design-caps.sh` 가 보고하지 않은 도구는 없는 거예요.
4. **실측 표기는 정직하게.** render 나 measure 가 빠지면 리포트 첫 줄은 `verdict: 실측 아님` 이에요. 스크린샷 경로와 px 숫자 없이 "측정했다" 고 쓰지 않아요.

## 4. 리포트에 적는 법

리포트 머리의 **도구** 줄에 슬롯마다 한 칸:

```
도구: tokens=src/theme/tokens.ts · components=없음→신설 · reference=건너뜀(빈 슬롯) · render=cli:simctl · measure=python:pillow
```
