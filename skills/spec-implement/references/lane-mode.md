# 레인 모드 — 코디네이터 루프

> SKILL.md §1.5 에서 `LANE_N > 0` 일 때만 읽어요. 단일 레인이면 이 문서는 필요 없어요.

이 세션은 **코디네이터**예요. 코드를 직접 고치지 않고, 레인을 띄우고, 보고를 받고, 검증하고,
체크박스를 켜요. 판단은 여기서 하고 기록은 원장이 해요 — 컨텍스트 안의 "누구에게 뭘 보냈더라"
는 압축되거나 세션이 죽으면 사라져요. 실제로 레인 8개가 전부 idle 이 됐을 때 체크박스는
24/36 이었고, 세 레인이 산출물을 만들어 놓고 전송하지 않아 아무것도 도착하지 않은 적이 있어요.

**0. 전제** — §1.5 의 violations 0 + `lane_file_conflicts` 0. 하나라도 있으면 띄우지 않아요.

**1. 준비된 task 를 레인별로 묶어요.**

```bash
echo "$PLAN"   | jq -r '.result.ready | join(" ")'                                   # 지금 시작 가능
echo "$LEDGER" | jq -r '.result.lanes[] | "\(.lane): \(.tasks | join(","))"'          # 레인 → task
echo "$LEDGER" | jq -r '.result.unassigned_open | join(" ")'                         # 레인 없는 task
```

- ready ∩ 레인 A 의 task → 레인 A 의 이번 브리프
- ready 인데 `레인:` 없음 → **코디네이터가 직접** 해요 (§3.1). 배럴·인덱스처럼 떼어낸 순차
  task 가 보통 여기예요
- §3.2 strict 조건(L3 + SP-SEC/DATA 등)에 걸리는 task 는 **레인에 넘기지 않아요.**
  코디네이터가 `[y/n]` 을 받고 직접 해요

**2. 디스패치를 원장에 먼저 적고, 그다음 띄워요.**

```bash
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --dispatch A --json   # 파일 소유 충돌이면 여기서 거부돼요
```

**exit 1 이 항상 에러는 아니에요** — 그 레인의 미완료 task 가 전부 이미 디스패치·보고까지
끝났으면 (더 보낼 게 없으면) `--dispatch` 가 exit 1 로 끝나요 (`status: error` + "전부 보고까지
받았어요 — 그래도 다시 보내려면 --force"). 이건 종료 조건이지 실패가 아니에요 — §5 로 넘어가서
`ready`·`dispatched_unreported` 를 다시 봐요. 진짜 실패(파일 소유 충돌)는 메시지가 달라요.

브리프는 `lane` skill §10 형식 그대로예요 — 소유 파일(그 레인 task 들의 `files:` 합집합) ·
금지 파일(다른 레인 소유 + `protected_paths` + 버전 파일) · task ID 와 각 `검증:` 명령 ·
정지 조건 · "커밋하지 않는다" · "체크박스는 켜지 않는다" · "결과를 최종 메시지에 전부 담는다
(`SendMessage`·`ListAgents` 는 이 레인엔 없어요 — 최종 응답이 유일한 산출물 경로예요)".

`Agent` 도구로 `goax:lane-worker` 를 띄워요 (vendor 설치면 `lane-worker`). 준비된 레인이
여럿이면 **한 메시지에 같이** 띄워요 — 하나 띄우고 기다렸다 다음을 띄우는 건 병렬이 아니에요.

**격리** — 기본은 공유 워킹 트리예요. 파일 소유권이 물리적 충돌을 막고, 원장이 소유 겹침을
거부해요. worktree 로 갈라야 하는 건 레인이 *같은 파일을 다른 방향으로* 바꿔야 할 때뿐이고,
그건 이미 `lane` 이 "가를 수 없는 일" 로 판정했어야 해요 (`lane` §0.5).

**3. 보고를 받으면 — 받았다는 사실부터 적어요.**

```bash
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --report A --json           # 레인 전체가 왔을 때
bash .ax/scripts/bash/lanes-dispatch.sh --spec "$SPEC" --report T010,T011 --json   # 일부만 왔을 때
```

그다음 **보고에 인용된 검증 명령을 코디네이터가 직접 다시 돌려요.** 통과한 task 만 §5 로
체크박스를 켜요. 레인이 "완료" 라고 했어도 명령이 실패하면 미완료예요 — 보고와 완료는 별개예요.

보고의 **"다른 레인에 넘길 것"** (바뀐 공유 이름 — props·타입·토큰·이벤트) 은 인계 노트에
바로 적어요. 다른 레인과 다음 세션이 여기서 이름을 대조해요:

```bash
bash .ax/scripts/bash/status-note.sh --add renamed "Pill.tone → variant (레인 A, T011)" --json
```

- 보고가 잘렸으면 잘린 지점을 지목해서 이어 보내달라고 해요 ("T3 섹션 3번째 항목부터"). "다시
  보내주세요" 만 하면 앞부분이 또 오고 또 잘려요
- 레인이 소유 목록 밖 파일을 건드렸다고 보고하면 → §7 범위 이탈, halt
- 레인이 정지 조건에 걸려 멈췄으면 → 전제가 틀린 거예요. 남은 task 를 재배정하지 말고 사용자 결정

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

**6. 통합 검증** — 파일이 안 겹쳤다는 건 물리적 충돌이 없었다는 뜻뿐이에요. 전체를 한 번 더:

```bash
bash .ax/scripts/bash/zero-verify.sh --json    # .ax/config.yml commands.* 를 파이프 없이 — 안 돌린 항목도 보고
bash .ax/scripts/bash/status-note.sh --show --json | jq -r '.result.sections.renamed[]'   # 이름 대조 목록
```

인계 노트의 "이번에 바뀐 이름" 을 모아 **이름 대조** — 같은 개념에 두 이름이 생기지 않았는지.
명령으로 안 잡히는 유일한 항목이라 사람 몫이에요. 여기까지 통과해야 §8 로 가요.

## 출력 패턴

```
📐 spec-implement (spec 014, 레인 모드)

 ▸ 게이트  violations 0 · 소유 충돌 0
 ▸ ready   T010 T011 T020   ·  레인 A {T010,T011}  B {T020}  ·  직접 T009
 ▸ 디스패치 A, B — 원장 기록 ✓ → lane-worker 2개 동시 기동

 (보고 수신)
 ✓ 보고 A — 원장 기록 · $ pnpm test Card (exit 0) · T010 T011 마킹 [x]
 ▸ 인계   renamed +1 (Pill.tone → variant)
 → T021 의존 해소 → 레인 A 재디스패치 (B 는 아직 진행 중)

 (전원 종료)
 ▸ 원장   dispatched_unreported 0 · done_without_report 0
 ▸ 통합   zero-verify.sh 전 항목 exit 0 · 이름 대조 1건 정합 확인
 → §8 완료 게이트
```
