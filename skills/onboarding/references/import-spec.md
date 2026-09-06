# 외부 spec → SDD 변환 — Q4 [b]

> sibling 디렉토리(`<repo>-spec` 등)나 자기 안의 `spec/` `specs/` `governance/` 를 우리 SDD 형식으로 흡수할 때의 규칙이에요.
> [a] 링크만 / [c] snapshot 만 / [d] 무시 는 변환이 없어요 — 이 문서는 [b] 에만 필요해요.

## 변환 규칙

| 원본 | 변환 후 | 변환 방식 |
|---|---|---|
| `<src>/specs/<name>.md` | `.ax/docs/spec/NNN-<name>/spec.md` | 원본을 spec.md template `## Specification` 섹션 본문으로. frontmatter (status, source) 추가 |
| `<src>/policies/<name>.md` | `.ax/docs/spec/NNN-<name>/policy.md` 또는 spec.md `## Policy` 섹션 | 정책 카테고리로 wrap |
| `<src>/adr/<name>.md` | `.ax/docs/adr/NNNN-<name>.md` | ADR 다음 번호로 재할당 (`next-spec-num.sh --kind adr --reserve`). `imported_from:` frontmatter |
| `<src>/docs/<name>.md` | `.ax/docs/spec/NNN-<name>/research.md` | 배경 문서로 |
| 원본 전체 | `.ax/docs/spec/imported/<name>/` snapshot | re-sync 용 보관 |

번호는 손으로 정하지 않아요 — `next-spec-num.sh --kind spec|adr --reserve --slug <slug>` 가 원자적으로 선점해요.

## 변환 파일 frontmatter

```yaml
---
imported_from: ../<src>/specs/<name>.md
imported_at: 2026-05-02
status: imported # draft / accepted / superseded 로 사용자가 갱신
---
```

## `.snapshot-meta`

`.ax/docs/spec/imported/<name>/.snapshot-meta` 에 원본 파일별 SHA256 을 기록해요 → 다음 onboarding/audit 시 외부 변경을 감지해요.

```
<sha256>  specs/payment-refund.md
<sha256>  adr/0007-idempotency.md
```

## 보고

```
✓ Q4 — .ax/docs/spec/ N개 SDD 변환 + adr/ K개 재번호 + imported/<name>/ snapshot (.snapshot-meta M 파일)
```

`triage-search.sh` 가 `imported/` 를 별도 카테고리로 검색해요 — specs 와 섞이지 않아요.
