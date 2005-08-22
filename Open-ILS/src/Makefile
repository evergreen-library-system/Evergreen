export TMPDIR			= $(TMP)/opensrf
export LD_OPTS			= -L $(TMPDIR) -L .
export CC_OPTS			= -g -Wall -O2 -fPIC -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) \
								-I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(TMPDIR)

all: mod_xmltools


install:	perl-install web-install string-templates-install storage-bootstrap xsl-install

web-install:	webcore-install autojs-install  mod_xmltools-install 


# -----------------------------------------------------------------------------------
# Web stuff
# -----------------------------------------------------------------------------------
mod_xmltools:
	echo $@
	make -C apachemods mod_xmltools.so

mod_xmltools-install:
	echo $@
	make -C apachemods mod_xmltools-install

webcore-install:
	echo $@
	echo "Copying web into $(WEBDIR)"
	mkdir -p $(WEBDIR)
	cp -r ../web/* $(WEBDIR)

autojs-install:
	echo $@
	cp extras/fieldmapper.pl $(BINDIR)
	cp extras/org_tree_js.pl $(BINDIR)
	cp extras/autogen.sh $(BINDIR)
# -----------------------------------------------------------------------------------

marcdumper:
	echo $@
	make -C extras/marcdumper

marcdumper-install:
	echo $@
	make -C extras/marcdumper install

# -----------------------------------------------------------------------------------

perl-install:
	echo $@
	@echo "Installing Perl modules to $(PERLDIR)"
	mkdir -p $(PERLDIR)
	cp -r perlmods/* $(PERLDIR)
	cp ../examples/openils.xml.example $(ETCDIR)
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/marc $(TEMPLATEDIR)

# -----------------------------------------------------------------------------------

storage-bootstrap:
	echo $@
	@echo "Installing cgi's to $(CGIDIR)"
	mkdir -p $(CGIDIR)
	cp -r cgi-bin/* $(CGIDIR)
	./extras/import/build-oils-db.sh $(DBDRVR) $(DBHOST) $(DBNAME) $(DBUSER) $(DBPW)

# -----------------------------------------------------------------------------------


string-templates-install:
	echo $@
	@echo "Installing string templates to $(TEMPLATEDIR)"
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/strings $(TEMPLATEDIR)

xsl-install:	
	echo $@
	@echo "Installing XSL files to $(XSLDIR)"
	mkdir -p $(XSLDIR)
	cp ../xsl/*.xsl $(XSLDIR)

clean:
	echo $@
	make -C extras clean

