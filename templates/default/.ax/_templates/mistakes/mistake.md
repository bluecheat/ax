---
category: {{CATEGORY}}
severity: {{SEVERITY}}
detected_by: {{DETECTED_BY}}
context_link: {{CONTEXT_LINK}}
captured_at: {{CAPTURED_AT}}
source: {{SOURCE}}
status: open
---

# 무엇이 일어났나
한 줄 요약.

# 어디서 (파일·모듈)
파일/모듈/도메인.

# 왜 발생 (5 Whys 기법)
원인 분석 — "왜?" 를 5번까지 깊게.
1. 왜 X? → A
2. 왜 A? → B
3. 왜 B? → C
4. 왜 C? → D
5. 왜 D? → 근본 원인

# 어떻게 막을 수 있나 (사람 리뷰 / Sensor 자동화 / 룰 추가)
- 사람 리뷰로 막을 수 있나? (No → Sensor 자동화 후보)
- 어떤 hook 또는 룰이 막아야 하나?

# 영향 (Cost)
즉시:
- <변경 비용 — 예: 영향받는 파일 N개 재작성 (약 X분)>
- <사용자 turn 추가 — 예: 1회 (지적)>

잠재 후속 (정정 안 했을 경우):
- <예: CI 빌드 / 테스트 실패>
- <예: 후속 리네임·마이그레이션 PR 비용>
- <예: 다른 모듈·통합 지점에 silent 영향 미검출>


# audit 액션 제안

## 이력