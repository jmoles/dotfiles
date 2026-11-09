# shellcheck shell=bash
# Shared setup for the guardrail tests. Source it; do not run it.
#
# Builds a throwaway HOME from this checkout (hook, wrappers, lib.sh,
# patterns.txt) and puts stub git/gh behind the wrappers, so the tests need no
# network, never run a real git/gh command, and leave the real HOME alone.
# Written for bash 3.2 (macOS) as well as newer.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

ORIG_PATH="$PATH"
export HOME="$T/home"
GR="$HOME/.config/git-guardrail"
HOOK="$HOME/.claude/hooks/pre-tool-git-guard.sh"
mkdir -p "$GR" "$HOME/.local/bin" "$HOME/.claude/hooks" "$T/stub"

cp "$ROOT/dot_config/git-guardrail/lib.sh" "$ROOT/dot_config/git-guardrail/patterns.txt" "$GR/"
install -m 755 "$ROOT/dot_claude/hooks/executable_pre-tool-git-guard.sh" "$HOOK"
install -m 755 "$ROOT/private_dot_local/bin/executable_git" "$HOME/.local/bin/git"
install -m 755 "$ROOT/private_dot_local/bin/executable_gh" "$HOME/.local/bin/gh"

# The "real" binaries the wrappers hand off to. A guard that blocks never
# reaches these, so seeing REAL in the output proves a command got through.
for tool in git gh; do
  printf '#!/bin/sh\necho "REAL %s $*"\n' "$tool" >"$T/stub/$tool"
  chmod 755 "$T/stub/$tool"
done

export PATH="$HOME/.local/bin:$T/stub:$ORIG_PATH"
export GUARDRAIL_AGENT=1
unset CLAUDECODE AI_AGENT GUARDRAIL_OFF

PASS=0
FAIL=0

check() { # want got label
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
    echo "ok   $3"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $3 (want=$1 got=$2)"
  fi
}

# Exit code of the Claude Code hook for a Bash command string.
hook_rc() {
  python3 -c 'import json,sys; sys.stdout.write(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" |
    "$HOOK" >/dev/null 2>&1
  echo $?
}

# Exit code of a wrapper; its output lands in $T/out.
wrap_rc() { # tool args...
  local tool="$1" rc
  shift
  "$HOME/.local/bin/$tool" "$@" >"$T/out" 2>&1 </dev/null
  rc=$?
  echo "$rc"
}

finish() {
  echo
  echo "$PASS passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]]
}
