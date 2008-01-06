"""
Parses an Evergreen fieldmapper IDL file and builds a global registry of
objects representing that IDL.

Typical usage:

>>> import osrf.system
>>> import oils.utils.idl
>>> osrf.system.connect('/openils/conf/opensrf_core.xml', 'config.opensrf')
>>> oils.utils.idl.oilsParseIDL()
>>> # 'bre' is a network registry hint, or class ID in the IDL file
... print oils.utils.idl.oilsGetIDLParser().IDLObject['bre'].tablename
biblio.record_entry
"""
import osrf.net_obj
import osrf.log, osrf.set, osrf.ex

import sys, string, xml.dom.minidom
from oils.const import OILS_NS_OBJ, OILS_NS_PERSIST, OILS_NS_REPORTER

__global_parser = None

def oilsParseIDL():
    global __global_parser
    if __global_parser: return # no need to re-parse the IDL
    idlParser = oilsIDLParser();
    idlParser.setIDL(osrf.set.get('IDL'))
    idlParser.parseIDL()
    __global_parser = idlParser

def oilsGetIDLParser():
    global __global_parser
    return __global_parser

class oilsIDLParser(object):

    def __init__(self):
        self.IDLObject = {}

    def setIDL(self, file):
        osrf.log.log_info("setting IDL file to " + str(file))
        self.idlFile = file

    def __getAttr(self, node, name, ns=None):
        """ Find the attribute value on a given node 
            Namespace is ignored for now.. 
            not sure if minidom has namespace support.
            """
        attr = node.attributes.get(name)
        if attr:
            return attr.nodeValue
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

                obj = IDLClass(
                    self.__getAttr(child, 'id'),
                    controller = self.__getAttr(child, 'controller'),
                    fieldmapper = self.__getAttr(child, 'oils_obj:fieldmapper', OILS_NS_OBJ),
                    virtual = self.__getAttr(child, 'oils_persist:virtual', OILS_NS_PERSIST),
                    label = self.__getAttr(child, 'reporter:label', OILS_NS_REPORTER),
                    tablename = self.__getAttr(child, 'oils_persist:tablename', OILS_NS_REPORTER),
                )


                self.IDLObject[obj.name] = obj

                fields = [f for f in child.childNodes if f.nodeName == 'fields']
                links = [f for f in child.childNodes if f.nodeName == 'links']
                keys = self.parseFields(obj, fields[0])
                if len(links) > 0:
                    self.parse_links(obj, links[0])

                osrf.net_obj.register_hint(obj.name, keys, 'array')

        doc.unlink()


    def parse_links(self, idlobj, links):

        for link in [l for l in links.childNodes if l.nodeName == 'link']:
            obj = IDLLink(
                field = idlobj.get_field(self.__getAttr(link, 'field')),
                rel_type = self.__getAttr(link, 'rel_type'),
                key = self.__getAttr(link, 'key'),
                map = self.__getAttr(link, 'map')
            )
            idlobj.links.append(obj)


    def parseFields(self, idlobj, fields):
        """Takes the fields node and parses the included field elements"""

        keys = []

        idlobj.primary = self.__getAttr(fields, 'oils_persist:primary', OILS_NS_PERSIST)
        idlobj.sequence =  self.__getAttr(fields, 'oils_persist:sequence', OILS_NS_PERSIST)

        # pre-flesh the array of keys to accomodate random index insertions
        for field in fields.childNodes:
            if field.nodeType == field.ELEMENT_NODE:
                keys.append(None)
        
        for field in [l for l in fields.childNodes if l.nodeName == 'field']:

            obj = IDLField(
                idlobj,
                name = self.__getAttr(field, 'name'),
                position = int(self.__getAttr(field, 'oils_obj:array_position', OILS_NS_OBJ)),
                virtual = self.__getAttr(field, 'oils_persist:virtual', OILS_NS_PERSIST),
                label = self.__getAttr(field, 'reporter:label', OILS_NS_REPORTER),
                rpt_datatype = self.__getAttr(field, 'reporter:datatype', OILS_NS_REPORTER),
                rpt_select = self.__getAttr(field, 'reporter:selector', OILS_NS_REPORTER),
                primitive = self.__getAttr(field, 'oils_persist:primitive', OILS_NS_PERSIST)
            )

            try:
                keys[obj.position] = obj.name
            except Exception, e:
                osrf.log.log_error("parseFields(): position out of range.  pos=%d : key-size=%d" % (obj.position, len(keys)))
                raise e

            idlobj.fields.append(obj)

        return keys


class IDLException(osrf.ex.OSRFException):
    pass

class IDLClass(object):
    def __init__(self, name, **kwargs):
        self.name = name
        self.controller = kwargs.get('controller')
        self.fieldmapper = kwargs.get('fieldmapper')
        self.virtual = kwargs.get('virtual')
        self.label = kwargs.get('label')
        self.tablename = kwargs.get('tablename')
        self.primary = kwargs.get('primary')
        self.sequence = kwargs.get('sequence')
        self.fields = []
        self.links = []

        if self.virtual and self.virtual.lower() == 'true':
            self.virtual = True
        else:
            self.virtual = False

    def get_field(self, field_name):
        try:
            return [f for f in self.fields if f.name == field_name][0]
        except:
            msg = "No field '%s' in IDL class '%s'" % (field_name, self.name)
            osrf.log.log_error(msg)
            #raise IDLException(msg)

class IDLField(object):
    def __init__(self, idl_class, **kwargs):
        '''
            @param idl_class The IDLClass object which owns this field
        '''
        self.idl_class = idl_class
        self.name = kwargs.get('name')
        self.label = kwargs.get('label')
        self.rpt_datatype = kwargs.get('rpt_datatype')
        self.rpt_select = kwargs.get('rpt_select')
        self.primitive = kwargs.get('primitive')
        self.virtual = kwargs.get('virtual')
        self.position = kwargs.get('position')

        if self.virtual and self.virtual.lower() == 'true':
            self.virtual = True
        else:
            self.virtual = False


class IDLLink(object):
    def __init__(self, field, **kwargs):
        '''
            @param field The IDLField object this link references
        '''
        self.field = field
        self.rel_type = kwargs.get('rel_type')
        self.key = kwargs.get('key')
        self.map = kwargs.get('map')


