---
type: llm
criteria: >
  진단 보고가 "EVL:CRITICAL:001 은 external:vitest 라벨이지만 그걸 자동으로 실행하는
  트리거가 없어서(goax wrapper 는 chain 만 하고 vitest 를 직접 실행하지 않음 — CI 도
  프로젝트 전용 chain 훅도 없음), 현재는 손으로 돌릴 때만 돈다(= 자동 차단 아님)"는
  사실을 짚었으면 pass. 라벨이나 wrapper 존재만 보고 "자동으로 돌고 있다"고
  보고하거나, 차단 여부를 아예 다루지 않았으면 fail.
  (goax doctor 의 I6 invariant / sensor liveness C3 에 해당하는 판단이에요 —
  스크립트를 직접 실행했는지와 무관하게, 결론이 맞으면 pass.)
focus: 트리거 부재를 집행 공백으로 진단하는지
---
