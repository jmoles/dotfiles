#!/usr/bin/env bash
set -eo pipefail

LIB="$HOME/.config/git-guardrail/lib.sh"
PAYLOAD=$(cat)

# Explicit override for trusted unattended hosts. Read from the environment
# Claude Code was launched with: an inline `GUARDRAIL_OFF=1 git push` inside a
# session can't reach this process, so it is not an in-session bypass.
if [[ -n "${GUARDRAIL_OFF:-}" ]]; then
  exit 0
fi

# Extract tool and command. Without a JSON parser the payload can't be read,
# and any exit other than 2 lets the call through, so fail closed explicitly.
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "[CLAUDE HOOK REJECTED] neither jq nor python3 is installed; guard cannot read the command" >&2
  exit 2
fi

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // empty')
  COMMAND=$(echo "$PAYLOAD" | jq -r '.tool_input.command // empty')
else
  TOOL_NAME=$(python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('tool_name', ''))" <<< "$PAYLOAD")
  COMMAND=$(python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('tool_input', {}).get('command', ''))" <<< "$PAYLOAD")
fi

if [[ "$TOOL_NAME" != "Bash" ]] || [[ -z "$COMMAND" ]]; then
  exit 0
fi

if [[ ! -r "$LIB" ]]; then
  # Exit 2 is the only blocking code; fail closed rather than run unguarded.
  echo "[CLAUDE HOOK REJECTED] $LIB missing; guard cannot evaluate rules" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$LIB"

# `git` as a word (not `digit`), optionally behind a path, followed by any
# global options. -C/-c/--git-dir etc. take a value; other -* flags do not.
BOUNDARY='(^|[^[:alnum:]_.-])'
GIT_OPTS='(-[Cc][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|super-prefix|config-env|attr-source)[[:space:]]+[^[:space:]]+|-[^[:space:]]+)'
GIT_RE="${BOUNDARY}git([[:space:]]+${GIT_OPTS})*[[:space:]]+"

while IFS= read -r pattern; do
  body="$(guardrail_ere "$pattern")"
  if [[ "$pattern" =~ ^\^(git|gh)([^a-zA-Z0-9_-]|$) ]]; then
    # Explicit tool rule. Drop the anchor so chained commands
    # (cd x && gh pr merge) still match.
    HOOK_PATTERN="${BOUNDARY}${body#^}"
  else
    # Bare subcommand rule (e.g. ^push) applies to git.
    HOOK_PATTERN="${GIT_RE}${body#^}"
  fi

  if [[ "$COMMAND" =~ $HOOK_PATTERN ]]; then
    echo "[CLAUDE HOOK REJECTED] Command prohibited by policy:" >&2
    echo "  Attempted: $COMMAND" >&2
    echo "  Matched rule: $pattern" >&2
    echo "  Action: Run this manually outside automation." >&2
    # Claude Code only treats exit 2 as blocking; exit 1 lets the call run.
    exit 2
  fi
done < <(guardrail_patterns)

exit 0
