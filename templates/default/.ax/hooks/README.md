# .ax/hooks — Sensors

AI 에이전트의 결과를 *작업 후* 자동 검증하는 sensor 4종(Computational/Inferential/Structural/Functional)을 hooks로 자동화해요.

| 위치 | 시점 | 역할 |
|---|---|---|
| pre-bash/ | bash 도구 호출 직전 | 파괴적 명령 차단 |
| pre-edit/ | Edit/Write 직전 | 보호 경로 변경 확인 |
| post-edit/ | Edit/Write 직후 | 변경 파일 lint (warning) |
| pre-commit/ | git commit 직전 | CRITICAL 룰 정적 검출 |

## 강도 모드

`.ax/config.yml`의 `sensors.mode`:
- warning — 출력만, 통과 (default)
- fail — exit 1로 차단

처음에는 warning, 데이터가 쌓이면 일부를 fail로 승격.

## 자기 프로젝트 맞춤화

- post-edit/lint-changed.sh — 자기 스택의 lint 명령으로 교체
- pre-commit/critical-rule-grep.sh — 자기 CRITICAL 룰의 정적 검출 패턴 추가
- 새 hook 추가 시 .claude/settings.json의 hooks 배열에 등록

## Claude Code 외 환경

git pre-commit hook으로도 등록 가능:

```bash
ln -sf "$(pwd)/.ax/hooks/pre-commit/critical-rule-grep.sh" .git/hooks/pre-commit
```
