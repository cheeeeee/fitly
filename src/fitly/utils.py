import inspect
from functools import wraps
from urllib.parse import parse_qs

import dash
import dash_html_components as html
import dash_bootstrap_components as dbc
from dash.dependencies import Output, Input
from dash.exceptions import PreventUpdate
from dash.development.base_component import Component
from flask import current_app as server
from werkzeug.datastructures import MultiDict

from .pages import page_not_found
from .exceptions import InvalidLayoutError


def component(func):
    """Decorator to help vanilla functions as pseudo Dash Components"""

    @wraps(func)
    def function_wrapper(*args, **kwargs):
        # remove className and style args from input kwargs so the component
        # function does not have to worry about clobbering them.
        className = kwargs.pop("className", None)
        style = kwargs.pop("style", None)

        # call the component function and get the result
        result = func(*args, **kwargs)

        # now restore the initial classes and styles by adding them
        # to any values the component introduced

        if className is not None:
            if hasattr(result, "className"):
                result.className = f"{className} {result.className}"
            else:
                result.className = className

        if style is not None:
            if hasattr(result, "style"):
                result.style = style.update(result.style)
            else:
                result.style = style

        return result

    return function_wrapper


class DashRouter:
    """A URL Router for Dash multipage apps"""

    def __init__(self, app, urls):
        """Initialise the router.

        Params:
        app:   A Dash instance to associate the router with.
        urls:  Ordered iterable of routes: tuples of (route, layout). 'route' is a
               string corresponding to the URL path of the route (will be prefixed
               with Dash's 'routes_pathname_prefix' and 'layout' is a Dash Component
               or callable that returns a Dash Component. The callable will also have
               any URL query parameters passed in as keyword arguments.
        """
        self.routes = {get_url(route): layout for route, layout in urls}

        @app.callback(
            Output(app.server.config["CONTENT_CONTAINER_ID"], "children"),
            [
                Input(server.config["LOCATION_COMPONENT_ID"], "pathname"),
                Input(server.config["LOCATION_COMPONENT_ID"], "search"),
            ],
        )
        def router_callback(pathname, search):
            """The router"""
            if pathname is None:
                raise PreventUpdate("Ignoring first Location.pathname callback")

            page = self.routes.get(pathname, None)

            if page is None:
                layout = page_not_found(pathname)
            elif isinstance(page, Component):
                layout = page
            elif callable(page):
                kwargs = MultiDict(parse_qs(search.lstrip("?")))
                layout = page(**kwargs)
                if not isinstance(layout, Component):
                    msg = (
                        "Layout function must return a Dash Component.\n\n"
                        f"Function {page.__name__} from module {page.__module__} "
                        f"returned value of type {type(layout)} instead."
                    )
                    raise InvalidLayoutError(msg)
            else:
                msg = (
                    "Page layouts must be a Dash Component or a callable that "
                    f"returns a Dash Component. Received value of type {type(page)}."
                )
                raise InvalidLayoutError(msg)
            return layout


class DashNavBar:
    """A Dash navbar for multipage apps"""

    def __init__(self, app, nav_items):
        """Initialise the navbar.

        Params:
        app:        A Dash instance to associate the router with.

        nav_items:  Ordered iterable of navbar items: tuples of `(route, display)`,
                    where `route` is a string corresponding to path of the route
                    (will be prefixed with Dash's 'routes_pathname_prefix') and
                    'display' is a valid value for the `children` keyword argument
                    for a Dash component (ie a Dash Component or a string).
        """
        self.nav_items = nav_items

        @app.callback(
            Output(server.config["NAVBAR_CONTAINER_ID"], "children"),
            [Input(server.config["LOCATION_COMPONENT_ID"], "pathname")],
        )
        def update_nav_callback(pathname):
            """Create the navbar with the current page set to active"""
            if pathname is None:
                # pathname is None on the first load of the app; ignore this
                raise PreventUpdate("Ignoring first Location.pathname callback")
            return self.make_nav(pathname)

    @component
    def make_nav(self, current_path, **kwargs):
        nav_items = []
        route_prefix = server.config["ROUTES_PATHNAME_PREFIX"]
        for i, (path, text) in enumerate(self.nav_items):
            href = get_url(path)
            active = (current_path == href) or (i == 0 and current_path == route_prefix)
            nav_item = dbc.NavItem(dbc.NavLink(text, href=href, active=active))
            nav_items.append(nav_item)
        return html.Ul(nav_items, className="navbar-nav", **kwargs)


def get_dash_args_from_flask_config(config):
    """Get a dict of Dash params that were specified """
    # all arg names less 'self'
    dash_args = set(inspect.getfullargspec(dash.Dash.__init__).args[1:])
    return {key.lower(): val for key, val in config.items() if key.lower() in dash_args}


def get_url(path):
    """Expands an internal URL to include prefix the app is mounted at"""
    return f"{server.config['ROUTES_PATHNAME_PREFIX']}{path}"


## Fitly specific Util ##


import json
from datetime import timedelta
import configparser
import os
import pytz


class FitlyConfig:
    """
    Configuration loader that supports three sources, in priority order:

      1. Environment variables  FITLY_<SECTION>_<KEY>  (uppercase)
         Example: FITLY_STRAVA_CLIENT_ID=abc123

      2. config/config.yaml  (if the file exists)

      3. config/config.ini   (classic INI fallback)

    Exposes the same .get(section, key) interface as configparser so
    all existing callers work without modification.
    """

    def __init__(self):
        self._yaml_data = {}
        self._ini = configparser.ConfigParser()
        self._using_yaml = False

        yaml_path = './config/config.yaml'
        ini_path = './config/config.ini'

        if os.path.isfile(yaml_path):
            try:
                import yaml
                with open(yaml_path, 'r') as f:
                    self._yaml_data = yaml.safe_load(f) or {}
                self._using_yaml = True
            except Exception as e:
                # YAML load failed — fall back to INI silently
                self._using_yaml = False

        if not self._using_yaml:
            self._ini.read(ini_path)

    def get(self, section, key, fallback=''):
        """Return value from env var > YAML > INI, or fallback if missing."""
        # 1. Environment variable override
        env_key = f'FITLY_{section.upper()}_{key.upper()}'
        env_val = os.environ.get(env_key)
        if env_val is not None:
            return env_val

        # 2. YAML
        if self._using_yaml:
            section_data = self._yaml_data.get(section, {})
            if isinstance(section_data, dict) and key in section_data:
                val = section_data[key]
                return str(val) if val is not None else fallback
            return fallback

        # 3. INI
        try:
            return self._ini.get(section, key)
        except (configparser.NoSectionError, configparser.NoOptionError):
            return fallback

    def set(self, section, key, value):
        """Update a value in memory (used by update_config)."""
        if self._using_yaml:
            if section not in self._yaml_data:
                self._yaml_data[section] = {}
            self._yaml_data[section][key] = value
        else:
            if not self._ini.has_section(section):
                self._ini.add_section(section)
            self._ini.set(section, key, value)

    def write_to_file(self):
        """Persist in-memory changes back to the active config file."""
        if self._using_yaml:
            import yaml
            with open('./config/config.yaml', 'w') as f:
                yaml.dump(self._yaml_data, f, default_flow_style=False, allow_unicode=True)
        else:
            with open('./config/config.ini', 'w') as f:
                self._ini.write(f)


config = FitlyConfig()

local_tz = pytz.timezone(config.get('timezone', 'timezone'))

oura_credentials_supplied = True if config.get('oura', 'client_id').strip() and config.get('oura',
                                                                                           'client_secret').strip() else False
peloton_credentials_supplied = True if config.get('peloton', 'username').strip() and config.get('peloton',
                                                                                                'password').strip() else False
withings_credentials_supplied = True if config.get('withings', 'client_id').strip() and config.get('withings',
                                                                                                   'client_secret').strip() else False

stryd_credentials_supplied = True if config.get('stryd', 'username').strip() and config.get('stryd',
                                                                                            'password').strip() else False

nextcloud_credentials_supplied = True if config.get('nextcloud', 'username').strip() and config.get('nextcloud',
                                                                                                    'password') and config.get(
    'nextcloud', 'fitbod_path').strip() else False

spotify_credentials_supplied = True if config.get('spotify', 'client_id').strip() and config.get('spotify',
                                                                                           'client_secret').strip() else False

A_OK_HTTP_CODES = [
    200,
    207
]

A_ERROR_HTTP_CODES = {
    400: "Request was invalid",
    401: "Invalid API key",
    403: "Bad OAuth scope",
    404: "Selector did not match any lights",
    422: "Missing or malformed parameters",
    426: "HTTP is required to perform transaction",
    # see http://api.developer.lifx.com/v1/docs/rate-limits
    429: "Rate limit exceeded",
    500: "API currently unavailable",
    502: "API currently unavailable",
    503: "API currently unavailable",
    523: "API currently unavailable"
}


##############################
# Main
##############################
def parse_response(response):
    """Parse JSON API response, return object."""
    parsed_response = json.loads(response.text)
    return parsed_response


def handle_error(response):
    """Raise appropriate exceptions if necessary."""
    status_code = response.status_code

    if status_code not in A_OK_HTTP_CODES:
        logError(response)
        error_explanation = A_ERROR_HTTP_CODES.get(status_code)
        raise_error = "{}: {}".format(status_code, error_explanation)
        raise Exception(raise_error)
    else:
        return True


def full_url(base, suffix):
    return base + suffix


def getResponse(session, url, payload, cookieDict):
    response = session.get(url, json=payload, cookies=cookieDict)
    parsed_response = parse_response(response)
    handle_error(response)

    return parsed_response


def logError(response):
    request = response.request
    url = request.url
    headers = request.headers


def calc_next_saturday(d):
    return d.date() + timedelta((12 - d.weekday()) % 7)


def calc_prev_sunday(d):
    return calc_next_saturday(d) - timedelta(days=6)


def update_config(section, parameter, value):
    config.set(section, parameter, value)
    config.write_to_file()


def utc_to_local(utc_dt):
    local_dt = utc_dt.replace(tzinfo=pytz.utc).astimezone(local_tz)
    return local_tz.normalize(local_dt).replace(tzinfo=None)  # .tz_localize(None)  # .normalize might be unnecessary
