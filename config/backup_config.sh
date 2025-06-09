#!/bin/bash
# MIT License
#
# Copyright (c) 2024 Esteban Cuevas <esteban at actitud dot xyz>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

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
    ".ssh/" # CONTAINS HIGHLY SENSITIVE SSH KEYS! Don't sync online
    ".gnupg/" # CONTAINS HIGHLY SENSITIVE GPG KEYS! Don't sync online
    ".pki/" # CONTAINS SENSITIVE PUBLIC KEY INFRASTRUCTURE FILES (CERTIFICATES, PRIVATE KEYS)! Don't sync online
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
    ".local/share/applications/" # User-specific application data, e.g., for Ulauncher
    ".local/share/gnome-shell/extensions/" # GNOME Shell extensions
    ".local/share/nautilus/scripts/"       # Nautilus scripts
    ".local/share/nautilus-python/extensions/" # Nautilus Python extensions
    ".local/share/ulauncher/extensions/"   # Ulauncher extensions
    ".config/ulauncher/"                   # Ulauncher configuration directory
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
