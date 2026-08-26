---
category: __CATEGORY__              # 파일명과 일치 (kebab-case)
applies_to: [code]                  # code | pr | commit | review (필요한 것 다중 선택)
paths:                              # 이 룰이 적용될 파일 글롭 — **비우면 자동 주입이 안 돼요**
  - "**/*.__EXT__"                  # 편집 대상이 여기 매칭되면 훅이 이 파일 경로를 주입
                                    # (pre-edit/spirit-rules-inject.sh)
# adr: .ax/docs/adr/NNNN-*.md           # 결정 근거 ADR (선택)
---

# __Category Title__

> 이 카테고리에 우리 팀의 룰을 추가하세요.
> 룰 작성법: `.ax/docs/reference/rules-tokens.md`

<!--
파일 사용법:
  1. 새 룰 = `## SP-<PREFIX>-<NNN>: <한 줄 제목>` 헤더로 시작
  2. ID는 카테고리 안에서 sequential (001, 002, ...)
  3. PREFIX는 카테고리 prefix 4자 이내 (예: SEC, NAMING, ERR)
  4. 자동 검출 가능하면 `검출 패턴:` 라인에 regex
  5. 결정 근거 있으면 `<!-- adr: .ax/docs/adr/NNNN-*.md -->` 코멘트
  6. doctor §3.7 spirit lint 로 검증 (헤더 형식 + SP-* 토큰 중복)
-->

## SP-__PREFIX__-001: <첫 번째 룰 제목>

<룰 본문을 동사 형태로 작성하세요 — "X는 Y한다", "X 금지" 등>

✅ <좋은 예>
❌ <나쁜 예>

<!-- 검출 패턴: <regex> -->
<!-- adr: .ax/docs/adr/NNNN-*.md -->

---

## SP-__PREFIX__-002: <두 번째 룰 — 필요 시>

...
