#!/bin/bash

CONFIG="$1";

[ -z "$CONFIG" ] && echo "usage: $0 <bootstrap_config>" && exit;

JSDIR="/openils/var/web/opac/common/js/";
SLIMPACDIR="/openils/var/web/opac/extras/slimpac/";

echo "Updating fieldmapper";
perl fieldmapper.pl "$CONFIG"	> "$JSDIR/fmall.js";

echo "Updating web_fieldmapper";
perl fieldmapper.pl "$CONFIG" "web_core"	> "$JSDIR/fmcore.js";

echo "Updating OrgTree";
perl org_tree_js.pl "$CONFIG" > "$JSDIR/OrgTree.js";

echo "Updating OrgTree HTML";
perl org_tree_html_options.pl "$CONFIG" "$SLIMPACDIR/lib_list.inc";

echo "Done";

