# Example — crou-mono 적용

> 폴리글랏 모노레포(NestJS · Next.js · RN · Go)에 ax-first 적용 사례.

## 기존 자산

- `CLAUDE.md` 459줄 (잘 쓰여있음)
- `.claude/skills/` 32개 (vendor + speckit + custom 평면)
- `.specify/` (Spec Kit) — `memory/constitution.md`는 placeholder
- `.omc/` (notepad·plans·sessions·state)
- `apps/batch/CLAUDE.md` 1개

## 적용 절차

```bash
cd ~/me/crou-mono
ax-first init   # default
# CLAUDE.md는 이미 있으므로 .ax-first/CLAUDE.md.suggested에 저장됨

# 수동 병합:
# 1. .ax-first/CLAUDE.md.suggested의 시그널 포맷(🔴🟡🔵)을 root CLAUDE.md에 적용
# 2. root CLAUDE.md의 도메인 룰을 apps/api/CLAUDE.md, apps/web/CLAUDE.md 등으로 분리

ax-first doctor
```

## 맞춤화

`.ax-first/config.yml`:

```yaml
domain_risk:
  payment: L3
  결제: L3
  routine: L1
  bible-reading: L1
  bookmark: L0

commands:
  build: "pnpm build"
  test: "pnpm test"
  lint: "pnpm lint"
  typecheck: "pnpm typecheck"
```

`apps/api/CLAUDE.md` (Layer 2 신규):

```markdown
# @crou/api — Module Rules

## 🔴 CRITICAL
- NestJS DI: `@UseGuards(JwtAuthGuard)` 사용 모듈은 `forwardRef(() => AuthModule)` import 필수
- 모듈 추가 시 `pnpm local:api` 기동 테스트 필수

## 🔵 CONVENTION
- 컨트롤러/서비스/모듈/엔티티/DTO 5종 디렉토리 구조
- Korean 주석
```

`apps/web/CLAUDE.md`:

```markdown
# @crou/web — Module Rules

## 🔴 CRITICAL
- SSR Hydration: JSX 안에서 `typeof window !== "undefined"` 분기 금지 → useEffect 패턴
- React 19 API만 사용, Mobile과 type 충돌 방지
```

`apps/mobile/CLAUDE.md`:

```markdown
# @crou/mobile — Module Rules

## 🔴 CRITICAL
- React 18.3 고정. React 19 API(useId, use 등) 사용 금지
- Hot Updater OTA 변경 시 네이티브 바이너리 영향 확인
```

## Triage 출력 예시

```bash
$ ax-first triage "북마크 정렬 옵션 추가"
🔍 ax-first triage
  size:    S
  risk:    L0
  domain:  bookmark
  path:    즉시 작업 + commit skill
  sensors: ktlint, eslint, tsc

$ ax-first triage "결제 환불 윈도우 7→14일"
🔍 ax-first triage
  size:    L
  risk:    L3
  domain:  payment 결제
  path:    task-machine 5-parallel + 도메인 페르소나 + ADR 강제
  sensors: ktlint, eslint, tsc, structural-check, integration tag, traffic estimation
  human gate: true
```

## 풀 플랜 문서

`/Users/stone/Documents/Claude/Projects/AX 플랫폼/crou-mono-harness-plan.md`
