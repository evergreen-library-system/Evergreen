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
AC_INIT(Open-ILS, 3.15.5, open-ils-dev@list.georgialibraries.org)
AC_CONFIG_SRCDIR([configure.ac])
AC_CONFIG_MACRO_DIR([m4])
AM_INIT_AUTOMAKE
AC_REVISION($Revision: 0.1 $)
AC_CONFIG_SUBDIRS([Open-ILS/xul/staff_client/external/libmar])
AC_SUBST(prefix)
AC_SUBST([abs_top_builddir])
#-----------------------------------
# Checks for programs.
#-----------------------------------


LT_INIT
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

# Default updates host?
AC_ARG_WITH([initialhost],
[  --with-initialhost=hostname    default hostname for staff client (default is blank)],
[INITIAL_HOST=${withval}],
[INITIAL_HOST=])
AC_SUBST([INITIAL_HOST])


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


#-----------------------------------
# Check for dependencies 
#-----------------------------------
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

AC_ARG_WITH([libxml2],
[  --with-libxml2=path         location of the libxml2 headers (default is /usr/include/libxml2)],
[LIBXML2_HEADERS=${withval}],
[LIBXML2_HEADERS=/usr/include/libxml2/])
AC_SUBST([LIBXML2_HEADERS])

PKG_CHECK_MODULES([DBI], [dbi])

AC_ARG_WITH([hiredis],
[  --with-hiredis=path         location of the hiredis headers (default is /usr/include/hiredis/))],
[HIREDIS_HEADERS=${withval}],
[HIREDIS_HEADERS=/usr/include/hiredis/])
AC_SUBST([HIREDIS_HEADERS])

AC_ARG_WITH([dbi],
[  --with-dbi=path             location of the libdbi driver libraries (default is /usr/lib/x86_64-linux-gnu/dbd/)],
[DBI_LIBS=${withval}],
[DBI_LIBS=/usr/lib/x86_64-linux-gnu/dbd/])

AC_ARG_WITH([perlbase],
[  --with-perlbase=path        base location to install Perl modules (default based on Config.pm)],
[PERL_BASE=${withval}],
[PERL_BASE=x])
AC_SUBST([PERL_BASE])

AC_ARG_WITH([redis-accounts],
[  --with-redis-accounts=path  location of the redis accounts file (default is $sysconfdir/redis-accounts.txt)],
[REDIS_ACCOUNTS=${withval}],
[REDIS_ACCOUNTS=$sysconfdir/redis-accounts.txt])
AC_SUBST([REDIS_ACCOUNTS])

# Skip password propagation if there is no password field.
AC_CHECK_FILE(
    [$REDIS_ACCOUNTS],
    [
        OPENSRF_BUS_PASSWORD=$(grep 'ACL SETUSER opensrf on >' ${REDIS_ACCOUNTS} | cut -d'>' -f2)
        GATEWAY_BUS_PASSWORD=$(grep 'ACL SETUSER gateway on >' ${REDIS_ACCOUNTS} | cut -d'>' -f2)
        ROUTER_BUS_PASSWORD=$(grep 'ACL SETUSER router on >' ${REDIS_ACCOUNTS} | cut -d'>' -f2)
        AC_SUBST([OPENSRF_BUS_PASSWORD])
        AC_SUBST([GATEWAY_BUS_PASSWORD])
        AC_SUBST([ROUTER_BUS_PASSWORD])
    ],
    [AC_MSG_RESULT(Skipping Redis accounts password propagation)]
)

AM_CONDITIONAL(CHECK_TESTS, test x$enable_tests = xyes)

if test "x$openils_core" = "xtrue"; then

    AC_PATH_PROG([OSRF_CONFIG], [osrf_config])
    if test "x$OSRF_CONFIG" == "x"; then
        AC_MSG_ERROR([Could not find osrf_config.
        Ensure OpenSRF is installed and that the PATH environment variable includes
        the OpenSRF executables. For example: PATH=\$PATH:/openils/bin ./configure])
    fi

    AC_ARG_WITH([opensrf-headers],
    [  --with-opensrf-headers=path location of the OpenSRF header files],
    [OPENSRF_HEADERS=${withval}],
    [OPENSRF_HEADERS=`$OSRF_CONFIG --includedir`])
    AC_SUBST([OPENSRF_HEADERS])

    # We need this for JavaScript
    AC_ARG_WITH([opensrf-libs],
    [  --with-opensrf-libs=path    location of the OpenSRF libraries],
    [OPENSRF_LIBS=${withval}],
    [OPENSRF_LIBS=`$OSRF_CONFIG --libdir`])
    AC_SUBST([OPENSRF_LIBS])

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

    PKG_CHECK_MODULES([YAZ],[yaz],[YAZ=yes],[YAZ=no])
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

    # IF the OpenSRF libs are installed in a non-standard location, such as
    # /openils/lib, the compilation test will fail. Support that case.
    LDFLAGS="-L$OPENSRF_LIBS"

    # checking this specific function name ensures we have a "new enough" libopensrf but isn't actually checking the lib version :-/
    AC_CHECK_LIB([opensrf], [osrf_buffer_free], [], AC_MSG_ERROR(*** OpenILS requires libopensrf))
    AC_CHECK_LIB([readline], [main], [], AC_MSG_ERROR(*** OpenILS requires libreadline))
    AC_CHECK_LIB([xml2], [main], [], AC_MSG_ERROR(*** OpenILS requires libxml2))
    AC_CHECK_LIB([hiredis], [redisConnect], [], AC_MSG_ERROR(***OpenSRF requires libhiredis))
    AC_CHECK_LIB([xslt], [main], [], AC_MSG_ERROR(*** OpenILS requires libxslt))
    AC_CHECK_LIB([pq], [main], [], AC_MSG_ERROR(*** OpenILS requires libpq))
    PKG_CHECK_MODULES(pcre, libpcre >= 3.0.0)


    #------------------------------------
    # Checks for header files.
    #------------------------------------

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

    #---------------------------------
    # Check for unit test framework.
    #---------------------------------
    PKG_CHECK_MODULES([CHECK], [check >= 0.9.0], [enable_tests=yes],
                      [enable_tests=no])
    if test "x$enable_tests" = "xno"; then
        AC_MSG_WARN(Check unit testing framework not found.)
    fi

    #----------------------------
    # Create Makefiles/Output
    #----------------------------

    AC_CONFIG_FILES([Open-ILS/examples/Makefile
             Open-ILS/src/c-apps/Makefile
             Open-ILS/src/c-apps/tests/Makefile
             Open-ILS/src/extras/Makefile])
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
AC_MSG_RESULT([]) 
AC_MSG_RESULT([-------- Installation Directories --------])
AC_MSG_RESULT(Installation directory prefix:            ${prefix})
AC_MSG_RESULT(Temporary directory:                      ${TMP})
AC_MSG_RESULT(APXS2 location:                           ${APXS2})
AC_MSG_RESULT(libxml2 headers location:                 ${LIBXML2_HEADERS})
AC_MSG_RESULT(libdbi location:                          ${DBI_LIBS})
AC_MSG_RESULT(OpenSRF headers location:                 ${OPENSRF_HEADERS})
AC_MSG_RESULT(OpenSRF libraries location:               ${OPENSRF_LIBS})
AC_MSG_RESULT(libhiredis headers location:              ${HIREDIS_HEADERS})
AC_MSG_RESULT(Redis Accounts: ${REDIS_ACCOUNTS})

AC_MSG_RESULT([----------------------------------------------------------------------])

# vim:et:ts=4:sw=4:
