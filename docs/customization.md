# Customization — 자기 프로젝트로 맞춤화

`ax-first init` 직후 손봐야 할 것 5가지.

## 1. CLAUDE.md (Layer 1)

기본 템플릿은 placeholder만 있어. 실제 룰은:
- `--preset ax` 사용 시 9 CRITICAL이 overlay로 들어감
- 그 외에는 직접 작성

체크리스트:
- [ ] 우리 팀에 안 맞는 CRITICAL 삭제
- [ ] 우리 팀 고유 CRITICAL 추가
- [ ] MANDATORY가 사람 승인 가능한 형태인가
- [ ] 시그널 이모지(🔴🟡🔵) 보존

## 2. `.ax-first/config.yml`

Triage가 참조하는 핵심 설정.

```yaml
domain_risk:
  payment: L3      # 자기 프로젝트 도메인 키워드 + 위험도
  order: L2
  ...
commands:
  build: "pnpm build"          # 자기 명령으로 교체
  test: "pnpm test"
  lint: "pnpm lint"
sensors:
  mode: warning                # 처음엔 warning, 안정화 후 fail
```

## 3. Hooks (Sensors)

`.claude/hooks/post-edit/lint-changed.sh`의 lint 명령을 자기 스택으로:

```bash
case "$TARGET_PATH" in
    *.kt|*.kts) ktlint --relative -- "$TARGET_PATH" ;;
    *.ts|*.tsx) eslint "$TARGET_PATH" ;;
    *.py)       ruff check "$TARGET_PATH" ;;
    *.go)       gofmt -l "$TARGET_PATH" ;;
esac
```

`.claude/hooks/pre-commit/critical-rule-grep.sh`의 정적 패턴을 자기 CRITICAL 룰로 확장.

## 4. 모듈 CLAUDE.md (Layer 2)

모노레포면 각 앱/모듈에:

```bash
# 예: crou-mono
touch apps/api/CLAUDE.md
touch apps/web/CLAUDE.md
touch apps/mobile/CLAUDE.md

# 예: commerce
for m in commerce-core commerce-rest commerce-data ...; do
  touch "$m/CLAUDE.md"
done
```

각 파일에는 **그 모듈 안에서만 결정되는 룰**만 적어 — Layer 1과 중복은 피한다.

## 5. Personas (선택)

`.claude/skills/personas/<role>/SKILL.md` 신설. 트리거 키워드를 명확히:

```yaml
---
name: payment-engineer
description: "결제·정산 도메인 전담. 멱등성·PG 연동·금액 흐름 검토. 트리거: '결제', 'payment', '환불', 'refund', 'PG', '정산', 'settlement'."
---
```

## 6. PR/CI 통합 (선택)

`circular_analysis.py` 같은 자기 프로젝트의 의존 분석 스크립트를 GitHub Actions에 연결:

```yaml
# .github/workflows/structural-check.yml
- name: Module dependency check
  run: |
    .claude/hooks/post-edit/structural-check.sh
  continue-on-error: true   # warning 모드 (config.yml의 sensors.mode와 맞춤)
```

---

## 안티 패턴

- ax-first init 결과를 그대로 두고 사용 → 자기 프로젝트 컨텍스트 무시
- CLAUDE.md를 매주 새로 쓰기 → 같은 룰 재발 + 컨벤션 변동성 ↑
- mode=fail 즉시 적용 → 팀이 동의 안 한 룰 강제 → 반발
- preset에 의존 → preset 작성자의 가정이 우리 환경과 다를 수 있음 (preset은 출발점일 뿐)
