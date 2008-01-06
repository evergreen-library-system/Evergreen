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

import osrf.log
from osrf.system import connect
from oils.utils.idl import IDLParser
from oils.utils.csedit import oilsLoadCSEditor

def oilsConnect(config, configContext):
	"""Connects to the opensrf network,  parses the IDL file, and loads the CSEditor"""
	osrf.log.log_info("oilsConnect(): connecting with config %s" % config)
	connect(config, configContext)
	IDLParser.parse()
	oilsLoadCSEditor()
