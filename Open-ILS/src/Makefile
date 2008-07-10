
export LDFLAGS			+= -L . -L$(TMP) -L $(OPENSRF_LIBS)
export CFLAGS			+= -pipe -g -Wall -O2 -fPIC -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) -I$(APR_HEADERS) \
				-D_LARGEFILE64_SOURCE -I$(LIBXML2_HEADERS)/libxml -I$(TMP) -I$(OPENSRF_HEADERS) \
								-I$(OPENSRF_HEADERS)/opensrf # <-- stop-gap until opensrf compilation can be fixed with external include directory

export INCDIR = "$(INCLUDEDIR)/openils/"

export STAFF_CLIENT_BUILD_ID = `/bin/cat ../xul/staff_client/build/BUILD_ID`

all:  c_apps client-xul mod_xmlent

install:	perl-install web-install server-xul string-templates-install xsl-install c_apps-install circ_rules-install offline-install storage-bootstrap cgi-bootstrap

web-install:	webcore-install autojs-install mod_xmlent-install offline-install

circ_rules-install:
	@echo $@
	mkdir -p $(CIRCRULESDIR)
	mkdir -p $(PENALTYRULESDIR)
	mkdir -p $(CATALOGSCRIPTDIR)
	cp javascript/backend/circ/*.js $(CIRCRULESDIR)
	cp javascript/backend/penalty/*.js $(PENALTYRULESDIR)
	cp javascript/backend/catalog/*.js $(CATALOGSCRIPTDIR)


# -----------------------------------------------------------------------------------
# Web stuff
# -----------------------------------------------------------------------------------
mod_xmlent:
	@echo $@
	make -C apachemods mod_xmlent.so

oils_cgi:
	@echo $@
	make -C apachemods oils_cgi.so

oils_cgi-install:
	@echo $@
	make -C apachemods oils_cgi-install

mod_xmlent-install:
	@echo $@
	make -C apachemods mod_xmlent-install

client-xul:
	@echo $@
	@echo "Building staff client"
	make -C ../xul/staff_client 

server-xul:
	@echo $@
	mkdir -p ${WEBDIR}
	@echo "Creating ${WEBDIR}/xul/"
	mkdir -p ${WEBDIR}/xul/
	@echo "BUILD_ID = ${STAFF_CLIENT_BUILD_ID}"
	@echo "Copying xul into ${WEBDIR}/xul/${STAFF_CLIENT_BUILD_ID}"
	mkdir -p "${WEBDIR}/xul/${STAFF_CLIENT_BUILD_ID}"
	cp -R ../xul/staff_client/build/server "${WEBDIR}/xul/${STAFF_CLIENT_BUILD_ID}/"

webcore-install:
	@echo $@
	echo "Copying web into $(WEBDIR)"
	mkdir -p $(ADMINDIR)
	cp -r ../admin/* $(ADMINDIR)
	mkdir -p $(WEBDIR)
	mkdir -p $(WEBDIR)/opac/extras/xsl/
	cp -r ../web/* $(WEBDIR)
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/mresult.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/rresult.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/rdetail.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/advanced.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/myopac.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/cnbrowse.xml
	cp ../xul/staff_client/chrome//content//util/date.js $(WEBDIR)/opac/common/js/
	cp ../xsl/*.xsl $(WEBDIR)/opac/extras/xsl/
	ln -sf $(ETCDIR)/fm_IDL.xml $(WEBDIR)/reports/
	cp ../xul/staff_client/server/admin/adminlib.js $(WEBDIR)/reports/
	mkdir -p $(WEBDIR)/opac/extras/slimpac/
	

libfieldmapper:	
	make -C apachemods libfieldmapper.so

libfieldmapper-install:	
	make -C apachemods libfieldmapper-install

c_apps:
	@echo $@
	make -C c-apps
	make -C extras oils_requestor

c_apps-install:
	@echo $@
	make -C c-apps install
	make -C extras oils_requestor-install

autojs-install:
	@echo $@
	cp extras/fieldmapper.pl $(BINDIR)
	cp extras/org_tree_js.pl $(BINDIR)
	cp extras/org_tree_html_options.pl $(BINDIR)
	cp extras/org_tree_proximity.pl $(BINDIR)
	cp extras/autogen.sh $(BINDIR)
	cp support-scripts/offline-blocked-list.pl $(BINDIR) # this should probably be somewhere else
# -----------------------------------------------------------------------------------

perl-install:
	@echo $@
	@echo "Installing Perl modules to $(PERLDIR)"
	mkdir -p $(PERLDIR)
	mkdir -p $(DATADIR)
	mkdir -p $(BINDIR)
	cp extras/ils_events.xml $(DATADIR)
	cp -r perlmods/* $(PERLDIR)
	cp ../examples/opensrf.xml.example $(ETCDIR)
	cp ../examples/fm_IDL.xml $(ETCDIR)
	cp ../examples/oils_sip.xml.example $(ETCDIR)
	cp ../examples/hold_notification_template.example $(DATADIR)
	cp ../examples/oils_ctl.sh $(BINDIR)
	cp ../examples/lib_ips.txt.example $(ETCDIR)
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/marc $(TEMPLATEDIR)

# -----------------------------------------------------------------------------------

reporter-install:
	@echo $@
#	@echo "Installing Reporter templates to $(REPORTERDIR) and example configs to $(ETCDIR)"
#	cp reporter/report_base.example.xml $(ETCDIR)/reporter.example.xml
#	cp reporter/tables.example.xml $(ETCDIR)
#	cp reporter/widgets.example.xml $(ETCDIR)
#	mkdir -p $(REPORTERDIR)
#	cp -r reporter/templates/* $(REPORTERDIR)

# -----------------------------------------------------------------------------------
offline-install:
	@echo "Installing offline CGIs to $(CGIDIR)/offline";
	mkdir -p $(CGIDIR)/offline;
	mkdir -p $(DATADIR)/offline;
	perl -pe "s{##CONFIG##}{$(ETCDIR)}" < offline/offline.pl > $(TMP)/offline.pl;
	cp offline/offline-config.pl $(ETCDIR)
	cp $(TMP)/offline.pl $(CGIDIR)/offline/
	chmod +x $(CGIDIR)/offline/offline.pl

# -----------------------------------------------------------------------------------

cgi-bootstrap:
	@echo "Installing cgi's to $(CGIDIR)"
	mkdir -p $(TMP)/cgi-bin
	mkdir -p $(CGIDIR)
	for i in cgi-bin/*cgi; do perl -pe "s{##CONFIG##}{$(ETCDIR)}" < $$i > $(TMP)/$$i; done
	cp $(TMP)/cgi-bin/*cgi $(CGIDIR)
	cp -r cgi-bin/support $(CGIDIR)
	cp cgi-bin/setup.pl $(ETCDIR)/live-db-setup.pl
	chmod 755 $(CGIDIR)/*cgi

storage-bootstrap:
	@echo $@
	@echo ""
	@echo "WARNING!"
	@echo ""
	@echo "storage-bootstrap will DESTROY all data within all of the ILS tables in your database."
	@echo "The database this script will touch has a DBI DSN of"
	@echo "    dbi:$(DBDRVR):host=$(DBHOST);dbname=$(DBNAME);port=$(DBPORT)"
	@echo "Type control-c to avoid destroying all of the data.  Type enter to continue..."
	@echo ""
	@read X;
	./extras/import/build-oils-db.sh $(DBDRVR) $(DBHOST) $(DBPORT) $(DBNAME) $(DBUSER) $(DBPW) $(DBVER)

# -----------------------------------------------------------------------------------


string-templates-install:
	@echo "Installing string templates to $(TEMPLATEDIR)"
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/strings $(TEMPLATEDIR)

xsl-install:	
	@echo "Installing XSL files to $(XSLDIR)"
	mkdir -p $(XSLDIR)
	cp ../xsl/*.xsl $(XSLDIR)
#	mkdir -p $(WEBDIR)/xsl/
#	cp ../xsl/*.xsl $(WEBDIR)/xsl/

clean:
	@echo $@
	make -C extras clean
	make -C apachemods clean
	make -C c-apps clean

