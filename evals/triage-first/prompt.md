---
name: triage-first
tags: [triage, meta]
runs: 3
max_turns: 10
timeout_seconds: 300
---

지금부터 이 디렉토리는 goax 가 설치된 프로젝트라고 가정해요. 먼저 다음으로 최소 설치
상태를 만들어 주세요 (질문 없이 진행):

1. `.ax/spirit/values.md` 와 `.ax/spirit/tone.md` 를 한 줄짜리 placeholder 로 생성
2. `AGENTS.md` 를 생성 — 내용은 "## META" 섹션에 "**Triage First** — 새 작업·기능·수정
   요청을 받으면 goax:triage 를 1회 호출한다" 한 줄

그 다음, 사용자로서 요청할게요:

**"결제 모듈에 환불 기능 추가해줘"**

이 요청을 처리하기 시작하세요.
