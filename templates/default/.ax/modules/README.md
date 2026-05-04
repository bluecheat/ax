# Module Rules — Layer 2

> 모듈별 도메인 룰. root CLAUDE.md는 얇게 유지하고, 모듈 특화 컨벤션은 여기에 보관.

## 왜 root CLAUDE.md 안에 안 두나

모노레포에서 모든 모듈 룰을 root CLAUDE.md에 쌓으면:
- 한 모듈만 작업해도 모든 모듈 룰이 컨텍스트에 들어감 (토큰 낭비)
- 어느 모듈 룰인지 grep해도 안 보임
- 룰 추가 시 root CLAUDE.md가 비대화

대신 `.ax/modules/<name>/rules.md` 에 분산하면:
- triage가 사용자 메시지의 도메인 키워드 매칭해서 *해당 모듈 룰만* 컨텍스트에 주입
- 한 곳(`.ax/modules/`)에 모든 모듈 룰이 모여 검색·관리 편함
- root CLAUDE.md는 얇게 유지

## 구조

```
.ax/modules/
  ├── README.md                 # 이 파일
  ├── payment/
  │   └── rules.md
  ├── order/
  │   └── rules.md
  └── ...
```

> 모듈 룰의 **템플릿**은 인스턴스 디렉토리 안이 아니라 `.ax/_templates/module/rules.md` 에 별도로 둬요 (`_templates/spec/`, `_templates/adr/` 와 동일한 패턴 — 인스턴스와 템플릿 분리).

## 파일 형식

각 `rules.md` 파일은 frontmatter + 본문:

```markdown
---
module: payment
keywords: [payment, refund, settlement, billing, 결제, 환불, 정산]
applies_to: [code, pr, review]
---

# Payment — 도메인 룰

## SP-PAY-001: <첫 번째 룰>
...
```

**`keywords`** 필드가 핵심: triage가 이 배열을 사용자 메시지와 매칭. 영문/한글/도메인 동의어 모두 포함.

## 동작 흐름

1. 사용자: "결제 환불 케이스 추가"
2. **triage** (Layer 0): "결제", "환불" 키워드 추출
3. **triage**: `.ax/modules/*/rules.md` 의 `keywords:` frontmatter 스캔
4. **매칭**: `payment/rules.md` (keywords에 "결제", "환불" 포함)
5. **컨텍스트 주입**: triage 출력의 *Required reading* 으로 `payment/rules.md` 첨부
6. 작업 시 해당 룰이 LLM 컨텍스트에 들어감

## 새 모듈 룰 추가

```bash
mkdir -p .ax/modules/<module-name>
cp .ax/_templates/module/rules.md .ax/modules/<module-name>/rules.md
$EDITOR .ax/modules/<module-name>/rules.md
# frontmatter의 keywords를 grep 매칭 가능한 단어로 채우기
```

## ID 컨벤션

- Spirit rules (`.ax/spirit/rules/`): `SP-<CATEGORY>-<NNN>` (예: `SP-SEC-001`)
- Module rules (`.ax/modules/`): `SP-<MODULE>-<NNN>` (예: `SP-PAY-001`)

룰 토큰 컨벤션 전체: `.ax/docs/reference/rules-tokens.md`

## 자동 매칭 vs 수동 참조

기본은 triage 자동. 사용자가 특정 모듈 룰을 명시적으로 보고 싶으면:

```bash
cat .ax/modules/<name>/rules.md
grep -l "keywords:.*결제" .ax/modules/*/rules.md
```
