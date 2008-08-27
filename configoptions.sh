#!/bin/bash

echo "------------------------------------------"
echo "Options selector for Open-ILS configure"
echo "------------------------------------------"
echo " "
echo "Install Open-ILS ALL? (y/n) "
read X; 
if [ $X == "y" ] ; then 
TARGS=${TARGS}" --enable-openils-all"
fi
echo "Install Open-ILS CORE? (y/n) "
read X; 
if [ $X == "n" ] ; then 
TARGS=${TARGS}" --disable-openils-core" 
fi
echo "Install Open-ILS WEB? (y/n) "
read X;
if [ $X == "n" ] ; then 
TARGS=${TARGS}" --disable-openils-web" 
fi
echo "Install Open-ILS DB? (y/n) "
read X;
if [ $X == "n" ] ; then
TARGS=${TARGS}" --disable-openils-db"
fi
echo "Install Open-ILS MARCDUMPER? (y/n) "
read X;
if [ $X == "y" ] ; then
TARGS=${TARGS}" --enable-openils-marcdumper"
fi
echo "Install Open-ILS REPORTER? (y/n) "
read X;
if [ $X == "y" ] ; then
TARGS=${TARGS}" --enable-openils-reporter"
elseif [ $X == "n" ] ; then
TARGS=${TARGS}" --disable-openils-reporter"
fi
echo "Install Open-ILS XUL CLIENT? (y/n) "
read X;
if [ $X == "y" ] ; then
TARGS=${TARGS}" --enable-openils-client-xul"
fi
echo "Install Open-ILS XUL SERVER? (y/n) "
read X;
if [ $X == "y" ] ; then
TARGS=${TARGS}" --enable-openils-server-xul"
elseif [ $X == "n" ] ; then
TARGS=${TARGS}" --disable-openils-server-xul"
fi
echo "Install EVERGREEN CORE? (y/n) "
read X;
if [ $X == "y" ] ; then
TARGS=${TARGS}" --enable-evergreen-core"
fi
echo "Install EVERGREEN XUL CLIENT? (y/n) "
read X;
if [ $X == "y" ] ; then
TARGS=${TARGS}" --enable-evergreen-xul-client"
fi


echo ${TARGS}
./configure --with-dbver=81 --with-dbuser=evergreen --with-dbpw=evergreen ${TARGS}
make
sudo make install

