#!/usr/bin/env bash
# tools/scaffold-rule.sh — Create rule .md + .yaml skeleton
# Usage: scaffold-rule.sh --number <NNN> --id <id> [--description <text>]
# Creates: core/rules/<NNN>-cf-<id>.md + .yaml
set -euo pipefail

# Parse args
_NUMBER=""
_ID=""
_DESCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: scaffold-rule.sh --number <NNN> --id <id> [--description <text>]

Create a new context-forge rule with .md and .yaml skeleton.

Options:
  --number <NNN>           — 3-digit rule number (e.g., 001, 042)
  --id <id>                — Rule ID (kebab-case, no cf- prefix)
  --description <text>     — One-line description (optional)

Requirements:
  - Rule files follow naming: <NNN>-cf-<id>.{md,yaml}
  - IDs must be kebab-case
  - Numbers should fit range (001-999)

Examples:
  scaffold-rule.sh --number 015 --id "token-efficiency" --description "Output constraints"
  scaffold-rule.sh --number 020 --id "api-boundaries"
EOF
      exit 0
      ;;
    --number)
      _NUMBER="$2"
      shift 2
      ;;
    --id)
      _ID="$2"
      shift 2
      ;;
    --description)
      _DESCRIPTION="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1"
      exit 1
      ;;
  esac
done

NUMBER="$_NUMBER"
ID="$_ID"
DESCRIPTION="${_DESCRIPTION:-Describe what this rule enforces and when it applies.}"

if [[ -z "$NUMBER" || -z "$ID" ]]; then
  echo "ERROR: --number and --id required"
  exit 1
fi

# Validate number (3 digits)
if ! echo "$NUMBER" | rg -q '^[0-9]{3}$'; then
  echo "ERROR: --number must be 3 digits (e.g., 001, 042, 999)"
  exit 1
fi

# Validate ID (kebab-case)
if ! echo "$ID" | rg -q '^[a-z][a-z0-9-]*$'; then
  echo "ERROR: --id must be kebab-case (lowercase alphanumeric + hyphens)"
  exit 1
fi

RULE_FILE="core/rules/${NUMBER}-cf-${ID}"
RULE_MD="${RULE_FILE}.md"
RULE_YAML="${RULE_FILE}.yaml"

echo "=== SCAFFOLD RULE: $NUMBER-cf-$ID ==="
echo ""

if [[ -f "$RULE_MD" || -f "$RULE_YAML" ]]; then
  echo "ERROR: rule already exists"
  echo "  $RULE_MD"
  echo "  $RULE_YAML"
  exit 1
fi

# Write .md file
cat > "$RULE_MD" <<'RULEMD'
# RULE_TITLE

DESCRIPTION_HERE

## SYSTEM CONSTRAINTS

NEVER [forbidden action].
ALWAYS [required action].

## Topic section 1

[Guidance, patterns, reference]

## Topic section 2

[More details]

## Few-shot example

**Input:** "[example user request]"
**Reasoning:** [1-3 line chain of thought]
**Output:**
[example output]

## Validation gate (MANDATORY before output)

- [ ] [constraint 1]?
- [ ] [constraint 2]?

If any unchecked → fix before returning output.
RULEMD

# Replace placeholders (BSD-compatible sed)
TITLE="Rule ${NUMBER}: ${ID}"
# Escape sed replacement metacharacters — a title/description containing
# "/", "|", "&" or "\" would otherwise break the s||| expression.
_sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
TITLE_ESC=$(_sed_escape "$TITLE")
DESCRIPTION_ESC=$(_sed_escape "$DESCRIPTION")

sed -i '' "s|RULE_TITLE|$TITLE_ESC|g" "$RULE_MD" 2>/dev/null || \
  sed -i "s|RULE_TITLE|$TITLE_ESC|g" "$RULE_MD"

sed -i '' "s|DESCRIPTION_HERE|$DESCRIPTION_ESC|g" "$RULE_MD" 2>/dev/null || \
  sed -i "s|DESCRIPTION_HERE|$DESCRIPTION_ESC|g" "$RULE_MD"

# Write .yaml metadata
cat > "$RULE_YAML" <<YAML
id: cf-$ID
number: $NUMBER
name: "$TITLE"
activation:
  mode: intelligent
  patterns: []
  description: "$DESCRIPTION"
content_file: ${NUMBER}-cf-${ID}.md
YAML

echo "Rule created:"
echo "  Files:"
echo "    - $RULE_MD"
echo "    - $RULE_YAML"
echo ""
echo "Next steps:"
echo "  1. Edit $RULE_MD with rule content"
echo "  2. Add trigger patterns to $RULE_YAML (if needed)"
echo "  3. Run: bash core/scripts/tools/validate-index.sh"
echo "  4. Run: npm run convert"
echo ""
echo "=== DONE SCAFFOLD RULE ==="
