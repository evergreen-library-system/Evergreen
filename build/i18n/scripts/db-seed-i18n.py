#/usr/bin/env python
#
# Copyright 2007 Dan Scott <dscott@laurentian.ca>
#
# This class enables translation of Evergreen's seed database strings.
#
# Requires polib from http://polib.googlecode.com
#
# ####
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
import re
import time

class EvergreenSQL:
    """
    This class provides methods for extracting translatable strings from
    Evergreen's database seed values, generating a translatable POT file,
    reading translated PO files, and generating SQL for inserting the
    translated values into the Evergreen database.
    """

    def getstrings(self, source):
        """
        Each INSERT statement contains a schema and tablename which we need to
        insert into the config.i18n table. We'll push this into our
        POEntry.occurences attribute.
        
        Each INSERT statement also contains 0 or more oils_i18n_gettext()
        markers for the en-US string that we'll use for our msgid attribute.

        A sample INSERT string that we'll scan is as follows:

            INSERT INTO foo.bar (key, value) VALUES 
                (99, oils_i18n_gettext('string'));
        """
        date = time.strftime("%Y-%m-%d %H:%M:%S")
        self.pot = polib.POFile()

        # We should be smarter about the Project-Id-Version attribute
        self.pot.metadata['Project-Id-Version'] = 'Evergreen 1.4'
        self.pot.metadata['Report-Msgid-Bugs-To'] = 'open-ils-dev@list.georgialibraries.org'
        # Cheat and hard-code the time zone offset
        self.pot.metadata['POT-Creation-Date'] = "%s %s" % (date, '-0400')
        self.pot.metadata['PO-Revision-Date'] = 'YEAR-MO-DA HO:MI+ZONE'
        self.pot.metadata['Last-Translator'] = 'FULL NAME <EMAIL@ADDRESS>'
        self.pot.metadata['Language-Team'] = 'LANGUAGE <LL@li.org>'
        self.pot.metadata['MIME-Version'] = '1.0'
        self.pot.metadata['Content-Type'] = 'text/plain; charset=utf-8'
        self.pot.metadata['Content-Transfer-Encoding'] = '8-bit'

        # table holds the fully-qualified table name (schema.table)
        # The source SQL may use multi-row VALUES clauses for a single
        # insert statement, so we need to remember the fq-table for
        # multiple lines
        table = ''
        n = 1
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
                    poe = polib.POEntry()
                    poe.occurences = [(table, n)]
                    poe.msgid = i18n
                    self.pot.append(poe)
            n = n + 1

    def savepot(self, destination):
        """
        Saves the POT file to a specified file.
        """
        self.pot.save(destination)
        
    def loadpo(self, source):
        """
        Loads a translated PO file so we can generate the corresponding SQL.
        """
        self.pot = polib.pofile(source)

    def createsql(self, locale):
        """
        Creates a set of INSERT statements that place translated strings
        into the config.i18n_core table.
        """

        insert = "INSERT INTO config.i18n_core (fq_field, identity_value, translation, string) VALUES ('%s', '%s', '%s', '%s');"
        self.sql = [] 
        for entry in self.pot:
            for table in entry.occurences:
                # Escape SQL single-quotes to avoid b0rkage
                msgid = re.compile(r'\'').sub("''", entry.msgid)
                msgstr = re.compile(r'\'').sub("''", entry.msgstr)
                if msgstr == '':
                    # Don't generate a stmt for an untranslated string
                    break
                self.sql.append(insert % (table[0], msgid, locale, msgstr))

    def __str__(self):
        """
        Returns the PO representation of the strings.
        """
        return self.pot.__str__()
 
if __name__ == '__main__':
    pot = EvergreenSQL()
    pot.getstrings('../../Open-ILS/src/sql/Pg/950.data.seed-values.sql')
    pot.savepot('po/db.seed.pot')

#    test = EvergreenSQL()
#    test.loadpo('po/db.seed.pot')
#    test.createsql('fr-CA')
#    for insert in test.sql: 
#       print insert
