# -----------------------------------------------------------------------
# Copyright (C) 2007  Georgia Public Library Service
# Bill Erickson <billserickson@gmail.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
#
# Collection of global constants
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------
# log levels
# -----------------------------------------------------------------------
OSRF_LOG_ERR	= 1
OSRF_LOG_WARN	= 2
OSRF_LOG_INFO	= 3
OSRF_LOG_DEBUG = 4
OSRF_LOG_INTERNAL = 5

# -----------------------------------------------------------------------
# Session states
# -----------------------------------------------------------------------
OSRF_APP_SESSION_CONNECTED    = 0
OSRF_APP_SESSION_CONNECTING   = 1
OSRF_APP_SESSION_DISCONNECTED = 2

# -----------------------------------------------------------------------
# OpenSRF message types
# -----------------------------------------------------------------------
OSRF_MESSAGE_TYPE_REQUEST = 'REQUEST'
OSRF_MESSAGE_TYPE_STATUS  = 'STATUS' 
OSRF_MESSAGE_TYPE_RESULT  = 'RESULT'
OSRF_MESSAGE_TYPE_CONNECT = 'CONNECT'
OSRF_MESSAGE_TYPE_DISCONNECT = 'DISCONNECT'

# -----------------------------------------------------------------------
# OpenSRF message statuses
# -----------------------------------------------------------------------
OSRF_STATUS_CONTINUE                 = 100
OSRF_STATUS_OK                       = 200
OSRF_STATUS_ACCEPTED                 = 202
OSRF_STATUS_COMPLETE                 = 205
OSRF_STATUS_REDIRECTED               = 307
OSRF_STATUS_BADREQUEST               = 400
OSRF_STATUS_UNAUTHORIZED             = 401
OSRF_STATUS_FORBIDDEN                = 403
OSRF_STATUS_NOTFOUND                 = 404
OSRF_STATUS_NOTALLOWED               = 405
OSRF_STATUS_TIMEOUT                  = 408
OSRF_STATUS_EXPFAILED                = 417
OSRF_STATUS_INTERNALSERVERERROR      = 500
OSRF_STATUS_NOTIMPLEMENTED           = 501
OSRF_STATUS_VERSIONNOTSUPPORTED      = 505


# -----------------------------------------------------------------------
# Some well-known services
# -----------------------------------------------------------------------
OSRF_APP_SETTINGS = 'opensrf.settings'
OSRF_APP_MATH = 'opensrf.math'


# where do we find the settings config
OSRF_METHOD_GET_HOST_CONFIG = 'opensrf.settings.host_config.get'


