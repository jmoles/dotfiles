#!/usr/bin/env bash
# Renders the Claude settings modify template and checks the permission rules
# it produces, including against the guard hook. Needs chezmoi and python3.
# Run: bash tests/permissions-test.sh
#
# This checks what the template emits. It cannot check how Claude Code itself
# matches those rules against a command; that needs a real session.
# shellcheck source=tests/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

command -v chezmoi >/dev/null 2>&1 || { echo "chezmoi not found" >&2; exit 1; }

: >"$T/chezmoi.toml"
render() {
  chezmoi --source "$ROOT" --destination "$HOME" --config "$T/chezmoi.toml" cat "$HOME/.claude/settings.json"
}

mkdir -p "$HOME/.claude"
SETTINGS="$HOME/.claude/settings.json"

echo "--- fresh render (no existing settings.json)"
render >"$T/fresh.json" 2>"$T/err.txt"
check 0 "$?" "template renders with no existing file"
[[ -s "$T/err.txt" ]] && sed 's/^/  chezmoi: /' "$T/err.txt"

# Emits "ok<TAB>label" / "FAIL<TAB>label" lines, and the commands implied by
# every allow rule (one per line) to $T/allow-cmds.txt for the hook check.
python3 - "$T/fresh.json" "$T/allow-cmds.txt" >"$T/props.txt" <<'EOF'
import json, re, sys

d = json.load(open(sys.argv[1]))
ask, allow = d["permissions"]["ask"], d["permissions"]["allow"]
out = []
def check(ok, label): out.append(("ok" if ok else "FAIL") + "\t" + label)

check(len(d["hooks"]["PreToolUse"]) == 1, "exactly one PreToolUse entry")
check("Bash(git *)" not in ask and "Bash(gh *)" not in ask, "no blanket git/gh ask (it would override every allow)")
for r in ("Bash(git commit)", "Bash(git commit *)", "Bash(gh api *)", "Bash(gh pr create *)",
          "Bash(gh repo edit *)", "Bash(gh extension install *)"):
    check(r in ask, "ask has " + r)
check(not (set(ask) & set(allow)), "no rule is in both ask and allow: " + str(sorted(set(ask) & set(allow))))

# Read-only whitelists. Anything else in allow is a mistake.
GIT_READ = {"status", "log", "diff", "show", "blame", "rev-parse", "ls-files", "describe",
            "shortlog", "branch", "stash", "remote"}
GH_WRITE_VERBS = {"create", "delete", "merge", "edit", "set", "install", "add", "close", "comment",
                  "upload", "update", "upgrade", "rerun", "cancel", "run", "enable", "disable", "rename",
                  "archive", "unarchive", "fork", "sync", "transfer", "lock", "unlock", "pin", "unpin",
                  "review", "reopen", "ready", "revert", "publish", "import", "remove", "exec",
                  "download", "checkout", "clone", "develop", "login", "logout", "refresh", "token"}
bad = []
cmds = []
for r in allow:
    m = re.fullmatch(r"Bash\((.+?)( \*)?\)", r)
    if not m:
        continue
    cmd, star = m.group(1), bool(m.group(2))
    cmds.append(cmd + (" x" if star else ""))
    w = cmd.split()
    if w[0] == "git" and len(w) > 1 and w[1] not in GIT_READ and not w[1].startswith("-"):
        bad.append(r)
    if w[0] == "gh":
        if len(w) > 1 and w[1] == "api":
            bad.append(r)
        if len(w) > 2 and w[2] in GH_WRITE_VERBS:
            bad.append(r)
check(not bad, "allow rules are read-only: " + str(bad))
open(sys.argv[2], "w").write("\n".join(cmds) + "\n")
print("\n".join(out))
EOF
while IFS="$(printf '\t')" read -r status label; do
  [[ -z "$status" ]] && continue
  if [[ "$status" == ok ]]; then PASS=$((PASS + 1)); echo "ok   $label"; else FAIL=$((FAIL + 1)); echo "FAIL $label"; fi
done <"$T/props.txt"

echo "--- every allow rule must pass the guard hook ($(wc -l <"$T/allow-cmds.txt" | tr -d ' ') commands)"
# An allow rule the hook blocks is dead: it promises no prompt, then gets stopped.
dead=""
while IFS= read -r cmd; do
  [[ -z "$cmd" ]] && continue
  [[ "$(hook_rc "$cmd")" == 0 ]] || dead="$dead [$cmd]"
done <"$T/allow-cmds.txt"
check "" "$dead" "no allow rule is blocked by the hook"

echo "--- idempotent"
cp "$T/fresh.json" "$SETTINGS"
render >"$T/second.json"
if cmp -s "$T/fresh.json" "$T/second.json"; then check same same "re-rendering the output changes nothing"; else check same different "re-rendering the output changes nothing"; fi

echo "--- migrates an old-style file and keeps local settings"
cat >"$SETTINGS" <<'EOF'
{"permissions":{"ask":["Bash(git *)","Bash(gh *)","Bash(my custom *)"],"allow":["Bash(make *)"]},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/opt/other-hook"}]}]},
 "theme":"light","somethingLocal":true}
EOF
render >"$T/legacy.json"
python3 - "$T/legacy.json" >"$T/legacy.txt" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
p = d["permissions"]
def c(ok, l): print(("ok" if ok else "FAIL") + "\t" + l)
c("Bash(git *)" not in p["ask"] and "Bash(gh *)" not in p["ask"], "blanket asks removed")
c("Bash(my custom *)" in p["ask"], "local ask rule kept")
c("Bash(make *)" in p["allow"], "local allow rule kept")
c(d.get("somethingLocal") is True, "unrelated local key kept")
cmds = [h["command"] for e in d["hooks"]["PreToolUse"] for h in e["hooks"]]
c("/opt/other-hook" in cmds and "$HOME/.claude/hooks/pre-tool-git-guard.sh" in cmds, "existing hook kept alongside the guard")
c(cmds.count("$HOME/.claude/hooks/pre-tool-git-guard.sh") == 1, "guard registered once")
EOF
while IFS="$(printf '\t')" read -r status label; do
  [[ -z "$status" ]] && continue
  if [[ "$status" == ok ]]; then PASS=$((PASS + 1)); echo "ok   $label"; else FAIL=$((FAIL + 1)); echo "FAIL $label"; fi
done <"$T/legacy.txt"

finish
