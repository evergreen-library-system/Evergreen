export DEF_LDFLAGS = -L. -L$(TMP) -L$(OPENSRF_LIBS)
export DEF_CFLAGS = -D_LARGEFILE64_SOURCE -pipe -g -Wall -O2 -fPIC -I@top_srcdir@/include -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) -I$(APR_HEADERS)  -I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(OPENSRF_HEADERS)
export DEF_LDLIBS = -lopensrf

COMMON = testsuite.c
AM_CFLAGS = $(DEF_CFLAGS) -DOSRF_LOG_PARAMS
AM_LDFLAGS = $(DEF_LDLIBS) -L$(DBI_LIBS)

TESTS = check_util check_idl
check_PROGRAMS = check_util check_idl

check_util_SOURCES = $(COMMON) check_util.c
check_util_CFLAGS = $(AM_CFLAGS)
check_util_LDFLAGS = $(AM_LDFLAGS) -loils_idl -loils_utils -lcheck
check_util_DEPENDENCIES = ../liboils_idl.la ../liboils_utils.la

check_idl_SOURCES = $(COMMON) check_idl.c
check_idl_CFLAGS = $(AM_CFLAGS)
check_idl_LDFLAGS = $(AM_LDFLAGS) -loils_idl -loils_utils -lcheck
check_idl_DEPENDENCIES = ../liboils_idl.la ../liboils_utils.la

