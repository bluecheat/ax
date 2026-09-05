# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is **goax** — a Claude Code Plugin that ships a 4-layer harness (Triage / Constitution / Module / Spec·ADR) plus two cross-cuts (Spirit / Mistake Loop) into user projects. There is no application code, no build system, no package manager. The plugin is **bash + markdown only**.

`README.md` has the user-facing overview. `CONCEPTS.md` is the design rationale (Korean). The two should agree with the code; if you change behavior, update both.

## Common commands

```bash
bash tests/smoke.sh    # only test runner — validates JSON manifests, skill frontmatter, shell syntax, hook paths, script standards
cat VERSION            # current plugin version (must match plugin.json + marketplace.json — smoke test enforces)
```

There is no `npm`/`make`/`gradle`. Anything more complex is invoked through Claude Code itself (`/plugin install goax`, then a skill like `up` or `doctor`).

## Repository layout (what each top-level dir does)

- `.claude-plugin/{plugin.json,marketplace.json}` — Claude Code plugin manifest. Both files plus `VERSION` must hold the **same version string** (smoke test fails otherwise).
- `skills/<name>/SKILL.md` — 17 skills (`up`, `onboarding`, `zero`, `doctor`, `rules`, `spec`, `spec-{tasks,implement,validate}`, `lane`, `audit`, `mistake`, `spirit`, `hud`, `triage`, `adr`, `vendor`). Each starts with frontmatter `name:` + `description:` where description is the trigger-keyword bag. Note: `install` was renamed to `up` (0.1.18), `spec-plan` was retired (0.1.16), `mistake` was added as the capture-only counterpart to `audit`. **`zero` and `lane` were added in 0.5.0** (`lane` was born as `parallel` and renamed in 0.5.1 — the unit of the skill is the lane, and the agents `lane-*` and scripts `lanes-*` already carried that name) — `zero` is the 0→1 entry point (`up` §6 hands greenfield to it; `onboarding` stays brownfield-only), and `lane` sits between `spec-tasks` and `spec-implement` to decide whether the work can be split at all.
- `commands/goax.md` — single slash-command index that delegates to skills (other thin per-skill wrappers were retired).
- `agents/{architect,evaluator,lane-scout,lane-worker}.md` — sub-agents invoked by skills. `evaluator` is the Generator/Evaluator separation: `spec-implement` §8 spawns it in a fresh context and it writes `<spec>/review.md` whose first line is `verdict: 진행|보강 필요|재논의 필요`; `tasks-gate.sh` G6 reads that line. `lane-scout`/`lane-worker` are the read-only investigation lane and the file-ownership execution lane that `spec-implement` runs in lane mode.
- `scripts/provision.sh` — the installer. `up` calls it with `--json`; it reads MANIFEST and copies `templates/default/` into the user project. Lives at the plugin root (not `templates/default/.ax/scripts/`) because it *creates* `.ax/` — it cannot live inside what it installs. Root `install.sh` is an unrelated legacy stub that only prints install instructions.
- `templates/default/` — **everything that gets copied into a user project** when the `up` skill runs.
- `templates/default/MANIFEST` — installer SSOT. `up` reads this line-by-line; lines ending in `/` are recursive directory copies, `src -> dst` lines do rename copies. **When you add anything under `templates/default/`, update MANIFEST or the installer will not copy it.** Conditional copies (CLAUDE.md, settings.json, config.yml, mistakes/README.md, .gitignore) are intentionally outside MANIFEST and live in `skills/up/SKILL.md` §5–§6.
- `templates/default/.ax/scripts/bash/` — deterministic shell tooling (31 scripts). All follow the standard in `templates/default/.ax/scripts/bash/README.md`: `set -euo pipefail`, `--json --dry-run --help` options, `[goax]` stderr prefix, exit codes `0` ok / `1` error / `2` skipped. Their `--json` shape is `{status, result, next_step, warnings, errors}`. SKILL.md files invoke these and parse the JSON; they do not reimplement the logic inline.
- `templates/default/.ax/hooks/{user-prompt,pre-bash,pre-edit,post-edit,pre-commit}/*.sh` — sensors. The companion `.claude/settings.json.template` registers them; `doctor` cross-checks installed hooks against this template (it is the SSOT for which hooks should be registered).
- `templates/default/.ax/spirit/{values.md,tone.md,README.md}` — cross-cut Spirit (shared agent personality), the trio the plugin ships. `spirit/rules/` is user-curated (no plugin-shipped instances) — categories get added via onboarding/audit, seeded from `_templates/spirit/ops.md` as an opt-in baseline. Spirit rule headers must match `## SP-<CAT>-<NNN>: text` — `doctor` lints this.
- `templates/default/.ax/_templates/{spec,adr,module,spirit,mistakes}/` — SDD templates the user copies into their own work. `_templates/spec/.origin` is a sha snapshot the installer writes; `check-templates-drift.sh` diffs current vs `.origin` to detect user edits vs plugin updates.
- `templates/default/CLAUDE.md.template` — the Layer 1 Constitution that lands in user projects (do not confuse with this file).
- `docs/reference/{rules-tokens,critical-rules,glossary,triage-matrix,rule-enforcement,confirmation-policy,opencode-compat}.md` — read-only reference (7 files). The installer copies the whole `docs/reference/` directory into `.ax/docs/reference/` in user projects, so user-facing docs (CLAUDE.md.template, spirit rules) reference these paths.
- `changelog/<version>.md` — release notes. One file per version.
- `tests/smoke.sh` — single shell test. The structural contract for the whole plugin lives here; read it first if you change file layout, frontmatter, or version strings.

## Architecture — the harness model

Three things must stay true together or the design breaks:

1. **Determinism boundary.** Anything reproducible (number assignment, sha, slug normalization, file generation, drift detection) lives in `.ax/scripts/bash/` and is invoked by SKILL.md via `--json`. SKILL.md handles only triggers, conversation, and JSON parsing. Do not move deterministic logic back into SKILL.md as inline bash.

2. **MANIFEST is the install contract.** `templates/default/MANIFEST` is the only thing the `up` skill iterates over for unconditional copies. Adding a directory or file to `templates/default/` without updating MANIFEST means it will not land in user projects, and `doctor` will flag it as missing.

3. **Two-step adoption.** `up` skill provisions the skeleton with one Y/n consent prompt. For brownfield projects (existing CLAUDE.md, hooks, multiple modules, or external spec), `up` writes `.ax/.onboarding-pending` and hands off to the `onboarding` skill, which runs a 5-step Q1–Q5 conversation that maps domains, risk levels, and rule categories. Do not collapse these into a single mega-prompt; the staging is the design.

## Skill conventions

- Every SKILL.md begins with `## 시작 전 필수` declaring it loads `.ax/spirit/values.md` and `tone.md`. Triage explicitly fails if those are missing.
- Tone throughout the plugin is Korean **`~해요` 체** — this is a deliberate consistency choice (see CONCEPTS §4.1, §7.3) and applies to all user-facing text including SKILL.md bodies, error messages, and ✓ confirmations.
- Skills update `.ax/state.json` (HUD signals) and `.ax/current-task.json` (triage→spec→audit context handoff) at well-defined points. Use the existing helpers (`update-state.sh`, jq tmp-mv pattern) — do not invent new state files.
- The `${CLAUDE_SKILL_DIR}` env var is the official Claude Code variable for finding the plugin root (`${CLAUDE_SKILL_DIR}/../..`). `${CLAUDE_PLUGIN_ROOT}` exists only as a legacy fallback. Do not introduce other variable names.
- `spec-implement` is the only executor. It runs single-lane (sequential) unless `tasks.md` carries `레인:` ledger fields, in which case it is the coordinator: it stamps `디스패치:` via `lanes-dispatch.sh`, spawns `lane-worker` agents, stamps `보고:` when a report arrives, re-runs the task's `검증:` command itself, and only then flips the checkbox. Lanes never flip checkboxes and never write the ledger. Completion is `tasks-gate.sh` G1–G6; G5 is the ledger, G6 is the fresh-context `evaluator` verdict. The coordinator must not write `review.md` itself. When you add an execution edge (who invokes whom), wire it in the receiving SKILL.md, not just in the sender — the `lane`→`spec-implement` and triage-matrix→`evaluator` handoffs were prose-only until they were wired here.

## Rule enforcement invariants

`templates/default/CLAUDE.md.template` and `docs/reference/rule-enforcement.md` mandate `enforced_by` schema invariants that `templates/default/.ax/scripts/bash/check-rule-enforcement.sh` checks and `doctor` reports:

- **I1**: 🔴 CRITICAL rules must have `enforced_by: hook:*` or `external:*` only — never `TODO:*`, `human:*`, or `script:*`. If you write a CRITICAL rule without a matching hook, downgrade to 🟡 MANDATORY first.
- **I2**: `enforced_by: TODO:*` requires a deadline (`YYYY-MM-DD` or `+Nd`/`+Nw`).
- **I5**: `enforced_by: hook:<path>` requires the hook file to exist *and* be registered in `.claude/settings.json`.

When editing rule content, run `bash templates/default/.ax/scripts/bash/check-rule-enforcement.sh --json` against a project that has the templates installed to verify.

## Versioning

The version string lives in **three places** and they must match:
- `VERSION`
- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → `version` (top-level *and* inside `plugins[0]`)

`tests/smoke.sh` compares all three and fails on mismatch. When bumping, also add `changelog/<new-version>.md`.

## What not to do

- Do not write a CLAUDE.md at a non-root path of this repo claiming to be Layer 2 module rules — this repo is the plugin source, not a project that consumes the plugin. The Layer 2 mechanism applies to *user projects* that install goax.
- Do not edit user-project files when working in this repo (i.e. nothing in `.ax/` *outside* `templates/default/.ax/`). The `.ax/` at the repo root is this Claude session's own state, not part of the plugin payload.
- Do not bypass the determinism boundary by inlining bash heredocs in SKILL.md when an existing script could be extended. Beyond the design rule there is a concrete cost: bash inside a markdown fence is not a file, so `shellcheck` and the `bash -n` sweep never saw it. `tests/smoke.sh` §30 now extracts and lints those blocks, but a real script is still the right home.
- Do not embed version markers (e.g. `(NEW 0.1.8+)`) in plugin docs/code; they rot fast and break re-reads.
