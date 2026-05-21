#!/usr/bin/env bash
# Pre-commit quality gate — run before pushing.
# Checks: brace balance, print() violations, file truncation.
# No Flutter required — pure shell + python3.

set -euo pipefail

cd "$(dirname "$0")/.."

FAIL=0

# ── 1. Brace balance ─────────────────────────────────────────────────
echo "Checking brace balance..."
BAD=$(python3 -c "
import os
bad = []
for root, _, files in os.walk('lib'):
    for f in files:
        if not f.endswith('.dart') or f.endswith('.g.dart'):
            continue
        path = os.path.join(root, f)
        text = open(path).read()
        opens, closes = text.count('{'), text.count('}')
        if opens != closes:
            bad.append(f'{path}: {{ = {opens}, }} = {closes} (diff {opens - closes})')
for b in bad:
    print(b)
")

if [ -n "$BAD" ]; then
    echo "❌ Brace imbalance detected:"
    echo "$BAD"
    FAIL=1
else
    echo "✅ All lib/ files brace-balanced"
fi

# ── 2. print() violations ────────────────────────────────────────────
echo ""
echo "Checking for print() violations..."
PRINT_BAD=$(grep -rn '[^a-zA-Z]print(' lib/ --include="*.dart" | grep -v "debugPrint" | grep -v "// allow-print" || true)
if [ -n "$PRINT_BAD" ]; then
    echo "❌ Found print() calls — use debugPrint() instead:"
    echo "$PRINT_BAD"
    FAIL=1
else
    echo "✅ No print() violations"
fi

# ── 3. File truncation — last line check ─────────────────────────────
echo ""
echo "Checking for truncated files..."
TRUNCATED=$(python3 -c "
import os
suspect = []
for root, _, files in os.walk('lib'):
    for f in files:
        if not f.endswith('.dart') or f.endswith('.g.dart'):
            continue
        path = os.path.join(root, f)
        text = open(path).read()
        lines = text.strip().split('\n')
        last = lines[-1].strip() if lines else ''
        # File ending with unclosed string, unclosed paren, or incomplete expression
        if last and not last[-1] in '});,>]':
            # Allow multi-line expressions that end mid-token (e.g. long strings)
            # but flag files that end with an opening construct
            if last.endswith('(') or last.endswith('{') or last.endswith('='):
                suspect.append(f'{path}: ends with \"{last[-40:]}\"')
for s in suspect:
    print(s)
")

if [ -n "$TRUNCATED" ]; then
    echo "⚠️  Possibly truncated files:"
    echo "$TRUNCATED"
    # Warning only — don't block (could be false positive on multiline)
else
    echo "✅ No obvious truncation"
fi

# ── 4. Amharic field resurrection ────────────────────────────────────
echo ""
echo "Checking for residual Amharic fields..."
AMHARIC=$(grep -rn "firstNameAm\|lastNameAm\|titleAmharic\|textAmharic\|nameAmharic\|isAmharic\|isAm\b\|LocaleProvider" lib/ --include="*.dart" | grep -v "\.g\.dart" || true)
if [ -n "$AMHARIC" ]; then
    echo "❌ Amharic fields resurrected in lib/:"
    echo "$AMHARIC"
    FAIL=1
else
    echo "✅ No Amharic field references"
fi

echo ""
if [ "$FAIL" -eq 1 ]; then
    echo "❌ Quality gate FAILED — fix issues above before committing"
    exit 1
else
    echo "✅ Quality gate PASSED"
    exit 0
fi
