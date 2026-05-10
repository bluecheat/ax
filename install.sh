#!/usr/bin/env bash
# goax — Claude Code Plugin
# 이 스크립트는 더 이상 설치를 수행하지 않아요. plugin으로 전환됐어요.

cat <<'INFO'
goax는 Claude Code Plugin이에요.

설치 방법 (Claude Code 안에서 두 줄):

  /plugin marketplace add https://github.com/bluecheat/ax
  /plugin install goax

설치 후 자연어 한 줄:

  "goax 도입해줘"

→ `up` skill 이 발동해서 .ax/ 골격을 깔아요. (이미 깔려있으면 idempotent update.)
brownfield 프로젝트면 onboarding으로 자연스럽게 이어가요.

자세히: https://github.com/bluecheat/ax
INFO
