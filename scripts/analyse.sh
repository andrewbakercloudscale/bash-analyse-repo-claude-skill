#!/usr/bin/env bash
# Purpose: Scan a directory of bash scripts and emit structured findings as JSON.
#          Used by the bash-analyse-repo-claude-skill to feed Claude the raw data
#          it needs to produce a prioritised report.
#
# Usage:   ./analyse.sh [--dir <path>] [--json] [--shellcheck]
# Output:  Human-readable summary to stdout, or JSON with --json flag

SCRIPT_NAME=$(basename "$0")
VERSION="1.0.0"
DEPENDENCIES=(bash grep find)

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" YELLOW="" GREEN="" BLUE="" CYAN="" NC=""
fi

function usage() {
    cat <<EOM

Scan bash scripts in a directory and output structured analysis findings.

usage: ${SCRIPT_NAME} [options]

options:
    -d|--dir        <path>    Directory to scan (default: current directory)
    -j|--json                 Output findings as JSON instead of plain text
    -s|--shellcheck           Run shellcheck on each script if available
    -v|--verbose              Show each script as it is scanned
    --version                 Print version and exit
    -h|--help                 Show this help message

dependencies: ${DEPENDENCIES[*]}
optional:     shellcheck (https://www.shellcheck.net)

examples:
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --dir ./scripts --shellcheck
    ${SCRIPT_NAME} --json | jq '.findings[] | select(.severity=="CRITICAL")'

EOM
    exit 1
}

function main() {
    local scan_dir="."
    local output_json=false
    local run_shellcheck=false
    local verbose=false

    while [[ "$1" != "" ]]; do
        case $1 in
        -d | --dir)
            shift
            scan_dir="$1"
            ;;
        -j | --json)
            output_json=true
            ;;
        -s | --shellcheck)
            run_shellcheck=true
            ;;
        -v | --verbose)
            verbose=true
            ;;
        --version)
            echo "${SCRIPT_NAME} version ${VERSION}"
            exit 0
            ;;
        -h | --help)
            usage
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            usage
            ;;
        esac
        shift
    done

    if [[ ! -d "$scan_dir" ]]; then
        echo "Error: Directory '${scan_dir}' does not exist" >&2
        exit 1
    fi

    exit_on_missing_tools "${DEPENDENCIES[@]}"

    local scripts=()
    while IFS= read -r -d '' file; do
        scripts+=("$file")
    done < <(find "$scan_dir" \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/vendor/*" \
        \( -name "*.sh" -o -name "*.bash" \) \
        -print0 2>/dev/null)

    # Also find extensionless files with bash shebang
    while IFS= read -r -d '' file; do
        local first_line
        first_line=$(head -1 "$file" 2>/dev/null)
        if [[ "$first_line" == "#!/usr/bin/env bash"* ]] || [[ "$first_line" == "#!/bin/bash"* ]]; then
            # Avoid duplicates
            local already=false
            for s in "${scripts[@]}"; do [[ "$s" == "$file" ]] && already=true && break; done
            [[ "$already" == false ]] && scripts+=("$file")
        fi
    done < <(find "$scan_dir" \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -maxdepth 3 \
        -type f \
        ! -name "*.sh" ! -name "*.bash" \
        -print0 2>/dev/null)

    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo "No bash scripts found in '${scan_dir}'" >&2
        exit 0
    fi

    [[ "$verbose" == true ]] && echo -e "${CYAN}Found ${#scripts[@]} bash scripts${NC}" >&2

    if [[ "$output_json" == true ]]; then
        output_json_report "$scan_dir" "$run_shellcheck" "$verbose" "${scripts[@]}"
    else
        output_text_report "$scan_dir" "$run_shellcheck" "$verbose" "${scripts[@]}"
    fi
}

function output_text_report() {
    local scan_dir="$1"
    local run_shellcheck="$2"
    local verbose="$3"
    shift 3
    local scripts=("$@")

    echo ""
    echo -e "${BLUE}Bash Script Analysis — ${scan_dir}${NC}"
    echo -e "${BLUE}Scripts found: ${#scripts[@]}${NC}"
    echo ""

    local critical=0 high=0 medium=0 low=0

    for script in "${scripts[@]}"; do
        [[ "$verbose" == true ]] && echo -e "${CYAN}  Scanning: ${script}${NC}" >&2

        local findings
        findings=$(scan_script "$script" "$run_shellcheck")
        if [[ -n "$findings" ]]; then
            echo -e "${YELLOW}── ${script} ──${NC}"
            echo "$findings"
            echo ""
            critical=$((critical + $(echo "$findings" | grep -c '^\[CRITICAL\]' || true)))
            high=$((high + $(echo "$findings" | grep -c '^\[HIGH\]' || true)))
            medium=$((medium + $(echo "$findings" | grep -c '^\[MEDIUM\]' || true)))
            low=$((low + $(echo "$findings" | grep -c '^\[LOW\]' || true)))
        fi
    done

    local total=$((critical + high + medium + low))
    echo ""
    echo -e "${BLUE}Summary${NC}"
    echo -e "  ${RED}Critical: ${critical}${NC}"
    echo -e "  ${YELLOW}High:     ${high}${NC}"
    echo -e "  Medium:   ${medium}"
    echo -e "  ${CYAN}Low:      ${low}${NC}"
    echo -e "  Total:    ${total}"
}

function output_json_report() {
    local scan_dir="$1"
    local run_shellcheck="$2"
    local verbose="$3"
    shift 3
    local scripts=("$@")

    local all_findings="[]"

    for script in "${scripts[@]}"; do
        [[ "$verbose" == true ]] && echo -e "${CYAN}  Scanning: ${script}${NC}" >&2
        local findings
        findings=$(scan_script_json "$script" "$run_shellcheck")
        # Merge arrays — requires jq
        if command -v jq &>/dev/null; then
            all_findings=$(echo "$all_findings $findings" | jq -s '.[0] + .[1]')
        fi
    done

    local date_str
    date_str=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v jq &>/dev/null; then
        jq -n \
            --arg date "$date_str" \
            --arg dir "$scan_dir" \
            --argjson scripts "${#scripts[@]}" \
            --argjson findings "$all_findings" \
            '{
                generated: $date,
                directory: $dir,
                scripts_count: $scripts,
                findings: $findings,
                summary: {
                    critical: ($findings | map(select(.severity=="CRITICAL")) | length),
                    high:     ($findings | map(select(.severity=="HIGH"))     | length),
                    medium:   ($findings | map(select(.severity=="MEDIUM"))   | length),
                    low:      ($findings | map(select(.severity=="LOW"))      | length),
                    total:    ($findings | length)
                }
            }'
    else
        echo '{"error":"jq is required for JSON output"}' >&2
        exit 1
    fi
}

function scan_script() {
    local file="$1"
    local run_shellcheck="$2"

    # Pattern checks — emit [SEVERITY] lines

    # C1 — Unquoted variable in rm
    grep -n 'rm -rf \$[A-Za-z_][A-Za-z0-9_]*[^"]' "$file" 2>/dev/null | while IFS=: read -r lineno line; do
        echo "[CRITICAL] C1: Unquoted variable in rm -rf — line ${lineno}: ${line}"
    done

    # C4 — cd without error check followed by rm
    awk '/^[[:space:]]*cd / && !/\|\|/ && !/if !/ { found=NR; cdline=$0 }
         found && NR==found+1 && /rm/ { print found": "cdline }' "$file" 2>/dev/null | while IFS=: read -r lineno line; do
        echo "[CRITICAL] C4: cd without error check before rm — line ${lineno}: ${line}"
    done

    # C3 — Hardcoded secrets
    grep -inE "(PASSWORD|SECRET|API_KEY|PRIVATE_KEY|TOKEN|AWS_SECRET)[[:space:]]*=[[:space:]]*['\"][^'\"\$]{4,}" "$file" 2>/dev/null | while IFS=: read -r lineno line; do
        echo "[CRITICAL] C3: Possible hardcoded credential — line ${lineno}: ${line}"
    done

    # C2 — eval of variable
    grep -nE '^[[:space:]]*eval[[:space:]]+["$]' "$file" 2>/dev/null | while IFS=: read -r lineno line; do
        echo "[CRITICAL] C2: eval of variable input — line ${lineno}: ${line}"
    done

    # H1 — set -e
    grep -n 'set -e\b\|set -[a-z]*e[a-z]*' "$file" 2>/dev/null | grep -v 'set -eo pipefail\|set -euo' | while IFS=: read -r lineno line; do
        echo "[HIGH] H1: set -e used — line ${lineno}: ${line}"
    done

    # H2 — no guard clause (for scripts with functions)
    if grep -q 'function ' "$file" 2>/dev/null; then
        if ! grep -q 'BASH_SOURCE\[0\]' "$file" 2>/dev/null; then
            echo "[HIGH] H2: No guard clause (script has functions but no BASH_SOURCE guard)"
        fi
    fi

    # H6 — pipefail missing when pipelines present
    if grep -qE '[^|]\|[^|]' "$file" 2>/dev/null; then
        if ! grep -q 'pipefail' "$file" 2>/dev/null && ! grep -q 'PIPESTATUS' "$file" 2>/dev/null; then
            echo "[HIGH] H6: Pipelines present but no pipefail or PIPESTATUS check"
        fi
    fi

    # M1 — no dependency checking
    if grep -qE '(jq|curl|aws|docker|kubectl|terraform|helm) ' "$file" 2>/dev/null; then
        if ! grep -qE 'command -v|which |type ' "$file" 2>/dev/null; then
            echo "[MEDIUM] M1: External tools used but no dependency checking"
        fi
    fi

    # M2 — no usage/help
    local line_count
    line_count=$(wc -l < "$file" 2>/dev/null || echo 0)
    if [[ "$line_count" -gt 30 ]]; then
        if ! grep -qE '\-\-help|\-h\b|usage\(\)' "$file" 2>/dev/null; then
            echo "[MEDIUM] M2: Script >30 lines but no usage/help function"
        fi
    fi

    # M3 — no main function
    if [[ "$line_count" -gt 30 ]]; then
        if ! grep -q 'function main\|^main()' "$file" 2>/dev/null; then
            echo "[MEDIUM] M3: Script >30 lines but no main() function"
        fi
    fi

    # M6 — errors to stdout
    grep -nE 'echo.*[Ee]rror[^>]*$' "$file" 2>/dev/null | grep -v '>&2' | head -3 | while IFS=: read -r lineno line; do
        echo "[MEDIUM] M6: Error message not redirected to stderr — line ${lineno}: ${line}"
    done

    # M8 — hardcoded absolute paths
    grep -nE '"/(home|var|etc|usr|opt)/[^"]*"' "$file" 2>/dev/null | head -3 | while IFS=: read -r lineno line; do
        echo "[MEDIUM] M8: Hardcoded absolute path — line ${lineno}: ${line}"
    done

    # L2/L3 — shebang
    local shebang
    shebang=$(head -1 "$file" 2>/dev/null)
    if [[ -z "$shebang" ]] || [[ "$shebang" != "#!/"* ]]; then
        echo "[LOW] L2: Missing shebang line"
    elif [[ "$shebang" == "#!/bin/bash"* ]]; then
        echo "[LOW] L3: Using #!/bin/bash — prefer #!/usr/bin/env bash"
    fi

    # L1 — no NO_COLOR support (for scripts with color codes)
    if grep -q 'RED=\|GREEN=\|YELLOW=' "$file" 2>/dev/null; then
        if ! grep -q 'NO_COLOR' "$file" 2>/dev/null; then
            echo "[LOW] L1: Color output defined but NO_COLOR not respected"
        fi
    fi

    # L7 — single bracket
    grep -ncE '[^[][[[:space:]]' "$file" 2>/dev/null | while read -r count; do
        [[ "$count" -gt 2 ]] && echo "[LOW] L7: ${count} uses of [ ] — prefer [[ ]] in bash"
    done

    # ShellCheck integration
    if [[ "$run_shellcheck" == true ]] && command -v shellcheck &>/dev/null; then
        shellcheck --severity=warning --format=gcc "$file" 2>/dev/null | while IFS= read -r line; do
            echo "[SHELLCHECK] ${line}"
        done
    fi
}

function scan_script_json() {
    local file="$1"
    local run_shellcheck="$2"
    local findings="[]"

    local text_findings
    text_findings=$(scan_script "$file" "$run_shellcheck")

    if [[ -z "$text_findings" ]]; then
        echo "[]"
        return
    fi

    if ! command -v jq &>/dev/null; then
        echo "[]"
        return
    fi

    echo "$text_findings" | while IFS= read -r finding; do
        local severity code message
        severity=$(echo "$finding" | grep -oE '^\[(CRITICAL|HIGH|MEDIUM|LOW|SHELLCHECK)\]' | tr -d '[]')
        code=$(echo "$finding" | grep -oE '[A-Z][0-9]+:' | tr -d ':')
        message=$(echo "$finding" | sed 's/^\[[A-Z]*\] //')
        echo "{\"file\":\"${file}\",\"severity\":\"${severity}\",\"code\":\"${code}\",\"message\":\"${message}\"}"
    done | jq -s '.'
}

function exit_on_missing_tools() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required tool '${cmd}' is not installed or not in PATH" >&2
            exit 1
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
