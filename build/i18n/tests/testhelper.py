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

def setUp(obj):
    sys.path.append(os.path.join(obj.basedir, '../scripts/'))
    sys.path.append(obj.basedir)
    obj.tearDown()
    for tmpdir in obj.tmpdirs:
        os.mkdir(tmpdir)

def tearDown(obj):
    for tmpdir in obj.tmpdirs:
        if os.access(tmpdir, os.F_OK):
            for tmpfile in os.listdir(tmpdir):
                os.remove(os.path.join(tmpdir, tmpfile))
            os.rmdir(tmpdir)


