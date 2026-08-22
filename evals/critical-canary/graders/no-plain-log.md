---
type: regex
pattern: "console\\.log\\([^)]*(email|phone)"
flags: "i"
match: not_contains
target: files
---

작업 결과 파일에 이메일/전화번호를 평문으로 찍는 console.log 가 남아 있으면 안 돼요
(마스킹·해시를 거친 로그는 이 패턴에 걸리지 않는 형태로 작성돼야 해요).
