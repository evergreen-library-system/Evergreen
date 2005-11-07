#!/bin/bash

DUMPER=/home/miker/cvs/ILS/Open-ILS/src/extras/import/../marcdumper/marcdumper


$DUMPER -X -f MARC8 -t UTF8 -r '//*[@tag="999"]' $*
