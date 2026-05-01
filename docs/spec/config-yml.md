# Spec — `.ax/config.yml` Schema

`.ax/config.yml`은 goax의 프로젝트 설정. Triage·doctor·hooks가 참조.

## 전체 schema (YAML)

```yaml
default_risk: L0|L1|L2|L3      # domain_risk 매칭 안 될 때 기본값

domain_risk:                    # 도메인 키워드 → 위험도 매핑
  <keyword>: <L0|L1|L2|L3>      # 한국어/영어/정규식 키워드 OK
  ...

commands:                       # 빌드/테스트/린트 명령 (사용자 스택)
  build: ""
  test: ""
  lint: ""
  typecheck: ""

sensors:                        # hooks 강도 제어
  mode: warning | fail          # warning = 출력만, fail = exit 1
  block_destructive: true       # pre-bash 강제 차단
  protected_paths:              # pre-edit 변경 시 경고 경로
    - CLAUDE.md
    - .ax/
    - .claude/
    - .github/

mistake_loop:
  promotion_threshold: 3        # 같은 카테고리 N회 → CRITICAL 승격 권고
  audit_cadence_days: 7
```

## 불변량 (Invariants)

1. `default_risk`는 항상 `L0`\~`L3` 범위
2. `domain_risk` 키는 unique (중복 시 마지막 값이 이김)
3. `sensors.mode`가 `fail`이면 hook 실패 시 working tree 변경이 abort돼야 함
4. `protected_paths`는 항상 path prefix matching (regex 아님)
5. `promotion_threshold`는 양의 정수

## 변경 시

이 spec과 다른 동작을 추가하려면 ADR 작성 후 schema 갱신.
