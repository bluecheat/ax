# 레인 모드 — 코디네이터 루프

> SKILL.md §1.5 에서 `LANE_N > 0` 일 때만 읽어요. 단일 레인이면 이 문서는 필요 없어요.

이 세션은 **코디네이터**예요. 코드를 직접 고치지 않고, 레인을 띄우고, 보고를 받고, 검증하고,
체크박스를 켜요. 판단은 여기서 하고 기록은 원장이 해요 — 컨텍스트 안의 "누구에게 뭘 보냈더라"
는 압축되거나 세션이 죽으면 사라져요. 실제로 레인 8개가 전부 idle 이 됐을 때 체크박스는
24/36 이었고, 세 레인이 산출물을 만들어 놓고 전송하지 않아 아무것도 도착하지 않은 적이 있어요.

**0. 전제** — §1.5 의 violations 0 + `lane_file_conflicts` 0. 하나라도 있으면 띄우지 않아요.

**1. 준비된 task 를 레인별로 묶어요.**

```bash
printf '%s\n' "$PLAN" | jq -r '.result.ready | join(" ")'                                   # 지금 시작 가능
printf '%s\n' "$LEDGER" | jq -r '.result.lanes[] | "\(.lane): \(.tasks | join(","))"'          # 레인 → task
printf '%s\n' "$LEDGER" | jq -r '.result.unassigned_open | join(" ")'                         # 레인 없는 task
```

- ready ∩ 레인 A 의 task → 레인 A 의 이번 브리프
- ready 인데 `레인:` 없음 → **코디네이터가 직접** 해요 (§3.1). 배럴·인덱스처럼 떼어낸 순차
  task 가 보통 여기예요
- §3.2 strict 조건(L3 + SP-SEC/DATA 등)에 걸리는 task 는 **레인에 넘기지 않아요.**
  코디네이터가 `[y/n]` 을 받고 직접 해요

**2. 디스패치를 원장에 먼저 적고, 그다음 띄워요.** 원장엔 **이번 브리프에 실제로 넣은 task 만** 적어요.

```bash
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --dispatch T010,T011 --json   # 이번 라운드에 맡기는 task 만
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --dispatch A --json           # 레인의 미완료 전부를 한 번에 맡길 때
```

- **task 목록이 기본이에요.** §1 의 "ready ∩ 레인 A" 는 보통 레인 A 의 일부라서, `--dispatch A` 로 적으면
  아무도 안 맡은 task 까지 시각이 찍혀요. 그러면 `dispatched_unreported` 와 완료 게이트의 "보고 안 받은
  디스패치" 에 안 보낸 task 가 섞여 신호가 흐려져요 (실측: 레인 하나의 8 task 가 실제 기동보다 77분 먼저
  찍혔고, 아무도 안 맡은 4 task 가 경보에 들어갔어요)
- 목록은 전부 미완료 · 같은 레인이어야 해요. 아니면 exit 1 이고 원장은 그대로예요
- 이미 디스패치된 task 를 다시 적으면 시각을 갱신하고 `보고:` 를 지운 뒤 `warnings` 에 알려요 — 재전송이에요
- 파일 소유 충돌이면 둘 다 여기서 거부돼요 (그 task 들이 속한 레인 기준)

**exit 1 이 항상 에러는 아니에요** — 레인 이름으로 보냈는데 그 레인의 미완료 task 가 전부 이미 디스패치·보고까지
끝났으면 (더 보낼 게 없으면) `--dispatch` 가 exit 1 로 끝나요 (`status: error` + "전부 보고까지
받았어요 — 그래도 다시 보내려면 --force"). 이건 종료 조건이지 실패가 아니에요 — §5 로 넘어가서
`ready`·`dispatched_unreported` 를 다시 봐요. 진짜 실패(파일 소유 충돌)는 메시지가 달라요.

브리프는 `lane` skill §10 형식 그대로예요 — 소유 파일(그 레인 task 들의 `files:` 합집합) ·
금지 파일(다른 레인 소유 + `protected_paths` + 버전 파일) · 공용 자원(포매터 범위 · 브라우저 세션 이름 · 빌드 출력 경로 · 디스크 기준 — 비어 있으면 띄우기 전에 채워요) · task ID 와 각 `검증:` 명령 ·
정지 조건 · "커밋하지 않는다" · "체크박스는 켜지 않는다" · 보고 경로. 보고 경로는 레인을 띄우는 방식이 정해요:

| 띄우는 방식 | 레인의 도구 | 보고 경로 | 레인의 최종 응답 |
|---|---|---|---|
| `Agent` 도구 (서브에이전트) | `SendMessage`·`ListAgents` 없음 | 최종 응답에 전문 — 유일한 산출물 경로 | 보고 전문 |
| 팀원(teammate) | `SendMessage` 있음 | `SendMessage` 로 코디네이터에게 1회, task 별로 나눠 한 메시지 ≤ 약 3,000자 | "보고를 SendMessage 로 보냈어요 — task N건, 검증 exit 0" 한 줄 |

브리프엔 둘 중 **실제로 띄우는 방식**의 줄을 적어요. 팀원 레인에 서브에이전트 규약("최종 메시지에 전부")을
주면 같은 보고가 SendMessage · idle 통지 · 후속 답으로 세 번 와요 (실측).

`Agent` 도구(또는 팀원)로 `goax:lane-worker` 를 띄워요 (vendor 설치면 `lane-worker`). 이름은 **`lane-<레인>`**
(조사 레인은 `scout-<주제>`) 로 줘요 — §3.5 정리가 이 접두사로 거르기만 하면 되게요. 준비된 레인이
여럿이면 **한 메시지에 같이** 띄워요 — 하나 띄우고 기다렸다 다음을 띄우는 건 병렬이 아니에요.
**모델** — 띄우기 전에 `bash .ax/scripts/bash/agent-model.sh lane-worker lane-scout --json` 을 돌려 `result.models.<이름>` 이 null 이 아니면 그 값을 Agent 호출의 `model` 로 넘겨요. null 이면 넘기지 않아요 (에이전트 정의의 기본값 — 팀은 `.ax/config.yml` 의 `agent_models` 로 바꿔요).

**격리** — 기본은 공유 워킹 트리예요. 파일 소유권이 물리적 충돌을 막고, 원장이 소유 겹침을
거부해요. worktree 로 갈라야 하는 건 레인이 *같은 파일을 다른 방향으로* 바꿔야 할 때뿐이고,
그건 이미 `lane` 이 "가를 수 없는 일" 로 판정했어야 해요 (`lane` §0.5).

**3. 보고를 받으면 — 받았다는 사실부터 적어요.**

```bash
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --report A --json           # 레인 전체가 왔을 때
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --report T010,T011 --json   # 일부만 왔을 때
```

**팀원 레인이면 idle 통지는 요약이고, 전문은 `SendMessage` 로 와요.** 통지의 result 는 길면
`[result truncated]` 로 잘려요 — 그걸 보고 재요청하지 말고 SendMessage 로 온 메시지들을 먼저 모아요
("레인 A 보고 1/N" 의 N 개가 다 왔는지). 원장 `--report` 는 전문이 다 도착한 task 만 적어요.

그다음 **보고에 인용된 검증 명령을 코디네이터가 직접 다시 돌려요.** 통과한 task 만 §5 로
체크박스를 켜요. 레인이 "완료" 라고 했어도 명령이 실패하면 미완료예요 — 보고와 완료는 별개예요.

보고의 **"다른 레인에 넘길 것"** (바뀐 공유 이름 — props·타입·토큰·이벤트) 은 인계 노트에
바로 적어요. 다른 레인과 다음 세션이 여기서 이름을 대조해요:

```bash
bash .ax/scripts/bash/status-note.sh --add renamed "Pill.tone → variant (레인 A, T011)" --json
```

- 보고가 잘렸으면 **잘린 줄을 그대로 인용해 지목하고** 그 다음부터 보내달라고 해요 ("T3 섹션의
  `$ pnpm test Card` 출력 다음 줄부터", "1/3 메시지의 마지막 줄 `…` 다음부터"). "다시 보내주세요" 만 하면
  앞부분이 또 오고 또 잘려요. 다시 작업하지 말고 이미 만든 결과를 보내라고 덧붙여요
- 레인이 소유 목록 밖 파일을 건드렸다고 보고하면 → §7 범위 이탈, halt
- 레인이 정지 조건에 걸려 멈췄으면 → 전제가 틀린 거예요. 남은 task 를 재배정하지 말고 사용자 결정

**3.5 레인 정리 — 받고 검증했으면 종료해요.** 팀원으로 띄운 레인에만 해당해요 (`Agent` 도구로 띄운 레인은
최종 응답과 함께 끝나요). 내 도구 목록에 `TaskStop` 이 없으면 이 절을 건너뛰고 §8 보고에 "레인 정리 못 함" 을 적어요.

1. **조건** — 그 레인의 이번 디스패치 task 가 전부 원장 `보고:` 로 찍혔고, §3 의 검증 재실행이 전부 통과.
   하나라도 아니면 종료하지 않아요 — 잘린 보고를 이어 받는 중인 레인도 아직이에요
2. **종료** — `TaskStop` 의 `task_id` 에 레인 이름(`lane-A`). 다음 라운드에 같은 레인이 또 일할 것 같아도
   종료해요 — 판단할 일을 남기지 않으려고요. 다시 일이 생기면 그 이름으로 `SendMessage` 하면 transcript 에서
   이어지고, 안 이어지면 같은 브리프로 새로 띄워요
3. **확인** — `TaskStop` 이 실패하면 `ListAgents` 에 그 이름이 남았는지 봐요. 없으면 이미 종료된 거예요.
   남았으면 `TaskStop` 을 **한 번만** 더. 그래도 남으면 더 시도하지 않고 이름을 인계 노트에 적고 진행해요
   (`status-note.sh --add open "레인 lane-A 가 종료 안 됨 — 직접 종료 필요"`)
4. **묻지 않아요** — `shutdown_request` 를 보내지 않아요. 레인이 응답할 차례를 얻고, 그 턴에 시키지 않은
   외부 쓰기를 한 적이 있어요 (실측). 사용자가 원할 때만 보내요

**4. 라운드 단위 배리어를 인정하고, 그 안에서 항목별로 승격해요.**

한 메시지에 같이 띄운 `Agent` 호출들은 **전부 끝나야** 이 세션으로 돌아와요 — 하나가 끝났다고
그 결과만 먼저 받아서 다음 레인을 바로 못 띄워요 (그 라운드가 배리어예요). 항목별 승격은 그
*다음* 라운드에서 일어나요: 라운드가 끝나 돌아오면, 그새 의존이 풀린 task(예: 레인 A 가 끝나며
T020 의 의존이 풀림)를 **가장 느렸던 레인(B)의 다음 라운드를 기다리지 않고** 바로 새 라운드로
띄워요 — "전원 종료" 를 기다리는 배리어는 `tasks-plan.sh` 가 일부러 안 만든 거예요. 즉 배리어는
"라운드 안"에는 있고 "라운드 사이"에는 없어요.

`phase_gate` 모드의 사람 확인은 **레인 보고를 받은 시점**에 해요. Phase 경계가 아니에요 —
Phase 와 레인은 1:1 이 아니라서 "Phase 2 → 3 전환" 이 레인 모드에선 정의되지 않아요. 확인
박스 내용은 §4 와 같아요: 받은 보고 요약 + 다음에 띄울 레인과 파일 + 룰 delta.

**5. 종료 조건** — `tasks-plan.sh` 의 `ready` 와 `blocked` 가 둘 다 비고, 원장의
`dispatched_unreported` 가 비어야 해요. 레인이 전부 idle 인 건 조건이 아니에요.
그리고 **`ListAgents` 에 이 세션이 띄운 `lane-`·`scout-` 이름이 0개**여야 해요 — 원장은 원장 밖에서
띄운 레인을 몰라서, 살아 있는 레인 목록이 기준이에요. 남은 게 있으면 §3.5 의 2~3 을 그 이름마다 해요.

**6. 통합 검증** — 파일이 안 겹쳤다는 건 물리적 충돌이 없었다는 뜻뿐이에요. 전체를 한 번 더:

```bash
bash .ax/scripts/bash/zero-verify.sh --json    # .ax/config.yml commands.* 를 파이프 없이 — 안 돌린 항목도 보고
bash .ax/scripts/bash/status-note.sh --show --json | jq -r '.result.sections.renamed[]'   # 이름 대조 목록
```

인계 노트의 "이번에 바뀐 이름" 을 모아 **이름 대조** — 같은 개념에 두 이름이 생기지 않았는지.
명령으로 안 잡히는 유일한 항목이라 사람이 맡아요. 여기까지 통과해야 §8 로 가요.

## 출력 패턴

```
◆  spec-implement (spec 014, 레인 모드)

 ▸ 게이트  violations 0 · 소유 충돌 0
 ▸ ready   T010 T011 T020   ·  레인 A {T010,T011}  B {T020}  ·  직접 T009
 ▸ 디스패치 A, B — 원장 기록 ✅ → lane-worker 2개 동시 기동

 (보고 수신)
 ✅ 보고 A — 원장 기록 · $ pnpm test Card (exit 0) · T010 T011 마킹 [x]
 ▸ 정리   lane-A TaskStop ✅
 ▸ 인계   renamed +1 (Pill.tone → variant)
 → T021 의존 해소 → 레인 A 재디스패치 (B 는 아직 진행 중)

 (전원 종료)
 ▸ 원장   dispatched_unreported 0 · done_without_report 0
 ▸ 레인   ListAgents lane-·scout- 0개
 ▸ 통합   zero-verify.sh 전 항목 exit 0 · 이름 대조 1건 정합 확인
 → §8 완료 게이트
```
