---
category: __CATEGORY__              # 파일명과 일치 (kebab-case)
applies_to: [code]                  # code | pr | commit | review (필요한 것 다중 선택)
                                    # `code` 가 있어야 편집 시점에 자동 주입돼요.
                                    # pr/commit/review 만 있으면 편집 중엔 안 나와요 (의도된 동작)
paths:                              # 이 룰이 적용될 파일 글롭 — **비우면 자동 주입이 안 돼요**
  - "**/*.__EXT__"                  # 편집 대상이 여기 매칭되면 훅이 이 파일 경로를 주입
                                    # (pre-edit/spirit-rules-inject.sh)
severity: convention                # critical | mandatory | convention
                                    # 생략하면 convention 으로 봐요. critical 은 enforced_by 가
                                    # hook:*/external:* 일 때만 정직해요 (invariant I1)
enforced_by:                        # 무엇이 이 룰을 실제로 막나 — **이 줄이 없으면 검사에서
  - human:pr-review                 # 통째로 빠져요** (위반이 아니라 무검사). 쓸 수 있는 값:
                                    # hook:<경로> · external:<도구> · human:<게이트> · TODO:<YYYY-MM-DD>
enforced_kind: human                # block | warn | grep | arch | human | missing
                                    # grep = 아래 룰의 `검출 패턴:` 마커가 집행 (패턴 없는 룰은 doctor I7)
# contract: <테스트 경로>               # 이 파일의 룰을 막는 짝 테스트 (선택, 목록도 돼요). 테스트 이름에
#                                     # SP-ID 를 넣으면(`it('SP-X-001: …')`) doctor 가 어느 룰이 막혀 있나 봐요
# contract_ids: [SP-X-001]             # 계약 대상만 고를 때 (없으면 파일의 모든 SP-ID)
# adr: .ax/docs/adr/<id>-*.md           # 결정 근거 ADR (선택)
---

<!-- severity/enforced_by/enforced_kind 의 schema 와 invariant: .ax/docs/reference/rule-enforcement.md
     doctor 가 매 호출마다 check-rule-enforcement.sh 로 추적해요. -->

# __Category Title__

> 이 카테고리의 룰을 이 파일에 모아요. 새 룰은 `rule` skill 로 써요 ("이거 룰로 만들어").
> 글쓰기 기준: `.ax/docs/reference/writing-for-agents.md`

<!--
룰 하나의 틀:
  1. 헤더 `## SP-<PREFIX>-<NNN>: <규범 한 줄>` — 제목은 "무엇을 해요" 한 문장이에요. 사건 이름이나 경위를 제목에 쓰지 않아요.
  2. 본문 1–3줄 — `<조건>에서, <주어>는 <행동>해요.` 다음 줄에 `이유: <한 줄>`. 본문은 8줄을 넘기지 않아요.
  3. ❌/✅ 한 쌍 — 백틱 안에 실제 코드 한 줄씩. 예시가 더 필요하면 `.ax/spirit/references/<category>.md` 로 옮기고 링크 한 줄을 남겨요.
  4. grep 으로 잡히는 룰이면 `검출 패턴` 주석에 ERE 를 채워요. pre-commit 의 critical-rule-grep.sh 가 `paths:` 에 맞는 staged 파일을
     이 정규식으로 검사하고, zero-probe.sh 가 ❌ 는 걸리고 ✅ 는 안 걸리는지 재요. 잡히지 않는 룰이면 주석 줄을 지우고
     frontmatter 를 `enforced_kind: human` 으로 둬요. rules-auditor 가 완료 직전에 대조해요.
  5. 결정 근거가 ADR 에 있으면 `adr` 주석 한 줄만 둬요.

넣지 않는 것:
  - 날짜, 커밋 해시, PR·이슈 번호, "이번 세션"·"실측" 같은 사건 경위 — mistake 파일이나 ADR 에 남겨요.
  - ADR 의 결정 서술 문단 — ADR 파일에 두고 여기엔 링크 한 줄만 둬요.
  - goax 에이전트·skill·게이트에 대한 지시 (lane-worker, evaluator, spec-validate …) — goax 가 고칠 일이라 이슈로 올려요.
rule-lint.sh 가 이 기준을 검사해요. 룰 파일을 고치면 post-edit 훅이 지적을 알려줘요.
-->

## SP-__PREFIX__-001: <규범 한 줄 — 예: 금액은 Long 으로 다뤄요>

<조건>에서, <주어>는 <행동>해요.
이유: <한 줄>

❌ `<나쁜 예 한 줄>`
✅ `<좋은 예 한 줄>`

<!-- 검출 패턴: <regex> -->
<!-- adr: .ax/docs/adr/<id>-*.md -->

---

## SP-__PREFIX__-002: <두 번째 룰 — 필요 시>

...
