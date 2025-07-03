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

echo "=========================================="
echo "TPM2 LUKS enroll"
echo "=========================================="
echo "" >&2
echo "WARNING: This script (luks-enroll-tpm2.sh) is provided AS IS, with NO WARRANTY and NO GUARANTEE of fitness for any particular purpose." >&2
echo "It is intended for advanced users. Use at your own risk. Always back up your data before proceeding!" >&2
echo ""

# Check if SecureBoot is enabled - required for TPM2 LUKS integration
check_secureboot_status() {
  echo "Checking SecureBoot status..."

  if ! command -v mokutil &>/dev/null; then
    echo "Error: mokutil command not found. Please install mokutil package."
    exit 1
  fi

  local sb_status
  sb_status=$(mokutil --sb-state 2>/dev/null)

  if [[ "$sb_status" != "SecureBoot enabled" ]]; then
    echo "Warning: SecureBoot is not enabled."
    echo "Current status: $sb_status"
    echo "This script requires SecureBoot to be enabled for TPM2 LUKS integration."
    echo "Please enable SecureBoot in your BIOS/UEFI settings and try again."
    exit 1
  fi

  echo "SecureBoot is enabled. Proceeding..."
}

# Get TPM2 device path from systemd-cryptenroll
get_tpm2_device_path() {
  echo "Detecting TPM2 device..." >&2

  if ! command -v systemd-cryptenroll &>/dev/null; then
    echo "Error: systemd-cryptenroll command not found. Please install systemd package." >&2
    exit 1
  fi

  local tpm2_output
  tpm2_output=$(systemd-cryptenroll --tpm2-device=list 2>/dev/null)

  if [[ -z "$tpm2_output" ]]; then
    echo "Error: Failed to get TPM2 device list." >&2
    exit 1
  fi

  # Extract the device path from the first data line (skip header)
  local device_path
  device_path=$(echo "$tpm2_output" | awk 'NR==2 {print $1}')

  if [[ -z "$device_path" || ! -e "$device_path" ]]; then
    echo "Error: No valid TPM2 device found or device not accessible." >&2
    echo "TPM2 output:" >&2
    echo "$tpm2_output" >&2
    exit 1
  fi

  echo "Found TPM2 device: $device_path" >&2
  echo "$device_path"
}

# Get the parent partition of the LUKS encrypted device
get_luks_partition() {
  echo "Detecting LUKS encrypted partition..." >&2

  if ! command -v lsblk &>/dev/null; then
    echo "Error: lsblk command not found. Please install util-linux package." >&2
    exit 1
  fi

  local lsblk_output
  lsblk_output=$(lsblk -o NAME,TYPE 2>/dev/null)

  if [[ -z "$lsblk_output" ]]; then
    echo "Error: Failed to get block device list." >&2
    exit 1
  fi

  # Find the crypt device and get its parent partition
  local crypt_device parent_partition
  crypt_device=$(echo "$lsblk_output" | awk '$2=="crypt" {print $1}' | head -1)

  if [[ -z "$crypt_device" ]]; then
    echo "Error: No LUKS encrypted device found." >&2
    echo "lsblk output:" >&2
    echo "$lsblk_output" >&2
    exit 1
  fi

  # Get the parent partition by looking for the partition that has the crypt device as child
  # We need to find the line above the crypt device that represents its parent
  parent_partition=$(echo "$lsblk_output" | awk -v crypt="$crypt_device" '
    {
      if ($1 == crypt && $2 == "crypt") {
        print prev_partition
        exit
      }
      if ($2 == "part") {
        prev_partition = $1
        # Remove tree characters (├─, └─, etc.)
        gsub(/[├└─│]/, "", prev_partition)
      }
    }
  ')

  if [[ -z "$parent_partition" ]]; then
    echo "Error: Could not determine parent partition of LUKS device." >&2
    echo "Crypt device found: $crypt_device" >&2
    exit 1
  fi

  echo "Found LUKS parent partition: $parent_partition" >&2
  echo "$parent_partition"
}

# Enroll TPM2 device with LUKS partition
enroll_tpm2_luks() {
  local tpm_device="$1"
  local luks_partition="$2"

  echo "Preparing to enroll TPM2 device with LUKS partition..."
  echo ""
  echo "TPM2 Device: $tpm_device"
  echo "LUKS Partition: $luks_partition"
  echo ""

  # Construct the full device path
  local device_path="/dev/$luks_partition"

  # Show the command that will be executed
  echo "The following command will be executed:"
  echo ""
  echo "sudo systemd-cryptenroll \\"
  echo "    --wipe-slot tpm2 \\"
  echo "    --tpm2-device $tpm_device \\"
  echo "    $device_path"
  echo ""

  # Ask for user confirmation
  read -p "Do you want to proceed with TPM2 enrollment? (y/N): " -n 1 -r
  echo "" # Add newline after input

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "TPM2 enrollment cancelled by user."
    exit 0
  fi

  echo "Proceeding with TPM2 enrollment..."

  # Execute the command
  if sudo systemd-cryptenroll \
    --wipe-slot tpm2 \
    --tpm2-device "$tpm_device" \
    "$device_path"; then
    echo "TPM2 enrollment completed successfully!"
  else
    echo "Error: TPM2 enrollment failed."
    exit 1
  fi
}

# Verify TPM2 enrollment status
verify_tpm2_enrollment() {
  local luks_partition="$1"
  local device_path="/dev/$luks_partition"

  echo ""
  echo "Verifying TPM2 enrollment status..."
  echo "Running: sudo systemd-cryptenroll $device_path"
  echo ""

  if sudo systemd-cryptenroll "$device_path"; then
    echo ""
    echo "TPM2 enrollment verification completed."
  else
    echo "Warning: Could not verify enrollment status."
  fi
}

# Update GRUB kernel arguments for TPM2 LUKS support
update_grub_tpm2_args() {
  local tpm_device="$1"

  echo ""
  echo "Preparing to update GRUB kernel arguments for TPM2 LUKS support..."
  echo ""
  echo "TPM2 Device: $tpm_device"
  echo ""

  # Show the commands that will be executed
  echo "The following commands will be executed:"
  echo ""
  echo "sudo grubby --update-kernel=ALL \\"
  echo "    --args=\"rd.luks.options=tpm2-device=$tpm_device\""
  echo ""
  echo "sudo grubby --info=DEFAULT"
  echo ""

  # Ask for user confirmation
  read -p "Do you want to proceed with GRUB kernel arguments update? (y/N): " -n 1 -r
  echo "" # Add newline after input

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "GRUB kernel arguments update cancelled by user."
    return 0
  fi

  echo "Proceeding with GRUB kernel arguments update..."

  # Execute the grubby update command
  if sudo grubby --update-kernel=ALL --args="rd.luks.options=tpm2-device=$tpm_device"; then
    echo "GRUB kernel arguments updated successfully!"
    echo ""
    echo "Verifying GRUB configuration..."
    echo "Running: sudo grubby --info=DEFAULT"
    echo ""

    # Show the current default kernel info for verification
    sudo grubby --info=DEFAULT

    echo ""
    echo "GRUB configuration update completed."
  else
    echo "Error: Failed to update GRUB kernel arguments."
    return 1
  fi
}

# Check and display crypttab configuration
check_crypttab_config() {
  echo ""
  echo "Checking /etc/crypttab configuration..."
  echo "Running: sudo cat /etc/crypttab"
  echo ""

  if [ -f "/etc/crypttab" ]; then
    if sudo cat /etc/crypttab; then
      echo ""
      echo "Crypttab configuration displayed successfully."
    else
      echo "Warning: Could not read /etc/crypttab configuration."
    fi
  else
    echo "Warning: /etc/crypttab file not found."
  fi

  echo ""
  echo "Note: This shows how encrypted partitions are configured for boot-time unlocking."
}

# Configure dracut for TPM2 and regenerate boot configurations
configure_dracut_tpm2() {
  echo ""
  echo "Preparing to configure dracut for TPM2 support and regenerate boot configurations..."
  echo ""

  # Show the commands that will be executed
  echo "The following commands will be executed:"
  echo ""
  echo "echo 'add_dracutmodules+=\" tpm2-tss \"' | sudo tee /etc/dracut.conf.d/tpm2.conf"
  echo ""
  echo "sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
  echo ""
  echo "sudo dracut -vf"
  echo ""

  # Ask for user confirmation
  read -p "Do you want to proceed with dracut TPM2 configuration and boot regeneration? (y/N): " -n 1 -r
  echo "" # Add newline after input

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Dracut TPM2 configuration cancelled by user."
    return 0
  fi

  echo "Proceeding with dracut TPM2 configuration..."
  echo ""

  # Step 1: Configure dracut for TPM2
  echo "Step 1: Adding TPM2 module to dracut configuration..."
  if echo 'add_dracutmodules+=" tpm2-tss "' | sudo tee /etc/dracut.conf.d/tpm2.conf; then
    echo "TPM2 dracut configuration created successfully."
  else
    echo "Error: Failed to create TPM2 dracut configuration."
    return 1
  fi

  echo ""

  # Step 2: Regenerate GRUB configuration
  echo "Step 2: Regenerating GRUB configuration..."
  if sudo grub2-mkconfig -o /boot/grub2/grub.cfg; then
    echo "GRUB configuration regenerated successfully."
  else
    echo "Error: Failed to regenerate GRUB configuration."
    return 1
  fi

  echo ""

  # Step 3: Regenerate initramfs with dracut
  echo "Step 3: Regenerating initramfs with dracut (this may take a moment)..."
  if sudo dracut -vf; then
    echo "Initramfs regenerated successfully with TPM2 support."
  else
    echo "Error: Failed to regenerate initramfs."
    return 1
  fi

  echo ""
  echo "Dracut TPM2 configuration and boot regeneration completed successfully!"
}

# Main execution
main() {
  check_secureboot_status

  # Get TPM2 device path
  TPM2_DEVICE=$(get_tpm2_device_path)

  # Get LUKS partition
  LUKS_PARTITION=$(get_luks_partition)

  # Enroll TPM2 with LUKS
  enroll_tpm2_luks "$TPM2_DEVICE" "$LUKS_PARTITION"

  # Verify the enrollment
  verify_tpm2_enrollment "$LUKS_PARTITION"

  # Update GRUB kernel arguments
  update_grub_tpm2_args "$TPM2_DEVICE"

  # Check crypttab configuration
  check_crypttab_config

  # Configure dracut for TPM2 and regenerate boot configs
  configure_dracut_tpm2

  echo ""
  echo "=========================================="
  echo "TPM2 LUKS setup completed successfully!"
  echo "=========================================="
  echo ""
  echo "What was accomplished:"
  echo "✓ SecureBoot status verified"
  echo "✓ TPM2 device detected and enrolled"
  echo "✓ LUKS partition configured for TPM2 unlock"
  echo "✓ GRUB kernel arguments updated"
  echo "✓ Dracut configured for TPM2 support"
  echo "✓ Boot configurations regenerated"
  echo ""
  echo "IMPORTANT: Please reboot your system to test automatic TPM2-based disk unlocking."
  echo "After reboot, your system should unlock the encrypted disk automatically without prompting for a password."
}

# Run main function
main "$@"
