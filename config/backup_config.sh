#!/bin/bash
# MIT License https://mit-license.org
#
# Copyright (c) 2024 Esteban Cuevas <esteban at actitud dot xyz>

# Configuration for backup.sh
# List of files and directories from $HOME to be copied directly into the dotfiles/home/ directory.
# For items here, the source is $HOME/item and target is dotfiles/home/item.
# Convention: Append a trailing slash (/) to directory names for clarity.

declare -a DOTFILES_TO_COPY_DIRECTLY=(
    ".zshrc"
    ".zsh_history"
    ".bashrc"
    ".bash_history"
    ".bash_profile"
    ".gitconfig"
    ".gitignore"
    ".gitignore_global"
    ".ssh/"        # CONTAINS HIGHLY SENSITIVE SSH KEYS! Don't sync online
    ".gnupg/"      # CONTAINS HIGHLY SENSITIVE GPG KEYS! Don't sync online
    ".pki/"        # CONTAINS SENSITIVE PUBLIC KEY INFRASTRUCTURE FILES (CERTIFICATES, PRIVATE KEYS)! Don't sync online
    ".subversion/" # CONTAINS SVN CLIENT CONFIG AND POTENTIALLY CACHED CREDENTIALS (IN auth/)! Don't sync online
    ".fonts/"
    ".themes/"
    ".icons/"
    ".codeium/"
    ".cursor/"
    ".vscode/"
    ".windsurf/"
    ".oh-my-zsh/custom/plugins/"
    ".oh-my-zsh/custom/themes/"
    ".local/bin/strauss"
    ".local/bin/lolcate"
    ".local/share/applications/"               # User-specific application data, e.g., for Ulauncher
    ".local/share/gnome-shell/extensions/"     # GNOME Shell extensions
    ".local/share/nautilus/scripts/"           # Nautilus scripts
    ".local/share/nautilus-python/extensions/" # Nautilus Python extensions
    ".local/share/ulauncher/extensions/"       # Ulauncher extensions
    ".config/ulauncher/"                       # Ulauncher configuration directory
    ".config/lolcate/default/config.toml"
    ".config/lolcate/default/ignores"
    ".config/zed/settings.json"
    ".config/appimagelauncher.cfg"
    ".config/chromium-flags.conf"
    ".config/code-flags.conf"
    ".config/code-url-handler-flags.conf"
    ".config/electron-flags.conf"
    ".config/ferdium-flags.conf"
    ".config/github-desktop.conf"
    ".config/obsidian-flags.conf"
    ".config/ulauncher-flags.conf"
    ".config/ulauncher-toggle-flags.conf"
    # Add other files or directories here, for example:
    # ".config/nvim/"
    # ".config/htop/htoprc"
    # ".local/bin/my_script"
    # "Documents/my_important_template.ott"
)
