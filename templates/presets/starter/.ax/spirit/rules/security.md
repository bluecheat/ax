---
category: security
applies_to: [code, pr, commit]
---

# Security

> 우리 팀의 보안 룰을 여기에 추가하세요.
> 작성법: `docs/reference/rules-tokens.md`

<!--
ID 컨벤션: SP-SEC-NNN (3자리)
다음 ID: 003 (자동 검사: goax spirit lint)
-->

## SP-SEC-001: Secrets는 환경변수 또는 vault 경유 (예시)

평문 password / api_key / token / private key 코드 내 하드코딩 금지.

✅ `process.env.API_KEY`, `os.environ["DB_PASSWORD"]`
❌ `const KEY = "sk-abc123..."`

검출 패턴: `(password|secret|api[_-]?key|token).*=.*["']`

---

## SP-SEC-002: <자기 팀 보안 룰 #2>

<여기에 본문을 작성하세요. 위 양식을 참고.>

