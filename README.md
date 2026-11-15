# dotfiles

My dotfiles, managed with [chezmoi](https://www.chezmoi.io/).

## Setup

Supported: macOS and Linux (tested on Fedora 43 and AlmaLinux 9). chezmoi
installs packages on macOS only; on Linux provision them first (see
Prerequisites).

```sh
# chezmoi not installed yet:
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply jmoles

# chezmoi already installed:
chezmoi init --apply jmoles
```

Afterwards, update with `chezmoi update`.

## Prerequisites

[`run_onchange_before_install-prereqs.sh.tmpl`](run_onchange_before_install-prereqs.sh.tmpl)
installs packages on **macOS only** (Homebrew, formulae and casks; needs admin
rights). On **Linux chezmoi installs nothing**: no dnf, no repos, no `sudo`, no
`chsh`. Provision the packages below with Ansible (or by hand) before
`chezmoi apply`.

| Tool | Used by | macOS (installed by script) | Linux (you provide) |
| --- | --- | --- | --- |
| zsh (5.8+) | `.zshrc` (plain zsh, no framework or plugins) | built in | `zsh`, set as login shell |
| git, git-lfs | `.gitconfig` (LFS filter is `required`) | Xcode CLT, Homebrew | `git`, `git-lfs` |
| 1Password app | commit signing (`op-ssh-sign`), SSH agent | Homebrew cask | not installed: remote hosts sign over the forwarded Mac agent with `ssh-keygen -Y sign` |
| 1Password CLI (`op`) | optional; nothing in the shell config depends on it | Homebrew cask | not needed |
| vim | git `core.editor` | built in | `vim` |
| [betterleaks](https://github.com/betterleaks/betterleaks) | global git `pre-commit` secret scan | Homebrew | `betterleaks` |
| jq | Claude Code guard hook (parses the tool call) | Homebrew | `jq` |
| gh | GitHub CLI; the `gh` guardrail wrapper is skipped if absent | Homebrew | `gh` (optional) |
| tmux + `tmux-256color` terminfo | `.tmux.conf` | Homebrew; terminfo built in | `tmux` (3.0+), terminfo entry |
| clangd | Claude Code `clangd-lsp` plugin | Xcode CLT | `clang-tools-extra` |
| [Ghostty](https://ghostty.org/) | `~/.config/ghostty` | Homebrew cask | not installed; see Optional |
| curl | setup | built in | `curl` |

The script warns (it does not install) if `tmux-256color` terminfo is missing.

Also:

- The shell config downloads nothing: no framework, plugin manager or
  self-update. Upgrading from Oh My Zsh leaves `~/.oh-my-zsh` and
  `~/.cache/oh-my-zsh` behind unused; delete them by hand.
- macOS: on a fresh machine the first apply starts the Xcode Command Line
  Tools installer and stops. Finish it, then run `chezmoi apply` again.
  Homebrew is installed if missing.

## Manual steps

1. Open 1Password, sign in, and in **Settings → Developer** enable the SSH
   agent and the CLI integration. Until then `git commit` fails (signing
   is required) and SSH has no keys.
2. Log out and back in so the new login shell takes effect (Linux).

On headless Linux hosts only the CLI is installed. They have no signing key
or local SSH agent: either sign over a forwarded agent from the Mac (only for
the host that opts in, see below) or commit and sign on the Mac and send the
work over.
A Linux machine you sit at that runs the 1Password desktop app uses its
agent locally.

## Per-host SSH config and remote workflow

Host-specific SSH config lives in
[`private_dot_ssh/private_config.d/encrypted_private_hosts.age`](private_dot_ssh/private_config.d/),
encrypted with age so host details aren't published with this repo
(names committed before this change are still in git history). Edit it with
`chezmoi edit ~/.ssh/config.d/hosts`.

Agent forwarding is off globally (`ForwardAgent no` in `Host *`) and enabled
only for the one host that needs to sign commits, via its block in the
encrypted hosts file. Anyone with root on a forwarded host can use your agent
while you're connected (1Password prompts per use), so keep it to a single
host. That host signs with `ssh-keygen -Y sign` over the forwarded
`$SSH_AUTH_SOCK`, with no 1Password install; `~/.ssh/rc` keeps a stable
`~/.ssh/ssh_auth_sock` symlink and tmux points at it so old panes survive
reconnects. Every other remote has no key: commit and sign on the Mac, then
push to it over SSH (signatures are preserved) or `rsync` uncommitted
changes; a commit there fails because signing is required. Signatures verify
locally (`git log --show-signature`) against
[`~/.config/git/allowed_signers`](dot_config/private_git/allowed_signers),
whose key must match `user.signingkey`.

To decrypt on a machine you SSH from:

1. Copy the age identity from the 1Password item **Chezmoi Key** into
   `~/.config/chezmoi/key.txt` and run `chmod 600` on it.
2. Run `chezmoi init` to regenerate the config, then `chezmoi apply`.

Machines without `key.txt` skip the encrypted file
([`.chezmoiignore`](.chezmoiignore)), so headless hosts apply cleanly.

### Rotating the signing key (yearly)

The key lives in 1Password and is referenced as a public key in two places
that must stay in sync. Nothing else (including the forwarded agent and the
remote host) needs to change, because the agent serves whatever key 1Password
holds.

1. In [`dot_gitconfig.tmpl`](dot_gitconfig.tmpl), set `user.signingkey` to
   the new public key.
2. In [`dot_config/private_git/allowed_signers`](dot_config/private_git/allowed_signers),
   add the new key as the **first** entry and keep the old one below it
   (comment it as retired). Removing the old key makes older commits show as
   unverified.
3. Add the new public key to GitHub/GitLab as a **signing** key (separate
   from any authentication key), and keep the old one there for the same
   reason.
4. If the SSH auth key also rotates, update `authorized_keys` on every
   remote, including the forwarding host.
5. `chezmoi apply` on the Mac, then on each remote that signs (the forwarding
   host). Check with `git commit --allow-empty -m test` and
   `git log --show-signature -1`.

## Global git hooks and secret scanning

`core.hooksPath` points every repo at
[`~/.config/git/hooks`](dot_config/private_git/hooks/). Every hook name there
is a symlink to one `dispatch` script, which:

- runs `betterleaks` on staged changes in `pre-commit` and blocks the commit
  on a finding (secrets are redacted in the output). If betterleaks itself
  errors, the commit is blocked too. If it isn't installed, the hook warns and
  lets the commit through.
- then runs the repo's own `.git/hooks/<name>`. A global `core.hooksPath`
  replaces repo hooks rather than adding to them, so without this they'd stop
  running silently.
- runs git-lfs's `pre-push`, `post-checkout`, `post-commit` and `post-merge`
  itself. Once `core.hooksPath` is set, `git lfs install` tries to write its
  hooks into the global dir and refuses because these links exist. Use
  `git lfs install --skip-repo` instead.

To handle a false positive, add a `# betterleaks:allow` comment on the line,
or put a `.gitleaksignore` / `.gitleaks.toml` in the repo. To skip the scan
once, use `git commit --no-verify`.

Limits:

- Repos that set their own `core.hooksPath` (husky, for example) use only
  their own hooks, so the scan doesn't run there.
- `push-to-checkout` and `reference-transaction` aren't linked, so repo-local
  copies of those don't run. See the comment in `dispatch` for why.
- Rebases and cherry-picks don't run `pre-commit`.

CI also runs gitleaks over this repo's full history.

## AI-tool git and gh guardrails

These rules apply to AI coding sessions (Claude Code), not to your own
terminal, cron, chezmoi or deploy scripts. Destructive or outward-facing
commands are blocked there: pushes, `reset --hard`, `rebase`, `clean -f`,
`branch -D`, `checkout .` / `restore .`, and for `gh`: repo
delete/archive/edit/rename, PR merge/close, release writes, secrets, ssh/gpg
keys, `gh auth` login-type commands, extensions, skills and aliases (they run
third-party code or shell), workflow/run/cache/variable writes, and `gh api`
with a write method or fields. The rules live in
[`~/.config/git-guardrail/patterns.txt`](dot_config/git-guardrail/patterns.txt).
Bare rules like `^push` are git subcommands; rules starting `^gh` are `gh`.

Two layers read that file:

- A Claude Code `PreToolUse` hook
  ([`pre-tool-git-guard.sh`](dot_claude/hooks/executable_pre-tool-git-guard.sh)),
  registered by the `settings.json` merge. It rejects the command with exit 2,
  the only code Claude Code treats as blocking.
- `git` and `gh` wrappers in `~/.local/bin` (ahead of the real binaries on
  `PATH`) that enforce the same rules for any AI tool that runs them.

The wrappers only enforce when `CLAUDECODE` or `AI_AGENT` is set (Claude Code
sets both), or `GUARDRAIL_AGENT=1` is exported. For another AI tool, export
`GUARDRAIL_AGENT=1` from that tool's own config. Set `GUARDRAIL_OFF=1` to
bypass them explicitly. Without any of those, they hand straight off to the
real binary. The hook only ever sees Claude Code, and it also honors
`GUARDRAIL_OFF=1`, but only from the environment Claude Code was launched with
(for a trusted unattended host, `GUARDRAIL_OFF=1 claude -p ...`). Setting it
inline inside a session has no effect on the hook.

The wrappers are skipped on a host where the real `git` or `gh` isn't
installed ([`.chezmoiignore`](.chezmoiignore) checks the usual install
paths). If the tool lives somewhere else, the wrapper is skipped and that tool
runs unguarded. The hook fails closed when it has neither `jq` nor `python3`.

Limits:

- This is a seatbelt against mistakes, not a security boundary. A session can
  unset the variables or call `/usr/bin/git` directly, and the hook matches
  command text, so obfuscated commands (`g''it push`, a script that runs it)
  get past it. `echo git push` is a false positive. Use credential gating
  (1Password-approved signing and SSH) and GitHub rulesets for anything that
  must hold.
- `gh api` writes (`-X POST|PUT|PATCH|DELETE`, `-f`/`-F`/`--field`/`--input`)
  are blocked and GET is allowed, but anything outside `git`/`gh` (`curl` with
  a token, a script) is not covered.
- If `lib.sh` is missing, the wrappers warn and run unguarded (so a broken
  install can't take `git` down), while the hook blocks every Bash call in Claude Code until it's restored.

### Permission prompts

The `settings.json` merge also manages `permissions`. Read-only commands
(`git status|log|diff|show|blame`, `gh pr|issue|run|... view|list`, ...) run
without a prompt; `git commit`, `gh api` and every mutating `gh` verb ask.
There is deliberately no blanket `Bash(git *)` or `Bash(gh *)` ask: an `ask`
rule beats an `allow` rule, so it would prompt for every `git log`. The `gh`
verb lists come from `gh <group> --help`; a verb added by a newer `gh` just
gets the normal prompt.

### Tests

```sh
bash tests/guardrail-test.sh     # hook + wrappers against patterns.txt
bash tests/permissions-test.sh   # renders the settings template (needs chezmoi)
```

Both build a throwaway `HOME` from the checkout and use stub `git`/`gh`, so
there's no network and no real command runs. CI runs them on Linux and macOS.
The permission test also checks that no `allow` rule is one the hook blocks.
Neither can check how Claude Code itself matches a rule against a command: after
applying, `gh pr list` should run without a prompt and `gh pr create` should ask.

To dry-run the whole repo without a TTY (what CI does), skip the age-encrypted
host file, which otherwise prompts if your local copy has drifted:
`chezmoi apply --dry-run --source "$PWD" --exclude=encrypted,externals`

## Optional

These only add to `PATH` or define aliases. Install them as needed; nothing
breaks without them.

- Rust via [rustup](https://rustup.rs/) (`~/.cargo/bin`)
- Go (`~/go/bin`)
- Ruby gems in `~/gems` (`GEM_HOME`)
- Visual Studio Code (`code` on `PATH`)
- Ghostty on Linux (config is deployed regardless). Every host gets the
  `xterm-ghostty` terminfo in `~/.terminfo`, so SSH from Ghostty works
  without it.
- Per-machine Ghostty overrides in `~/.config/ghostty/local.ghostty`
  (not managed by chezmoi)
- AMD Vitis 2026.1 at `/opt/xilinx/2026.1` (`xilinx-env` alias)

## Claude Code settings

Claude Code writes `~/.claude/settings.json` itself, so chezmoi doesn't own
the file. [`modify_private_settings.json`](dot_claude/modify_private_settings.json)
merges a few keys into whatever is there on each apply and leaves the rest
local. Those keys win over local edits; `permissions.ask` is merged, not
replaced.

## CI

GitHub Actions runs `chezmoi apply --dry-run` on macOS and Ubuntu,
shellcheck, and TOML/JSON validation.
