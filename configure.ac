# Copyright (C) 2008 Equinox Software, Inc.
# Kevin Beswick <kevinbeswick00@gmail.com>
# Copyright (C) 2010 Laurentian University 
# Dan Scott <dscott@laurentian.ca>
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
AC_PREREQ(2.61)
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
AC_PROG_MKDIR_P
AM_PROG_CC_C_O

#-----------------------------------
# Install options 
#-----------------------------------

# install openils-all?
#AC_ARG_ENABLE([openils-all],
#[  --enable-openils-all    enables the installation of the default openils system (base system,web,staffclient) ],
#[case "${enableval}" in
#    yes) openils_all=true;
#     openils_core=true;
#     openils_web=true;
#     openils_updates=true;
#     openils_reporter=true;
#     openils_client_xul=true;
#     openils_server_xul=true ;;
#    no)  openils_all=false ;;
#  *) AC_MSG_ERROR([please choose another value for --enable-openils-all (supported values are yes or no])
#esac],
#[openils_all=false])

# install evergreen-core?
AC_ARG_ENABLE([core],
[  --disable-core    disables installation of the Evergreen core components ],
[case "${enableval}" in
    yes) openils_core=true ;;
    no)  openils_core=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-core (supported values are yes or no])
esac],
[openils_core=true])

AM_CONDITIONAL([BUILDILSCORE], [test x$openils_core = xtrue])

# install evergreen-web?

AC_ARG_ENABLE([web],
[  --disable-web    disables installation of the Evergreen web modules ],
[case "${enableval}" in
    yes) openils_web=true ;;
    no)  openils_web=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-web (supported values are yes or no])
esac],
[openils_web=true])

AM_CONDITIONAL([BUILDILSWEB], [test x$openils_web = xtrue])

# install evergreen-updates?

AC_ARG_ENABLE([updates],
[  --disable-updates    disables installation of the Evergreen updates folder ],
[case "${enableval}" in
    yes) openils_updates=true ;;
    no)  openils_updates=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-updates (supported values are yes or no])
esac],
[openils_updates=true])

AM_CONDITIONAL([BUILDILSUPDATES], [test x$openils_updates = xtrue])

# Default updates host?
AC_ARG_WITH([updateshost],
[  --with-updateshost=hostname    default hostname for automatic updates (default is blank)],
[AUTOUPDATE_HOST=${withval}],
[AUTOUPDATE_HOST=])
AC_SUBST([AUTOUPDATE_HOST])

# install Evergreen Apache modules?
AC_ARG_ENABLE([apache-modules],
[  --disable-apache-modules    disables installation of the Evergreen Apache modules ],
[case "${enableval}" in
    yes) build_apachemods=true ;;
    no)  build_apachemods=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-apache-modules (supported values are yes or no])
esac],
[build_apachemods=true])

AM_CONDITIONAL([BUILDAPACHEMODS], [test x$build_apachemods = xtrue])

# build evergreen-reporter ?

AC_ARG_ENABLE([reporter],
[  --disable-reporter    disables installation of the Evergreen reporter module ],
[case "${enableval}" in
    yes) openils_reporter=true ;;
    no)  openils_reporter=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-reporter (supported values are yes or no])
esac],
[openils_reporter=true])

AM_CONDITIONAL([BUILDILSREPORTER], [test x$openils_reporter = xtrue])

# build evergreen-client ?

AC_ARG_ENABLE([client],
[  --disable-client    disables installation of the Evergreen staff client ],
[case "${enableval}" in
    yes) openils_client=true ;;
    no)  openils_client=false ;;
  *) AC_MSG_ERROR([please choose another value for --disable-client (supported values are yes or no])
esac],
[openils_client=true])

AM_CONDITIONAL([BUILDILSCLIENT], [test x$openils_client = xtrue])


# build evergreen java ?

AC_ARG_ENABLE([java],
[  --enable-java    enables installation of the Evergreen Java components ],
[case "${enableval}" in
    yes) evergreen_java=true ;;
    no)  evergreen_java=false ;;
  *) AC_MSG_ERROR([please choose another value for --enable-java (supported values are yes or no])
esac],
[evergreen_java=false])

AM_CONDITIONAL([BUILDEGJAVA], [test x$evergreen_java = xtrue])


# build the evergreen python modules?

AC_ARG_ENABLE([python],
[  --enable-python    enables installation of the Evergreen Python modules ],
[case "${enableval}" in
    yes) EG_PYTHON_INSTALL=true ;;
    no)  EG_PYTHON_INSTALL=false ;;
  *) AC_MSG_ERROR([please choose another value for --enable-python (supported values are yes or no)])
esac],
[EG_PYTHON_INSTALL=false])

AM_CONDITIONAL([BUILDEGPYTHON], [test x$EG_PYTHON_INSTALL = xtrue])

#-----------------------------------
# Check for dependencies 
#-----------------------------------

AC_ARG_WITH([opensrf-headers],
[  --with-opensrf-headers=path location of the OpenSRF header files (default is /openils/include/)],
[OPENSRF_HEADERS=${withval}],
[OPENSRF_HEADERS=/openils/include/])
AC_SUBST([OPENSRF_HEADERS])

# We need this for JavaScript
AC_ARG_WITH([opensrf-libs],
[  --with-opensrf-libs=path    location of the OpenSRF libraries (default is /openils/lib/)],
[OPENSRF_LIBS=${withval}],
[OPENSRF_LIBS=/openils/lib/])
AC_SUBST([OPENSRF_LIBS])

AC_ARG_WITH([tmp],
[  --with-tmp=path             location of the Evergreen temporary directory (default is /tmp) ],
[TMP=${withval}],
[TMP=/tmp])
AC_SUBST([TMP])

AC_ARG_WITH([apxs],
[  --with-apxs=path            location of the apxs Apache configuration tool (default is /usr/bin/apxs2)],
[APXS2=${withval}],
[APXS2=/usr/bin/apxs2])

# If the passed in value doesn't work, try some reasonable defaults
# Fedora puts the file in /usr/sbin/apxs, for example
if ! test -x "$APXS2"; then
    for i in /usr/bin /usr/sbin /usr/local/apache/bin /usr/local/apache2/bin ; do
        for j in apxs apxs2 ; do
            if test -x "$i/$j"; then
                APXS2="$i/$j"
                break
            fi
        done
    done
fi
AC_SUBST([APXS2])

AC_ARG_WITH([apache],
[  --with-apache=path          location of the Apache headers (default is /usr/include/apache2)],
[APACHE2_HEADERS=${withval}],
[APACHE2_HEADERS=/usr/include/apache2])
AC_SUBST([APACHE2_HEADERS])

AC_ARG_WITH([apr],
[  --with-apr=path             location of the Apache Portable Runtime (APR) headers (default is /usr/include/apr-1.0/)],
[APR_HEADERS=${withval}],
[APR_HEADERS=/usr/include/apr-1.0])
AC_SUBST([APR_HEADERS])

AC_ARG_WITH([libxml2],
[  --with-libxml2=path         location of the libxml2 headers (default is /usr/include/libxml2)],
[LIBXML2_HEADERS=${withval}],
[LIBXML2_HEADERS=/usr/include/libxml2/])
AC_SUBST([LIBXML2_HEADERS])

AC_ARG_WITH([dbi],
[  --with-dbi=path             location of the libdbi driver libraries (default is /usr/local/lib/dbd)],
[DBI_LIBS=${withval}],
[DBI_LIBS=/usr/local/lib/dbd/])

# If the passed in value doesn't work, fall back to reasonable defaults
# Distributions are starting to package a good version of libdbi / libdbd
if ! test -d "$DBI_LIBS"; then
    for i in /usr/lib/dbd/ /usr/lib64/dbd /usr/local/lib/dbd/ ; do
        if test -d "$i"; then
            DBI_LIBS="$i"
            break
        fi
    done
fi
AC_SUBST([DBI_LIBS])

if test "x$openils_core" = "xtrue"; then

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

    #------------------------------------
    # Checks for libraries. 
    #------------------------------------

    # Check for the existence of libraries in non-standard locations

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
    AC_CHECK_LIB([ncurses], [main], [], AC_MSG_ERROR(*** OpenILS requires libncurses))
    AC_CHECK_LIB([readline], [main], [], AC_MSG_ERROR(*** OpenILS requires libreadline))
    AC_CHECK_LIB([xml2], [main], [], AC_MSG_ERROR(*** OpenILS requires libxml2))
    AC_CHECK_LIB([xslt], [main], [], AC_MSG_ERROR(*** OpenILS requires libxslt))
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

    AC_CONFIG_FILES([Open-ILS/examples/Makefile
             Open-ILS/src/c-apps/Makefile
             Open-ILS/src/extras/Makefile
             Open-ILS/src/java/Makefile
             Open-ILS/src/python/Makefile])
fi

if test "x$build_apachemods" = "xtrue"; then

    #-----------------------------------
    # Set install path variables 
    #-----------------------------------

    #APACHE PREFORK DEV TEST
    AC_MSG_CHECKING([APXS2])
    if test -x "${APXS2}"; then
    AC_MSG_RESULT([yes])
    else
    AC_MSG_ERROR([*** apxs not found in ${APXS2}, aborting])
    fi  

    AC_CONFIG_FILES([Open-ILS/src/apachemods/Makefile])
fi

AC_CONFIG_FILES([Makefile
         Open-ILS/src/Makefile
         Open-ILS/src/perlmods/Makefile
         Open-ILS/web/Makefile
         Open-ILS/updates/Makefile
         Open-ILS/xul/staff_client/Makefile
         Open-ILS/src/extras/eg_config
         ],
        [
            if test -e "./Open-ILS/src/extras/eg_config"; then chmod 755 Open-ILS/src/extras/eg_config; fi;
        ])
AC_OUTPUT

#-------------------------------------------------
# OUTPUT STUFF 
#-------------------------------------------------

AC_MSG_RESULT([])
AC_MSG_RESULT([--------------------- Configuration options:  -----------------------])

AC_MSG_RESULT([])
AC_MSG_RESULT([-------- Installation Options: --------])
if test "$openils_core" = "true" ; then
    AC_MSG_RESULT([Evergreen Core:          yes])
else
    AC_MSG_RESULT([Evergreen Core:          no])
fi
if test "$build_apachemods" = "true" ; then
AC_MSG_RESULT([Evergreen Apache module:     yes])
    else
AC_MSG_RESULT([Evergreen Apache module:     no])
    fi
    if test "$openils_web" = "true" ; then
AC_MSG_RESULT([Evergreen Web:               yes])
    else
AC_MSG_RESULT([Evergreen Web:               no])
    fi
    if test "$openils_updates" = "true" ; then
AC_MSG_RESULT([Evergreen Updates:           yes])
    else
AC_MSG_RESULT([Evergreen Updates:           no])
    fi
    if test "$openils_reporter" = "true" ; then
AC_MSG_RESULT([Evergreen Reporter:          yes])
    else
AC_MSG_RESULT([Evergreen Reporter:          no])
    fi
    if test "$openils_client" = "true" ; then
AC_MSG_RESULT([Evergreen Staff Client:      yes])
    else
AC_MSG_RESULT([Evergreen Staff Client:      no])
    fi
    if test "$EG_PYTHON_INSTALL" = "true" ; then
AC_MSG_RESULT([Evergreen Python Components: yes])
    else
AC_MSG_RESULT([Evergreen Python Components: no])
    fi
    if test "$evergreen_java" = "true" ; then
AC_MSG_RESULT([Evergreen Java Components:   yes])
    else
AC_MSG_RESULT([Evergreen Java Components:   no])
fi
AC_MSG_RESULT([]) 
AC_MSG_RESULT([-------- Installation Directories --------])
AC_MSG_RESULT(Installation directory prefix:            ${prefix})
AC_MSG_RESULT(Temporary directory:                      ${TMP})
AC_MSG_RESULT(APXS2 location:                           ${APXS2})
AC_MSG_RESULT(Apache headers location:                  ${APACHE2_HEADERS})
AC_MSG_RESULT(APR headers location:                     ${APR_HEADERS})
AC_MSG_RESULT(libxml2 headers location:                 ${LIBXML2_HEADERS})
AC_MSG_RESULT(libdbi location:                          ${DBI_LIBS})
AC_MSG_RESULT(OpenSRF headers location:                 ${OPENSRF_HEADERS})
AC_MSG_RESULT(OpenSRF libraries location:               ${OPENSRF_LIBS})

AC_MSG_RESULT([----------------------------------------------------------------------])

# vim:et:ts=4:sw=4:
