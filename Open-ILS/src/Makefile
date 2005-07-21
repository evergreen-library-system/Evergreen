all: extras

install:	perl-install javascript-install web-templates-install string-templates-install

marcdumper:
	make -C extras/marcdumper

marcdumper-install:
	make -C extras/marcdumper install

perl-install:
	mkdir -p $(PERLDIR)
	cp -r perlmods/* $(PERLDIR)

javascript-install:
	mkdir -p $(WEBDIR)
	cp -r javascript/* $(WEBDIR)
	cp ../../$(OPENSRFDIR)/javascript/JSON.js $(WEBDIR)/util/
	cp ../../$(OPENSRFDIR)/javascript/md5.js $(WEBDIR)/util/

web-templates-install:
	mkdir -p $(TEMPLATEDIR)
	cp -r templates/opac $(TEMPLATEDIR)
	cp -r templates/html $(TEMPLATEDIR)

string-templates-install:
	cp -r templates/strings $(TEMPLATEDIR)

clean:
	@echo "Cleaning..."
	make -C extras clean
