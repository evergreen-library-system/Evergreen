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
import xml.dom.minidom
#import osrf.net_obj, osrf.log, osrf.set, osrf.ex, osrf.ses
import osrf.net_obj, osrf.log, osrf.ex, osrf.ses
from oils.const import OILS_NS_OBJ, OILS_NS_PERSIST, OILS_NS_REPORTER, OILS_APP_ACTOR

class IDLException(osrf.ex.OSRFException):
    """Exception thrown when parsing the IDL file"""
    pass

class IDLParser(object):
    """Evergreen fieldmapper IDL file parser"""

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
            parser.set_idl(idl_path)
            parser.parse_idl()
            IDLParser._global_parser = parser

    @staticmethod
    def get_class(class_name):
        ''' Returns the IDLClass object with the given 
            network hint / IDL class name.
            @param The class ID from the IDL
            '''
        return IDLParser.get_parser().idl_object[class_name]

    # ------------------------------------------------------------
    # instance methods
    # ------------------------------------------------------------

    def __init__(self):
        """Initializes the IDL object"""
        self.idl_object = {}
        self.idl_file = None

    def set_IDL(self, idlfile):
        """Deprecated non-PEP8 version of set_idl()"""
        self.set_idl(idlfile)

    def set_idl(self, idlfile):
        """Specifies the filename or file that contains the IDL"""
        self.idl_file = idlfile

    def parse_IDL(self):
        """Deprecated non-PEP8 version of parse_idl()"""
        self.parse_idl()

    def parse_idl(self):
        """Parses the IDL file and builds class, field, and link objects"""

        # in case we're calling parse_idl directly
        if not IDLParser._global_parser:
            IDLParser._global_parser = self

        doc = xml.dom.minidom.parse(self.idl_file)
        root = doc.documentElement

        for child in root.childNodes:
        
            if child.nodeType == child.ELEMENT_NODE and child.nodeName == 'class':
        
                # -----------------------------------------------------------------------
                # 'child' is the main class node for a fieldmapper class.
                # It has 'fields' and 'links' nodes as children.
                # -----------------------------------------------------------------------

                obj = IDLClass(
                    _attr(child, 'id'),
                    controller = _attr(child, 'controller'),
                    fieldmapper = _attr(child, 'oils_obj:fieldmapper', OILS_NS_OBJ),
                    virtual = _attr(child, 'oils_persist:virtual', OILS_NS_PERSIST),
                    label = _attr(child, 'reporter:label', OILS_NS_REPORTER),
                    tablename = _attr(child, 'oils_persist:tablename', OILS_NS_PERSIST),
                    field_safe = _attr(child, 'oils_persist:field_safe', OILS_NS_PERSIST),
                )

                self.idl_object[obj.name] = obj

                fields = [f for f in child.childNodes if f.nodeName == 'fields']
                links = [f for f in child.childNodes if f.nodeName == 'links']

                fields = _parse_fields(obj, fields[0])
                if len(links) > 0:
                    _parse_links(obj, links[0])

                osrf.net_obj.register_hint(
                    obj.name, [f.name for f in fields], 'array'
                )

        doc.unlink()


class IDLClass(object):
    """Represents a class in the fieldmapper IDL"""

    def __init__(self, name, **kwargs):
        self.name = name
        self.controller = kwargs.get('controller')
        self.fieldmapper = kwargs.get('fieldmapper')
        self.virtual = _to_bool(kwargs.get('virtual'))
        self.label = kwargs.get('label')
        self.tablename = kwargs.get('tablename')
        self.primary = kwargs.get('primary')
        self.sequence = kwargs.get('sequence')
        self.field_safe = _to_bool(kwargs.get('field_safe'))
        self.fields = []
        self.links = []
        self.field_map = {}

    def __str__(self):
        ''' Stringify the parsed IDL ''' # TODO: improve the format/content

        idl = '-'*60 + '\n'
        idl += "%s [%s] %s\n" % (self.label, self.name, self.tablename)
        idl += '-'*60 + '\n'
        idx = 0
        for field in self.fields:
            idl += "[%d] " % idx
            if idx < 10:
                idl += " "
            idl += str(field) + '\n'
            idx += 1

        return idl

    def get_field(self, field_name):
        """Return the specified field from the class"""

        try:
            return self.field_map[field_name]
        except:
            msg = "No field '%s' in IDL class '%s'" % (field_name, self.name)
            osrf.log.log_warn(msg)
            #raise IDLException(msg)

class IDLField(object):
    """Represents a field in a class in the fieldmapper IDL"""

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

        if self.virtual and str(self.virtual).lower() == 'true':
            self.virtual = True
        else:
            self.virtual = False

    def __str__(self):
        ''' Format as field name and data type, plus linked class for links. '''
        field = self.name
        if self.rpt_datatype:
            field += " [" + self.rpt_datatype
            if self.rpt_datatype == 'link':
                link = [ 
                    l for l in self.idl_class.links
                        if l.field.name == self.name 
                ]
                if len(link) > 0 and link[0].class_:
                    field += " @%s" % link[0].class_
            field += ']'
        return field


class IDLLink(object):
    """Represents a link between objects defined in the IDL"""

    def __init__(self, field, **kwargs):
        '''
            @param field The IDLField object this link references
        '''
        self.field = field
        self.reltype = kwargs.get('reltype')
        self.key = kwargs.get('key')
        self.map = kwargs.get('map')
        self.class_ = kwargs.get('class_')

def _attr(node, name, namespace=None):
    """ Find the attribute value on a given node 
        Namespace is ignored for now;
        not sure if minidom has namespace support.
        """
    attr = node.attributes.get(name)
    if attr:
        return attr.nodeValue
    return None

def _parse_links(idlobj, links):
    """Parses the links between objects defined in the IDL"""

    for link in [l for l in links.childNodes if l.nodeName == 'link']:
        obj = IDLLink(
            field = idlobj.get_field(_attr(link, 'field')),
            reltype = _attr(link, 'reltype'),
            key = _attr(link, 'key'),
            map = _attr(link, 'map'),
            class_ = _attr(link, 'class')
        )
        idlobj.links.append(obj)

def _parse_fields(idlobj, fields):
    """Takes the fields node and parses the included field elements"""

    idlobj.primary = _attr(fields, 'oils_persist:primary', OILS_NS_PERSIST)
    idlobj.sequence =  _attr(fields, 'oils_persist:sequence', OILS_NS_PERSIST)

    position = 0
    for field in [l for l in fields.childNodes if l.nodeName == 'field']:

        name = _attr(field, 'name')

        if name in ['isnew', 'ischanged', 'isdeleted']: 
            continue

        obj = IDLField(
            idlobj,
            name = name,
            position = position,
            virtual = _attr(field, 'oils_persist:virtual', OILS_NS_PERSIST),
            label = _attr(field, 'reporter:label', OILS_NS_REPORTER),
            rpt_datatype = _attr(field, 'reporter:datatype', OILS_NS_REPORTER),
            rpt_select = _attr(field, 'reporter:selector', OILS_NS_REPORTER),
            primitive = _attr(field, 'oils_persist:primitive', OILS_NS_PERSIST)
        )

        idlobj.fields.append(obj)
        idlobj.field_map[obj.name] = obj
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

def _to_bool(field):
    """Converts a string from the DOM into a boolean value. """

    if field and str(field).lower() == 'true':
        return True
    return False

