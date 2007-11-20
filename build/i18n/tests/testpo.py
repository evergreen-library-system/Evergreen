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

    po_sources = ('../../Open-ILS/web/opac/locale/en-US/*.dtd', \
        '../../Open-ILS/xul/staff_client/chrome/locale/en-US/*.properties')

    def setUp(self):
        self.tearDown()
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'newpo'), 0, None, None, devnull, devnull).wait()
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'newproject'), 0, None, None, devnull, devnull).wait()
        devnull.close()

    def tearDown(self):
        tmpdirs = ('po/ll-LL', 'locale/ll-LL')
        tmpfiles = ('po/test.properties.pot', 'locale/ll-LL/temp.properties.po')
        for dir in tmpdirs:
            if os.access(dir, os.F_OK):
                for file in os.listdir(dir):
                    os.remove(os.path.join(dir, file))
                os.rmdir(dir)

        for file in tmpfiles:
            if os.access(file, os.F_OK):
                os.remove(file)

    def testnewpofiles(self):
        # Create a brand new set of PO files from our en-US project files.
        # Compare the files generated in the po/ll-LL directory with
        # the number expected by a manual count of our known sources.
        po_files = []
        for po_dir in self.po_sources:
            for path in glob.glob(po_dir):
                po_files.append(os.path.basename(path) + '.po')
        po_files.sort()
        new_pofiles = os.listdir('po/ll-LL/')
        new_pofiles.sort()
        self.assertEqual(po_files, new_pofiles)

    def testnewprojectfiles(self):
        # Create a brand new set of project files from PO files.
        # Compare the files created with a manual count of our known sources.
        moz_files = []
        for po_dir in self.po_sources:
            for path in glob.glob(po_dir):
                moz_files.append(os.path.basename(path))
        moz_files.sort()
        new_mozfiles = os.listdir('locale/ll-LL/')
        new_mozfiles.sort()
        self.assertEqual(moz_files, new_mozfiles)

    def testtranslatedfile(self):
        # "Translate" strings in a PO file, then generate the project
        # files to ensure that the translated string appears in the output.

        # Create the "translated" PO file
        commonpo = 'po/ll-LL/common.properties.po'
        testpo = 'po/ll-LL/test.properties.po'
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
        commonprops = 'locale/ll-LL/common.properties'
        testprops = 'locale/ll-LL/test.properties'
        commonfile = open(commonprops)
        testfile = open(testprops, 'w')
        for line in commonfile:
            line = re.sub(r'^(.*?)=.*?$', r'\1=abcdefg', line)
            testfile.write(line)
        commonfile.close()
        testfile.close()

        # Regenerate the project files to get the translated strings in place
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'updateproject'), 0, None, None, devnull, devnull).wait()

        self.assertEqual(filecmp.cmp(commonprops, testprops), 1)

    def testupdatepo(self):
        # Add strings to a POT file, then ensure that the updated PO files
        # include the new strings

        # Create the "template" PO file
        commonpo = 'po/ll-LL/common.properties.po'
        testpo = 'po/ll-LL/test.properties.po'
        commonfile = open(commonpo)
        testfile = open(testpo, 'w')
        for line in commonfile:
            line = re.sub(r'common.properties$', r'test.properties', line)
            testfile.write(line)
        commonfile.close()
        testfile.close()

        # Create the test POT file
        commonpot = 'po/common.properties.pot'
        testpot = 'po/test.properties.pot'
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
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'updatepo'), 0, None, None, devnull, devnull).wait()

        commonprops = 'po/ll-LL/common.properties.po'
        tempprops = 'po/ll-LL/temp.properties.po'
        testprops = 'po/ll-LL/test.properties.po'

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
