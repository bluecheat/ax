---
category: {{CATEGORY}}
severity: {{SEVERITY}}
detected_by: {{DETECTED_BY}}
context_link: {{CONTEXT_LINK}}
captured_at: {{CAPTURED_AT}}
source: {{SOURCE}}
model: {{MODEL}}
session_ref: {{SESSION_REF}}
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

# 어떻게 막을 수 있나 (집행 사다리 — 위에서부터)
- ① 구조로 제거할 수 있나? (디렉토리·타입·의존 방향으로 아예 못 쓰게)
- ② 이미 있는 lint/CI 가 잡을 수 있나? (external:<도구>)
- ③ grep 한 줄로 잡히나? 패턴 초안: `<ERE>` — audit 이 룰의 `<!-- 검출 패턴: -->` 으로 옮겨요
- ④ 셋 다 아니면 어떤 사람 게이트가 막나? (산문 룰은 마지막)

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