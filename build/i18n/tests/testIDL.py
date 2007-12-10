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
import polib
import re
import subprocess
import sys
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
        sys.path.append(os.path.join(self.basedir, '../scripts/'))
        self.tearDown()
        for dir in self.tmpdirs:
            os.mkdir(dir)

    def tearDown(self):
        for dir in self.tmpdirs:
            if os.access(dir, os.F_OK):
                for file in os.listdir(dir):
                    os.remove(os.path.join(dir, file))
                os.rmdir(dir)

    def testentityize(self):
        """
        Convert an en-US IDL file to an entityized version
        """
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(
            ('python', self.script, '--convert', self.idlfile,
            '--output', self.saveidlent),
            0, None, None, devnull, devnull).wait()

        self.assertEqual(filecmp.cmp(self.saveidlent, self.idlentfile), 1)

    def testsavepot(self):
        """
        Create a POT file from a fieldmapper IDL file
        """
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(
            ('python', self.script, '--pot', self.idlfile,
            '--output', self.savepot),
            0, None, None, devnull, devnull).wait()

        mungepothead(self.savepot)
        mungepothead(self.testpot)

        self.assertEqual(filecmp.cmp(self.savepot, self.testpot), 1)

    def testgenent(self):
        """
        Generate an entity definition file from a PO file
        """
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(
            ('python', self.script, '--entity', self.testpo,
            '--output', self.saveentities),
            0, None, None, devnull, devnull).wait()
        self.assertEqual(filecmp.cmp(self.saveentities, self.idlentities), 1)


def mungepothead(file):
    """
    Change POT header to avoid annoying timestamp mismatch
    """
    lines = [] 
    mungefile = open(file)
    for line in mungefile:
        line = re.sub(r'^("POT-Creation-Date: ).+"$', r'\1', line)
        lines.append(line)
    mungefile.close()

    # Write the changed lines back out
    mungefile = open(file, 'w')
    for line in lines:
        mungefile.write(line)
    mungefile.close()

if __name__ == '__main__':
    unittest.main()
