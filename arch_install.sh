#!/bin/bash
# Script to install tools I commonly use on arch.

PACMAN_SYNC="pacman --sync --noconfirm"

if [[ "$(id -u)" != "0" ]]; then
  echo "This script must be run as root."
  exit 1
fi


$PACMAN_SYNC curl wget
$PACMAN_SYNC zsh zsh-doc zsh-completions
$PACMAN_SYNC vim
