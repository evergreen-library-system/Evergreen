export DEF_LDFLAGS = -L@abs_top_srcdir@/Open-ILS/src/c-apps -L$(OPENSRF_LIBS)
export DEF_CFLAGS = -D_LARGEFILE64_SOURCE -pipe -g -Wall -O2 -fPIC -I@abs_top_srcdir@/Open-ILS/include -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) -I$(APR_HEADERS) -I$(LIBXML2_HEADERS)/libxml -I$(OPENSRF_HEADERS)
export DEF_LDLIBS = -lopensrf

COMMON = testsuite.c
AM_CFLAGS = $(DEF_CFLAGS) -DOSRF_LOG_PARAMS
AM_LDFLAGS = $(DEF_LDFLAGS) $(DEF_LDLIBS) -L$(DBI_LIBS)

TESTS = check_util check_idl
check_PROGRAMS = check_util check_idl

check_util_SOURCES = $(COMMON) check_util.c
check_util_CFLAGS = $(AM_CFLAGS) $(CHECK_CFLAGS)
check_util_LDFLAGS = $(AM_LDFLAGS) $(CHECK_LIBS) -loils_idl -loils_utils 
check_util_DEPENDENCIES = ../liboils_idl.la ../liboils_utils.la

check_idl_SOURCES = $(COMMON) check_idl.c
check_idl_CFLAGS = $(AM_CFLAGS) $(CHECK_CFLAGS)
check_idl_LDFLAGS = $(AM_LDFLAGS) $(CHECK_LIBS) -loils_idl -loils_utils 
check_idl_DEPENDENCIES = ../liboils_idl.la ../liboils_utils.la

