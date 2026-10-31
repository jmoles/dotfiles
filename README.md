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
| 1Password app | commit signing (`op-ssh-sign`), SSH agent | Homebrew cask | `1password`, only if a display manager is enabled |
| 1Password CLI (`op`) | Oh My Zsh `1password` plugin | Homebrew cask | `1password-cli` |
| vim | git `core.editor` | built in | `vim-enhanced` |
| tmux + `tmux-256color` terminfo | `.tmux.conf` | Homebrew; terminfo built in | `tmux` |
| clangd | Claude Code `clangd-lsp` plugin | Xcode CLT | `clang-tools-extra` |
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
SSH agent need the desktop app, so they don't work there.

## Optional

These only add to `PATH` or define aliases. Install them as needed; nothing
breaks without them.

- Rust via [rustup](https://rustup.rs/) (`~/.cargo/bin`)
- Go (`~/go/bin`)
- Ruby gems in `~/gems` (`GEM_HOME`)
- Visual Studio Code (`code` on `PATH`)
- AMD Vitis 2026.1 at `/opt/xilinx/2026.1` (`xilinx-env` alias)

## CI

GitHub Actions runs `chezmoi apply --dry-run` on macOS and Ubuntu,
shellcheck, and TOML/JSON validation.
