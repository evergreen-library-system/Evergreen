#-----------------------------------------------------------
# Makefile.am for Open-ILS/src/c-apps
# Author: Kevin Beswick (kevinbeswick00@gmail.com)
# Process this file with automake to generate Makefile.in
#-----------------------------------------------------------

SUBDIRS = . tests

AM_CFLAGS = $(DEF_CFLAGS) -DOSRF_LOG_PARAMS -I@top_srcdir@/include/ -I @HIREDIS_HEADERS@
AM_LDFLAGS = $(DEF_LDFLAGS) -L$(DBI_LIBS) -lopensrf

bin_PROGRAMS = oils_dataloader dump_idl idlval test_json_query test_qstore
oils_dataloader_SOURCES = oils_dataloader.c
oils_dataloader_LDFLAGS = $(AM_LDFLAGS) -loils_idl
oils_dataloader_DEPENDENCIES = liboils_idl.la liboils_utils.la

dump_idl_SOURCES = dump_idl.c
dump_idl_LDFLAGS = $(AM_LDFLAGS) -loils_idl
dump_idl_DEPENDENCIES = liboils_idl.la liboils_utils.la

idlval_SOURCES = idlval.c oils_sql.c
idlval_CFLAGS = $(AM_CFLAGS)
idlval_LDFLAGS = $(AM_LDFLAGS) -loils_idl -loils_utils
idlval_DEPENDENCIES = liboils_idl.la liboils_utils.la

test_json_query_SOURCES = test_json_query.c oils_sql.c
test_json_query_CFLAGS = $(AM_CFLAGS)
test_json_query_LDFLAGS = $(AM_LDFLAGS) -loils_idl -loils_utils
test_json_query_DEPENDENCIES = liboils_idl.la liboils_utils.la

test_qstore_SOURCES = test_qstore.c buildSQL.c oils_buildq.c oils_execsql.c oils_sql.c oils_storedq.c 
test_qstore_CFLAGS = $(AM_CFLAGS)
test_qstore_LDFLAGS = $(AM_LDFLAGS) -loils_idl -loils_utils
test_qstore_DEPENDENCIES = liboils_idl.la liboils_utils.la

lib_LTLIBRARIES = liboils_idl.la liboils_utils.la liboils_cstore.la liboils_qstore.la liboils_rstore.la liboils_pcrud.la liboils_auth.la liboils_auth_internal.la

liboils_idl_la_SOURCES = oils_idl-core.c
liboils_idl_la_LDFLAGS = -version-info 2:0:0

liboils_utils_la_SOURCES = oils_utils.c oils_event.c
liboils_utils_la_LDFLAGS = -loils_idl -version-info 2:0:0

liboils_cstore_la_SOURCES = oils_cstore.c oils_sql.c
liboils_cstore_la_LDFLAGS = $(AM_LDFLAGS) -loils_utils -module -version-info 2:0:0
liboils_cstore_la_DEPENDENCIES = liboils_utils.la

liboils_qstore_la_SOURCES = oils_qstore.c oils_sql.c oils_storedq.c oils_buildq.c buildSQL.c oils_execsql.c
liboils_qstore_la_LDFLAGS = $(AM_LDFLAGS) -loils_utils -module -version-info 2:0:0
liboils_qstore_la_DEPENDENCIES = liboils_utils.la

liboils_rstore_la_SOURCES = oils_rstore.c oils_sql.c
liboils_rstore_la_LDFLAGS = $(AM_LDFLAGS) -loils_utils -module -version-info 2:0:0
liboils_rstore_la_DEPENDENCIES = liboils_utils.la

liboils_pcrud_la_SOURCES = oils_pcrud.c oils_sql.c
liboils_pcrud_la_LDFLAGS = $(AM_LDFLAGS) -loils_utils -module -version-info 2:0:0
liboils_pcrud_la_DEPENDENCIES = liboils_utils.la

liboils_auth_la_SOURCES = oils_auth.c
liboils_auth_la_LDFLAGS = -module -loils_utils -lpcre2-8 -version-info 2:0:0
liboils_auth_la_DEPENDENCIES = liboils_utils.la

liboils_auth_internal_la_SOURCES = oils_auth_internal.c
liboils_auth_internal_la_LDFLAGS = -module -loils_utils -version-info 2:0:0
liboils_auth_internal_la_DEPENDENCIES = liboils_utils.la



