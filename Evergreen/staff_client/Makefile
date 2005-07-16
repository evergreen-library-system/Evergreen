VERSION=0.0.9
PACKAGE=Evergreen
DESCRIPTION=Evergreen Staff Client Pre-Alpha
BUILD=2005071519

ILS_DIR=${PWD}/../..

RETRIEVE_FIELDMAPPER=wget -N http://gapines.org/js/util/fieldmapper.js
RETRIEVE_ORG_TREE=wget -N http://gapines.org/js/util/OrgTree.js
RETRIEVE_CLIENT_CONFIG=cp ${ILS_DIR}/OpenSRF/examples/math_xul_client/math/content/conf/client_config.xml .

all: evergreen.xpi
	@echo
	@echo How do makefiles work again?
	@echo BUILD = ${BUILD}
	touch application.ini

stamp: 
	sed -i s/^Version=.\*/Version=${VERSION}/ application.ini 
	sed -i s/^BuildID=.\*/BuildID=${BUILD}/ application.ini
	sed -i s/^Name=.\*/Name=${PACKAGE}/ application.ini 
	sed -i 's/<em:version>.*<\/em:version>/<em:version>${VERSION}<\/em:version>/' install.rdf 
	sed -i 's/<em:name>.*<\/em:name>/<em:name>${PACKAGE}<\/em:name>/' install.rdf 
	sed -i 's/<em:description>.*<\/em:description>/<em:description>${DESCRIPTION}<\/em:description>/' install.rdf 
	sed -i "s/extVersion: '.\*'/extVersion: '${VERSION}'/" install.js 
	sed -i "s/extFullName: '.\*'/extFullName: '${DESCRIPTION}'/" install.js 
	sed -i 's/auth\.title ".*"/auth\.title "${DESCRIPTION}"/' chrome/locale/en-US/evergreen/auth.dtd 
	sed -i 's/auth\.version ".*"/auth\.version "${VERSION} ${BUILD}"/' chrome/locale/en-US/evergreen/auth.dtd 

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
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/patron_search_results/g | sed s/PagedTree/PatronSearchResults/g > chrome/content/evergreen/patron/patron_search_results_overlay.xul )
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/patron_checkout_items/g | sed s/PagedTree/PatronCheckoutItems/g > chrome/content/evergreen/patron/patron_checkout_items_overlay.xul )
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_items.dtd)
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_search_results.dtd)
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_checkout_items.dtd)

circ:
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/checkin_items/g | sed s/PagedTree/CheckinItems/g > chrome/content/evergreen/circ/checkin_items_overlay.xul )
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/checkin_items.dtd)

evergreen.xpi: evergreen.jar
	@echo
	@echo make the xpi file
	zip -r evergreen.xpi chrome/ defaults/ install.js install.rdf Makefile LICENSE README -x \*CVS\* > /dev/null

evergreen.jar: generated open-ils patron circ
	@echo
	@echo make the jar file
	(cd chrome; zip -r evergreen.jar content/ locale/ skin/ -x \*CVS\* > /dev/null )

clean:
	@echo
	@echo delete derived files
	rm -f evergreen.xpi
	rm -f chrome/evergreen.jar
	rm -f chrome/content/evergreen/patron/patron_items_overlay.xul chrome/locale/en-US/evergreen/patron_items.dtd
	rm -f chrome/content/evergreen/patron/patron_search_results_overlay.xul chrome/locale/en-US/evergreen/patron_search_results.dtd
	rm -f chrome/content/evergreen/patron/patron_checkout_items_overlay.xul chrome/locale/en-US/evergreen/patron_checkout_items.dtd
	rm -f chrome/content/evergreen/circ/checkin_items_overlay.xul chrome/locale/en-US/evergreen/checkin_items.dtd
	rm -f chrome/content/evergreen/conf/client_config.xml
	rm -f chrome/content/evergreen/util/fieldmapper.js
	rm -f chrome/content/evergreen/util/OrgTree.js
	rm -f chrome/content/evergreen/OpenSRF/*js
	rm -f chrome/content/evergreen/Open-ILS/util/*js
	rm -f chrome/content/evergreen/Open-ILS/widgets/*js
	rm -f chrome/content/evergreen/Open-ILS/widgets/menu/*js
