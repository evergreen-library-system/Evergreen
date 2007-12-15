#!/usr/bin/env python
#
"""
This class enables translation of Evergreen's seed database strings.

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
        Each INSERT statement contains a schema and tablename which we need to
        insert into the config.i18n table. We'll push this into our
        POEntry.occurrences attribute.
        
        Each INSERT statement also contains 0 or more oils_i18n_gettext()
        markers for the en-US string that we'll use for our msgid attribute.

        A sample INSERT string that we'll scan is as follows:

            INSERT INTO foo.bar (key, value) VALUES 
                (99, oils_i18n_gettext('string'));
        """
        self.pothead()

        # table holds the fully-qualified table name (schema.table)
        # The source SQL may use multi-row VALUES clauses for a single
        # insert statement, so we need to remember the fq-table for
        # multiple lines
        table = ''
        num = 1
        findtable = re.compile(r'\s*INSERT\s+INTO\s+(\S+).*?$')
        findi18n = re.compile(r'.*?oils_i18n_gettext\(\'(.+?)\'\)')

        # Iterate through the source SQL grabbing table names and l10n strings
        sourcefile = open(source)
        for line in sourcefile:
            ftable = findtable.search(line)
            if ftable is not None:
                table = ftable.group(1)
            fi18n = findi18n.search(line)
            if fi18n is not None:
                for i18n in fi18n.groups():
                    # Unescape escaped SQL single-quotes for translators' sanity
                    i18n = re.compile(r'\'\'').sub("'", i18n)
                    if i18n is not None:
                        poe = polib.POEntry()
                        poe.occurrences = [(table, num)]
                        poe.msgid = i18n
                        self.pot.append(poe)
            num = num + 1

    def create_sql(self, locale):
        """
        Creates a set of INSERT statements that place translated strings
        into the config.i18n_core table.
        """

        insert = "INSERT INTO config.i18n_core (fq_field, identity_value," \
            " translation, string) VALUES ('%s', '%s', '%s', '%s');"
        for entry in self.pot:
            for table in entry.occurrences:
                # Escape SQL single-quotes to avoid b0rkage
                msgid = re.compile(r'\'').sub("''", entry.msgid)
                msgstr = re.compile(r'\'').sub("''", entry.msgstr)
                if msgstr == '':
                    # Don't generate a stmt for an untranslated string
                    break
                self.sql.append(insert % (table[0], msgid, locale, msgstr))

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
