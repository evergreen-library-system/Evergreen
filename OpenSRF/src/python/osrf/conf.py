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
from osrf.ex import *

class osrfConfig(object):
	"""Loads and parses the bootstrap config file"""

	config = None

	def __init__(self, file=None):
		self.file = file	
		self.data = {}

	def parseConfig(self,file=None):
		self.data = osrfXMLFileToObject(file or self.file)
		osrfConfig.config = self
	
	def getValue(self, key, idx=None):
		val = osrfObjectFindPath(self.data, key, idx)
		if not val:
			raise osrfConfigException("Config value not found: " + key)
		return val


def osrfConfigValue(key, idx=None):
	"""Returns a bootstrap config value.

	key -- A string representing the path to the value in the config object
		e.g.  "domains.domain", "username"
	idx -- Optional array index if the searched value is an array member
	"""
	return osrfConfig.config.getValue(key, idx)
				
