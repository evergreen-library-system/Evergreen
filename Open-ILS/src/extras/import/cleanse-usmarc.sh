#!/bin/bash

DUMPER=../marcdumper/marcdumper


$DUMPER -X -f MARC8 -t UTF8 -r '/*/*[@tag="999"]' $*
