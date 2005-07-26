all: 

install:	perl-install javascript-install web-templates-install string-templates-install storage-bootstrap xsl-install

JSDIR=$(WEBDIR)/js

marcdumper:
	make -C extras/marcdumper

marcdumper-install:
	make -C extras/marcdumper install

perl-install:
	@echo "Installing Perl modules to $(PERLDIR)"
	mkdir -p $(PERLDIR)
	cp -r perlmods/* $(PERLDIR)
	cp ../examples/openils.xml.example $(ETCDIR)

javascript-install:
	@echo "Installing javascript to $(JSDIR)"
	mkdir -p $(JSDIR)
	cp -r javascript/* $(JSDIR)
	cp ../../$(OPENSRFDIR)/javascript/JSON.js $(JSDIR)/util/
	cp ../../$(OPENSRFDIR)/javascript/md5.js $(JSDIR)/util/

storage-bootstrap:
	@echo "Installing cgi's to $(CGIDIR)"
	mkdir -p $(CGIDIR)
	cp -r cgi-bin/* $(CGIDIR)
	./extras/import/build-oils-db.sh $(DBDRVR) $(DBHOST) $(DBNAME) $(DBUSER) $(DBPW)

web-templates-install:
	@echo "Installing web templates to $(TEMPLATEDIR)"
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/opac $(TEMPLATEDIR)
	cp -r templates/html $(TEMPLATEDIR)

string-templates-install:
	@echo "Installing string templates to $(TEMPLATEDIR)"
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/strings $(TEMPLATEDIR)

xsl-install:	
	@echo "Installing XSL files to $(XSLDIR)"
	mkdir -p $(XSLDIR)
	cp ../xsl/*.xsl $(XSLDIR)

clean:
	@echo "Cleaning..."
	make -C extras clean
