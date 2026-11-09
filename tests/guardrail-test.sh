#!/usr/bin/env bash
# Tests the Claude Code hook and the git/gh wrappers against patterns.txt.
# Hermetic: see common.sh. Run: bash tests/guardrail-test.sh
# shellcheck source=tests/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
set -f # case lines below contain no globs; keep word splitting literal

# One command per line. Used against both the hook (command text) and the
# wrapper (arguments).
BLOCKED='
git push
git push --force
git push -f origin main
git -C /tmp push
git --no-pager push
git -c a=b reset --hard
git reset --hard HEAD~1
git clean -fd
git rebase -i HEAD~2
git branch -D x
git branch --delete x
git checkout .
git restore .
gh pr merge 1
gh pr close 1
gh pr --repo o/r merge 1
gh pr -R o/r close 1
gh repo delete o/r
gh repo archive o/r
gh repo edit --visibility public
gh repo rename x
gh repo unarchive o/r
gh repo deploy-key add k
gh release create v1
gh release delete v1
gh release edit v1
gh release upload v1 f
gh release delete-asset v1 a
gh secret list
gh secret set X
gh ssh-key add k
gh gpg-key add k
gh gpg-key list
gh auth login
gh auth logout
gh auth token
gh extension install o/gh-x
gh extension upgrade --all
gh skill install x
gh skill update
gh alias set a b
gh alias import f
gh issue delete 1
gh variable set X
gh variable delete X
gh workflow run w
gh workflow enable w
gh run rerun 1
gh run cancel 1
gh run delete 1
gh cache delete 1
gh gist delete 1
gh project delete 1
gh label delete x
gh codespace delete
gh api -X DELETE repos/o/r
gh api -X POST repos/o/r/issues
gh api --method PATCH repos/o/r
gh api --method=put repos/o/r
gh api -XPOST repos/o/r/issues
gh api repos/o/r/issues -f title=t
gh api graphql -F query=@q
gh api repos/o/r --input f
gh api repos/o/r --field a=b
gh api repos/o/r --raw-field a=b
'

ALLOWED='
git status
git status --short
git -C /tmp status
git log
git log --oneline
git diff
git show HEAD
git commit -m x
git checkout main
git branch --show-current
git add file
git switch -c b
git fetch
gh pr view 1
gh pr list
gh pr status
gh pr checks 1
gh pr diff 1
gh pr create --title t
gh issue list
gh issue view 1
gh issue create
gh run list
gh run view 1
gh run watch 1
gh repo view
gh repo list
gh repo clone o/r
gh release list
gh release view v1
gh status
gh auth status
gh auth git-credential get
gh search issues x
gh config get editor
gh api repos/o/r
gh api -X GET repos/o/r
gh api --method GET repos/o/r
gh workflow list
gh workflow view w
gh variable list
gh variable get X
gh label list
gh extension list
gh alias list
gh gist view 1
gh discussion list
gh attestation verify x
gh repo gitignore list
gh pr list --state merged
gh pr view 1 --json close
gh issue list --label delete
gh pr -R o/r list
'

# Chained commands, absolute paths and env tricks only make sense for the hook,
# which sees the whole command line.
HOOK_ONLY_BLOCKED='
cd x && git push
cd x && gh pr merge 1
/usr/bin/git push
/opt/homebrew/bin/gh pr merge 1
env -u CLAUDECODE git push
GUARDRAIL_OFF=1 git push
CLAUDECODE= gh repo delete x
'
HOOK_ONLY_ALLOWED='
ls -la
echo hello
digit push
mygit push
git-lfs push
'

echo "--- blocked: hook (exit 2) and wrapper (exit 126)"
while IFS= read -r cmd; do
  [[ -z "$cmd" ]] && continue
  check 2 "$(hook_rc "$cmd")" "hook blocks   :: $cmd"
  tool="${cmd%% *}"
  args="${cmd#* }"
  # shellcheck disable=SC2086 # intentional word splitting of the case line
  rc="$(wrap_rc "$tool" $args)"
  check 126 "$rc" "wrapper blocks :: $cmd"
  grep -q '^REAL' "$T/out" && check "no REAL output" "REAL output" "wrapper leaked to real $tool :: $cmd"
done <<<"$BLOCKED"

echo "--- allowed: hook (exit 0) and wrapper (reaches real tool)"
while IFS= read -r cmd; do
  [[ -z "$cmd" ]] && continue
  check 0 "$(hook_rc "$cmd")" "hook allows   :: $cmd"
  tool="${cmd%% *}"
  args="${cmd#* }"
  # shellcheck disable=SC2086
  rc="$(wrap_rc "$tool" $args)"
  check 0 "$rc" "wrapper allows :: $cmd"
  grep -q "^REAL $tool" "$T/out" || check "REAL $tool output" "none" "wrapper reached real $tool :: $cmd"
done <<<"$ALLOWED"

echo "--- hook only"
while IFS= read -r cmd; do
  [[ -z "$cmd" ]] && continue
  check 2 "$(hook_rc "$cmd")" "hook blocks :: $cmd"
done <<<"$HOOK_ONLY_BLOCKED"
while IFS= read -r cmd; do
  [[ -z "$cmd" ]] && continue
  check 0 "$(hook_rc "$cmd")" "hook allows :: $cmd"
done <<<"$HOOK_ONLY_ALLOWED"
check 0 "$(hook_rc "")" "hook ignores an empty command"

echo "--- agent scoping (wrappers)"
unset GUARDRAIL_AGENT
check 0 "$(wrap_rc git push)" "human shell: git push reaches real git"
check 0 "$(wrap_rc gh pr merge 1)" "human shell: gh pr merge reaches real gh"
check 126 "$(GUARDRAIL_AGENT=1 wrap_rc git push)" "GUARDRAIL_AGENT=1 blocks"
check 126 "$(CLAUDECODE=1 wrap_rc git push)" "CLAUDECODE=1 blocks"
check 126 "$(AI_AGENT=x wrap_rc git push)" "AI_AGENT set blocks"
check 0 "$(CLAUDECODE=1 GUARDRAIL_OFF=1 wrap_rc git push)" "GUARDRAIL_OFF=1 overrides the wrappers"
export GUARDRAIL_AGENT=1

echo "--- hook: override and missing parser"
PUSH='git push'
check 0 "$(GUARDRAIL_OFF=1 hook_rc "$PUSH")" "GUARDRAIL_OFF=1 in the hook's environment allows"
check 2 "$(hook_rc "GUARDRAIL_OFF=1 git push")" "inline GUARDRAIL_OFF=1 in the command text is still blocked"
NB="$T/nobin"
mkdir -p "$NB"
for t in cat sed; do ln -s "$(command -v "$t")" "$NB/$t"; done
rc=$(python3 -c 'import json,sys; sys.stdout.write(json.dumps({"tool_name":"Bash","tool_input":{"command":"git push"}}))' |
  env PATH="$NB" /bin/bash "$HOOK" >/dev/null 2>&1; echo $?)
check 2 "$rc" "no jq and no python3 fails closed"

echo "--- missing lib.sh"
mkdir -p "$T/nolib"
rc=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | HOME="$T/nolib" "$HOOK" >/dev/null 2>&1; echo $?)
check 2 "$rc" "hook fails closed without lib.sh"
# Falls back to a fixed-path real git, not the stub: needs a real git installed.
if [[ -x /usr/bin/git || -x /opt/homebrew/bin/git || -x /usr/local/bin/git ]]; then
  GIT_WRAPPER="$HOME/.local/bin/git"
  rc=$(HOME="$T/nolib" "$GIT_WRAPPER" --version >/dev/null 2>&1; echo $?)
  check 0 "$rc" "git wrapper still runs git (warns) without lib.sh"
fi

finish
