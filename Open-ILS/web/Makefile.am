#---------------------------------------------------------
# Makefile.am for web
## Process this file with automake to generate Makefile.in
#---------------------------------------------------------

webdir = $(WEBDIR)
opacjsdir = $(DESTDIR)$(WEBDIR)/opac/common/js
jsdojodir = $(DESTDIR)$(WEBDIR)/js/dojo
jsdojoosrfdir = $(DESTDIR)$(WEBDIR)/js/dojo/opensrf
opacextrasdir = $(DESTDIR)$(WEBDIR)/opac/extras/xsl/
reportsdir = $(DESTDIR)$(WEBDIR)/reports/

if BUILDILSWEB
OILSWEB_INST = webcore-install offline-install cgi-bootstrap

#webcore-install

reports_SCRIPTS = @top_srcdir@/Open-ILS/xul/staff_client/server/admin/adminlib.js
opacjs_SCRIPTS = $(OPENSRF_LIBS)/javascript/DojoSRF.js \
		 $(OPENSRF_LIBS)/javascript/JSON_v0.js \
		 $(OPENSRF_LIBS)/javascript/JSON_v1.js \
		 $(OPENSRF_LIBS)/javascript/md5.js \
		 $(OPENSRF_LIBS)/javascript/opensrf.js \
		 $(OPENSRF_LIBS)/javascript/opensrf_xhr.js \
		 $(OPENSRF_LIBS)/javascript/opensrf_xmpp.js \
		 @top_srcdir@/Open-ILS/xul/staff_client/chrome//content//util/date.js
jsdojo_SCRIPTS = $(OPENSRF_LIBS)/javascript/DojoSRF.js
jsdojoosrf_SCRIPTS = $(OPENSRF_LIBS)/javascript/md5.js \
		     $(OPENSRF_LIBS)/javascript/JSON_v1.js \
		     $(OPENSRF_LIBS)/javascript/opensrf.js \
		     $(OPENSRF_LIBS)/javascript/opensrf_xhr.js \
		     $(OPENSRF_LIBS)/javascript/opensrf_xmpp.js
endif

install-exec-local: webcore-install offline-install cgi-bootstrap

uninstall-hook:
	rm -R $(opacextrasdir)
	rm -R $(webdir)

webcore-install:
	mkdir -p $(WEBDIR)
	mkdir -p $(WEBDIR)/opac/extras/slimpac/
	mkdir -p $(WEBDIR)/standalone/
	mkdir -p $(opacextrasdir)
	mkdir -p $(DESTDIR)$(reportsdir)
	mkdir -p $(XSLDIR)
	rm -f $(DESTDIR)$(reportsdir)/fm_IDL.xml
	cp $(DESTDIR)@sysconfdir@/fm_IDL.xml $(DESTDIR)$(WEBDIR)/reports/
	cp -r @top_srcdir@/Open-ILS/web/. $(DESTDIR)$(WEBDIR)
	cp @top_srcdir@/Open-ILS/xsl/*.xsl $(opacextrasdir)
	cp @top_srcdir@/Open-ILS/xsl/*.xsl $(XSLDIR)
	cp -r $(DESTDIR)$(WEBDIR)/opac/skin/default/* $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/
	cp -r @top_srcdir@/Open-ILS/web/opac/skin/craftsman/* $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/mresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/rresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/rdetail.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/advanced.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/myopac.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/cnbrowse.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/mresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/rresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/rdetail.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/advanced.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/myopac.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/cnbrowse.xml

offline-install:
	@echo "Installing offline CGIs to $(CGIDIR)/offline";
	mkdir -p $(TMP)
	mkdir -p $(CGIDIR)/offline;
	mkdir -p $(datadir)/offline;
	perl -pe "s{##CONFIG##}{@sysconfdir@}" < @top_srcdir@/Open-ILS/src/offline/offline.pl > $(TMP)/offline.pl;
	cp $(TMP)/offline.pl $(DESTDIR)$(CGIDIR)/offline/
	chmod +x $(DESTDIR)$(CGIDIR)/offline/offline.pl

cgi-bootstrap:
	@echo "Installing cgi's to $(CGIDIR)"
	mkdir -p $(TMP)/cgi-bin
	mkdir -p $(CGIDIR)
	for i in @top_srcdir@/Open-ILS/src/cgi-bin/*cgi; do xxx=`basename $$i`; perl -pe "s{##CONFIG##}{@sysconfdir@}" < $$i > $(TMP)/cgi-bin/$$xxx; done
	cp $(TMP)/cgi-bin/*cgi $(CGIDIR)
	cp -r @top_srcdir@/Open-ILS/src/cgi-bin/support $(CGIDIR)
	chmod 755 $(DESTDIR)$(CGIDIR)/*cgi

