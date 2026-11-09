# shellcheck shell=bash
# Shared helpers for the git/gh guardrail wrappers. Sourced, not executed.
# One implementation so the wrappers can't drift apart on how they normalize
# a command line before matching it against patterns.txt.

GUARDRAIL_PATTERNS="${GUARDRAIL_PATTERNS:-$HOME/.config/git-guardrail/patterns.txt}"

# The wrappers only enforce inside AI-tool sessions so they don't get in the
# way of a human terminal, cron, chezmoi or deploy scripts. This is a
# convenience scope, not a security boundary: an agent can unset these.
# CLAUDECODE is set by Claude Code; AI_AGENT is present in its sessions too.
# For other tools, export GUARDRAIL_AGENT=1 from that tool's own config.
# GUARDRAIL_OFF=1 is the explicit human override.
guardrail_is_agent() {
  [[ -z "${GUARDRAIL_OFF:-}" ]] || return 1
  [[ -n "${GUARDRAIL_AGENT:-}" || -n "${CLAUDECODE:-}" || -n "${AI_AGENT:-}" ]]
}

# Find the real binary behind a wrapper. Compare inodes (-ef) instead of
# grepping paths: a failed filter would otherwise resolve to the wrapper
# itself and exec-loop forever.
guardrail_find_real() {
  local name="$1" self="$2" dir
  local -a dirs
  IFS=: read -ra dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    [[ -n "$dir" && -x "$dir/$name" && ! "$dir/$name" -ef "$self" ]] || continue
    printf '%s\n' "$dir/$name"
    return 0
  done
  for dir in /usr/bin /opt/homebrew/bin /usr/local/bin; do
    [[ -x "$dir/$name" && ! "$dir/$name" -ef "$self" ]] || continue
    printf '%s\n' "$dir/$name"
    return 0
  done
  return 1
}

# Strip git's leading global options so `git -C x push` is matched as `push`.
# Options that take a separate value must consume it, or the value would be
# mistaken for the subcommand.
guardrail_git_normalize() {
  while (($#)); do
    case "$1" in
      -C | -c | --git-dir | --work-tree | --namespace | --super-prefix | --config-env | --attr-source)
        if (($# >= 2)); then shift 2; else shift; fi
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$*"
}

# Positional words only, so `gh pr --repo x merge` is matched as `pr merge`.
guardrail_gh_normalize() {
  local out=()
  while (($#)); do
    case "$1" in
      -R | --repo | --hostname)
        if (($# >= 2)); then shift 2; else shift; fi
        ;;
      -*) shift ;;
      *)
        out+=("$1")
        shift
        ;;
    esac
  done
  printf '%s\n' "${out[*]}"
}

# bash ERE has no \s; let pattern authors use it anyway.
guardrail_ere() { printf '%s' "${1//\\s/[[:space:]]}"; }

# Read patterns.txt, one trimmed non-comment line per output line.
guardrail_patterns() {
  [[ -f "$GUARDRAIL_PATTERNS" ]] || return 0
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$GUARDRAIL_PATTERNS"
}

guardrail_block() {
  local tool="$1" shown="$2" rule="$3"
  {
    echo "=========================================================="
    echo " [GUARDRAIL] $tool operation blocked by local policy: $shown"
    echo " Matched rule: $rule"
    echo " Run it manually with the full binary path if intended."
    echo "=========================================================="
  } >&2
}
