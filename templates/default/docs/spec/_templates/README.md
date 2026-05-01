# Spec Templates

> 피처 spec 작성 시 이 템플릿을 복사해서 시작하세요.
> `goax spec new <name>` 명령이 자동으로 복사 + ID 부여.

---

## 사용법

```bash
goax spec new payment-refund-window
# → docs/spec/feature/001-payment-refund-window/ 디렉토리 생성
#   spec.md, plan.md, tasks.md, checklists/requirements.md 자동 복사
```

## 파일 구성

| 파일 | 역할 | 필수? |
|---|---|---|
| `spec.md` | WHAT/WHY (SSOT) | ✅ |
| `plan.md` | HOW (기술 계획) | ✅ |
| `tasks.md` | 작업 분해 | ✅ |
| `checklists/requirements.md` | 게이팅 체크리스트 | ✅ |
| `research.md` | 깊이 분석 | 선택 |
| `data-model.md` | 데이터 모델 | 선택 (복잡할 때) |
| `contracts/api.yaml` | API spec | 선택 |
| `contracts/events.md` | 이벤트 스키마 | 선택 |
| `quickstart.md` | 사용 가이드 | 선택 |

## SSOT 원칙

**spec.md가 단일 진실의 출처**:
- plan.md, tasks.md는 spec.md를 *입력*으로 받음
- 코드와 spec이 다르면 spec이 맞다고 가정 — 코드를 spec에 맞춰
- spec 변경 → plan/tasks 갱신 필수

## 게이팅 (NEEDS CLARIFICATION)

spec.md §1.3의 `**NEEDS CLARIFICATION**: <질문>` 마커가 1개라도 남아있으면:
- `goax spec check`가 fail
- plan/implement 단계 진입 차단

→ 모든 모호함을 spec 단계에서 해소해야 다음 단계로.

## Triage 자동 게이팅 (v0.6+)

`goax triage`가 size=L 이상 또는 risk=L2 이상으로 분류하면:
- spec 우선 작성 권장
- spec 디렉토리 미존재 시 implement 단계 차단 (옵션)
