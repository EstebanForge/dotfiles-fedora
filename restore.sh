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

# Script for post-installation setup tasks on Fedora

# Ensure the script is run from the dotfiles directory
cd "$(dirname "$0")" || exit

HOME_SOURCE_DIR="home"      # The directory within the dotfiles repo that mirrors the user's home for symlinking
GENERATED_DATA_DIR="config" # The directory within the dotfiles repo where generated backup files are stored
USER_HOME="$HOME"           # The actual home directory of the user

# Function to ask for confirmation
confirm() {
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
    [yY][eE][sS] | [yY]) true ;;
    *) false ;;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

echo "Starting post-installation setup..."
echo "This script will attempt to automate various system configurations."
echo "It should be run as your regular user. It will use 'sudo' for commands requiring root privileges."
echo "Ensure you have 'sudo' privileges and an active internet connection."

# --- Rsync $HOME_SOURCE_DIR to $USER_HOME ---
rsync_source_home_to_user_home() {
    echo -e "\n--- Copying files from '$HOME_SOURCE_DIR/' to '$USER_HOME/' using rsync ---" # Ensuring -e for proper newline handling

    if [ ! -d "$HOME_SOURCE_DIR" ]; then
        echo "Error: Source directory '$HOME_SOURCE_DIR' not found in the current path ($(pwd)). Skipping rsync."
    else
        # Ensure we are in the root of the dotfiles repository for correct relative paths
        # The script already cds to its own directory, so pwd should be the dotfiles repo root.
        local repo_root
        repo_root=$(pwd)
        local rsync_source_path="$repo_root/$HOME_SOURCE_DIR/"
        local rsync_target_path="$USER_HOME/"

        echo "Source for rsync: $rsync_source_path"
        echo "Target for rsync: $rsync_target_path"

        if confirm "Proceed with copying files using rsync? This will overwrite existing files in the target if they are different, and create directories as needed. [y/N]"; then
            echo "Starting rsync operation..."
            # -a: archive mode (preserves permissions, ownership (if run as root), times, symlinks, recursive, etc.)
            # -v: verbose
            # -h: human-readable numbers
            # --delete: delete extraneous files from dest dirs (optional, uncomment if desired)
            # --backup --backup-dir=../rsync_backups_$(date +%Y-%m-%d_%H-%M-%S): create backups of overwritten files (optional)
            if rsync -avh "$rsync_source_path" "$rsync_target_path"; then
                echo "Rsync operation completed successfully."
            else
                echo "Rsync operation encountered errors. Please review the output above."
            fi
        else
            echo "Skipping rsync operation for $HOME_SOURCE_DIR."
        fi
    fi
}

# --- RPM Fusion ---
setup_rpm_fusion() {
    if confirm "Install RPM Fusion repositories? [y/N]"; then
        echo "Installing RPM Fusion..."
        sudo dnf install -y \
            "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
            "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
        echo "RPM Fusion installation attempted."
        echo "Updating DNF cache after adding RPM Fusion repositories..."
        if sudo dnf check-update; then
            echo "DNF cache updated successfully."
        else
            echo "Warning: 'sudo dnf check-update' failed or returned an error. Consider running it manually."
        fi
    else
        echo "Skipping RPM Fusion setup."
    fi
}

# --- Common DNF Packages ---
install_common_dnf_packages() {
    if confirm "Install common DNF packages from $GENERATED_DATA_DIR/dnf_packages.txt? [y/N]"; then
        echo "Processing DNF packages from $GENERATED_DATA_DIR/dnf_packages.txt..."
        local dnf_packages_file="$GENERATED_DATA_DIR/dnf_packages.txt"

        if [ ! -f "$dnf_packages_file" ] || [ ! -r "$dnf_packages_file" ]; then
            echo "Error: DNF packages file not found or not readable at $dnf_packages_file."
            echo "Skipping DNF package installation from file."
            return
        fi

        local groups_to_install_list=()
        local packages_to_install_list=()

        while IFS= read -r line || [[ -n "$line" ]]; do
            # Trim leading/trailing whitespace
            line=$(echo "$line" | awk '{$1=$1};1')

            if [[ -z "$line" ]] || [[ "$line" == \#* ]]; then # Skip empty lines and comments
                continue
            fi

            if [[ "$line" == group:* ]]; then
                local group_name="${line#group:}"
                group_name=$(echo "$group_name" | awk '{$1=$1};1') # Trim group name
                if [[ -n "$group_name" ]]; then
                    groups_to_install_list+=("$group_name")
                fi
            else
                # Add packages from the line to the list; $line can contain multiple space-separated packages
                packages_to_install_list+=($line)
            fi
        done <"$dnf_packages_file"

        if [ ${#groups_to_install_list[@]} -gt 0 ]; then
            echo "Installing DNF groups: ${groups_to_install_list[*]}..."
            if sudo dnf group install -y "${groups_to_install_list[@]}"; then
                echo "DNF groups installation attempted successfully for: ${groups_to_install_list[*]}."
            else
                echo "Error or issues encountered during DNF group installation for: ${groups_to_install_list[*]}."
            fi
        else
            echo "No DNF groups to install from file."
        fi

        if [ ${#packages_to_install_list[@]} -gt 0 ]; then
            echo "Installing DNF packages: ${packages_to_install_list[*]}..."
            if sudo dnf install -y "${packages_to_install_list[@]}" --skip-unavailable --allowerasing; then
                echo "DNF packages installation attempted successfully for: ${packages_to_install_list[*]}."
            else
                echo "Error or issues encountered during DNF package installation for: ${packages_to_install_list[*]}."
            fi
        else
            echo "No DNF packages to install from file."
        fi

        echo "Common DNF packages processing from file completed."
    else
        echo "Skipping common DNF packages installation from file."
    fi
}

# --- Restore Flatpak Packages ---
restore_flatpak_packages() {
    echo "--- Restoring Flatpak Packages ---"
    if ! command_exists flatpak; then
        echo "Flatpak command not found. Please install Flatpak first."
        echo "Skipping Flatpak package restoration."
        return
    fi

    if [ -f "flatpak_apps.txt" ] && [ -s "flatpak_apps.txt" ]; then
        if confirm "Reinstall user Flatpak applications from flatpak_apps.txt? [y/N]"; then
            echo "Reinstalling user Flatpak applications..."
            xargs -r -a "flatpak_apps.txt" flatpak install --user -y
            # xargs -r ensures it doesn't run if the file is empty, though the -s check should cover this.
            echo "User Flatpak applications reinstallation process initiated."
        else
            echo "Skipping user Flatpak application reinstallation."
        fi
    else
        echo "flatpak_apps.txt not found or empty. Skipping user Flatpak application reinstallation."
    fi
}

# --- Flatpak Overrides ---
setup_flatpak_overrides() {
    if command_exists flatpak; then
        if confirm "Apply Flatpak overrides for Bitwarden (Wayland, IPC)? [y/N]"; then
            echo "Applying Flatpak overrides for com.bitwarden.desktop..."
            flatpak override --user --env=ELECTRON_OZONE_PLATFORM_HINT=auto com.bitwarden.desktop
            flatpak override --user --socket=wayland com.bitwarden.desktop
            flatpak override --user --nosocket=x11 com.bitwarden.desktop
            flatpak override --user --unshare=ipc com.bitwarden.desktop
            echo "Flatpak overrides for Bitwarden applied."
        else
            echo "Skipping Flatpak overrides for Bitwarden."
        fi
    else
        echo "Flatpak command not found. Skipping Flatpak overrides."
    fi
}

# --- Homebrew Installation ---
install_homebrew() {
    if ! command_exists brew; then
        if confirm "Install Homebrew (Linuxbrew)? [y/N]"; then
            echo "Installing Homebrew..."
            # Ensure curl is installed as Homebrew installer uses it
            if ! command_exists curl; then
                echo "curl is not installed. Attempting to install curl..."
                if sudo dnf install -y curl; then
                    echo "curl installed successfully."
                else
                    echo "Failed to install curl. Homebrew installation might fail."
                    # Decide if we should return or let the Homebrew installer try and fail
                fi
            fi

            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            echo "Homebrew installation attempted. Please follow any on-screen instructions."

            # Source Homebrew environment for the current script session
            local brew_executable_path="/home/linuxbrew/.linuxbrew/bin/brew"
            if [ -f "$brew_executable_path" ]; then
                echo "Adding Homebrew to PATH for current session..."
                eval "$("$brew_executable_path" shellenv)"
                # Verify if brew is now in PATH
                if command_exists brew; then
                    echo "Homebrew successfully added to PATH for this session."
                else
                    echo "Failed to add Homebrew to PATH for this session. Brew commands might fail until shell is reloaded or PATH is manually updated."
                fi
            else
                echo "Homebrew executable not found at $brew_executable_path after installation attempt. Manual PATH configuration might be needed."
            fi

            echo "You might need to add Homebrew to your PATH permanently (e.g. in .zshrc or .bashrc). The installer usually provides instructions."
            echo "IMPORTANT: For Homebrew to work correctly with system services or scripts run by root, you might need to add its path (e.g., /home/linuxbrew/.linuxbrew/bin) to 'secure_path' in /etc/sudoers. Use 'sudo visudo' carefully."
        else
            echo "Skipping Homebrew installation."
        fi
    else
        echo "Homebrew already installed."
        # Even if already installed, ensure it's in PATH for the current session if possible
        local brew_executable_path="/home/linuxbrew/.linuxbrew/bin/brew"
        if [ -f "$brew_executable_path" ] && ! command_exists brew; then # Check if brew command is not found despite file existing
            echo "Homebrew executable found, attempting to set up environment for current session..."
            eval "$("$brew_executable_path" shellenv)"
            if command_exists brew; then
                echo "Homebrew environment set up for current session."
            else
                echo "Failed to set up Homebrew environment for current session from existing installation."
            fi
        fi
    fi
}

# --- Brew Packages ---
install_brew_packages() {
    if command_exists brew; then
        if confirm "Install Brew packages from $GENERATED_DATA_DIR/brew_packages.txt? [y/N]"; then
            echo "Installing Brew packages from $GENERATED_DATA_DIR/brew_packages.txt..."
            # Source Homebrew environment script if it exists and brew is not in PATH
            if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            elif [ -f /opt/homebrew/bin/brew ]; then # macOS path, but good to have a fallback
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi

            local brew_packages_file_path="$GENERATED_DATA_DIR/brew_packages.txt"

            if [ -f "$brew_packages_file_path" ] && [ -s "$brew_packages_file_path" ]; then
                echo "Found $brew_packages_file_path. Attempting to install packages..."
                if brew bundle install --file="$brew_packages_file_path"; then
                    echo "Brew packages installation from $brew_packages_file_path attempted successfully."
                else
                    echo "Error or issues encountered during Brew package installation from $brew_packages_file_path."
                fi
            else
                echo "Error: Brew packages file not found or empty at $brew_packages_file_path."
                echo "Skipping Brew package installation from file."
            fi
        else
            echo "Skipping Brew packages installation."
        fi
    else
        echo "Homebrew not found. Skipping Brew packages."
    fi
}

# --- SSH Permissions ---
setup_ssh_permissions() {
    if [ -d "$HOME/.ssh" ]; then
        if confirm "Set recommended SSH permissions for $HOME/.ssh? [y/N]"; then
            echo "Setting SSH permissions..."
            chmod 700 "$HOME/.ssh"
            find "$HOME/.ssh" -type f ! -name "*.pub" -exec chmod 600 {} \;
            find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} \;
            [ -f "$HOME/.ssh/authorized_keys" ] && chmod 600 "$HOME/.ssh/authorized_keys"
            [ -f "$HOME/.ssh/known_hosts" ] && chmod 644 "$HOME/.ssh/known_hosts"
            # chown should not be needed if script is run as user and user owns their .ssh dir.
            # If there are ownership issues, the user should fix them.
            echo "SSH permissions set. Verifying ownership (should be current user)..."
            ls -ld "$HOME/.ssh"
            ls -l "$HOME/.ssh"
        else
            echo "Skipping SSH permissions setup."
        fi
    else
        echo "$HOME/.ssh directory not found. Skipping SSH permissions setup."
    fi
}

# --- ZSH and Oh-My-Zsh ---
setup_zsh() {
    if confirm "Install Zsh, Oh-My-Zsh, and Zsh plugins (syntax-highlighting, autosuggestions, completions via Homebrew)? [y/N]"; then
        echo "Setting up Zsh..."
        if ! command_exists zsh; then
            sudo dnf install -y zsh
        fi

        if [ "$SHELL" != "$(which zsh)" ]; then
            if confirm "Set Zsh as default shell for $USER? [y/N]"; then
                chsh -s "$(which zsh)"
                echo "Zsh set as default shell. You may need to log out and log back in for this to take full effect."
            fi
        else
            echo "Zsh is already the default shell."
        fi

        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            echo "Installing Oh-My-Zsh..."
            sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            echo "Oh-My-Zsh installation attempted."
        else
            echo "Oh-My-Zsh already installed."
        fi

        echo "Zsh plugins (zsh-syntax-highlighting, zsh-autosuggestions, zsh-completions) are installed via Homebrew."
        echo "Ensure they are sourced in your .zshrc:"
        echo "Example for .zshrc (Oh My Zsh plugins array):"
        echo "plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)"
        echo "Or manually source if needed (check paths after brew install):"
        echo "source /home/linuxbrew/.linuxbrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
        echo "source /home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
        echo "source /home/linuxbrew/.linuxbrew/share/zsh-completions/zsh-completions.zsh"
    else
        echo "Skipping Zsh setup."
    fi
}

# --- Docker ---
setup_docker() {
    if confirm "Install Docker and configure? [y/N]"; then
        echo "Setting up Docker..."
        if ! command_exists docker; then
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo usermod -aG docker "$USER"
            echo "Docker installed. You may need to log out and log back in for group changes to take effect."
            echo "Docker service started. Current status:"
            sudo systemctl status docker --no-pager
        else
            echo "Docker already installed."
        fi

        if confirm "Set Docker to NOT start automatically on boot? (Otherwise it will be enabled) [y/N]"; then
            sudo systemctl stop docker.service
            sudo systemctl disable docker.service
            sudo systemctl disable docker.socket
            echo "Docker auto-start disabled."
        else
            if ! sudo systemctl is-enabled docker.service &>/dev/null; then
                sudo systemctl enable docker.service
                echo "Docker auto-start enabled."
            else
                echo "Docker auto-start was already enabled or is currently running."
            fi
        fi

        # Docker socket permissions (usually handled by package, but good to check)
        if [ -e /var/run/docker.sock ]; then
            if ! getfacl /var/run/docker.sock | grep -q "group:docker:rw-"; then
                sudo chown root:docker /var/run/docker.sock
                sudo chmod 660 /var/run/docker.sock
                echo "Permissions for /var/run/docker.sock verified/set."
            fi
        fi
    else
        echo "Skipping Docker setup."
    fi
}

# --- GNOME Specific Settings ---
setup_gnome_settings() {
    if confirm "Apply various GNOME specific settings (fractional scaling, touchpad drag lock)? [y/N]"; then
        echo "Applying GNOME settings..."
        gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
        echo "Enabled GNOME fractional scaling experimental feature."
        gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag-lock true
        echo "Enabled touchpad tap-and-drag-lock."
    else
        echo "Skipping GNOME specific settings."
    fi
}

# --- Font Rendering (macOS like) ---
setup_font_rendering() {
    if confirm "Apply macOS-like font rendering settings (FreeType, GNOME)? [y/N]"; then
        echo "Applying macOS-like font rendering settings..."

        # User-specific FreeType properties
        mkdir -p "$HOME/.config/environment.d/"
        echo 'FREETYPE_PROPERTIES="cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0"' >"$HOME/.config/environment.d/freetype.conf"
        echo "User FreeType properties set in $HOME/.config/environment.d/freetype.conf"

        # System-wide FreeType properties (subset for /etc/environment)
        # Note: /etc/environment is not a script, so it's just KEY=VALUE pairs.
        # We'll check for a simpler marker to avoid duplicate full lines if one part changes.
        local etc_env_freetype_line='FREETYPE_PROPERTIES="cff:no-stem-darkening=0 autofitter:no-stem-darkening=0"'
        if ! sudo grep -q "cff:no-stem-darkening=0" /etc/environment || ! sudo grep -q "autofitter:no-stem-darkening=0" /etc/environment; then
            # Check if FREETYPE_PROPERTIES is already there and append, or add new line
            if sudo grep -q "^FREETYPE_PROPERTIES=" /etc/environment; then
                echo "Warning: FREETYPE_PROPERTIES already exists in /etc/environment. Manual check recommended."
                echo "Attempting to append cff:no-stem-darkening=0 and autofitter:no-stem-darkening=0 if not present."
                # This is tricky; for now, we'll just add the full desired line if our specific parts are missing,
                # which might lead to duplicates if the existing line is different. A more robust sed would be needed for modification.
                # For simplicity and safety, if the key parts are missing, we add our preferred line.
                # This could be improved by more complex sed logic to merge, but that's riskier.
                if ! sudo grep -q "${etc_env_freetype_line}" /etc/environment; then # Add only if exact line isn't there
                    echo "${etc_env_freetype_line}" | sudo tee -a /etc/environment >/dev/null
                    echo "System FreeType properties added to /etc/environment. Review this file for duplicates if FREETYPE_PROPERTIES existed previously with different values."
                else
                    echo "System FreeType properties (cff & autofitter no-stem-darkening) seem to be present in /etc/environment."
                fi
            else
                echo "${etc_env_freetype_line}" | sudo tee -a /etc/environment >/dev/null
                echo "System FreeType properties added to /etc/environment."
            fi
        else
            echo "System FreeType properties (cff & autofitter no-stem-darkening) already set in /etc/environment."
        fi

        # GNOME settings
        gsettings set org.gnome.desktop.interface font-hinting 'none'
        gsettings set org.gnome.desktop.interface font-antialiasing 'grayscale'
        echo "GNOME font hinting set to 'none' and antialiasing to 'grayscale'."

        echo "Font rendering changes may require a logout/reboot to take full effect."
    else
        echo "Skipping macOS-like font rendering settings."
    fi
}

# --- Crypto Policies (OpenSSL Legacy for Pantheon) ---
setup_crypto_policies() {
    if confirm "Manage system-wide crypto policies (e.g., for OpenSSL LEGACY)? [y/N]"; then
        echo "Current crypto policy: $(update-crypto-policies --show)"
        if confirm "Set crypto policy to LEGACY (e.g., for Pantheon, older SSL/TLS)? This has security implications. [y/N]"; then
            echo "Setting crypto policy to LEGACY..."
            sudo update-crypto-policies --set LEGACY
            echo "Crypto policy set to LEGACY. Current policy: $(update-crypto-policies --show)"
            echo "To revert, you can run this script again or use: sudo update-crypto-policies --set DEFAULT"
        elif confirm "Set crypto policy to DEFAULT (revert from LEGACY or other)? [y/N]"; then
            echo "Setting crypto policy to DEFAULT..."
            sudo update-crypto-policies --set DEFAULT
            echo "Crypto policy set to DEFAULT. Current policy: $(update-crypto-policies --show)"
        else
            echo "No changes made to crypto policies."
        fi
    else
        echo "Skipping crypto policy management."
    fi
}

# --- AMD P-States and s2idle Grub Configuration ---
setup_amd_pstates_and_s2idle_grub_args() {
    if confirm "Configure GRUB for AMD P-States (guided) and s2idle sleep? (Modifies kernel boot parameters) [y/N]"; then
        echo "Applying AMD P-States (guided) and mem_sleep_default=s2idle to GRUB kernel arguments..."

        local current_args
        current_args=$(sudo grubby --info=ALL | grep -E "^args=" | sed -e 's/^args="//' -e 's/"$//' | head -n 1) # Get args from the first kernel entry as a sample

        # Check if amd_pstate=guided is already set
        if [[ "$current_args" == *"amd_pstate=guided"* ]]; then
            echo "Kernel argument 'amd_pstate=guided' seems to be already set."
        else
            echo "Adding 'amd_pstate=guided' to kernel arguments..."
            if sudo grubby --update-kernel=ALL --args="amd_pstate=guided"; then
                echo "Successfully added 'amd_pstate=guided'."
            else
                echo "Failed to add 'amd_pstate=guided'."
                # Optionally, decide if you want to proceed or return
            fi
        fi

        # Check if mem_sleep_default=s2idle is already set
        if [[ "$current_args" == *"mem_sleep_default=s2idle"* ]]; then
            echo "Kernel argument 'mem_sleep_default=s2idle' seems to be already set."
        else
            echo "Adding 'mem_sleep_default=s2idle' to kernel arguments..."
            if sudo grubby --update-kernel=ALL --args="mem_sleep_default=s2idle"; then
                echo "Successfully added 'mem_sleep_default=s2idle'."
            else
                echo "Failed to add 'mem_sleep_default=s2idle'."
                # Optionally, decide if you want to proceed or return
            fi
        fi

        echo "Rebuilding GRUB configuration..."
        if sudo grub2-mkconfig -o /boot/grub2/grub.cfg; then
            echo "GRUB configuration rebuilt successfully."
        else
            echo "Failed to rebuild GRUB configuration."
        fi
        echo "Changes to GRUB will take effect on next reboot."
    else
        echo "Skipping AMD P-States and s2idle GRUB configuration."
    fi
}

# --- System Environment and Profile ---
setup_system_environment() {
    if confirm "Configure system environment (Gnome animations, Electron Wayland, GSK Renderer)? [y/N]"; then
        echo "Configuring system environment..."

        # GNOME_SHELL_SLOWDOWN_FACTOR
        if ! grep -q "GNOME_SHELL_SLOWDOWN_FACTOR" /etc/environment; then
            echo 'GNOME_SHELL_SLOWDOWN_FACTOR=0.5' | sudo tee -a /etc/environment >/dev/null
            echo "GNOME_SHELL_SLOWDOWN_FACTOR set in /etc/environment."
        else
            echo "GNOME_SHELL_SLOWDOWN_FACTOR already in /etc/environment."
        fi

        # ELECTRON_OZONE_PLATFORM_HINT
        if ! grep -q "ELECTRON_OZONE_PLATFORM_HINT" /etc/environment; then
            echo 'ELECTRON_OZONE_PLATFORM_HINT=wayland' | sudo tee -a /etc/environment >/dev/null
            echo "ELECTRON_OZONE_PLATFORM_HINT set in /etc/environment."
        else
            echo "ELECTRON_OZONE_PLATFORM_HINT already in /etc/environment."
        fi

        echo "These changes may require a logout/reboot to take full effect."
    else
        echo "Skipping system environment configuration."
    fi
}

# --- Software Installations (Browsers, Editors, etc.) ---
install_additional_software() {
    if confirm "Install additional software (Brave, Sublime Text, GitHub Desktop, Mullvad, 1Password, Beyond Compare, NordVPN, Insync, LocalWP)? [y/N]"; then
        # Brave Browser
        if ! command_exists brave-browser; then
            echo "Installing Brave Browser..."
            sudo dnf install -y dnf-plugins-core # For config-manager
            sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo dnf install -y brave-browser
            echo "Brave Browser installation attempted."
        else
            echo "Brave Browser already installed."
        fi

        # Sublime Text & Merge
        if ! command_exists subl; then
            echo "Installing Sublime Text and Sublime Merge..."
            sudo dnf config-manager addrepo --from-repofile=https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo
            sudo rpm -v --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg
            sudo dnf install -y sublime-text sublime-merge
            echo "Sublime Text and Merge installation attempted."
        else
            echo "Sublime Text already installed."
        fi

        # GitHub Desktop
        if ! command_exists github-desktop; then
            echo "Installing GitHub Desktop..."
            sudo rpm --import https://mirror.mwt.me/shiftkey-desktop/gpgkey
            sudo sh -c 'echo -e "[mwt-packages]\nname=GitHub Desktop\nbaseurl=https://mirror.mwt.me/shiftkey-desktop/rpm\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://mirror.mwt.me/shiftkey-desktop/gpgkey" > /etc/yum.repos.d/mwt-packages.repo'
            sudo dnf install -y github-desktop
            echo "GitHub Desktop installation attempted."
        else
            echo "GitHub Desktop already installed."
        fi

        # 1Password
        if ! command_exists 1password; then
            echo "Installing 1Password..."
            local onepassword_rpm_url="https://downloads.1password.com/linux/rpm/stable/x86_64/1password-latest.rpm"
            local temp_rpm_path="/tmp/1password-latest.rpm"
            echo "Downloading 1Password RPM from $onepassword_rpm_url..."
            if curl -L -o "$temp_rpm_path" "$onepassword_rpm_url"; then
                echo "Download successful. Installing 1Password..."
                if sudo dnf install -y "$temp_rpm_path"; then
                    echo "1Password installation successful."
                else
                    echo "Error: Failed to install 1Password from RPM."
                fi
                rm -f "$temp_rpm_path" # Clean up downloaded RPM
            else
                echo "Error: Failed to download 1Password RPM."
            fi
        else
            echo "1Password already installed."
        fi

        # Beyond Compare
        if ! command_exists bcompare; then
            echo "Installing Beyond Compare..."
            local bcompare_rpm_url="https://www.scootersoftware.com/files/bcompare-5.1.0.31016.x86_64.rpm"
            local temp_rpm_path="/tmp/bcompare-latest.rpm"
            echo "Downloading Beyond Compare RPM from $bcompare_rpm_url..."
            if curl -L -o "$temp_rpm_path" "$bcompare_rpm_url"; then
                echo "Download successful. Installing Beyond Compare..."
                if sudo dnf install -y "$temp_rpm_path"; then
                    echo "Beyond Compare installation successful."
                else
                    echo "Error: Failed to install Beyond Compare from RPM."
                fi
                rm -f "$temp_rpm_path" # Clean up downloaded RPM
            else
                echo "Error: Failed to download Beyond Compare RPM."
            fi
        else
            echo "Beyond Compare already installed."
        fi

        # NordVPN
        if ! command_exists nordvpn; then
            echo "Installing NordVPN..."
            if sh <(wget -qO - https://downloads.nordcdn.com/apps/linux/install.sh) -p nordvpn-gui; then
                echo "NordVPN installation script executed. Please follow any on-screen instructions."
                # Attempt to add current user to nordvpn group, may require logout/login
                if groups "$USER" | grep -q "\bnordvpn\b"; then
                    echo "User $USER is already in the nordvpn group."
                else
                    echo "Adding user $USER to nordvpn group..."
                    if sudo usermod -aG nordvpn "$USER"; then
                        echo "User $USER added to nordvpn group. A logout/login may be required for this to take effect."
                    else
                        echo "Failed to add user $USER to nordvpn group. Manual intervention may be required."
                    fi
                fi
            else
                echo "Error: NordVPN installation script failed."
            fi
        else
            echo "NordVPN already installed."
        fi

        # Insync
        if ! command_exists insync; then
            echo "Installing Insync..."
            local insync_rpm_url="https://cdn.insynchq.com/builds/linux/3.9.6.60027/insync-3.9.6.60027-fc42.x86_64.rpm"
            local temp_rpm_path="/tmp/insync-latest.rpm"
            echo "Downloading Insync RPM from $insync_rpm_url..."
            if curl -L -o "$temp_rpm_path" "$insync_rpm_url"; then
                echo "Download successful. Installing Insync..."
                if sudo dnf install -y "$temp_rpm_path"; then
                    echo "Insync installation successful."
                else
                    echo "Error: Failed to install Insync from RPM."
                fi
                rm -f "$temp_rpm_path" # Clean up downloaded RPM
            else
                echo "Error: Failed to download Insync RPM."
            fi
        else
            echo "Insync already installed."
        fi

        # LocalWP
        if ! command_exists local; then
            echo "Installing LocalWP..."
            local localwp_rpm_url="https://cdn.localwp.com/releases-stable/9.2.4+6788/local-9.2.4-linux.rpm"
            local temp_rpm_path="/tmp/localwp-latest.rpm"
            echo "Downloading LocalWP RPM from $localwp_rpm_url..."
            if curl -L -o "$temp_rpm_path" "$localwp_rpm_url"; then
                echo "Download successful. Installing LocalWP..."
                if sudo dnf install -y "$temp_rpm_path"; then
                    echo "LocalWP installation successful."
                else
                    echo "Error: Failed to install LocalWP from RPM."
                fi
                rm -f "$temp_rpm_path" # Clean up downloaded RPM
            else
                echo "Error: Failed to download LocalWP RPM."
            fi
        else
            echo "LocalWP already installed."
        fi

    else
        echo "Skipping additional software installation."
    fi
}

# --- VSCode Installation ---
install_vscode() {
    if confirm "Install Visual Studio Code? [y/N]"; then
        if ! command_exists code; then
            echo "Installing Visual Studio Code..."
            # Import Microsoft GPG key
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            # Add VSCode repository
            sudo sh -c 'echo -e "[code]\\nname=Visual Studio Code\\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\\nenabled=1\\ngpgcheck=1\\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
            # Update dnf cache and install
            echo "Updating DNF cache after adding VSCode repository..."
            if sudo dnf check-update; then
                echo "DNF cache updated successfully."
            else
                echo "Warning: 'sudo dnf check-update' failed or returned an error. VSCode installation might fail or install an older version."
            fi
            sudo dnf install -y code
            echo "Visual Studio Code installation attempted."
        else
            echo "Visual Studio Code already installed."
        fi
    else
        echo "Skipping Visual Studio Code installation."
    fi
}

# --- Windsurf Installation ---
install_windsurf() {
    if confirm "Install Windsurf? [y/N]"; then
        echo "Installing Windsurf..."
        if curl -fsSL https://raw.githubusercontent.com/EstebanForge/windsurf-installer-linux/main/install-windsurf.sh | bash; then
            echo "Windsurf installation script executed."
        else
            echo "Windsurf installation script failed to execute."
        fi
    else
        echo "Skipping Windsurf installation."
    fi
}

# --- System Utilities and Tools ---
install_system_utilities() {
    if confirm "Install system utilities (Flameshot, keyd, Ulauncher, lolcate, libinput-config, Python pip packages)? [y/N]"; then
        # Flameshot
        if ! command_exists flameshot; then
            sudo dnf install -y flameshot
            echo "Flameshot installed. Configure shortcuts manually in GNOME Settings. Suggested command for Wayland: sh -c -- \"QT_QPA_PLATFORM=wayland flameshot gui > /dev/null\""
        else
            echo "Flameshot already installed."
        fi

        # keyd (Hyperkey)
        echo "Setting up keyd for Hyperkey..."
        if ! command_exists keyd; then
            echo "keyd not found. Attempting to install via COPR repository alternateved/keyd..."
            # Check if 'dnf copr' functionality is available
            if command_exists dnf && dnf help copr >/dev/null 2>&1; then
                # Enable COPR repository if not already enabled
                if ! sudo dnf copr list | grep -q "alternateved/keyd"; then # Check if repo is enabled
                    echo "Enabling COPR repository alternateved/keyd..."
                    if ! sudo dnf copr enable -y alternateved/keyd; then
                        echo "Error: Failed to enable COPR repository alternateved/keyd. keyd installation might fail."
                    else
                        echo "COPR repository alternateved/keyd enabled successfully."
                    fi
                else
                    echo "COPR repository alternateved/keyd already enabled."
                fi
            else
                echo "Warning: 'dnf copr' command not available or 'copr' subcommand not found. Cannot manage COPR repo for keyd. Installation might fail if keyd is not in standard repos."
            fi

            echo "Installing keyd package..."
            if ! sudo dnf install -y keyd; then
                echo "Error: Failed to install keyd. Skipping Hyperkey setup."
            else
                echo "keyd installed successfully."
            fi
        else
            echo "keyd is already installed."
        fi

        # Proceed with configuration if keyd command is now available
        if command_exists keyd; then
            echo "keyd found. Proceeding with Hyperkey configuration..."
            KEYD_CONFIG_FILE="/etc/keyd/default.conf"
            CONFIG_JUST_CREATED=false
            if [ ! -f "$KEYD_CONFIG_FILE" ]; then
                echo "Creating keyd configuration file $KEYD_CONFIG_FILE for Hyperkey..."
                sudo mkdir -p "$(dirname "$KEYD_CONFIG_FILE")"
                sudo tee "$KEYD_CONFIG_FILE" <<'EOF' >/dev/null
[ids]
*

[main]
capslock = overload(capslock_layer, esc)

[capslock_layer:C-S-A-M]
h = left
j = down
k = up
l = right
EOF
                echo "keyd configuration file created."
                CONFIG_JUST_CREATED=true
            else
                echo "keyd configuration file $KEYD_CONFIG_FILE already exists."
            fi

            # Ensure keyd service is enabled and active
            if ! sudo systemctl is-enabled --quiet keyd; then
                echo "Enabling keyd service..."
                sudo systemctl enable keyd
            else
                echo "keyd service already enabled."
            fi

            if ! sudo systemctl is-active --quiet keyd; then
                echo "Starting keyd service..."
                sudo systemctl start keyd
            elif [ "$CONFIG_JUST_CREATED" = true ]; then
                echo "Restarting keyd service to apply newly created configuration..."
                sudo systemctl restart keyd
            else
                echo "keyd service already active."
            fi
            echo "keyd service status verified/updated."

            # Ensure keyd is enabled and started as per user request
            echo "Ensuring keyd is enabled and started (post-check)..."
            sudo systemctl enable keyd
            sudo systemctl start keyd
            echo "keyd enable and start commands executed (post-check)."
        else
            echo "keyd command not found even after installation attempt. Skipping Hyperkey setup."
        fi

        # Ulauncher
        if ! command_exists ulauncher; then
            echo "Installing Ulauncher..."
            sudo dnf install -y ulauncher
            echo "Ulauncher installation attempted."
            echo "You may still want to install Ulauncher extensions and their Python dependencies separately if needed."
        else
            echo "Ulauncher already installed."
        fi

        # Python Pip Packages (for Ulauncher extensions or general use)
        echo "Installing Python packages (Pint, simpleeval, parsedatetime, pytz, babel, lorem, deepl) via pip..."
        if python -m pip install Pint simpleeval parsedatetime pytz babel lorem deepl; then
            echo "Python pip packages installed successfully."
        else
            echo "Failed to install some Python pip packages. Please check for errors."
        fi

        # lolcate (File Indexer)
        # Based on instructions from Linux 2024 Configuration Fedora.md
        echo "Setting up lolcate file indexer..."
        LOLCATE_USER_BIN_PATH="$HOME/.local/bin/lolcate"
        LOLCATE_SYMLINK_PATH="/usr/bin/lolcate" # As per markdown
        LOLCATE_CONFIG_DIR="$HOME/.config/lolcate/default"

        # Check if lolcate is installed in user's local bin or symlinked and accessible via command_exists
        if ! command_exists lolcate && [ ! -f "$LOLCATE_USER_BIN_PATH" ]; then
            echo "lolcate not found. Attempting to install..."
            mkdir -p "$HOME/.local/bin"
            LOLCATE_DOWNLOAD_URL="https://github.com/ngirard/lolcate-rs/releases/download/v0.10.0/lolcate--x86_64-unknown-linux-musl.tar.gz"

            echo "Downloading lolcate from $LOLCATE_DOWNLOAD_URL..."
            if wget -qO- "$LOLCATE_DOWNLOAD_URL" | tar xz -C "$HOME/.local/bin" lolcate; then # Extracts 'lolcate' member directly
                if [ -f "$LOLCATE_USER_BIN_PATH" ]; then
                    chmod +x "$LOLCATE_USER_BIN_PATH"
                    echo "lolcate downloaded and extracted to $LOLCATE_USER_BIN_PATH."
                else
                    echo "Error: lolcate binary not found in $HOME/.local/bin after attempted extraction."
                fi
            else
                echo "Error: Failed to download or extract lolcate."
            fi
        elif [ -f "$LOLCATE_USER_BIN_PATH" ]; then
            echo "lolcate found at $LOLCATE_USER_BIN_PATH."
        else
            echo "lolcate seems to be installed (command_exists returned true)."
        fi

        # Ensure symlink exists if lolcate is in user's bin but not found by command_exists initially, or just to be sure
        if [ -f "$LOLCATE_USER_BIN_PATH" ]; then
            if [ ! -L "$LOLCATE_SYMLINK_PATH" ] && [ ! -f "$LOLCATE_SYMLINK_PATH" ]; then
                echo "Creating symlink $LOLCATE_SYMLINK_PATH..."
                if sudo ln -s "$LOLCATE_USER_BIN_PATH" "$LOLCATE_SYMLINK_PATH"; then
                    echo "Symlink $LOLCATE_SYMLINK_PATH created."
                else
                    echo "Error: Failed to create symlink $LOLCATE_SYMLINK_PATH."
                fi
            elif [ -L "$LOLCATE_SYMLINK_PATH" ]; then
                # Verify existing symlink points to the right place if we manage $LOLCATE_USER_BIN_PATH
                if [ "$(readlink -f "$LOLCATE_SYMLINK_PATH")" != "$LOLCATE_USER_BIN_PATH" ]; then
                    echo "Warning: $LOLCATE_SYMLINK_PATH exists but points elsewhere. Consider removing it and re-running."
                else
                    echo "Symlink $LOLCATE_SYMLINK_PATH already exists and points correctly."
                fi
            elif [ -f "$LOLCATE_SYMLINK_PATH" ]; then
                echo "Warning: $LOLCATE_SYMLINK_PATH exists but is not a symlink. Manual intervention may be needed."
            fi
        fi

        # Run lolcate --create and --update if lolcate command is available
        if command_exists lolcate; then
            echo "Ensuring lolcate configuration directory exists: $LOLCATE_CONFIG_DIR"
            mkdir -p "$LOLCATE_CONFIG_DIR"
            echo "Note: lolcate --create might require specific configuration in $LOLCATE_CONFIG_DIR/config.toml and $LOLCATE_CONFIG_DIR/ignores."
            echo "Please ensure these are set up as per your requirements (see Linux 2024 Configuration Fedora.md)."

            echo "Attempting to create lolcate index (lolcate --create)..."
            if lolcate --create; then
                echo "lolcate --create command executed successfully."
            else
                echo "Warning: lolcate --create command failed or returned an error. This might be due to missing or default configuration."
            fi

            echo "Attempting to update lolcate index (lolcate --update)..."
            if lolcate --update; then
                echo "lolcate --update command executed successfully."
            else
                echo "Warning: lolcate --update command failed or returned an error."
            fi
        else
            echo "Error: lolcate command not found even after installation attempt. Skipping index creation and update."
        fi

        # libinput-config (Mouse scroll with button)
        echo "Setting up libinput-config for mouse scroll customization..."
        if ! command_exists libinput-config; then                                  # Crude check, real check is if binary is in PATH
            sudo dnf install -y libinput-devel libudev-devel meson ninja-build git # evtest already in common packages
            TEMP_DIR=$(mktemp -d)
            git clone https://gitlab.com/warningnonpotablewater/libinput-config.git "$TEMP_DIR/libinput-config"
            cd "$TEMP_DIR/libinput-config" || exit 1
            meson build
            cd build || exit 1
            ninja
            sudo ninja install
            cd "$HOME" # Go back home
            rm -rf "$TEMP_DIR"
            echo "libinput-config installed."
        else
            echo "libinput-config seems to be installed or build dependencies missing for check."
        fi
        # Create default config if not exists
        if [ ! -f /etc/libinput.conf ]; then
            sudo tee /etc/libinput.conf <<'EOF' >/dev/null
# /etc/libinput.conf
# Configuration for libinput-config

# Enable this to override your desktop environment's scroll settings
override-compositor=enabled

# Set the scroll method to 'on-button-down' to enable scrolling
# while a specific button is held down.
# Other options include: 'two-finger', 'edge', 'none'
scroll-method=on-button-down

# Set the button to trigger scrolling.
# Event code 273 typically corresponds to the secondary (right) mouse button.
scroll-button=273

# Set to 'enabled' if you want the scroll button to toggle scrolling
# on and off with each click, rather than requiring you to hold it down.
# 'disabled' means you must hold the button to scroll.
scroll-button-lock=disabled

# --- Optional Settings ---

# Speed adjustment for scrolling. Default is 1.0.
# Higher values mean faster scrolling, lower values mean slower.
scroll-factor=1.2

# Enable or disable natural scrolling (inverted scrolling).
# natural-scroll=enabled

# Left-handed mode (swaps primary and secondary buttons).
# left-handed=disabled

# Tapping for touchpads.
# tap-to-click=disabled

# Disable while typing for touchpads.
disable-while-typing=enabled
EOF
            echo "Created default /etc/libinput.conf. You may need to reboot or restart your session."
            echo "Verify scroll-button event code with 'sudo evtest'."
        else
            echo "/etc/libinput.conf already exists. Review its settings."
        fi
    else
        echo "Skipping system utilities installation."
    fi
}

# --- Grub and System Tweaks ---
setup_grub_tweaks() {
    if confirm "Apply Grub tweaks (timeout)? [y/N]"; then
        # Grub timeout
        if grep -q "GRUB_TIMEOUT=" /etc/default/grub; then
            sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
        else
            echo "GRUB_TIMEOUT=3" | sudo tee -a /etc/default/grub >/dev/null
        fi
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        echo "Grub timeout set to 3 seconds."
    else
        echo "Skipping Grub tweaks."
    fi
}

# --- Configure Sudo Secure Path ---
configure_sudo_secure_path() {
    echo "Configuring sudo secure_path for Homebrew"

    local custom_sudoers_file="/etc/sudoers.d/99-dotfiles-brew-securepath"
    # Define standard paths, explicitly excluding Snap path
    local standard_paths="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    local brew_path="/home/linuxbrew/.linuxbrew/bin" # Assuming this is the correct path for your Homebrew installation

    # Construct the desired secure_path value
    # This ensures brew_path is included and attempts a simple deduplication
    local desired_secure_path_value
    if [[ ":${standard_paths}:" == *":${brew_path}:"* ]]; then # Check if brew_path is already in standard_paths
        desired_secure_path_value="${standard_paths}"
    else
        desired_secure_path_value="${standard_paths}:${brew_path}"
    fi
    # Simple deduplication: split by ':', get unique lines, then join back with ':'
    desired_secure_path_value=$(echo "${desired_secure_path_value}" | tr ':' '\n' | awk '!seen[$0]++' | paste -sd':')

    local desired_secure_path_line="Defaults    secure_path = ${desired_secure_path_value}"

    local file_content="# This file is automatically generated by the dotfiles post_install_setup.sh script.\n"
    file_content+="# It defines sudo's secure_path to include Homebrew and standard system paths.\n"
    file_content+="# This file will effectively set the secure_path; other definitions might be overridden.\n"
    file_content+="${desired_secure_path_line}"

    # Check if the file exists and already contains the exact desired line
    if [ -f "$custom_sudoers_file" ] && sudo grep -Fxq "$desired_secure_path_line" "$custom_sudoers_file"; then
        echo "Sudo secure_path already correctly configured in $custom_sudoers_file."
    else
        echo "Creating/Updating $custom_sudoers_file for sudo secure_path..."
        local temp_file
        temp_file=$(mktemp)
        if [ -z "$temp_file" ]; then
            echo "Failed to create a temporary file. Sudo secure_path not configured."
            return 1
        fi

        echo -e "${file_content}" >"$temp_file"

        # Copy, set permissions, and set ownership
        if sudo cp "$temp_file" "$custom_sudoers_file" && sudo chmod 0440 "$custom_sudoers_file" && sudo chown root:root "$custom_sudoers_file"; then
            echo "Successfully configured sudo secure_path in $custom_sudoers_file."
            echo "IMPORTANT: Please verify sudo functionality (e.g., by running 'sudo ls')."
            echo "If sudo is broken, you might need to boot into recovery mode to remove or fix $custom_sudoers_file."
        else
            echo "Failed to write, set permissions, or set ownership for $custom_sudoers_file. Sudo secure_path not configured."
            # Attempt to clean up if the custom file was created but something went wrong
            if sudo test -f "$custom_sudoers_file"; then # Check with sudo as we might not have perms
                echo "Attempting to remove potentially problematic $custom_sudoers_file..."
                sudo rm -f "$custom_sudoers_file"
            fi
            rm -f "$temp_file" # Clean up temp file regardless
            return 1
        fi
        rm -f "$temp_file" # Clean up temp file on success
    fi
    echo "Sudo secure_path configuration completed."
}

# --- Restore GNOME Settings ---
restore_gnome_settings() {
    echo "--- Restoring GNOME Settings ---"
    if [ -f "$GENERATED_DATA_DIR/gnome-settings.dconf" ]; then
        if confirm "Restore GNOME settings from $GENERATED_DATA_DIR/gnome-settings.dconf? (This will overwrite current settings) [y/N]"; then
            echo "Restoring GNOME settings..."
            dconf load / <"$GENERATED_DATA_DIR/gnome-settings.dconf"
            echo "GNOME settings restored."
        else
            echo "Skipping GNOME settings restore."
        fi
    else
        echo "$GENERATED_DATA_DIR/gnome-settings.dconf not found. Skipping GNOME settings restore."
    fi
}

# --- Finalization ---
finalize_setup() {
    echo -e "\n---------------------------------------------------------------------"
    echo "Post-installation setup script finished."
    echo "Please review the output above for any manual steps, errors, or further instructions."
    echo "Some changes (like default shell, environment variables, services) may require a logout/login or a full system reboot to take effect."
    echo "Remember to configure applications like Ulauncher, Flameshot shortcuts, etc., to your liking."
    echo "---------------------------------------------------------------------"

    # AppImage Reminder
    if [ -f "$GENERATED_DATA_DIR/appimage_list.txt" ] && [ -s "$GENERATED_DATA_DIR/appimage_list.txt" ]; then
        echo -e "\n---------------------------------------------------------------------"
        echo "AppImage Restore Reminder:"
        echo "The following AppImages were previously backed up (list in $GENERATED_DATA_DIR/appimage_list.txt):"
        cat "$GENERATED_DATA_DIR/appimage_list.txt"
        echo "Ensure these are restored to ~/Applications/ (or your preferred location) and made executable (chmod +x)."
        echo "If you used PikaBackup for your home directory, they might already be restored."
        echo "---------------------------------------------------------------------"
    fi

    # Reminder for other configurations
    echo -e "\n---------------------------------------------------------------------"
    echo "Remember to also:"
    echo "  - Restore your entire home directory from PikaBackup if you haven't already, especially for files not managed by these dotfiles (if applicable)."
    echo "  - Source your shell configuration (e.g., source ~/.zshrc or source ~/.bashrc) or restart your terminal for changes to take effect."
    echo "---------------------------------------------------------------------"
}

# --- Main execution flow ---
rsync_source_home_to_user_home # Call the new rsync function first
setup_rpm_fusion
install_common_dnf_packages
restore_flatpak_packages # Call the new function
setup_flatpak_overrides  # Add call to the new function
install_homebrew
install_brew_packages # Depends on Homebrew
setup_ssh_permissions
setup_zsh # Installs Zsh, OhMyZsh, plugins
setup_docker
setup_gnome_settings
setup_font_rendering
setup_crypto_policies
setup_amd_pstates_and_s2idle_grub_args # Call the new function
setup_system_environment
install_additional_software
install_vscode           # Call the new function to install VSCode
install_windsurf         # Call the new function to install Windsurf
install_system_utilities # Installs Flameshot, keyd, Ulauncher helpers, libinput-config
setup_grub_tweaks
configure_sudo_secure_path
restore_gnome_settings # Call the new function to restore GNOME settings

finalize_setup

exit 0
