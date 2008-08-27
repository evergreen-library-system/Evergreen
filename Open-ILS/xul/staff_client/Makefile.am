#---------------------------------------------------------
# Makefile.am for xul/staff_client
## Process this file with automake to generate Makefile.in
#---------------------------------------------------------

export STAFF_CLIENT_BUILD_ID = $$(/bin/cat build/BUILD_ID)
OPENSRF_JSLIBS = "$(OPENSRF_LIBS)/javascript"

install-exec-local: build

build: build_dir generated open-ils stamp
	@echo To test the staff client:
	@echo "  cd build/"
	@echo "  xulrunner application.ini"

build_dir:
	@echo ' * Creating and populating build/ '
	mkdir -p build/
	cp -R chrome build/
	cp -R server build/
	cp -R defaults build/
	cp -R components build/
	cp application.ini build/
	cp -R build/chrome/content/util/ build/server/
	cp -R build/chrome/content/auth/ build/server/
	cp build/chrome/content/main/constants.js build/server/main/constants.js
	cp build/chrome/content/main/simple_auth.xul build/server/main/simple_auth.xul
	cp build/chrome/content/OpenILS/data.js build/server/OpenILS/data.js
	cp build/chrome/content/OpenILS/global_util.js build/server/OpenILS/global_util.js
	for i in `cd @top_srcdir@/Evergreen/xul/staff_client/server/ && find -type f |grep -v \.svn|cut -f2- -d/`; do cp @top_srcdir@/Evergreen/xul/staff_client/server/$$i build/server/$$i; done
	external/prune_dirs.sh build/

stamp:
	@/bin/date +"%Y%m%d.%H%M%S" > build/BUILD_ID
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "Stamping with Build ID: ${STAFF_CLIENT_BUILD_ID}" ; echo ${STAFF_CLIENT_BUILD_ID} > build/BUILD_ID ) ; fi
	@if [ -z "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "No Build ID for versioning" ; echo "none" > build/BUILD_ID ) ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then sed -i s/^Version=.\*/Version=${STAFF_CLIENT_BUILD_ID}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then sed -i s/^BuildID=.\*/BuildID=${STAFF_CLIENT_BUILD_ID}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.xul' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.html' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.xhtml' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.js' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.xml' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi

generated:
	@echo ' * Grabbing lang.dtd from the OPAC code '
	cp @top_srcdir@/Open-ILS/web/opac/locale/en-US/lang.dtd build/chrome/locale/en-US/

open-ils:
	@echo ' * Grabbing more OPAC code and legacy code and custom code'
	cp @top_srcdir@/Open-ILS/web/opac/common/js/*.js build/chrome/content/OpenILS/util/
	cp $(OPENSRF_JSLIBS)/*.js build/chrome/content/OpenILS/util/
	external/prune_dirs.sh build/


