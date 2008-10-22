#!/bin/bash
pushd . >/dev/null 2>/dev/null
cd `dirname $0`

xsltproc ../../examples/extract-IDL-permissions.xsl ../../examples/fm_IDL.xml|perl -e 'while(<>){s/^\s+(.*)\s+$/$1/o;print("$1\n")unless(/^\s*$/ || /\s+/)}'|sort -u > /tmp/oils_permacrud_perm_list
grep -A1 perm_list ../sql/Pg/950.data.seed-values.sql|grep "'"|cut -f2 -d"'"|sort -u > /tmp/oils_sql_perm_list

echo "New permissions from permacrud:"
echo

for i in `diff -pu /tmp/oils_sql_perm_list /tmp/oils_permacrud_perm_list |grep '^+'|cut -f2 -d'+'|grep -v '^$'`; do
	echo "INSERT INTO permission.perm_list (code) VALUES ('$i');"
done

echo

popd >/dev/null 2>/dev/null

