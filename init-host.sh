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
# =============================================================================
# init-host.sh — Fitly Host Optimizer, Pre-Flight Check & Config Generator
# =============================================================================
# Run this script once on a new host before starting Fitly.
# It will:
#   1. Detect your hardware (RAM, CPU, storage type)
#   2. Tune kernel I/O settings for your storage (if needed)
#   3. Validate Docker memory cgroups (Raspberry Pi)
#   4. Generate a ready-to-use config.yaml in ./config/
#
# Usage:
#   chmod +x init-host.sh
#   ./init-host.sh
#
# To skip interactive prompts and generate only the config:
#   ./init-host.sh --config-only
# =============================================================================

CONFIG_ONLY=0
if [ "$1" = "--config-only" ]; then
    CONFIG_ONLY=1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Fitly Host Optimizer & Config Generator              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# HELPER UTILITIES
# =============================================================================

_has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Prompt with a default value; echoes the user's input (or default)
# Usage: result=$(_prompt "Question" "default_value")
_prompt() {
    _msg="$1"
    _default="$2"
    printf "  %s [%s]: " "$_msg" "$_default"
    read -r _input
    echo "${_input:-$_default}"
}

# Yes/no prompt; returns 0=yes 1=no
# Usage: if _confirm "Enable cron?"; then ...
_confirm() {
    printf "  %s (y/N): " "$1"
    read -r _yn
    case "$_yn" in [yY]*) return 0;; *) return 1;; esac
}

# =============================================================================
# PHASE 1: HARDWARE DETECTION
# =============================================================================
echo "─── Phase 1: Hardware Detection ───────────────────────────────"

# RAM
TOTAL_MEM=0
if _has_cmd free; then
    TOTAL_MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
fi
TOTAL_MEM=${TOTAL_MEM:-0}
echo "  RAM:        ${TOTAL_MEM} MB"

# CPU cores (logical)
CPU_COUNT=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
echo "  CPU cores:  ${CPU_COUNT}"

# Physical vs logical (detect hyperthreading)
PHYSICAL_CORES=$CPU_COUNT
if _has_cmd python3; then
    _phys=$(python3 -c "import os; print(len(os.sched_getaffinity(0)))" 2>/dev/null)
    [ -n "$_phys" ] && PHYSICAL_CORES="$_phys"
fi
HAS_HT=0
[ "$CPU_COUNT" -gt "$PHYSICAL_CORES" ] && HAS_HT=1

# Storage type detection — look at the disk backing ./config or /
IS_SSD=0
STORAGE_TYPE="unknown"
_dev=""
if _has_cmd df && _has_cmd lsblk; then
    _dev=$(df . 2>/dev/null | tail -1 | awk '{print $1}' | sed 's|/dev/||;s|[0-9]*$||;s|p[0-9]*$||')
    if [ -n "$_dev" ]; then
        _rotational=$(cat "/sys/block/${_dev}/queue/rotational" 2>/dev/null)
        case "$_rotational" in
            0) IS_SSD=1; STORAGE_TYPE="SSD/NVMe" ;;
            1) STORAGE_TYPE="HDD/SD card" ;;
        esac
    fi
fi
# Fallback: if on a Pi and no HDD detected, assume SD card
if [ "$STORAGE_TYPE" = "unknown" ] && [ -f /proc/device-tree/model ]; then
    grep -qi "raspberry" /proc/device-tree/model 2>/dev/null && STORAGE_TYPE="SD card (Raspberry Pi)"
fi
[ "$STORAGE_TYPE" = "unknown" ] && STORAGE_TYPE="unknown (assuming HDD/SD)"
echo "  Storage:    ${STORAGE_TYPE}"

# Is this a Pi?
IS_PI=0
if [ -f /proc/device-tree/model ] && grep -qi "raspberry" /proc/device-tree/model 2>/dev/null; then
    IS_PI=1
    echo "  Platform:   Raspberry Pi"
else
    echo "  Platform:   Generic Linux"
fi

# =============================================================================
# Derive sensible defaults from hardware
# =============================================================================

# Gunicorn workers
if [ "$HAS_HT" -eq 1 ]; then
    RECOMMENDED_WORKERS=$(( (2 * PHYSICAL_CORES) + 1 ))
else
    RECOMMENDED_WORKERS=$(( PHYSICAL_CORES + 1 ))
fi
# Cap at available CPUs minus 1 for OS headroom, min 2
AVAILABLE_CPUS=$(( CPU_COUNT - 1 ))
[ "$AVAILABLE_CPUS" -lt 1 ] && AVAILABLE_CPUS=1
[ "$RECOMMENDED_WORKERS" -gt "$AVAILABLE_CPUS" ] && RECOMMENDED_WORKERS=$AVAILABLE_CPUS
[ "$RECOMMENDED_WORKERS" -lt 2 ] && RECOMMENDED_WORKERS=2

# Datapull pool workers (half of logical CPUs, min 1)
POOL_WORKERS=$(( CPU_COUNT / 2 ))
[ "$POOL_WORKERS" -lt 1 ] && POOL_WORKERS=1

# SQLite cache (use ~25% of RAM, capped at 256MB, min 32MB)
CACHE_MB=$(( TOTAL_MEM / 4 ))
[ "$CACHE_MB" -lt 32 ]  && CACHE_MB=32
[ "$CACHE_MB" -gt 256 ] && CACHE_MB=256

# mmap: same as cache on SSD, 0 on SD (mmap on SD card can hurt performance)
if [ "$IS_SSD" -eq 1 ]; then
    MMAP_MB=$CACHE_MB
else
    MMAP_MB=0
fi

# serialize_db_writes: true on SD/HDD, false on SSD
if [ "$IS_SSD" -eq 1 ]; then
    SERIALIZE_WRITES="false"
else
    SERIALIZE_WRITES="true"
fi

# WAL checkpoint: fewer checkpoints on SD to reduce write amplification
if [ "$IS_SSD" -eq 1 ]; then
    WAL_CHECKPOINT=2000
else
    WAL_CHECKPOINT=4000
fi

# Gunicorn timeout: longer on slow hardware
if [ "$IS_PI" -eq 1 ]; then
    SERVER_TIMEOUT=1800
else
    SERVER_TIMEOUT=1200
fi

echo ""
echo "  Recommended settings derived from hardware:"
echo "    gunicorn_workers:  ${RECOMMENDED_WORKERS}"
echo "    pool workers:      ${POOL_WORKERS}"
echo "    cache_size_mb:     ${CACHE_MB}"
echo "    serialize_writes:  ${SERIALIZE_WRITES}"
echo ""

# =============================================================================
# PHASE 2: KERNEL I/O TUNING (skip if --config-only)
# =============================================================================
if [ "$CONFIG_ONLY" -eq 0 ]; then
    echo "─── Phase 2: Kernel I/O Tuning ────────────────────────────────"

    if [ "$TOTAL_MEM" -gt 0 ] && [ "$TOTAL_MEM" -lt 1500 ]; then
        echo "  [+] Low-memory edge device. Applying SD card I/O trickle-write tuning..."
        grep -q "vm.dirty_background_ratio" /etc/sysctl.conf 2>/dev/null || \
            echo "vm.dirty_background_ratio = 2" | sudo tee -a /etc/sysctl.conf >/dev/null
        grep -q "vm.dirty_ratio" /etc/sysctl.conf 2>/dev/null || \
            echo "vm.dirty_ratio = 5" | sudo tee -a /etc/sysctl.conf >/dev/null
        sudo sysctl -p >/dev/null 2>&1
        echo "  [+] Host I/O tuned for SD card safety."
    else
        echo "  [+] Sufficient RAM detected. Default kernel I/O limits retained."
    fi

    # =============================================================================
    # PHASE 3: DOCKER CGROUP VALIDATION (Raspberry Pi)
    # =============================================================================
    echo ""
    echo "─── Phase 3: Docker cgroup Memory Fence ───────────────────────"

    if [ -f /proc/cgroups ] && awk '$1=="memory" {print $4}' /proc/cgroups 2>/dev/null | grep -q "1"; then
        echo "  [+] Memory cgroups are enabled. Docker memory fencing is operational."
    else
        echo "  [!] WARNING: Memory cgroups are DISABLED in the host kernel."
        echo "      Docker cannot enforce memory limits — risk of OOM system freeze."

        CMDLINE_FILE=$(find /media /boot -name "cmdline.txt" 2>/dev/null | head -n 1)
        if [ -n "$CMDLINE_FILE" ] && [ -f "$CMDLINE_FILE" ]; then
            echo "  [+] Found boot config at: $CMDLINE_FILE"
            if grep -q "cgroup_memory" "$CMDLINE_FILE"; then
                echo "  [+] cgroup flags already present. Reboot pending."
            else
                echo "  [+] Injecting cgroup flags into $CMDLINE_FILE..."
                sudo sed -i 's/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE_FILE"
                echo "  [+] PATCH APPLIED. Reboot required before running Docker."
            fi
        else
            echo "  [!] Could not auto-locate cmdline.txt."
            echo "      Manually add to your Pi's cmdline.txt (single line, space-separated):"
            echo "        cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
        fi
    fi
    echo ""
fi

# =============================================================================
# PHASE 4: CONFIG FILE GENERATION
# =============================================================================
echo "─── Phase 4: Config Generation ────────────────────────────────"

# Determine config directory (same dir as this script, or ./config)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG_DIR="${SCRIPT_DIR}/config"
mkdir -p "$CONFIG_DIR"

CONFIG_YAML="${CONFIG_DIR}/config.yaml"
CONFIG_INI="${CONFIG_DIR}/config.ini"

# Warn if a config already exists
if [ -f "$CONFIG_YAML" ]; then
    echo "  [!] ${CONFIG_YAML} already exists."
    if ! _confirm "Overwrite it?"; then
        echo "  [~] Skipping config generation. Existing file preserved."
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Pre-flight complete. Existing config preserved."
        echo "═══════════════════════════════════════════════════════════════"
        exit 0
    fi
fi

echo ""
echo "  We'll now collect values for your config."
echo "  Press Enter to accept the suggested default shown in [brackets]."
echo ""

# --- Strava (required) ---
echo "[ Strava ]"
STRAVA_CLIENT_ID=$(_prompt    "client_id"              "")
STRAVA_CLIENT_SECRET=$(_prompt "client_secret"          "")
STRAVA_AFTER_DATE=$(_prompt   "activities_after_date"  "2018-01-01T00:00:00Z")

# --- Oura ---
echo ""
echo "[ Oura Ring ] (leave blank to skip)"
OURA_CLIENT_ID=$(_prompt     "client_id"     "")
OURA_CLIENT_SECRET=$(_prompt "client_secret" "")
OURA_DAYS_BACK=$(_prompt     "days_back"     "7")

# --- Spotify ---
echo ""
echo "[ Spotify ] (leave blank to skip)"
SPOTIFY_CLIENT_ID=$(_prompt     "client_id"           "")
SPOTIFY_CLIENT_SECRET=$(_prompt "client_secret"        "")
SPOTIFY_REDIRECT=$(_prompt      "redirect_uri"         "")

# --- Peloton ---
echo ""
echo "[ Peloton ] (leave blank to skip)"
PELOTON_USER=$(_prompt "username" "")
PELOTON_PASS=$(_prompt "password" "")

# --- Withings ---
echo ""
echo "[ Withings ] (leave blank to skip)"
WITHINGS_CLIENT_ID=$(_prompt     "client_id"     "")
WITHINGS_CLIENT_SECRET=$(_prompt "client_secret" "")

# --- Stryd ---
echo ""
echo "[ Stryd ] (leave blank to skip)"
STRYD_USER=$(_prompt "username" "")
STRYD_PASS=$(_prompt "password" "")

# --- Nextcloud ---
echo ""
echo "[ Nextcloud / Fitbod ] (leave blank to skip)"
NC_URL=$(_prompt      "url"         "")
NC_USER=$(_prompt     "username"    "")
NC_PASS=$(_prompt     "password"    "")
NC_FITBOD=$(_prompt   "fitbod_path" "")

# --- General ---
echo ""
echo "[ General ]"
TZ=$(_prompt "timezone" "America/New_York")
APP_PASSWORD=$(_prompt  "app password (leave blank for none)" "")
CRON_ENABLE="false"
_confirm "Enable hourly data refresh cron job?" && CRON_ENABLE="true"
CRON_HOUR=$(_prompt "Refresh hour(s) (APScheduler, e.g. '*' = every hour, '2' = 2am)" "*")

# --- Server ---
echo ""
echo "[ Server ]"
SRV_HOST=$(_prompt    "bind host"              "0.0.0.0")
SRV_PORT=$(_prompt    "port"                   "80")
SRV_TIMEOUT=$(_prompt "request timeout (secs)" "$SERVER_TIMEOUT")
GUN_WORKERS=$(_prompt "gunicorn workers"       "$RECOMMENDED_WORKERS")

# --- Database path ---
echo ""
echo "[ Database ]"
echo "  Tip: For best performance, point db_path at a path on fast storage (SSD)."
DB_PATH=$(_prompt "db_path" "./config/fitness.db")

# =============================================================================
# Write config.yaml
# =============================================================================
cat > "$CONFIG_YAML" << YAML
# Fitly configuration — auto-generated by init-host.sh
# Detected: RAM=${TOTAL_MEM}MB, CPUs=${CPU_COUNT}, Storage=${STORAGE_TYPE}
#
# Cloud-native override: any value can be set via environment variable
#   FITLY_<SECTION>_<KEY>  (uppercase, underscores)
#   e.g. FITLY_STRAVA_CLIENT_ID=abc123

logger:
  level: DEBUG
  log_file: ./config/log.log
  log_max_bytes: 10000000
  log_backup_count: 5

cron:
  hourly_pull: ${CRON_ENABLE}
  refresh_hour: "${CRON_HOUR}"

settings:
  password: "${APP_PASSWORD}"
  gunicorn_workers: ${GUN_WORKERS}

# ---------------------------------------------------------------------------
# Spotify — leave client_id / client_secret blank to disable
# Restart required after connecting via the settings page.
# ---------------------------------------------------------------------------
spotify:
  client_id: "${SPOTIFY_CLIENT_ID}"
  client_secret: "${SPOTIFY_CLIENT_SECRET}"
  redirect_uri: "${SPOTIFY_REDIRECT}"
  skip_min_threshold: 0.05
  skip_max_threshold: 0.80
  min_secs_listened: 15
  poll_interval_seconds: 0.5

peloton:
  username: "${PELOTON_USER}"
  password: "${PELOTON_PASS}"

stryd:
  username: "${STRYD_USER}"
  password: "${STRYD_PASS}"
  compare_against_age: 1
  compare_against_gender: 1
  compare_against_race_event: 1

# ---------------------------------------------------------------------------
# Strava — required for activity import
# ---------------------------------------------------------------------------
strava:
  activities_after_date: "${STRAVA_AFTER_DATE}"
  client_id: "${STRAVA_CLIENT_ID}"
  client_secret: "${STRAVA_CLIENT_SECRET}"
  redirect_uri: "http://127.0.0.1:8050/settings?strava"

oura:
  redirect_uri: "http://127.0.0.1:8050/settings?oura"
  client_id: "${OURA_CLIENT_ID}"
  client_secret: "${OURA_CLIENT_SECRET}"
  days_back: ${OURA_DAYS_BACK}
  white: "rgb(220, 220, 220)"
  teal: "rgb(134, 201, 250)"
  light_blue: "rgb(85, 139, 189)"
  dark_blue: "rgb(43, 70, 119)"
  orange: "rgb(234, 109, 95)"

withings:
  redirect_uri: "http://127.0.0.1:8050/settings?withings"
  client_id: "${WITHINGS_CLIENT_ID}"
  client_secret: "${WITHINGS_CLIENT_SECRET}"

nextcloud:
  url: "${NC_URL}"
  username: "${NC_USER}"
  password: "${NC_PASS}"
  fitbod_path: "${NC_FITBOD}"

timezone:
  timezone: "${TZ}"

# ---------------------------------------------------------------------------
# Processing — auto-tuned for detected hardware
# ---------------------------------------------------------------------------
processing:
  workers: ${POOL_WORKERS}
  serialize_db_writes: ${SERIALIZE_WRITES}
  db_write_max_retries: 5
  db_write_base_delay_s: 1.0

# ---------------------------------------------------------------------------
# Database — SQLite path and performance tuning
# ---------------------------------------------------------------------------
database:
  db_path: ${DB_PATH}
  connection_timeout_s: 30
  busy_timeout_ms: 30000
  cache_size_mb: ${CACHE_MB}
  mmap_size_mb: ${MMAP_MB}
  wal_autocheckpoint: ${WAL_CHECKPOINT}

# ---------------------------------------------------------------------------
# Server — network binding and gunicorn worker timeout
# ---------------------------------------------------------------------------
server:
  host: "${SRV_HOST}"
  port: ${SRV_PORT}
  request_timeout_s: ${SRV_TIMEOUT}

dashboard:
  transition: 2000
YAML

echo ""
echo "  [+] Config written to: ${CONFIG_YAML}"

# Remove stale config.ini if present so YAML takes precedence
if [ -f "$CONFIG_INI" ]; then
    echo "  [~] Note: ${CONFIG_INI} also exists. YAML takes priority."
    echo "      Delete or rename config.ini if you want to use YAML exclusively:"
    echo "        mv ${CONFIG_INI} ${CONFIG_INI}.bak"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Pre-flight complete!"
echo ""
echo "  Next steps:"
echo "    1. Review ${CONFIG_YAML}"
echo "    2. Connect services (Strava/Oura/etc.) via the Settings page"
echo "    3. Start Fitly:"
echo "         docker-compose up -d"
echo "      or:"
echo "         gunicorn --config gunicorn_conf.py 'fitly:server'"
echo "═══════════════════════════════════════════════════════════════"
echo ""
>>>>>>> feature/configurable-concurrency
