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

import libxml2, re

def osrfXMLFileToObject(filename):
	"""Turns the contents of an XML file into a Python object"""
	doc	= libxml2.parseFile(filename)
	xmlNode	= doc.children.children
	return osrfXMLNodeToObject(xmlNode)

def osrfXMLStringToObject(string):
	"""Turns an XML string into a Python object"""
	doc	= libxml2.parseString(string)
	xmlNode	= doc.children.children
	return osrfXMLNodeToObject(xmlNode)

def osrfXMLNodeToObject(xmlNode):
	"""Turns an XML node into a Python object"""
	obj = {}

	while xmlNode:
		if xmlNode.type == 'element':
			nodeChild = xmlNode.children
			done = False
			nodeName = xmlNode.name

			while nodeChild:
				if nodeChild.type == 'element':

					# If a node has element children, create a new sub-object 
					# for this node, attach an array for each type of child
					# and recursively collect the children data into the array(s)

					if not obj.has_key(nodeName):
						obj[nodeName] = {}

					sub_obj = osrfXMLNodeToObject(nodeChild);

					if not obj[nodeName].has_key(nodeChild.name):
						# we've encountered 1 sub-node with nodeChild's name
						obj[nodeName][nodeChild.name] = sub_obj[nodeChild.name]

					else:
						if isinstance(obj[nodeName][nodeChild.name], list):
							# we already have multiple sub-nodes with nodeChild's name
							obj[nodeName][nodeChild.name].append(sub_obj[nodeChild.name])

						else:
							# we already have 1 sub-node with nodeChild's name, make 
							# it a list and append the current node
							val = obj[nodeName][nodeChild.name]
							obj[nodeName][nodeChild.name] = [ val, sub_obj[nodeChild.name] ]

					done = True

				nodeChild = nodeChild.next

			if not done:
				# If the node has no children, clean up the text content 
				# and use that as the data
				data = re.compile('^\s*').sub('', xmlNode.content)
				data = re.compile('\s*$').sub('', data)

				obj[nodeName] = data

		xmlNode = xmlNode.next

	return obj


def osrfObjectFindPath(obj, path, idx=None):
	"""Searches an object along the given path for a value to return.

	Path separaters can be '/' or '.', '/' is tried first."""

	parts = []

	if re.compile('/').search(path):
		parts = path.split('/')
	else:
		parts = path.split('.')

	for part in parts:
		try:
			o = obj[part]
		except Exception:
			return None
		if isinstance(o,str): 
			return o
		if isinstance(o,list):
			if( idx != None ):
				return o[idx]
			return o
		if isinstance(o,dict):
			obj = o
		else:
			return o

	return obj


			

