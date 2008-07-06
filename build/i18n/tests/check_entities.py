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
Parse DTD files and XUL files looking for trouble
    * Missing entities
"""

import os
import re

DEBUG = False

DTD_DIRS = (
        '../../../Open-ILS/web/opac/locale/en-US/',
        )

XUL_DIRS = (
        '../../../Open-ILS/xul/staff_client/server/',
        '../../../Open-ILS/xul/staff_client/chrome/',
        )

def parse_entities():
    """
    Parse entities files in known places
    """

    basedir = os.path.normpath(os.path.dirname(os.path.abspath(__file__)))

    entities = {
        "amp" : "&",
        "lt" : "<",
        "gt" : ">",
        "nbsp" : ">",
        "quot" : ">",
    }

    dtd_files = []

    for p_dir in DTD_DIRS:
        p_dir = os.path.normpath(os.path.join(basedir, p_dir))
        file_list = os.listdir(p_dir)
        for d_file in file_list:
            if os.path.splitext(d_file)[1] == '.dtd':
                dtd_files.append(os.path.join(p_dir, d_file))

    prefix = os.path.commonprefix(dtd_files)

    for d_file in dtd_files:
		if DEBUG:
			print "Checking %s\n" % (d_file)

        # Get the shortest unique address for this file
        short_df = d_file[len(prefix):]

        dtd_file = open(d_file, 'r')

        line_num = 1

        for line in dtd_file:
            line_num += 1

            # Get rid of trailing linefeed
            line = line[0:-1]

            # Parse entity/value 
            unpack = re.search(r'<!ENTITY\s+(.+?)\s+([\'"])(.*?)\2\s*>', line)
            if DEBUG and unpack:
                print(unpack.groups())

            # Skip anything other than entity definitions
            # Note that this makes some massive assumptions:
            #   1. that we only have with one entity defined per line
            #   2. that we only have single-line entities
            #   3. that the entity begins in position 0 on the line
            if not unpack or not line or not line.startswith('<!ENTITY'):
                continue

            # If we did not retrieve an entity and definition, that's probably not good
            if len(unpack.groups()) != 3:
                print("%s:%d: No entity defined on line [%s]" % (short_df, line_num, line))
                continue

            entity_key, quote, value = unpack.groups()
            if DEBUG:
                print(entity_key, value)

            if not entities.has_key(entity_key):
                entities[entity_key] = [{'value': value, 'file': short_df}]
                continue

            for entry in entities[entity_key]:
                if ['file'] == short_df:
                    print("%s:%d: Duplicate key '%s' in line [%s]" % (short_df, line_num, entity_key, line[0:-1]))
                    continue

            entities[entity_key].append({'value': value, 'file': short_df})

        dtd_file.close()

    return entities

def check_xul_files(entities):
    """
    Finds all the XUL and JavaScript files
    """

    basedir = os.path.normpath(os.path.dirname(os.path.abspath(__file__)))

    xul_files = []

    for x_dir in XUL_DIRS:
        for root, dirs, files in os.walk(x_dir):
            for x_file in files:
                if os.path.splitext(x_file)[1] == '.xul' or os.path.splitext(x_file)[1] == '.js':
                    check_xul(root, x_file, entities)

def check_xul(root, filename, entities):
    """
    Checks all XUL files to ensure:
      * that the requested entity exists
      * that every entity is actually required
    """

    num_strings = 0

    # Typical entity usage:
    # &blah.blah.blah_bity.blah;
    strings = re.compile(r'''&([a-zA-Z:_][a-zA-Z0-9:_\-.]+);''')

    xul = open(os.path.join(root, filename), 'r')
    content = xul.read()
    xul.close()

    if DEBUG:
        print("File: %s" % (os.path.normpath(os.path.join(root, filename))))

    for s_match in strings.finditer(content):
        num_strings += 1
        if not entities.has_key(s_match.group(1)):
            print("File: %s" % (os.path.normpath(os.path.join(root, filename))))
            print("\tEntity %s not found, expected in %s" % (s_match.group(1), 'lang.dtd'))

	# Find bad entities
	bad_strings = re.compile(r'''&([^a-zA-Z:_]?[a-zA-Z0-9:_]*[^a-zA-Z0-9:_\-.;][a-zA-Z0-9:_\-.]*);''')

	# Match character entities (&#0129; etc), which are okay
	char_entity = re.compile(r'''^((#([0-9])+)|(#x([0-9a-fA-F])+))$''')

	for s_match in bad_strings.finditer(content):
		# Rule out character entities and URL concatenation
		if (not char_entity.search(s_match.group(1))) and s_match.group(1) != "'":
			print("File: %s" % (os.path.normpath(os.path.join(root, filename))))
			print("\tBad entity: %s" % (s_match.group(1)))

    if DEBUG:
        print("\t%d entities found" % (num_strings))

if __name__ == '__main__':
    entities = parse_entities() 
    check_xul_files(entities)
