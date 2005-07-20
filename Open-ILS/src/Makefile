all: extras

install:	perl-install javascript-install web-templates-install string-templates-install

marcdumper:
	make -C extras/marcdumper

marcdumper-install:
	make -C extras/marcdumper install

perl-install:
	cp -r perlmods/* $(PERLDIR)

javascript-install:
	cp -r javascript/* $(WEBDIR)

web-templates-install:
	cp -r templates/opac $(TEMPLATEDIR)
	cp -r templates/html $(TEMPLATEDIR)

string-templates-install:
	cp -r templates/strings $(TEMPLATEDIR)

clean:
	@echo "Cleaning..."
	make -C extras clean
