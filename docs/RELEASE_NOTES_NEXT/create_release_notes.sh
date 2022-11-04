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

outfile="../RELEASE_NOTES_$ver.adoc"

title="= Evergreen $ver Release Notes ="

echo $title > $outfile;
echo ':toc:' >> $outfile
echo ':numbered:' >> $outfile
echo ':toclevels: 3' >> $outfile
echo >> $outfile
echo '== Upgrade notes ==' >> $outfile
echo >> $outfile

echo '== New Features ==' >> $outfile
echo >> $outfile

echo ':leveloffset: +2' >> $outfile

for i in `ls -l|grep ^d|awk '{print $9}'`; do
    files=$(ls $i/*{txt,adoc} 2>/dev/null)
    if [ "_$files" != "_" ]; then
        echo >> $outfile
        echo >> $outfile
        echo "= $i =" >> $outfile
        echo >> $outfile

        for j in $files; do
            echo >> $outfile
            cat $j >> $outfile
            echo >> $outfile
        done
    fi
done

files=$(ls *{txt,adoc} 2>/dev/null | grep -v 'RELEASE_NOTE_TEMPLATE.adoc')
if [ "_$files" != "_" ]; then
    echo >> $outfile
    echo '= Miscellaneous =' >> $outfile
    echo >> $outfile
    for j in $files; do
        cat $j >> $outfile
    done
fi

echo >> $outfile
echo ':leveloffset: 0' >> $outfile
echo >> $outfile

if [ -f _acknowledgments ]; then
    echo >> $outfile
    echo "== Acknowledgments ==" >> $outfile
    cat _acknowledgments >> $outfile
    echo >> $outfile
fi
