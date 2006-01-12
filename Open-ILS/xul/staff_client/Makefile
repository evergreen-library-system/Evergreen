VERSION=0.1.0
PACKAGE=Evergreen
DESCRIPTION=Evergreen Staff Client 
BUILD=2005072719

RETRIEVE_FM_ALL=wget -N http://dev.gapines.org/opac/common/js/fmall.js
RETRIEVE_CLIENT_CONFIG=cp ../../../../../../../OpenSRF/examples/math_xul_client/math/content/conf/client_config.xml .
RETRIEVE_LANG_DTD=cp ../../../../../../web/opac/locale/en-US/lang.dtd .
MOZILLA_SPECIAL_RESOURCE=/home/phasefx/work/mozilla/dist/bin/res/dtd

all: build package
	@echo
	@echo How do makefiles work again?
	@echo BUILD = ${BUILD}
	touch application.ini

#build: generated open-ils patron circ
build: generated open-ils custom
	@echo
	@echo Everything before packaging

package: evergreen.xpi
	@echo
	@echo Packaging

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
	sed -i 's/auth\.version ".*"/auth\.version "${PACKAGE} ${VERSION} ${BUILD}"/' chrome/locale/en-US/evergreen/auth.dtd 

generated:
	@echo
	@echo These things are installation specific.  The staff client is the last thing you should try to build.
	(cd chrome/content/evergreen/conf ; ${RETRIEVE_CLIENT_CONFIG} );
	(cd chrome/content/evergreen/OpenILS/util/ ; ${RETRIEVE_FM_ALL} );
	(cd chrome/locale/en-US/evergreen/ ; ${RETRIEVE_LANG_DTD} );
	external/dtd2js.pl chrome/locale/en-US/evergreen/lang.dtd > chrome/content/evergreen/main/lang.js

open-ils:
	cp ../../../OpenSRF/src/javascript/*.js chrome/content/evergreen/OpenSRF/
	cp ../../../Open-ILS/web/opac/common/js/*.js chrome/content/evergreen/OpenILS/util/
	cp ../../../Evergreen/staff_client/chrome/content/evergreen/cat/marc* chrome/content/evergreen/legacy/
	cp ../../../Evergreen/staff_client/chrome/locale/en-US/evergreen/cat.dtd chrome/locale/en-US/evergreen/
	#cp server/main/menu* chrome/content/evergreen/main/
	#cp server/cat/opac* chrome/content/evergreen/cat/

patron:
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/patron_items/g | sed s/PagedTree/PatronItems/g > chrome/content/evergreen/patron/patron_items_overlay.xul )
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/patron_search_results/g | sed s/PagedTree/PatronSearchResults/g > chrome/content/evergreen/patron/patron_search_results_overlay.xul )
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/patron_checkout_items/g | sed s/PagedTree/PatronCheckoutItems/g > chrome/content/evergreen/patron/patron_checkout_items_overlay.xul )
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/patron_holds/g | sed s/PagedTree/PatronHolds/g > chrome/content/evergreen/patron/patron_holds_overlay.xul )
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_items.dtd)
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_search_results.dtd)
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_checkout_items.dtd)
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/patron_holds.dtd)

circ:
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/checkin_items/g | sed s/PagedTree/CheckinItems/g > chrome/content/evergreen/circ/checkin_items_overlay.xul )
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/checkin_items.dtd)
	(cat chrome/content/evergreen/main/paged_tree_overlay.xul | sed s/paged_tree/hold_capture_items/g | sed s/PagedTree/HoldCaptureItems/g > chrome/content/evergreen/circ/hold_capture_items_overlay.xul )
	(cp chrome/locale/en-US/evergreen/paged_tree.dtd chrome/locale/en-US/evergreen/hold_capture_items.dtd)

custom:
	#(cd chrome/content/evergreen/OpenILS/util; cp RemoteRequest.js~ RemoteRequest.js)
	#cp chrome/locale/en-US/evergreen/*.* ${MOZILLA_SPECIAL_RESOURCE}

evergreen.xpi: evergreen.jar
	@echo
	@echo make the xpi file
	zip -r evergreen.xpi chrome/ defaults/ install.js install.rdf application.ini Makefile LICENSE README -x \*CVS\* > /dev/null

evergreen.jar: build
	@echo
	@echo make the jar file
	(cd chrome; zip -r evergreen.jar content/ locale/ skin/ -x \*CVS\* > /dev/null )

clean:
	@echo
	@echo delete derived files
	rm -f evergreen.xpi
	rm -f chrome/evergreen.jar
	#rm -f chrome/content/evergreen/main/menu.js chrome/content/evergreen/menu_frame*
	rm chrome/content/evergreen/legacy/marc*
	rm chrome/locale/en-US/evergreen/cat.dtd
	rm -f chrome/content/evergreen/patron/patron_items_overlay.xul chrome/locale/en-US/evergreen/patron_items.dtd
	rm -f chrome/content/evergreen/patron/patron_search_results_overlay.xul chrome/locale/en-US/evergreen/patron_search_results.dtd
	rm -f chrome/content/evergreen/patron/patron_checkout_items_overlay.xul chrome/locale/en-US/evergreen/patron_checkout_items.dtd
	rm -f chrome/content/evergreen/patron/patron_holds_overlay.xul chrome/locale/en-US/evergreen/patron_holds.dtd
	rm -f chrome/content/evergreen/circ/checkin_items_overlay.xul chrome/locale/en-US/evergreen/checkin_items.dtd
	rm -f chrome/content/evergreen/circ/hold_capture_items_overlay.xul chrome/locale/en-US/evergreen/hold_capture_items.dtd
	rm -f chrome/content/evergreen/conf/client_config.xml
	rm -f chrome/content/evergreen/util/fieldmapper.js
	rm -f chrome/content/evergreen/util/OrgTree.js
	rm -f chrome/content/evergreen/OpenSRF/*js
	rm -f chrome/content/evergreen/OpenILS/util/*js
	rm -f chrome/content/evergreen/OpenILS/widgets/*js
	rm -f chrome/content/evergreen/OpenILS/widgets/menu/*js
