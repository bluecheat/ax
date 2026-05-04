# Spec — `.ax/config.yml` Schema

`.ax/config.yml`은 goax의 프로젝트 설정. plugin skill (`triage`, `doctor`, `audit`) 과 `.ax/hooks/*.sh`가 참조.

## 전체 schema (YAML)

```yaml
# ───────────────────────────────────────────────────────────
# 도메인 위험도 매트릭스 — triage가 작업 키워드와 매칭
# 키: 영문 kebab-case만. 한글은 인라인 주석.
# 같은 도메인을 영문/한글 별도 키로 두지 않음 (중복·충돌 방지).
# ───────────────────────────────────────────────────────────
default_risk: L1        # domain_risk 매칭 안 될 때 fallback (L0|L1|L2|L3)

domain_risk:
 payment: L3          # 결제, PG, 환불
 settlement: L3        # 정산
 order: L2           # 주문
 coupon: L2          # 쿠폰 (포인트성 자산)
 catalog: L1          # 카탈로그
 product: L1          # 상품
 log: L0            # 로그·관측
 # ...

# ───────────────────────────────────────────────────────────
# 빌드/테스트/린트 명령 — doctor 진단·hooks 가 참조
# 사용자 프로젝트 스택에 맞게 채움
# ───────────────────────────────────────────────────────────
commands:
 build: ""           # 예: pnpm build, ./gradlew build, cargo build
 test: ""           # 예: pnpm test, ./gradlew test, cargo test
 lint: ""           # 예: pnpm lint, ./gradlew ktlintCheck, ruff check
 typecheck: ""         # 예: pnpm typecheck, ./gradlew compileKotlin

# ───────────────────────────────────────────────────────────
# Sensors — .ax/hooks/*.sh 강도 (decision-making, not LLM)
# ───────────────────────────────────────────────────────────
sensors:
 mode: warning         # warning = 메시지만 / fail = exit 1로 작업 차단
 block_destructive: true    # pre-bash hook이 rm -rf · git push --force 등 강제 차단
 protected_paths:       # pre-edit hook이 변경 시 경고할 경로 (path prefix match)
  - CLAUDE.md
  - .ax/
  - .claude/
  - .github/

# ───────────────────────────────────────────────────────────
# Mistake Loop — audit가 참조
# ───────────────────────────────────────────────────────────
mistake_loop:
 promotion_threshold: 3    # 같은 카테고리 N회 이상 누적 → audit이 룰 승격 권고
 audit_cadence_days: 7     # N일마다 사용자에게 audit 권유 (옵션)
```

## 불변량 (Invariants)

1. **`default_risk`는 항상 `L0`~`L3` 범위.** 그 외 값은 invalid.
2. **`domain_risk` 키는 영문 kebab-case + unique.** 한글 키 금지 (사용자 메시지의 한글은 LLM이 영문 키로 의역해서 매칭).
3. **`sensors.mode`가 `fail`이면** hook 실패 시 working tree 변경이 abort 돼야 함 (`exit 1`).
4. **`protected_paths`는 path prefix matching** (regex 아님). `CLAUDE.md`는 정확 매칭, `.ax/`는 prefix 매칭.
5. **`promotion_threshold`는 양의 정수.** 0 또는 음수 금지.
6. **`audit_cadence_days`는 양의 정수**, 14 이하 권장 (너무 길면 mistakes 누적량 폭발).

## skill 별 사용처

| skill | 참조 항목 |
|---|---|
| `triage` | `domain_risk`, `default_risk` (작업 키워드 매칭) |
| `doctor` | `commands.*` (빌드 가능 여부 체크), `sensors.mode` (hooks 활성 상태) |
| `audit` | `mistake_loop.promotion_threshold`, `audit_cadence_days` |
| `spec` | `domain_risk` (slug에 도메인 매칭, 위험도 미리보기) |
| `.ax/hooks/pre-bash` | `sensors.block_destructive`, `sensors.mode` |
| `.ax/hooks/pre-edit` | `sensors.protected_paths`, `sensors.mode` |

## 변경 시

이 spec과 다른 동작을 추가하려면 ADR 작성 후 schema 갱신:
```
"새 ADR 만들어줘 — config-yml-schema-extension"
```
→ `adr` skill이 0000-template.md 기반으로 ADR 골격 생성.

## 한글 키 금지 이유 (히스토리)

이전엔 `payment: L3` + `결제: L3`을 양쪽 키로 두는 패턴이 있었으나:
- **중복**: 같은 도메인을 두 키로 표현 → `doctor` 진단 시 부풀려짐
- **충돌**: 한글 메시지에 "결제 환불" 들어오면 두 키 모두 매칭 → 위험도 결정 모호
- **SSOT 위반**: 도메인 정의의 단일 source가 깨짐

→ 영문 kebab-case 키 + 인라인 한글 주석으로 통일 . triage가 LLM으로 한글→영문 의역 매칭.
