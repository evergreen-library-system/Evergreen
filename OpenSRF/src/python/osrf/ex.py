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
# This modules define the exception classes.  In general, an 
# exception is little more than a name.
# -----------------------------------------------------------------------

class osrfException(Exception):
	"""Root class for exceptions."""
	def __init__(self, info=None):
		self.info = info;
	def __str__(self):
		return self.info


class osrfNetworkException(osrfException):
	def __str__(self):
		str = "\nUnable to communicate with the OpenSRF network"
		if self.info:
			str = str + '\n' + repr(self.info)
		return str

class osrfProtocolException(osrfException):
	"""Raised when something happens during opensrf network stack processing."""
	pass

class osrfServiceException(osrfException):
	"""Raised when there was an error communicating with a remote service."""
	pass

class osrfConfigException(osrfException):
	"""Invalid config option requested."""
	pass

class osrfNetworkObjectException(osrfException):
	pass
	
class osrfJSONParseException(osrfException):
	"""Raised when a JSON parsing error occurs."""
	pass



