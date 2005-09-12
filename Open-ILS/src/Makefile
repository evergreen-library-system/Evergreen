
export TMPDIR			= $(TMP)/opensrf
export LDFLAGS			= -L $(TMPDIR) -L .
export CFLAGS			= -g -Wall -O2 -fPIC -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) \
								-I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(TMPDIR)

export INCLUDEDIR += "/openils/"

all: mod_xmltools mod_ils_rest_gateway


install:	perl-install web-install string-templates-install storage-bootstrap cgi-bootstrap xsl-install

web-install:	webcore-install autojs-install  mod_xmltools-install mod_ils_rest_gateway-install


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

mod_xmltools:
	@echo $@
	make -C apachemods mod_xmltools.so

mod_xmltools-install:
	@echo $@
	make -C apachemods mod_xmltools-install

webcore-install:
	@echo $@
	echo "Copying web into $(WEBDIR)"
	#mkdir -p $(WEBDIR)
	#cp -r ../web/* $(WEBDIR)

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
	cp -r perlmods/* $(PERLDIR)
	cp ../examples/openils.xml.example $(ETCDIR)
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/marc $(TEMPLATEDIR)

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

