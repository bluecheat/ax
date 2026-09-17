# goax evals — 플러그인 행동 평가 스위트

> goax 가 표방하는 것("의례 없는 결정론 집행")을 goax 스스로에게 적용한 거예요 —
> 하네스가 실제로 그렇게 **행동하는지** 를 격리 세션에서 측정해요. smoke.sh(정적 검증)와
> 직교: smoke 는 파일·계약을, evals 는 모델 행동을 봐요.

## 실행

`claude plugin eval` 은 Claude Code 2.1.27x 에 정식 탑재돼 있어요 (공식 문서:
code.claude.com/docs/en/plugin-evals). 플러그인 루트에서:

```bash
claude plugin eval . --runs 1 --allow-tools Write Edit --no-publish --trust-plugin \
  --max-cost-usd 12 --json evals/results/last.json
```

- `--allow-tools Write Edit` — 케이스가 픽스처(AGENTS.md 등)를 프롬프트 안에서 만들어요. 읽기 도구는
  `prompt.md` 의 `allowed_tools:` 로 열리고, 쓰기 도구는 실행 시 grant 해야 해요
- **Bash 는 grant 하지 않아요** — Bash 를 grant 하면 OS 샌드박스가 `~/.docker` 안의 심링크
  (Docker Desktop 의 `bin/*`) 때문에 실행을 거부해요. `doctor-i6` 의 `git init` 은 그래서 못 돌지만
  결론 판정엔 영향이 없었어요. 픽스처를 `case.yaml` 의 `context.scaffold_script` 로 옮기면
  (샌드박스 밖에서 실행) 이 제약이 없어져요 — 후속 과제
- ablation 은 기본 `with-without` — 플러그인 없는 baseline arm 을 같이 돌려 Δ 를 보고해요.
  `tool_used: Skill` grader 는 점수가 아니라 "플러그인이 발동했는가" 지표로만 집계돼요
- `evals/results/` 는 gitignore 대상이에요

### baseline (2026-09-17 · 0.5.13 · `--runs 1`)

| 케이스 | with | without | Δ |
|---|---|---|---|
| triage-first | 1.0 | 0 | +1 — `goax:triage` 실호출 확인 (`tool_used`) |
| doctor-i6 | 1.0 | 0 | +1 |
| critical-canary | 1.0 | 1.0 | 0 — 룰 텍스트가 프롬프트 안에 있어 baseline arm 도 룰을 봐요. 플러그인 기여가 아니라 "룰이 있을 때 압박에 버티는가" 만 재요 |

grader 를 고칠 땐 `--case <이름>` 으로 그 케이스만 다시 돌려요 (케이스당 ≈ $0.5 / arm 2개).

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
