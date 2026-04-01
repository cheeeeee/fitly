from flask import Flask
from dash import Dash

from .__version__ import __version__
<<<<<<< HEAD
from .utils import get_dash_args_from_flask_config
=======
from .utils import get_dash_args_from_flask_config, config
>>>>>>> feature/configurable-concurrency
from sqlalchemy.orm import scoped_session
from .api.database import SessionLocal, engine
from .api.sqlalchemy_declarative import *
from sqlalchemy import event
from datetime import datetime


def create_flask(config_object=f"{__package__}.settings"):
    """Create the Flask instance for this application"""
    server = Flask(__package__)

    # load default settings
    server.config.from_object(config_object)

    # load additional settings that will override the defaults in settings.py. eg
    # $ export FITLY_SETTINGS=/some/path/prod_settings.py
    server.config.from_envvar(
        "FITLY_SETTINGS", silent=True
    )

    return server

<<<<<<< HEAD
# SQL w/ WAL - Optimized for Low-Memory Edge Devices
=======
# SQL w/ WAL
>>>>>>> feature/configurable-concurrency
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    import time
    import logging
    logger = logging.getLogger(__name__)
<<<<<<< HEAD
    # Temporarily disable sqlite3 implicit transactions to run WAL PRAGMA on an empty DB
    isolation_level = dbapi_connection.isolation_level
    dbapi_connection.isolation_level = None
    
    cursor = dbapi_connection.cursor()
    # 1. Enable Write-Ahead Logging for concurrent multi-threading
    cursor.execute("PRAGMA journal_mode=WAL")
    # 2. Relax sync to prevent SD card I/O lockups
    cursor.execute("PRAGMA synchronous=NORMAL")
    # 3. Cap the connection cache at 10MB to prevent OOM panics
    cursor.execute("PRAGMA cache_size=-10000")
    cursor.close()
    
=======

    # Read tunable PRAGMA values from config (with safe defaults)
    try:
        busy_timeout_ms = int(config.get('database', 'busy_timeout_ms', fallback='30000'))
    except Exception:
        busy_timeout_ms = 30000
    try:
        cache_size_mb = int(config.get('database', 'cache_size_mb', fallback='64'))
    except Exception:
        cache_size_mb = 64
    try:
        mmap_size_mb = int(config.get('database', 'mmap_size_mb', fallback='64'))
    except Exception:
        mmap_size_mb = 64
    try:
        wal_autocheckpoint = int(config.get('database', 'wal_autocheckpoint', fallback='2000'))
    except Exception:
        wal_autocheckpoint = 2000

    # Temporarily disable sqlite3 implicit transactions to run WAL PRAGMA on an empty DB
    isolation_level = dbapi_connection.isolation_level
    dbapi_connection.isolation_level = None

    cursor = dbapi_connection.cursor()
    cursor.execute(f"PRAGMA busy_timeout={busy_timeout_ms}")
    for attempt in range(3):
        try:
            cursor.execute("PRAGMA journal_mode=WAL")
            result = cursor.fetchone()
            if result and result[0].lower() != 'wal':
                logger.warning(f"Failed to set WAL mode, got: {result[0]}")
            cursor.execute("PRAGMA synchronous=NORMAL")
            cursor.execute(f"PRAGMA cache_size=-{cache_size_mb * 1000}")
            cursor.execute("PRAGMA temp_store=MEMORY")
            cursor.execute(f"PRAGMA mmap_size={mmap_size_mb * 1024 * 1024}")
            cursor.execute(f"PRAGMA wal_autocheckpoint={wal_autocheckpoint}")
            break
        except Exception:
            if attempt < 2:
                time.sleep(0.5)
            else:
                raise
    cursor.close()

>>>>>>> feature/configurable-concurrency
    # Restore standard SQLAlchemy transaction management
    dbapi_connection.isolation_level = isolation_level

def create_dash(server):
    Base.metadata.create_all(bind=engine)

    """Create the Dash instance for this application"""
    app = Dash(
        name=__package__,
        server=server,
        suppress_callback_exceptions=True,
        **get_dash_args_from_flask_config(server.config),
    )

    # Update the Flask config a default "TITLE" and then with any new Dash
    # configuration parameters that might have been updated so that we can
    # access Dash config easily from anywhere in the project with Flask's
    # 'current_app'
    server.config.setdefault("TITLE", "Dash")
    server.config.update({key.upper(): val for key, val in app.config.items()})

    app.title = server.config["TITLE"]

    app.session = scoped_session(SessionLocal)

    if "SERVE_LOCALLY" in server.config:
        app.scripts.config.serve_locally = server.config["SERVE_LOCALLY"]
        app.css.config.serve_locally = server.config["SERVE_LOCALLY"]

    return app

def db_startup(app):
    # Fetch the first athlete record, if one exists
    dummy_athlete = app.session.query(athlete).first()
    
    # If the database is completely empty, create the baseline athlete
    if not dummy_athlete:
        dummy_athlete = athlete(name='Will')
        app.session.add(dummy_athlete)
    
    # Forcefully populate the required dummy values if they are missing
    if not dummy_athlete.birthday:
        dummy_athlete.birthday = datetime(1987, 10, 28)
    if not dummy_athlete.sex:
        dummy_athlete.sex = 'M'
    if dummy_athlete.weight_lbs is None:
        dummy_athlete.weight_lbs = 170
    if dummy_athlete.resting_hr is None:
        dummy_athlete.resting_hr = 50
    if dummy_athlete.run_ftp is None:
        dummy_athlete.run_ftp = 300
    if dummy_athlete.ride_ftp is None:
        dummy_athlete.ride_ftp = 300
        
    # Commit all changes to the database
    app.session.commit()

    # ... move on to the dbRefreshStatus logic ...
# def db_startup(app):
#     athlete_exists = True if len(app.session.query(athlete).all()) > 0 else False
#     # If no athlete created in db, create one
#     if not athlete_exists:
#         dummy_athlete = athlete(
#             name='Will', 
#             birthday=datetime(1987, 10, 28),
#             ride_ftp=300, 
#             run_ftp=300,
#             weight_lbs=170,
#             resting_hr=50,
#             sex='M'
#         )
#         app.session.add(dummy_athlete)
#         app.session.commit()

    # Check for refresh record AFTER the athlete commit
    db_refresh_record = True if len(app.session.query(dbRefreshStatus).all()) > 0 else False
    
    # Insert initial system load refresh record
    if not db_refresh_record:
        dummy_db_refresh_record = dbRefreshStatus(
            timestamp_utc=datetime.utcnow(),
            refresh_method='system',
            oura_status='System Startup',
            strava_status='System Startup',
            withings_status='System Startup',
            fitbod_status='System Startup')
        app.session.add(dummy_db_refresh_record)
        app.session.commit()

    # ... rest of the fitbod_muscles code stays the same ...

    # If fitbod_muslces table not populated create
    fitbod_muscles_table = True if len(app.session.query(fitbod_muscles).all()) > 0 else False
    if not fitbod_muscles_table:
        for exercise, muscle in [
            # Abs
            ('Crunch', 'Abs'),
            ('Russian Twist', 'Abs'),
            ('Leg Raise', 'Abs'),
            ('Flutter Kicks', 'Abs'),
            ('Sit-Up', 'Abs'),
            ('Side Bridge', 'Abs'),
            ('Scissor Kick', 'Abs'),
            ('Toe Touchers', 'Abs'),
            ('Pallof Press', 'Abs'),
            ('Cable Wood Chop', 'Abs'),
            ('Scissor Crossover Kick', 'Abs'),
            ('Plank', 'Abs'),
            ('Leg Pull-In', 'Abs'),
            ('Knee Raise', 'Abs'),
            ('Bird Dog', 'Abs'),
            ('Dead Bug', 'Abs'),
            ('Dip', 'Abs'),
            ('Abs', 'Abs'),

            # Arms
            ('Tricep', 'Triceps'),
            ('Bench Dips', 'Triceps'),
            ('Dumbbell Floor Press', 'Triceps'),
            ('Dumbbell Kickback', 'Triceps'),
            ('Skullcrusher', 'Triceps'),
            ('Skull Crusher', 'Triceps'),
            ('Tate', 'Triceps'),
            ('bell Curl', 'Biceps'),
            ('EZ-Bar Curl', 'Biceps'),
            ('Hammer Curl', 'Biceps'),
            ('Bicep', 'Biceps'),
            ('Preacher Curl', 'Biceps'),
            ('No Money', 'Biceps'),
            ('Concentration Curls', 'Biceps'),
            ('Zottman', 'Biceps'),
            ('bell Wrist Curl', 'Forearms'),

            # Chest
            ('Cable Crossover Fly', 'Chest'),
            ('Chest', 'Chest'),
            ('Bench Press', 'Chest'),
            ('Machine Fly', 'Chest'),
            ('Decline Fly', 'Chest'),
            ('Dumbbell Fly', 'Chest'),
            ('Push Up', 'Chest'),
            ('Pullover', 'Chest'),
            ('Floor Press', 'Chest'),
            ('Smith Machine Press', 'Chest'),
            ('Svend', 'Chest'),

            # Back
            ('Pulldown', 'Back'),
            ('Pull Down', 'Back'),
            ('Cable Row', 'Back'),
            ('Machine Row', 'Back'),
            ('Bent Over Row', 'Back'),
            ('bell Row', 'Back'),
            ('Pull Up', 'Back'),
            ('Pull-Up', 'Back'),
            ('Pullup', 'Back'),
            ('Chin Up', 'Back'),
            ('Renegade', 'Back'),
            ('Smith Machine Row', 'Back'),
            ('Shotgun Row', 'Back'),
            ('Landmine Row', 'Back'),
            ('Ball Slam', 'Back'),
            ('T-Bar', 'Back'),
            ('Back Extension', 'Lower Back'),
            ('Superman', 'Lower Back'),
            ('Leg Crossover', 'Lower Back'),
            ('Hyperextension', 'Lower Back'),

            ('Stiff-Legged Barbell Good Morning', 'Lower Back'),
            ('Hip', 'Glutes'),
            ('Step Up', 'Glutes'),
            ('Leg Lift', 'Glutes'),
            ('Glute', 'Glutes'),
            ('Rack Pulls', 'Glutes'),
            ('Pull Through', 'Glutes'),
            ('Leg Kickback', 'Glutes'),
            ('Balance Trainer Reverse Hyperextension', 'Glutes'),

            # Soulders
            ('Shoulder', 'Shoulders'),
            ('Lateral', 'Shoulders'),
            ('Face Pull', 'Shoulders'),
            ('Delt', 'Shoulders'),
            ('Elbows Out', 'Shoulders'),
            ('Back Fly', 'Shoulders'),
            ('One-Arm Upright Row', 'Shoulders'),
            ('Dumbbell Raise', 'Shoulders'),
            ('Plate Raise', 'Shoulders'),
            ('Arnold', 'Shoulders'),
            ('Iron Cross', 'Shoulders'),
            ('Push Press', 'Shoulders'),
            ('Landmine Press', 'Shoulders'),
            ('Overhead Press', 'Shoulders'),

            # Neck
            ('Upright Row', 'Traps'),
            ('Barbell Shrug', 'Traps'),
            ('Neck', 'Traps'),

            # Legs
            ('Leg Press', 'Quads'),
            ('Leg Extension', 'Quads'),
            ('Lunge', 'Quads'),
            ('Squat', 'Quads'),
            ('Tuck Jump', 'Quads'),
            ('Mountain Climber', 'Quads'),
            ('Burpee', 'Quads'),
            ('Power Clean', 'Quads'),
            ('Wall Sit', 'Quads'),
            ('bell Clean', 'Hamstrings'),
            ('Leg Curl', 'Hamstrings'),
            ('Deadlift', 'Hamstrings'),
            ('Dumbbell Snatch', 'Hamstrings'),
            ('Swing', 'Hamstrings'),
            ('Morning', 'Hamstrings'),
            ('Calf Raise', 'Calves'),
            ('Heel Press', 'Calves'),
            ('Thigh Abductor', 'Abductors'),
            ('Clam', 'Abductors'),
            ('Thigh Adductor', 'Adductors')
        ]:
            app.session.add(fitbod_muscles(exercise=exercise, muscle=muscle))
        app.session.commit()
    app.session.remove()