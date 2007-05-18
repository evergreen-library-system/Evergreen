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


import simplejson, types 
from osrf.net_obj import *

JSON_PAYLOAD_KEY = '__p'
JSON_CLASS_KEY = '__c'

#class osrfNetworkObject(object):
#	"""Base class for serializable network objects."""
#	def getData(self):
#		"""Returns a dict of data contained by this object"""
#		return self.data
#
#
#class __unknown(osrfNetworkObject):
#	"""Default class for un-registered network objects."""
#	def __init__(self, data=None):
#		self.data = data
#
#setattr(__unknown,'__keys', [])
#setattr(osrfNetworkObject,'__unknown', __unknown)
#
#
#def osrfNetworkRegisterHint(hint, keys, type='hash'):
#	"""Register a network hint.  
#	
#		This creates a new class at osrfNetworkObject.<hint> with 
#		methods for accessing/mutating the object's data.  
#		Method names will match the names found in the keys array
#
#		hint - The hint name to encode with the object
#		type - The data container type.  
#		keys - An array of data keys.  If type is an 'array', the order of
#		the keys will determine how the data is accessed
#	"""
#
#	estr = "class %s(osrfNetworkObject):\n" % hint
#	estr += "\tdef __init__(self, data=None):\n"
#	estr += "\t\tself.data = data\n"
#	estr += "\t\tif data:\n"
#
#	if type == 'hash': 
#		estr += "\t\t\tpass\n"
#	else:
#		# we have to make sure the array is large enough	
#		estr += "\t\t\twhile len(data) < %d:\n" % len(keys)
#		estr += "\t\t\t\tdata.append(None)\n"
#
#	estr += "\t\telse:\n"
#
#	if type == 'array':
#		estr += "\t\t\tself.data = []\n"
#		estr += "\t\t\tfor i in range(%s):\n" % len(keys)
#		estr += "\t\t\t\tself.data.append(None)\n"
#		for i in range(len(keys)):
#			estr +=	"\tdef %s(self, *args):\n"\
#						"\t\tif len(args) != 0:\n"\
#						"\t\t\tself.data[%s] = args[0]\n"\
#						"\t\treturn self.data[%s]\n" % (keys[i], i, i)
#
#	if type == 'hash':
#		estr += "\t\t\tself.data = {}\n"
#		estr += "\t\t\tfor i in %s:\n" % str(keys)
#		estr += "\t\t\t\tself.data[i] = None\n"
#		for i in keys:
#			estr +=	"\tdef %s(self, *args):\n"\
#						"\t\tif len(args) != 0:\n"\
#						"\t\t\tself.data['%s'] = args[0]\n"\
#						"\t\tval = None\n"\
#						"\t\ttry: val = self.data['%s']\n"\
#						"\t\texcept: return None\n"\
#						"\t\treturn val\n" % (i, i, i)
#
#	estr += "setattr(osrfNetworkObject, '%s', %s)\n" % (hint,hint)
#	estr += "setattr(osrfNetworkObject.%s, '__keys', keys)" % hint
#	exec(estr)
#	
#		
#
## -------------------------------------------------------------------
## Define the custom object parsing behavior 
## -------------------------------------------------------------------
#def __parseNetObject(obj):
#	hint = None
#	islist = False
#	try:
#		hint = obj[JSON_CLASS_KEY]
#		obj = obj[JSON_PAYLOAD_KEY]
#	except: pass
#	if isinstance(obj,list):
#		islist = True
#		for i in range(len(obj)):
#			obj[i] = __parseNetObject(obj[i])
#	else: 
#		if isinstance(obj,dict):
#			for k,v in obj.iteritems():
#				obj[k] = __parseNetObject(v)
#
#	if hint: # Now, "bless" the object into an osrfNetworkObject
#		estr = 'obj = osrfNetworkObject.%s(obj)' % hint
#		try:
#			exec(estr)
#		except AttributeError:
#			# this object has not been registered, shove it into the default container
#			obj = osrfNetworkObject.__unknown(obj)
#
#	return obj;
#
#
## -------------------------------------------------------------------
# Define the custom object encoding behavior 
# -------------------------------------------------------------------

class osrfJSONNetworkEncoder(simplejson.JSONEncoder):
	def default(self, obj):
		if isinstance(obj, osrfNetworkObject):
			return { 
				JSON_CLASS_KEY: obj.__class__.__name__,
				JSON_PAYLOAD_KEY: self.default(obj.getData())
			}	
		return obj


def osrfObjectToJSON(obj):
	"""Turns a python object into a wrapped JSON object"""
	return simplejson.dumps(obj, cls=osrfJSONNetworkEncoder)


def osrfJSONToObject(json):
	"""Turns a JSON string into python objects"""
	obj = simplejson.loads(json)
	return parseNetObject(obj)

def osrfParseJSONRaw(json):
	"""Parses JSON the old fashioned way."""
	return simplejson.loads(json)

def osrfToJSONRaw(obj):
	"""Stringifies an object as JSON with no additional logic."""
	return simplejson.dumps(obj)

def __tabs(t):
	r=''
	for i in range(t): r += '   '
	return r

def osrfDebugNetworkObject(obj, t=1):
	"""Returns a debug string for a given object.

	If it's an osrfNetworkObject and has registered keys, key/value p
	pairs are returned.  Otherwise formatted JSON is returned"""

	s = ''
	if isinstance(obj, osrfNetworkObject) and len(obj.__keys):
		obj.__keys.sort()

		for k in obj.__keys:

			key = k
			while len(key) < 24: key += '.' # pad the names to make the values line up somewhat
			val = getattr(obj, k)()

			subobj = val and not (isinstance(val,unicode) or \
					isinstance(val, int) or isinstance(val, float) or isinstance(val, long))


			s += __tabs(t) + key + ' = '

			if subobj:
				s += '\n'
				val = osrfDebugNetworkObject(val, t+1)

			s += str(val)

			if not subobj: s += '\n'

	else:
		s = osrfFormatJSON(osrfObjectToJSON(obj))
	return s

def osrfFormatJSON(json):
	"""JSON pretty-printer"""
	r = ''
	t = 0
	instring = False
	inescape = False
	done = False

	for c in json:

		done = False
		if (c == '{' or c == '[') and not instring:
			t += 1
			r += c + '\n' + __tabs(t)
			done = True

		if (c == '}' or c == ']') and not instring:
			t -= 1
			r += '\n' + __tabs(t) + c
			done = True

		if c == ',' and not instring:
			r += c + '\n' + __tabs(t)
			done = True

		if c == '"' and not inescape:
			instring = not instring

		if inescape: 
			inescape = False

		if c == '\\':
			inescape = True

		if not done:
			r += c

	return r

	
