#!/bin/bash
# This can take a file containing output produced by the replacement dump function in custom.js.example
# and break it into multiple files, one for each numeric dump prefix.  Not perfect, since it'll truncate
# messages that aren't on one contiguous line.
for x in `grep '>>>>>>>>>>>>>' $* | perl -ne 'if ( />>>> .. (\d+) =/ ) { print "$1\n"; }'` ; do
grep $x $* > $x
done
grep '>>>>>>>>>>>>>' $*
