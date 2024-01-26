#---------------------------------------------------------
# Makefile.am for web
## Process this file with automake to generate Makefile.in
#---------------------------------------------------------

webdir = $(WEBDIR)
opacjsdir = $(DESTDIR)$(WEBDIR)/opac/common/js
jsdojodir = $(DESTDIR)$(WEBDIR)/js/dojo
jsdojoosrfdir = $(DESTDIR)$(WEBDIR)/js/dojo/opensrf
opacextrasdir = $(DESTDIR)$(WEBDIR)/opac/extras/xsl/
reportsdir = $(WEBDIR)/reports/

if BUILDILSWEB
OILSWEB_INST = webcore-install offline-install

#webcore-install

reports_SCRIPTS = @top_srcdir@/Open-ILS/xul/staff_client/server/admin/adminlib.js
OPACJS = $(OPENSRF_LIBS)/javascript/DojoSRF.js \
	 $(OPENSRF_LIBS)/javascript/JSON_v1.js \
	 $(OPENSRF_LIBS)/javascript/md5.js \
	 $(OPENSRF_LIBS)/javascript/opensrf.js \
	 $(OPENSRF_LIBS)/javascript/opensrf_xhr.js \
	 $(OPENSRF_LIBS)/javascript/opensrf_xmpp.js \
	 @top_srcdir@/Open-ILS/xul/staff_client/chrome//content//util/date.js
JSDOJO = $(OPENSRF_LIBS)/javascript/DojoSRF.js
JSDOJOSRF = $(OPENSRF_LIBS)/javascript/md5.js \
	     $(OPENSRF_LIBS)/javascript/JSON_v1.js \
	     $(OPENSRF_LIBS)/javascript/opensrf.js \
	     $(OPENSRF_LIBS)/javascript/opensrf_xhr.js \
	     $(OPENSRF_LIBS)/javascript/opensrf_xmpp.js \
	     $(OPENSRF_LIBS)/javascript/opensrf_ws.js \
	     $(OPENSRF_LIBS)/javascript/opensrf_ws_shared.js
endif

install-exec-local: webcore-install offline-install

uninstall-hook:
	rm -R $(opacextrasdir)
	rm -R $(webdir)

webcore-install:
	$(MKDIR_P) $(DESTDIR)$(WEBDIR)
	$(MKDIR_P) $(DESTDIR)$(WEBDIR)/standalone/
	$(MKDIR_P) $(opacextrasdir)
	$(MKDIR_P) $(DESTDIR)$(reportsdir)
	$(MKDIR_P) $(DESTDIR)$(XSLDIR)
	rm -f $(DESTDIR)$(reportsdir)/fm_IDL.xml
	cp $(DESTDIR)@sysconfdir@/fm_IDL.xml $(DESTDIR)$(WEBDIR)/reports/
	cp -r @top_srcdir@/Open-ILS/web/. $(DESTDIR)$(WEBDIR)
	rm -f $(DESTDIR)$(WEBDIR)/Makefile*
	cp @top_srcdir@/Open-ILS/xsl/*.xsl $(opacextrasdir)
	cp @top_srcdir@/Open-ILS/xsl/*.xsl $(DESTDIR)$(XSLDIR)

offline-install:
	@echo "Installing offline CGIs to $(CGIDIR)/offline";
	$(MKDIR_P) $(TMP)
	$(MKDIR_P) $(DESTDIR)$(CGIDIR)/offline;
	$(MKDIR_P) $(DESTDIR)$(datadir)/offline;
	perl -pe "s{##CONFIG##}{@sysconfdir@}" < @top_srcdir@/Open-ILS/src/offline/offline.pl > $(TMP)/offline.pl;
	cp $(TMP)/offline.pl $(DESTDIR)$(CGIDIR)/offline/
	chmod +x $(DESTDIR)$(CGIDIR)/offline/offline.pl

install-data-local:
	$(MKDIR_P) $(DESTDIR)$(WEBDIR)/opac/common/js
	for i in $(OPACJS); do \
		cd $(DESTDIR)$(WEBDIR)/opac/common/js && \
		rm -f `basename $$i` && $(LN_S) $$i . ; \
	done
	$(MKDIR_P) $(DESTDIR)$(WEBDIR)/js/dojo/opensrf
	for i in $(JSDOJOSRF); do \
		cd $(DESTDIR)$(WEBDIR)/js/dojo/opensrf && \
		rm -f `basename $$i` && $(LN_S) $$i . ; \
	done
	for i in $(JSDOJO); do \
		cd $(DESTDIR)$(WEBDIR)/js/dojo && \
		rm -f `basename $$i` && $(LN_S) $$i . ; \
	done
