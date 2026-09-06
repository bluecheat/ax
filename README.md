# GOAX

<p align="center">
  <img src="goax_img.png" alt="GOAX — AX 4-Layer Harness" width="640">
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-D97757?logo=anthropic)](https://github.com/bluecheat/ax)
[![OpenCode Compatible](https://img.shields.io/badge/OpenCode-Compatible-blue)](https://opencode.ai/)
[![Lang](https://img.shields.io/badge/lang-한국어-blue.svg)](README.ko.md)

> **Control AI output consistency through the *environment*.**
> 4-layer harness — Triage · Constitution · Module · Spec/ADR. Cross-cut — Spirit · Mistake Loop.

**Equip the environment, not the prompt.** Install the plugin → a 5-minute onboarding conversation provisions the harness environment. No *automatic magic* promised.

> **Requirements** — Claude Code CLI · OpenCode (Hybrid compatibility). See [Multi-CLI compatibility](#multi-cli-compatibility) for the matrix.

[Quick Start](#quick-start) · [Architecture](#architecture) · [Spec Workflow](#spec-workflow--two-paths) · [Commands](#commands) · [Principles](#core-principles) · [More](#further-reading)

---

## Quick Start

**1. Install** — inside Claude Code, two lines:

```
/plugin marketplace add https://github.com/bluecheat/ax
/plugin install goax
```

**2. Adopt** — trigger via natural language:

```
"set up goax"
```

→ `up` analyzes the project, asks for consent (Y/n), and provisions `.ax/` (about 30s). On brownfield projects a 5-minute onboarding conversation (Q1–Q5) follows. Detailed flow: [`docs/up.md`](docs/up.md).

**3. Daily use** — drop intent in natural language; every task hits the same entry point and the same gating:

```
"plan the payment refund policy change"
   → triage → spec tier recommendation → spirit · rules · persona context injection
```

> OpenCode users: see [Multi-CLI compatibility](#multi-cli-compatibility).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 0  Triage         Intent interview (short input) + Size × Risk auto-classify │
│                          + UserPromptSubmit nudge (idle reminder)  │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1  Constitution    CLAUDE.md (root) — thin                   │
│                          ## META (4 guardrails) + signals + non-negotiables │
│                          🔴 CRITICAL / 🟡 MANDATORY / 🔵 CONVENTION │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2  Module Rules    .ax/modules/<n>/rules.md                  │
│                          keywords frontmatter → triage auto-grep matching │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3  Spec / ADR     .ax/docs/{spec, adr}/                     │
│                          SSOT, NEEDS CLARIFICATION gating          │
└─────────────────────────────────────────────────────────────────┘
       ▲                                       ▲
       │ Cross-cut: Spirit                     │ Cross-cut: Mistake Loop
       │ .ax/spirit/{values, tone, rules}      │ .ax/mistakes/ — manually captured (mistake skill)
       │ → shared attitude across sub-agents   │ → /audit review → promote to rule

Sensors (deterministic):  .ax/hooks/{user-prompt, pre-bash, pre-edit, post-edit, pre-commit, subagent-start, stop}/*.sh
Scripts (deterministic):  .ax/scripts/bash/*.sh — --json standard
```

### Universal vs Project-Specific

What GOAX provisions splits into two flavors:

| Flavor | Pre-registered (universal) | Consent-based (project-specific) |
|---|---|---|
| **META** (cognitive guard) | Triage First (lean — generic behavioral principles live in the opt-in `_templates/spirit/behavioral-baseline.md`) | — |
| **CRITICAL hooks** | Destructive commands / protected paths / secrets / hydration / Entity·SQL / Kotlin var | DDL conventions · module dependencies · test framework → onboarding asks [hook now / TODO later / demote] |
| **Behavioral** (Spirit) | `_templates/spirit/ops.md` SP-OPS-001–007 — opt-in template (user explicitly copies into `spirit/rules/`) | Category-specific extra rules |
| **Module rules** | — | `.ax/modules/<n>/rules.md` (only L2/L3 domains mapped in Q2 are stubbed) |

Principle: **Pre-register validated universal best practices; explicitly ask via onboarding when project judgment is required.**

Concept deep-dive: [`CONCEPTS.md`](CONCEPTS.md)

---

## Spec Workflow — Two Paths

The `spec` skill doesn't generate every artifact upfront. The triage result decides *just enough*.

### Tier Matrix

| Tier | Outputs | Applies to size × risk |
|---|---|---|
| **standard** | `spec.md` + `tasks.md` (2) | S/M/L × L0–L2 |
| **full** | + `research / data-model / quickstart / contracts` + paired ADR | L × L3 / XL × * |

### Fast Path — single phrase

```
"create spec payment-refund — full package"
```

### Stepwise Path — per stage

```
"create spec payment-refund"   → spec.md + tasks.md
"break into tasks"              → tasks breakdown ([P] parallel marker)
"start implementation"          → run tasks.md: sequential, or as lane coordinator when
                                  tasks carry lane assignments (lanes-dispatch.sh ledger)
                                  → completion gate G1–G6 (+ fresh-context evaluator for L / M×L3)
"split into lanes"              → lane — first asks whether the work can be split at all
# Design decisions go to ADR (.ax/docs/adr/NNNN-*.md)
```

Natural-language tier overrides: `"simple"` / `"spec + tasks"` → standard · `"full package"` → full. Design decisions live in ADR (`.ax/docs/adr/NNNN-*.md`), not a separate plan file.

---

## Commands

**Every feature is invoked via natural language.** The thin slash wrappers were retired; only `/goax` remains as a discoverability index. Skill `description:` frontmatter drives autorouting on both Claude Code and OpenCode.

| Phrase | Triggered skill |
|---|---|
| `/goax` | Index — shows all triggers (the only remaining slash command) |
| "set up goax" / "install goax" | up → onboarding (brownfield) or zero (greenfield) |
| "start a new project" / "from zero" | zero — 0→1 entry: product · business · ADR · enforcement plumbing |
| "vendor goax" | vendor — ship skills inside the repo without the plugin |
| "diagnose" / "goax doctor" | doctor — gap diagnosis + `_templates` drift |
| "show rules" / "critical rules only" | doctor → `rules-index.sh` — Constitution + Spirit + Module index |
| "create spec — <slug>" | spec — tier-aware spec generation |
| "break into tasks" | spec-tasks |
| "split into lanes" / "run in parallel" | lane — decides first whether the work can be split at all |
| "start implementation" / "run tasks" | spec-implement |
| "validate spec" | spec-validate — NEEDS CLARIFICATION gating |
| "plan the <task>" / "fix" / "refactor" | triage — Size × Risk classify in 30s |
| "write ADR" / "record decision" | adr — new ADR file |
| "spirit check" | doctor → `spirit-lint.sh` — header format · token duplicates · placeholders |
| "log a mistake" / "capture mistake" | mistake — single-event capture |
| "audit" / "review mistakes" | audit — Mistake Loop review · promotion |
| "/hud setup" / "activate statusline" | hud — Claude Code statusline (OpenCode adapter pending) |

When autorouting fails, fall back to keywords from the `/goax` index, or have the assistant call `Skill goax:<name>` explicitly.

---

## Core Principles

> **Deterministic work goes to scripts; judgment and interaction go to the LLM.**

- **Deterministic bash scripts** (`.ax/scripts/bash/`) — `--json --dry-run --help` standard, `[goax]` stderr prefix, exit 0/1/2 (graceful degradation). See [`templates/default/.ax/scripts/bash/README.md`](templates/default/.ax/scripts/bash/README.md) for the catalog.
- **`current-task.json`** — task-context SSOT shared between triage → spec → audit (no LLM re-inference)
- **`_templates/.origin`** — sha-compares user edits vs plugin shipped version; doctor surfaces drift. Never auto-overwrites.
- **Thin-wrapper SKILL.md** — deterministic parts delegated to scripts. SKILL handles only triggers, interaction, and JSON parsing.
- **Rebaseline over accumulate** — behavioral scaffolding is re-baselined per model generation: lean by default for frontier models (`model_tier: frontier`), full behavioral baseline opt-in for weaker models via `.ax/_templates/spirit/behavioral-baseline.md`. Instructions are restored per-item only when a failure actually recurs (ablation principle) — determinism (Sensors · Mistake Loop) is exempt from this depreciation.

---

## What Gets Installed

`up` skill (after consent) adds the following to your project:

```
your-project/
├── AGENTS.md                              # Layer 1 SSOT — multi-CLI Constitution
├── CLAUDE.md                              # @AGENTS.md alias for Claude Code auto-detection
├── opencode.json                          # OpenCode config (only if OpenCode env detected)
├── .ax/
│   ├── spirit/{values, tone, README}.md   # Cross-cut Spirit (shipped trio; rules/ is user-curated, ops.md is opt-in via _templates/spirit/)
│   ├── modules/                           # Layer 2 — per-module domain rules (instances only)
│   │   ├── README.md
│   │   └── <module-name>/rules.md         # onboarding Q5 stubs only L2/L3 domains
│   ├── hooks/                             # Sensors (deterministic)
│   │   ├── user-prompt/triage-nudge.sh    # idle-phase reminder (Claude Code only)
│   │   ├── pre-bash/{block-destructive,grep-on-commit}.sh
│   │   ├── pre-edit/{check-protected-paths,spirit-check,spirit-rules-inject}.sh
│   │   ├── pre-commit/{critical-rule-grep,check-mistake-secrets}.sh
│   │   └── post-edit/lint-changed.sh
│   ├── scripts/bash/*.sh                  # deterministic tools (--json standard)
│   │   └── install-git-hooks.sh           # OpenCode mode — git pre-commit chain installer
│   ├── _templates/                        # Layer 3 — all templates in one place
│   │   ├── adr/0000-template.md
│   │   └── spec/{spec, tasks, ...}.md  + .origin (drift sha)
│   ├── current-task.json                  # task-context SSOT
│   ├── config.yml                         # domain risk + sensors.mode
│   ├── mistakes/                          # Cross-cut Mistake Loop
│   ├── version
│   └── docs/
│       ├── adr/                           # Real ADRs (onboarding auto-generates 0001-goax-adoption.md)
│       ├── spec/                          # Real spec directory (NNN-<slug>/)
│       └── reference/                     # 7 read-only reference docs (copied from plugin docs/reference/)
└── .claude/
    └── settings.json                      # Hook registration (Claude Code only — UserPromptSubmit + PreToolUse + PostToolUse)
```

**That's everything added to your project tree.** Skills · commands · agents are auto-loaded by the plugin (Claude Code) or `opencode.json` `instructions:` (OpenCode).

---

## Multi-CLI compatibility

GOAX ships as a Claude Code plugin but works on OpenCode as well through a Hybrid compatibility layer.

| Asset | Claude Code | OpenCode | Note |
|---|---|---|---|
| `AGENTS.md` (Constitution SSOT) | ✅ via `@AGENTS.md` import chain | ✅ direct (priority 1) | multi-CLI SSOT |
| `CLAUDE.md` (alias) | ✅ native | ✅ fallback | One-line `@AGENTS.md` import |
| Skills (`.claude/skills/*/SKILL.md`) | ✅ autorouting | ✅ recognised ([docs](https://opencode.ai/docs/skills/)) | OpenCode [Issue #6177](https://github.com/sst/opencode/issues/6177) known plural/singular mismatch |
| Deterministic bash (`.ax/scripts/bash/`) | ✅ via Claude Code | ✅ via `GOAX_PROJECT_DIR=$pwd` | `--json --dry-run --help` CLI-agnostic |
| Hooks — PreToolUse / PostToolUse | ✅ `.claude/settings.json` | ❌ not supported | OpenCode plugin SDK is TypeScript in-process only |
| Hooks — pre-commit | ✅ via `grep-on-commit.sh` | ⚠️ via `install-git-hooks.sh` (git native pre-commit) | CATASTROPHIC + secrets checks preserved at commit time |
| Slash commands | ✅ `/goax` index | ❌ `.claude/commands/` not read ([Issue #6985](https://github.com/anomalyco/opencode/issues/6985)) | slash wrappers retired — natural language only |
| Mistake auto-capture (hook) | ✅ deprecated → manual | ❌ manual only | User-invoked `/mistake` on both CLIs |
| HUD statusline | ✅ Claude Code spec | ⚠️ adapter pending | Claude Code only for now |

### OpenCode install

OpenCode has no `/plugin` marketplace, so vendor the harness directly:

```bash
git clone https://github.com/bluecheat/ax .ax-source && \
  cp -r .ax-source/templates/default/* . && \
  rm -rf .ax-source

bash .ax/scripts/bash/install-git-hooks.sh
```

Rename `opencode.json.template` → `opencode.json` so OpenCode merges `AGENTS.md` into its system prompt automatically.

### OpenCode environment notes

- If you already installed the Claude Code plugin, `up` skill auto-detects OpenCode via `OPENCODE_CONFIG_DIR`, `.opencode/`, `~/.config/opencode/`, or `command -v opencode` and runs the vendoring above for you.
- `OPENCODE_DISABLE_CLAUDE_CODE=1` etc. supported — goax stays safe with either default (AGENTS.md is the SSOT either way).
- Path-scoped Spirit rule injection (`spirit-rules-inject.sh`) is Claude Code only. On OpenCode, import the rule files into `AGENTS.md`'s CONVENTION section to make them universal.

Full compatibility detail, troubleshooting, and TypeScript plugin roadmap: [`docs/reference/opencode-compat.md`](docs/reference/opencode-compat.md).

---

## HUD — one line, harness position only

The statusline shows **where you are in the harness** and nothing else. Model, context %, agents and todos belong to OMC HUD; lanes, gates and alerts belong to skill output and `doctor`.

```
[goax#0.5.1] | M×L2 · payment | spec ✓ › tasks ✓ › impl ● [######----]7/12 › review ○ | mistakes:3
```

| Segment | Meaning |
|---|---|
| `[goax#0.5.1]` | Installed version. `[goax#0.5.1] -> 0.5.2 goax up` when the plugin is newer |
| `M×L2 · payment` | Triage result (Size×Risk, domain). `idle` when nothing is active |
| `spec ✓ › tasks ✓ › impl ● 7/12 › review ○` | Workflow chain for M+ work. `✓` done · `●` current · `○` next. S shows `즉시 작업` instead. Full tier adds `adr`; `review` appears only when the evaluator is required |
| `mistakes:3` | Accumulated mistakes (yellow ≥5, red ≥10) |

Presets follow OMC HUD naming — `minimal` / `focused` (default) / `full` — via `.ax/config.yml` `hud.preset`. The script reads files only (no subprocess scripts) so it fits the 300ms statusline debounce; heavier values are cached by `update-state.sh` and flagged `(stale)` after 30 minutes.

Enable:

```
/hud setup
```

If another statusline (e.g. OMC) is already configured, `setup` offers a combined script that feeds stdin to **both** commands — concatenating two commands does not work, the first one consumes stdin.

## Updates

```
/plugin marketplace update goax
/plugin install goax
```

That's all. Just stay on the latest.

---

## Security model

goax installs **shell scripts into your repository** and registers them as Claude Code hooks. Two things follow from that, and both are worth understanding before you adopt it.

**1. Hooks are a safety net, not a security boundary.**

The hooks (`block-destructive.sh`, `check-protected-paths.sh`, the pre-commit chain) are bash pattern matching. They are designed to catch *accidents* — an agent or a person doing something destructive by mistake. They are **not** designed to stop someone who is trying to get around them, and they cannot be: a shell command string can express the same action in unlimited ways, and any hook can be sidestepped by using a tool path it does not watch (`sed -i` instead of `Edit`, `git commit --no-verify`, editing in an IDE).

So read 🔴 CRITICAL as *"you will not pass this by accident"*, not *"this cannot be bypassed"*. If you need a real trust boundary — running untrusted code, isolating credentials — use a sandbox, permission separation, or a CI gate. goax does not replace those. See [`docs/reference/rule-enforcement.md`](docs/reference/rule-enforcement.md) for the full contract.

**2. `.ax/` is executable code that travels with your repository.**

`.ax/hooks/**/*.sh`, `.ax/scripts/bash/*.sh`, and `.claude/settings.json` are meant to be committed — that is how the harness stays consistent across your team. The consequence is that **cloning a repository that uses goax and opening it in Claude Code means running shell scripts that repository supplied.** Claude Code's own trust prompt is the gate here, but treat a third-party `.ax/` the same way you would treat any other executable content in a repo you did not write: read it before you trust it.

For your own repositories this is exactly the point — the harness is version-controlled alongside the code it governs. For repositories from elsewhere, review `.ax/hooks/` and `.claude/settings.json` in the diff.

---

## Further Reading

- [`CONCEPTS.md`](CONCEPTS.md) — the design rationale, why it's built this way
- [`docs/sdd.md`](docs/sdd.md) — Spec-Driven Development
- [`docs/spirit.md`](docs/spirit.md) — Spirit operating guide
- [`docs/skill-routing.md`](docs/skill-routing.md) — Skill routing matrix
- [`docs/up.md`](docs/up.md) — Brownfield adoption flow
- [`changelog/0.1.0.md`](changelog/0.1.0.md) "Design decisions" — Rejected alternatives + adoption rationale (consolidated from old docs/adr/ × 6)
- [`templates/default/.ax/scripts/bash/README.md`](templates/default/.ax/scripts/bash/README.md) — Deterministic script catalog + `--json` standard
- [`changelog/`](changelog/README.md) — Release notes (not strictly user-facing)

---

## License

MIT License. See [`LICENSE`](LICENSE) for the full text.
