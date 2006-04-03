
export TMPDIR			= $(TMP)/opensrf
export LDFLAGS			= -L $(TMPDIR) -L .
export CFLAGS			= -pipe -g -Wall -O2 -fPIC -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) -I$(APR_HEADERS) \
								-I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(TMPDIR)

export INCDIR = "$(INCLUDEDIR)/openils/"

export STAFF_CLIENT_BUILD_ID = `/bin/cat ../xul/staff_client/build/BUILD_ID`

all: mod_ils_rest_gateway c_apps client-xul mod_xmlent

install:	perl-install web-install server-xul string-templates-install storage-bootstrap cgi-bootstrap xsl-install c_apps-install circ_rules-install offline-install

web-install:	webcore-install autojs-install mod_ils_rest_gateway-install  mod_xmlent-install offline-install

circ_rules-install:
	@echo $@
	cp javascript/backend/circ/*.js $(CIRCRULESDIR)


# -----------------------------------------------------------------------------------
# Web stuff
# -----------------------------------------------------------------------------------
mod_ils_rest_gateway:
	@echo $@
	make -C apachemods mod_ils_rest_gateway.so

mod_ils_rest_gateway-install:
	@echo $@
	make -C apachemods libfieldmapper-install
	make -C apachemods mod_ils_rest_gateway-install

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
	mkdir -p $(WEBDIR)
	cp -r ../web/* $(WEBDIR)
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/mresult.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/rresult.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/rdetail.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/advanced.xml
	ln -sf $(WEBDIR)/opac/skin/default/xml/index.xml $(WEBDIR)/opac/skin/default/xml/myopac.xml

libfieldmapper:	
	make -C apachemods libfieldmapper.so

libfieldmapper-install:	
	make -C apachemods libfieldmapper-install

c_apps:	libfieldmapper
	@echo $@
	make -C c-apps
	make -C extras oils_requestor

c_apps-install:	libfieldmapper-install
	@echo $@
	make -C c-apps install
	make -C extras oils_requestor-install

autojs-install:
	@echo $@
	cp extras/fieldmapper.pl $(BINDIR)
	cp extras/org_tree_js.pl $(BINDIR)
	cp extras/autogen.sh $(BINDIR)
# -----------------------------------------------------------------------------------

marcdumper:
	@echo $@
	make -C extras/marcdumper

marcdumper-install:
	@echo $@
	make -C extras/marcdumper install

# -----------------------------------------------------------------------------------

perl-install:
	@echo $@
	@echo "Installing Perl modules to $(PERLDIR)"
	mkdir -p $(PERLDIR)
	mkdir -p $(DATADIR)
	cp extras/ils_events.xml $(DATADIR)
	cp -r perlmods/* $(PERLDIR)
	cp ../examples/openils.xml.example $(ETCDIR)
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/marc $(TEMPLATEDIR)

# -----------------------------------------------------------------------------------

reporter-install:
	@echo $@
	@echo "Installing Reporter templates to $(REPORTERDIR) and example configs to $(ETCDIR)"
	cp reporter/report_base.example.xml $(ETCDIR)/reporter.example.xml
	cp reporter/tables.example.xml $(ETCDIR)
	cp reporter/widgets.example.xml $(ETCDIR)
	mkdir -p $(REPORTERDIR)
	cp -r reporter/templates/* $(REPORTERDIR)

# -----------------------------------------------------------------------------------
offline-install:
	@echo "Installing offline CGIs to $(CGIDIR)/offline";
	mkdir -p $(CGIDIR)/offline;
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

storage-bootstrap:
	@echo $@
	@echo ""
	@echo "WARNING!"
	@echo ""
	@echo "storage-bootstrap will DESTROY all data within all of the ILS tables in your database."
	@echo "Type control-c to avoid destroying all of the data.  Type enter to continue..."
	@echo ""
	@read X;
	./extras/import/build-oils-db.sh $(DBDRVR) $(DBHOST) $(DBNAME) $(DBUSER) $(DBPW)

# -----------------------------------------------------------------------------------


string-templates-install:
	@echo "Installing string templates to $(TEMPLATEDIR)"
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/strings $(TEMPLATEDIR)

xsl-install:	
	@echo "Installing XSL files to $(XSLDIR)"
	mkdir -p $(XSLDIR)
	cp ../xsl/*.xsl $(XSLDIR)

clean:
	@echo $@
	make -C extras clean
	make -C apachemods clean
	make -C c-apps clean

