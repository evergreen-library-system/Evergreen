# Copyright (C) 2008 Equinox Software, Inc.
# Kevin Beswick <kevinbeswick00@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.


#---------------------------
# Init
#---------------------------

export PATH=${PATH}:/usr/sbin
AC_PREREQ(2.59)
AC_INIT(Open-ILS, trunk, open-ils-dev@list.georgialibraries.org)
AM_INIT_AUTOMAKE([OpenILS], [trunk])
AC_REVISION($Revision: 0.1 $)
AC_CONFIG_SRCDIR([configure.ac])
AC_PREFIX_DEFAULT([/openils/])
AC_SUBST(prefix)
AC_SUBST([abs_top_builddir])

#-----------------------------------
# Checks for programs.
#-----------------------------------

AC_PROG_LIBTOOL
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_LN_S
AC_PROG_MAKE_SET

#-----------------------------------
# Install options 
#-----------------------------------

# install openils-all?
#AC_ARG_ENABLE([openils-all],
#[  --enable-openils-all    enables the installation of the default openils system (base system,web,staffclient) ],
#[case "${enableval}" in
#    yes) openils_all=true;
#	 openils_core=true;
#	 openils_web=true;
#	 openils_reporter=true;
#	 openils_client_xul=true;
#	 openils_server_xul=true ;;
#    no)  openils_all=false ;;
#  *) AC_MSG_ERROR([please choose another value for --enable-openils-all (supported values are yes or no])
#esac],
#[openils_all=false])

# install evergreen-core?
AC_ARG_ENABLE([evergreen-core],
[  --disable-evergreen-core    disables the installation of the evergreen core components ],
[case "${enableval}" in
    yes) openils_core=true ;;
    no)  openils_core=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-evergreen-core (supported values are yes or no])
esac],
[openils_core=true])

AM_CONDITIONAL([BUILDILSCORE], [test x$openils_core = xtrue])

# install evergreen-web?

AC_ARG_ENABLE([evergreen-web],
[  --disable-evergreen-web    disables the installation of the openils web modules ],
[case "${enableval}" in
    yes) openils_web=true ;;
    no)  openils_web=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-evergreen-web (supported values are yes or no])
esac],
[openils_web=true])

AM_CONDITIONAL([BUILDILSWEB], [test x$openils_web = xtrue])

# build evergreen-reporter ?

AC_ARG_ENABLE([evergreen-reporter],
[  --disable-evergreen-reporter    disables the installation of the evergreen reporter module ],
[case "${enableval}" in
    yes) openils_reporter=true ;;
    no)  openils_reporter=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-evergreen-reporter (supported values are yes or no])
esac],
[openils_reporter=true])

AM_CONDITIONAL([BUILDILSREPORTER], [test x$openils_reporter = xtrue])

# build evergreen-client ?

AC_ARG_ENABLE([evergreen-client],
[  --disable-evergreen-client    disables the installation of the evergreen staff client ],
[case "${enableval}" in
    yes) openils_client=true ;;
    no)  openils_client=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-evergreen-client (supported values are yes or no])
esac],
[openils_client=true])

AM_CONDITIONAL([BUILDILSCLIENT], [test x$openils_client = xtrue])


# build evergreen java ?

AC_ARG_ENABLE([evergreen-java],
[  --enable-evergreen-java    enables the installation of the evergreen java components ],
[case "${enableval}" in
    yes) evergreen_java=true ;;
    no)  evergreen_java=false ;;
  *) AC_MSG_ERROR([please choose another value for --enable-evergreen-java (supported values are yes or no])
esac],
[evergreen_java=false])

AM_CONDITIONAL([BUILDEGJAVA], [test x$evergreen_java = xtrue])


# build the evergreen python modules?

AC_ARG_ENABLE([evergreen-python],
[  --enable-evergreen-python    enables the installation of the evergreen python modules ],
[case "${enableval}" in
    yes) EG_PYTHON_INSTALL=true ;;
    no)  EG_PYTHON_INSTALL=false ;;
  *) AC_MSG_ERROR([please choose another value for --enable-python-install (supported values are yes or no)])
esac],
[EG_PYTHON_INSTALL=false])

AM_CONDITIONAL([BUILDEGPYTHON], [test x$EG_PYTHON_INSTALL = xtrue])



#-----------------------------------
# Check for dependencies 
#-----------------------------------

AC_CHECK_PROG([MEMCACHED],memcached,yes,no)
if test $MEMCACHED = "no"; then
	AC_MSG_ERROR([*** memcached not found, aborting])
fi

AC_CHECK_PROG([ASPELL],aspell,yes,no)
if test $ASPELL = "no"; then
	AC_MSG_ERROR([*** aspell not found, aborting])
fi

AC_CHECK_PROG([CPAN],cpan,yes,no)
if test $CPAN = "no"; then
	AC_MSG_ERROR([*** cpan not found, aborting])
fi

AC_CHECK_PROG([YAZ],yaz-config,yes,no)
if test $YAZ = "no"; then
	AC_MSG_ERROR([*** yaz not found, aborting])
fi

AC_CHECK_PROG([PERL],perl,yes,no)
if test $PERL = "no"; then 
	AC_MSG_ERROR([*** perl not found, aborting])
fi


#-----------------------------------
# Set install path variables 
#-----------------------------------

AC_ARG_WITH([tmp],
[ --with-tmp=path		location for the tmp dir for OpenILS (default is /tmp) ],
[TMP=${withval}],
[TMP=/tmp])
AC_SUBST([TMP])


APXS2=`apxs2 -q BINDIR`/apxs2
AC_SUBST([APXS2])

APACHE2_HEADERS=`apxs2 -q INCLUDEDIR`
AC_SUBST([APACHE2_HEADERS])

APR_HEADERS=`apr-config --includedir`
AC_SUBST([APR_HEADERS])

AC_ARG_WITH([libxml],
[  --with-libxml=path         location of the libxml headers (default is /usr/include/libxml2)],
[LIBXML2_HEADERS=${withval}],
[LIBXML2_HEADERS=/usr/include/libxml2/])
AC_SUBST([LIBXML2_HEADERS])

AC_ARG_WITH([dbi],
[  --with-dbi=path		location of the libdbi libraries (default is /usr/local/lib/dbd)],
[DBI_LIBS=${withval}],
[DBI_LIBS=/usr/local/lib/dbd/])
AC_SUBST([DBI_LIBS])

AC_ARG_WITH([opensrf-headers],
[  --with-opensrf-headers=path		location of the opensrf header files (default is /openils/include/)],
[OPENSRF_HEADERS=${withval}],
[OPENSRF_HEADERS=/openils/include/])
AC_SUBST([OPENSRF_HEADERS])

AC_ARG_WITH([opensrf-libs],
[  --with-opensrf-libs=path		location of the opensrf libraries (default is /openils/lib/)],
[OPENSRF_LIBS=${withval}],
[OPENSRF_LIBS=/openils/lib/])
AC_SUBST([OPENSRF_LIBS])

#------------------------------------
# Checks for libraries. 
#------------------------------------

# Check for the existance of libraries in non-standard locations

AC_MSG_CHECKING(for -lopensrf)
if test -e ${OPENSRF_LIBS}/libopensrf.so; then
AC_MSG_RESULT([yes])
else
AC_MSG_ERROR([*** libopensrf not found (or not in location specified to configure), aborting])
fi

# Check for the rest of the libraries

#check for dynamic linking functions
AC_CHECK_LIB(dl,dlopen)

#check for the libdbi library
AC_CHECK_LIB(dbi,dbi_initialize)

#to check for the availability and function of a particular
#driver we need a runtime check (since the driver is loaded
#dynamically). This example checks for the mysql driver
AC_MSG_CHECKING([for libdbi pgsql driver (dynamic load)])
AC_RUN_IFELSE(
  [AC_LANG_PROGRAM(,
    [[dbi_initialize(0); return(dbi_conn_new("pgsql") ? 0 : 1);]])],
  [AC_MSG_RESULT("yes")],
  [AC_MSG_FAILURE("pgsql driver not installed?")])

AC_CHECK_LIB([expat], [main], [], AC_MSG_ERROR(*** OpenILS requires libexpat))
AC_CHECK_LIB([readline], [main], [], AC_MSG_ERROR(*** OpenILS requires libreadline))
AC_CHECK_LIB([xml2], [main], [], AC_MSG_ERROR(*** OpenILS requires libxml2))
AC_CHECK_LIB([xslt], [main], [], AC_MSG_ERROR(*** OpenILS requires libxslt))
AC_CHECK_LIB([yaz], [main], [], AC_MSG_ERROR(*** OpenILS requires libyaz))
AC_CHECK_LIB([perl], [main], [], AC_MSG_ERROR(*** OpenILS requires libperl-dev))
AC_CHECK_LIB([pq], [main], [], AC_MSG_ERROR(*** OpenILS requires libpq))


#------------------------------------
# Checks for header files.
#------------------------------------

AC_HEADER_STDC
AC_CHECK_HEADERS([fcntl.h langinfo.h locale.h stdlib.h string.h unistd.h])

#-------------------------------------------------------------------
# Checks for typedefs, structures, and compiler characteristics.
#-------------------------------------------------------------------

AC_C_CONST
AC_TYPE_SIZE_T
AC_STRUCT_TM
AC_HEADER_STDBOOL

#-------------------------------------------------------------------
# Checks for library functions.
#-------------------------------------------------------------------

AC_FUNC_STRFTIME
AC_FUNC_STRTOD
AC_CHECK_FUNCS([localtime_r memset nl_langinfo setlocale strcasecmp strchr strdup strerror strncasecmp])

#----------------------------
# Create Makefiles/Output
#----------------------------

AC_CONFIG_FILES([Makefile
                 Open-ILS/examples/Makefile
                 Open-ILS/src/Makefile
                 Open-ILS/src/apachemods/Makefile
                 Open-ILS/src/c-apps/Makefile
                 Open-ILS/src/extras/Makefile
                 Open-ILS/src/java/Makefile
                 Open-ILS/src/python/Makefile
                 Open-ILS/xul/staff_client/Makefile
		 Open-ILS/src/offline/offline-config.pl
		 Open-ILS/src/extras/eg_config
                 build/i18n/Makefile],  [if test -e "./Open-ILS/src/extras/eg_config"; then chmod 755 Open-ILS/src/extras/eg_config; fi])
AC_OUTPUT

#-------------------------------------------------
# OUTPUT STUFF 
#-------------------------------------------------

AC_MSG_RESULT([])
AC_MSG_RESULT([--------------------- Configuration options:  -----------------------])

AC_MSG_RESULT([])
AC_MSG_RESULT([-------- Installation Options: --------])
if test "$openils_core" = "true" ; then
	AC_MSG_RESULT([Evergreen Core:			yes])
else
	AC_MSG_RESULT([Evergreen Core:			no])
fi
if test "$openils_web" = "true" ; then
        AC_MSG_RESULT([Evergreen Web:			yes])
else
        AC_MSG_RESULT([Evergreen Web:			no])
fi
if test "$openils_reporter" = "true" ; then
        AC_MSG_RESULT([Evergreen Reporter:		yes])
else
        AC_MSG_RESULT([Evergreen Reporter:		no])
fi
if test "$openils_client" = "true" ; then
        AC_MSG_RESULT([Evergreen Staff Client:		yes])
else
        AC_MSG_RESULT([Evergreen Staff Client:		no])
fi
if test "$EG_PYTHON_INSTALL" = "true" ; then
        AC_MSG_RESULT([Evergreen Python Components:	yes])
else
        AC_MSG_RESULT([Evergreen Python Components:	no])
fi
if test "$evergreen_java" = "true" ; then
        AC_MSG_RESULT([Evergreen Java Components:	yes])
else
        AC_MSG_RESULT([Evergreen Java Components:	no])
fi
AC_MSG_RESULT([]) 
AC_MSG_RESULT([-------- Installation Directories --------])
AC_MSG_RESULT(Installation dir prefix:                  ${prefix})
AC_MSG_RESULT(Temporary dir location:                   ${TMP})
AC_MSG_RESULT(APXS2 dir location:                       ${APXS2})
AC_MSG_RESULT(Apache headers location:                  ${APACHE2_HEADERS})
AC_MSG_RESULT(APR headers location:                     ${APR_HEADERS})
AC_MSG_RESULT(libxml headers location:                  ${LIBXML2_HEADERS})
AC_MSG_RESULT(libdbi dir location:                      ${DBI_LIBS})
AC_MSG_RESULT(OpenSRF Headers location:                 ${OPENSRF_HEADERS})
AC_MSG_RESULT(OpenSRF Libraries location:               ${OPENSRF_LIBS})

AC_MSG_RESULT([----------------------------------------------------------------------])

