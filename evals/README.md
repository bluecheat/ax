# goax evals — 플러그인 행동 평가 스위트

> goax 가 표방하는 것("의례 없는 결정론 집행")을 goax 스스로에게 적용한 거예요 —
> 하네스가 실제로 그렇게 **행동하는지** 를 격리 세션에서 측정해요. smoke.sh(정적 검증)와
> 직교: smoke 는 파일·계약을, evals 는 모델 행동을 봐요.

## 상태 — early access 주의

`claude plugin eval` 은 아직 early-access 기능이고 공개 문서가 없어요. 이 스위트의
레이아웃(`<case>/prompt.md` + `graders/*.md`)은 현 시점 임베디드 레퍼런스 기준이라,
실행 전에 다음으로 실제 빌드와 맞는지 확인하세요:

```bash
claude plugin eval --help    # flag·포맷 확인
# "early access" 안내가 나오면 org 활성화가 필요해요 (env var 이름 추측 금지)
```

명령이 없거나 포맷이 다르면 각 케이스의 `prompt.md` 를 `claude -p` 샌드박스로 수동
실행하고 graders 의 기준으로 채점해도 같은 신호를 얻어요 (케이스가 자기 완결이 되게
픽스처 생성 단계를 프롬프트 안에 넣어 뒀어요). 스킬 단위 평가는 skill-creator 의
`evals/evals.json` 스키마(공식 문서화됨)가 안정 대안이에요.

## 케이스

| 케이스 | 측정하는 것 |
|---|---|
| `triage-first/` | 새 작업 요청에서 triage 가 실제로 먼저 발동하는가 (META 1번 룰) |
| `critical-canary/` | 🔴 룰을 정면으로 유혹하는 요청을 하네스가 막거나 지적하는가 |
| `doctor-i6/` | 집행 실체가 없는 설치를 doctor 가 I6/C3 로 정확히 진단하는가 |

## 운영 원칙

- 케이스는 **실패 사례에서** 추가해요 — 실제로 관찰된 룰 미준수·오진을 케이스로 승격
  (mistake loop 와 같은 방향). 추측성 케이스를 늘리지 않아요.
- AGENTS.md 템플릿·spirit·doctor 를 바꾸는 PR 은 이 스위트를 재실행하는 게 원칙이에요 —
  하네스 문서에도 회귀 테스트가 있어야 "라벨과 실제의 일치"가 지켜져요.
