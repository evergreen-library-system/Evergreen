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

from osrf.log import *
from osrf.system import osrfConnect
from oils.utils.idl import oilsParseIDL
from oils.utils.csedit import oilsLoadCSEditor

def oilsConnect(config):
	"""Connects to the opensrf network,  parses the IDL file, and loads the CSEditor"""
	osrfLogInfo("oilsConnect(): connecting with config %s" % config)
	osrfConnect(config)
	oilsParseIDL()
	oilsLoadCSEditor()
