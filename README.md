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

## Required — Strava

Strava is the primary hub for workout data.

1. Go to https://www.strava.com/settings/api and set the authorization callback to `127.0.0.1:8050?strava`
2. Copy your `client_id` and `client_secret` into your config

## Optional — Oura Ring

Oura data powers the home page and improves performance analytics accuracy (HRV-based readiness, resting heart rate). Without it, the home page will not render.

1. Create a developer account at https://cloud.ouraring.com/oauth/applications
2. Set redirect URI to: `http://127.0.0.1:8050/settings?oura`
3. Copy `client_id` and `client_secret` into your config

Config keys: `days_back` (how far back each cron pull goes, default `7`)

## Optional — Withings

Body composition data (weight, body fat) used to improve performance analytics.

1. Create a developer account at https://account.withings.com/partner/dashboard_oauth2
2. Set redirect URI to: `http://127.0.0.1:8050/settings?withings`
3. Copy `client_id` and `client_secret` into your config

## Optional — Spotify

Tracks every song you listen to and analyzes your listening behavior (skips, rewinds, fast-forwards) to determine song likability by activity type and intensity. Can auto-generate recommended playlists.

1. Create a developer account at https://developer.spotify.com/dashboard/
2. Set redirect URI to: `http://127.0.0.1:8050/settings?spotify`
3. Copy `client_id` and `client_secret` into your config

> **Note:** A full application restart is required after first connecting Spotify for the live stream listener to start.

## Optional — Peloton

Fitly matches Peloton classes to Strava workouts by timestamp and updates Strava activity titles with the class name. If using Oura, HRV-based recommendations can auto-bookmark new Peloton classes on your device daily.

![Peloton recommendations](https://i.imgur.com/q654WHY.png)

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
