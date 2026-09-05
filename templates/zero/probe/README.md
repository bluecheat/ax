# 네거티브 프로브 — "막힌다" 를 증명하고, 계속 증명하기

> 게이트를 깔았다는 사실과 게이트가 막는다는 사실은 다른 사실이에요.
> 실증 프로젝트에서 CI 가 **의존성 설치 실패로 한 번도 안 돌면서 초록**이었어요.
>
> policy-as-code 실무의 같은 경고: *"통제를 집행하는 것처럼 보이는 룰이 조용히 'false' 가
> 아니라 'undefined' 로 평가될 수 있고, undefined 는 denied 와 다르다."*
>
> **그래서 첫날 1회로 끝내지 않아요.** 프로브를 파일로 만들어 CI 에서 매 푸시마다 돌려요.

## 프로브 계약

`.ax/probes/<name>.sh` 파일 하나 = 프로브 하나. 러너는 `zero-probe.sh` 예요.

- 첫 줄 주석 `# probe: <설명>` — 보고에 실려요
- 스스로 **위반을 만들고 → 게이트를 돌리고 → 되돌리고 → 판정**해요
- **게이트가 막았으면 exit 0** · 못 막았으면 **exit 1** · 돌릴 수 없으면 **exit 2**(skip)
- 게이트 명령에 **파이프를 붙이지 않아요** — `cmd | tail` 의 종료 코드는 tail 것이에요
- 워킹 트리를 건드렸으면 `trap cleanup EXIT` 로 반드시 되돌려요 (다른 세션이 같은 트리에 있어요)

```bash
bash .ax/scripts/bash/zero-probe.sh --list          # 무엇이 등록됐나
bash .ax/scripts/bash/zero-probe.sh --json          # 전부 돌리기 (CI 가 이걸 씁니다)
bash .ax/scripts/bash/zero-probe.sh --only secret-scan
```

## 시작하는 법

`.ax/_templates/zero/probes/` 의 예시를 `.ax/probes/` 로 복사해서 프로젝트에 맞게 고쳐요.
예시 셋이 세 가지 전형을 덮습니다.

| 예시 | 무엇을 재나 |
|---|---|
| `dependency-direction.sh` | 코드 위반을 만들고 **lint 가 막는지** |
| `secret-scan.sh` | 위반 파일을 스테이지하고 **pre-commit 훅이 막는지** |
| `ci-actually-ran.sh` | CI 가 성공했는지가 아니라 **게이트 출력이 로그에 있는지** |

첫날엔 2~3개면 충분해요. 게이트를 하나 새로 깔 때마다 프로브도 하나 늘려요 —
**게이트와 프로브는 짝**이에요.

## 언어별 위반 만들기

게이트 명령만 갈아 끼우면 나머지는 같아요.

```bash
# TypeScript · ESLint 경계
printf "import React from 'react';\n" > packages/core/src/__probe__.ts
npx eslint packages/core/src/__probe__.ts --no-inline-config      # --no-inline-config 필수
```

`--no-inline-config` 가 없으면 `// eslint-disable` 한 줄로 우회돼요.

```bash
# Python · import-linter
printf 'import app.web\n' > src/core/_probe.py
lint-imports
```

```bash
# Go
printf 'package core\nimport _ "example.com/app/web"\n' > internal/core/probe_x.go
go build ./...
```

```bash
# 도구가 없는 스택 — grep 최소본. 정확도가 낮아도 0 보다 커요
grep -rn "from '\.\./\.\./app" packages/core/src && exit 1
```

사용자 약속 계약(`SP-CTR-001`)의 프로브는 코드가 아니라 픽스처예요 — 약속을 어긴 입력을
하나 넣고 테스트를 돌려요. 통과하면 그 약속은 아직 계약이 아니라 문서예요.

## 기록

첫날 프로브 결과는 배관 커밋 메시지나 ADR 에 한 줄씩 남겨요. 이후로는 CI 가 대신 말해요.

```
probe: core→react import → eslint exit 2 (차단 확인)
probe: 시크릿 스테이지 → pre-commit exit 1 (차단 확인)
probe: CI 로그에 게이트 출력 4줄 (실행 확인)
```
