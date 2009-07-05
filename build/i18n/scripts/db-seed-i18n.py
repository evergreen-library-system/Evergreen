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
import os.path

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
        serts = dict()

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
                    # Unescape escaped SQL single-quotes for translators' sanity
                    msgid = re.compile(r'\'\'').sub("'", fi18n.group('string'))

                    # Hmm, sometimes people use ":" in text identifiers and
                    # polib doesn't seem to like that; urlencode the colon
                    occurid = re.compile(r':').sub("%3A", fi18n.group('id'))

                    if (msgid in serts):
                        serts[msgid].occurrences.append((os.path.basename(source), num))
                        serts[msgid].tcomment = ' '.join((serts[msgid].tcomment, 'id::%s__%s' % (fq_field, occurid)))
                    else:
                        poe = polib.POEntry()
                        poe.tcomment = 'id::%s__%s' % (fq_field, occurid)
                        poe.occurrences = [(os.path.basename(source), num)]
                        poe.msgid = msgid
                        serts[msgid] = poe
            except Exception as exc:
                print "Error in line %d of SQL source file: %s" % (num, exc) 

        for poe in serts.values():
            self.pot.append(poe)

    def create_sql(self, locale):
        """
        Creates a set of INSERT statements that place translated strings
        into the config.i18n_core table.
        """

        insert = "INSERT INTO config.i18n_core (fq_field, identity_value," \
            " translation, string) VALUES ('%s', '%s', '%s', '%s');"
        idregex = re.compile(r'^id::(?P<class>.*?)__(?P<id>.*?)$')
        for entry in self.pot:
            for id_value in entry.tcomment.split():
                # Escape SQL single-quotes to avoid b0rkage
                msgstr = re.compile(r'\'').sub("''", entry.msgstr)

                identifier = idregex.search(id_value)
                if identifier is None:
                    continue
                # And unescape any colons in the occurence ID
                occurid = re.compile(r'%3A').sub(':', identifier.group('id'))

                if msgstr == '':
                    # Don't generate a stmt for an untranslated string
                    break
                self.sql.append(insert % (identifier.group('class'), occurid, locale, msgstr))

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
