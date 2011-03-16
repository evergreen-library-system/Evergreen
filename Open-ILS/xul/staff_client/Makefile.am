#---------------------------------------------------------
# Makefile.am for xul/staff_client
## Process this file with automake to generate Makefile.in
#---------------------------------------------------------

export STAFF_CLIENT_BUILD_ID = $$(/bin/cat build/BUILD_ID)
export STAFF_CLIENT_VERSION = $$(/bin/cat build/VERSION)
export STAFF_CLIENT_STAMP_ID = $$(/bin/cat build/STAMP_ID)

# from http://closure-compiler.googlecode.com/files/compiler-latest.zip  FIXME: Autotools this?
export CLOSURE_COMPILER_JAR = ~/closure-compiler/compiler.jar
XULRUNNER_VERSION=1.9.2.15
XULRUNNER_WINFILE=xulrunner-$(XULRUNNER_VERSION).en-US.win32.zip
XULRUNNER_LINUXFILE=xulrunner-$(XULRUNNER_VERSION).en-US.linux-i686.tar.bz2
XULRUNNER_URL=http://releases.mozilla.org/pub/mozilla.org/xulrunner/releases/$(XULRUNNER_VERSION)/runtimes/

OPENSRF_JSLIBS = "$(OPENSRF_LIBS)/javascript"
CHROME_LOCALES = $$(ls -1 chrome/locale)
SKIN_CSS = $$(ls -1 server/skin/*css | sed -e "s/.css/_custom.css/")
UPDATESDIR=@localstatedir@/updates

SVN=svn # Because some people might need to override this to 'git svn' or something

export NSIS_EXTRAOPTS
export NSIS_WICON=$$(if [ -f client/evergreen.ico ]; then echo '-DWICON'; fi)
export NSIS_AUTOUPDATE=$$([ -f client/defaults/preferences/autoupdate.js ] && echo '-DAUTOUPDATE')
export NSIS_DEV=$$([ -f client/defaults/preferences/developers.js ] && echo '-DDEVELOPER')
export NSIS_PERMACHINE=$$([ -f client/defaults/preferences/aa_per_machine.js ] && echo '-DPERMACHINE')

#------------------------------
# Build ILS XUL CLIENT/SERVER
#------------------------------

if BUILDILSCLIENT
OILSSERVER_INST = server-xul
endif

install-exec-local: $(OILSSERVER_INST)

devbuild: build
	@echo ' * Copying in developer preferences'
	@cp external/developers.js build/defaults/preferences/

permachine: build
	@echo ' * Copying in default to machine level registration file'
	@cp external/aa_per_machine.js build/defaults/preferences/

build: build_dir chrome2remote localize_manifest generated custom_skins open-ils stamp 
	@echo To test the staff client:
	@echo "  cd build/"
	@echo "  xulrunner application.ini"

build_dir:
	@echo ' * Creating and populating build/ '
	@rm -rf build/
	@mkdir -p build/
	@cp -fR chrome build/
	@cp -fR server build/
	@cp -fR defaults build/
	@cp -fR components build/
	@cp application.ini build/
	@if [ -f "install.mccoy.rdf" ]; then cp install.mccoy.rdf build/install.rdf; else cp install.rdf build/; fi
	@cp -fR build/chrome/content/util/ build/server/
	@cp -fR build/chrome/content/auth/ build/server/
	@cp build/chrome/content/main/constants.js build/server/main/constants.js
	@cp build/chrome/content/main/bindings.xml build/server/main/bindings.xml
	@cp build/chrome/content/OpenILS/data.js build/server/OpenILS/data.js
	@cp build/chrome/content/OpenILS/global_util.js build/server/OpenILS/global_util.js
	@if [ -d branding ]; then copy -fR branding/* build/; fi
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

# On this page:
# https://developer.mozilla.org/en/xul_application_packaging
# The Documentation states:
# BUILD ID should be a unique build identifier, usually date based, and should be different for each released version
# VERSION should be in a format as described here:
# https://developer.mozilla.org/en/Toolkit_version_format

# The default "automatic" BUILD ID is acceptable.

# The version from the README usually conforms to that documentation, unless it is trunk.
# If we are in trunk, we probably have svn kicking around, ask it for the revision and build an appropriate version string.

# Neither really applies to the STAMP, though.
# The method below gives the same format STAMPS as previous instructions provided. If README has version 1.2.3.4 then STAMP_ID will become rel_1_2_3_4.
# Trunk VERSION will end up with 0trunk.release, trunk STAMP ID will be 0trunk_release.
stamp:
	@/bin/date +"%Y%m%d.%H%M%S" > build/BUILD_ID
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "Stamping with Build ID: ${STAFF_CLIENT_BUILD_ID}" ; echo ${STAFF_CLIENT_BUILD_ID} > build/BUILD_ID ) ; fi
	@if [ -z "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "No Build ID for versioning" ; echo "none" > build/BUILD_ID ) ; fi
	@sed -n -e '1 s/^.* \([^ ]*\)$$/\1/p' @top_srcdir@/README > build/VERSION
	@if [ "${STAFF_CLIENT_VERSION}" == "trunk" ]; then echo "0trunk.$$(${SVN} info | sed -n -e 's/Last Changed Rev: \([0-9][0-9]*\)/\1/p')" > build/VERSION; fi 
	@if [ -n "${STAFF_CLIENT_VERSION}" ]; then ( echo "Stamping with Version: ${STAFF_CLIENT_VERSION}" ; echo ${STAFF_CLIENT_VERSION} > build/VERSION ) ; fi
	@if [ -z "${STAFF_CLIENT_VERSION}" ]; then ( echo "No Version" ; echo "none" > build/VERSION ) ; fi
	@sed -e 's/\./_/g' -e 's/^\([0-9_]*\)$$/rel_&/' build/VERSION > build/STAMP_ID
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then ( echo "Stamping with Stamp ID: ${STAFF_CLIENT_STAMP_ID}" ; echo ${STAFF_CLIENT_STAMP_ID} > build/STAMP_ID ) ; fi
	@if [ -z "${STAFF_CLIENT_STAMP_ID}" ]; then ( echo "No Stamp ID for versioning" ; echo "none" > build/STAMP_ID ) ; fi
	@if [ -n "${STAFF_CLIENT_VERSION}" ]; then sed -i -e s/^Version=.\*/Version=${STAFF_CLIENT_VERSION}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_VERSION}" ]; then sed -i -e "s|<em:version>.*</em:version>|<em:version>${STAFF_CLIENT_VERSION}</em:version>|" build/install.rdf ; fi
	@if [ -n "${STAFF_CLIENT_VERSION}" ]; then find build/ -name 'constants.js' -exec sed -i -e "s/\(CLIENT_VERSION *= '\)'/\1${STAFF_CLIENT_VERSION}'/" {} \; ; fi
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then sed -i -e s/^BuildID=.\*/BuildID=${STAFF_CLIENT_BUILD_ID}/ build/application.ini ; fi
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then find build/ -name '*.css' -exec sed -i -e s/xul\\\/server/xul\\\/${STAFF_CLIENT_STAMP_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then find build/ -name '*.xul' -exec sed -i -e s/xul\\\/server/xul\\\/${STAFF_CLIENT_STAMP_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then find build/ -name '*.html' -exec sed -i -e s/xul\\\/server/xul\\\/${STAFF_CLIENT_STAMP_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then find build/ -name '*.xhtml' -exec sed -i -e s/xul\\\/server/xul\\\/${STAFF_CLIENT_STAMP_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then find build/ -name '*.js' -exec sed -i -e s/xul\\\/server/xul\\\/${STAFF_CLIENT_STAMP_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then find build/ -name '*.xml' -exec sed -i -e s/xul\\\/server/xul\\\/${STAFF_CLIENT_STAMP_ID}\\\/server/g {} \; ; fi
	@if [ -n "${STAFF_CLIENT_STAMP_ID}" ]; then find build/ -name 'constants.js' -exec sed -i -e "s/\(CLIENT_STAMP *= '\)'/\1${STAFF_CLIENT_STAMP_ID}'/" {} \; ; fi
	@if [ -z "${AUTOUPDATE_HOST}" ]; then rm -f build/defaults/preferences/autoupdate.js; fi
	@if [ -z "${AUTOUPDATE_HOST}" ]; then sed -i -e /updateURL/d build/install.rdf; fi
	@if [ -n "${AUTOUPDATE_HOST}" ]; then echo "Applying automatic update host ${AUTOUPDATE_HOST}"; fi
	@if [ -n "${AUTOUPDATE_HOST}" ]; then sed -i -e "s|::HOSTNAME::|${AUTOUPDATE_HOST}|" -e "s|https\?://\(https\?://\)|\1|" build/defaults/preferences/autoupdate.js; fi
	@if [ -n "${AUTOUPDATE_HOST}" ]; then sed -i -e "s|::HOSTNAME::|${AUTOUPDATE_HOST}|" -e "s|https\?://\(https\?://\)|\1|" build/install.rdf; fi

bell:
	@perl -e 'print "Ringing bell..." . chr(7) . "\n";'

bundle:
	@rm -f build/build.tar
	@tar -c --exclude=server -f build.tar build/
	@mv build.tar build/
	@md5sum build/build.tar > build/build.tar.md5

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

needwebdir:
	@if [ -z "$(WEBDIR)" ]; then echo "!!!--------!!!"; echo "WEBDIR is not set. Must use top level Makefile or set WEBDIR to use this target."; echo "!!!--------!!!"; exit 1; fi

server-xul: needwebdir build
	@echo $@
	mkdir -p $(WEBDIR)
	mkdir -p $(WEBDIR)/xul/
	@echo "STAMP_ID = $(STAFF_CLIENT_STAMP_ID)"
	@echo "Copying xul into $(WEBDIR)/xul/$(STAFF_CLIENT_STAMP_ID)"
	mkdir -p "$(WEBDIR)/xul/$(STAFF_CLIENT_STAMP_ID)"
	cp -R @top_srcdir@/Open-ILS/xul/staff_client/build/server "${WEBDIR}/xul/${STAFF_CLIENT_STAMP_ID}/"

compress-javascript: build
	@echo "Size of build/ before compression = " `du -sh build/`
	@echo " * Running Google's Closure Compiler against javascript.  Errors in build/compression.err"
	@external/closure_compiler.sh $(CLOSURE_COMPILER_JAR) 2>> build/compression.err
	@echo `find build/ -name '*.js~' -size 0 -print | wc -l` compression failures
	@find build/ -name '*.js~' -size 0 -exec rm {} \; # remove the output files for those that did not compile
	@echo `find build/ -name '*.js~' -print | wc -l` compression successes
	@find build/ -name '*.js~' -exec perl -e '$$a = "{}"; chop $$a; `mv $$a~ $$a`;' \;
	@echo "Size of build/ (minus compression.err) after compression = " `du -sh --exclude compression.err build/`

# Easy way to make all three kinds of clients

clients:
	@make win-client
	@make linux-client
	@make generic-client

# By doing this we don't change the original build in the build folder
# Great for adding/changing things without a full rebuild

client_dir:
	@if [ ! -f build/BUILD_ID ]; then echo 'ERROR! Current build not stamped!'; exit 1; fi
	@echo 'Prepping Client Set'
	@rm -rf client/
	@mkdir -p client
	@cp -fR build/* client/
	@rm -rf client/server/
	@rm -f client/build.tar*

# When building as a standalone client install.rdf is a bad thing
# as we haven't "sanitized" the client for extension use

client_app: client_dir
	@echo 'Cleaning Extension Information'
	@rm -f client/install.rdf

# If automatic updates are enabled, or the standalone_xul_app.js is present,
# the extension can break Firefox.
# Remove those, and we need a chrome.manifest

client_ext: client_dir
	@echo 'Cleaning App Information'
	@rm -f client/application.ini
	@rm -f client/defaults/preferences/autoupdate.js
	@rm -f client/defaults/preferences/autochannel.js
	@rm -f client/defaults/preferences/standalone_xul_app.js
	@echo 'Prepping chrome.manifest'
	@perl -ne 'if(/open_ils_staff_client/) { s/ (?!chrome:\/\/open_ils_staff_client)([^ ]*)$$/ chrome\/\1/; print; }' client/chrome/chrome.manifest > client/chrome.manifest

# Would merge client_ext into this one, but this way an installer that doesn't
# use an xpi can be made for extension later, if desired

extension: client_ext
	@echo ' * Packaging as an XPI'
	@(cd client/ && zip -q -r ../evergreen.xpi * -x defaults/preferences/standalone_xul_app.js)
	@md5sum evergreen.xpi > evergreen.xpi.md5

# Generic client, as an xpi, theoretically suitable for --install-app usage

generic-client: client_app
	@echo 'Packing Generic Client via zip (as xpi file)'
	@rm -f evergreen_staff_client.xpi
	@cd client && zip -q -r ../evergreen_staff_client.xpi *
	@echo done

# These two targets complete the layout defined on
# https://developer.mozilla.org/en/XULRunner/Deploying_XULRunner_1.8
# for their respective platforms in regards to XULRunner deployment

# Note that I decided to use win/lin channels for ease of coding platform specific updates

win-xulrunner: client_app
	@echo 'Preparing Windows xulrunner'
	@if [ ! -f ${XULRUNNER_WINFILE} ]; then wget ${XULRUNNER_URL}${XULRUNNER_WINFILE}; fi
	@unzip -q ${XULRUNNER_WINFILE} -dclient
	@if [ -f client/defaults/preferences/autoupdate.js ]; then echo 'pref("app.update.channel","win");' >> client/defaults/preferences/autochannel.js; fi;
	@echo 'Preparing stub'
	@if [ -f xulrunner-stub.exe ]; then cp xulrunner-stub.exe client/evergreen.exe; rm client/xulrunner/xulrunner-stub.exe; else mv client/xulrunner/xulrunner-stub.exe client/evergreen.exe; fi

linux-xulrunner: client_app
	@echo 'Preparing Linux xulrunner'
	@if [ ! -f ${XULRUNNER_LINUXFILE} ]; then wget ${XULRUNNER_URL}${XULRUNNER_LINUXFILE}; fi
	@cd client; tar xjf ../${XULRUNNER_LINUXFILE}; cd ..
	@if [ -f client/defaults/preferences/autoupdate.js ]; then echo 'pref("app.update.channel","lin");' >> client/defaults/preferences/autochannel.js; fi;
	@echo 'Preparing stub'
	@mv client/xulrunner/xulrunner-stub client/evergreen

# Build a windows installer.

win-client: win-xulrunner
	@echo 'Building installer'
	@makensis -DPRODUCT_VERSION="${STAFF_CLIENT_VERSION}" ${NSIS_WICON} ${NSIS_AUTOUPDATE} ${NSIS_DEV} ${NSIS_PERMACHINE} ${NSIS_EXTRAOPTS} windowssetup.nsi
	@echo 'Done'

# For linux, just build a tar.bz2 archive

linux-client: linux-xulrunner
	@echo 'Packing as evergreen_staff_client.tar.bz2'
	@rm -f evergreen_staff_client.tar.bz2
	@cd client; tar cjf ../evergreen_staff_client.tar.bz2 *; cd ..
	@echo 'Done'

# For running the updates script with the correct updates directory, optionally building clients as well

updates updates-client win-updates win-updates-client linux-updates linux-updates-client generic-updates generic-updates-client extension-updates:
	@if [ ! -f build/BUILD_ID ]; then echo 'ERROR! Current build not stamped!'; exit 1; fi
	@if [ ! -x external/make_updates.sh ]; then chmod u+x external/make_updates.sh; fi
	@if [ ! -x external/make_updates.sh ]; then echo 'ERROR! external/make_updates.sh is not executable!'; exit 1; fi
	@external/make_updates.sh ${UPDATESDIR} $@
