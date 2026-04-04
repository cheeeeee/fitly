"""
Centralized unit conversion module for Fitly.

All data is stored internally in imperial units (miles, mph, feet, lbs, °F).
This module provides display-layer conversion functions that respect the global
``unit_system`` setting from config.yaml (or the FITLY_SETTINGS_UNIT_SYSTEM
environment variable).

Usage::

    from fitly.units import distance, distance_label, is_metric

    display_value = distance(row['distance'])      # miles → km if metric
    label = distance_label()                        # 'km' or 'mi'
"""

from .utils import config

# ── Conversion constants ────────────────────────────────────────────────────
_MI_TO_KM = 1.609344
_FT_TO_M = 0.3048
_LBS_TO_KG = 0.453592
_MPH_TO_KPH = 1.609344
# Oura provides temperature_delta in °C; the app historically converts to °F
_CELSIUS_TO_FAHRENHEIT_FACTOR = 9.0 / 5.0


# ── System detection ────────────────────────────────────────────────────────

def get_unit_system():
    """Return 'imperial' or 'metric' from config."""
    val = config.get('settings', 'unit_system', fallback='imperial').strip().lower()
    return val if val in ('imperial', 'metric') else 'imperial'


def is_metric():
    """Return True if the user has selected the metric system."""
    return get_unit_system() == 'metric'


def set_unit_system(system):
    """Persist the unit system choice to config.yaml.

    Parameters
    ----------
    system : str
        Either 'imperial' or 'metric'.
    """
    system = system.strip().lower()
    if system not in ('imperial', 'metric'):
        raise ValueError(f"Invalid unit system: {system!r}")
    
    config.set('settings', 'unit_system', system)
    try:
        config.write_to_file()
    except (PermissionError, OSError) as e:
        import logging
        logging.getLogger(__name__).warning(
            "Unable to persist unit system to config file. Applied for current session only. Error: %s", e
        )


# ── Distance (miles ↔ km) ───────────────────────────────────────────────────

def distance(miles):
    """Convert stored miles to display unit."""
    if miles is None:
        return None
    return miles * _MI_TO_KM if is_metric() else miles


def distance_label():
    """Return the appropriate distance abbreviation."""
    return 'km' if is_metric() else 'mi'


# ── Speed (mph ↔ km/h) ─────────────────────────────────────────────────────

def speed(mph):
    """Convert stored mph to display unit."""
    if mph is None:
        return None
    return mph * _MPH_TO_KPH if is_metric() else mph


def speed_label():
    """Return the appropriate speed abbreviation."""
    return 'km/h' if is_metric() else 'mph'


# ── Pace (mph → min:sec per mi or km) ──────────────────────────────────────

def pace(mph):
    """Convert stored mph to pace string (min:sec/mi or min:sec/km).

    Returns a formatted string like '8:30' or None if speed is zero/None.
    """
    if mph is None or mph <= 0:
        return None
    # minutes per mile
    min_per_mile = 60.0 / mph
    if is_metric():
        min_per_unit = min_per_mile / _MI_TO_KM  # min/km is shorter than min/mi
    else:
        min_per_unit = min_per_mile
    minutes = int(min_per_unit)
    seconds = int(round((min_per_unit - minutes) * 60))
    if seconds == 60:
        minutes += 1
        seconds = 0
    return f'{minutes}:{seconds:02d}'


def pace_label():
    """Return the appropriate pace unit label."""
    return 'min/km' if is_metric() else 'min/mi'


# ── Elevation (feet ↔ metres) ───────────────────────────────────────────────

def elevation(feet):
    """Convert stored feet to display unit."""
    if feet is None:
        return None
    return feet * _FT_TO_M if is_metric() else feet


def elevation_label():
    """Return the appropriate elevation abbreviation."""
    return 'm' if is_metric() else 'ft'


# ── Weight (lbs ↔ kg) ──────────────────────────────────────────────────────

def weight(lbs):
    """Convert stored lbs to display unit."""
    if lbs is None:
        return None
    return lbs * _LBS_TO_KG if is_metric() else lbs


def weight_label():
    """Return the appropriate weight abbreviation."""
    return 'kg' if is_metric() else 'lbs'


# ── Temperature delta (°C ↔ °F) ────────────────────────────────────────────
# Oura stores temperature_delta in °C.  The app historically converted to °F.
# In metric mode we show °C as-is; in imperial mode we convert the delta.

def temperature_delta(celsius_delta):
    """Convert a temperature *delta* for display.

    Note: this is a delta, not an absolute temperature, so no +32 offset.
    """
    if celsius_delta is None:
        return None
    return celsius_delta * _CELSIUS_TO_FAHRENHEIT_FACTOR if not is_metric() else celsius_delta


def temperature_label():
    """Return the appropriate temperature unit."""
    return '°C' if is_metric() else '°F'
