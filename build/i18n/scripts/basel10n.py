#!/usr/bin/env python
# basel10n.py
"""
This class enables translation of Evergreen's seed database strings
and fieldmapper IDL XML.

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

import polib
import time

class BaseL10N:
    """
    Define the base class for localization support in Evergreen
    """

    def __init__(self):
        self.pot = polib.POFile()

    def pothead(self, version=None, date=None):
        """
        Initializes the header for a POT file to reasonable defaults
        """
        # We should be smarter about the Project-Id-Version attribute
        if version is None:
            version = 'Evergreen 1.4'
        if date is None:
            date = time.strftime("%Y-%m-%d %H:%M:%S") + '-0400'
        self.pot.metadata['Project-Id-Version'] = version
        self.pot.metadata['Report-Msgid-Bugs-To'] = \
            'open-ils-dev@list.georgialibraries.org'
        # Cheat and hard-code the time zone offset
        self.pot.metadata['POT-Creation-Date'] = date
        self.pot.metadata['PO-Revision-Date'] = 'YEAR-MO-DA HO:MI+ZONE'
        self.pot.metadata['Last-Translator'] = 'FULL NAME <EMAIL@ADDRESS>'
        self.pot.metadata['Language-Team'] = 'LANGUAGE <LL@li.org>'
        self.pot.metadata['MIME-Version'] = '1.0'
        self.pot.metadata['Content-Type'] = 'text/plain; charset=utf-8'
        self.pot.metadata['Content-Transfer-Encoding'] = '8-bit'

    def savepot(self, destination):
        """
        Saves the POT file to a specified file.
        """
        self.pot.save(destination)
        
    def loadpo(self, source):
        """
        Loads a translated PO file so we can generate the corresponding SQL or entity definitions.
        """
        self.pot = polib.pofile(source)

    def __str__(self):
        """
        Returns the PO representation of the strings.
        """
        return self.pot.__str__()

