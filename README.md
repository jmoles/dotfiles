# dotfiles

My dotfiles, managed with [chezmoi](https://www.chezmoi.io/).

## Setup

Supported: macOS and dnf-based Linux (tested on Fedora 43 and AlmaLinux 9).

```sh
# chezmoi not installed yet:
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply jmoles

# chezmoi already installed:
chezmoi init --apply jmoles
```

Afterwards, update with `chezmoi update`.

## Prerequisites

[`run_onchange_before_install-prereqs.sh.tmpl`](run_onchange_before_install-prereqs.sh.tmpl)
installs these before any dotfiles are written. It re-runs only when the
script changes, and needs `sudo` on Linux and admin rights on macOS.

| Tool | Used by | macOS | Fedora/RHEL (dnf) |
| --- | --- | --- | --- |
| zsh + [Oh My Zsh](https://ohmyz.sh/) | `.zshrc` | built in | `zsh`; login shell set via `chsh` |
| git, git-lfs | `.gitconfig` (LFS filter is `required`) | Xcode CLT, Homebrew | `git`, `git-lfs` |
| 1Password app | commit signing (`op-ssh-sign` on macOS, `ssh-keygen` on Linux), SSH agent | Homebrew cask | `1password`, only if a display manager is enabled |
| 1Password CLI (`op`) | Oh My Zsh `1password` plugin | Homebrew cask | `1password-cli` |
| vim | git `core.editor` | built in | `vim-enhanced` |
| [betterleaks](https://github.com/betterleaks/betterleaks) | global git `pre-commit` secret scan | Homebrew | `betterleaks` |
| tmux + `tmux-256color` terminfo | `.tmux.conf` | Homebrew; terminfo built in | `tmux` |
| clangd | Claude Code `clangd-lsp` plugin | Xcode CLT | `clang-tools-extra` |
| [Ghostty](https://ghostty.org/) | `~/.config/ghostty` | Homebrew cask | not installed; see Optional |
| curl | setup | built in | `curl` |

Also:

- Oh My Zsh is pulled by chezmoi itself
  ([`.chezmoiexternal.toml`](.chezmoiexternal.toml)), refreshed weekly.
- On Linux, the 1Password dnf repo is added if missing. `util-linux-user` is
  installed for `chsh` on EL9.
- macOS: on a fresh machine the first apply starts the Xcode Command Line
  Tools installer and stops. Finish it, then run `chezmoi apply` again.
  Homebrew is installed if missing.
- Linux without dnf: the script exits with an error. Install the tools
  above by hand.

## Manual steps

1. Open 1Password, sign in, and in **Settings → Developer** enable the SSH
   agent and the CLI integration. Until then `git commit` fails (signing
   is required) and SSH has no keys.
2. Log out and back in so the new login shell takes effect (Linux).

On headless Linux hosts only the CLI is installed. Commit signing and the
SSH agent work there only through a forwarded agent (see below).

## SSH agent forwarding and per-host config

Host-specific SSH config lives in
[`private_dot_ssh/private_config.d/encrypted_private_hosts.age`](private_dot_ssh/private_config.d/),
encrypted with age so host details aren't published with this repo
(names committed before this change are still in git history). Edit it with
`chezmoi edit ~/.ssh/config.d/hosts`.

Hosts opt in to `ForwardAgent yes` there. On those hosts, git signs with
`ssh-keygen` through the forwarded agent, so the 1Password approval prompt
shows up on the machine you're SSHing from. Signatures verify locally
(`git log --show-signature`) against
[`~/.config/git/allowed_signers`](dot_config/private_git/allowed_signers),
whose key must match `user.signingkey`. Anyone with root on a forwarded
host can use your agent while you're connected, so only opt in hosts you
control.

To decrypt on a machine you SSH from:

1. Copy the age identity from the 1Password item **Chezmoi Key** into
   `~/.config/chezmoi/key.txt` and run `chmod 600` on it.
2. Run `chezmoi init` to regenerate the config, then `chezmoi apply`.

Machines without `key.txt` skip the encrypted file
([`.chezmoiignore`](.chezmoiignore)), so headless hosts apply cleanly.

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
