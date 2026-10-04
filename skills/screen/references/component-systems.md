# 디자인 시스템별 부품 값 비교 — 합의 규칙 · 시스템마다 다른 값 · 상태 · 접근성

공개 디자인 시스템과 표준(shadcn/ui · Material 3 · Chakra UI v3 · Apple HIG · WAI-ARIA APG · WCAG)을 직접 읽고 **공급자 중립 규칙**만 다시 쓴 비교표예요. 이 skill 은 이 시스템들에 **의존하지 않아요** — 이름과 출처는 "왜 이 숫자인가" 의 근거로만 남겨요. 프로젝트에 자기 디자인 시스템이 있으면 그 값이 이기고, 이 표는 그 값이 실무 범위 안인지 보는 잣대예요.

- 숫자마다 출처 키(`[키]`)를 달았어요. URL 은 맨 아래 **출처**. 직접 확인하지 못한 값은 **(미확인)** 이에요.
- 출처 없이 "(관행)" 이라 적힌 규칙은 여러 실무 팀에서 반복되지만 위 공개 문서엔 명시가 없는 것이에요.
- 조사일 2026-10-04. `components.md`(16종 규격)가 "어떻게 그리나" 라면, 이 파일은 "시스템들은 몇으로 정했고 어디서 갈리나" 예요.

단위 메모
- shadcn·Chakra 는 Tailwind/Panda 스페이싱이에요. 1단위 = 4px(0.25rem) — `h-9` = 36px, `size-4` = 16px, Chakra `h: "10"` = 40px.
- M3 모양 단계: extra-small 4 · small 8 · medium 12 · large 16 · extra-large 28 · full [M3-shape]. dp ≈ CSS px.
- Chakra 반경: l1 = xs = 2px, l2 = sm = 4px, l3 = md = 6px [CH-radii].
- HIG pt ≈ CSS px (1x 기준).

## 목차

- §0 모든 부품에 걸리는 공통 규칙 (터치 · 대비 · 비활성 · 포커스 · 눌림 · 상태 레이어 수치)
- §1 Button · §2 Text field · §3 List row · §4 Card · §5 Chip · §6 Tabs·Segmented · §7 Bottom sheet·Dialog · §8 Toast·Snackbar · §9 Checkbox·Radio·Switch · §10 Top app bar
  - 부품마다: 합의된 규칙 → 시스템마다 다른 값 → 상태 체크리스트 → 접근성·키보드 → 문구 → 안티패턴
- §11 토큰 역할 이름 대응표 (역할 → 각 시스템 이름)
- §12 디자인 시스템이 없을 때 기본값 (한 장 요약)
- 출처

---

## 0. 모든 부품에 걸리는 공통 규칙

### 0.1 합의된 규칙

- **최소 터치 영역**: 모바일은 44–48. HIG iOS 기본 44×44pt, 최소 28×28pt [HIG-a11y]. M3 칩 min touch target 48dp [M3-chip-doc], 텍스트필드 아이콘 min 48dp [M3-tf-doc]. WCAG 2.2 AA 24×24 CSS px (간격 예외 있음) [WCAG-258], AAA 44×44 [WCAG-255]. 아주 작은 스위치도 터치 영역은 24 이상을 보장해요 (관행).
- **보이는 모양이 작아도 터치 영역은 커야 해요**: M3 체크박스는 18px 상자에 40px 상태 레이어 [M3-cb]. 라벨을 포함한 영역 전체가 타깃이고, 리스트에서는 행 전체가 타깃이에요 (관행 · `principles.md` C3).
- **대비**: 본문 텍스트 4.5:1, 18pt 이상 큰 텍스트 3:1 [HIG-a11y]. 비텍스트 UI(테두리·포커스 링·아이콘)는 3:1 (WCAG 1.4.11, 미확인 — 페이지 미조회). APCA 로 재면 역할별 기준이 달라요 — `principles.md` C2.
- **비활성 처리**: shadcn·Chakra 는 `opacity: 0.5` 하나 [SH-button][CH-layer]. M3 는 컨테이너 12%, 내용 38% [M3-fb]. 전용 disabled 배경·글자 토큰을 두는 시스템도 있어요. → 비활성은 투명도 하나가 아니라 **"배경과 글자 둘 다 약해진다"** 로 정의하고, 비활성이어도 글자는 읽혀야 해요.
- **포커스 표시**: shadcn 은 `focus-visible:ring-[3px] ring-ring/50` + 테두리 `border-ring` [SH-button], Chakra 는 `focusVisibleRing: outside`(입력은 inside) [CH-button][CH-input]. → 마우스 클릭이 아니라 **키보드 포커스(`:focus-visible`)에서만** 링을 보여 줘요.
- **눌림 피드백은 필수예요**: HIG 는 커스텀 버튼에 press 상태를 반드시 넣으라고 해요 [HIG-btn]. M3 는 pressed 상태 레이어 12% [M3-state]. 모든 인터랙티브 부품에 pressed 정의를 두고, 필요하면 축소(scale) 피드백도 더해요 (`principles.md` B2–B8).
- **브랜드 색은 아껴 써요**: HIG 는 prominent 버튼을 뷰마다 가장 가능성 높은 액션 하나에만 쓰라고 해요 [HIG-btn][HIG-toolbar]. 브랜드 색은 핵심 액션·사용자 간 연결에만 (`principles.md` A3).

### 0.2 상태 레이어 수치 (다른 시스템이 따로 정하지 않았을 때의 기본값은 M3)

| 상태 | M3 [M3-state] | shadcn [SH-button] | Chakra [CH-button] |
|---|---|---|---|
| hover | 8% 오버레이 | `bg-primary/90` | `colorPalette.solid/90` |
| focus | 12% | 3px 링 50% | ring outside |
| pressed | 12% | (hover 와 같음) | — |
| dragged | 16% | — | — |
| disabled | 컨테이너 12% / 내용 38% | opacity 50% | opacity 50% |

모바일 우선 시스템은 hover 를 두지 않고 pressed 전용 토큰 + 축소를 써요 (관행).

---

## 1. Button

### 1.1 합의된 규칙

1. **화면당 가장 강한 버튼은 하나예요.** HIG: 가장 가능성 높은 액션 하나에만 prominent 스타일, 툴바도 primary 액션은 하나만 [HIG-btn][HIG-toolbar].
2. **위계는 크기가 아니라 스타일로 나눠요.** HIG: 선택지 여러 개를 같은 크기로 두고 선호하는 것만 더 강한 스타일로 [HIG-btn]. Solid + Weak, 또는 Outline 둘을 조합 (관행).
3. **강조 3단계**: 강(solid fill) · 중(약한 fill — tonal/secondary/subtle) · 약(outline/ghost/text). shadcn `default/secondary/outline/ghost/link` [SH-button], Chakra `solid/subtle/surface/outline/ghost/plain` [CH-button], M3 filled/tonal/outlined/elevated/text [M3-btn-doc].
4. **파괴적 액션은 따로 표시하고 기본 선택으로 두지 않아요.** shadcn `destructive` [SH-button]. HIG 는 파괴적 버튼에 primary role 을 주지 말라고 해요 — 사람들이 읽지 않고 누를 수 있어서 [HIG-btn]. 위험 채움은 삭제·초기화처럼 되돌릴 수 없는 작업에만, 주로 확인 대화상자 안에서 (관행).
5. **라벨은 동사로 시작하고 결과를 말해요.** HIG "Add to Cart" 처럼 동사로 시작 [HIG-btn], 알림 버튼은 1–2단어 [HIG-alert]. '다음' 이 아니라 '시작하기' 처럼 무엇을 하는지 (관행 · `ux-writing.md`).
6. **아이콘은 앞이나 뒤 중 한쪽에만 둬요.** 앞 = 의미 보조, 뒤 = chevron 같은 동작 보조 — 둘을 함께 쓰지 않아요 (관행). M3 도 아이콘은 라벨 앞 [M3-btn-doc].
7. **아이콘만 있는 버튼에는 접근성 라벨이 필수예요.** 꼭 필요할 때만 쓰고, 정사각 크기를 따로 둬요 (shadcn `size-9`/`icon`, Chakra `minW`=h) [SH-button][CH-button].
8. **로딩 상태는 버튼 안에서 보여 줘요.** HIG 는 바로 끝나지 않는 액션이면 버튼 안에 activity indicator 를 두라고 해요 [HIG-btn]. 스피너 14–18, 너비 유지 (관행).
9. **나란히 두는 버튼은 2개까지예요.** 3개 이상은 넘치는 액션을 icon-only 나 더보기로. 닫기 성격의 Weak + Solid 조합은 3:7 비율 (관행). HIG 알림은 버튼 최대 3개 [HIG-alert].

### 1.2 시스템마다 다른 값

| 시스템 | 크기별 높이 | 가로 패딩 | 반경 | 아이콘 | 글자 |
|---|---|---|---|---|---|
| M3 expressive [M3-bxs] | XS 32 · S 40 · M 56 · L 96 · XL 136 | 12 · 16 · 24 · 48 · 64 | round = full / square = 12·12·16·28·28 | 20 · 20 · 24 · 32 · 40 | label-large |
| shadcn [SH-button] | sm 32 · default **36** · lg 40 (xs 24) | 12 · 16 · 24 (아이콘 있으면 10/12/16) | `rounded-md` | 16 (xs 12) | 14 medium |
| Chakra [CH-button] | 2xs 24 · xs 32 · sm 36 · **md 40** · lg 44 · xl 48 · 2xl 64 | 8 · 10 · 14 · 16 · 20 · 20 · 28 | l2 = 4px | 14 · 16 · 16 · 20 · 20 · 20 · 24 | xs/sm/md/lg, medium |
| HIG | iOS 터치 최소 44×44pt [HIG-a11y]. 고정 높이 단계는 visionOS 만 공개: 28·32·44·52·64pt [HIG-btn] | — | 캡슐/라운드 사각 | SF Symbols | 대표 텍스트 스타일 |

정리
- 웹 대시보드 기본 높이는 **36–40** (shadcn 36, Chakra 40, M3 S 40).
- 모바일 하단 CTA 는 **52–56** (M3 M 56, 모바일 앱 관행 52 — `locale-ko.md`).
- 32 이하(M3 XS, shadcn sm)는 눈에 보이는 크기일 뿐이에요. 터치 영역은 따로 44–48 을 확보해요.

### 1.3 상태 체크리스트

- [ ] default (enabled)
- [ ] hover — 포인터 환경에서만 (shadcn `/90`, Chakra `/90`)
- [ ] pressed — 색을 바꾸거나 축소 (HIG 필수)
- [ ] focus-visible — 링 3px 또는 외곽 링
- [ ] disabled — 배경과 글자 모두 약하게, `pointer-events: none`. 이유를 알려야 하면 `aria-disabled` + 설명 [APG-btn]
- [ ] loading — 라벨 자리에 스피너. 너비는 유지하고 중복 클릭은 막아요
- [ ] (토글 버튼) selected — `aria-pressed`, 라벨은 상태가 바뀌어도 그대로 [APG-btn]
- [ ] invalid — shadcn `aria-invalid:border-destructive` [SH-button]

### 1.4 접근성·키보드

- `role=button` 이고 Enter 와 Space 로 실행해요 [APG-btn]. 토글은 `aria-pressed` 를 쓰고 라벨은 바꾸지 않아요 ("Mute" 그대로) [APG-btn]. 메뉴를 여는 버튼은 `aria-haspopup` [APG-btn].
- 실행한 뒤 포커스는 다이얼로그를 열었으면 다이얼로그 안으로, 닫았으면 원래 버튼으로 돌아가요 [APG-btn].

### 1.5 문구 규칙

- 동사로 시작하고 사용자 관점에서 결과를 써요. 같은 액션은 어디서나 같은 단어로 [HIG-btn].
- 1–2단어, 끝에 마침표 없음. 영어는 Title Case (HIG) [HIG-alert]. 한국어는 '~하기' 처럼 동사형으로 (`locale-ko.md`).
- macOS 에서 다른 창이나 뷰를 여는 버튼은 라벨 끝에 말줄임(…) [HIG-btn].
- 'OK/확인/다음' 처럼 모호한 라벨은 피해요 [HIG-alert].

### 1.6 안티패턴

- 브랜드 색 버튼을 여러 개 두는 것 (관행 · [HIG-btn])
- 앞뒤 아이콘을 동시에 쓰는 것 (관행)
- 버튼 3개 이상을 나란히 두는 것 — 큰 글씨 설정에서 잘려요 (관행)
- 크기로 위계를 나누는 것 [HIG-btn]
- 파괴적 액션을 primary 로 두는 것 [HIG-btn]
- Outline 버튼을 Solid 와 한 줄에 섞는 것 (관행)
- 커스텀 버튼에 press 상태가 없는 것 [HIG-btn]
- 액션 대신 정보나 선택 상태를 보여 주는 데 버튼을 쓰는 것 → Chip 을 써요 (관행)

---

## 2. Text field / Input

### 2.1 합의된 규칙

1. **라벨은 placeholder 와 따로 둬요.** HIG 는 placeholder 가 입력하면 사라지니 별도 라벨을 두라고 하고 [HIG-tf], MDC 는 hint 를 바깥 레이아웃에 두라고 해요 [M3-tf-doc]. 입력은 라벨·설명·에러를 담는 Field 안에서 써요 (관행). `components.md` §8 의 "플레이스홀더 통합" 은 항목이 1–2개인 짧은 폼에 한정하고, 그때도 접근성 라벨은 남겨요.
2. **테두리는 기본 1px, 포커스·에러 때 2px**: M3 outlined 1→2px (포커스 `primary`, 에러 `error`) [M3-otf]. shadcn 은 테두리 1px 에 링 3px [SH-input].
3. **에러는 색만으로 알리지 않아요.** M3 는 에러 상태에서 라벨·테두리·보조 텍스트·trailing 아이콘을 모두 `error` 로 바꿔요 [M3-otf]. 접근성 라벨이 달린 에러 메시지를 함께 보여 줘요 [M3-tf-doc].
4. **값이 있으면 Clear 버튼을 줘요**: HIG (트레일링 끝) [HIG-tf].
5. **형식이 정해진 값(전화번호·주민번호)은 칸을 나누지 말고 자동으로 포맷해요** (관행). 숫자는 formatter 와 맞는 키보드 타입을 써요 [HIG-tf].
6. **검증 시점**: 이메일은 다음 필드로 넘어갈 때, 아이디·비밀번호는 넘어가기 전에 [HIG-tf].
7. **비활성 / 읽기 전용을 구분해요**: 둘 다 배경이 약해지지만 읽기 전용은 글자를 보조 글자색으로 유지해 복사·확인할 수 있게 (관행).
8. **필드 너비는 예상 입력 길이에 맞춰요** [HIG-tf]. M3 기본 최대 너비 488dp, 라벨이 있으면 최소 88dp [M3-tf-doc].

### 2.2 시스템마다 다른 값

| 시스템 | 높이 | 가로 패딩 | 반경 | 글자 | 아이콘 |
|---|---|---|---|---|---|
| M3 outlined [M3-otf] | 56dp (미확인 — 토큰 파일에 height 없음) | — | extra-small 4 | body-large | 24 |
| shadcn [SH-input] | **36** (`h-9`) | 12 | `rounded-md` | 16 (모바일) / 14 (md 이상) | — |
| Chakra [CH-input] | 2xs 28 · xs 32 · sm 36 · **md 40** · lg 44 · xl 48 · 2xl 64 | 8 · 8 · 10 · 12 · 16 · 18 · 20 | l2 = 4px | xs·xs·sm·sm·md·md·lg | — |
| 모바일 앱 관행 | 48–52 (40 은 데스크톱 전용) | 14–16 | 8–12 | 16 | 20 |
| 여러 줄 입력 (관행) | 자동 높이 최소 3줄 / 고정이면 최소 2줄 + 최대 높이 필수 | | | | |

**모바일 입력 글자는 16px 이상**이에요. shadcn 은 모바일에서 `text-base`(16) 를 쓰고 md 이상에서만 14 로 줄여요 [SH-input]. iOS Safari 는 16px 미만 입력에 포커스하면 화면을 확대해요 (미확인 — 공식 문서 미조회).

### 2.3 상태 체크리스트

- [ ] enabled (빈 값 / 값 있음)
- [ ] hover (M3 hover outline 1px on-surface) [M3-otf]
- [ ] focused (2px 강조 테두리 또는 링)
- [ ] error / error + focused [M3-otf]
- [ ] disabled (글자·placeholder·아이콘 모두 disabled 색)
- [ ] read-only

### 2.4 접근성·키보드

- 보이는 라벨을 `<label for>` 나 `aria-labelledby` 로 연결하고, 보조·에러 텍스트는 `aria-describedby` 로 연결해요 (APG 공통 라벨 규칙 [APG-cb]). 에러는 `aria-invalid=true` (shadcn·Chakra 가 이 속성으로 스타일을 줘요 [SH-input]).
- Tab 순서는 사람이 기대하는 흐름을 따라가요 [HIG-tf].
- 앞뒤 아이콘이 버튼 역할을 하면 접근성 이름(contentDescription)이 필요하고, 터치 영역은 48 이상 [M3-tf-doc].

### 2.5 문구 규칙

- placeholder 에는 예시나 힌트만 ("Email"). 꼭 필요한 정보는 라벨이나 설명 텍스트에 [HIG-tf].
- 입력값이 하나면 한 번에 입력하게 해요. 2열 배치는 라벨과 값이 모두 짧을 때만, 간격을 넉넉히 (관행).

### 2.6 안티패턴

- placeholder 만 있고 라벨이 없는 것 [HIG-tf]
- 전화번호를 3칸으로 나누는 것 (관행)
- 모바일에서 40 짜리 작은 입력을 쓰는 것 (관행)
- 화면에 입력이 하나뿐인데 무거운 outline 상자를 쓰는 것 → 밑줄형(underline) 이 가벼워요 (관행)
- 필요하지 않은데 텍스트 필드를 보여 주는 것 [HIG-tf]

---

## 3. List row / Item

### 3.1 합의된 규칙

1. **한 줄 행의 최소 높이는 44–56.** M3 one-line 56 / two-line 72 / three-line 88 [M3-list]. HIG 터치 최소 44 [HIG-a11y]. 세로 패딩 12 + 제목 16 이면 대략 48 (관행).
2. **좌우 여백은 화면 거터와 같아요 (16).** M3 leading/trailing space 16 [M3-list]. shadcn Item 기본 `p-4`(16), sm `px-4 py-3` [SH-item].
3. **구조는 leading(아이콘·아바타·이미지) · 본문(제목 + 보조) · trailing(값·chevron·컨트롤)** — M3 leading/label/supporting/trailing [M3-list], shadcn ItemMedia/ItemContent/ItemTitle/ItemDescription/ItemActions [SH-item].
4. **보조 텍스트는 한 단계 약한 색과 작은 글자로.** shadcn description `text-muted-foreground` + `line-clamp-2` [SH-item]. M3 supporting `on-surface-variant` [M3-list]. 제목 16 / 보조 13 (관행).
5. **행 안에 컨트롤(체크·스위치)이 있으면 행 전체가 터치 영역이에요** (관행 · [M3-cb]).
6. **텍스트는 짧게, 길면 상세 화면으로** [HIG-list]. 잘리는 텍스트는 줄 수를 제한해요 (shadcn line-clamp-2) [SH-item].
7. **선택하면 피드백을 줘요** [HIG-list]. 전폭 행은 pressed 때 배경을 좌우 몇 px 안쪽으로 줄이고 작은 반경을 주는 방식도 있어요 (관행 · `principles.md` B8).

### 3.2 시스템마다 다른 값

| 항목 | M3 [M3-list] | shadcn [SH-item] | 모바일 앱 관행 |
|---|---|---|---|
| 행 높이 | 56 / 72 / 88 | 패딩으로 결정 (p 16 / py 12) | 패딩으로 결정 (py 12) |
| leading 아이콘 | 24 (expressive 20) | 미디어 32 (아이콘 박스), 이미지 40 | 22–24 |
| 아바타 | 40 | 40 | 32–40 |
| trailing 아이콘 | 24 | — | 18–20, 보조 글자색 |
| prefix 와 본문 간격 | 12 (between-space) | 16 (gap-4) / 10 | 12 |
| 제목 / 보조 | body-large / body-medium | 14 / 14 | 16 / 13 |
| 강조 행 | — | variant `muted` = `bg-muted/50` | 브랜드 약한 배경 |
| 구분선 | 1px, 좌우 16 들여쓰기 | variant outline = `border-border` | 1px 10–20% 또는 없음 |

### 3.3 상태 체크리스트

- [ ] default
- [ ] hover (링크 행: shadcn `hover:bg-accent/50`)
- [ ] pressed (투명 → 눌림 오버레이)
- [ ] focus-visible (shadcn 링 3px)
- [ ] selected / highlighted (브랜드 약한 배경)
- [ ] disabled (제목·보조·아이콘 모두 disabled 색)
- [ ] (M3) dragged [M3-list]

### 3.4 접근성

- 행 전체가 링크나 버튼이면 하나의 interactive 요소로 만들어요 (안에 또 버튼을 겹치지 않아요). 단일 선택 목록은 APG Listbox 패턴 (`listbox`/`option`/`aria-selected`) (미확인 — Listbox 페이지 미조회).
- 행 안 체크박스나 스위치의 라벨은 행 제목이 맡아요 (`aria-labelledby`) [APG-cb][APG-switch].

### 3.5 안티패턴

- 트레일링에 chevron 같은 컨트롤이 있는 표에 인덱스까지 다는 것 [HIG-list]
- info 버튼을 정보 보기 말고 다른 용도로 쓰는 것 [HIG-list]
- 체크박스 마크만 탭할 수 있는 것 (관행)

---

## 4. Card

> HIG 에는 Card 페이지가 없어요. 모바일 우선 시스템 중엔 Card 부품 자체를 두지 않는 곳도 있어요 — 여백과 구분선으로 충분하다는 판단이에요. 그래서 비교는 shadcn·M3·Chakra 세 시스템이에요.

### 4.1 합의된 규칙

1. **반경은 버튼·입력보다 한 단계 커요.** shadcn 버튼·입력 `rounded-md` → 카드 `rounded-xl` [SH-button][SH-card]. Chakra 버튼 l2(4) → 카드 l3(6) [CH-button][CH-card]. M3 카드 corner-medium 12 [M3-card].
2. **안쪽 여백은 16–24 로 일정하게.** shadcn 좌우 `px-6` 24, 세로 `py-6` 24, 섹션 사이 `gap-6` 24 [SH-card]. M3 모바일 카드 바깥 여백 8dp 권장 [M3-card-doc].
3. **구조는 header(제목 + 설명 + 액션) · content · footer.** shadcn CardHeader/Title/Description/Action/Content/Footer, 제목 `font-semibold leading-none`, 설명 `text-sm text-muted-foreground` [SH-card].
4. **분리는 테두리나 그림자 중 하나로.** shadcn `border` + `shadow-sm` [SH-card]. M3 elevated = `surface-container-low` + level1, outlined 는 stroke 1dp, filled 는 stroke 0 [M3-card][M3-card-doc]. Chakra 기본 variant `outline` [CH-card].
5. **카드 전체가 눌리면 접근성 액션을 줘요.** MDC 는 드래그하거나 재정렬할 수 있는 카드에 AccessibilityDelegate 로 대체 액션을 주라고 해요 [M3-card-doc].

### 4.2 시스템마다 다른 값

| | shadcn [SH-card] | M3 [M3-card][M3-card-doc] | Chakra [CH-card] |
|---|---|---|---|
| 반경 | `rounded-xl` | 12 | l3 = 6 |
| 패딩 | 24 | (미확인, 보통 16) | 사이즈별 (미확인) |
| 배경 | `--card` / `--card-foreground` | `surface-container-low` (elevated) | `bg.panel` (미확인) |
| 깊이 | `shadow-sm` + `border` | elevated 1dp / hover 2dp | outline 기본 |

### 4.3 상태 체크리스트 (눌리는 카드일 때)

- [ ] default
- [ ] hover (M3 hover level2) [M3-card]
- [ ] pressed / focus (M3 state layer 12%) [M3-state]
- [ ] dragged (level4) [M3-card]
- [ ] disabled (M3 별도 토큰) [M3-card]
- [ ] selected / checked (MDC checkedIcon 24dp, 여백 8dp) [M3-card-doc]

### 4.4 안티패턴

- 카드 안에 카드를 겹치는 것, 테두리·그림자·배경색을 한꺼번에 쓰는 것 (미확인 — 세 시스템 문서에 명시 없음, 디자인 관행 · `patterns.md` 3)
- 카드 전체가 링크인데 안에 또 버튼을 두는 것 (중첩 interactive. APG 일반 원칙, 미확인)

---

## 5. Chip / Tag (filter · choice · input · suggestion)

### 5.1 합의된 규칙

1. **Chip 은 액션이 아니라 '선택이나 상태 표시' 예요.** 액션 실행은 버튼, 정보 + 선택 표현은 칩이고 2개 이상 그룹으로 써요 (관행). M3 는 assist/filter/input/suggestion 4종이고 filter 는 콘텐츠를 거르는 태그예요 [M3-chip-doc].
2. **용도를 4가지로 나눠요** [M3-chip-doc]
   - **Filter**: 목록 조건을 켜고 끄기. 켜진 필터가 있으면 전체 해제 버튼을 보여 줘요 (관행).
   - **Choice / Selection**: 단일·다중 선택. 선택된 칩이 여러 개 보일 수 있으니 약한 선택 스타일(테두리 강조 + 약한 채움)이 나아요 (관행).
   - **Input**: 사용자가 입력한 값. 뒤에 Remove 버튼.
   - **Suggestion / Assist**: 제안 항목.
3. **높이는 32 근처예요.** M3 filter chip 32 [M3-fchip], MDC min height 32dp [M3-chip-doc]. 모바일 앱은 32 / 36 / 40 세 단계를 두기도 해요 (관행).
4. **칩 사이 간격은 8.** MDC chipSpacing 8dp [M3-chip-doc].
5. **선택 상태는 채움색이나 테두리를 바꾸고, 필요하면 체크 아이콘을 붙여요.** M3 선택 = `secondary-container` [M3-fchip]. 무채색 강한 채움 + 반전 글자, 또는 강한 테두리 + 약한 채움 (관행).
6. **칩을 탭처럼 쓰려면 탭 부품(칩형 탭)을 써요** — 생김새가 같아도 역할이 달라요 (관행 · `principles.md` E4).

### 5.2 시스템마다 다른 값

| | M3 [M3-fchip][M3-chip-doc] | Chakra Tag [CH-tag] | shadcn Badge [SH-badge] |
|---|---|---|---|
| 높이 | 32 (터치 48) | sm 18 · md 20 · lg 24 · xl 32 | 내용 + `py-0.5` (≈22) |
| 반경 | small 8 | l1 / l2 | full |
| 아이콘 | 18, close 18 | 12–18 | 12 |
| 테두리 | flat unselected 1px / selected 0 | — | outline variant |
| 비활성 | 내용 38% / 컨테이너 12% | — | — |

> shadcn 에는 Chip 이 없어요. 읽기 전용 표시는 Badge, 선택형은 Toggle/ToggleGroup (h 32/36/40) [SH-toggle] 으로 만들어요.

### 5.3 상태 체크리스트

- [ ] enabled · pressed · disabled × (unselected / selected) — 6조합 모두
- [ ] focus-visible
- [ ] (filter) 켜진 필터 개수와 전체 해제 버튼
- [ ] (input) remove 버튼과 그 접근성 이름 [M3-chip-doc]

### 5.4 접근성

- Filter / Choice 칩은 토글 버튼(`aria-pressed`)이나 체크박스·라디오 의미로 노출해요. 라벨은 상태가 바뀌어도 그대로 [APG-btn].
- Input 칩의 close 아이콘에는 접근성 이름(contentDescription)이 필요해요 [M3-chip-doc].

### 5.5 안티패턴

- 칩을 액션 버튼 대신 쓰는 것 (관행)
- 칩형 탭과 칩 필터를 같은 스타일로 같이 쓰는 것 → 서로 다른 스타일로 (관행)
- 앞 슬롯에 임의의 커스텀 요소를 넣는 것 — 왼쪽 여백 규칙이 깨져요 (관행)

---

## 6. Tabs / Segmented control

### 6.1 합의된 규칙

1. **Tabs 는 탐색, Segmented 는 조작이에요.** Tabs 는 다른 섹션으로 이동하고 아래 영역 전체를 바꿔요. Segmented 는 같은 데이터를 필터·정렬하거나 다른 방식으로 보는 것이고, 제어하는 콘텐츠 바로 위에 둬요 (관행). HIG: 메인 영역의 뷰 전환은 segmented 가 아니라 tab view 로 [HIG-seg].
2. **Segmented 는 2–4개, 많아도 5개.** HIG iPhone 에서 약 5개 이하, 넓은 화면 5–7 [HIG-seg]. 그보다 많으면 라디오 그룹이나 팝업 버튼 [HIG-toggle].
3. **Segmented 라벨은 짧은 명사** [HIG-seg]. 세그먼트 너비는 같게, 텍스트와 아이콘을 섞지 않아요 [HIG-seg].
4. **화면당 Segmented 는 하나** (관행).
5. **Line 탭의 선택 표시**: 아래 인디케이터 2–3px. M3 3px `primary` [M3-tab], MDC 2dp [M3-tab-doc], shadcn line variant `h-0.5`(2px) [SH-tabs].
6. **탭 높이는 40–48.** M3 48 (아이콘 + 라벨 72) [M3-tab][M3-tab-doc], Chakra 36 / 40 / 44 [CH-tabs], shadcn 리스트 36 [SH-tabs]. 모바일 앱 관행 40–44.
7. **꽉 채우는 탭(fill)은 5개까지.** 6개 이상이거나 라벨이 길면 내용 폭(hug) 또는 스크롤로 (관행). MDC 스크롤 탭 최소 너비 72dp, 최대 264dp [M3-tab-doc].
8. **알림 배지는 한 번에 한 탭에만** (관행).
9. **2단 탭은 1차 Line + 2차 Chip 으로 조합** (관행).

### 6.2 시스템마다 다른 값

| | M3 | shadcn | Chakra | HIG |
|---|---|---|---|---|
| Tabs 높이 | 48 / 72, 탭 패딩 12 [M3-tab][M3-tab-doc] | list 36, 안쪽 패딩 3, trigger `rounded-md` [SH-tabs] | sm 36 · md 40 · lg 44 [CH-tabs] | — |
| 인디케이터 | 3px [M3-tab] | 2px (line) / 흰 pill (default) [SH-tabs] | line 기본 [CH-tabs] | — |
| Segmented | outlined segmented 40, full, 1px [M3-seg] | Tabs default variant (`bg-muted` pill) 로 대신해요 [SH-tabs] | xs 24 · sm 32 · md 40 · lg 44 [CH-seg] | ≤5개 (iPhone) [HIG-seg] |

모바일 앱 관행의 Segmented: 아이템 최소 높이 34, 컨테이너 안쪽 4, 약한 무채색 띠 + 선택만 흰 채움 (`components.md` §7).

### 6.3 상태 체크리스트

- [ ] unselected (보조 글자색 / M3 `on-surface-variant`) [M3-tab]
- [ ] selected (본문 글자색 / `primary`)
- [ ] pressed
- [ ] focus-visible
- [ ] disabled
- [ ] (배지) notification

### 6.4 접근성·키보드 [APG-tabs]

- `tablist` > `tab` (`aria-selected`, `aria-controls`) ↔ `tabpanel` (`aria-labelledby`)
- Tab 키는 탭 목록으로 들어갔다가 다음 요소로 나가요 (목록 안에서는 Tab 으로 돌아다니지 않아요). ←/→ 로 이동하고 끝에서 처음으로 돌아가요. Home/End 는 선택 사항.
- 콘텐츠가 바로 뜨면 자동 활성화, 로딩이 있으면 Space/Enter 로 직접 활성화.
- Segmented 가 단일 선택이면 radiogroup 의미 (화살표로 이동하면서 선택) 로 노출할 수 있어요 [APG-radio].

### 6.5 안티패턴

- Segmented 로 화면 이동을 하는 것 [HIG-seg]
- 칩형 탭을 겹쳐 쓰는 것 (관행)
- 여러 탭에 동시에 배지를 다는 것 (관행)
- segmented 근처에 다른 포커스 요소를 붙여 두는 것 [HIG-seg]

---

## 7. Bottom sheet / Dialog (Alert dialog 포함)

### 7.1 합의된 규칙

1. **한 번에 하나만 띄워요** [HIG-sheet].
2. **Alert dialog 는 짧고 중요한 확인에만.** 정보만 전달하거나, 흔하고 되돌릴 수 있는 파괴 작업에는 띄우지 않아요 [HIG-alert]. 반드시 선택이 필요하거나 되돌릴 수 없는 액션에만, 액션은 닫기를 포함해 2개 이하 (관행). HIG 알림 버튼은 최대 3개 [HIG-alert].
3. **파괴적 확인에는 '취소' 를 꼭 둬요.** 파괴 버튼은 위험 스타일로 [HIG-alert].
4. **바텀시트 최대 높이는 화면의 80–90%.** shadcn Drawer `max-h-[80vh]` [SH-drawer]. 90% 를 넘으면 페이지로 (관행). Dialog 최대 80% (관행).
5. **바텀시트 최대 너비는 480–640dp** — M3 640dp [M3-bs-doc], 모바일 앱 관행 480. 다이얼로그는 shadcn `sm:max-w-lg`(512) [SH-dialog], 관행 480 / alert 272.
6. **크기를 바꿀 수 있는 시트에는 손잡이(grabber)를 둬요** [HIG-sheet]. 스냅 포인트가 있으면 handle 필수 (관행). shadcn handle 100×8 [SH-drawer], MDC handle 영역 최소 48dp [M3-bs-doc].
7. **닫기 방법**: 시트는 아래로 끌기와 바깥 탭으로 닫혀요 [HIG-sheet]. 실수하면 안 되는 작업(결제·복잡한 폼)이면 handle 을 없애고 상단 닫기 버튼을 둬요 (관행). Alert dialog 는 바깥 탭으로 닫히지 않고 명시적인 버튼으로만 (관행). → `spec-template.md` 표 5 의 "닫는 법 셋" 은 일반 시트 기준이고, 결제·경고 레이어는 그 예외를 표 5 에 적어요.
8. **상단 반경은 크게 (20–28).** M3 다이얼로그·시트 extra-large 28 [M3-dialog][M3-bs-doc]. 모바일 앱 관행 시트 24 / 다이얼로그 20.
9. **스크림(어두운 배경막)**: shadcn `bg-black/50` [SH-dialog]. `components.md` §12 는 20–30% 를 권해요 — 웹 라이브러리 기본값이 더 진해요.
10. **복잡하고 긴 흐름은 시트가 아니라 별도 화면으로** [HIG-sheet].

### 7.2 시스템마다 다른 값

| | M3 | shadcn | Chakra | HIG | 모바일 앱 관행 |
|---|---|---|---|---|---|
| 시트 상단 반경 | 28 [M3-bs-doc] | `rounded-t-lg` [SH-drawer] | l3 [CH-drawer] | 시스템 | 24 |
| 시트 패딩 | — | header·footer p 16 [SH-drawer] | — | — | 헤더 위 24 / 아래 16, 본문 좌우 16, 푸터 위 12 / 아래 16 |
| 시트 제목 / 설명 | — | — | — | — | 20–22 / 16 보조 글자 |
| 다이얼로그 반경 | 28 [M3-dialog] | `rounded-lg` [SH-dialog] | l3 = 6 [CH-dialog] | — | 20 |
| 다이얼로그 패딩 | — | p 24, gap 16 [SH-dialog] | — | — | 24 |
| 다이얼로그 너비 | — | `calc(100% - 2rem)`, sm 이상 512 [SH-dialog] | sm~full [CH-dialog] | — | 화면의 90%, max 480 |
| Alert 너비 / 제목 | — | — | — | 제목 2줄 이하 [HIG-alert] | 272–320 / 20 |
| 스냅 기본값 | — | — | — | medium / large detent [HIG-sheet] | 90 / 50 / 10% |
| 표면 | `surface-container-high` [M3-dialog] | `--background` | `bg.panel` | — | 떠 있는 표면 (`color-type.md`) |

### 7.3 상태 체크리스트

- [ ] 열림 / 닫힘 애니메이션 (shadcn fade + zoom 95%) [SH-dialog]
- [ ] 스크롤됨 — 스크롤되면 본문 위에 1px 구분선, 아래에 페이드 (관행)
- [ ] 키보드가 올라온 상태 — 시트 높이를 다시 계산해요
- [ ] 스냅 포인트별 높이
- [ ] 닫기 버튼 / handle 있음·없음
- [ ] 긴 버튼 라벨 → 버튼을 세로로 쌓아요 (관행)

### 7.4 접근성·키보드 [APG-dialog]

- `role=dialog` (경고는 `alertdialog`) + `aria-modal=true` + `aria-labelledby` (제목). 설명이 단순하면 `aria-describedby`.
- 열리면 포커스가 안으로 들어가요. Tab 과 Shift+Tab 은 다이얼로그 안에서만 돌고, Esc 로 닫혀요. 닫으면 연 버튼으로 포커스가 돌아가요.
- HIG: 외부 키보드에서 Esc 나 ⌘. 로 알림을 취소할 수 있어요 [HIG-alert]. 의도적으로 고른 파괴 작업(휴지통 비우기)의 확인 버튼에는 destructive 스타일을 주지 않아요 [HIG-alert].

### 7.5 문구 규칙

- 제목은 무슨 일이 왜 일어났는지 구체적으로 2줄 안에. "Error" 처럼 정보 없는 제목은 쓰지 않아요 [HIG-alert].
- 본문은 값을 더할 때만 쓰고, 버튼을 설명하지 않아요 [HIG-alert].
- 버튼은 결과를 말하는 동사 (삭제·나가기). 'OK' 는 정보 알림에서만, 취소 버튼은 '취소(Cancel)' [HIG-alert]. 한국어 화면은 보조 버튼도 무엇을 하는지 ("그대로 두기") 쓰는 쪽이 나아요 (`ux-writing.md`).
- 시트 제목과 설명은 짧게 (관행).

### 7.6 안티패턴

- 앱을 시작하자마자 알림을 띄우는 것 [HIG-alert]
- 스크롤되는 알림 [HIG-alert]
- Cancel·Done·Back 세 버튼을 동시에 두는 것 [HIG-sheet]
- 확인 대화상자를 화면마다 임의로 커스텀하거나 버튼 정렬을 바꾸는 것 (관행)
- 바텀시트 안에서 긴 스크롤 (관행)
- 선택지 메뉴를 Alert 로 만드는 것 → 메뉴 시트나 액션 시트 [HIG-alert]

---

## 8. Toast / Snackbar

### 8.1 합의된 규칙

1. **화면에는 하나씩, 나머지는 큐에.** MDC 는 한 번에 하나만 보여 줘요 [M3-sb-doc]. sonner 는 기본으로 최대 3개를 쌓아 보여 줘요 [SONNER]. 웹 라이브러리 기본값과 모바일 가이드가 갈리는 지점이에요 — 모바일은 1개.
2. **표시 시간은 4–5초.** sonner 4000ms [SONNER], Radix 5000ms [RADIX-toast]. 메시지가 길면 늘리고, 누르고 있거나 호버하면 멈춰요 (관행).
3. **낮은 심각도의 결과 알림에만.** 결정이 필요하면 다이얼로그나 시트, 계속 보여야 하는 경고는 배너, 긴 안내는 콜아웃으로 (관행).
4. **액션은 최대 1개, 1–2단어로 구체적으로** ('되돌리기', '목록 보기'. '확인·취소' 는 쓰지 않아요). 추가나 삭제 뒤에는 '되돌리기' (관행).
5. **위치는 하단 중앙, 안전 영역과 FAB 위** (관행). MDC 는 anchor view 를 지원해요 [M3-sb-doc].
6. **색은 반전 표면 (어두운 바탕 + 밝은 글자)** — M3 `inverse-surface` / `inverse-on-surface`, 액션 `inverse-primary` [M3-sb]. shadcn/sonner 는 반대로 `--popover` 표면 [SH-sonner], Chakra 도 `bg.panel` + 그림자 xl [CH-toast].

### 8.2 시스템마다 다른 값

| | M3 [M3-sb] | Chakra [CH-toast] | shadcn/sonner [SH-sonner][SONNER] | 모바일 앱 관행 |
|---|---|---|---|---|
| 높이 | 1줄 48 / 2줄 68 | 내용 (py 16) | 내용 | 최소 44 |
| 최대 너비 | — | — | 356 | 464 |
| 반경 | extra-small 4 | l2 = 4 | `--radius` | 8 |
| 패딩 | — | 16 / 16 / 24 | — | 10–12, 바깥 8 |
| 메시지 글자 | body-medium | — | — | 14 |
| 아이콘 | 24 | — | — | 24, 성공·위험 역할 색 |
| 액션 터치 | — | — | — | 최소 높이 44 |

### 8.3 상태 체크리스트

- [ ] default / 성공 / 위험 (아이콘 색만 바뀌어요)
- [ ] 액션 있음·없음, 1줄·2줄 (줄바꿈 때 아이콘과 버튼은 세로 가운데 정렬)
- [ ] 진입 / 퇴장, 스와이프로 닫기 [RADIX-toast]
- [ ] 누르는 동안 일시정지

### 8.4 접근성

- 포커스를 가져가지 않는 상태 메시지는 `role=status` (성공·진행), 에러는 `role=alert` [WCAG-413].
- Radix: 사용자 액션의 결과면 `foreground`, 백그라운드 작업이면 `background` 유형. F8 핫키로 토스트 영역으로 이동. 스크린리더용 라벨이 필요해요 [RADIX-toast].
- 4–5초 안에 눌러야 하는 액션은 키보드나 보조기기 사용자가 놓칠 수 있어요. 중요한 액션은 토스트에만 두지 않아요 (미확인 — 디자인 관행).

### 8.5 문구 규칙 (관행)

- 명사 + 동사로 결과를 먼저 ("사진을 저장했어요").
- 한 문장이면 마침표를 빼고, 두 문장 이상이면 모든 문장에 마침표.
- 긍정문으로. 이중 부정은 쓰지 않아요.

### 8.6 안티패턴

- 토스트 여러 개를 동시에 쌓는 것 (모바일)
- 결정을 요구하는 것, 영구 경고나 긴 텍스트를 넣는 것
- '확인' 같은 모호한 액션 라벨

---

## 9. Selection controls — Checkbox / Radio / Switch

### 9.1 합의된 규칙

1. **고르는 기준**
   - **Switch**: 바로 적용되는 독립 설정 (저장 버튼 없음) [M3-switch-doc].
   - **Checkbox**: 저장 같은 확정 액션이 따로 있을 때, 여러 개 선택, 부모-자식 관계 [HIG-toggle].
   - **Radio**: 서로 배타적인 선택. 5개를 넘으면 드롭다운이나 팝업 [HIG-toggle][M3-radio-doc].
2. **부모 체크박스는 일부만 선택되면 indeterminate(mixed)** [APG-cb][M3-cb-doc].
3. **라벨까지 포함해 터치 영역**이에요. 리스트에서는 행 전체 (관행). M3 상태 레이어 40 + min touch target [M3-cb][M3-radio][M3-switch].
4. **비활성일 때는 라벨도 비활성 색으로** (관행).
5. **스위치 라벨은 상태가 바뀌어도 그대로** [APG-switch]. 상태 차이는 눈에 확실히 보여야 해요 [HIG-toggle].
6. **iOS 에서 switch 는 리스트 행 안에서만** 쓰고, 리스트 밖에서는 토글 버튼 [HIG-toggle].
7. **마크 크기는 16–24** (아래 표).

### 9.2 시스템마다 다른 값

| | Checkbox 마크 | Radio 마크 | Switch 트랙(W×H) / thumb | 행 높이 |
|---|---|---|---|---|
| M3 | 18, 반경 2, 미선택 테두리 2px, 상태 레이어 40 [M3-cb] | 20, 상태 레이어 40 [M3-radio] | 52×32 / 미선택 16 · 선택 24 · 눌림 28, 상태 레이어 40 [M3-switch] | min touch target [M3-cb-doc] |
| shadcn | 16, 반경 4 [SH-checkbox] | 16, 안쪽 점 8 [SH-radio] | 32×18.4 / 16 (sm 24×14 / 12) [SH-switch] | — |
| Chakra | xs 12 · sm 16 · md 20 · lg 24, 반경 l1 [CH-checkmark] | (미확인) | md 40×20 (xs 24×12, sm 32×16, lg 48×24) [CH-switch] | — |
| HIG | macOS 체크박스·라디오 | — | iOS 시스템 스위치 (51×31pt, 미확인) | 터치 44 [HIG-a11y] |
| 모바일 앱 관행 | 20 · 24, 반경 4 | 20 · 24, 안쪽 점 8–12 | 52×32 / 26 (작은 크기 38×24 / 20) | 최소 32–36 + 행 전체 터치 |

체크박스 모양은 둘로 나눠 쓰기도 해요: **상자형**(필수이고 사용자가 꼭 인지해야 할 항목)과 **체크만 있는 형**(선택 사항, 3개 이하) (관행).

### 9.3 상태 체크리스트

- [ ] unchecked / checked / indeterminate (checkbox)
- [ ] × enabled / pressed / disabled
- [ ] focus-visible (shadcn 링 3px) [SH-checkbox]
- [ ] invalid (shadcn `aria-invalid:border-destructive`, M3 errorAccessibilityLabel) [SH-checkbox][M3-cb-doc]
- [ ] 선택 색 tone: 브랜드 vs 무채색 — 포인트를 아끼려면 무채색 기본 (관행)

### 9.4 접근성·키보드

- Checkbox: Space 로 토글, `aria-checked` true/false/mixed, 그룹은 `role=group` + `aria-labelledby` [APG-cb].
- Radio: Tab 으로 들어가면 선택된 항목(없으면 첫 항목)에 포커스. 화살표로 이동하면서 바로 선택하고, Space 로 선택. `radiogroup` > `radio` [APG-radio].
- Switch: Space (Enter 는 선택 사항), `role=switch` + `aria-checked` [APG-switch].

### 9.5 문구 규칙

- 라벨은 켜졌을 때의 상태를 설명해요 ("알림 받기"). 그룹 관계가 분명하지 않으면 그룹 제목 [HIG-toggle].
- 버튼처럼 동작하는 토글에 목적을 설명하는 라벨을 따로 붙이지 않아요 [HIG-toggle].

### 9.6 안티패턴

- 바로 적용되지 않는 곳에 Switch 를 쓰는 것 [M3-switch-doc]
- '전체 선택' 을 Switch 로 만드는 것 (관행)
- 체크박스를 스위치로 바꾸는 것 (macOS) [HIG-toggle]
- 라디오가 너무 많은 것 [HIG-toggle]
- 마크만 탭할 수 있는 것 (관행)

---

## 10. Top app bar / Navigation bar

### 10.1 합의된 규칙

1. **높이는 56–64.** M3 small 64 [M3-appbar], 모바일 앱 관행 56. HIG iOS 내비게이션 바 44pt (미확인 — navigation-bars 문서 수신 실패).
2. **구성은 leading(뒤로 / 닫기) · 제목 · trailing 액션** [HIG-toolbar].
3. **뒤로(<)와 닫기(X)를 구분해요.** 뒤로는 이전 화면(입력 유지), 닫기는 레이어나 플로우 종료(입력이 버려질 수 있음) (관행). HIG 도 표준 Back / Close 버튼을 쓰라고 해요 [HIG-toolbar].
4. **trailing 아이콘은 2개 권장, 최대 3개, 텍스트 버튼은 1개.** 넘치면 '더보기 + 메뉴' (관행). HIG 도 과밀을 피하고 More 메뉴를 쓰라고 해요 [HIG-toolbar].
5. **제목은 한 줄로 짧게.** HIG 15자 미만 [HIG-toolbar]. 넘치면 한 줄 + 말줄임. 창 제목에 앱 이름을 쓰지 않아요 [HIG-toolbar].
6. **아이콘은 24** (M3 leading/trailing 24) [M3-appbar]. 테두리 없는 시스템 심볼 [HIG-toolbar].
7. **스크롤하면 표면을 바꿔요.** M3 `surface` → `surface-container` [M3-appbar]. 이미지 위에선 투명 + 위쪽 35% 안팎 검정 그라디언트 (관행).
8. **툴바의 주요 액션(Done / Submit)은 하나만 prominent 로** [HIG-toolbar].

### 10.2 시스템마다 다른 값

| | M3 [M3-appbar] | HIG | 모바일 앱 관행 |
|---|---|---|---|
| 높이 | 64 (검색 56) | 44pt (미확인) | 56 |
| 가로 패딩 | — | — | 4–8 (아이콘 터치 영역이 여백을 겸해요) |
| 제목 | title-large | 15자 미만 [HIG-toolbar] | 18 (부제목 있으면 16 + 12) |
| 표면 | `surface`, 스크롤 시 `surface-container` | 반투명 재질, 배경 줄이기 [HIG-toolbar] | 기본 표면 / 투명 + 그라디언트 |
| 플랫폼 관례 | center-aligned 변형 | 가운데 제목 | iOS 가운데 / Android 왼쪽 |

### 10.3 상태 체크리스트

- [ ] 루트 화면 (뒤로 없음, 핵심 액션) vs 2-depth 이상 (뒤로 또는 닫기)
- [ ] 스크롤 0 / 스크롤됨
- [ ] 투명 (이미지 위) / 불투명
- [ ] 제목 말줄임
- [ ] 아이콘 배지

### 10.4 접근성

- 아이콘 버튼마다 접근성 이름이 필요해요 (뒤로·닫기·검색). 터치 영역 44–48 [HIG-a11y][M3-chip-doc].
- 화면 제목은 heading 으로 노출해요 (미확인 — APG 페이지 미조회).

### 10.5 안티패턴

- 액션 아이콘이 많아 제목을 가리는 것 (관행)
- 모달에 뒤로 아이콘을 쓰는 것, 또는 그 반대 (관행)
- 툴바 배경과 아이콘을 같은 색 계열로 칠하는 것 [HIG-toolbar]

---

## 11. 토큰 역할 이름 대응표

같은 역할이 시스템마다 어떤 이름인지 정리했어요. 화면을 설계할 때는 **역할 이름(첫 열)** 으로 생각하고, 출력할 때 대상 시스템 이름으로 바꿔요. 첫 열은 `color-type.md` 의 기본 팔레트 역할과 같은 말이에요.

| 역할 | shadcn [SH-*] | M3 [M3-*] | Chakra [CH-sem] | HIG |
|---|---|---|---|---|
| 브랜드 채움 (brand solid) | `--primary` | `primary` | `colorPalette.solid` | accent / tint (미확인) |
| 브랜드 위 글자 (brand contrast) | `--primary-foreground` | `on-primary` | `colorPalette.contrast` | — |
| 강한 중립 채움 (neutral solid · CTA) | (`--primary` 가 겸해요, 기본 테마가 무채색) | `inverse-surface` (유사) | `gray.solid` | — |
| 약한 채움 (neutral weak · 보조 버튼·칩) | `--secondary` / `--secondary-foreground` | `secondary-container` / `on-secondary-container` | `colorPalette.subtle` + `colorPalette.fg` | gray / tinted 버튼 (미확인) |
| hover·pressed 오버레이 | `--accent` / `--accent-foreground` | state layer 8 / 12% | `colorPalette.muted` | — |
| 기본 글자 | `--foreground` | `on-surface` | `fg` | label (미확인) |
| 보조 글자 | `--muted-foreground` | `on-surface-variant` | `fg.muted` | secondaryLabel (미확인) |
| 더 약한 글자 | (`--muted-foreground`) | — | `fg.subtle` | tertiaryLabel (미확인) |
| placeholder | `--muted-foreground` | `on-surface-variant` | `fg.subtle` (미확인) | placeholderText (미확인) |
| 페이지 표면 (layer default) | `--background` | `surface` | `bg` | systemBackground (미확인) |
| 낮은 표면 (카드 · basement) | `--card` / `--muted` | `surface-container-low` | `bg.subtle` / `bg.muted` | secondarySystemBackground (미확인) |
| 떠 있는 표면 (floating · 다이얼로그·시트) | `--popover` / `--background` | `surface-container-high` | `bg.panel` | — |
| 기본 테두리·구분선 | `--border` | `outline-variant` (미확인) | `border` | separator (미확인) |
| 입력 테두리 | `--input` | `outline` | `border` / `border.emphasized` | — |
| 입력 포커스 테두리 | `--ring` | `primary` | `colorPalette.focusRing` | — |
| 포커스 링 | `--ring` (50%, 3px) | (focus indicator, 미확인) | `colorPalette.focusRing` | — |
| 위험 채움 (critical solid) | `--destructive` / 흰 글자 | `error` / `on-error` | `red.solid` / `fg.error` (미확인) | systemRed |
| 위험 글자·테두리 | `--destructive` (`aria-invalid`) | `error` | `fg.error` / `border.error` | systemRed |
| 성공 / 정보 / 경고 | (기본 없음) | (기본 없음) | `fg.success` / `fg.info` / `fg.warning` | systemGreen 등 (미확인) |
| 비활성 | opacity 50% | `on-surface` 12% / 38% | `layerStyle: disabled` (opacity 0.5) | — |
| 스크림 | `bg-black/50` | `scrim` (미확인) | `blackAlpha` (미확인) | — |
| 반전 표면 (토스트) | `--popover` (반전 안 함) | `inverse-surface` / `inverse-on-surface` / `inverse-primary` | `bg.inverted` / `fg.inverted` | — |
| 브랜드 약한 배경 (brand weak · 강조 행) | — | `primary-container` (미확인) | `colorPalette.subtle` | — |

명명 패턴 요약
- **역할 × 강도 형**(이 skill 의 기본): `{배경|글자|선}.{역할}-{강도}`. 역할 = brand / neutral / critical / positive / warning / informative, 강도 = solid / weak / contrast, 상태 접미사 `-pressed`. 채움 위 글자는 `{역할}-contrast`. 상세는 `color-type.md`.
- **shadcn**: `--{role}` / `--{role}-foreground` 쌍 + `--border` / `--input` / `--ring` / `--radius` [SH-*].
- **M3**: `{role}` / `on-{role}`, `{role}-container` / `on-{role}-container`, `surface-container-{lowest…highest}`, `inverse-*` [M3-*].
- **Chakra**: `{bg|fg|border}.{DEFAULT|subtle|muted|emphasized|inverted|panel|error…}` + 팔레트 슬롯 `colorPalette.{solid|contrast|fg|subtle|muted|emphasized|focusRing}` [CH-sem].

---

## 12. 디자인 시스템이 없을 때 기본값 (한 장 요약)

시스템이 정해지지 않았을 때 쓰는 값이에요. 출처가 둘 이상 겹치는 값만 골랐어요. `spec-template.md` 표 0·2 를 채울 때 이 표에서 시작해요.

| 부품 | 모바일 기본 | 데스크톱 기본 | 반경 | 근거 |
|---|---|---|---|---|
| CTA 버튼 | 52–56 높이, 전체 너비 | 40 | 8–12 / full | M3 M 56, 모바일 관행 52 / shadcn·Chakra·M3 S 40 |
| 보조 버튼 | 40 | 36 | 8 | 모바일 관행 40 / shadcn 36 |
| 입력 | 48–52, 글자 16 | 36–40 | 8–12 | M3 56, 모바일 관행 52 / shadcn 36, Chakra 40 |
| 리스트 행 | 최소 48–56, 좌우 16 | 같음 | 0 | M3 56, py 12 + 거터 16 |
| 칩 | 32, 간격 8 | 32 | full / 8 | M3 32, chipSpacing 8 |
| 탭 | 44–48, 인디케이터 2–3px | 36–40 | — | M3 48, Chakra 44 / shadcn 36 |
| Segmented | 2–4개, 34–40 | 같음 | full | HIG, M3 40 |
| 바텀시트 | 최대 높이 90%, 최대 너비 480–640, 상단 반경 24–28 | 다이얼로그 최대 480–512 | 20–28 | M3, shadcn |
| Alert | 액션 2개 이하, 너비 272–320 | — | 20–28 | HIG, 관행 |
| 토스트·스낵바 | 1개씩, 4초, 액션 1개, 최소 44–48 | 최대 3개 쌓기 (sonner) | 4–8 | M3, sonner |
| 체크·라디오 | 마크 20–24, 행 전체 터치 | 16–18 | 4 / full | M3, shadcn |
| 스위치 | 52×32 | 32×18 – 40×20 | full | M3 / shadcn·Chakra |
| 상단 바 | 56, 아이콘 24, trailing ≤2 (최대 3) | 64 | 0 | M3, 관행 |
| 터치 영역 | 44–48 | 24 이상 (WCAG AA) | — | HIG, M3, WCAG |

---

## 출처

shadcn/ui (registry new-york-v4)
- [SH-button] https://ui.shadcn.com/r/styles/new-york-v4/button.json
- [SH-input] https://ui.shadcn.com/r/styles/new-york-v4/input.json
- [SH-item] https://ui.shadcn.com/r/styles/new-york-v4/item.json
- [SH-card] https://ui.shadcn.com/r/styles/new-york-v4/card.json
- [SH-badge] https://ui.shadcn.com/r/styles/new-york-v4/badge.json
- [SH-toggle] https://ui.shadcn.com/r/styles/new-york-v4/toggle.json
- [SH-tabs] https://ui.shadcn.com/r/styles/new-york-v4/tabs.json
- [SH-dialog] https://ui.shadcn.com/r/styles/new-york-v4/dialog.json
- [SH-drawer] https://ui.shadcn.com/r/styles/new-york-v4/drawer.json
- [SH-sonner] https://ui.shadcn.com/r/styles/new-york-v4/sonner.json
- [SH-checkbox] https://ui.shadcn.com/r/styles/new-york-v4/checkbox.json
- [SH-radio] https://ui.shadcn.com/r/styles/new-york-v4/radio-group.json
- [SH-switch] https://ui.shadcn.com/r/styles/new-york-v4/switch.json
- [SH-*] 위 파일 전체의 CSS 변수 이름

Material Design 3
- [M3-shape] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-sys-shape.scss
- [M3-state] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-sys-state.scss
- [M3-bxs] https://github.com/material-components/material-web/blob/main/tokens/versions/latest/sass/_md-comp-button-xsmall.scss (같은 폴더의 -small / -medium / -large / -xlarge)
- [M3-fb] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-filled-button.scss
- [M3-btn-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/CommonButton.md
- [M3-otf] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-outlined-text-field.scss
- [M3-tf-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/TextField.md
- [M3-list] https://github.com/material-components/material-web/blob/main/tokens/versions/latest/sass/_md-comp-list.scss
- [M3-card] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-elevated-card.scss
- [M3-card-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/Card.md
- [M3-fchip] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-filter-chip.scss
- [M3-chip-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/Chip.md
- [M3-tab] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-primary-navigation-tab.scss
- [M3-tab-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/Tabs.md
- [M3-seg] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-outlined-segmented-button.scss
- [M3-dialog] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-dialog.scss
- [M3-bs-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/BottomSheet.md
- [M3-sb] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-snackbar.scss
- [M3-sb-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/Snackbar.md
- [M3-cb] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-checkbox.scss
- [M3-cb-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/Checkbox.md
- [M3-radio] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-radio-button.scss
- [M3-radio-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/RadioButton.md
- [M3-switch] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-switch.scss
- [M3-switch-doc] https://github.com/material-components/material-components-android/blob/master/docs/components/Switch.md
- [M3-appbar] https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-comp-top-app-bar-small.scss (latest/sass/_md-comp-app-bar-small.scss 도 64)
- [M3-*] 위 토큰 파일들의 `md-sys-color` 역할 이름
- (참고, 본문 수신 실패) https://m3.material.io/components

Chakra UI v3 (github.com/chakra-ui/chakra-ui, `packages/react/src/theme`)
- [CH-button] [CH-input] [CH-tag] [CH-tabs] [CH-switch] [CH-checkmark] [CH-seg] [CH-toast] [CH-dialog] [CH-drawer] [CH-card] — https://github.com/chakra-ui/chakra-ui/blob/main/packages/react/src/theme/recipes/<name>.ts (button · input · tag · tabs · switch · checkmark · segment-group · toast · dialog · drawer · card)
- [CH-radii] https://github.com/chakra-ui/chakra-ui/blob/main/packages/react/src/theme/semantic-tokens/radii.ts + …/tokens/radius.ts
- [CH-sem] https://github.com/chakra-ui/chakra-ui/blob/main/packages/react/src/theme/semantic-tokens/colors.ts
- [CH-layer] https://github.com/chakra-ui/chakra-ui/blob/main/packages/react/src/theme/layer-styles.ts

Apple Human Interface Guidelines
- [HIG-btn] https://developer.apple.com/design/human-interface-guidelines/buttons
- [HIG-a11y] https://developer.apple.com/design/human-interface-guidelines/accessibility
- [HIG-tf] https://developer.apple.com/design/human-interface-guidelines/text-fields
- [HIG-list] https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- [HIG-sheet] https://developer.apple.com/design/human-interface-guidelines/sheets
- [HIG-alert] https://developer.apple.com/design/human-interface-guidelines/alerts
- [HIG-toggle] https://developer.apple.com/design/human-interface-guidelines/toggles
- [HIG-seg] https://developer.apple.com/design/human-interface-guidelines/segmented-controls
- [HIG-toolbar] https://developer.apple.com/design/human-interface-guidelines/toolbars
- (수신 실패) https://developer.apple.com/design/human-interface-guidelines/navigation-bars

Radix · WAI-ARIA APG · WCAG · 라이브러리
- [APG-btn] https://www.w3.org/WAI/ARIA/apg/patterns/button/
- [APG-cb] https://www.w3.org/WAI/ARIA/apg/patterns/checkbox/
- [APG-radio] https://www.w3.org/WAI/ARIA/apg/patterns/radio/
- [APG-switch] https://www.w3.org/WAI/ARIA/apg/patterns/switch/
- [APG-tabs] https://www.w3.org/WAI/ARIA/apg/patterns/tabs/
- [APG-dialog] https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/
- [WCAG-258] https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
- [WCAG-255] https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html (44×44 — 본문 직접 확인은 못 했지만 SC 원문 값)
- [WCAG-413] https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html
- [RADIX-toast] https://github.com/radix-ui/website/blob/main/data/primitives/docs/components/toast.mdx (duration 5000, hotkey F8, type foreground/background)
- [SONNER] https://github.com/emilkowalski/sonner/blob/main/src/index.tsx (TOAST_LIFETIME 4000, VISIBLE_TOASTS_AMOUNT 3, TOAST_WIDTH 356)
