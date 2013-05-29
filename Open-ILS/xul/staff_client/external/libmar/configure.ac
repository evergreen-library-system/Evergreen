#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ([2.61])
AC_INIT([libmar], [1.0], [jason@sigio.com])
AM_INIT_AUTOMAKE([foreign])
AC_CONFIG_SRCDIR([tool/mar.c])
AC_CONFIG_HEADER([config.h])

# Check for MAR_CHANNEL_ID:
AC_ARG_WITH([marchannelid],
[  --with-marchannelid=channelname    default name for MAR channel (default is blank)],
[mar_channel_id=${withval}],
[mar_channel_id=])
AC_DEFINE_UNQUOTED([MAR_CHANNEL_ID], ["${mar_channel_id}"], [Default MAR_CHANNEL_ID])

# Check for MOZ_APP_VERSION
AC_ARG_WITH([mozappversion],
[  --with-mozappversion=appversion    default version for app (default is 19.0.1)],
[moz_app_version=${withval}],
[moz_app_version="19.0.1"])
AC_DEFINE_UNQUOTED([MOZ_APP_VERSION], ["${moz_app_version}"], [Default MOZ_APP_VERSION])


# Checks for programs.
AC_PROG_CC
AC_PROG_RANLIB

# Checks for libraries.
AC_CHECK_LIB([bz2],[BZ2_bzCompressInit],,AC_MSG_ERROR(*** OpenILS requires libbz2))

# Checks for header files.
AC_CHECK_HEADERS([err.h fcntl.h netinet/in.h stdint.h stdio.h stdlib.h string.h sys/stat.h sys/types.h unistd.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_TYPE_INT64_T
AC_TYPE_SIZE_T
AC_TYPE_UINT32_T
AC_TYPE_UINT64_T

# Checks for library functions.
AC_FUNC_FSEEKO
AC_FUNC_MALLOC
AC_FUNC_REALLOC
AC_CHECK_FUNCS([memset mkdir strdup strrchr])

AC_CONFIG_FILES([Makefile
                 src/Makefile
                 tool/Makefile])
AC_OUTPUT
