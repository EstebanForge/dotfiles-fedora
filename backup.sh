#!/bin/bash
# MIT License
#
# Copyright (c) 2025 Esteban Cuevas <esteban at actitud dot xyz>
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

# Script to backup system configurations

# Ensure the script is run from the dotfiles directory
cd "$(dirname "$0")" || exit

# Function to check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Function to ask for confirmation
confirm() {
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
    [yY][eE][sS] | [yY]) true ;;
    *) false ;;
    esac
}

HOME_DIR="home"                          # For user's actual dotfiles to be symlinked
DATA_DIR="config"                        # For generated backup data (package lists, etc.)
CONFIG_FILE="$DATA_DIR/backup_config.sh" # Path to the configuration file

# Source the configuration file here, at the global scope
if [ -f "$CONFIG_FILE" ]; then
    echo "Sourcing configuration from $CONFIG_FILE at global scope..."
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file $CONFIG_FILE not found. Exiting."
    exit 1
fi

ensure_directories() {
    echo "Ensuring base directories..."
    mkdir -p "$HOME_DIR"
    echo "Ensuring '$HOME_DIR' directory exists (for user dotfiles)."
    mkdir -p "$DATA_DIR"
    echo "Ensuring '$DATA_DIR' directory exists (for generated backup data)."
}

load_configuration() {
    echo "Configuration loading step (variables should have been sourced globally)."
    # Configuration is now sourced globally, this function can be used for future validation if needed.
}

backup_gnome_settings() {
    echo "---------------------------------------------------------------------"
    echo "Backing up GNOME settings..."
    local gnome_settings_file="$DATA_DIR/gnome-settings.dconf"
    if [ -f "$gnome_settings_file" ] && [ -s "$gnome_settings_file" ]; then
        if ! confirm "'$gnome_settings_file' already exists and is not empty. Overwrite? [y/N]"; then
            echo "Skipping update of '$gnome_settings_file'."
            return
        fi
    fi
    dconf dump / >"$gnome_settings_file"
    echo "GNOME settings backed up to $gnome_settings_file"
}

backup_flatpak_packages() {
    echo "---------------------------------------------------------------------"
    echo "Backing up Flatpak user and system-installed applications..."
    local config_flatpak_apps_file="$DATA_DIR/flatpak_apps.txt"
    mkdir -p "$(dirname "$config_flatpak_apps_file")"

    if [ -f "$config_flatpak_apps_file" ] && [ -s "$config_flatpak_apps_file" ]; then
        if ! confirm "'$config_flatpak_apps_file' already exists and is not empty. Overwrite? [y/N]"; then
            echo "Skipping update of \"$config_flatpak_apps_file\"."
            return
        fi
    fi

    if command_exists flatpak; then
        (
            flatpak list --app --columns=application
            flatpak list --app --system --columns=application
        ) | sort -u >"$config_flatpak_apps_file"
        echo "Combined Flatpak application list saved to $config_flatpak_apps_file"
    else
        echo "Flatpak command not found. Skipping Flatpak backup."
        touch "$config_flatpak_apps_file"
    fi
}

backup_brew_packages() {
    echo "---------------------------------------------------------------------"
    echo "Backing up Brew packages to $DATA_DIR/brew_packages.txt..."
    local brew_packages_file_path="$DATA_DIR/brew_packages.txt"
    if [ -f "$brew_packages_file_path" ] && [ -s "$brew_packages_file_path" ]; then
        if ! confirm "'$brew_packages_file_path' already exists and is not empty. Overwrite? [y/N]"; then
            echo "Skipping update of '$brew_packages_file_path'."
            return
        fi
    fi

    if command_exists brew; then
        brew bundle dump --file="$brew_packages_file_path" --force
        echo "Brew packages saved to $brew_packages_file_path"

        # Filter out vscode extensions
        if [ -f "$brew_packages_file_path" ]; then
            echo "Filtering out vscode extensions from $brew_packages_file_path..."
            local temp_brew_file
            temp_brew_file=$(mktemp)
            grep -v '^vscode ' "$brew_packages_file_path" >"$temp_brew_file"
            # Check if grep succeeded and the temp file is not empty (to prevent overwriting with an empty file if all lines were vscode lines)
            if [ $? -eq 0 ]; then                 # grep succeeded
                if [ -s "$temp_brew_file" ]; then # temp file is not empty
                    mv "$temp_brew_file" "$brew_packages_file_path"
                    echo "Successfully filtered vscode extensions."
                else
                    mv "$temp_brew_file" "$brew_packages_file_path"
                    echo "Filtered vscode extensions. The resulting file might be empty if all packages were vscode extensions or the original was empty."
                fi
            else
                echo "Warning: Filtering vscode extensions with grep failed. Original file kept."
                rm -f "$temp_brew_file" # Clean up temp file if grep failed
            fi
        fi
    else
        echo "Brew command not found. Skipping Brew backup."
        touch "$brew_packages_file_path" # Create empty file if brew not found and we decided to proceed
    fi
}

backup_appimage_list() {
    echo "---------------------------------------------------------------------"
    echo "Backing up AppImage list..."
    local appimage_list_file="$DATA_DIR/appimage_list.txt"
    if [ -f "$appimage_list_file" ] && [ -s "$appimage_list_file" ]; then
        if ! confirm "'$appimage_list_file' already exists and is not empty. Overwrite? [y/N]"; then
            echo "Skipping update of '$appimage_list_file'."
            return
        fi
    fi

    if [ -d "$HOME/Applications" ]; then
        find "$HOME/Applications/" -maxdepth 1 -type f -iname "*.appimage" -printf "%f\n" >"$appimage_list_file"
        echo "AppImage list saved to $appimage_list_file"
    else
        echo "No ~/Applications directory found. Skipping AppImage backup."
        touch "$appimage_list_file"
    fi
}

# Helper function for backup_critical_dotfiles
_backup_dotfile_item() {
    local source_item_path="$1"
    local target_item_name="$2"
    local backup_dest_path="$HOME_DIR/$target_item_name"

    # Ensure the parent directory of the destination exists
    local target_parent_dir=$(dirname "$backup_dest_path")
    if [ ! -d "$target_parent_dir" ]; then
        mkdir -p "$target_parent_dir"
        echo "Created directory structure: $target_parent_dir"
    fi

    if [ -e "$source_item_path" ]; then
        echo "Backing up '$source_item_path' to '$backup_dest_path' using rsync..."
        if rsync -avh --no-perms --delete "$source_item_path" "$backup_dest_path"; then
            echo "Successfully backed up '$target_item_name'."
        else
            echo "Error during rsync of '$target_item_name'. Check rsync output above."
        fi
    else
        echo "Source '$source_item_path' not found, skipping."
    fi
}

backup_critical_dotfiles() {
    echo "---------------------------------------------------------------------"
    echo "Backing up critical dotfiles from user's home to $HOME_DIR/ (based on $CONFIG_FILE)..."
    echo "---------------------------------------------------------------------"

    if [ ${#DOTFILES_TO_COPY_DIRECTLY[@]} -gt 0 ]; then
        for item in "${DOTFILES_TO_COPY_DIRECTLY[@]}"; do
            _backup_dotfile_item "$HOME/$item" "$item"
        done
    else
        echo "No items listed in DOTFILES_TO_COPY_DIRECTLY in $CONFIG_FILE. Skipping this section."
    fi
}

check_ssh_backup_warning() {
    if [[ " ${DOTFILES_TO_COPY_DIRECTLY[@]} " =~ " .ssh " ]] || [[ " ${DOTFILES_TO_COPY_DIRECTLY[@]} " =~ " .ssh/ " ]]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "WARNING: .ssh directory is configured for backup. This includes your private keys."
        echo "Ensure this dotfiles repository is stored securely. Not on a public server!"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    fi
}

finalize_backup() {
    echo -e "\n---------------------------------------------------------------------"
    echo "Backup complete!"
    echo "Review the output for any errors."
    echo "Make sure to backup this entire directory to a safe location, like"
    echo "an external drive, local NAS or a secure cloud storage."
    echo "---------------------------------------------------------------------"
}

main() {
    echo "Starting backup process..."

    ensure_directories
    load_configuration # This sources $CONFIG_FILE, making DOTFILES_TO_COPY_DIRECTLY available

    backup_gnome_settings
    backup_flatpak_packages
    backup_brew_packages
    backup_appimage_list
    backup_critical_dotfiles
    check_ssh_backup_warning

    finalize_backup
    exit 0
}

# --- Main execution ---
main
