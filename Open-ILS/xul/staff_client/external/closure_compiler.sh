#!/bin/sh
find build/ -name '*.js' -exec java -jar $* --js {} --js_output_file {}~ \;
exit 0
