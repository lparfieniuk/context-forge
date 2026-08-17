#!/usr/bin/env bash
# tools/scaffold-skill.sh — Create SKILL.md + skill.yaml template
# Port from ai-system; adapted for context-forge
# Usage: scaffold-skill.sh --name <skill_name> [--description <text>]
# Creates: core/skills/<name>/SKILL.md + skill.yaml
set -euo pipefail

# Parse args
_NAME=""
_DESCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      cat <<'EOF'
Usage: scaffold-skill.sh --name <skill_name> [--description <text>]

Create a new skill with SKILL.md and skill.yaml skeleton.

Options:
  --name <name>            — Skill name (kebab-case, max 64 chars)
  --description <text>     — One-line description (optional)

Requirements:
  - skill_name must be kebab-case (lowercase alphanumeric + hyphens)
  - max 64 characters
  - no uppercase letters

Examples:
  scaffold-skill.sh --name "my-skill" --description "Does cool things"
  scaffold-skill.sh --name "cf-token-counter"
EOF
      exit 0
      ;;
    --name)
      _NAME="$2"
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

NAME="$_NAME"
DESCRIPTION="${_DESCRIPTION:-Describe what this skill does and when to use it.}"

if [[ -z "$NAME" ]]; then
  echo "ERROR: --name required"
  exit 1
fi

# Validate name format (kebab-case, max 64 chars)
if ! echo "$NAME" | rg -q '^cf-[a-z][a-z0-9-]{0,61}$' 2>/dev/null; then
  if ! echo "$NAME" | rg -q '^[a-z][a-z0-9-]{0,63}$' 2>/dev/null; then
    echo "ERROR: skill name must be kebab-case, max 64 chars, no uppercase"
    echo "HINT: Names should start with 'cf-' to follow context-forge convention"
    exit 1
  fi
fi

SKILL_DIR="core/skills/$NAME"

echo "=== SCAFFOLD SKILL: $NAME ==="
echo ""

if [[ -d "$SKILL_DIR" ]]; then
  echo "ERROR: skill already exists at $SKILL_DIR"
  exit 1
fi

mkdir -p "$SKILL_DIR"

# Write SKILL.md
cat > "$SKILL_DIR/SKILL.md" <<'SKILLMD'
# Skill: SKILLNAME

DESCRIPTION_HERE

## SYSTEM CONSTRAINTS

NEVER [forbidden action].
ALWAYS [required action].

## When to use

- [trigger condition 1]
- [trigger condition 2]

## Execution Protocol

### Step 1: [first action]

```bash
# example command
```

### Step 2: [next action]

[description]

## Few-shot example

**Input:** "[example user request]"
**Reasoning:** [1-3 line chain of thought]
**Output:**
```
[example output]
```

## Validation gate (MANDATORY before output)

- [ ] [constraint 1]?
- [ ] [constraint 2]?

If any unchecked → fix before proceeding.
SKILLMD

# Replace placeholders
# Escape sed replacement metacharacters. Without this a description containing
# "/" (e.g. "so /clear costs no context") breaks the s/// delimiter.
_sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
NAME_ESC=$(_sed_escape "$NAME")
DESCRIPTION_ESC=$(_sed_escape "$DESCRIPTION")

sed -i '' "s|SKILLNAME|$NAME_ESC|g" "$SKILL_DIR/SKILL.md" 2>/dev/null || \
  sed -i "s|SKILLNAME|$NAME_ESC|g" "$SKILL_DIR/SKILL.md"

sed -i '' "s|DESCRIPTION_HERE|$DESCRIPTION_ESC|g" "$SKILL_DIR/SKILL.md" 2>/dev/null || \
  sed -i "s|DESCRIPTION_HERE|$DESCRIPTION_ESC|g" "$SKILL_DIR/SKILL.md"

# Write skill.yaml
cat > "$SKILL_DIR/skill.yaml" <<YAML
id: $NAME
name: "$DESCRIPTION"
description: "Skill for context-forge"
activation:
  trigger_patterns:
    - "skill:$NAME"
  keywords: []
author: "context-forge"
version: "0.1"
YAML

echo "Skill created:"
echo "  Directory: $SKILL_DIR"
echo "  Files:"
echo "    - SKILL.md"
echo "    - skill.yaml"
echo ""
echo "Next steps:"
echo "  1. Edit $SKILL_DIR/SKILL.md with skill content"
echo "  2. Run: bash core/scripts/tools/validate-index.sh"
echo "  3. Run: npm run convert"
echo ""
echo "=== DONE SCAFFOLD SKILL ==="
