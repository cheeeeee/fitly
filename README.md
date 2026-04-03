# ⚠️ Important: Running on Edge Devices (Raspberry Pi)

If you are deploying this project on a Raspberry Pi or similar edge hardware running off an SD card, please read this section before starting the container.

Multi-threaded applications performing heavy, concurrent database writes (like pulling bulk Strava data) can easily overwhelm an SD card's limited random-write speeds. On devices with lower memory—such as the Raspberry Pi 3 (~1GB RAM)—the Linux kernel will attempt to cache database writes in RAM and flush them to the SD card all at once. This instantly causes an **I/O Wait Death Spiral**, which completely freezes the host OS, drops network traffic, and locks you out of SSH.

### 1. Host Kernel Tuning (Trickle Writes)
We provide a pre-flight script that detects low-memory host devices and automatically tunes the Linux kernel's `sysctl` settings (`vm.dirty_background_ratio` and `vm.dirty_ratio`). This forces the OS to continuously "trickle" data to the SD card rather than dumping it in large, system-crashing batches.

**Before running Docker Compose, execute this script on your host machine:**
```bash
chmod +x init-host.sh
./init-host.sh
```
### 2. Container Memory Fencing
The included docker-compose.yml contains hardcoded resource limits (memory: '750M'). Because many lightweight OS deployments (like Alpine) have zero Swap space by default, allowing a container to consume all available RAM will trigger an Out-Of-Memory (OOM) kernel panic. This memory fence guarantees the host OS always has enough breathing room to manage network and disk I/O.

### 3. SQLite Concurrency Optimizations

Under the hood, the Python application initializes the SQLite database with PRAGMA journal_mode=WAL; and PRAGMA synchronous=NORMAL;. This heavily optimizes the database for multi-threaded worker pools, dramatically lowering SD card wear and eliminating micro-freezes during bulk data ingestion.

# Fit.ly
Web analytics for endurance athletes

![Dashboard](https://i.imgur.com/Z3mfOMR.jpeg)
![Performance](https://i.imgur.com/A5rJNff.png)
![Charts](https://i.imgur.com/PewZiKt.png)
![HRV](https://i.imgur.com/hsSPvyn.png)
![Training](https://i.imgur.com/26Bglbc.jpg)
![Music](https://i.imgur.com/tbx5YmT.png)
![Oura](https://i.imgur.com/zeNnCvn.jpg)
![Peloton](https://i.imgur.com/7j6Ez9K.jpg)
![Withings](https://i.imgur.com/uafoBFI.jpg)

Special thanks to Slapdash for helping organize!
https://github.com/ned2/slapdash

---

# Installation Methods

## Docker (Recommended)

```sh
docker create --name=fitly \
    --restart unless-stopped \
    -e MODULE_NAME=src.fitly.app \
    -e VARIABLE_NAME=server \
    -e TZ=America/New_York \
    -p 8050:80 \
    -v <local mount path>:/app/config \
    ethanopp/fitly:latest
```

## Python / IDE

After cloning/downloading the repository, install Fit.ly into your environment:

```sh
pip install -e PATH_TO_fitly
```

---

# Quick Start — `init-host.sh`

The easiest way to get started is to run the included setup script. It will:

1. **Detect your hardware** — RAM, CPU count, storage type (SSD vs SD card)
2. **Tune the host** — applies kernel I/O settings for SD card safety on Raspberry Pi
3. **Validate Docker cgroups** — patches `cmdline.txt` if memory cgroups are missing
4. **Generate your config** — interactive prompts with hardware-tuned defaults, writes `config/config.yaml`

```sh
chmod +x init-host.sh
./init-host.sh
```

On a machine without root access (or to skip the kernel/cgroup phases):

```sh
./init-host.sh --config-only
```

After running, review `config/config.yaml` and connect your integrations via the Settings page.

## `init-host.sh` Requirements

### Required system commands

| Command | Purpose |
|---|---|
| `sh` (POSIX) | Script interpreter — do not invoke with `bash -e`, the shebang is `#!/bin/sh` |
| `free` | RAM detection |
| `nproc` | CPU core count |
| `df` + `lsblk` | Storage type detection (SSD vs SD/HDD) |
| `awk`, `grep`, `sed` | Text processing throughout |
| `mkdir`, `find`, `cat` | Directory creation, boot config lookup, YAML generation |
| `read` | Interactive credential prompts (Phase 4) |
| `sudo` | Kernel I/O tuning and Raspberry Pi cgroup patching (Phases 2 & 3 only) |

### Optional commands

| Command | Purpose |
|---|---|
| `python3` | Hyperthreading detection (physical vs logical core count) |
| `sysctl` | Applying `vm.dirty_*` kernel parameters (requires `sudo`) |

### Permissions

- **`sudo` access** is required for Phases 2 and 3 (kernel I/O tuning and Docker cgroup patching). Use `--config-only` to skip these phases — no `sudo` needed.
- **Write access to `./config/`** — the script creates this directory next to itself and writes `config.yaml` into it.

### Environment

- **Interactive terminal required** — the script prompts for API credentials; it cannot be piped from a non-interactive shell.
- **Linux only** — relies on `/proc/cgroups`, `/proc/cpuinfo`, `/sys/block/`, and (optionally) `/proc/device-tree/model`. Not supported on macOS.
- Must be run from the **repo root directory** (or the directory containing `init-host.sh`) so that `./config/` resolves correctly.

---

# Configuring Your App

Fitly supports three config sources in **priority order**:

| Priority | Source | Notes |
|---|---|---|
| **1** | Environment variables | `FITLY_<SECTION>_<KEY>` — best for Docker/Kubernetes |
| **2** | `config/config.yaml` | Recommended for new installs |
| **3** | `config/config.ini` | Classic format, still fully supported |

If `config.yaml` exists it takes precedence over `config.ini`. Both example files are included in the `config/` directory.

## Using YAML (recommended)

```sh
cp config/config.yaml.example config/config.yaml
# Edit config.yaml with your values, then start Fitly
```

## Using INI (classic)

```sh
cp config/config.ini.example config/config.ini
# Edit config.ini with your values, then start Fitly
```

## Using Environment Variables (Docker / Kubernetes)

Any config value can be overridden with an environment variable:

```
FITLY_<SECTION>_<KEY>=value
```

Examples:
```sh
FITLY_STRAVA_CLIENT_ID=abc123
FITLY_SETTINGS_PASSWORD=mysecretpassword
FITLY_DATABASE_DB_PATH=/data/fitness.db
FITLY_SERVER_PORT=8080
```

---

# Configuration Reference

## `[logger]`

| Key | Default | Description |
|---|---|---|
| `level` | `DEBUG` | Log level: `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `log_file` | `./config/log.log` | Path to the rotating log file |
| `log_max_bytes` | `10000000` | Max log size before rotation (bytes) |
| `log_backup_count` | `5` | Number of rotated log files to keep |

## `[cron]`

| Key | Default | Description |
|---|---|---|
| `hourly_pull` | `false` | Enable background data refresh |
| `refresh_hour` | `*` | APScheduler hour expression (`*` = every hour, `2` = 2am, `*/3` = every 3h) |

## `[settings]`

| Key | Default | Description |
|---|---|---|
| `password` | _(blank)_ | Password for the settings page |
| `gunicorn_workers` | auto | Override gunicorn worker count (see `[server]`) |

## `[database]` ⭐ _new_

| Key | Default | Description |
|---|---|---|
| `db_path` | `./config/fitness.db` | SQLite file path — **mount an SSD/NVMe volume here for best performance** |
| `connection_timeout_s` | `30` | Seconds to wait for a locked DB before erroring |
| `busy_timeout_ms` | `30000` | SQLite `PRAGMA busy_timeout` |
| `cache_size_mb` | `64` | In-memory page cache size (MB) |
| `mmap_size_mb` | `64` | Memory-mapped I/O size (0 to disable; useful on SSD) |
| `wal_autocheckpoint` | `2000` | WAL checkpoint threshold (pages) |

## `[server]` ⭐ _new_

| Key | Default | Description |
|---|---|---|
| `host` | `0.0.0.0` | Bind address (`127.0.0.1` for localhost-only) |
| `port` | `80` | TCP port |
| `request_timeout_s` | `1200` | Gunicorn worker timeout in seconds |

## `[processing]`

| Key | Default | Description |
|---|---|---|
| `workers` | `auto` | Parallel workers for activity imports (`auto` = half of CPUs) |
| `serialize_db_writes` | `true` | Serialize DB writes with a lock (`true` = safe for SD cards; `false` = faster on SSD) |
| `db_write_max_retries` | `5` | Retry attempts when SQLite reports `database is locked` |
| `db_write_base_delay_s` | `1.0` | Initial retry delay in seconds (doubles each attempt) |

## `[timezone]`

| Key | Default | Description |
|---|---|---|
| `timezone` | `America/New_York` | Your local timezone (IANA format) |

---

# Integrations

## OAuth Redirect URIs (Callback URLs)

Every integration that uses OAuth (Strava, Oura, Withings, Spotify) requires a **redirect URI** registered with the provider and matching your config. After you authorize, the provider redirects your browser back to this URL — so **it must be reachable from your browser**, not from the server.

> **Common mistake:** Using `http://127.0.0.1:8050` when accessing Fitly from a different machine (e.g. laptop → Raspberry Pi). After authorizing Strava, Strava redirects your browser to `127.0.0.1:8050`, which is your laptop — not the Pi. The connection fails silently.

### Choosing the right redirect URI

| Access method | Redirect URI to use |
|---|---|
| Browser on same machine as Fitly | `http://127.0.0.1:8050/settings?strava` |
| Browser on different LAN machine (e.g. Pi) | `http://<pi-ip>:8050/settings?strava` |
| Reverse proxy with DNS | `https://fit.yourdomain.com/settings?strava` |

Replace `?strava` with `?oura`, `?withings`, or `?spotify` for each integration.

> **Important:** The redirect URI you set in your config **must exactly match** the one registered with the provider (Strava API settings, Oura developer portal, etc.), including the protocol (`http`/`https`) and port.

### Example — Raspberry Pi at `192.168.1.50`

In Strava API settings (`https://www.strava.com/settings/api`):
```
Authorization Callback Domain: 192.168.1.50
```

In `config/config.yaml`:
```yaml
strava:
  redirect_uri: "http://192.168.1.50:8050/settings?strava"
```

---

## Required — Strava

Strava is the primary hub for workout data.

1. Go to https://www.strava.com/settings/api
2. Set the **Authorization Callback Domain** to match your access method (see table above)
3. Copy your `client_id` and `client_secret` into your config
4. Set `redirect_uri` in your config to `http://<your-host>:8050/settings?strava`

## Optional — Oura Ring

Oura data powers the home page and improves performance analytics accuracy (HRV-based readiness, resting heart rate). Without it, the home page will not render.

1. Create a developer account at https://cloud.ouraring.com/oauth/applications
2. Set redirect URI to: `http://<your-host>:8050/settings?oura`
3. Copy `client_id` and `client_secret` into your config

Config keys: `days_back` (how far back each cron pull goes, default `7`)

## Optional — Withings

Body composition data (weight, body fat) used to improve performance analytics.

1. Create a developer account at https://account.withings.com/partner/dashboard_oauth2
2. Set redirect URI to: `http://<your-host>:8050/settings?withings`
3. Copy `client_id` and `client_secret` into your config

## Optional — Spotify

Tracks every song you listen to and analyzes your listening behavior (skips, rewinds, fast-forwards) to determine song likability by activity type and intensity. Can auto-generate recommended playlists.

1. Create a developer account at https://developer.spotify.com/dashboard/
2. Set redirect URI to: `http://<your-host>:8050/settings?spotify`
3. Copy `client_id` and `client_secret` into your config

> **Note:** A full application restart is required after first connecting Spotify for the live stream listener to start.

## Optional — Peloton

Fitly matches Peloton classes to Strava workouts by timestamp and updates Strava activity titles with the class name. If using Oura, HRV-based recommendations can auto-bookmark new Peloton classes on your device daily.

![Peloton recommendations](https://i.imgur.com/q654WHy.png)

Enter your Peloton `username` and `password` into your config.

## Optional — Stryd

Pulls Critical Power (FTP) directly from Stryd.

Enter your Stryd `username` and `password` into your config.

## Optional — Fitbod & Nextcloud

Export your Fitbod workout data (Log → Settings → Export workout data) to a Nextcloud location, then point Fitly at it:

```yaml
nextcloud:
  url: https://your-nextcloud.com
  username: your_username
  password: your_password
  fitbod_path: /path/to/fitbod_export.csv
```

---

# Power & FTP

Fitly determines your Functional Threshold Power (FTP) automatically using a fallback chain. You can always override it manually via the **Settings → Athlete** card.

## Running FTP

| Priority | Source | How it works |
|---|---|---|
| **1** | Stryd | If Stryd credentials are configured, FTP is pulled from the matched Stryd workout |
| **2** | 20-minute estimate | Best 20-min power (from prior activities) × 0.95 |
| **3** | Athlete table | The value you set manually on the Settings page (`run_ftp`) |

## Cycling FTP

| Priority | Source | How it works |
|---|---|---|
| **1** | FTP test activity | The average watts from your most recent ride whose **Strava title contains "FTP test"** (case-insensitive) × 0.95 |
| **2** | 20-minute estimate | Best 20-min power (from prior ride activities) × 0.95 |
| **3** | Athlete table | The value you set manually on the Settings page (`ride_ftp`) |

> **Tip — Setting cycling FTP via Strava:** After completing an FTP test on the bike, make sure the Strava activity name contains the text **"FTP test"** (e.g. "Indoor FTP Test 2026", "ftp test ride"). Fitly will pick up the average watts from that activity, multiply by 0.95, and use it as your cycling FTP going forward.

## Power Tab Display

The **Current FTP** header on the Power tab displays the best available FTP value:

- If a 20-minute best-power estimate from the last 90 days exceeds your manually-set FTP, the header shows **"Est. FTP ___ W (20min×.95)"**
- Otherwise it shows **"Current FTP ___ W"** from the athlete table
- The historical FTP bar chart still shows per-activity FTP values for trend accuracy

---

# Dashboard Startup

1. Navigate to `http://127.0.0.1:8050/pages/settings`
2. Enter the password from your config `[settings] password`
3. Use the **Connect** buttons in the top-left to authenticate each integration
4. Click **Refresh** to pull your data

### IDE / Development Mode

```sh
run-fitly-dev
```

Use `--port` to change the port, and `--host 0.0.0.0` to expose outside localhost.

---

# Hosting Externally (Docker Compose + NGINX)

```yaml
version: '3'
services:
  letsencrypt:
    image: linuxserver/letsencrypt
    container_name: letsencrypt
    cap_add:
      - NET_ADMIN
    restart: always
    ports:
      - "80:80"
      - "443:443"
    environment:
      - TZ=America/New_York
      - EMAIL=<your email>
      - URL=<website.com>
      - SUBDOMAINS=fit
    volumes:
      - <host config dir>:/config

  fitly:
    image: ethanopp/fitly:latest
    container_name: fitly
    restart: always
    depends_on:
      - letsencrypt
    ports:
      - "8050:80"
    environment:
      - MODULE_NAME=src.fitly.app
      - VARIABLE_NAME=server
      - TZ=America/New_York
      # All config values can be passed as env vars:
      # FITLY_SETTINGS_PASSWORD=mysecretpassword
      # FITLY_DATABASE_DB_PATH=/app/config/fitness.db
    volumes:
      - <host config dir>:/app/config
      - <letsencrypt config dir>/keys:/app/keys
```

### NGINX (subdomain example)

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name fit.*;

    include /config/nginx/ssl.conf;

    client_max_body_size 0;

    location / {
        include /config/nginx/proxy.conf;
        resolver 127.0.0.11 valid=30s;
        set $upstream_fitly fitly;
        proxy_pass http://$upstream_fitly:80;
    }
}
```

---

# Performance Tuning

## Raspberry Pi / SD Card (default)

The defaults are tuned for safety on slow storage. No changes needed.

```yaml
processing:
  workers: auto          # half of CPU cores
  serialize_db_writes: true   # one write at a time
database:
  cache_size_mb: 64
  mmap_size_mb: 0        # disabled on SD card
  wal_autocheckpoint: 4000
```

## SSD / NVMe / Fast Storage

On fast storage you can enable concurrent writes and larger caches:

```yaml
processing:
  serialize_db_writes: false  # concurrent writes via WAL
database:
  cache_size_mb: 256
  mmap_size_mb: 256
  wal_autocheckpoint: 2000
```

## Kubernetes / Cloud (PVC)

Mount a PVC at any path and point `db_path` at it:

```yaml
database:
  db_path: /data/fitness.db  # maps to your PVC mountPath
```

Or via environment variable:
```sh
FITLY_DATABASE_DB_PATH=/data/fitness.db
```
