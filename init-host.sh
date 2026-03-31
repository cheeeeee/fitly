#!/bin/sh

echo "=== Fitly Host Optimizer & Pre-Flight Check ==="

# ---------------------------------------------------------
# PHASE 1: HARDWARE MEMORY & SD CARD I/O TUNING
# ---------------------------------------------------------
# Get total RAM in MB (works natively on Alpine/BusyBox)
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "Detected RAM: ${TOTAL_MEM}MB"

if [ "$TOTAL_MEM" -lt 1500 ]; then
    echo "[+] Low memory edge device detected. Applying kernel I/O trickle-writes..."
    
    # Safely append to sysctl.conf if the rules don't already exist
    grep -q "vm.dirty_background_ratio" /etc/sysctl.conf || echo "vm.dirty_background_ratio = 2" | sudo tee -a /etc/sysctl.conf
    grep -q "vm.dirty_ratio" /etc/sysctl.conf || echo "vm.dirty_ratio = 5" | sudo tee -a /etc/sysctl.conf
    
    # Apply immediately silently
    sudo sysctl -p > /dev/null 2>&1
    echo "    -> Host I/O tuned for SD card safety."
else
    echo "[+] Sufficient RAM detected. Using default kernel I/O limits."
fi

# ---------------------------------------------------------
# PHASE 2: DOCKER CGROUP MEMORY FENCE VALIDATION
# ---------------------------------------------------------
echo -e "\n=== Checking Kernel Cgroup Limits ==="

# Check if the memory cgroup exists and is enabled (value '1' in column 4)
if [ -f /proc/cgroups ] && awk '$1=="memory" {print $4}' /proc/cgroups | grep -q "1"; then
    echo "[+] Memory cgroups are enabled. Docker memory fencing will work correctly."
else
    echo "[!] WARNING: Memory cgroups are DISABLED in the host kernel."
    echo "    Docker cannot enforce memory limits, risking an Out-Of-Memory system freeze."
    
    # Attempt to auto-locate the Pi bootloader config
    echo "    -> Attempting to auto-patch Raspberry Pi boot configuration..."
    CMDLINE_FILE=$(find /media /boot -name "cmdline.txt" 2>/dev/null | head -n 1)
    
    if [ -n "$CMDLINE_FILE" ] && [ -f "$CMDLINE_FILE" ]; then
        echo "    -> Found boot configuration at: $CMDLINE_FILE"
        
        # Check if we already patched it previously
        if grep -q "cgroup_memory" "$CMDLINE_FILE"; then
            echo "    -> Cgroup flags are already present. A system reboot is pending."
        else
            echo "    -> Injecting cgroup flags into $CMDLINE_FILE..."
            # Safely append to the exact end of the single line
            sudo sed -i 's/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE_FILE"
            echo "    -> PATCH SUCCESSFUL. You MUST reboot this device for changes to take effect."
        fi
    else
        echo "[!] COULD NOT AUTO-LOCATE cmdline.txt!"
        echo "    You must manually add 'cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory'"
        echo "    to your Pi's cmdline.txt file and reboot before running Docker."
    fi
fi

echo -e "\n=== Pre-Flight Complete ==="