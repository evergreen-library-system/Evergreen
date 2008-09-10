#!/usr/bin/env python
# fieldmapper.py
"""
This class enables translation of Evergreen's fieldmapper IDL XML.

Requires polib from http://polib.googlecode.com
"""
# Copyright 2007 Dan Scott <dscott@laurentian.ca>
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

import basel10n
import optparse
import polib
import sys
import xml.sax
import xml.sax.handler

class IDL(basel10n.BaseL10N):
    """
    This class provides methods for extracting translatable strings from
    Evergreen's fieldmapper IDL reporter:label attributes, generating a
    translatable POT file, reading translated PO files, and generating
    an updated fm_IDL.xml file with the additional language strings.
    """

    def __init__(self):
        self.pot = None
        basel10n.BaseL10N.__init__(self)
        self.idl = ''
        self.definitions = []

    def get_strings(self, source):
        """
        Extracts translatable strings from the reporter:label attributes
        in Evergreen's fieldmapper IDL file.
        """
        self.pothead()

        locator = xml.sax.xmlreader.Locator()
        parser = xml.sax.make_parser()
        handler = IDLHandler()
        handler.setDocumentLocator(locator)
        parser.setContentHandler(handler)
        parser.parse(source)

        for entity in handler.entities:
            poe = polib.POEntry()
            poe.occurrences = handler.entities[entity]
            poe.msgid = entity
            self.pot.append(poe)
        self.idl = handler.entityized

    def create_entity(self):
        """
        Creates an entity definition file based on a translated PO file.
        """
        entity = '<!ENTITY %s "%s">'
        for entry in self.pot:
            for name in entry.occurrences:
                if entry.msgstr == '':
                    # No translation available; use the en-US definition
                    self.definitions.append(entity % (name[0], entry.msgid))
                else:
                    self.definitions.append(entity % (name[0], entry.msgstr))

class IDLHandler(xml.sax.handler.ContentHandler):
    """
    Parses a fieldmapper IDL file to get at reporter:label and name attributes.
    Generates a list of entity definitions and their values, as well as an
    entity-ized version of the fieldmapper IDL.
    """

    def __init__(self):
        xml.sax.handler.ContentHandler.__init__(self)
        self.entities = dict()
        self.classid = None
        self.entityized = u"""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE fieldmapper [
    <!--#include virtual="/opac/locale/${locale}/fm_IDL.dtd"--> 
]>
"""
        self.locator = None

    def setDocumentLocator(self, locator):
        """
        Override setDocumentLocator so we can track line numbers
        """
        self.locator = locator

    def startElement(self, name, attributes):
        """
        Return the reporter:label or name attribute value for each class
        or field element.
        """
        entity = None
        lineno = self.locator.getLineNumber()
        if name == 'class':
            self.classid = attributes['id']
        if attributes.has_key('reporter:label'):
            if name == 'class':
                entity = "%s.%s.label" % (name, self.classid)
            elif name == 'field':
                entity = "%s.%s.%s.label" % (name, self.classid, \
                    attributes['name'])
            label = attributes['reporter:label']
            if not self.entities.has_key(label):
                self.entities[label] = [(str(entity), lineno)]
            else:
                self.entities[label].append((str(entity), lineno))

        # Now we'll render an entity-ized version of this element
        element = "<%s" % (name)
        for att in attributes.keys():
            # Replace reporter:label attribute values with entities
            if att == 'reporter:label':
                element = element + " %s='&%s;'" % (att, entity) 
            else:
                element = element + " %s='%s'" % (att, attributes[att])

        # field and link elements are empty elements
        if name == 'field' or name == 'link':
            element = element + " />"
        else:
            element = element + ">"
        self.entityized = self.entityized + element

    def characters(self, content):
        """
        Shove character data into the entityized IDL file
        """
        self.entityized = self.entityized + xml.sax.saxutils.escape(content)

    def endElement(self, name):
        """
        field and link elements are empty elements
        """
        if name == 'field' or name == 'link':
            pass
        else:
            self.entityized = self.entityized + "</%s>" % (name)

def main():
    """
    Determine what action to take
    """
    opts = optparse.OptionParser()
    opts.add_option('-p', '--pot', action='store', \
        help='Create a POT file from the specified fieldmapper IDL file', \
        metavar='FILE')
    opts.add_option('-c', '--convert', action='store', \
        help='Create a fieldmapper FILE that uses entities instead of text ' \
        'strings for field labels and names', metavar='FILE')
    opts.add_option('-e', '--entity', action='store', \
        help='Create an entity definition from a translated PO FILE', \
        metavar='FILE')
    opts.add_option('-o', '--output', dest='outfile', \
        help='Write output to FILE (defaults to STDOUT)', metavar='FILE')
    (options, args) = opts.parse_args()

    pot = IDL()
    # Generate a new POT file from the fieldmapper IDL
    if options.pot:
        pot.get_strings(options.pot)
        if options.outfile:
            pot.savepot(options.outfile)
        else:
            sys.stdout.write(pot.pot.__str__())
    # Generate an entity file from a PO file
    elif options.entity:
        pot.loadpo(options.entity)
        pot.create_entity()
        if options.outfile:
            outfile = open(options.outfile, 'w')
            for entity in pot.definitions: 
                outfile.write(entity + "\n")
        else:
            for entity in pot.definitions:
                print(entity)
    # Generate an entity-ized fieldmapper IDL file
    elif options.convert:
        pot.get_strings(options.convert)
        if options.outfile:
            outfile = open(options.outfile, 'w')
            outfile.write(pot.idl)
        else:
            sys.stdout.write(pot.idl)
    # No options were recognized - print help and bail
    else:
        opts.print_help()

if __name__ == '__main__':
    main()
