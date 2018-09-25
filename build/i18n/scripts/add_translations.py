#!/usr/bin/env python3
# -*- Mode: python; coding: utf-8 -*-
# ---------------------------------------------------------------
# Copyright © 2015 Jason J.A. Stephenson <jason@sigio.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

"""A program to assist with the process of adding new po and pot files
into the Evergreen git repository.
"""

import argparse, os, re, subprocess

__version__ = "1.0.2"

modifiedFiles = []
acceptedFiles = []
rejectedFiles = []

def cd_root():
    """Change working directory to the root of the git repository."""
    with subprocess.Popen(['git', 'rev-parse', '--show-toplevel'], 
                           stdout=subprocess.PIPE) as git:
        output = git.stdout.read().decode('utf8')
        directory = output.strip()
        if directory != os.getcwd():
            os.chdir(directory)

def commit():
    """Commit the accepted files into git with a default message."""
    with subprocess.Popen(['git', 'commit', '-sm',
                           'Translation updates - newpot'],
                          stdout=subprocess.PIPE) as git:
        output = git.stdout.read().decode('utf8')
        return output

def get_files():
    """Get list of changed or new files in build/i18n/po."""
    args = ['git', 'status', '--porcelain', '--', 'build/i18n/po']
    with subprocess.Popen(args, stdout=subprocess.PIPE) as git:
        lines = git.stdout.read().decode('utf8').splitlines()
        for line in lines:
            if line.startswith(' M'):
                modifiedFiles.append(line[3:])
            elif line.startswith('??'):
                path = line[3:]
                if os.path.isdir(path):
                    path += '.'
                acceptedFiles.append(path)

def add_files():
    """Stage (git add) accepted files to be committed."""
    args = ['git', 'add']
    args += acceptedFiles
    with subprocess.Popen(args, stdout=subprocess.PIPE) as git:
        output = git.stdout.read().decode('utf8')
        return output

def reset_files():
    """'Reset' rejected file changes by checking the files out again."""
    args = ['git', 'checkout', '--']
    args += rejectedFiles
    with subprocess.Popen(args, stdout=subprocess.PIPE) as git:
        output = git.stdout.read().decode('utf8')
        return output

def diff_file(file):
    """Run git diff to get file changes."""
    with subprocess.Popen(['git', 'diff', file], stdout=subprocess.PIPE) as git:
        output = git.stdout.read().decode('utf8')
        return output

def process_modified():
    """Process diff output and ask human if a change should be kept."""
    for file in modifiedFiles:
        print(diff_file(file))
        print('====================  K for keep ==')
        x = input()
        if x == 'k' or x == 'K':
            acceptedFiles.append(file)
        else:
            rejectedFiles.append(file)

def autoprocess_modified():
    """Process diff output without human intervention."""
    isDiff = re.compile(r'^(?:\+[^\+]|-[^-])')
    isMeta = re.compile(r'^(?:\+|-)"[-a-zA-z]+: ')
    for file in modifiedFiles:
        keep = False
        diffLines = diff_file(file).splitlines()
        for line in diffLines:
            if re.match(isDiff, line) and not re.match(isMeta, line):
                keep = True
                break
        if keep:
            acceptedFiles.append(file)
        else:
            rejectedFiles.append(file)

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="Run this in your Evergreen git repo after running make newpot."
    )
    parser.add_argument("-m", "--manual", action="store_true",
                        help="manually decide which files to add")
    parser.add_argument("-c", "--commit", action="store_true",
                        help="automatically commit added files")
    return parser.parse_args()
        
def main():
    arguments = parse_arguments()
    cd_root()
    get_files()
    if arguments.manual:
        process_modified()
    else:
        autoprocess_modified()
    if len(rejectedFiles) > 0:
        reset_files()
    if len(acceptedFiles) > 0:
        add_files()
        if arguments.commit:
            print(commit())

########################################

if __name__ == '__main__':
    main()
