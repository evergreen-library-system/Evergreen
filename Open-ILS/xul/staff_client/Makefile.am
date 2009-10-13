#---------------------------------------------------------
# Makefile.am for xul/staff_client
## Process this file with automake to generate Makefile.in
#---------------------------------------------------------

export STAFF_CLIENT_BUILD_ID = $$(/bin/cat build/BUILD_ID)

OPENSRF_JSLIBS = "$(OPENSRF_LIBS)/javascript"
CHROME_LOCALES = $$(ls -1 chrome/locale)
SKIN_CSS = $$(ls -1 server/skin/*css | sed -e "s/.css/_custom.css/")

#------------------------------
# Build ILS XUL CLIENT/SERVER
#------------------------------

if BUILDILSCLIENT
OILSSERVER_INST = server-xul
endif

install-exec-local: $(OILSSERVER_INST)

build: build_dir chrome2remote localize_manifest generated custom_skins open-ils stamp 
	@echo To test the staff client:
	@echo "  cd build/"
	@echo "  xulrunner application.ini"

build_dir:
	@echo ' * Creating and populating build/ '
	@mkdir -p build/
	@cp -fR chrome build/
	@cp -fR server build/
	@cp -fR defaults build/
	@cp -fR components build/
	@cp application.ini build/
	@cp -fR build/chrome/content/util/ build/server/
	@cp -fR build/chrome/content/auth/ build/server/
	@cp build/chrome/content/main/constants.js build/server/main/constants.js
	@cp build/chrome/content/main/bindings.xml build/server/main/bindings.xml
	@cp build/chrome/content/OpenILS/data.js build/server/OpenILS/data.js
	@cp build/chrome/content/OpenILS/global_util.js build/server/OpenILS/global_util.js
	@external/prune_dirs.sh build/

# Convert chrome to remote for server localization
chrome2remote:
	@for loc in $(CHROME_LOCALES); do \
		cp -fr chrome/locale/$$loc build/server/locale/. ; \
	done;

# Update the manifest for our installed locales
localize_manifest:
	@for loc in $(CHROME_LOCALES) ; do \
		if [ "$$loc" != "en-US" ]; then ( echo "locale open_ils_staff_client $$loc locale/$$loc/" >> build/chrome/chrome.manifest ) ; fi; \
	done;

stamp:
	@/bin/date +"%Y%m%d.%H%M%S" > build/BUILD_ID
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "Stamping with Build ID: ${STAFF_CLIENT_BUILD_ID}" ; echo ${STAFF_CLIENT_BUILD_ID} > build/BUILD_ID ) ; fi
	@if [ -z "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "No Build ID for versioning" ; echo "none" > build/BUILD_ID ) ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then sed -i s/^Version=.\*/Version=${STAFF_CLIENT_BUILD_ID}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then sed -i s/^BuildID=.\*/BuildID=${STAFF_CLIENT_BUILD_ID}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.css' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.xul' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.html' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.xhtml' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.js' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then find build/ -name '*.xml' -exec sed -i s/xul\\\/server/xul\\\/${STAFF_CLIENT_BUILD_ID}\\\/server/g {} \; ; fi

bell:
	@perl -e 'print "Ringing bell..." . chr(7) . "\n";'

bundle:
	@rm -f build/build.tar
	@tar cf build.tar build/
	@mv build.tar build/

generated:
	@echo ' * Grabbing lang.dtd from the OPAC code '
	@cp @top_srcdir@/Open-ILS/web/opac/locale/en-US/lang.dtd build/chrome/locale/en-US/

open-ils:
	@echo ' * Grabbing more OPAC code and legacy code and custom code'
	@cp @top_srcdir@/Open-ILS/web/opac/common/js/*.js build/chrome/content/OpenILS/util/
	@cp $(OPENSRF_JSLIBS)/*.js build/chrome/content/OpenILS/util/
	@external/prune_dirs.sh build/

custom_skins:
	@for skin in $(SKIN_CSS); do \
		if [ ! -f "$$skin" ]; then ( touch build/"$$skin" ); fi \
	done;

server-xul: build
	@echo $@
	mkdir -p $(WEBDIR)
	mkdir -p $(WEBDIR)/xul/
	@echo "BUILD_ID = $(STAFF_CLIENT_BUILD_ID)"
	@echo "Copying xul into $(WEBDIR)/xul/$(STAFF_CLIENT_BUILD_ID)"
	mkdir -p "$(WEBDIR)/xul/$(STAFF_CLIENT_BUILD_ID)"
	cp -R @top_srcdir@/Open-ILS/xul/staff_client/build/server "${WEBDIR}/xul/${STAFF_CLIENT_BUILD_ID}/"
