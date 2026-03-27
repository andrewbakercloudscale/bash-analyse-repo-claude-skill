# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Purpose

This is a Claude Skill package that analyses bash scripts in a repository and produces a prioritised, actionable report with Critical, High, Medium, and Low findings. It is designed to be used as a Claude Code skill — either globally or per-project.

## Development Commands

```bash
# Test the analyser script
chmod +x scripts/analyse.sh
./scripts/analyse.sh --dir /path/to/repo

# Test with JSON output (requires jq)
./scripts/analyse.sh --dir /path/to/repo --json | jq '.summary'

# Test with shellcheck integration
./scripts/analyse.sh --dir /path/to/repo --shellcheck

# Syntax check the analyser itself
bash -n scripts/analyse.sh

# Test against this repo's own scripts
./scripts/analyse.sh --dir .
```

## Architecture

### SKILL.md
The main skill definition. Contains:
- Frontmatter with name and trigger description
- Full pattern catalogue (C1–C5 Critical, H1–H6 High, M1–M8 Medium, L1–L8 Low)
- Report format template with exact output structure
- Analysis instructions for Claude
- ShellCheck code mapping table

### scripts/analyse.sh
A standalone bash script that performs automated pattern detection. It:
- Discovers all .sh/.bash files plus extensionless bash scripts
- Runs grep/awk pattern checks for each finding category
- Optionally runs shellcheck and incorporates results
- Outputs plain text or JSON

The script feeds Claude the raw findings data. Claude then:
1. Merges automated findings with its own code reading
2. Deduplicates and contextualises
3. Formats the final report per the SKILL.md template

### Skill Activation
The skill triggers when users ask to "analyse", "audit", "review", or "scan" bash scripts, or ask for a quality/health report on shell scripts.

## Severity Levels

| Level    | Meaning                                          | Action         |
|----------|--------------------------------------------------|----------------|
| Critical | Data loss, security, silent corruption risk      | Fix immediately |
| High     | Broken error handling, silent failures           | Fix this sprint |
| Medium   | Maintainability, operational friction            | Fix this month  |
| Low      | Style, documentation, portability                | Fix when convenient |

## Testing Strategy

1. Run `./scripts/analyse.sh --dir /path/to/test-repo` against a known-bad script
2. Verify each pattern fires correctly
3. Syntax check: `bash -n scripts/analyse.sh`
4. ShellCheck the analyser itself: `shellcheck scripts/analyse.sh`
