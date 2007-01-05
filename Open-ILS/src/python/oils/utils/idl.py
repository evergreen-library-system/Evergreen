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

from osrf.json import *
from osrf.log import *
from osrf.set import osrfSettingsValue

import sys, libxml2, osrf.conf, string
from oils.const import OILS_NS_OBJ, OILS_NS_PERSIST, OILS_NS_REPORTER

__global_parser = None

def oilsParseIDL():
	global __global_parser
	idlParser = oilsIDLParser();
	idlParser.setIDL(osrfSettingsValue('IDL'))
	idlParser.parseIDL()
	__global_parser = idlParser

def oilsGetIDLParser():
	global __global_parser
	return __global_parser

class oilsIDLParser(object):

	def __init__(self):
		self.IDLObject = {}

	def setIDL(self, file):
		osrfLogInfo("setting IDL file to " + file)
		self.idlFile = file

	def parseIDL(self):
		"""Parses the IDL file and builds class objects"""

		doc	= libxml2.parseFile(self.idlFile)
		root	= doc.children
		child = root.children

		while child:
		
			if child.type == 'element':
		
				# -----------------------------------------------------------------------
				# 'child' is the main class node for a fieldmapper class.
				# It has 'fields' and 'links' nodes as children.
				# -----------------------------------------------------------------------

				id = child.prop('id')
				self.IDLObject[id] = {}
				obj = self.IDLObject[id]
				obj['fields'] = []

				obj['controller'] = child.prop('controller')
				obj['fieldmapper'] = child.nsProp('fieldmapper', OILS_NS_OBJ)
				obj['virtual'] = child.nsProp('virtual', OILS_NS_PERSIST)
				obj['rpt_label'] = child.nsProp('label', OILS_NS_REPORTER)

				class_node = child.children
				#osrfLogInternal("parseIDL(): parsing class %s" % id)
		
				keys = []
				while class_node:
					if class_node.type == 'element':
						if class_node.name == 'fields':
							keys = self.parseFields(id, class_node)
					class_node = class_node.next

				#obj['fields'] = keys
				osrfNetworkRegisterHint(id, keys, 'array' )

			child = child.next

		doc.freeDoc()


	def parseFields(self, cls, fields):
		"""Takes the fields node and parses the included field elements"""

		field = fields.children
		keys = []
		idlobj = self.IDLObject[cls]

		while field:
			if field.type == 'element':
				keys.append(None)
			field = field.next
		
		field = fields.children
		while field:
			obj = {}
			if field.type == 'element':
				name			= field.prop('name')
				position		= int(field.nsProp('array_position', OILS_NS_OBJ))
				obj['name'] = name

				try:
					keys[position] = name
				except Exception, e:
					osrfLogErr("parseFields(): position out of range.  pos=%d : key-size=%d" % (position, len(keys)))
					raise e

				virtual = field.nsProp('virtual', OILS_NS_PERSIST)
				obj['rpt_label']	= field.nsProp('label', OILS_NS_REPORTER)
				obj['rpt_dtype']	= field.nsProp('datatype', OILS_NS_REPORTER)
				obj['rpt_select']	= field.nsProp('selector', OILS_NS_REPORTER)

				if virtual == string.lower('true'):
					obj['virtual']	= True
				else:
					obj['virtual']	= False

				idlobj['fields'].append(obj)

			field = field.next

		return keys



	
