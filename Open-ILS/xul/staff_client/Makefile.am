#---------------------------------------------------------
# Makefile.am for xul/staff_client
## Process this file with automake to generate Makefile.in
#---------------------------------------------------------
export WEBDIR=@localstatedir@/web
export STAFF_CLIENT_BUILD_ID = $$(/bin/cat build/BUILD_ID)
export STAFF_CLIENT_VERSION = $$(/bin/cat build/VERSION)
export STAFF_CLIENT_STAMP_ID = $$(/bin/cat build/STAMP_ID)

# from http://closure-compiler.googlecode.com/files/compiler-latest.zip  FIXME: Autotools this?
export CLOSURE_COMPILER_JAR = ~/closure-compiler/compiler.jar

# XULRunner is our base.
XULRUNNER_VERSION=14.0.1
XULRUNNER_WINFILE=xulrunner-$(XULRUNNER_VERSION).en-US.win32.zip
XULRUNNER_LINUX32FILE=xulrunner-$(XULRUNNER_VERSION).en-US.linux-i686.tar.bz2
XULRUNNER_LINUX64FILE=xulrunner-$(XULRUNNER_VERSION).en-US.linux-x86_64.tar.bz2
XULRUNNER_URL=ftp://ftp.mozilla.org/pub/mozilla.org/xulrunner/releases/$(XULRUNNER_VERSION)/runtimes/
XULRUNNER_MAJOR_VERSION=$$(echo ${XULRUNNER_VERSION} | cut -d. -f1)

# Extensions we include when not an extension ourselves
# Grab the latest. If that becomes a problem we can swap them out for specific versions.
DOMINSPECTOR_URL=https://addons.mozilla.org/firefox/downloads/latest/6622/addon-6622-latest.xpi
DOMINSPECTOR_ID=inspector@mozilla.org
VENKMAN_URL=https://addons.mozilla.org/firefox/downloads/latest/216/addon-216-latest.xpi
VENKMAN_ID={f13b157f-b174-47e7-a34d-4815ddfdfeb8}

OPENSRF_JSLIBS = "$(OPENSRF_LIBS)/javascript"
CHROME_LOCALES = $$(ls -1 chrome/locale)
SKIN_CSS = $$(ls -1 server/skin/*css | sed -e "s/.css/_custom.css/")
UPDATESDIR=@localstatedir@/updates

GIT_BRANCH=$$(echo $$(git rev-parse --abbrev-ref HEAD || echo master) | sed 's|.*/||')
GIT_TAG=$$(git rev-parse --short HEAD) # For auto-tagging builds

export NSIS_EXTRAOPTS
export NSIS_WICON=$$(if [ -f client/evergreen.ico ]; then echo '-DWICON'; fi)
export NSIS_AUTOUPDATE=$$([ -f client/defaults/preferences/autoupdate.js ] && echo '-DAUTOUPDATE')
export NSIS_DEV=$$([ -f client/defaults/preferences/developers.js ] && echo '-DDEVELOPER')
export NSIS_PERMACHINE=$$([ -f client/defaults/preferences/aa_per_machine.js ] && echo '-DPERMACHINE')
export NSIS_EXTRAS=$$([ -f extras.nsi ] && echo '-DEXTRAS')
# Url taken from http://nsis.sourceforge.net/AccessControl_plug-in
NSIS_ACCESSCONTROL=http://nsis.sourceforge.net/mediawiki/images/4/4a/AccessControl.zip

#------------------------------
# Build ILS XUL CLIENT/SERVER
#------------------------------

if BUILDILSCLIENT
OILSSERVER_INST = server-xul
endif

install-exec-local: $(OILSSERVER_INST)

# Helper target
# For when you want to add devbuild/permachine/autoupdate to an existing stamp id
rebuild: export STAFF_CLIENT_STAMP_ID=`cat PREV_STAMP_ID`
rebuild: export STAFF_CLIENT_VERSION=`cat PREV_VERSION`
rebuild: build

rigrelease:
	@echo ' * Rigging for release branding'
	@cp xulrunner-stub.release.exe xulrunner-stub.exe
	@mkdir -p branding
	@cp evergreen-icon.ico branding/evergreen.ico
	@sed -i -e 's/^\s*;\?\s*!define UI_IMAGESET "release"/!define UI_IMAGESET "release"/' -e 's/^\s*;\?\s*!define UI_IMAGESET "beta"/;!define UI_IMAGESET "beta"/' windowssetup.nsi

rigbeta:
	@echo ' * Rigging for beta branding'
	@cp xulrunner-stub.beta.exe xulrunner-stub.exe
	@mkdir -p branding
	@cp evergreen-icon-beta.ico branding/evergreen.ico
	@sed -i -e 's/^\s*;\?\s*!define UI_IMAGESET "release"/;!define UI_IMAGESET "release"/' -e 's/^\s*;\?\s*!define UI_IMAGESET "beta"/!define UI_IMAGESET "beta"/' windowssetup.nsi

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
	@cp chrome.manifest build/
	@if [ -f "install.mccoy.rdf" ]; then cp install.mccoy.rdf build/install.rdf; else cp install.rdf build/; fi
	@cp -fR build/chrome/content/util/ build/server/
	@cp -fR build/chrome/content/auth/ build/server/
	@cp build/chrome/content/main/constants.js build/server/main/constants.js
	@cp build/chrome/content/main/bindings.xml build/server/main/bindings.xml
	@cp build/chrome/content/OpenILS/data.js build/server/OpenILS/data.js
	@cp build/chrome/content/OpenILS/global_util.js build/server/OpenILS/global_util.js
	@if [ -d branding ]; then cp -fR branding/* build/; fi
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

# The version from the README usually conforms to that documentation, unless it is master.
# If we are in master, we probably have git kicking around, ask it for the revision and build an appropriate version string.

# Neither really applies to the STAMP, though.
# The method below gives the same format STAMPS as previous instructions provided. If README has version 1.2.3.4 then STAMP_ID will become rel_1_2_3_4.
# Master VERSION will end up with 0branch.release, master STAMP ID will be 0branch_release.
stamp:
	@/bin/date +"%Y%m%d.%H%M%S" > build/BUILD_ID
	@if [ -n "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "Stamping with Build ID: ${STAFF_CLIENT_BUILD_ID}" ; echo ${STAFF_CLIENT_BUILD_ID} > build/BUILD_ID ) ; fi
	@if [ -z "${STAFF_CLIENT_BUILD_ID}" ]; then ( echo "No Build ID for versioning" ; echo "none" > build/BUILD_ID ) ; fi
	@sed -n -e 's/^AC_INIT([^,]*, \([^,]*\),.*$$/\1/p' @top_srcdir@/configure.ac > build/VERSION
	@if [ "${STAFF_CLIENT_VERSION}" == "trunk" ]; then echo "0${GIT_BRANCH}.${GIT_TAG}" > build/VERSION; fi 
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
	@if [ -n "${STAFF_CLIENT_NAME}" ]; then sed -i -e s/^Name=.\*/Name=${STAFF_CLIENT_NAME}/ build/application.ini ; fi
	@if [ -z "${AUTOUPDATE_HOST}" ]; then rm -f build/defaults/preferences/autoupdate.js; fi
	@if [ -z "${AUTOUPDATE_HOST}" ]; then sed -i -e /updateURL/d build/install.rdf; fi
	@if [ -n "${AUTOUPDATE_HOST}" ]; then echo "Applying automatic update host ${AUTOUPDATE_HOST}"; fi
	@if [ -n "${AUTOUPDATE_HOST}" ]; then sed -i -e "s|::HOSTNAME::|${AUTOUPDATE_HOST}|" -e "s|https\?://\(https\?://\)|\1|" build/defaults/preferences/autoupdate.js; fi
	@if [ -n "${AUTOUPDATE_HOST}" ]; then sed -i -e "s|::HOSTNAME::|${AUTOUPDATE_HOST}|" -e "s|https\?://\(https\?://\)|\1|" build/install.rdf; fi
	@cp build/STAMP_ID PREV_STAMP_ID
	@cp build/VERSION PREV_VERSION

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
	mkdir -p $(DESTDIR)$(WEBDIR)
	mkdir -p $(DESTDIR)$(WEBDIR)/xul/
	@echo "STAMP_ID = $(STAFF_CLIENT_STAMP_ID)"
	@echo "Copying xul into $(DESTDIR)$(WEBDIR)/xul/$(STAFF_CLIENT_STAMP_ID)"
	mkdir -p "$(DESTDIR)$(WEBDIR)/xul/$(STAFF_CLIENT_STAMP_ID)"
	cp -R @top_srcdir@/Open-ILS/xul/staff_client/build/server "$(DESTDIR)${WEBDIR}/xul/${STAFF_CLIENT_STAMP_ID}/"

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
	@make linux32-client
	@make linux64-client
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
	@echo 'Installing Extensions'
	@mkdir -p client/extensions
# Note: XULRunner before 4 requires extracted extensions
# XULRunner after 4 keeps them in XPI form...unless their manifest says to unpack
# This block is thus structured to make it easy to add the latter kind later.
	@if [ ${XULRUNNER_MAJOR_VERSION} -lt 4 ]; then \
		if [ -f extensions/${DOMINSPECTOR_ID}.xpi ]; then \
			mkdir -p client/extensions/${DOMINSPECTOR_ID}/; \
			unzip extensions/${DOMINSPECTOR_ID}.xpi -d client/extensions/${DOMINSPECTOR_ID}/; \
		fi; \
		if [ -f extensions/${VENKMAN_ID}.xpi ]; then \
			mkdir -p client/extensions/${VENKMAN_ID}/; \
			unzip extensions/${VENKMAN_ID}.xpi -d client/extensions/${VENKMAN_ID}/; \
		fi; \
	else \
		if [ -f extensions/${DOMINSPECTOR_ID}.xpi ]; then \
			cp extensions/${DOMINSPECTOR_ID}.xpi client/extensions/; \
		fi; \
		if [ -f extensions/${VENKMAN_ID}.xpi ]; then \
			cp extensions/${VENKMAN_ID}.xpi client/extensions/; \
		fi; \
	fi

# If automatic updates are enabled, or the standalone_xul_app.js is present,
# the extension can break Firefox.
# Also, per machine registration + extension mode is probably a bad idea.
# Remove those, and we need an updated chrome.manifest

client_ext: client_dir
	@echo 'Cleaning App Information'
	@rm -f client/application.ini
	@rm -f client/defaults/preferences/autoupdate.js
	@rm -f client/defaults/preferences/autochannel.js
	@rm -f client/defaults/preferences/standalone_xul_app.js
	@rm -f client/defaults/preferences/aa_per_machine.js
	@echo 'Prepping chrome.manifest'
	@perl -ne 'if(/open_ils_staff_client/) { s/ (?!chrome:\/\/open_ils_staff_client)([^ ]*)$$/ chrome\/\1/; print; }' client/chrome/chrome.manifest > client/chrome.manifest
	@grep -v manifest build/chrome.manifest >> client/chrome.manifest

# Would merge client_ext into this one, but this way an installer that doesn't
# use an xpi can be made for extension later, if desired

extension: client_ext
	@echo ' * Packaging as an XPI'
	@(cd client/ && zip -q -r ../evergreen.xpi * -x defaults/preferences/standalone_xul_app.js)
	@md5sum evergreen.xpi > evergreen.xpi.md5

# Fetch extensions to load into the client
# This could be done in a "if they aren't there" fashion, but these are manually triggered anyway
# That, and this way you can update the extensions by running this target again
fetch-extensions: fetch-dom-inspector fetch-venkman

fetch-dom-inspector:
	@echo 'Fetching DOM Inspector'
	@mkdir -p extensions/
	@wget -Oextensions/${DOMINSPECTOR_ID}.xpi ${DOMINSPECTOR_URL}

fetch-venkman:
	@echo 'Fetching Venkman'
	@mkdir -p extensions/
	@wget -Oextensions/${VENKMAN_ID}.xpi ${VENKMAN_URL}

# Generic client, as an xpi, theoretically suitable for --install-app usage

generic-client: client_app
	@echo 'Packing Generic Client via zip (as xpi file)'
	@rm -f evergreen_staff_client.xpi
	@cd client && zip -q -r ../evergreen_staff_client.xpi *
	@echo done

# These two targets complete the layout defined on
# https://developer.mozilla.org/en/XULRunner/Deploying_XULRunner_1.8
# for their respective platforms in regards to XULRunner deployment

nsis_check:
	@echo 'Checking for makensis'
	@type -P makensis > /dev/null || ( echo 'MAKENSIS NOT FOUND: Cannot continue. Do you need to install the NSIS package?' && exit 1 )

unzip_check:
	@echo 'Checking for unzip'
	@type -P unzip > /dev/null || ( echo 'UNZIP NOT FOUND: Cannot continue.' && exit 1 )

branding_check:
	@echo 'Checking for branding'
	@[ -f xulrunner-stub.exe ] || echo 'xulrunner-stub.exe not found'
	@[ -f build/evergreen.ico ] || echo 'build/evergreen.ico not found'
	@if [ ! -f xulrunner-stub.exe -o ! -f build/evergreen.ico ]; then echo 'Branding incomplete. Did you forget to run "make rigbeta" or "make rigrelease"?'; echo 'You will need to "make rebuild" afterwards.'; exit 1; fi

# Note that I decided to use win/lin channels for ease of coding platform specific updates

win-xulrunner: unzip_check branding_check client_app
	@echo 'Preparing Windows xulrunner'
	@if [ ! -f ${XULRUNNER_WINFILE} ]; then wget ${XULRUNNER_URL}${XULRUNNER_WINFILE}; fi
	@unzip -q ${XULRUNNER_WINFILE} -dclient
	@if [ -f client/defaults/preferences/autoupdate.js ]; then echo 'pref("app.update.channel","win");' >> client/defaults/preferences/autochannel.js; fi;
	@if [ -d branding_win ]; then cp -fR branding_win/* client/; fi
	@echo 'Preparing stub'
	@if [ -f xulrunner-stub.exe ]; then cp xulrunner-stub.exe client/evergreen.exe; rm client/xulrunner/xulrunner-stub.exe; else mv client/xulrunner/xulrunner-stub.exe client/evergreen.exe; fi
	@if [ ${XULRUNNER_MAJOR_VERSION} -ge 4 -a -f client/xulrunner/mozcrt19.dll ]; then cp client/xulrunner/mozcrt19.dll client/; fi # XULRunner 4+ need this, if the file exists
	@if [ ${XULRUNNER_MAJOR_VERSION} -ge 9 -a -f client/xulrunner/mozutils.dll ]; then cp client/xulrunner/mozutils.dll client/; fi # XULRunner 9+ need this, if the file exists

linux32-xulrunner: client_app
	@echo 'Preparing Linux (32 bit) xulrunner'
	@if [ ! -f ${XULRUNNER_LINUX32FILE} ]; then wget ${XULRUNNER_URL}${XULRUNNER_LINUX32FILE}; fi
	@cd client; tar xjf ../${XULRUNNER_LINUX32FILE}; cd ..
	@if [ -f client/defaults/preferences/autoupdate.js ]; then echo 'pref("app.update.channel","lin");' >> client/defaults/preferences/autochannel.js; fi;
	@if [ -d branding_lin ]; then cp -fR branding_lin/* client/; fi
	@echo 'Preparing stub'
	@mv client/xulrunner/xulrunner-stub client/evergreen

linux64-xulrunner: client_app
	@echo 'Preparing Linux (64 bit) xulrunner'
	@if [ ! -f ${XULRUNNER_LINUX64FILE} ]; then wget ${XULRUNNER_URL}${XULRUNNER_LINUX64FILE}; fi
	@cd client; tar xjf ../${XULRUNNER_LINUX64FILE}; cd ..
	@if [ -f client/defaults/preferences/autoupdate.js ]; then echo 'pref("app.update.channel","lin64");' >> client/defaults/preferences/autochannel.js; fi;
# Note: We assume that we want 32 bit branding files, but provide a way to override for 64 bit
	@if [ -d branding_lin ]; then cp -fR branding_lin/* client/; fi
	@if [ -d branding_lin64 ]; then cp -fR branding_lin64/* client/; fi
	@echo 'Preparing stub'
	@mv client/xulrunner/xulrunner-stub client/evergreen


# Build a windows installer.

win-client: nsis_check win-xulrunner
	@if [ "${NSIS_AUTOUPDATE}${NSIS_PERMACHINE}" -a ! -d AccessControl ]; then echo 'Fetching AccessControl Plugin'; wget ${NSIS_ACCESSCONTROL} -O AccessControl.zip; unzip AccessControl.zip $$(unzip -t AccessControl.zip | grep 'AccessControl/Contrib/' > /dev/null || echo "-dAccessControl"); fi
	@echo 'Building installer'
	@makensis -V2 -DPRODUCT_VERSION="${STAFF_CLIENT_VERSION}" ${NSIS_WICON} ${NSIS_AUTOUPDATE} ${NSIS_DEV} ${NSIS_PERMACHINE} ${NSIS_EXTRAS} ${NSIS_EXTRAOPTS} windowssetup.nsi
	@echo 'Done'

# For linux, just build a tar.bz2 archive

linux32-client: linux32-xulrunner
	@echo 'Packing as evergreen_staff_client_i686.tar.bz2'
	@rm -f evergreen_staff_client_i686.tar.bz2
	@cd client; tar cjf ../evergreen_staff_client_i686.tar.bz2 *; cd ..
	@echo 'Done'

linux64-client: linux64-xulrunner
	@echo 'Packing as evergreen_staff_client_x86_64.tar.bz2'
	@rm -f evergreen_staff_client_x86_64.tar.bz2
	@cd client; tar cjf ../evergreen_staff_client_x86_64.tar.bz2 *; cd ..
	@echo 'Done'

# For running the updates script with the correct updates directory, optionally building clients as well

updates updates-client win-updates win-updates-client linux32-updates linux32-updates-client linux64-updates linux64-updates-client generic-updates generic-updates-client extension-updates:
	@if [ ! -f build/BUILD_ID ]; then echo 'ERROR! Current build not stamped!'; exit 1; fi
	@if [ ! -x external/make_updates.sh ]; then chmod u+x external/make_updates.sh; fi
	@if [ ! -x external/make_updates.sh ]; then echo 'ERROR! external/make_updates.sh is not executable!'; exit 1; fi
	@external/make_updates.sh ${UPDATESDIR} $@
