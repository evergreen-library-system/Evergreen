#!/bin/bash
find $1 -type d -name CVS -exec rm -rf {} \; 2> /dev/null
find $1 -type d -name OPEN_ILS_STAFF_CLIENT -exec rm -rf {} \; 2> /dev/null
exit 0
