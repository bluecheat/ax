# Spec — Layer 3

> 우리 프로젝트의 **도메인 정의·인터페이스·계약**을 기록하는 공간이에요.
> ADR은 *결정의 근거*(왜)를, Spec은 *도메인의 정의*(무엇)를 다뤄요.

## 디렉토리 구조

```
.ax/docs/spec/
├── _templates/          # 새 spec 시작 시 이 템플릿을 복사
│   ├── spec.md          # 문제·요구사항·NEEDS CLARIFICATION
│   ├── plan.md          # 접근 방법·트레이드오프
│   ├── tasks.md         # 작업 분해
│   ├── research.md
│   ├── data-model.md
│   ├── contracts/{api.yaml, events.md}
│   ├── quickstart.md
│   ├── checklists/requirements.md
│   └── README.md
├── NNN-<slug>/          # 작성된 spec (3자리 zero-pad + kebab-case)
└── imported/            # 외부 spec snapshot (onboarding Q4 [b]/[c])
```

## 새 spec 만드는 법

자연어 한 줄:

```
"새 spec 만들어줘 — payment-refund-window-extension"
```

→ `spec-new` skill이 다음 번호 계산 + `_templates/` 복사 + 디렉토리 생성.

## 작성 흐름 (SDD)

1. **spec.md** — 문제·요구사항·`NEEDS CLARIFICATION` 명시
2. **`spec-validate`** — `NEEDS CLARIFICATION` 0건 게이팅 통과
3. **plan.md** — 접근·트레이드오프
4. **tasks.md** — 작업 분해
5. 구현 → 검증 → commit
6. (L2/L3 도메인) 동반 ADR 작성 권장

## 외부 spec 처리

onboarding Q4에서 결정:

- `[a]` 링크만 — 외부 그대로 (SSOT 단일)
- `[b]` ★ SDD 포맷 변환 흡수 — 우리 templates 형식으로 wrap
- `[c]` snapshot raw copy
- `[d]` 무시

흡수된 외부 spec은 `imported/<name>/`에 원본 snapshot, 변환된 결과는 `NNN-<name>/`에.

## 큰 프로젝트에서 빠른 검색

`spec-validate`, `triage`, `audit`이 사전 검색에 활용해요:

```bash
# 도메인 키워드로 기존 spec 찾기
find .ax/docs/spec -maxdepth 2 -type d -name "*payment*"
grep -lE "payment|refund" .ax/docs/spec/*/spec.md

# NEEDS CLARIFICATION 누적 통계
grep -rc "NEEDS CLARIFICATION" .ax/docs/spec/*/

# 최근 수정된 spec
ls -lt .ax/docs/spec/*/spec.md 2>/dev/null | head -5

# imported snapshot의 SHA256 변경 감지
sha256sum -c .ax/docs/spec/imported/<name>/.snapshot-meta 2>/dev/null
```

## 연관

- ADR (결정): [`../adr/`](../adr/)
- Constitution (룰): root `CLAUDE.md`
- Spirit (태도): `.ax/spirit/`
