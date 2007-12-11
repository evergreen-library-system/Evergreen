import os
import re
import sys

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

def setUp(self):
    sys.path.append(os.path.join(self.basedir, '../scripts/'))
    sys.path.append(self.basedir)
    self.tearDown()
    for dir in self.tmpdirs:
        os.mkdir(dir)

def tearDown(self):
    for dir in self.tmpdirs:
        if os.access(dir, os.F_OK):
            for file in os.listdir(dir):
                os.remove(os.path.join(dir, file))
            os.rmdir(dir)


