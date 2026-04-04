# Fitly

**Fitly** is a self-hosted performance analytics dashboard that consolidates your fitness and health data from Strava, Oura, Withings, Spotify, and more. It helps you track your training load, readiness, and power duration curves across different sports.

> [!NOTE]
> **Running on a Raspberry Pi / Edge Device?** See the [Performance Tuning](#-performance-tuning) section to prevent SD card I/O issues.

---

## ✨ Key Features & Improvements

This repository builds heavily on the original Fitly project with major enhancements for stability, performance, and usability:
- **Cloud-Native Configuration:** Fully supports `config.yaml` and environment-variable overrides (`FITLY_SECTION_KEY=val`) for easy deployment in Docker and Kubernetes.
- **Improved Concurrency:** Re-architected data ingestion using Python multiprocessing pools and SQLite `WAL` mode to eliminate database lock errors and speed up data pulls.
- **Edge-Device Ready:** Includes `init-host.sh` for Raspberry Pi/SD-card host tuning. Employs hardware detection to throttle concurrent writes and prevent fatal OS I/O deadlocks.
- **Dynamic FTP Matching:** Intelligently extracts Cycling FTP from Strava activities named *"FTP test"* and queries Run FTP directly via the Stryd API.
- **Expanded Integrations:** First-class Nextcloud support for syncing Fitbod strength routines, along with Peloton, Spotify, Oura, and Withings sync handling.
- **Metric/Imperial System:** Global toggles for handling measurements (Coming soon / tracked dynamically across running and cycling pages).

---

## 🚀 Quick Start

The easiest way to get started is using the included pre-flight script. It detects your hardware, tunes the host (if on a Raspberry Pi), and generates a `config/config.yaml`.

```bash
chmod +x init-host.sh
./init-host.sh
```
*(Use `./init-host.sh --config-only` to skip host tuning steps requiring `sudo`).*

Then, start the application:

**Using Docker (Recommended):**
```bash
docker-compose up -d
```

**Using Python / IDE:**
```bash
pip install -e .
gunicorn --config gunicorn_conf.py 'fitly:server'
# Or use `run-fitly-dev` for development
```

Access the dashboard at `http://127.0.0.1:8050/settings` and use your configured password to connect your integration accounts.

---

## ⚙️ Configuration

Fitly uses `config/config.yaml` as its primary configuration source, but supports environment variable overrides for easy Docker/Kubernetes deployments (`FITLY_<SECTION>_<KEY>=value`).

### Core Settings
- **`[database] db_path`**: Path to your SQLite DB (mount an SSD/NVMe volume here for best performance).
- **`[settings] password`**: Used for securing the Settings dashboard.
- **`[cron] hourly_pull`**: Set to `true` to enable automatic background data refresh.

*See `config/config.yaml.example` for a full list of configuration parameters.*

---

## 🔗 Integrations (OAuth)

Each integration requires a matching **redirect URI** on both the provider's developer console and your Fitly configuration.

**Redirect URI Format**: `http://<your-fitly-ip>:8050/settings?<provider>` (e.g., `?strava`, `?oura`).
*(Ensure this matches exactly how you access the dashboard, including `http`/`https` and the port).*

### Setup Requirements
| Provider | Setup Link | Config Required |
|---|---|---|
| **Strava** (Required) | [API Settings](https://www.strava.com/settings/api) | `client_id`, `client_secret`, `activities_after_date` |
| **Oura** | [Developer Portal](https://cloud.ouraring.com/oauth/applications) | `client_id`, `client_secret` |
| **Withings** | [Developer Dashboard](https://account.withings.com/partner/dashboard_oauth2) | `client_id`, `client_secret` |
| **Spotify** | [Developer Dashboard](https://developer.spotify.com/dashboard/) | `client_id`, `client_secret` |

**Optional Non-OAuth Integrations:**
- **Peloton**: Add `username` / `password` to match classes to Strava workouts.
- **Stryd**: Add `username` / `password` to sync Critical Power automatically.
- **Fitbod**: Specify Nextcloud credentials and a CSV path to sync strength workouts.

---

## ⚡ Power & FTP

Fitly determines your Functional Threshold Power (FTP) dynamically to power its charts.

**Run FTP**: 
1. Stryd value (if credentials configured).
2. 20-min Best Power × 0.95 (from recent run activities). 
3. Manual override in Settings.

**Ride FTP**:
1. Strava Activity title contains **"FTP test"** (e.g., "Indoor FTP Test"). Average watts × 0.95.
2. 20-min Best Power × 0.95 (from recent ride activities).
3. Manual override in Settings.

---

## 🛠 Advanced Usage

### Hosting Externally
When hosting externally via a reverse proxy (like NGINX), ensure your `redirect_uri` configurations use your domain (e.g., `https://fit.yourdomain.com/settings?strava`). Set `[server] host` to `0.0.0.0` to expose the port for the proxy.

### 🏎 Performance Tuning
For Raspberry Pi or SD card users, Fitly limits concurrent writes to prevent SD card burnout (I/O Wait Death Spiral). On SSDs/NVMe drives, you can unlock full database concurrency by modifying `config.yaml`:

```yaml
processing:
  serialize_db_writes: false  # Unlock concurrent writes
database:
  cache_size_mb: 256
  mmap_size_mb: 256
```
