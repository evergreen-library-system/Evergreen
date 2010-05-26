#!/bin/bash
#
# Author: Joe Atzberger
# Purpose: identify files that should be executable, but aren't.
#
# usage: run this from the base directory of your repo,
#   or wherever you want to check, inclusive of subdirectories

find . \( -name "*.pl" -o -name "*.sh" -o -name "*.py" \) ! -executable -ls

