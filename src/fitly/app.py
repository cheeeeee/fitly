from . import create_flask, create_dash, db_startup
from .layouts import main_layout_header, main_layout_sidebar
from apscheduler.schedulers.background import BackgroundScheduler
from .utils import spotify_credentials_supplied
from dash import html

# The Flask instance
server = create_flask()

# The Dash instance
app = create_dash(server)

# New DB startup tasks
db_startup(app)



# Logging — all values configurable via [logger] section
import logging
from logging.handlers import RotatingFileHandler
from .utils import config
from .api.sqlalchemy_declarative import dbRefreshStatus

try:
    _log_file = config.get('logger', 'log_file', fallback='') or './config/log.log'
except Exception:
    _log_file = './config/log.log'
try:
    _log_max_bytes = int(config.get('logger', 'log_max_bytes', fallback='10000000'))
except Exception:
    _log_max_bytes = 10_000_000
try:
    _log_backup_count = int(config.get('logger', 'log_backup_count', fallback='5'))
except Exception:
    _log_backup_count = 5

# Can also use %(pathname)s for full pathname for file instead of %(module)s
handler = RotatingFileHandler(_log_file, maxBytes=_log_max_bytes, backupCount=_log_backup_count)
formatter = logging.Formatter("[%(asctime)s] %(levelname)s from %(module)s line %(lineno)d - %(message)s")
handler.setFormatter(formatter)
app.server.logger.setLevel(config.get('logger', 'level') or 'DEBUG')
app.server.logger.addHandler(handler)
# Suppress WSGI info logs
logging.getLogger('werkzeug').setLevel(logging.INFO)

# Push an application context so we can use Flask's 'current_app'
with server.app_context():
    # load the rest of our Dash app
    from . import index

    # Enable refresh cron
    if config.get('cron', 'hourly_pull').lower() == 'true':
        try:
            from .api.datapull import refresh_database

            # cron_hour: which hour(s) to run the data pull (APScheduler format, default every hour)
            try:
                _cron_hour = config.get('cron', 'refresh_hour', fallback='*') or '*'
            except Exception:
                _cron_hour = '*'

            scheduler = BackgroundScheduler()
            scheduler.add_job(func=refresh_database, trigger="cron", hour=_cron_hour)

            # Add spotify job on 20 min schedule since API only allows grabbing the last 50 songs
            if spotify_credentials_supplied:
                from .api.spotifyAPI import stream, get_spotify_client, spotify_connected

                if spotify_connected():
                    app.server.logger.debug("Listening to Spotify stream...")
                    # Use this job to pull 'last 50' songs from spotify every 20 mins
                    # scheduler.add_job(func=save_spotify_play_history, trigger="cron", minute='*/20')

                    # Use this job for polling every second (much more precise data with this method can detect skips, etc.)
                    scheduler.add_job(stream, "interval", seconds=float(config.get('spotify', 'poll_interval_seconds')),
                                      max_instances=2)
                else:
                    app.server.logger.debug('Spotify not connected. Not listening to stream.')
            app.server.logger.info('Starting cron jobs')
            scheduler.start()
        except BaseException as e:
            app.server.logger.error(f'Error starting cron jobs: {e}')

    # Delete any audit logs for running processes, since restarting server would stop any processes
    app.session.query(dbRefreshStatus).filter(dbRefreshStatus.refresh_method == 'processing').delete()
    app.session.commit()
    app.session.remove()
    # configure the Dash instance's layout
    app.layout = main_layout_header()

