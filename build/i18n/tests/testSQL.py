#!/usr/bin/env python
#
# Perform the following tests:
#  1. Generate a POT file from a set of marked SQL statements
#  2. Generate an SQL file from a translated PO file

import filecmp
import os
import subprocess
import testhelper
import unittest

class TestSQLFramework(unittest.TestCase):

    basedir = os.path.dirname(__file__)
    script = os.path.join(basedir, '../scripts/db-seed-i18n.py')
    tmpdirs = [(os.path.join(basedir, 'tmp/'))]
    sqlsource = os.path.join(basedir, 'data/sqlsource.sql')
    canonpot = os.path.join(basedir, 'data/sql2pot.pot')
    canonpo = os.path.join(basedir, 'data/sqlsource.po')
    testpot = os.path.join(basedir, 'tmp/sql2pot.pot')
    canonsql = os.path.join(basedir, 'data/po2sql.sql')
    testsql = os.path.join(basedir, 'tmp/testi18n.sql')

    def setUp(self):
        testhelper.setUp(self)

    def tearDown(self):
        testhelper.tearDown(self)

    def testgenpot(self):
        """
        Create a POT file from our test SQL statements.
        """
        subprocess.Popen(
            ('python', self.script, '--pot', self.sqlsource,
            '--output', self.testpot),
            0, None, None).wait()

        # avoid basic timestamp conflicts
        testhelper.mungepothead(self.testpot)
        testhelper.mungepothead(self.canonpot)

        self.assertEqual(filecmp.cmp(self.canonpot, self.testpot), 1)

    def testgensql(self):
        """
        Create a SQL file from a translated PO file.
        """
        devnull = open('/dev/null', 'w')
        subprocess.Popen(
            ('python', self.script, '--sql', self.canonpo,
            '--locale', 'zz-ZZ', '--output', self.testsql),
            0, None, None, devnull, devnull).wait()
        self.assertEqual(filecmp.cmp(self.canonsql, self.testsql), 1)

if __name__ == '__main__':
    unittest.main()
