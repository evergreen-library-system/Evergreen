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
# -----------------------------------------------------------------------

from osrf.utils import *
from osrf.const import *
from osrf.ex import *

# global settings config object
__conifg = None

def osrfSettingsValue(path, idx=0):
	global __config
	val = osrfObjectFindPath(__config, path, idx)
	if not val:
		raise osrfConfigException("Config value not found: " + path)
	return val


def osrfLoadSettings(hostname):
	global __config

	from osrf.system import osrfConnect
	from osrf.ses import osrfClientSession

	ses = osrfClientSession(OSRF_APP_SETTINGS)
	req = ses.request(OSRF_METHOD_GET_HOST_CONFIG, hostname)
	resp = req.recv(timeout=30)
	__config = resp.content()
	req.cleanup()
	ses.cleanup()

