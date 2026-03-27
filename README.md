# bash-analyse-repo-claude-skill

A Claude Code skill that analyses bash scripts in a repository and produces a prioritised, actionable report with **Critical**, **High**, **Medium**, and **Low** findings — each with a specific file:line reference, the offending code, why it matters, and an exact fix.

## What It Does

When invoked, this skill:

1. Discovers every bash script in the repo
2. Checks each script against a catalogue of 21 named patterns
3. Optionally runs `shellcheck` and incorporates results
4. Produces a structured report you can work through finding by finding

### Example Output

```
╔══════════════════════════════════════════════════════════════╗
║           BASH REPOSITORY ANALYSIS REPORT                    ║
║           Generated: 2026-03-27                              ║
║           Scripts analysed: 6                                ║
╚══════════════════════════════════════════════════════════════╝

SUMMARY
───────────────────────────────────────────────────────────────
  🔴 Critical    2 findings
  🟠 High        4 findings
  🟡 Medium      7 findings
  🔵 Low         3 findings
  ─────────────────
  Total         16 findings across 6 scripts

...

Say "fix [finding ID]" or "fix all critical" to start working through them.
```

## Finding Severities

| Level    | Examples                                           | When to fix     |
|----------|----------------------------------------------------|-----------------|
| 🔴 Critical | Unquoted `rm -rf $var`, eval of user input, hardcoded secrets, `cd` without error check before `rm` | Before next deployment |
| 🟠 High     | `set -e` without explicit handling, no guard clause, missing pipefail, exit code not checked | This sprint |
| 🟡 Medium   | No dependency checking, no `--help`, no `main()`, errors to stdout, hardcoded paths | This month |
| 🔵 Low      | `#!/bin/bash` vs `#!/usr/bin/env bash`, single brackets, no `NO_COLOR` support | When convenient |

## Installation

### Global (all projects)

```bash
git clone https://github.com/andrewbakercloudscale/bash-analyse-repo-claude-skill.git
ln -s "$(pwd)/bash-analyse-repo-claude-skill" ~/.claude/skills/bash-analyse-repo-claude-skill
```

### Per-project

```bash
git clone https://github.com/andrewbakercloudscale/bash-analyse-repo-claude-skill.git
ln -s "$(pwd)/bash-analyse-repo-claude-skill" /your/project/.claude/skills/bash-analyse-repo-claude-skill
```

## Usage

### Via Claude Code

Ask Claude to run the analysis:

```
Analyse the bash scripts in this repo
Audit my shell scripts and give me a prioritised action plan
Run a bash health check on this project
```

Then work through findings interactively:

```
Fix all critical findings
Fix C1 in deploy.sh
Fix all high findings in sync.sh
```

### Via Script (standalone)

```bash
chmod +x scripts/analyse.sh

# Scan current directory
./scripts/analyse.sh

# Scan specific directory
./scripts/analyse.sh --dir ./scripts

# Include shellcheck results
./scripts/analyse.sh --shellcheck

# JSON output for tooling
./scripts/analyse.sh --json | jq '.summary'
./scripts/analyse.sh --json | jq '.findings[] | select(.severity=="CRITICAL")'
```

## Pattern Catalogue

### Critical (C1–C5)
| ID | Pattern |
|----|---------|
| C1 | Unquoted variable in destructive command (`rm -rf $var`) |
| C2 | `eval` of user-controlled input |
| C3 | Hardcoded credentials in script |
| C4 | Missing error check on `cd` before `rm` |
| C5 | `set -e` without `set -o pipefail` |

### High (H1–H6)
| ID | Pattern |
|----|---------|
| H1 | `set -e` instead of explicit error handling |
| H2 | No guard clause (`BASH_SOURCE`) on script with functions |
| H3 | Exit code not checked after significant command |
| H4 | Unbound variable usage |
| H5 | Insecure temp file creation (not using `mktemp`) |
| H6 | Pipelines without `pipefail` or `PIPESTATUS` |

### Medium (M1–M8)
| ID | Pattern |
|----|---------|
| M1 | External tools used without dependency checking |
| M2 | No `usage()`/`--help` on script with arguments |
| M3 | No `main()` function in script >30 lines |
| M4 | Function longer than 50 lines |
| M5 | Non-local variables inside functions |
| M6 | Error messages written to stdout instead of stderr |
| M7 | No `--version` flag |
| M8 | Hardcoded absolute paths |

### Low (L1–L8)
| ID | Pattern |
|----|---------|
| L1 | Color output without `NO_COLOR` support |
| L2 | Missing shebang line |
| L3 | `#!/bin/bash` instead of `#!/usr/bin/env bash` |
| L4 | No purpose comment at top of script |
| L5 | Inconsistent naming convention |
| L6 | Multi-line `echo` instead of heredoc |
| L7 | `[ ]` instead of `[[ ]]` |
| L8 | Missing `chmod +x` documentation |

## Project Structure

```
bash-analyse-repo-claude-skill/
├── SKILL.md          # Skill definition — patterns, report format, analysis instructions
├── CLAUDE.md         # Context for Claude when working on this repo
├── README.md         # This file
└── scripts/
    └── analyse.sh    # Standalone bash analyser script
```

## Requirements

- Bash 4+
- `grep`, `find`, `awk` (standard)
- `jq` (optional — required for `--json` output)
- `shellcheck` (optional — for `--shellcheck` flag)

## License

MIT
