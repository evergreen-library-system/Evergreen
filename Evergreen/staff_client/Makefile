ILS_DIR=${PWD}/../..

RETRIEVE_FIELDMAPPER=wget -N http://gapines.org/js/util/fieldmapper.js
RETRIEVE_ORG_TREE=wget -N http://gapines.org/js/util/OrgTree.js
RETRIEVE_CLIENT_CONFIG=cp ${ILS_DIR}/OpenSRF/examples/math_xul_client/math/content/conf/client_config.xml .

all: evergreen.xpi
	@echo
	@echo How do makefiles work again?
	touch application.ini

generated:
	@echo
	@echo These things are installation specific.  The staff client is the last thing you should try to build.
	(cd chrome/content/evergreen/util ; ${RETRIEVE_FIELDMAPPER} );
	(cd chrome/content/evergreen/util ; ${RETRIEVE_ORG_TREE} );
	(cd chrome/content/evergreen/conf ; ${RETRIEVE_CLIENT_CONFIG} );

open-ils:
	cp ../../OpenSRF/src/javascript/*.js chrome/content/evergreen/OpenSRF/
	cp ../../Open-ILS/src/javascript/util/*.js chrome/content/evergreen/Open-ILS/util/
	cp ../../Open-ILS/src/javascript/widgets/*.js chrome/content/evergreen/Open-ILS/widgets/
	cp ../../Open-ILS/src/javascript/widgets/menu/*.js chrome/content/evergreen/Open-ILS/widgets/menu/

patron:
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/patron_items/g | sed s/PagedTree/PatronItems/g > chrome/content/evergreen/patron/patron_items_overlay.xul )
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_items.dtd)

evergreen.xpi: evergreen.jar
	@echo
	@echo make the xpi file
	zip -r evergreen.xpi chrome/ defaults/ install.js install.rdf Makefile LICENSE README -x \*CVS\* > /dev/null

evergreen.jar: generated open-ils patron
	@echo
	@echo make the jar file
	(cd chrome; zip -r evergreen.jar content/ locale/ skin/ -x \*CVS\* > /dev/null )

clean:
	@echo
	@echo delete derived files
	rm -f evergreen.xpi
	rm -f chrome/evergreen.jar
	rm -f chrome/content/evergreen/patron/patron_items_overlay.xml chrome/locale/en-US/evergreen/patron_items.dtd
	rm -f chrome/content/evergreen/conf/client_config.xml
	rm -f chrome/content/evergreen/util/fieldmapper.js
	rm -f chrome/content/evergreen/util/OrgTree.js
	rm -f chrome/content/evergreen/OpenSRF/*js
	rm -f chrome/content/evergreen/Open-ILS/util/*js
	rm -f chrome/content/evergreen/Open-ILS/widgets/*js
	rm -f chrome/content/evergreen/Open-ILS/widgets/menu/*js
