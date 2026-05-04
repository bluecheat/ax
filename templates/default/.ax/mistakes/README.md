# Mistakes — 캡처 슬롯

> AI 에이전트나 사람이 발견한 실수를 즉시 적재하는 디렉토리.
> 7일에 1회 `goax audit`로 일괄 심사하고, 같은 카테고리 3회 이상 반복되면 CRITICAL/MANDATORY로 승격.

## git-tracked 정책

`.ax/mistakes/*.md` 는 **git-tracked**. gitignore 하지 않아요. 이유:

- mistake loop의 가치는 **팀 단위 패턴 누적** — gitignore하면 1인 회고로 전락, threshold 영원히 미달.
- weekly audit (Routine 등 schedule)이 fresh clone에서 빈 디렉토리만 봄 → 영구 no-op.
- 신규 합류자가 과거 실패 컨텍스트 흡수.

심리적 부담은 다음 4가지 보호 장치로 낮춰요:

1. **race-free ID** — `${DATE}-${EPOCH}-${RAND4}-<category>-<slug>.md` (15자 ID + 짧은 slug). 동시 캡처 충돌 사실상 0 (같은 초 + 같은 4-hex random = 1/65536).
2. **자동 redaction** — `redact_secrets` 헬퍼 (`common.sh`) 가 write 직전 DETAILS의 secret 패턴(`AKIA*`, `ghp_*`, `password=*`, JWT, PEM 등)을 `[REDACTED]`로 치환. 타이틀(ONE_LINE)은 시그널 손실 방지를 위해 redact 미적용 — caller가 secret을 타이틀에 직접 박지 않을 책임.
3. **bot author 컨벤션 (권장)** — 자동 commit 시 `git -c user.name=goax-bot` 사용. "내 실수가 commit log에 박힌다"의 심리적 비용 제거.
4. **별도 commit 분리** — mistake 캡처는 feature commit과 절대 섞지 않음. 자동화로 작은 chore commit으로만 누적.

## 파일 컨벤션 (단일)

```
.ax/mistakes/
└── YYYY-MM-DD-EPOCH-RAND4-<category>-<short-slug>.md
```

예: `2026-05-05-1777914582-1a94-secrets-pg-key-hardcoded.md`

- `EPOCH` = Unix timestamp 초 (10자)
- `RAND4` = 4-hex random (`$RANDOM` → `printf '%04x'`)
- `category` = frontmatter `category` 와 동일
- `slug` = ONE_LINE 영숫자 정규화 (cut 30 + trailing dash 제거). 한글 only → md5 hash 8자 fallback.

## 캡처 경로 — `mistake` skill 만

mistake 캡처는 사용자 명시 `mistake` skill 호출로만. hook 자동 capture 는 폐기 — 위반이 mistake 로 자동 박히면 일상 작업이 자기 자신을 신고하는 잡음 루프 + 본문 quality 가 placeholder.

```
"실수 기록해줘"  /mistake  "이번 mistake 캡처"
   ↓
mistake skill — 인터뷰 (category/severity/detected_by/context_link/ONE_LINE)
   ↓
init-mistake-file.sh — frontmatter sed 치환 + 파일 생성 (idempotent)
   ↓
LLM Edit tool — 본문 (5 Whys / 영향 / audit 액션) 작성
```

## 파일 템플릿

`.ax/_templates/mistakes/mistake.md` (spec/adr/module/spirit과 동일 `_templates/` 컨벤션). frontmatter 는 `{{...}}` placeholder 형식 — `init-mistake-file.sh` 가 sed 치환. 수동 작성 시 placeholder 직접 채움.

## 처리 후

심사 완료 + Constitution/ADR로 승격된 항목은 `_archive/`로 이동한다.

```
.ax/mistakes/
├── _archive/
│   └── YYYY/MM/...
└── (현재 활성 항목)
```
