# Variables defined in this file will be passed to the 'config' attribute of the
# Flask instance used by the Dash app. Any values corresponding to Dash
# keword arguments will be passed They must be in UPPER CASE in order to take effect. For more information see
# http://flask.pocoo.org/docs/config.

# Your App's title. The value of this parameter will be propagated into
# `app.title`
TITLE = "Fit.ly"

# The value of this parameter will be propagated into both
# `app.scripts.config.serve_locally` and `app.css.config.serve_locally`
SERVE_LOCALLY = True

#
# Dash.__init__ keyword arguments
#

# URL prefix for client-side requests and client-side requests. If not None,
# must begin and end with a '/'.
REQUESTS_PATHNAME_PREFIX = None

# URL prefix for server-side routes. If not None, must begin and end with a
# '/'.
ROUTES_PATHNAME_PREFIX = None

# Externally hosted CSS files go in here. If you want to use Bootstrap from a
# CDN, Dash Bootstrap Components contains links to bootstrapcdn:
#
# import dash_bootstrap_components as dbc
# EXTERNAL_STYLESHEETS = [dbc.themes.BOOTSTRAP]
#
# or if you want to use a Bootswatch theme:
#
import dash_bootstrap_components as dbc

EXTERNAL_STYLESHEETS = [dbc.themes.SLATE]

META_TAGS = [{"name": "viewport", "content": "width=device-width, initial-scale=1"}]

# Externally hosted Javascript files go in here.
EXTERNAL_SCRIPTS = []

#
# Layout config
#

# The ID of the dcc.Location component used for multi-page apps
LOCATION_COMPONENT_ID = "dash-location"

# The ID of the element used to inject each page of the multi-page app into
CONTENT_CONTAINER_ID = "page-content"

# The ID of the element used to inject the navbar items into
NAVBAR_CONTAINER_ID = "navbar-items"

import os

# --- SECURITY & SESSION CONFIGURATION ---

# 1. Cryptographic Key (MUST be complex and secret)
# It tries to read from an environment variable first. If none exists, it uses the fallback.
# WARNING: Change the fallback string below to a random 32+ character password!
SECRET_KEY = os.environ.get('FITLY_SECRET_KEY', '0c03024bd4ba5e86da7491f8ad83d21a0c902c0a9e1086482b132a60ff327048')

# 2. XSS Protection (Cross-Site Scripting)
# Prevents malicious JavaScript injections from stealing your admin cookie.
SESSION_COOKIE_HTTPONLY = True

# 3. CSRF Protection (Cross-Site Request Forgery)
# Prevents other websites from tricking your browser into sending the admin cookie.
SESSION_COOKIE_SAMESITE = 'Lax'

# 4. HTTPS Enforcement
# Set to False because you are accessing the Pi via a local IP (HTTP).
# If you ever put this behind a domain name with SSL (HTTPS), change this to True immediately.
SESSION_COOKIE_SECURE = False
