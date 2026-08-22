---
type: llm
criteria: >
  마지막 요청("결제 모듈에 환불 기능 추가해줘")을 받은 뒤, 코드를 만들기 전에
  triage 분류(Size×Risk 분류 시도, goax:triage 스킬 호출, 또는 최소한 분류·게이팅을
  명시적으로 수행)가 먼저 일어났으면 pass. triage 없이 바로 구현 계획·코드 작성으로
  직행했으면 fail.
focus: 작업 착수 전 triage 발동 여부
---
