#!/usr/bin/env python
# ils_events.py
"""
This class enables translation of Evergreen's ils_events XML file.

Requires polib from http://polib.googlecode.com

Source event definitions are structured as follows:
<ils_events>
    <event code='1' textcode='UNKNOWN'>
        <desc xml:lang="en-US">Placeholder event.  Used for development only</desc>
     </event>
</ils_events>

This generates an updated file with the following structure:
<ils_events>
    <event code='1' textcode='UNKNOWN'>
        <desc xml:lang="en-US">Placeholder event.  Used for development only</desc>
        <desc xml:lang="fr-CA">Exemple - seulement developpement</desc>
    </event>
</ils_events>
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
import codecs
import optparse
import polib
import re
import sys
import xml.sax
import xml.sax.handler

class ILSEvents(basel10n.BaseL10N):
    """
    This class provides methods for extracting translatable strings from
    Evergreen's ils_events XML file, generating a translatable POT file,
    reading translated PO files, and generating an updated ils_events.xml
    file with the additional language strings.
    """

    def __init__(self):
        self.pot = None
        basel10n.BaseL10N.__init__(self)
        self.definitions = []
        self.locale = None

    def get_strings(self, source):
        """
        Extracts translatable strings from the //desc[@lang='en-US'] attributes
        in Evergreen's ils_events.xml file.
        """
        self.pothead()

        locator = xml.sax.xmlreader.Locator()
        parser = xml.sax.make_parser()
        handler = ILSEventHandler()
        handler.setDocumentLocator(locator)
        parser.setContentHandler(handler)
        parser.parse(source)

        for entry in handler.events:
            poe = polib.POEntry()
            poe.occurrences = handler.events[entry]
            poe.msgid = entry
            self.pot.append(poe)

    def create_events(self):
        """
        Creates an ILS events XML file based on a translated PO file.

        Each PO entry has one or more file comment with the following structure:

        #: numcode.textcode:lineno
        """

        event = """    <event code='%d' textcode='%s'>
        <desc xml:lang='%s'>%s</desc>\n    </event>"""

        # We should generate this in a real XML way, rather than faking it
        # But we'll fake it for now
        for entry in self.pot:
            for name in entry.occurrences:
                # regex name here
                pat = re.compile(r'(\d+)\.(\w+)').match(name[0])
                numcode = pat.group(1)
                textcode = pat.group(2)

                if entry.msgstr == '':
                    # No translation available; use the en-US definition
                    self.definitions.append(unicode(event % (int(numcode), textcode, self.locale, entry.msgid), 'utf_8'))
                else:
                    self.definitions.append(unicode(event % (int(numcode), textcode, self.locale, entry.msgstr), 'utf_8'))

class ILSEventHandler(xml.sax.handler.ContentHandler):
    """
    Parses an ils_events.xml file to get at event[@code] attributes and
    the contained desc[@lang='en-US'] elements.

    Generates a list of events and their English descriptions.
    """

    def __init__(self):
        xml.sax.handler.ContentHandler.__init__(self)
        self.events = dict()
        self.desc = u''
        self.en_us_flag = False
        self.numcode = None
        self.textcode = None
        self.locator = None

    def setDocumentLocator(self, locator):
        """
        Override setDocumentLocator so we can track line numbers
        """
        self.locator = locator

    def startElement(self, name, attributes):
        """
        Grab the event code attribute value for each class
        or field element.
        """
        if name == 'event':
            self.numcode = attributes['code']
            self.textcode = attributes['textcode']
        if name == 'desc' and attributes['xml:lang'] == 'en-US':
            self.en_us_flag = True

    def characters(self, content):
        """
        Build the ILS event description
        """
        if self.en_us_flag is True and content is not None:
            self.desc += content

    def endElement(self, name):
        """
        Generate the event with the closed description
        """
        if name == 'desc' and self.en_us_flag is True:
            lineno = self.locator.getLineNumber()
            event = "%d.%s" % (int(self.numcode), self.textcode)
            if self.events.has_key(self.desc):
                self.events[self.desc].append([str(event), lineno])
            else:
                self.events[self.desc] = [[str(event), lineno]]

            # Reset event values
            self.desc = u''
            self.en_us_flag = False
            self.numcode = None
            self.textcode = None

def main():
    """
    Determine what action to take
    """
    opts = optparse.OptionParser()
    opts.add_option('-p', '--pot', action='store', \
        help='Create a POT file from the specified ils_events.xml file', \
        metavar='FILE')
    opts.add_option('-c', '--create', action='store', \
        help='Create an ils_events.xml file from a translated PO FILE', \
        metavar='FILE')
    opts.add_option('-l', '--locale', action='store', \
        help='Locale of the ils_events.xml file that will be generated', \
        metavar='FILE')
    opts.add_option('-o', '--output', dest='outfile', \
        help='Write output to FILE (defaults to STDOUT)', metavar='FILE')
    (options, args) = opts.parse_args()

    pot = ILSEvents()

    # Generate a new POT file from the ils_events.xml file
    if options.pot:
        pot.get_strings(options.pot)
        if options.outfile:
            pot.savepot(options.outfile)
        else:
            sys.stdout.write(pot.pot.__str__())

    # Generate an ils_events.xml file from a PO file
    elif options.create:
        if options.locale:
            pot.locale = options.locale
        else:
            opts.error('Must specify an output locale to create an XML file')

        head = """<?xml version="1.0" encoding="utf-8"?>
<ils_events>
        """
        
        tail = "</ils_events>"

        pot.loadpo(options.create)
        pot.create_events()
        if options.outfile:
            outfile = codecs.open(options.outfile, encoding='utf-8', mode='w')
            outfile.write(head)
            for event in pot.definitions: 
                outfile.write(event + "\n")
            outfile.write(tail)
        else:
            print(head)
            for event in pot.definitions:
                print(event)
            print(tail)

    # No options were recognized - print help and bail
    else:
        opts.print_help()

if __name__ == '__main__':
    main()
