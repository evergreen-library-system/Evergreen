all: 

install:	perl-install javascript-install web-templates-install string-templates-install storage-bootstrap

JSDIR=$(WEBDIR)/js

marcdumper:
	make -C extras/marcdumper

marcdumper-install:
	make -C extras/marcdumper install

perl-install:
	mkdir -p $(PERLDIR)
	cp -r perlmods/* $(PERLDIR)
	cp ../examples/openils.xml.example $(ETCDIR)

javascript-install:
	mkdir -p $(JSDIR)
	cp -r javascript/* $(JSDIR)
	cp ../../$(OPENSRFDIR)/javascript/JSON.js $(JSDIR)/util/
	cp ../../$(OPENSRFDIR)/javascript/md5.js $(JSDIR)/util/

storage-bootstrap:
	mkdir -p $(CGIDIR)
	cp -r cgi-bin/* $(CGIDIR)
	./extras/import/build-oils-db.sh $(DBDRVR) $(DBHOST) $(DBNAME) $(DBUSER) $(DBPW)

web-templates-install:
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/opac $(TEMPLATEDIR)
	cp -r templates/html $(TEMPLATEDIR)

string-templates-install:
	cp -r templates/strings $(TEMPLATEDIR)

clean:
	@echo "Cleaning..."
	make -C extras clean
