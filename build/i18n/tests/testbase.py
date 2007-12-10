#!/usr/bin/env python
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

    tmpdirs = [('tmp/')]
    savefile = ('tmp/testsave.pot')
    canonpot = ('data/complex.pot')
    canonpo = ('data/complex.po')
    poentries = [{
        'msgid': 'Using Library', 
        'msgstr': 'Utiliser la bibliothèque',
        'occurences': [
            {'line': 240, 'name': 'field.aihu.org_unit.label'},
            {'line': 257, 'name': 'field.ancihu.org_unit.label'},
        ]},
        {
        'msgid': '\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell\nSuper crazy long and repetitive message ID from hell', 
        'msgstr': 'ôèàéç',
        'occurences': [
            {'line': 2475, 'name': 'field.rxbt.voided.label'},
        ]},
        {
        'msgid': 'Record Source', 
        'occurences': [
            {'line': 524, 'name': 'field.bre.source.label'},
        ]},
    ]

    def setUp(self):
        sys.path.append('../scripts/')
        self.tearDown()
        for dir in self.tmpdirs:
            os.mkdir(dir)

    def tearDown(self):
        for dir in self.tmpdirs:
            if os.access(dir, os.F_OK):
                for file in os.listdir(dir):
                    os.remove(os.path.join(dir, file))
                os.rmdir(dir)

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
            for x in msg['occurences']:
                poe.occurences.append((x['line'], x['name']))
            poe.msgid = msg['msgid']
            if msg.has_key('msgstr'):
                poe.msgstr = msg['msgstr']
            pogen.pot.append(poe)

        self.assertEqual(str(poload), str(pogen))

    def testsavepot(self):
        """
        Save a generated POT file and compare to a known good one
        """
        import basel10n
        pogen = basel10n.BaseL10N()
        pogen.pothead('Evergreen 1.4', '1999-12-31 23:59:59 -0400')
        for msg in self.poentries:
            poe = polib.POEntry()
            for x in msg['occurences']:
                poe.occurences.append((x['line'], x['name']))
            poe.msgid = msg['msgid']
            pogen.pot.append(poe)
        pogen.savepot(self.savefile)

        self.assertEqual(filecmp.cmp(self.savefile, self.canonpot), 1)

if __name__ == '__main__':
    unittest.main()
