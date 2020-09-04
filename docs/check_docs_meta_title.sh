#!/bin/bash

# This script will search a website and gather up all of the <title></title> for each page
# the results will land in out.csv
# This is a nice aid to help us find pages that do not have the "right" headings

wget --spider -r -l inf -w .25 -nc -nd $1 -R bmp,css,gif,ico,jpg,jpeg,js,mp3,mp4,pdf,png,PNG,JPG,swf,txt,xml,xls,zip 2>&1 | tee wglog  

rm out.csv
cat wglog | grep '^--' | awk '{print $3}' | sort | uniq | while read url; do {

printf "%s* Retreiving title for: %s$url%s " "$bldgreen" "$txtrst$txtbld" "$txtrst"  
printf ""${url}","`curl -# ${url} | sed -n -E 's!.*<title>(.*)</title>.*!\1!p'`" , " >> out.csv  
printf " "          
}; done

