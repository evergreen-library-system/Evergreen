#--------------------------------------------------------------
# Makefile.am for Open-ILS/src/extras
# Author: Kevin Beswick (kevinbeswick00@gmail.com)
## Process this file with automake to generate Makefile.in
#-------------------------------------------------------------

LDADD = $(DEF_LDLIBS) -lreadline -loils_utils -lopensrf -lxml2 -loils_idl
AM_LDFLAGS = -L@top_builddir@/Open-ILS/src/c-apps -L$(OPENSRF_LIBS)
AM_CFLAGS = $(DEF_CFLAGS) -I@top_srcdir@/include

bin_PROGRAMS = oils_requestor
oils_requestor_SOURCES = oils_requestor.c
oils_requestor_LDADD = $(LDADD)
