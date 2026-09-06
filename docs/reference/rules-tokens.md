# Rules Tokens — 룰 식별·검색 컨벤션

> 모든 룰에 표준 토큰을 박아 두면 사람도 grep 도 1초 안에 찾아요.

## 두 layer, 두 scheme

goax 는 두 위치에 룰이 살고, 각각 토큰 형식이 달라요. 같은 도메인 룰이라도 layer 가 달라서 분리.

| Layer | 위치 | 토큰 형식 | 성격 |
|---|---|---|---|
| **Layer 1 / Constitution** | `CLAUDE.md` (root) | `<scope>:<TIER>:<NNN>` | 비협상 룰 (coarse) — `🔴 CRITICAL` / `🟡 MANDATORY` / `🔵 CONVENTION` 등급 |
| **Cross-cut / Spirit** | `.ax/spirit/rules/<category>.md` | `SP-<CAT>-<NNN>` | 카테고리별 fine-grained 룰 (path-scoped 또는 always-on inject) |

두 scheme 은 **상호 참조** 관계 — Layer 1 토큰 본문이 자세한 룰의 Spirit 토큰을 가리켜요. 예:

```markdown
🟡 **`COMMERCE:MANDATORY:001`** 모듈 의존 방향 단방향
자세한 룰: `.ax/spirit/rules/architecture.md` (SP-ARCH-001/002).
```

## Layer 1 — Constitution scheme: `<scope>:<TIER>:<NNN>`

| 부분 | 의미 | 예 |
|---|---|---|
| `scope` | 적용 범위 | `AX` (전역), `COMMERCE`, `<module>`, `*` (모든 모듈) |
| `TIER` | 등급 (대문자) | `CRITICAL`, `MANDATORY`, `CONVENTION` |
| `NNN` | 3자리 0-padded 순차 | `001`, `042`, `127` |

### 예시

| 토큰 | 해석 |
|---|---|
| `AX:CRITICAL:001` | 전역 비협상 룰 #1 |
| `COMMERCE:MANDATORY:001` | commerce 도메인 사람 게이트 룰 #1 |
| `*:CONVENTION:015` | 모든 모듈 공통 컨벤션 #15 |

### 룰 본문 작성

```markdown
🟡 **`COMMERCE:MANDATORY:001`** 모듈 의존 방향 단방향

위반 시 사람 승인 필요. ArchUnit 검증 PR.

자세한 룰: `.ax/spirit/rules/architecture.md` (SP-ARCH-001/002).
```

권장 요소:
- 등급 이모지 (`🔴 🟡 🔵`) + 토큰 (백틱 안)
- 한 줄 요약 → 빈 줄 → 본문
- 결정 근거·enforcement 표시는 `enforced_by:` schema (별도 doc: [`rule-enforcement.md`](rule-enforcement.md))
- Spirit 룰 cross-reference 는 본문에 `자세한 룰: ...` 형식

## Cross-cut Spirit scheme: `SP-<CAT>-<NNN>`

`.ax/spirit/rules/<category>.md` 의 각 룰 헤딩이 따라야 하는 형식:

```
## SP-<CAT>-<NNN>: <한 줄 요약>
```

| 부분 | 의미 | 예 |
|---|---|---|
| `CAT` | 3-5자 카테고리 prefix (대문자) | `ARCH`, `DOM`, `KOT`, `SEC`, `TEST` |
| `NNN` | 3자리 0-padded 순차 (CAT 안) | `001`, `042` |

### 예시

```markdown
## SP-ARCH-001: 빌드 conventions 위치

`build-logic/` 의 conventions plugin 만 사용. 모듈별 독립 build.gradle 금지.

위반 케이스:
- 모듈에 inline `dependencies { ... }` 블록 → conventions 로 추출
```

권장 요소:
- 헤딩 형식 strict (`spirit-lint.sh` 가 비표준 헤더·중복 토큰을 검출 — `doctor` 가 불러요)
- 토큰 중복 금지 — 같은 prefix-NNN 이 spirit/rules/ + modules/*/rules.md 통틀어 1번만
- path-scoped 룰이면 frontmatter 의 `paths:` 선언

## grep 패턴

```bash
# Layer 1 (CLAUDE.md)
grep -rn 'CRITICAL'              --include='CLAUDE.md' .   # 전체 CRITICAL
grep -rn 'AX:'                   --include='CLAUDE.md' .   # 전역만
grep -rn 'COMMERCE:CRITICAL'     --include='CLAUDE.md' .   # commerce CRITICAL
grep -rn '`[A-Za-z*]\+:MANDATORY' --include='CLAUDE.md' .  # 모든 MANDATORY (정규식)

# Cross-cut Spirit
grep -hE '^## SP-[A-Z]+-[0-9]{3}:' .ax/spirit/rules/*.md   # 모든 SP-* 헤딩
grep -hE '^## SP-DOM-' .ax/spirit/rules/*.md               # 도메인 카테고리만
```

## 룰 인덱스 — `rules-index.sh`

직접 grep 안 쳐도 세 소스(Constitution 시그널 라인 · `.ax/spirit/rules/` · `.ax/modules/*/rules.md`)를 한 인덱스로 보여줘요.
트리거: "goax rules", "rules 보여줘", "CRITICAL 룰만" — `doctor` 가 받아 이 스크립트 출력을 그대로 보여줘요 (룰 본문은 요약하지 않아요).

```bash
bash .ax/scripts/bash/rules-index.sh                          # 전체
bash .ax/scripts/bash/rules-index.sh --level critical         # TIER 필터: critical|mandatory|convention
bash .ax/scripts/bash/rules-index.sh --source spirit          # 소스 필터: constitution|spirit|module
bash .ax/scripts/bash/rules-index.sh --category security      # Spirit 카테고리 또는 모듈명
bash .ax/scripts/bash/rules-index.sh --find AX:CRITICAL:001   # 토큰 정확 매칭
```

## ID 발급 규칙

| 상황 | 처리 |
|---|---|
| 신규 Layer 1 룰 | scope 안에서 마지막 NNN + 1 |
| 신규 Spirit 룰 | CAT 안에서 마지막 NNN + 1 |
| 룰 폐기 | NNN 재사용 X — frontmatter 또는 본문에 `status: deprecated` |
| 룰 재배치 (scope/CAT 변경) | 새 위치의 다음 NNN 발급, 본문에 `replaces: <old-token>` 명시 |
| 룰 분할 | 옛 토큰 `replaces` 표시, 새 토큰 둘 발급 |

## 안티 패턴

- 토큰 없는 룰 → CLI/grep 에서 못 찾음 → `goax doctor` 가 spirit lint 로 비표준 헤더 검출
- ID 충돌 (같은 scope·TIER·NNN 또는 같은 CAT·NNN) → `spirit-lint.sh` 가 `duplicates` 로 잡아요 ("spirit 점검" 트리거)
- TIER 소문자 (`critical`) → 대문자 통일 (`CRITICAL`)
- Layer 1 룰을 spirit/rules/ 에 직접 박기 → Layer 분리 위반. Layer 1 은 CLAUDE.md, fine 룰은 spirit/rules/.
- ADR 링크를 HTML 주석으로 첨부 → `enforced_by:` schema 로 통일 ([`rule-enforcement.md`](rule-enforcement.md))
