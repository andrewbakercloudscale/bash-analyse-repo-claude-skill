---
name: bash-analyse-repo-claude-skill
description: Analyse bash scripts in a repository and produce a prioritised actionable report with Critical, High, Medium, and Low findings. Triggers when the user asks to analyse, audit, review, or scan bash/shell scripts in a repo, or asks for a health check, quality report, or action plan for shell scripts.
---

# Bash Repository Analysis Skill

This skill analyses all bash scripts in the current repository and produces a prioritised, actionable report organised into Critical, High, Medium, and Low findings. Every finding includes a specific file, line reference, explanation, and concrete fix.

## When This Skill Applies

Invoke this skill when:
- User asks to "analyse", "audit", "review", or "scan" bash scripts
- User asks for a "health check", "quality report", or "action plan" for shell scripts
- User wants to know what needs fixing in their scripts
- User asks for a prioritised list of bash improvements

## Analysis Methodology

### Step 1 — Discover Scripts

Find all bash scripts in the repo:
```bash
# Find by shebang
grep -rl '#!/usr/bin/env bash\|#!/bin/bash' . \
  --include="*.sh" --include="*.bash" \
  --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="vendor"

# Also find extensionless scripts with bash shebang
grep -rl '#!/usr/bin/env bash\|#!/bin/bash' . \
  --exclude-dir=".git" --exclude-dir="node_modules"
```

### Step 2 — Run ShellCheck (if available)

```bash
# Run shellcheck on all found scripts
shellcheck --severity=style --format=json script.sh 2>/dev/null

# Map shellcheck severity to report severity:
# shellcheck error   → Critical or High
# shellcheck warning → High or Medium
# shellcheck info    → Medium
# shellcheck style   → Low
```

### Step 3 — Apply Pattern Analysis

For each script, check each pattern below and record findings.

### Step 4 — Produce Report

Format findings into the standard report structure (see Report Format section).

---

## Finding Severity Definitions

### CRITICAL
Issues that can cause **data loss, security vulnerabilities, or silent corruption** in production.

### HIGH
Issues that cause **unpredictable failures, broken error handling, or scripts that silently succeed when they should fail**.

### MEDIUM
Issues that reduce **maintainability, make scripts hard to debug, or create operational friction**.

### LOW
Issues that affect **consistency, documentation, or style** — important but not urgent.

---

## Pattern Catalogue

### CRITICAL Patterns

#### C1 — Unquoted Variable in Destructive Command
```bash
# BAD — $dir could be empty, running: rm -rf /
rm -rf $dir
rm -rf $file/*

# GOOD
rm -rf "${dir:?variable is empty}"
```
**Risk**: Empty variable → `rm -rf /` or equivalent.
**Fix**: Always quote variables. Use `${var:?error message}` to abort on empty.

#### C2 — Eval of User-Controlled Input
```bash
# BAD
eval "$user_input"
eval "echo $1"
```
**Risk**: Arbitrary code execution.
**Fix**: Never eval user input. Use arrays, parameter expansion, or case statements instead.

#### C3 — Credentials Hardcoded in Script
```bash
# BAD
PASSWORD="hunter2"
AWS_SECRET_KEY="AKIAIOSFODNN7EXAMPLE"
DB_PASS="mysecretpassword"
```
**Risk**: Credentials committed to git and exposed.
**Fix**: Use environment variables, AWS SSM Parameter Store, or secrets manager. Document the expected env var name.

#### C4 — Missing Error Check on Destructive Operation
```bash
# BAD — if cd fails, rm runs in wrong directory
cd /some/path
rm -rf *

# GOOD
cd /some/path || { echo "Error: Cannot cd to /some/path" >&2; exit 1; }
rm -rf *
```
**Risk**: Silent failure of cd/mkdir leads to unintended deletion or modification.
**Fix**: Always check return codes before destructive operations. Use `|| { ... ; exit 1; }`.

#### C5 — Using `set -e` Without `set -o pipefail`
```bash
# BAD — pipe failures are silently ignored
set -e
cat file | grep pattern | process  # if grep fails with no match, ignored

# ACCEPTABLE (but still discouraged — see H1)
set -e
set -o pipefail
```
**Risk**: Pipeline failures are invisible even with `set -e`.
**Fix**: If using `set -e`, always pair with `set -o pipefail`. Better: drop both and use explicit error handling (see H1).

---

### HIGH Patterns

#### H1 — Using `set -e` Instead of Explicit Error Handling
```bash
# BAD — set -e is unpredictable across shell versions and subshells
set -e
do_thing
do_other_thing

# GOOD — explicit and readable
if ! do_thing; then
    echo "Error: do_thing failed" >&2
    exit 1
fi
```
**Risk**: `set -e` exits silently with no context. Behaviour differs across bash versions.
**Fix**: Remove `set -e`. Add explicit `if !` or `|| { ... ; exit 1; }` checks on every command that matters.

#### H2 — No Guard Clause on Complex Script
```bash
# BAD — sourcing this script runs main() immediately
function main() { ... }
main "$@"

# GOOD
function main() { ... }
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
```
**Applies to**: Scripts > 30 lines OR scripts with multiple functions.
**Risk**: Cannot be safely sourced for testing or composition.
**Fix**: Add the guard clause at the very end of the script.

#### H3 — Missing Exit Code Check After Command
```bash
# BAD
aws s3 cp file.txt s3://bucket/
echo "Upload complete"  # always prints even if aws failed

# GOOD
if ! aws s3 cp file.txt s3://bucket/; then
    echo "Error: Upload failed" >&2
    exit 1
fi
echo "Upload complete"
```
**Risk**: Script continues and reports success after a failed operation.
**Fix**: Check return code of every significant command.

#### H4 — Unbound Variable Usage
```bash
# BAD — will silently use empty string
echo "Deploying to: $ENVIROMENT"  # typo, silently empty

# GOOD — declare at top of script with defaults or fail-fast
: "${ENVIRONMENT:?ENVIRONMENT must be set}"
```
**Risk**: Typos and missing env vars silently produce wrong behaviour.
**Fix**: Add `set -u` at the top, or use `${VAR:?error}` for required variables.

#### H5 — Insecure Temporary File Creation
```bash
# BAD — race condition and predictable path
TMPFILE=/tmp/script_output.txt
echo "data" > $TMPFILE

# GOOD
TMPFILE=$(mktemp)
trap "rm -f '$TMPFILE'" EXIT
```
**Risk**: Symlink attack; another process can pre-create the file.
**Fix**: Always use `mktemp`. Always `trap` cleanup on EXIT.

#### H6 — Missing Pipefail for Pipelines
```bash
# BAD — left side failures are hidden
cat file.txt | grep pattern | process_data

# GOOD
set -o pipefail
cat file.txt | grep pattern | process_data

# OR check PIPESTATUS explicitly
cat file.txt | grep pattern | process_data
[[ ${PIPESTATUS[0]} -eq 0 ]] || { echo "Error: cat failed" >&2; exit 1; }
```
**Risk**: Upstream pipeline failures are invisible.
**Fix**: Use `set -o pipefail` or check `${PIPESTATUS[@]}` after pipelines.

---

### MEDIUM Patterns

#### M1 — No Dependency Checking
```bash
# BAD — dies with cryptic error if jq missing
result=$(jq '.key' file.json)

# GOOD
DEPENDENCIES=(jq curl aws)
for cmd in "${DEPENDENCIES[@]}"; do
    command -v "$cmd" &>/dev/null || {
        echo "Error: Required tool '$cmd' is not installed" >&2
        exit 1
    }
done
```
**Fix**: Add a DEPENDENCIES array and check all tools at startup.

#### M2 — No Usage / Help Function
```bash
# BAD — script takes arguments but has no --help

# GOOD
function usage() {
    cat <<EOM
Description of what this script does.

usage: $(basename "$0") [options]

options:
    -e|--env     <name>    Environment name (required)
    -h|--help              Show this help

examples:
    $(basename "$0") --env production
EOM
    exit 1
}
```
**Applies to**: Any script that accepts arguments.
**Fix**: Add a `usage()` function. Handle `-h|--help` in the argument parser.

#### M3 — No Main Function Pattern
```bash
# BAD — logic at top level
echo "Starting..."
do_work
echo "Done"

# GOOD
function main() {
    echo "Starting..."
    do_work
    echo "Done"
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
```
**Applies to**: Scripts > 30 lines.
**Fix**: Wrap top-level logic in `main()`.

#### M4 — Function Longer Than 50 Lines
Large functions are hard to test, read, and maintain.
**Fix**: Break into single-responsibility sub-functions with descriptive names.

#### M5 — Non-Local Variables Inside Functions
```bash
# BAD — modifies global state
function process_file() {
    result="done"   # global leak
}

# GOOD
function process_file() {
    local result="done"
}
```
**Fix**: Always declare variables inside functions with `local`.

#### M6 — Errors Written to stdout
```bash
# BAD — error mixed into output stream
echo "Error: file not found"

# GOOD
echo "Error: file not found" >&2
```
**Fix**: All error and diagnostic messages go to stderr with `>&2`.

#### M7 — No Version Flag
Scripts used in CI or by multiple people should be versioned.
```bash
VERSION="1.0.0"
# In argument parser:
--version) echo "$(basename "$0") version ${VERSION}"; exit 0 ;;
```

#### M8 — Hardcoded Paths
```bash
# BAD
CONFIG="/home/ubuntu/app/config.json"

# GOOD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/../config/config.json"
```
**Fix**: Use `SCRIPT_DIR` pattern for relative paths. Accept paths as arguments.

---

### LOW Patterns

#### L1 — No Color / NO_COLOR Support
Scripts with user-facing output should respect `NO_COLOR`:
```bash
if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi
```

#### L2 — Missing Shebang Line
All scripts must start with `#!/usr/bin/env bash`.

#### L3 — Using `#!/bin/bash` Instead of `#!/usr/bin/env bash`
`/bin/bash` is not portable. Use `#!/usr/bin/env bash`.

#### L4 — No Purpose Comment at Top
Every script should have a brief comment explaining what it does, who runs it, and what it needs.

#### L5 — Inconsistent Naming Convention
Functions and variables should use `snake_case`. Avoid camelCase or mixed styles.

#### L6 — `echo` Used for Multi-line Output Instead of `cat <<EOM`
Use heredoc for multi-line messages — easier to read and edit.

#### L7 — `[ ]` Instead of `[[ ]]`
Prefer `[[ ]]` for conditionals in bash — more predictable, supports regex, no word-splitting issues.

#### L8 — Missing `chmod +x` Documentation
If users must make a script executable, document it in usage or README.

---

## Report Format

Produce the report in this exact structure:

```
╔══════════════════════════════════════════════════════════════╗
║           BASH REPOSITORY ANALYSIS REPORT                    ║
║           Generated: <date>                                   ║
║           Scripts analysed: <N>                              ║
╚══════════════════════════════════════════════════════════════╝

SUMMARY
───────────────────────────────────────────────────────────────
  🔴 Critical   <N> findings
  🟠 High       <N> findings
  🟡 Medium     <N> findings
  🔵 Low        <N> findings
  ─────────────────
  Total         <N> findings across <N> scripts


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 CRITICAL  — Fix before next deployment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[C1] Unquoted variable in destructive command
  File: deploy.sh:47
  Code: rm -rf $output_dir
  Why:  If $output_dir is empty or unset, this runs `rm -rf `
        which deletes the current directory.
  Fix:  rm -rf "${output_dir:?output_dir is not set}"

[C4] Missing error check before rm -rf
  File: cleanup.sh:23
  Code: cd "$TARGET"; rm -rf *
  Why:  If cd fails, rm runs in the caller's working directory.
  Fix:  cd "$TARGET" || { echo "Error: cannot cd to $TARGET" >&2; exit 1; }
        rm -rf *


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🟠 HIGH  — Fix this sprint
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[H1] set -e used instead of explicit error handling
  File: deploy.sh:3
  Code: set -e
  Why:  set -e exits silently with no error context. Behaviour
        differs across bash versions and inside subshells.
  Fix:  Remove set -e. Add explicit checks:
        if ! command; then echo "Error: ..." >&2; exit 1; fi

...


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🟡 MEDIUM  — Fix this month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

...


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔵 LOW  — Fix when convenient
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

...


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECOMMENDED ACTION ORDER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. [C4] cleanup.sh:23 — Add cd error check before rm -rf
2. [C1] deploy.sh:47  — Quote $output_dir in rm -rf
3. [H1] deploy.sh:3   — Remove set -e, add explicit checks
...

Say "fix [finding ID]" or "fix all critical" to start working through them.
```

---

## Analysis Instructions

When performing the analysis:

1. **Read every bash script** in the repo — do not sample.
2. **Apply all patterns** from the catalogue above to each script.
3. **Include exact file:line references** for every finding — no vague findings.
4. **Include the actual offending code** in the finding, not a description of it.
5. **ShellCheck integration**: If shellcheck is available, run it and incorporate results. Map shellcheck codes to the appropriate severity.
6. **Deduplicate**: If the same pattern appears 10 times in one file, list the first 3 occurrences and note "and N more in this file."
7. **Score scripts**: At the end of the report, include a per-script score table.
8. **Omit empty sections**: If there are no Critical findings, omit that section.
9. **Keep findings actionable**: Every finding must have a Fix that can be implemented immediately.

## Per-Script Score Table Format

```
SCRIPT HEALTH SCORES
───────────────────────────────────────────────────────────────
Script              Critical  High  Medium  Low   Grade
deploy.sh              2       3      1      2     F
sync.sh                0       1      3      1     C
cloudtorepo.sh         0       0      2      4     B
───────────────────────────────────────────────────────────────
Grade: A=0 findings, B=Low only, C=Medium+Low, D=High, F=Critical
```

---

## ShellCheck Code Mapping

| ShellCheck Code | Finding ID | Severity |
|----------------|-----------|----------|
| SC2035 | C1 | Critical |
| SC2046 | C1 | Critical |
| SC2006 | M5 | Medium |
| SC2034 | M5 | Medium |
| SC2086 | H3/C1 | High/Critical |
| SC2155 | M5 | Medium |
| SC2164 | C4 | Critical |
| SC1090 | L4 | Low |
| SC2015 | H3 | High |
| SC2181 | H3 | High |

---

## Quick Reference: Severity Decision Tree

```
Does the finding risk data loss, deletion, or secret exposure?
  YES → CRITICAL

Does the finding cause silent failure or broken error propagation?
  YES → HIGH

Does the finding make the script harder to maintain, debug, or operate?
  YES → MEDIUM

Does the finding affect style, documentation, or minor portability?
  YES → LOW
```
