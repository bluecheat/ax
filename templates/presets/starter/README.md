# starter Preset

`goax init --preset starter`로 활성화되는 프리셋.

## 무엇이 추가되는가

1. **CLAUDE.md.overlay** — 어디에나 유용한 3 CRITICAL + 2 MANDATORY + 3 CONVENTION이 기존 CLAUDE.md 끝에 append.

## 적용 후 첫 작업

- `CLAUDE.md`에 추가된 룰 중 우리 프로젝트에 안 맞는 것 삭제·조정.
- `.ax/config.yml`의 `domain_risk` 매트릭스를 우리 도메인으로 갱신.
- `goax doctor`로 결손 검사.

## 자기 프리셋 만들기

`templates/presets/<name>/`에 다음 구조로 만들면 `--preset <name>`로 사용 가능:

```
templates/presets/<name>/
├── CLAUDE.md.overlay              # 기존 CLAUDE.md 끝에 append
├── README.md                      # 프리셋 설명
└── (선택) .ax/                    # 프리셋 한정 skill/agent/hook
```
