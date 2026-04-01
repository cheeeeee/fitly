import json
import multiprocessing
import os

# ---------------------------------------------------------------------------
# Host hardware detection
# ---------------------------------------------------------------------------
# os.cpu_count() returns logical CPUs (physical cores × threads-per-core).
# We use that to size workers while reserving headroom so the host can still
# handle SSH, cron, OS services, and other I/O without contention.
#
# On systems with hyperthreading (HT), the classic formula is (2 × cores) + 1
# because idle threads can serve requests during I/O waits.
# On systems WITHOUT HT (e.g. Raspberry Pi), cores = logical CPUs and that
# formula over-provisions. We use (cores + 1) instead and reserve 1 core
# for OS overhead (SSH, cron, system daemons).
# ---------------------------------------------------------------------------

logical_cpus = os.cpu_count() or 1

# Detect physical cores vs logical CPUs to identify hyperthreading
try:
    physical_cores = len(os.sched_getaffinity(0))
except (AttributeError, OSError):
    physical_cores = logical_cpus

has_hyperthreading = logical_cpus > physical_cores

# Reserve 1 CPU for system overhead (SSH, OS daemons, etc.)
reserved_cpus = 1
available_cpus = max(1, logical_cpus - reserved_cpus)

if has_hyperthreading:
    # HT systems: (2 × physical_cores) + 1, capped by available
    recommended_workers = min((2 * physical_cores) + 1, available_cpus)
else:
    # Non-HT systems (Raspberry Pi, etc.): cores + 1, capped by available
    recommended_workers = min(physical_cores + 1, available_cpus)

# Ensure at least 2 workers for reliability
recommended_workers = max(2, recommended_workers)

# ---------------------------------------------------------------------------
# Allow overrides via config (YAML preferred, falls back to INI) → env vars → computed default
# ---------------------------------------------------------------------------
import sys
sys.path.insert(0, './src')
try:
    from fitly.utils import config as _fitly_cfg
    _using_fitly_cfg = True
except Exception:
    _using_fitly_cfg = False
    import configparser
    _fitly_cfg = configparser.ConfigParser()
    _fitly_cfg.read('./config/config.ini')

def _cfg_get(section, key, fallback=''):
    """Read from FitlyConfig (YAML/INI/env) or raw configparser."""
    if _using_fitly_cfg:
        return _fitly_cfg.get(section, key, fallback=fallback)
    try:
        return _fitly_cfg.get(section, key)
    except Exception:
        return fallback

try:
    workers = int(_cfg_get('settings', 'gunicorn_workers'))
except (ValueError, Exception):
    workers = recommended_workers          # smart default based on host hardware

# Allow env-var override as a final escape hatch
if os.getenv("WEB_CONCURRENCY"):
    workers = int(os.getenv("WEB_CONCURRENCY"))

# ---------------------------------------------------------------------------
# Network / bind — config [server] section, then env vars, then sensible defaults
_cfg_host = _cfg_get('server', 'host')
_cfg_port = _cfg_get('server', 'port')
host = os.getenv("HOST") or _cfg_host or "0.0.0.0"
port = os.getenv("PORT") or _cfg_port or "80"
bind = os.getenv("BIND") or f"{host}:{port}"

# ---------------------------------------------------------------------------
# Gunicorn settings (module-level variables are read by gunicorn)
# ---------------------------------------------------------------------------
loglevel = os.getenv("LOG_LEVEL") or _cfg_get('logger', 'level') or "info"
keepalive = 120
errorlog = "-"

# Preload the app so the APScheduler does not duplicate across workers
preload_app = True

# Set generous timeout for long-running data-pull callbacks
_cfg_timeout = _cfg_get('server', 'request_timeout_s')
timeout = int(os.getenv("TIMEOUT") or _cfg_timeout or "1200")

# ---------------------------------------------------------------------------
# Startup banner
# ---------------------------------------------------------------------------
log_data = {
    "loglevel": loglevel,
    "workers": workers,
    "bind": bind,
    "logical_cpus": logical_cpus,
    "physical_cores": physical_cores,
    "hyperthreading": has_hyperthreading,
    "reserved_cpus": reserved_cpus,
    "host": host,
    "port": port,
}
print(json.dumps(log_data))
