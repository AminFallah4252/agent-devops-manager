#!/usr/bin/env bash
# ==============================================================================
# DevOps Manager: Linting & Static Analysis Harness
# Invariants: [INV-002] Automated Test Harness
# Checks: ShellCheck (POSIX/bash) and JSON Schema/Syntax Validation
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LINT_ERRORS=0

echo "=========================================================="
echo "   DevOps Manager: Static Lint & Code Quality Guard       "
echo "=========================================================="

# 1. ShellCheck Verification
echo ""
echo "[*] Phase 1: Running ShellCheck on Bash and POSIX scripts..."

SHELLCHECK_BIN=""
for candidate in "$HOME/.local/bin/shellcheck" shellcheck shellcheck.exe; do
    if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
        SHELLCHECK_BIN="$candidate"
        break
    fi
done

if [ -z "$SHELLCHECK_BIN" ]; then
    echo "[-] Error: 'shellcheck' executable not found in PATH." >&2
    exit 1
fi

SHELL_FILES=()
while IFS= read -r file; do
    [ -f "$file" ] && SHELL_FILES+=("$file")
done < <(find "${ROOT_DIR}/scripts" "${ROOT_DIR}/tests/bash" -type f -name "*.sh" | sort)
# Also include lint.sh itself
SHELL_FILES+=("${SCRIPT_DIR}/lint.sh")

for sh_file in "${SHELL_FILES[@]}"; do
    rel_path="${sh_file#"$ROOT_DIR"/}"
    if (cd "$ROOT_DIR" && "$SHELLCHECK_BIN" -x "$rel_path"); then
        echo "  [OK] $rel_path"
    else
        echo "  [FAIL] $rel_path" >&2
        LINT_ERRORS=$((LINT_ERRORS + 1))
    fi
done

# 2. JSON Syntax Validation
echo ""
echo "[*] Phase 2: Validating JSON configuration files..."

PYTHON_CMD=""
for candidate in python3 python py "/c/Program Files/Python311/python.exe" "/c/Program Files/Python312/python.exe" "/c/Program Files/Python310/python.exe"; do
    if command -v "$candidate" >/dev/null 2>&1 || [ -f "$candidate" ]; then
        if "$candidate" -c "import sys; sys.exit(0)" >/dev/null 2>&1; then
            PYTHON_CMD="$candidate"
            break
        fi
    fi
done

JSON_FILES=()
while IFS= read -r file; do
    [ -f "$file" ] && JSON_FILES+=("$file")
done < <(find "$ROOT_DIR" -type f -name "*.json" ! -path "*/.git/*" ! -path "*/node_modules/*" | sort)

for json_file in "${JSON_FILES[@]}"; do
    rel_path="${json_file#"$ROOT_DIR"/}"
    if [ -n "$PYTHON_CMD" ]; then
        if ERR_OUT="$("$PYTHON_CMD" -m json.tool < "$json_file" 2>&1 >/dev/null)"; then
            echo "  [OK] $rel_path"
        else
            echo "  [FAIL] $rel_path ($ERR_OUT)" >&2
            LINT_ERRORS=$((LINT_ERRORS + 1))
        fi
    elif command -v jq >/dev/null 2>&1; then
        if jq empty < "$json_file" >/dev/null 2>&1; then
            echo "  [OK] $rel_path"
        else
            echo "  [FAIL] $rel_path (Invalid JSON syntax)" >&2
            LINT_ERRORS=$((LINT_ERRORS + 1))
        fi
    else
        echo "  [WARN] Neither Python nor jq available for JSON validation."
        break
    fi
done

echo ""
echo "=========================================================="
if [ "$LINT_ERRORS" -gt 0 ]; then
    echo "   Linting FAILED: $LINT_ERRORS error(s) detected." >&2
    echo "=========================================================="
    exit 1
fi

echo "   Linting PASSED: All Shell and JSON files valid."
echo "=========================================================="
exit 0
