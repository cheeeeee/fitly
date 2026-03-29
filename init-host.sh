#!/bin/sh

echo "=== Fitly Host Optimizer ==="

# Get total RAM in MB (works on Alpine/BusyBox and standard Linux)
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "Detected RAM: ${TOTAL_MEM}MB"

# If RAM is less than 1500MB, apply aggressive SD card protections
if [ "$TOTAL_MEM" -lt 1500 ]; then
    echo "Low memory edge device detected. Applying kernel I/O trickle-writes..."
    
    # Safely append to sysctl.conf if the rules don't already exist
    grep -q "vm.dirty_background_ratio" /etc/sysctl.conf || echo "vm.dirty_background_ratio = 2" | sudo tee -a /etc/sysctl.conf
    grep -q "vm.dirty_ratio" /etc/sysctl.conf || echo "vm.dirty_ratio = 5" | sudo tee -a /etc/sysctl.conf
    
    # Apply immediately
    sudo sysctl -p
    echo "Host I/O tuned for SD card safety."
else
    echo "Sufficient RAM detected. Using default kernel I/O limits."
fi