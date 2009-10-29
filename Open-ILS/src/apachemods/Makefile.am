#-------------------------------------------------------------
# Makefile.am for Open-ILS/src/apachemods
# Author: Kevin Beswick (kevinbeswick00@gmail.com)
## Process this file with automake to generate Makefile.in
#-------------------------------------------------------------

AM_CFLAGS = -D_LARGEFILE64_SOURCE -Wall -I@abs_top_srcdir@/Open-ILS/include/ -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) -I$(APR_HEADERS) -I$(OPENSRF_HEADERS)
AM_LDFLAGS = -L$(LIBDIR) -L$(OPENSRF_LIBS)

if BUILDAPACHEMODS
OILSAPACHEINST = apachemods
endif

install-exec-local: $(OILSAPACHEINST)

apachemods:
	$(APXS2) -c $(AM_LDFLAGS) -lxml2 -lopensrf -lxslt -lexpat $(AM_CFLAGS) @srcdir@/mod_xmlent.c
	$(APXS2) -i -a @srcdir@/mod_xmlent.la
	$(APXS2) -c $(AM_LDFLAGS) -lxml2 -lopensrf -lxslt -lexpat $(AM_CFLAGS) @srcdir@/mod_idlchunk.c
	$(APXS2) -i -a @srcdir@/mod_idlchunk.la

clean-local:
	rm -f @srcdir@/mod_xmlent.la @srcdir@/mod_xmlent.lo @srcdir@/mod_xmlent.slo
	rm -f @srcdir@/mod_idlchunk.la @srcdir@/mod_idlchunk.lo @srcdir@/mod_idlchunk.slo
