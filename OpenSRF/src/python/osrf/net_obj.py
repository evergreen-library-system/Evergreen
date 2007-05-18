# -----------------------------------------------------------------------
# Copyright (C) 2007  Georgia Public Library Service
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


JSON_PAYLOAD_KEY = '__p'
JSON_CLASS_KEY = '__c'

class osrfNetworkObject(object):
	"""Base class for serializable network objects."""
	def getData(self):
		"""Returns a dict of data contained by this object"""
		return self.data


class __unknown(osrfNetworkObject):
	"""Default class for un-registered network objects."""
	def __init__(self, data=None):
		self.data = data

setattr(__unknown,'__keys', [])
setattr(osrfNetworkObject,'__unknown', __unknown)


def osrfNetworkRegisterHint(hint, keys, type='hash'):
	"""Register a network hint.  
	
		This creates a new class at osrfNetworkObject.<hint> with 
		methods for accessing/mutating the object's data.  
		Method names will match the names found in the keys array

		hint - The hint name to encode with the object
		type - The data container type.  
		keys - An array of data keys.  If type is an 'array', the order of
		the keys will determine how the data is accessed
	"""

    #
    # XXX Surely there is a cleaner way to accomplish this via 
    # the PythonAPI
    #

	estr = "class %s(osrfNetworkObject):\n" % hint
	estr += "\tdef __init__(self, data=None):\n"
	estr += "\t\tself.data = data\n"
	estr += "\t\tif data:\n"

	if type == 'hash': 
		estr += "\t\t\tpass\n"
	else:
		# we have to make sure the array is large enough	
		estr += "\t\t\twhile len(data) < %d:\n" % len(keys)
		estr += "\t\t\t\tdata.append(None)\n"

	estr += "\t\telse:\n"

	if type == 'array':
		estr += "\t\t\tself.data = []\n"
		estr += "\t\t\tfor i in range(%s):\n" % len(keys)
		estr += "\t\t\t\tself.data.append(None)\n"
		for i in range(len(keys)):
			estr +=	"\tdef %s(self, *args):\n"\
						"\t\tif len(args) != 0:\n"\
						"\t\t\tself.data[%s] = args[0]\n"\
						"\t\treturn self.data[%s]\n" % (keys[i], i, i)

	if type == 'hash':
		estr += "\t\t\tself.data = {}\n"
		estr += "\t\t\tfor i in %s:\n" % str(keys)
		estr += "\t\t\t\tself.data[i] = None\n"
		for i in keys:
			estr +=	"\tdef %s(self, *args):\n"\
						"\t\tif len(args) != 0:\n"\
						"\t\t\tself.data['%s'] = args[0]\n"\
						"\t\tval = None\n"\
						"\t\ttry: val = self.data['%s']\n"\
						"\t\texcept: return None\n"\
						"\t\treturn val\n" % (i, i, i)

	estr += "setattr(osrfNetworkObject, '%s', %s)\n" % (hint,hint)
	estr += "setattr(osrfNetworkObject.%s, '__keys', keys)" % hint
	exec(estr)
	
		

# -------------------------------------------------------------------
# Define the custom object parsing behavior 
# -------------------------------------------------------------------
def parseNetObject(obj):
	hint = None
	islist = False
	try:
		hint = obj[JSON_CLASS_KEY]
		obj = obj[JSON_PAYLOAD_KEY]
	except: pass
	if isinstance(obj,list):
		islist = True
		for i in range(len(obj)):
			obj[i] = parseNetObject(obj[i])
	else: 
		if isinstance(obj,dict):
			for k,v in obj.iteritems():
				obj[k] = parseNetObject(v)

	if hint: # Now, "bless" the object into an osrfNetworkObject
		estr = 'obj = osrfNetworkObject.%s(obj)' % hint
		try:
			exec(estr)
		except AttributeError:
			# this object has not been registered, shove it into the default container
			obj = osrfNetworkObject.__unknown(obj)

	return obj;



	
