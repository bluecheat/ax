# goax

<p align="center">
  <img src="goax_img.png" alt="goax — AX 4-Layer Harness" width="640">
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-D97757?logo=anthropic)](https://github.com/bluecheat/ax)
[![Lang](https://img.shields.io/badge/lang-한국어-blue.svg)](README.ko.md)

> **Control AI output consistency through the *environment*.**
> 4-layer harness — Triage · Constitution · Module · Spec/ADR. Cross-cut — Spirit · Mistake Loop.

**Equip the environment, not the prompt.** Install the plugin → a 5-minute onboarding conversation provisions the harness environment. No *automatic magic* promised.

> **Requirements** — Claude Code CLI

[Quick Start](#quick-start) · [Architecture](#architecture) · [Spec Workflow](#spec-workflow--two-paths) · [Commands](#commands) · [Principles](#core-principles) · [More](#further-reading)

---

## Quick Start

**Step 1 — Install**

Inside Claude Code, run *one line at a time*:

```
/plugin marketplace add https://github.com/bluecheat/ax

/plugin install goax
```

**Step 2 — Adopt**

Trigger via natural language.

```
"set up goax"
```

→ `up` analyzes the project, asks a consent prompt (Y/n), then provisions `.ax/` (about 30s).
For **brownfield** projects (with existing assets), `onboarding` follows up and walks through domain · risk level · hooks intensity · external specs · layer activation as a **5-step Q1–Q5 conversation** (about 5 minutes). It's not *one-shot magic* — it's a flow designed to elicit deliberate decisions.

**Step 3 — Daily use**

```
"plan the payment refund policy change"
   → triage → spec tier recommendation → spirit · rules · persona context injection
```

Once the skeleton is in place, every task goes through the same entry point and the same gating.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 0  Triage         Auto-classify Size × Risk on task entry    │
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
       │ .ax/spirit/{values, tone, rules}      │ .ax/mistakes/ — auto-captured by hooks
       │ → shared attitude across sub-agents   │ → /audit review → promote to rule

Sensors (deterministic):  .ax/hooks/{user-prompt, pre-bash, pre-edit, post-edit, pre-commit}/*.sh
Scripts (deterministic):  .ax/scripts/bash/*.sh — --json standard
```

### Universal vs Project-Specific

What goax provisions splits into two flavors:

| Flavor | Pre-registered (universal) | Consent-based (project-specific) |
|---|---|---|
| **META** (cognitive guard) | 4 core guardrail principles — identical across projects | — |
| **CRITICAL hooks** | Destructive commands / protected paths / secrets / hydration / Entity·SQL / Kotlin var | DDL conventions · module dependencies · test framework → onboarding asks [hook now / TODO later / demote] |
| **Behavioral** (Spirit) | `ops.md` SP-OPS-001–007 (MANDATORY behavior directives / Generator-Evaluator / no-warning-suppression) | Category-specific extra rules |
| **Module rules** | — | `.ax/modules/<n>/rules.md` (only L2/L3 domains mapped in Q2 are stubbed) |

Principle: **Pre-register validated universal best practices; explicitly ask via onboarding when project judgment is required.**

Concept deep-dive: [`CONCEPTS.md`](CONCEPTS.md)

---

## Spec Workflow — Two Paths

`spec-new` doesn't generate all 9 files upfront. The triage result decides *just enough*.

### Tier Matrix

| Tier | Outputs | Applies to size × risk |
|---|---|---|
| **standard** | `spec.md` + `tasks.md` (2) | S/M/L × L0–L2 |
| **full** | + `research / data-model / quickstart / contracts` + paired ADR | L × L3 / XL × * |

### Fast Path — Single Command

```
/spec --tier full payment-refund
```

### Stepwise Path — Per-stage

```
/spec --tier standard payment-refund  → spec.md + tasks.md
/spec-tasks                                 → tasks breakdown ([P] parallel marker)
/spec-implement                             → run tasks.md sequentially + - [x] marking
# Design decisions go to ADR (.ax/docs/adr/NNNN-*.md)
```

Natural language overrides: `"simple"` / `"spec + tasks"` → standard · `"full package"` → full. Design decisions live in ADR (`.ax/docs/adr/NNNN-*.md`), not a separate plan file.

---

## Commands

### Slash Commands

| Command | What it does | Natural language alias |
|---|---|---|
| `/goax` | Help / index | — |
| `/doctor` | Gap diagnosis + `_templates` drift | "diagnose" |
| `/rules` | Constitution + Spirit + Module aggregation | "show rules" |
| `/spec` | Tier-aware spec generation (one-shot) | "create spec — <slug>" |
| `/spec-tasks` | tasks.md stage | "break into tasks" |
| `/spec-implement` | Sequential execution + checklist marking | "start implementation" |
| `/spec-validate` | NEEDS CLARIFICATION gating | "validate spec" |
| `/audit` | Mistake Loop capture · review · promotion | "audit", "again that" |

### Natural Language Only (no slash command)

| Phrase | Triggered skill |
|---|---|
| "set up goax" | up → onboarding (auto-delegated) |
| "plan the <task>" | triage → spec-new (tier auto-recommended) |
| "spirit check" | spirit-check |
| "write ADR" | adr-write |
| "activate statusline" | hud setup |

---

## Core Principles

> **Deterministic work goes to scripts; judgment and interaction go to the LLM.**

- **10 bash scripts** (`.ax/scripts/bash/`) — `--json --dry-run --help` standard, `[goax]` stderr prefix, exit 0/1/2 (graceful degradation)
- **`current-task.json`** — task-context SSOT shared between triage → spec → audit (no LLM re-inference)
- **`_templates/.origin`** — sha-compares user edits vs plugin shipped version; doctor surfaces drift. Never auto-overwrites.
- **Thin-wrapper SKILL.md** — deterministic parts delegated to scripts. SKILL handles only triggers, interaction, and JSON parsing.

---

## What Gets Installed

`up` skill (after consent) adds the following to your project:

```
your-project/
├── CLAUDE.md                              # Layer 1 (.suggested if one already exists)
├── .ax/
│   ├── spirit/{values, tone, rules}/      # Cross-cut Spirit (includes ops.md)
│   ├── modules/                           # Layer 2 — per-module domain rules (instances only)
│   │   ├── README.md
│   │   └── <module-name>/rules.md         # onboarding Q5 stubs only L2/L3 domains
│   ├── hooks/                             # Sensors (deterministic)
│   │   ├── user-prompt/triage-nudge.sh    # idle-phase reminder
│   │   ├── pre-bash/{block-destructive,grep-on-commit}.sh
│   │   ├── pre-edit/{check-protected-paths,spirit-check}.sh
│   │   ├── pre-commit/critical-rule-grep.sh
│   │   └── post-edit/lint-changed.sh
│   ├── scripts/bash/*.sh                  # 9 deterministic tools (incl. capture-mistake)
│   ├── current-task.json                  # task-context SSOT
│   ├── config.yml                         # domain risk + sensors.mode
│   ├── mistakes/                          # Cross-cut Mistake Loop (hook auto-capture)
│   ├── version
│   └── docs/
│       ├── _templates/                    # Layer 3 — all templates in one place
│       │   ├── adr/0000-template.md
│       │   └── spec/{spec, tasks, ...}.md  + .origin (drift sha)
│       ├── adr/                           # Real ADRs (onboarding auto-generates 0001-goax-adoption.md)
│       └── spec/                          # Real spec directory (NNN-<slug>/)
└── .claude/
    └── settings.json                      # Hook registration (UserPromptSubmit + PreToolUse + PostToolUse)
```

**That's everything added to your project tree.** Skills · commands · agents are auto-loaded by the plugin.

---

## HUD — One-line Layer Status (fact-based)

The statusline has a **single design** (no presets). Three core signals on one line:

```
triage: M×L3 | harness: 🪐 | ☄3       ← task active
harness: 🪐 | ☄3                       ← no task (idle)
```

### Signal 1 — `triage: <Size>×<Risk>` (color matrix)

Instantly read current task size · risk by color:

- **Size**: S=dim · M=cyan · L=yellow · XL=red
- **Risk**: L0=dim · L1=green · L2=yellow · L3=red

All 16 matrix combinations are color-distinct.

### Signal 2 — `harness: <evolution>` (4-layer aggregate)

Plugin's 4-layer activation as *cosmic evolution* stages:

| Active | Emoji | Meaning | Color |
|---|---|---|---|
| 0/4 | `·` | Singularity (origin) | dim |
| 1/4 | `✦` | First starlight | yellow |
| 2/4 | `⭐` | Stellar formation | yellow |
| 3/4 | `🌟` | Shining star | green |
| 4/4 | `🪐` | Elegant planet (complete) | cyan |

### Signal 3 — `☄<n>` (mistakes count)

Cumulative mistake count. Cosmic metaphor stays consistent (comet = collision event):

- 0=dim · 1–4=plain · 5–9=yellow · 10+=red

### Live Refresh

The statusline auto-refreshes *after each assistant message* (Claude Code spec). For periodic refresh during idle, add `refreshInterval` to `.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": ".ax/hud/statusline.sh",
    "refreshInterval": 5
  }
}
```

Re-runs every 5s — instantly reflects spec/tasks progress when background work updates them.

### How to Activate

```
/hud setup
```

Or add `statusLine` directly to `.claude/settings.json`. If another plugin's statusLine conflicts, `setup` offers a merge option.

---

## Updates

```
/plugin marketplace update goax
/plugin install goax
```

That's all. Just stay on the latest.

---

## Further Reading

- [`CONCEPTS.md`](CONCEPTS.md) — 14 core concept cards (why it's built this way)
- [`docs/sdd.md`](docs/sdd.md) — Spec-Driven Development
- [`docs/spirit.md`](docs/spirit.md) — Spirit operating guide
- [`docs/skill-routing.md`](docs/skill-routing.md) — Skill routing matrix
- [`docs/up.md`](docs/up.md) — Brownfield adoption flow
- [`changelog/0.1.0.md`](changelog/0.1.0.md) "Design decisions" — Rejected alternatives + adoption rationale (consolidated from old docs/adr/ × 6)
- [`templates/default/.ax/scripts/bash/README.md`](templates/default/.ax/scripts/bash/README.md) — 10-script standard
- [`changelog/`](changelog/README.md) — Release notes (not strictly user-facing)

---

## License

MIT License. See [`LICENSE`](LICENSE) for the full text.
