#!/bin/sh
# =============================================================================
# init-host.sh — Fitly Host Optimizer, Pre-Flight Check & Config Generator
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

_prompt() {
    _msg="$1"
    _default="$2"
    printf "  %s [%s]: " "$_msg" "$_default" >&2
    read -r _input </dev/tty
    echo "${_input:-$_default}"
}

_confirm() {
    printf "  %s (y/N): " "$1" >&2
    read -r _yn </dev/tty
    case "$_yn" in [yY]*) return 0;; *) return 1;; esac
}

# =============================================================================
# PHASE 0: DEPENDENCY CHECK
# =============================================================================
echo "─── Phase 0: Dependency Check ─────────────────────────────────"
REQUIRED_TOOLS="awk grep sed find free df sudo"
MISSING_TOOLS=""

for tool in $REQUIRED_TOOLS; do
    if ! _has_cmd "$tool"; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo "  [!] FATAL ERROR: Missing required system utilities."
    echo "      Please install: $MISSING_TOOLS"
    exit 1
else
    echo "  [+] All required system tools detected."
    echo ""
fi

# =============================================================================
# PHASE 1: HARDWARE DETECTION & LIMIT CALCULATION
# =============================================================================
echo "─── Phase 1: Hardware Detection ───────────────────────────────"

# RAM Detection
TOTAL_MEM=0
if _has_cmd free; then
    TOTAL_MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
fi
TOTAL_MEM=${TOTAL_MEM:-0}
echo "  RAM:        ${TOTAL_MEM} MB"

# CPU Core Detection
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

# Platform Detection
IS_PI=0
if [ -f /proc/device-tree/model ] && grep -qi "raspberry" /proc/device-tree/model 2>/dev/null; then
    IS_PI=1
    echo "  Platform:   Raspberry Pi"
else
    echo "  Platform:   Generic Linux"
fi

# Storage Detection
IS_SSD=0
IS_SD=0
STORAGE_TYPE="unknown"

if _has_cmd df; then
    _raw_dev=$(df . 2>/dev/null | tail -n 1 | awk '{print $1}')
    if _has_cmd readlink; then
        _raw_dev=$(readlink -f "$_raw_dev" 2>/dev/null || echo "$_raw_dev")
    fi
    _base=$(basename "$_raw_dev")
    
    # POSIX compliant parent device resolution
    _dev="$_base"
    if [ -n "$_dev" ]; then
        while [ ! -d "/sys/block/$_dev" ] && [ -n "$_dev" ]; do
            _dev=${_dev%?}
        done
    fi
    [ -z "$_dev" ] && _dev="$_base"

    if [ -n "$_dev" ] && [ -f "/sys/block/${_dev}/queue/rotational" ]; then
        _rotational=$(cat "/sys/block/${_dev}/queue/rotational" 2>/dev/null)
        case "$_dev" in
            mmcblk*)
                IS_SD=1
                if [ "$(cat "/sys/block/${_dev}/removable" 2>/dev/null)" = "1" ]; then
                    STORAGE_TYPE="SD card"
                else
                    STORAGE_TYPE="eMMC"
                fi
                ;;
            nvme*)
                IS_SSD=1
                STORAGE_TYPE="SSD/NVMe"
                ;;
            *)
                if [ "$_rotational" = "0" ]; then
                    IS_SSD=1
                    STORAGE_TYPE="SSD"
                elif [ "$_rotational" = "1" ]; then
                    STORAGE_TYPE="HDD"
                fi
                ;;
        esac
    fi
fi

if [ "$STORAGE_TYPE" = "unknown" ] && [ "$IS_PI" -eq 1 ]; then
    IS_SD=1
    STORAGE_TYPE="SD card (Fallback)"
fi

echo "  Storage:    ${STORAGE_TYPE}"

# Docker Memory Limit Calculation
if [ "$TOTAL_MEM" -lt 1024 ]; then
    DOCKER_MEM_LIMIT=$(( TOTAL_MEM - 150 ))
elif [ "$TOTAL_MEM" -lt 4096 ]; then
    DOCKER_MEM_LIMIT=$(( TOTAL_MEM - 500 ))
else
    DOCKER_MEM_LIMIT=4096
fi
echo "  Target Fence: ${DOCKER_MEM_LIMIT}M (Docker Memory Limit)"

# Dynamic Defaults Calculation
if [ "$HAS_HT" -eq 1 ]; then
    RECOMMENDED_WORKERS=$(( (2 * PHYSICAL_CORES) + 1 ))
else
    RECOMMENDED_WORKERS=$(( PHYSICAL_CORES + 1 ))
fi
AVAILABLE_CPUS=$(( CPU_COUNT - 1 ))
[ "$AVAILABLE_CPUS" -lt 1 ] && AVAILABLE_CPUS=1
[ "$RECOMMENDED_WORKERS" -gt "$AVAILABLE_CPUS" ] && RECOMMENDED_WORKERS=$AVAILABLE_CPUS
[ "$RECOMMENDED_WORKERS" -lt 2 ] && RECOMMENDED_WORKERS=2

POOL_WORKERS=$(( CPU_COUNT / 2 ))
[ "$POOL_WORKERS" -lt 1 ] && POOL_WORKERS=1

CACHE_MB=$(( TOTAL_MEM / 4 ))
[ "$CACHE_MB" -lt 32 ]  && CACHE_MB=32
[ "$CACHE_MB" -gt 256 ] && CACHE_MB=256

if [ "$IS_SSD" -eq 1 ] || { [ "$IS_SD" -eq 0 ] && [ "$STORAGE_TYPE" = "eMMC" ]; }; then
    MMAP_MB=$CACHE_MB
    SERIALIZE_WRITES="false"
    WAL_CHECKPOINT=2000
else
    MMAP_MB=0
    SERIALIZE_WRITES="true"
    WAL_CHECKPOINT=4000
fi

if [ "$IS_PI" -eq 1 ]; then
    SERVER_TIMEOUT=1800
else
    SERVER_TIMEOUT=1200
fi

# LAN IP Detection — used to build correct OAuth redirect URIs
LAN_IP="127.0.0.1"
if _has_cmd ip; then
    _detected_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    [ -n "$_detected_ip" ] && LAN_IP="$_detected_ip"
elif _has_cmd hostname; then
    _detected_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -n "$_detected_ip" ] && LAN_IP="$_detected_ip"
fi
echo "  LAN IP:     ${LAN_IP}"

echo ""
echo "  Recommended settings derived from hardware:"
echo "    gunicorn_workers:  ${RECOMMENDED_WORKERS}"
echo "    pool workers:      ${POOL_WORKERS}"
echo "    cache_size_mb:     ${CACHE_MB}"
echo "    serialize_writes:  ${SERIALIZE_WRITES}"
echo ""

# =============================================================================
# PHASE 2: HOST TUNING & CGROUP VALIDATION (skip if --config-only)
# =============================================================================
if [ "$CONFIG_ONLY" -eq 0 ]; then
    echo "─── Phase 2: Host Tuning & Cgroup Validation ──────────────────"

    # I/O Tuning
    if [ "$TOTAL_MEM" -gt 0 ] && [ "$TOTAL_MEM" -lt 1500 ]; then
        echo "  [+] Low-memory device. Applying SD card I/O trickle-write tuning..."
        grep -q "vm.dirty_background_ratio" /etc/sysctl.conf 2>/dev/null || echo "vm.dirty_background_ratio = 2" | sudo tee -a /etc/sysctl.conf >/dev/null
        grep -q "vm.dirty_ratio" /etc/sysctl.conf 2>/dev/null || echo "vm.dirty_ratio = 5" | sudo tee -a /etc/sysctl.conf >/dev/null
        sudo sysctl -p >/dev/null 2>&1
    else
        echo "  [+] Sufficient RAM detected. Default kernel I/O limits retained."
    fi

    # Cgroup Validation (v1 and v2)
    CGROUP_V2=0
    CGROUP_V1=0
    if [ -f /sys/fs/cgroup/cgroup.controllers ] && grep -q "memory" /sys/fs/cgroup/cgroup.controllers 2>/dev/null; then
        CGROUP_V2=1
    elif [ -f /proc/cgroups ] && awk '$1=="memory" {print $4}' /proc/cgroups 2>/dev/null | grep -q "1"; then
        CGROUP_V1=1
    fi

    if [ "$CGROUP_V2" -eq 1 ]; then
        echo "  [+] Modern cgroup v2 detected. Docker memory fencing operational."
    elif [ "$CGROUP_V1" -eq 1 ]; then
        echo "  [+] Legacy cgroup v1 detected. Docker memory fencing operational."
    else
        if [ "$IS_PI" -eq 1 ]; then
            echo "  [!] WARNING: Memory cgroups are DISABLED on this Raspberry Pi."
            CMDLINE_FILE=$(find /media /boot -name "cmdline.txt" 2>/dev/null | head -n 1)
            if [ -n "$CMDLINE_FILE" ] && [ -f "$CMDLINE_FILE" ]; then
                if grep -q "cgroup_memory" "$CMDLINE_FILE"; then
                    echo "  [+] cgroup flags already present. Reboot pending."
                else
                    echo "  [+] Injecting cgroup flags into $CMDLINE_FILE..."
                    # POSIX compliant file append via pipeline and sudo tee
                    cat "$CMDLINE_FILE" | sed 's/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' | sudo tee "$CMDLINE_FILE" >/dev/null
                    echo "  [!] PATCH APPLIED. You MUST reboot before running Docker."
                fi
            else
                echo "  [!] Could not auto-locate cmdline.txt. Manual patch required."
            fi
        else
            echo "  [!] WARNING: No memory cgroup controllers (v1 or v2) detected."
        fi
    fi
    echo ""
fi

# =============================================================================
# PHASE 3: ENVIRONMENT INJECTION
# =============================================================================
echo "─── Phase 3: Environment Injection ────────────────────────────"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"
touch "$ENV_FILE"

# POSIX compliant stream replacement (avoids sed -i)
grep -v "^FITLY_MEM_LIMIT=" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null || true
echo "FITLY_MEM_LIMIT=${DOCKER_MEM_LIMIT}M" >> "${ENV_FILE}.tmp"
mv "${ENV_FILE}.tmp" "$ENV_FILE"

echo "  [+] Injected FITLY_MEM_LIMIT=${DOCKER_MEM_LIMIT}M into .env file."
echo ""

# =============================================================================
# PHASE 4: CONFIG GENERATION
# =============================================================================
echo "─── Phase 4: Config Generation ────────────────────────────────"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG_DIR="${SCRIPT_DIR}/config"
mkdir -p "$CONFIG_DIR"

CONFIG_YAML="${CONFIG_DIR}/config.yaml"
CONFIG_INI="${CONFIG_DIR}/config.ini"

if [ -f "$CONFIG_YAML" ]; then
    echo "  [!] ${CONFIG_YAML} already exists."
    if ! _confirm "Overwrite it?"; then
        echo "  [~] Skipping config generation. Existing file preserved."
        exit 0
    fi
fi

echo ""
echo "  We'll now collect values for your config."
echo "  Press Enter to accept the suggested default shown in [brackets]."
echo ""

# --- Docker port (external) ---
DOCKER_PORT=$(_prompt "Docker host port for Fitly (e.g. 8050)" "8050")
CALLBACK_BASE="http://${LAN_IP}:${DOCKER_PORT}"
echo "" >&2
echo "  OAuth redirect base URL: ${CALLBACK_BASE}" >&2
echo "  (All integrations will use this for redirect URIs)" >&2

# --- Strava (required) ---
echo "" >&2
echo "┌─ Strava (required) ────────────────────────────────────────" >&2
echo "│  Strava is the primary source for workout data." >&2
echo "│  Create an API app at: https://www.strava.com/settings/api" >&2
echo "│  Set callback domain to: ${LAN_IP}" >&2
echo "└────────────────────────────────────────────────────────────" >&2
STRAVA_CLIENT_ID=$(_prompt "Strava API client ID" "")
STRAVA_CLIENT_SECRET=$(_prompt "Strava API client secret" "")
_strava_date_raw=$(_prompt "Import activities after this date (MM-DD-YY)" "1-1-18")

# Convert US date (MM-DD-YY or MM-DD-YYYY) to ISO 8601 for Strava API
_mm=$(echo "$_strava_date_raw" | cut -d'-' -f1)
_dd=$(echo "$_strava_date_raw" | cut -d'-' -f2)
_yy=$(echo "$_strava_date_raw" | cut -d'-' -f3)
# Expand 2-digit year: assume 20xx
if [ ${#_yy} -le 2 ]; then _yy="20${_yy}"; fi
# Zero-pad month and day
_mm=$(printf '%02d' "$_mm")
_dd=$(printf '%02d' "$_dd")
STRAVA_AFTER_DATE="${_yy}-${_mm}-${_dd}T00:00:00Z"

# --- Oura ---
echo "" >&2
echo "┌─ Oura Ring (optional — leave blank to skip) ─────────────" >&2
echo "│  Powers the home page and HRV-based readiness analytics." >&2
echo "│  Create an app at: https://cloud.ouraring.com/oauth/applications" >&2
echo "│  Set redirect URI:  ${CALLBACK_BASE}/settings?oura" >&2
echo "└────────────────────────────────────────────────────────────" >&2
OURA_CLIENT_ID=$(_prompt "Oura API client ID" "")
OURA_CLIENT_SECRET=$(_prompt "Oura API client secret" "")
OURA_DAYS_BACK=$(_prompt "Days of history to re-pull each refresh" "7")

# --- Spotify ---
echo "" >&2
echo "┌─ Spotify (optional — leave blank to skip) ───────────────" >&2
echo "│  Tracks listening behavior and generates workout playlists." >&2
echo "│  Create an app at: https://developer.spotify.com/dashboard/" >&2
echo "│  Set redirect URI:  ${CALLBACK_BASE}/settings?spotify" >&2
echo "└────────────────────────────────────────────────────────────" >&2
SPOTIFY_CLIENT_ID=$(_prompt "Spotify API client ID" "")
SPOTIFY_CLIENT_SECRET=$(_prompt "Spotify API client secret" "")
SPOTIFY_REDIRECT=$(_prompt "Spotify redirect URI" "${CALLBACK_BASE}/settings?spotify")

# --- Peloton ---
echo "" >&2
echo "┌─ Peloton (optional — leave blank to skip) ───────────────" >&2
echo "│  Matches Peloton class names to Strava workout titles." >&2
echo "│  Uses your regular Peloton login credentials." >&2
echo "└────────────────────────────────────────────────────────────" >&2
PELOTON_USER=$(_prompt "Peloton account username (email)" "")
PELOTON_PASS=$(_prompt "Peloton account password" "")

# --- Withings ---
echo "" >&2
echo "┌─ Withings (optional — leave blank to skip) ──────────────" >&2
echo "│  Body weight and body fat data for performance analytics." >&2
echo "│  Create an app at: https://account.withings.com/partner/dashboard_oauth2" >&2
echo "│  Set redirect URI:  ${CALLBACK_BASE}/settings?withings" >&2
echo "└────────────────────────────────────────────────────────────" >&2
WITHINGS_CLIENT_ID=$(_prompt "Withings API client ID" "")
WITHINGS_CLIENT_SECRET=$(_prompt "Withings API client secret" "")

# --- Stryd ---
echo "" >&2
echo "┌─ Stryd (optional — leave blank to skip) ─────────────────" >&2
echo "│  Pulls Critical Power (FTP) directly from Stryd." >&2
echo "│  Uses your regular Stryd login credentials." >&2
echo "└────────────────────────────────────────────────────────────" >&2
STRYD_USER=$(_prompt "Stryd account username (email)" "")
STRYD_PASS=$(_prompt "Stryd account password" "")

# --- Nextcloud ---
echo "" >&2
echo "┌─ Nextcloud / Fitbod (optional — leave blank to skip) ────" >&2
echo "│  Import Fitbod strength workout exports from Nextcloud." >&2
echo "│  Export from Fitbod: Log > Settings > Export workout data" >&2
echo "│  Upload the CSV to Nextcloud and enter the path below." >&2
echo "└────────────────────────────────────────────────────────────" >&2
NC_URL=$(_prompt "Nextcloud server URL (e.g. https://cloud.example.com)" "")
NC_USER=$(_prompt "Nextcloud username" "")
NC_PASS=$(_prompt "Nextcloud password" "")
NC_FITBOD=$(_prompt "Path to Fitbod CSV on Nextcloud" "")

# --- General ---
echo "" >&2
echo "┌─ General Settings ──────────────────────────────────────────" >&2
echo "└────────────────────────────────────────────────────────────" >&2
TZ=$(_prompt "Your timezone (IANA format, e.g. America/New_York)" "America/New_York")
APP_PASSWORD=$(_prompt "Settings page password (blank = no password)" "")
CRON_ENABLE="false"
_confirm "Enable hourly automatic data refresh cron job?" && CRON_ENABLE="true"
CRON_HOUR=$(_prompt "Cron refresh hour ('*' = every hour, '2' = 2am only)" "*")

# --- Server ---
echo "" >&2
echo "┌─ Server Settings ─────────────────────────────────────────" >&2
echo "│  Network binding and gunicorn worker configuration." >&2
echo "└────────────────────────────────────────────────────────────" >&2
SRV_HOST=$(_prompt "Bind address (0.0.0.0 = all interfaces)" "0.0.0.0")
SRV_PORT=$(_prompt "HTTP port" "80")
SRV_TIMEOUT=$(_prompt "Request timeout in seconds" "$SERVER_TIMEOUT")
GUN_WORKERS=$(_prompt "Gunicorn worker count" "$RECOMMENDED_WORKERS")

# --- Database path ---
echo "" >&2
echo "┌─ Database ───────────────────────────────────────────────" >&2
echo "│  Path to the SQLite database file." >&2
echo "│  Tip: For best performance, use a path on fast storage (SSD)." >&2
echo "└────────────────────────────────────────────────────────────" >&2
DB_PATH=$(_prompt "SQLite database file path" "./config/fitness.db")

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
  redirect_uri: "${CALLBACK_BASE}/settings?strava"

oura:
  redirect_uri: "${CALLBACK_BASE}/settings?oura"
  client_id: "${OURA_CLIENT_ID}"
  client_secret: "${OURA_CLIENT_SECRET}"
  days_back: ${OURA_DAYS_BACK}
  white: "rgb(220, 220, 220)"
  teal: "rgb(134, 201, 250)"
  light_blue: "rgb(85, 139, 189)"
  dark_blue: "rgb(43, 70, 119)"
  orange: "rgb(234, 109, 95)"

withings:
  redirect_uri: "${CALLBACK_BASE}/settings?withings"
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