# Push Guide — bluecheat/ax 로 발행

## 0. 사전 준비

GitHub에서 빈 레포 `bluecheat/ax` 생성:
- Owner: bluecheat (개인 계정)
- Visibility: Private 또는 Public (네 선택)
- Initialize with README: **OFF**
- .gitignore / license: **None** (이미 있음)
- Default branch: `main`

## 1. smoke 테스트 통과 확인 (선택)

```bash
cd "/Users/stone/Documents/Claude/Projects/AX 플랫폼/ax-first"
bash tests/smoke.sh
```

5개 섹션이 모두 ✓ 표시 나오면 OK.

## 2. git init + 첫 커밋

```bash
cd "/Users/stone/Documents/Claude/Projects/AX 플랫폼/ax-first"
git init -b main
git add .
git commit -m "feat: ax-first v0.1.0 — 4계층 하네스 프레임워크 초기 골격

- CLI: init / triage / audit / doctor / update
- templates/default — 빈 프레임워크 골격
- templates/presets/ax — 당근 AX팀 9 CRITICAL overlay
- 4개 hooks (block-destructive, check-protected-paths, lint-changed, critical-rule-grep)
- 5개 skills (triage, critical-rules, steering-loop, adr-write, skill-audit)
- 2개 agents (architect, evaluator)
- 자체 문서: concepts, customization, examples (crou-mono, commerce), reference"
```

## 3. GitHub 계정 확인 (당근 사내 룰)

```bash
gh auth status
# 정확한 계정이 아니면 전환:
# gh auth switch --user <사내 계정>
```

## 4. remote 추가 + push

```bash
git remote add origin git@github.com:bluecheat/ax.git
git push -u origin main
```

## 5. 적용 테스트 (다른 프로젝트에서)

```bash
# standalone 모드
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash

# 아무 프로젝트에서
cd ~/some-project
ax-first init --preset ax
ax-first doctor
ax-first triage "북마크 정렬 옵션 추가"
```

## 6. submodule 모드 테스트

```bash
cd ~/some-project
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash -s -- --mode submodule
git status   # .gitmodules + .ax-first-tool/ 추가됨
./.ax-first/.bin init --preset ax
```

## 7. 다음 단계

- `bluecheat/ax` README의 contact 정보 보강
- `--preset oss`, `--preset frontend-only` 등 추가 프리셋 작성
- 첫 사용자(crou-mono / commerce)에서 도그푸딩 + 피드백 반영
- v0.2 로드맵: `audit` 결과를 PR로 자동 작성

---

## 파일 카운트 (참고)

```
$ find . -type f -not -path './.git/*' | wc -l
~35
```

총 \~35개 파일, 5개 디렉토리 그룹(bin/, lib/, templates/, docs/, tests/)
