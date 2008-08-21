#!/usr/bin/env python
# vim:et:ts=4:sw=4:
"""
This class enables translation of Evergreen's seed database strings.

Requires polib from http://polib.googlecode.com
"""
# Copyright 2007-2008 Dan Scott <dscott@laurentian.ca>
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
import re
import sys

class SQL(basel10n.BaseL10N):
    """
    This class provides methods for extracting translatable strings from
    Evergreen's database seed values, generating a translatable POT file,
    reading translated PO files, and generating SQL for inserting the
    translated values into the Evergreen database.
    """

    def __init__(self):
        self.pot = None
        basel10n.BaseL10N.__init__(self)
        self.sql = []

    def getstrings(self, source):
        """
        Each INSERT statement contains 0 or more oils_i18n_gettext()
        markers for the en-US string that identify the string (which
        we push into the POEntry.occurrences attribute), class hint,
        and property. We concatenate the class hint and property and
        use that for our msgid attribute.
        
        A sample INSERT string that we'll scan is as follows:

            INSERT INTO foo.bar (key, value) VALUES 
                (99, oils_i18n_gettext(99, 'string', 'class hint', 'property'));
        """
        self.pothead()

        num = 0
        findi18n = re.compile(r'.*?oils_i18n_gettext\((.*?)\'\)')
        intkey = re.compile(r'\s*(?P<id>\d+),\s*\'(?P<string>.+?)\',\s*\'(?P<class>.+?)\',\s*\'(?P<property>.+?)$')
        textkey = re.compile(r'\s*\'(?P<id>.*?)\',\s*\'(?P<string>.+?)\',\s*\'(?P<class>.+?)\',\s*\'(?P<property>.+?)$')

        # Iterate through the source SQL grabbing table names and l10n strings
        sourcefile = open(source)
        for line in sourcefile:
            try:
                num = num + 1
                entry = findi18n.search(line)
                if entry is None:
                    continue
                for parms in entry.groups():
                    # Try for an integer-based primary key parameter first
                    fi18n = intkey.search(parms)
                    if fi18n is None:
                        # Otherwise, it must be a text-based primary key parameter
                        fi18n = textkey.search(parms)
                    fq_field = "%s.%s" % (fi18n.group('class'), fi18n.group('property'))
                    poe = polib.POEntry()
                    poe.occurrences = [(fq_field, num)]
                    poe.tcomment = 'id::' + fi18n.group('id')
                    # Unescape escaped SQL single-quotes for translators' sanity
                    poe.msgid = re.compile(r'\'\'').sub("'", fi18n.group('string'))
                    self.pot.append(poe)
            except:
                print "Error in line %d of SQL source file" % (num) 

    def create_sql(self, locale):
        """
        Creates a set of INSERT statements that place translated strings
        into the config.i18n_core table.
        """

        insert = "INSERT INTO config.i18n_core (fq_field, identity_value," \
            " translation, string) VALUES ('%s', '%s', '%s', '%s');"
        for entry in self.pot:
            for fq_field in entry.occurrences:
                # Escape SQL single-quotes to avoid b0rkage
                msgid = re.compile(r'\'').sub("''", entry.tcomment)
                msgstr = re.compile(r'\'').sub("''", entry.msgstr)
                msgid = re.compile(r'^id::').sub('', msgid)
                if msgstr == '':
                    # Don't generate a stmt for an untranslated string
                    break
                self.sql.append(insert % (fq_field[0], msgid, locale, msgstr))

def main():
    """
    Determine what action to take
    """
    opts = optparse.OptionParser()
    opts.add_option('-p', '--pot', action='store', \
        help='Generate POT from the specified source SQL file', metavar='FILE')
    opts.add_option('-s', '--sql', action='store', \
        help='Generate SQL from the specified source POT file', metavar='FILE')
    opts.add_option('-l', '--locale', \
        help='Locale of the SQL file that will be generated')
    opts.add_option('-o', '--output', dest='outfile', \
        help='Write output to FILE (defaults to STDOUT)', metavar='FILE')
    (options, args) = opts.parse_args()

    if options.pot:
        pot = SQL()
        pot.getstrings(options.pot)
        if options.outfile:
            pot.savepot(options.outfile)
        else:
            sys.stdout.write(pot.pot.__str__())
    elif options.sql:
        if not options.locale:
            opts.error('Must specify an output locale')
        pot = SQL()
        pot.loadpo(options.sql)
        pot.create_sql(options.locale)
        if not options.outfile:
            outfile = sys.stdout
        else:
            outfile = open(options.outfile, 'w')
        for insert in pot.sql: 
            outfile.write(insert + "\n")
    else:
        opts.print_help()

if __name__ == '__main__':
    main()
