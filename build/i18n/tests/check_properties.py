#!/usr/bin/env python
# -----------------------------------------------------------------------
# Copyright (C) 2008  Laurentian University
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
# -----------------------------------------------------------------------

# vim:et:sw=4:ts=4: set fileencoding=utf-8 :

"""
Parse i18n properties files and XUL / JavaScript files looking for trouble
    * Invalid strings
    * Unused strings
    * Missing strings
"""

import os
import re

DEBUG = False

PROP_DIRS = (
        '../../../Open-ILS/xul/staff_client/server/locale/en-US/',
        '../../../Open-ILS/xul/staff_client/chrome/locale/en-US/'
        )

XUL_DIRS = (
        '../../../Open-ILS/xul/staff_client/server/',
        '../../../Open-ILS/xul/staff_client/chrome/',
        )

def parse_properties():
    """
    Parse the properties files in known places
    """

    basedir = os.path.normpath(os.path.dirname(os.path.abspath(__file__)))

    properties = {}

    prop_files = []

    for p_dir in PROP_DIRS:
        p_dir = os.path.normpath(os.path.join(basedir, p_dir))
        file_list = os.listdir(p_dir)
        for p_file in file_list:
            if os.path.splitext(p_file)[1] == '.properties':
                prop_files.append(os.path.join(p_dir, p_file))

    prefix = os.path.commonprefix(prop_files)

    for p_file in prop_files:

        # Get the shortest unique address for this file
        short_pf = p_file[len(prefix):]

        prop_file = open(p_file, 'r')

        line_num = 1

        for line in prop_file:
            line_num += 1

            # Get rid of trailing linefeed
            line = line[0:-1]

            # Skip comments
            if not line or line[0] == '#':
                continue

            # Split property/value on first = sign
            unpack = re.split('=', line, 1)

            # If a line doesn't have an = sign, is that okay (run-on from previous?) or illegal?
            # I think it's illegal
            if len(unpack) != 2:
                print("%s:%d: No property in line [%s]" % (short_pf, line_num, line))
                continue

            prop_key, value = unpack

            if not properties.has_key(prop_key):
                properties[prop_key] = [{'value': value, 'file': short_pf}]
                continue

            for entry in properties[prop_key]:
                if entry['file'] == short_pf:
                    print("File: %s:%d"% (short_pf, line_num))
                    print("\tDuplicate key '%s' in line [%s]" % (prop_key, line[0:-1]))
                    continue

            properties[prop_key].append({'value': value, 'file': short_pf})

        prop_file.close()

    return properties

def check_xul_files(props):
    """
    Finds all the XUL and JavaScript files
    """

    basedir = os.path.normpath(os.path.dirname(os.path.abspath(__file__)))

    xul_files = []

    for x_dir in XUL_DIRS:
        for root, dirs, files in os.walk(os.path.join(basedir, x_dir)):
            for x_file in files:
                if os.path.splitext(x_file)[1] == '.xul' or os.path.splitext(x_file)[1] == '.js':
                    check_xul(root, x_file, props)

def check_xul(root, filename, props):
    """
    Parse all getString() and getFormattedString() calls in XUL and JavaScript
    files to ensure:
      * that the requested property exists
      * that every property is actually required
    """

    num_strings = 0

    # Typical example of a getString request:
    # document.getElementById('catStrings').getString('staff.cat.bib_brief.deleted')
    strings = re.compile(r'''\(\s*?(['"])([^'"]+?)Strings\1\s*?\)\.getString\(\s*?(['"])([^'"]+?)\3\s*?\)''')

    # Typical example of a getFormattedString request:
    # document.getElementById('catStrings').getFormattedString('staff.cat.bib_brief.record_id', [docid])
    formed_strings = re.compile(r'''\(\s*?(['"])([^'"]+?)Strings\1\s*?\)\.getFormattedString\(\s*?(['"])([^'"]+?)\3\s*?,\s*\[(.+?)\]\s*\)\)''')

    xul = open(os.path.join(root, filename), 'r')
    content = xul.read()
    xul.close()

    if DEBUG:
        print "File: %s" % (os.path.normpath(os.path.join(root, filename)))

    for s_match in strings.finditer(content):
        num_strings += 1
        #print "\tStringset: %s ID: %s" % (s_match.group(2), s_match.group(4))
        if not props.has_key(s_match.group(4)):
            print "File: %s" % (os.path.normpath(os.path.join(root, filename)))
            print "\tID %s not found, expected in %sStrings" % (s_match.group(4), s_match.group(2))

    for s_match in formed_strings.finditer(content):
        num_strings += 1
        #print "\tStringset: %s ID: %s, data: %s" % (s_match.group(2), s_match.group(4), s_match.group(5))
        if not props.has_key(s_match.group(4)):
            print "File: %s" % (os.path.normpath(os.path.join(root, filename)))
            print "\tID %s not found, expected in %sStrings" % (s_match.group(4), s_match.group(2))

    if DEBUG:
        print "\t%d i18n calls found" % (num_strings)

if __name__ == '__main__':
    props = parse_properties() 
    check_xul_files(props)
