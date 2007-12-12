#!/usr/bin/env python

import filecmp
import glob
import os
import re
import shutil
import subprocess
import sys
import unittest

class TestPOFramework(unittest.TestCase):

    po_sources = ('../../Open-ILS/web/opac/locale/en-US/*.dtd',
        '../../Open-ILS/xul/staff_client/chrome/locale/en-US/*.properties',
        '../../Open-ILS/examples/fm_IDL.xml',
        '../../Open-ILS/src/sql/Pg/950.data.seed-values.sql')

    po_tmp_files = ('tests/tmp/po/test.properties.pot', 'tests/tmp/po/ll-LL/temp.properties.po')
    pot_dir = 'tests/tmp/po'
    locale_dir = 'tests/tmp/po/ll-LL/'
    po_tmp_dirs = (locale_dir, locale_dir, pot_dir, 'tests/tmp')

    def setUp(self):
        self.tearDown()
        devnull = open('/dev/null', 'w')
        os.mkdir('tests/tmp')
        proc = subprocess.Popen(('cp', '-r', 'po', 'tests/tmp'), 0, None, None, devnull, devnull).wait()
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'POINDIR=tests/tmp/po', 'POOUTDIR=tests/tmp/po', 'newpot'), 0, None, None, devnull, devnull).wait()
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'POINDIR=tests/tmp/po', 'POOUTDIR=tests/tmp/po', 'newpo'), 0, None, None, devnull, devnull).wait()
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'POINDIR=tests/tmp/po', 'POOUTDIR=tests/tmp/po', 'newproject'), 0, None, None, devnull, devnull).wait()
        devnull.close()

    def tearDown(self):
        for dir in self.po_tmp_dirs:
            for root, dirs, files in os.walk(os.path.join(os.path.dirname(__file__), dir), topdown=False):
                for name in files:
                    os.remove(os.path.join(root, name))
                for name in dirs:
                    os.rmdir(os.path.join(root, name))

        for file in self.po_tmp_files:
            if os.access(file, os.F_OK):
                os.remove(file)

        if os.access('tests/tmp', os.F_OK):
            os.rmdir('tests/tmp')

    def testnewpofiles(self):
        # Create a brand new set of PO files from our en-US project files.
        # Compare the files generated in the po/ll-LL directory with
        # the number expected by a manual count of our known sources.
        po_files = []
        for po_dir in self.po_sources:
            for path in glob.glob(po_dir):
                po_files.append(os.path.basename(path) + '.po')
        po_files.sort()
        new_pofiles = os.listdir(self.locale_dir)
        new_pofiles.sort()
        self.assertEqual(len(po_files), len(new_pofiles))

    def testnewprojectfiles(self):
        # Create a brand new set of project files from PO files.
        # Compare the files created with a manual count of our known sources.
        moz_files = []
        for po_dir in self.po_sources:
            for path in glob.glob(po_dir):
                moz_files.append(os.path.basename(path))
        moz_files.sort()
        new_mozfiles = os.listdir(self.locale_dir)
        new_mozfiles.sort()
        self.assertEqual(len(moz_files), len(new_mozfiles))

    def testtranslatedfile(self):
        # "Translate" strings in a PO file, then generate the project
        # files to ensure that the translated string appears in the output.

        # Create the "translated" PO file
        commonpo = os.path.join(self.locale_dir, 'common.properties.po')
        testpo = os.path.join(self.locale_dir, 'test.properties.po')
        commonfile = open(commonpo)
        testfile = open(testpo, 'w')
        for line in commonfile:
            line = re.sub(r'^msgstr ""', r'msgstr "abcdefg"', line)
            testfile.write(line)
        commonfile.close()
        testfile.close()
        os.remove(commonpo)
        os.rename(testpo, commonpo)

        # Create the "translated" properties file
        commonprops = os.path.join(self.locale_dir, 'common.properties')
        testprops = os.path.join(self.locale_dir, 'test.properties')
        commonfile = open(commonprops)
        testfile = open(testprops, 'w')
        for line in commonfile:
            line = re.sub(r'^(.*?)=.*?$', r'\1=abcdefg', line)
            testfile.write(line)
        commonfile.close()
        testfile.close()

        # Regenerate the project files to get the translated strings in place
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'POINDIR=tests/tmp/po', 'POOUTDIR=tests/tmp/po', 'updateproject'), 0, None, None, devnull, devnull).wait()

        self.assertEqual(filecmp.cmp(commonprops, testprops), 1)

    def testupdatepo(self):
        # Add strings to a POT file, then ensure that the updated PO files
        # include the new strings

        # Create the "template" PO file
        commonpo = os.path.join(self.locale_dir, 'common.properties.po')
        testpo = os.path.join(self.locale_dir, 'test.properties.po')
        commonfile = open(commonpo)
        testfile = open(testpo, 'w')
        for line in commonfile:
            line = re.sub(r'common.properties$', r'test.properties', line)
            testfile.write(line)
        commonfile.close()
        testfile.close()

        # Create the test POT file
        commonpot = os.path.join(self.pot_dir, 'common.properties.pot')
        testpot = os.path.join(self.pot_dir, 'test.properties.pot')
        commonfile = open(commonpot)
        testfile = open(testpot, 'w')
        for line in commonfile:
            line = re.sub(r'common.properties$', r'test.properties', line)
            testfile.write(line)
        commonfile.close()
        testfile.write("\n#: common.testupdatepo")
        testfile.write('\nmsgid "TESTUPDATEPO"')
        testfile.write('\nmsgstr ""')
        testfile.close()

        # Update the PO files to get the translated strings in place
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'POINDIR=tests/tmp/po', 'POOUTDIR=tests/tmp/po', 'updatepo'), 0, None, None, devnull, devnull).wait()

        commonprops = os.path.join(self.locale_dir, 'common.properties.po')
        tempprops = os.path.join(self.locale_dir, 'temp.properties.po')
        testprops = os.path.join(self.locale_dir, 'test.properties.po')

        # Munge the common file to make it what we expect it to be
        commonfile = open(commonprops, 'a+')
        commonfile.write("\n#: common.testupdatepo")
        commonfile.write('\nmsgid "TESTUPDATEPO"')
        commonfile.write('\nmsgstr ""')
        commonfile.close()

        shutil.copyfile(commonprops, tempprops)
        commonfile = open(commonprops, 'w')
        tempfile = open(testpot)
        for line in tempfile:
            line = re.sub(r'common.properties$', r'test.properties', line)
            line = re.sub(r'^"Project-Id-Version: .*"$', r'"Project-Id-Version: PACKAGE VERSION\\n"', line)
            commonfile.write(line)
        commonfile.write("\n")
        commonfile.close()
        tempfile.close()

        # Compare the updated PO files - they should be the same
        self.assertEqual(filecmp.cmp(commonprops, testprops), 1)

if __name__ == '__main__':
    os.chdir('..')
    unittest.main()
