#!/usr/bin/env python
# vim: set fileencoding=utf-8 :
"""
 Perform the following tests:
  1. Generate an entityized version of an abbreviated version of fm_IDL.xml 
  2. Generate a POT file from fm_IDL.xml
  3. Generate an entity definition file from a PO file
"""

import filecmp
import os
import subprocess
import testhelper
import unittest

class TestIDLL10N(unittest.TestCase):

    basedir = os.path.dirname(__file__)
    script = os.path.join(basedir, '../scripts/fieldmapper.py')
    tmpdirs = [(os.path.join(basedir, 'tmp/'))]
    savepot = os.path.join(basedir, 'tmp/testsave.pot')
    saveidlent = os.path.join(basedir, 'tmp/testidlent.xml')
    saveentities = os.path.join(basedir, 'tmp/testentity.ent')
    idlfile = os.path.join(basedir, 'data/testidl.xml')
    idlentfile = os.path.join(basedir, 'data/testidlent.xml')
    idlentities = os.path.join(basedir, 'data/testidl.ent')
    testpot = os.path.join(basedir, 'data/testidl.pot')
    testpo = os.path.join(basedir, 'data/testidl.po')

    def setUp(self):
        testhelper.setUp(self)

    def tearDown(self):
        testhelper.tearDown(self)

    def testentityize(self):
        """
        Convert an en-US IDL file to an entityized version
        """
        devnull = open('/dev/null', 'w')
        subprocess.Popen(
            ('python', self.script, '--convert', self.idlfile,
            '--output', self.saveidlent),
            0, None, None, devnull, devnull).wait()

        self.assertEqual(filecmp.cmp(self.saveidlent, self.idlentfile), 1)

    def testsavepot(self):
        """
        Create a POT file from a fieldmapper IDL file
        """
        devnull = open('/dev/null', 'w')
        subprocess.Popen(
            ('python', self.script, '--pot', self.idlfile,
            '--output', self.savepot),
            0, None, None, devnull, devnull).wait()

        # Avoid timestamp mismatches
        testhelper.mungepothead(self.savepot)
        testhelper.mungepothead(self.testpot)

        self.assertEqual(filecmp.cmp(self.savepot, self.testpot), 1)

    def testgenent(self):
        """
        Generate an entity definition file from a PO file
        """
        devnull = open('/dev/null', 'w')
        subprocess.Popen(
            ('python', self.script, '--entity', self.testpo,
            '--output', self.saveentities),
            0, None, None, devnull, devnull).wait()
        self.assertEqual(filecmp.cmp(self.saveentities, self.idlentities), 1)

if __name__ == '__main__':
    unittest.main()
