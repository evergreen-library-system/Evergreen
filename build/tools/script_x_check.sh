#!/bin/bash
#
# Author: Joe Atzberger
# Purpose: identify files that should be executable, but aren't.
#
# usage: run this from the base directory of your repo,
#   or wherever you want to check, inclusive of subdirectories

find . \
    \(  -path ./Open-ILS/src/python/oils -prune \
     -o -path ./build/i18n/tests/testhelper.py -prune \
     -o -path ./Open-ILS/src/extras/Evergreen.py -prune \
    \) -o \
\
    \( \
       -name "*.pl" \
    -o -name "*.sh" \
    -o -name "*.py" \
    \) \
    \( ! -executable \) \
    -ls ;

exit;


########################################################
These should be exceptions (non-executable python libs):
./Open-ILS/src/python/oils/const.py
./Open-ILS/src/python/oils/event.py
./Open-ILS/src/python/oils/org.py
./Open-ILS/src/python/oils/system.py
./Open-ILS/src/python/oils/utils/utils.py
./Open-ILS/src/python/oils/utils/csedit.py
./Open-ILS/src/python/oils/utils/idl.py
./Open-ILS/src/extras/Evergreen.py
./build/i18n/tests/testhelper.py
