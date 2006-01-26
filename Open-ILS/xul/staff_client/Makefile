VERSION=0.1.0
PACKAGE=Evergreen
DESCRIPTION=Evergreen Staff Client 
BUILD=2005072719

RETRIEVE_FM_ALL=wget -N http://dev.gapines.org/opac/common/js/fmall.js
RETRIEVE_CLIENT_CONFIG=cp ../../../../../../OpenSRF/examples/math_xul_client/math/content/conf/client_config.xml .
RETRIEVE_LANG_DTD=cp ../../../../../web/opac/locale/en-US/lang.dtd .

all: build 
	@echo
	@echo How do makefiles work again?
	@echo BUILD = ${BUILD}
	touch application.ini

#build: generated open-ils patron circ
build: generated open-ils custom
	@echo
	@echo Everything before packaging

package: open_ils_staff_client.xpi
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
	sed -i 's/auth\.title ".*"/auth\.title "${DESCRIPTION}"/' chrome/locale/en-US/auth.dtd 
	sed -i 's/auth\.version ".*"/auth\.version "${PACKAGE} ${VERSION} ${BUILD}"/' chrome/locale/en-US/auth.dtd 

generated:
	@echo
	@echo These things are installation specific.  The staff client is the last thing you should try to build.
	(cd chrome/content/conf ; ${RETRIEVE_CLIENT_CONFIG} );
	(cd chrome/content/OpenILS/util/ ; ${RETRIEVE_FM_ALL} );
	(cd chrome/locale/en-US/ ; ${RETRIEVE_LANG_DTD} );
	external/dtd2js.pl chrome/locale/en-US/lang.dtd > chrome/content/main/lang.js

symlinks:
	ln -sf ../chrome/content/util/ server/
	ln -sf ../../chrome/content/main/constants.js server/main/constants.js
	ln -sf ../../chrome/content/OpenILS/data.js server/OpenILS/data.js

open-ils:
	cp ../../../OpenSRF/src/javascript/*.js chrome/content/OpenSRF/
	cp ../../../Open-ILS/web/opac/common/js/*.js chrome/content/OpenILS/util/
	cp ../../../Evergreen/staff_client/chrome/content/evergreen/cat/marc* chrome/content/legacy/
	cp ../../../Evergreen/staff_client/chrome/content/evergreen/cat/browse* chrome/content/legacy/
	cp ../../../Evergreen/staff_client/chrome/locale/en-US/evergreen/cat.dtd chrome/locale/en-US/
	find chrome/content/legacy/ -type f -name '*.*' -exec sed -i s/evergreen/open_ils_staff_client/g {} \;

patron:

circ:

custom:
	#(cd chrome/content/OpenILS/util; cp RemoteRequest.js~ RemoteRequest.js)

open_ils_staff_client.xpi: open_ils_staff_client.jar
	@echo
	@echo make the xpi file
	zip -r open_ils_staff_client.xpi chrome/ defaults/ install.js install.rdf application.ini Makefile LICENSE README -x \*CVS\* > /dev/null

open_ils_staff_client.jar: build
	@echo
	@echo make the jar file
	(cd chrome; zip -r open_ils_staff_client.jar content/ locale/ skin/ -x \*CVS\* > /dev/null )

clean:
	@echo
	@echo delete derived files
	rm -f open_ils_staff_client.xpi
	rm -f chrome/open_ils_staff_client.jar
	rm -f chrome/content/legacy/marc*
	rm -f chrome/content/legacy/browse*
	rm -f chrome/locale/en-US/cat.dtd
	rm -f chrome/content/conf/client_config.xml
	rm -f chrome/content/OpenSRF/*js
	rm -f chrome/content/OpenILS/util/*js
