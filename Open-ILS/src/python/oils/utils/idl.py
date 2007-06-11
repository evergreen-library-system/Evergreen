from osrf.net_obj import osrfNetworkRegisterHint
from osrf.log import *
from osrf.set import osrfSettingsValue

import sys, string, xml.dom.minidom
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

    def __getAttr(self, node, name, ns=None):
        """ Find the attribute value on a given node 
            Namespace is ignored for now.. 
            not sure if minidom has namespace support.
            """
        for (k, v) in node.attributes.items():
            if k == name:
                return v
        return None

    def parseIDL(self):
        """Parses the IDL file and builds class objects"""

        doc = xml.dom.minidom.parse(self.idlFile)
        root = doc.childNodes[0]

        for child in root.childNodes:
        
            if child.nodeType == child.ELEMENT_NODE:
        
                # -----------------------------------------------------------------------
                # 'child' is the main class node for a fieldmapper class.
                # It has 'fields' and 'links' nodes as children.
                # -----------------------------------------------------------------------

                id = self.__getAttr(child, 'id')
                self.IDLObject[id] = {}
                obj = self.IDLObject[id]
                obj['fields'] = []

                obj['controller'] = self.__getAttr(child, 'controller')
                obj['fieldmapper'] = self.__getAttr(child, 'oils_obj:fieldmapper', OILS_NS_OBJ)
                obj['virtual'] = self.__getAttr(child, 'oils_perist:virtual', OILS_NS_PERSIST)
                obj['rpt_label'] = self.__getAttr(child, 'reporter:label', OILS_NS_REPORTER)

                keys = []
                for classNode in child.childNodes:
                    if classNode.nodeType == classNode.ELEMENT_NODE:
                        if classNode.nodeName == 'fields':
                            keys = self.parseFields(id, classNode)

                osrfNetworkRegisterHint(id, keys, 'array' )

        doc.unlink()


    def parseFields(self, cls, fields):
        """Takes the fields node and parses the included field elements"""

        keys = []
        idlobj = self.IDLObject[cls]

        for field in fields.childNodes:
            if field.nodeType == field.ELEMENT_NODE:
                keys.append(None)
        
        for field in fields.childNodes:
            obj = {}
            if field.nodeType == fields.ELEMENT_NODE:
                name            = self.__getAttr(field, 'name')
                position        = int(self.__getAttr(field, 'oils_obj:array_position', OILS_NS_OBJ))
                obj['name'] = name

                try:
                    keys[position] = name
                except Exception, e:
                    osrfLogErr("parseFields(): position out of range.  pos=%d : key-size=%d" % (position, len(keys)))
                    raise e

                virtual = self.__getAttr(field, 'virtual', OILS_NS_PERSIST)
                obj['rpt_label']    = self.__getAttr(field, 'reporter:label', OILS_NS_REPORTER)
                obj['rpt_dtype']    = self.__getAttr(field, 'reporter:datatype', OILS_NS_REPORTER)
                obj['rpt_select']   = self.__getAttr(field, 'reporter:selector', OILS_NS_REPORTER)

                if virtual == string.lower('true'):
                    obj['virtual']  = True
                else:
                    obj['virtual']  = False

                idlobj['fields'].append(obj)

        return keys



    
