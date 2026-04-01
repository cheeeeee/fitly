from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool
<<<<<<< HEAD

SQLALCHEMY_DATABASE_URL = 'sqlite:///./config/fitness.db'
=======
import os

# Allow db path to be overridden via env var or config (cloud-native: mount a PVC at any path)
# Priority: env FITLY_DATABASE_DB_PATH > config [database] db_path > default
_db_path = os.environ.get('FITLY_DATABASE_DB_PATH')
if not _db_path:
    try:
        import configparser as _cp
        _cfg = _cp.ConfigParser()
        _cfg.read('./config/config.ini')
        _db_path = _cfg.get('database', 'db_path')
    except Exception:
        pass
if not _db_path:
    # Try YAML config
    try:
        import yaml as _yaml
        with open('./config/config.yaml') as _f:
            _ydata = _yaml.safe_load(_f) or {}
        _db_path = str(_ydata.get('database', {}).get('db_path', ''))
    except Exception:
        pass
if not _db_path:
    _db_path = './config/fitness.db'

# Connection timeout: how long SQLite waits before raising OperationalError
_timeout = int(os.environ.get('FITLY_DATABASE_CONNECTION_TIMEOUT_S', '30'))

SQLALCHEMY_DATABASE_URL = f'sqlite:///{_db_path}'
>>>>>>> feature/configurable-concurrency

# NullPool is recommended for SQLite with multiple workers/processes.
# It creates a fresh connection per use and closes it immediately after,
# avoiding the pool contention that causes 'database is locked' errors.
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
<<<<<<< HEAD
    connect_args={"check_same_thread": False, "timeout": 30},
=======
    connect_args={"check_same_thread": False, "timeout": _timeout},
>>>>>>> feature/configurable-concurrency
    poolclass=NullPool,
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()
<<<<<<< HEAD
=======

>>>>>>> feature/configurable-concurrency
