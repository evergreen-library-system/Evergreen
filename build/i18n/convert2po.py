#!/usr/bin/env python
# -----------------------------------------------------------------------
# Copyright (C) 2007  Laurentian University
# Dan Scott <dscott@laurentian.ca>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# --------------------------------------------------------------------
#
# Generates a complete set of PO files from DTD and JavaScript property
# files for use in translation.
#
# DTD files are placed in a /dtd/ subdirectory and property files are
# placed in a /property/ subdirectory so that we can round-trip the
# files back into DTD and property file format once they have been
# translated.
#
# Prerequisite: Translate Toolkit from http://translate.sourceforge.net/

import glob
import os.path
from translate.convert import moz2po

def convert2po(dir, extension):
    """
    Run moz2po on property and entity files to generate PO files.

    For each property or entity file:
        moz2po.main(["-i", "(name).ext", "-o", "(name).po"])
    """
    files = os.path.abspath(dir)
    for file in glob.glob(os.path.join(files , '*.' + extension)):
        base = os.path.basename(file)
        sep = base.find(".")
        root = base[:sep]
        target = os.path.join(os.path.abspath('.'), extension);
        if os.access(target, os.F_OK) is False:
            os.mkdir(target)
        moz2po.main(["-i", file, "-o", os.path.join(target, root + ".po"), "--progress", "none"])

if __name__=='__main__':
    convert2po('../../Open-ILS/web/opac/locale/en-US/', 'dtd')
    convert2po('../../Open-ILS/xul/staff_client/chrome/locale/en-US/', 'properties')
