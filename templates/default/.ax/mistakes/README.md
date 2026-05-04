# Mistakes — 캡처 슬롯

> AI 에이전트나 사람이 발견한 실수를 즉시 적재하는 디렉토리.
> 7일에 1회 `goax audit`로 일괄 심사하고, 같은 카테고리 3회 이상 반복되면 CRITICAL/MANDATORY로 승격.

## git-tracked 정책

`.ax/mistakes/*.md` 는 **git-tracked**. gitignore 하지 않아요. 이유:

- mistake loop의 가치는 **팀 단위 패턴 누적** — gitignore하면 1인 회고로 전락, threshold 영원히 미달.
- weekly audit (Routine 등 schedule)이 fresh clone에서 빈 디렉토리만 봄 → 영구 no-op.
- 신규 합류자가 과거 실패 컨텍스트 흡수.

심리적 부담은 다음 4가지 보호 장치로 낮춰요:

1. **race-free ID** — `${DATE}-${EPOCH_MS}-${PID}-${RANDOM}-<slug>.md` (0.1.8+). 동시 캡처 충돌 0.
2. **자동 redaction** — `capture-mistake.sh` 가 write 직전 DETAILS의 secret 패턴(`AKIA*`, `ghp_*`, `password=*`, JWT, PEM 등)을 `[REDACTED]`로 치환. 타이틀(ONE_LINE)은 시그널 손실 방지를 위해 redact 미적용 — caller가 secret을 타이틀에 직접 박지 않을 책임.
3. **bot author 컨벤션 (권장)** — 자동 commit 시 `git -c user.name=goax-bot` 사용. "내 실수가 commit log에 박힌다"의 심리적 비용 제거.
4. **별도 commit 분리** — mistake 캡처는 feature commit과 절대 섞지 않음. 자동화로 작은 chore commit으로만 누적.

## 파일 컨벤션

```
.ax/mistakes/
└── YYYY-MM-DD-EPOCH_MS-PID-RANDOM-<category>-<short-slug>.md   # 0.1.8+
└── YYYY-MM-DD-NNN-<category>-<short-slug>.md                    # 0.1.7 호환
```

## 파일 템플릿

```markdown
---
category: <one-of: dependency-direction | hydration | n+1 | secrets-in-code | ...>
severity: <low | medium | high>
detected_by: <claude | reviewer | ci | self>
context_link: <PR URL or commit SHA>
---

# 무엇이 일어났나
한 줄 요약.

# 어디서
파일/모듈/도메인.

# 왜 발생
원인 분석.

# 어떻게 막을 수 있나
- 사람 리뷰로 막을 수 있나? (No → Sensor로 자동화 후보)
- 어떤 hook 또는 룰이 막아야 하나?
```

## 처리 후

심사 완료 + Constitution/ADR로 승격된 항목은 `_archive/`로 이동한다.

```
.ax/mistakes/
├── _archive/
│   └── YYYY/MM/...
└── (현재 활성 항목)
```
