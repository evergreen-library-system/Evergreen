#!/bin/bash

CONFIG="$1";

[ -z "$CONFIG" ] && echo "usage: $0 <bootstrap_config>" && exit;


JSDIR="/openils/var/web/js/util";

echo "Updating fieldmapper";
perl fieldmapper.pl		> "$JSDIR/fieldmapper.js";

echo "Updating web_fieldmapper";
perl fieldmapper.pl 1	> "$JSDIR/web_fieldmapper.js";

echo "Updating OrgTree";
perl org_tree_js.pl "$CONFIG" | sed 's/null//g'	> "$JSDIR/OrgTree.js";

echo "Done";

