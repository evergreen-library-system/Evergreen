#!/bin/bash

ver=
while getopts r: opt; do
  case $opt in
  r)
      ver=$OPTARG
      ;;
  esac
done

if [ -z "$ver" ]; then echo "I need a version: -r"; exit; fi

outfile="../RELEASE_NOTES_$ver.txt"

title="Evergreen $ver Release Notes"

echo $title > $outfile;
for j in `seq 1 ${#title}`; do echo -n '='; done >> $outfile

echo >> $outfile
echo ':toc:' >> $outfile
echo ':numbered:' >> $outfile
echo >> $outfile
echo Upgrade notes >> $outfile
echo ------------- >> $outfile
echo >> $outfile


for i in `ls -l|grep ^d|awk '{print $9}'`; do
    files=$(ls $i/*txt 2>/dev/null)
    if [ "_$files" != "_" ]; then
        echo >> $outfile
        echo >> $outfile
        echo $i >> $outfile
        for j in `seq 1 ${#i}`; do echo -n '~'; done >> $outfile
        echo >> $outfile
        echo >> $outfile

        for j in $files; do
            echo >> $outfile
            echo >> $outfile
            cat $j >> $outfile
            echo >> $outfile
            echo >> $outfile
        done
    fi
done

files=$(ls *txt 2>/dev/null)
if [ "_$files" != "_" ]; then
    echo >> $outfile
    echo Miscellaneous >> $outfile
    echo ------------- >> $outfile
    echo >> $outfile
    for j in $files; do
        cat $j >> $outfile
    done
fi

