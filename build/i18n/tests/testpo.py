#!/usr/bin/env python

import filecmp
import glob
import os
import re
import subprocess
import sys
import unittest

class TestPOFramework(unittest.TestCase):

    po_sources = ('../../Open-ILS/web/opac/locale/en-US/*.dtd', \
        '../../Open-ILS/xul/staff_client/chrome/locale/en-US/*.properties')

    def setUp(self):
        devnull = open('/dev/null', 'w')
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'newpo'), 0, None, None, devnull, devnull).wait()
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'newproject'), 0, None, None, devnull, devnull).wait()

    def tearDown(self):
        for file in os.listdir('po/ll-LL/'):
            os.remove(os.path.join('po/ll-LL', file))
        os.rmdir('po/ll-LL/')
        for file in os.listdir('locale/ll-LL/'):
            os.remove(os.path.join('locale/ll-LL/', file))
        os.rmdir('locale/ll-LL/')

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
        proc = subprocess.Popen(('make', 'LOCALE=ll-LL', 'newproject'), 0, None, None, devnull, devnull).wait()

        self.assertEqual(filecmp.cmp(commonprops, testprops), 1)

if __name__ == '__main__':
    os.chdir('..')
    unittest.main()
