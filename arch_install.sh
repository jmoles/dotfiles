#!/bin/bash
# Script to install tools I commonly use on arch.

PACMAN_SYNC="pacman --sync --noconfirm"

if [[ "$(id -u)" != "0" ]]; then
  echo "This script must be run as root."
  exit 1
fi

# OS Basics
## Tools
$PACMAN_SYNC curl 
$PACMAN_SYNC wget
$PACMAN_SYNC zsh
$PACMAN_SYNC zsh-doc 
$PACMAN_SYNC zsh-completions
$PACMAN_SYNC vim

# Tools
## Editors
$PACMAN_SYNC code
## Browsers
$PACMAN_SYNC firefox
$PACMAN_SYNC chromium
$PACMAN_SYNC google-chrome
## File Management
$PACMAN_SYNC syncthing

