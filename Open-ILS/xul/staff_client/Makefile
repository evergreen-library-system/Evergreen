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

package: OPEN_ILS_STAFF_CLIENT.xpi
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
	sed -i 's/auth\.title ".*"/auth\.title "${DESCRIPTION}"/' chrome/locale/en-US/OPEN_ILS_STAFF_CLIENT/auth.dtd 
	sed -i 's/auth\.version ".*"/auth\.version "${PACKAGE} ${VERSION} ${BUILD}"/' chrome/locale/en-US/OPEN_ILS_STAFF_CLIENT/auth.dtd 

generated:
	@echo
	@echo These things are installation specific.  The staff client is the last thing you should try to build.
	(cd chrome/content/OPEN_ILS_STAFF_CLIENT/conf ; ${RETRIEVE_CLIENT_CONFIG} );
	(cd chrome/content/OPEN_ILS_STAFF_CLIENT/OpenILS/util/ ; ${RETRIEVE_FM_ALL} );
	(cd chrome/locale/en-US/OPEN_ILS_STAFF_CLIENT/ ; ${RETRIEVE_LANG_DTD} );
	external/dtd2js.pl chrome/locale/en-US/OPEN_ILS_STAFF_CLIENT/lang.dtd > chrome/content/OPEN_ILS_STAFF_CLIENT/main/lang.js

open-ils:
	cp ../../../OpenSRF/src/javascript/*.js chrome/content/OPEN_ILS_STAFF_CLIENT/OpenSRF/
	cp ../../../Open-ILS/web/opac/common/js/*.js chrome/content/OPEN_ILS_STAFF_CLIENT/OpenILS/util/
	cp ../../../Evergreen/staff_client/chrome/content/evergreen/cat/marc* chrome/content/OPEN_ILS_STAFF_CLIENT/legacy/
	cp ../../../Evergreen/staff_client/chrome/content/evergreen/cat/browse* chrome/content/OPEN_ILS_STAFF_CLIENT/legacy/
	cp ../../../Evergreen/staff_client/chrome/locale/en-US/evergreen/cat.dtd chrome/locale/en-US/OPEN_ILS_STAFF_CLIENT/
	#cp server/main/menu* chrome/content/OPEN_ILS_STAFF_CLIENT/main/
	#cp server/cat/opac* chrome/content/OPEN_ILS_STAFF_CLIENT/cat/

patron:

circ:

custom:
	#(cd chrome/content/OPEN_ILS_STAFF_CLIENT/OpenILS/util; cp RemoteRequest.js~ RemoteRequest.js)
	#cp chrome/locale/en-US/OPEN_ILS_STAFF_CLIENT/*.* ${MOZILLA_SPECIAL_RESOURCE}

OPEN_ILS_STAFF_CLIENT.xpi: OPEN_ILS_STAFF_CLIENT.jar
	@echo
	@echo make the xpi file
	zip -r OPEN_ILS_STAFF_CLIENT.xpi chrome/ defaults/ install.js install.rdf application.ini Makefile LICENSE README -x \*CVS\* > /dev/null

OPEN_ILS_STAFF_CLIENT.jar: build
	@echo
	@echo make the jar file
	(cd chrome; zip -r OPEN_ILS_STAFF_CLIENT.jar content/ locale/ skin/ -x \*CVS\* > /dev/null )

clean:
	@echo
	@echo delete derived files
	rm -f OPEN_ILS_STAFF_CLIENT.xpi
	rm -f chrome/OPEN_ILS_STAFF_CLIENT.jar
	#rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/main/menu.js chrome/content/OPEN_ILS_STAFF_CLIENT/menu_frame*
	rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/legacy/marc*
	rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/legacy/browse*
	rm -f chrome/locale/en-US/OPEN_ILS_STAFF_CLIENT/cat.dtd
	rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/conf/client_config.xml
	rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/OpenSRF/*js
	rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/OpenILS/util/*js
	#rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/OpenILS/widgets/*js
	#rm -f chrome/content/OPEN_ILS_STAFF_CLIENT/OpenILS/widgets/menu/*js
