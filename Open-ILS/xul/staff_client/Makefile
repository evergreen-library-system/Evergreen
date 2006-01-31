# ILS/Open-ILS/xul/staff_client/Makefile

export STAFF_CLIENT_BUILD_ID = `/bin/cat build/BUILD_ID`

all: build 
	@echo
	@echo

build: build_dir generated open-ils custom stamp
	@echo
	@echo 
	@echo To test the staff client:
	@echo "  cd build/"
	@echo "  xulrunner application.ini"

build_dir:
	@echo
	@echo '*********************************************************  Creating and populating build/ '
	mkdir -p build/
	/bin/date +"%Y%m%d.%H%M%S" > build/BUILD_ID
	cp -R chrome build/
	cp -R server build/
	cp -R defaults build/
	cp -R components build/
	cp application.ini build/
	cp -R build/chrome/content/util/ build/server/
	cp build/chrome/content/main/constants.js build/server/main/constants.js
	cp build/chrome/content/OpenILS/data.js build/server/OpenILS/data.js
	external/prune_dirs.sh build/

stamp: 
	@echo
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "Stamping with Build ID: ${STAFF_CLIENT_BUILD_ID}" ) ; fi
	@if [ -z "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "No Build ID for versioning" ) ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then sed -i s/^Version=.\*/Version=${STAFF_CLIENT_BUILD_ID}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then sed -i s/^BuildID=.\*/BuildID=${STAFF_CLIENT_BUILD_ID}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.xul' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.js' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi

generated:
	@echo
	@echo '********************************************************* Grabbing lang.dtd from the OPAC code '
	cp ../../../Open-ILS/web/opac/locale/en-US/lang.dtd build/chrome/locale/en-US/
	external/dtd2js.pl build/chrome/locale/en-US/lang.dtd > build/chrome/content/main/lang.js

open-ils:
	@echo
	@echo '********************************************************* Grabbing more OPAC code and legacy code '
	cp ../../../OpenSRF/src/javascript/*.js build/chrome/content/OpenSRF/
	cp ../../../Open-ILS/web/opac/common/js/*.js build/chrome/content/OpenILS/util/
	cp ../../../Evergreen/staff_client/chrome/content/evergreen/cat/marc* build/chrome/content/legacy/
	cp ../../../Evergreen/staff_client/chrome/content/evergreen/cat/browse* build/chrome/content/legacy/
	cp ../../../Evergreen/staff_client/chrome/locale/en-US/evergreen/cat.dtd build/chrome/locale/en-US/
	find build/chrome/content/legacy/ -type f -name '*.*' -exec sed -i s/evergreen/open_ils_staff_client/g {} \;

custom:
	@echo
	@echo
	@echo '********************************************************* Placeholder for debugging tweaks '
	#(cd chrome/content/OpenILS/util; cp RemoteRequest.js~ RemoteRequest.js)

clean:
	@echo
	@echo '********************************************************* Removing build/ '
	rm -rf build/
