---
module: __MODULE_NAME__
keywords: [__keyword1__, __keyword2__, __한글_동의어__]
applies_to: [code, pr, review]      # code 가 있어야 편집 시점에 주입돼요 (pr/review 는 표시용)
paths:                              # 이 모듈의 소스 글롭 — **비우면 자동 주입이 안 돼요**
  - "__module/src/path__/**"        # 편집 대상이 여기 매칭되면 훅이 이 파일 경로를 주입
                                    # (pre-edit/module-rules-inject.sh)
adr:                                # 이 모듈의 결정 근거 ADR (선택) — 주입 시 같이 가리켜요
  - .ax/docs/adr/NNNN-<slug>.md
---

# __Module Name__ — 도메인 룰

> root CLAUDE.md의 비협상 룰 + `.ax/spirit/rules/`의 카테고리별 컨벤션 위에 쌓는 **모듈 특화 가이드**.
> triage가 사용자 메시지에서 위 `keywords`를 매칭하면 자동 컨텍스트 주입.

<!--
파일 사용법:
  1. frontmatter의 keywords를 grep 매칭 가능한 단어로 채우기 (영문 + 한글 + 동의어)
  2. 새 룰 = `## SP-<MODULE_PREFIX>-<NNN>: <한 줄 제목>` 헤더로 시작
  3. ID는 모듈 안에서 sequential (001, 002, ...)
  4. MODULE_PREFIX는 4자 이내 (예: PAY, ORD, AUTH)
  5. 자동 검출 가능하면 `검출 패턴:` 라인에 regex
  6. 결정 근거 있으면 `<!-- adr: .ax/docs/adr/NNNN-*.md -->` 코멘트
-->

## SP-__PREFIX__-001: <첫 번째 룰 제목 — 동사 형태>

<룰 본문 — "X는 Y한다", "X 금지" 등>

✅ <좋은 예>
❌ <나쁜 예>

<!-- 검출 패턴: <regex> -->
<!-- adr: .ax/docs/adr/NNNN-*.md -->

---

## SP-__PREFIX__-002: <두 번째 룰 — 필요 시>

...
