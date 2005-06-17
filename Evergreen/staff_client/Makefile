all: evergreen.xpi
	@echo
	@echo How do makefiles work again?

evergreen.xpi: evergreen.jar
	@echo
	@echo make the xpi file
	zip -r evergreen.xpi chrome/ defaults/ install.js install.rdf Makefile LICENSE README -x \*CVS\*

evergreen.jar:
	@echo
	@echo make the jar file
	(cd chrome; zip -r evergreen.jar content/ locale/ skin/ -x \*CVS\* )

clean:
	@echo
	@echo delete derived files
	rm evergreen.xpi
	rm chrome/evergreen.jar
