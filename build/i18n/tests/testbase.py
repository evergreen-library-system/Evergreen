#!/usr/bin/env python
# -*- coding: utf=8 -*-
# vim: set fileencoding=utf-8 :
"""
Test the BaseL10N class to ensure that we have a solid foundation.
"""

import filecmp
import os
import polib
import sys
import unittest

class TestBaseL10N(unittest.TestCase):

    basedir = os.path.dirname(__file__)
    tmpdirs = [(os.path.join(basedir, 'tmp/'))]
    savefile = os.path.join(basedir, 'tmp/testsave.pot')
    canonpot = os.path.join(basedir, 'data/complex.pot')
    canonpo = os.path.join(basedir, 'data/complex.po')
    poentries = [{
        'msgid': 'Using Library', 
        'msgstr': u'Utiliser la bibliothèque',
        'occurrences': [
            {'line': 240, 'name': 'field.aihu.org_unit.label'},
            {'line': 257, 'name': 'field.ancihu.org_unit.label'},
        ]},
        {
        'msgid': '\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell', 
        'msgstr': u'ôèàéç',
        'occurrences': [
            {'line': 2475, 'name': 'field.rxbt.voided.label'},
        ]},
        {
        'msgid': 'Record Source', 
        'occurrences': [
            {'line': 524, 'name': 'field.bre.source.label'},
        ]},
    ]

    def setUp(self):
        sys.path.append(os.path.join(self.basedir, '../scripts/'))
        self.tearDown()
        for tmpdir in self.tmpdirs:
            os.mkdir(tmpdir)

    def tearDown(self):
        for tmpdir in self.tmpdirs:
            if os.access(tmpdir, os.F_OK):
                for tmpfile in os.listdir(tmpdir):
                    os.remove(os.path.join(tmpdir, tmpfile))
                os.rmdir(tmpdir)

    def testload(self):
        """
        Load a translated PO file and compare to a generated one
        """
        import basel10n
        poload = basel10n.BaseL10N()
        poload.loadpo(self.canonpo)
        pogen = basel10n.BaseL10N()
        pogen.pothead('Evergreen 1.4', '1999-12-31 23:59:59 -0400')
        pogen.pot.metadata['PO-Revision-Date'] = '2007-12-08 23:14:20 -0400'
        pogen.pot.metadata['Last-Translator'] = ' Dan Scott <dscott@laurentian.ca>'
        pogen.pot.metadata['Language-Team'] = 'fr-CA <LL@li.org>'
        for msg in self.poentries:
            poe = polib.POEntry()
            for x in msg['occurrences']:
                poe.occurrences.append((x['name'], x['line']))
            poe.msgid = msg['msgid']
            if msg.has_key('msgstr'):
                poe.msgstr = msg['msgstr']
            pogen.pot.append(poe)

        self.assertEqual(unicode(poload), unicode(pogen))

    def testsavepot(self):
        """
        Save a generated POT file and compare to a known good one
        """
        import basel10n
        pogen = basel10n.BaseL10N()
        pogen.pothead('Evergreen 1.4', '1999-12-31 23:59:59 -0400')
        for msg in self.poentries:
            poe = polib.POEntry()
            for x in msg['occurrences']:
                poe.occurrences.append((x['line'], x['name']))
            poe.msgid = msg['msgid']
            pogen.pot.append(poe)
        pogen.savepot(self.savefile)

        self.assertEqual(filecmp.cmp(self.savefile, self.canonpot), 1)

if __name__ == '__main__':
    unittest.main()
