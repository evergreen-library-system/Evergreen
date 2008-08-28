#!/bin/sh
# autogen.sh - generates configure using the autotools

: ${LIBTOOLIZE=libtoolize}
: ${ACLOCAL=aclocal}
: ${AUTOHEADER=autoheader}
: ${AUTOMAKE=automake}
: ${AUTOCONF=autoconf}


${LIBTOOLIZE} --force --copy
${ACLOCAL}
${AUTOMAKE} --add-missing


${AUTOCONF}

echo 
echo "---------------------------------------------"
echo "autogen finished running, now run ./configure"
echo "---------------------------------------------"
