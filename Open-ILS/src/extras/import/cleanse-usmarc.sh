#!/bin/bash

DUMPER=/home/miker/cvs/ILS/Open-ILS/src/extras/import/marcFilterDump.pl


$DUMPER -X -f MARC8 -t UTF8 -r '//*[@tag="999"]' $*
