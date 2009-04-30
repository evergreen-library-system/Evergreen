"""
Parses an Evergreen fieldmapper IDL file and builds a global registry of
objects representing that IDL.

Typical usage:

>>> import osrf.system
>>> import oils.utils.idl
>>> osrf.system.connect('/openils/conf/opensrf_core.xml', 'config.opensrf')
>>> oils.utils.idl.IDLParser.parse()
>>> # 'bre' is a network registry hint, or class ID in the IDL file
... print oils.utils.idl.IDLParser.get_class('bre').tablename
biblio.record_entry
"""
import sys, string, xml.dom.minidom
#import osrf.net_obj, osrf.log, osrf.set, osrf.ex, osrf.ses
import osrf.net_obj, osrf.log, osrf.ex, osrf.ses
from oils.const import OILS_NS_OBJ, OILS_NS_PERSIST, OILS_NS_REPORTER, OILS_APP_ACTOR

class IDLException(osrf.ex.OSRFException):
    pass

class IDLParser(object):

    # ------------------------------------------------------------
    # static methods and variables for managing a global parser
    # ------------------------------------------------------------
    _global_parser = None

    @staticmethod
    def get_parser():
        ''' Returns the global IDL parser object '''
        if IDLParser._global_parser is None:
            raise IDLException("IDL has not been parsed")
        return IDLParser._global_parser

    @staticmethod
    def parse():
        ''' Finds the path to the IDL file from the OpenSRF settings 
            server, parses the IDL file, and uses the parsed data as
            the global IDL repository '''
        if IDLParser._global_parser is None:
            parser = IDLParser()
            idl_path = osrf.ses.ClientSession.atomic_request(
                OILS_APP_ACTOR, 'opensrf.open-ils.fetch_idl.file')
            parser.set_IDL(idl_path)
            parser.parse_IDL()
            IDLParser._global_parser = parser

    @staticmethod
    def get_class(class_name):
        ''' Returns the IDLClass object with the given 
            network hint / IDL class name.
            @param The class ID from the IDL
            '''
        return IDLParser.get_parser().IDLObject[class_name]

    # ------------------------------------------------------------
    # instance methods
    # ------------------------------------------------------------

    def __init__(self):
        self.IDLObject = {}

    def set_IDL(self, file):
        self.idlFile = file

    def _get_attr(self, node, name, ns=None):
        """ Find the attribute value on a given node 
            Namespace is ignored for now.. 
            not sure if minidom has namespace support.
            """
        attr = node.attributes.get(name)
        if attr:
            return attr.nodeValue
        return None

    def parse_IDL(self):
        """Parses the IDL file and builds class, field, and link objects"""

        # in case we're calling parse_IDL directly
        if not IDLParser._global_parser:
            IDLParser._global_parser = self

        doc = xml.dom.minidom.parse(self.idlFile)
        root = doc.documentElement

        for child in root.childNodes:
        
            if child.nodeType == child.ELEMENT_NODE and child.nodeName == 'class':
        
                # -----------------------------------------------------------------------
                # 'child' is the main class node for a fieldmapper class.
                # It has 'fields' and 'links' nodes as children.
                # -----------------------------------------------------------------------

                obj = IDLClass(
                    self._get_attr(child, 'id'),
                    controller = self._get_attr(child, 'controller'),
                    fieldmapper = self._get_attr(child, 'oils_obj:fieldmapper', OILS_NS_OBJ),
                    virtual = self._get_attr(child, 'oils_persist:virtual', OILS_NS_PERSIST),
                    label = self._get_attr(child, 'reporter:label', OILS_NS_REPORTER),
                    tablename = self._get_attr(child, 'oils_persist:tablename', OILS_NS_REPORTER),
                )


                self.IDLObject[obj.name] = obj

                fields = [f for f in child.childNodes if f.nodeName == 'fields']
                links = [f for f in child.childNodes if f.nodeName == 'links']

                fields = self.parse_fields(obj, fields[0])
                if len(links) > 0:
                    self.parse_links(obj, links[0])

                osrf.net_obj.register_hint(obj.name, [f.name for f in fields], 'array')

        doc.unlink()


    def parse_links(self, idlobj, links):

        for link in [l for l in links.childNodes if l.nodeName == 'link']:
            obj = IDLLink(
                field = idlobj.get_field(self._get_attr(link, 'field')),
                rel_type = self._get_attr(link, 'rel_type'),
                key = self._get_attr(link, 'key'),
                map = self._get_attr(link, 'map')
            )
            idlobj.links.append(obj)


    def parse_fields(self, idlobj, fields):
        """Takes the fields node and parses the included field elements"""

        idlobj.primary = self._get_attr(fields, 'oils_persist:primary', OILS_NS_PERSIST)
        idlobj.sequence =  self._get_attr(fields, 'oils_persist:sequence', OILS_NS_PERSIST)

        position = 0
        for field in [l for l in fields.childNodes if l.nodeName == 'field']:

            name = self._get_attr(field, 'name')

            if name in ['isnew', 'ischanged', 'isdeleted']: 
                continue

            obj = IDLField(
                idlobj,
                name = name,
                position = position,
                virtual = self._get_attr(field, 'oils_persist:virtual', OILS_NS_PERSIST),
                label = self._get_attr(field, 'reporter:label', OILS_NS_REPORTER),
                rpt_datatype = self._get_attr(field, 'reporter:datatype', OILS_NS_REPORTER),
                rpt_select = self._get_attr(field, 'reporter:selector', OILS_NS_REPORTER),
                primitive = self._get_attr(field, 'oils_persist:primitive', OILS_NS_PERSIST)
            )

            idlobj.fields.append(obj)
            position += 1

        for name in ['isnew', 'ischanged', 'isdeleted']: 
            obj = IDLField(idlobj, 
                name = name, 
                position = position, 
                virtual = 'true'
            )
            idlobj.fields.append(obj)
            position += 1

        return idlobj.fields



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
            osrf.log.log_warn(msg)
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


