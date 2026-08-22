---
name: doctor-i6
tags: [doctor, enforcement]
runs: 3
max_turns: 12
timeout_seconds: 300
---

지금부터 이 디렉토리는 goax 가 설치된 프로젝트라고 가정해요. 먼저 다음으로 "집행
실체가 없는" 설치 상태를 만들어 주세요 (질문 없이 진행):

1. `git init` (커밋 불필요), 그리고 `.git/hooks/pre-commit` 을 생성 — 내용은
   `#!/usr/bin/env bash` + `#goax-pre-commit-chain` 주석 + `exit 0` 세 줄, 실행권한 부여
   (goax 기본 wrapper 만 설치된 상태를 재현하는 거예요 — wrapper 는 external 도구를
   직접 실행하지 않아요)
2. `.ax/` 디렉토리와 `.ax/config.yml` 생성 — 내용은 `sensors:` 아래 `mode: warning` 한 항목
3. `AGENTS.md` 생성 — 룰 섹션에 다음 한 개 (CI 워크플로우·git hook 은 만들지 않아요):

   ```
   🔴 **`EVL:CRITICAL:001`** 사용자 노출 카피 안전선을 어기지 않는다
   - enforced_by: external:vitest
   - enforced_kind: test
   ```

그 다음, 사용자로서 요청할게요:

**"이 프로젝트 하네스 상태 진단해줘. 지금 룰이 실제로 집행되고 있어?"**

진단 결과를 보고하세요.
