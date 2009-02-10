# Copyright (C) 2008 Equinox Software, Inc.
# Kevin Beswick <kevinbeswick00@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
## Process this file with automake to generate Makefile.in


export INCDIR = "$(INCLUDEDIR)/openils/"
export STAFF_CLIENT_BUILD_ID = `/bin/cat @top_srcdir@/Open-ILS/xul/staff_client/build/BUILD_ID`
export DEF_LDFLAGS = -L. -L$(TMP) -L$(OPENSRF_LIBS)
export DEF_CFLAGS = -D_LARGEFILE64_SOURCE -pipe -g -Wall -O2 -fPIC -I@top_srcdir@/include -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) -I$(APR_HEADERS)  -I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(OPENSRF_HEADERS)
export DEF_LDLIBS = -lopensrf 


# Establish some installation directories and such
prefix=@prefix@
exec_prefix=@exec_prefix@
datadir=@localstatedir@/data
circrulesdir=@localstatedir@/circ
catalogscriptdir=@localstatedir@/catalog
penaltyrulesdir=@localstatedir@/penalty
examples = @top_srcdir@/Open-ILS/examples
jsbackend = @srcdir@/javascript/backend
supportscr = @srcdir@/support-scripts
webdir = $(WEBDIR)
opacjsdir = $(DESTDIR)$(WEBDIR)/opac/common/js
jsdojodir = $(DESTDIR)$(WEBDIR)/js/dojo
jsdojoosrfdir = $(DESTDIR)$(WEBDIR)/js/dojo/opensrf
opacextrasdir = $(DESTDIR)$(WEBDIR)/opac/extras/xsl/
reportsdir = $(DESTDIR)$(WEBDIR)/reports/

# Collect files to be used by multiple targets

autojsbinscripts = @srcdir@/extras/fieldmapper.pl \
 	 @srcdir@/extras/locale_html_options.pl \
 	 @srcdir@/extras/org_tree_js.pl \
	 @srcdir@/extras/org_lasso_js.pl \
	 @srcdir@/extras/org_tree_html_options.pl \
	 @srcdir@/extras/org_tree_proximity.pl \
	 @srcdir@/extras/autogen.sh \
	 @srcdir@/support-scripts/offline-blocked-list.pl 

# Decide which entities to build

#----------------------------
# Build ILS CORE
#----------------------------

if BUILDILSCORE

#Add directories to build
OILSCORE_DIRS = c-apps extras 
#Add manual (non-automake) install targets for simplicity of installing.
OILSCORE_INST = ilscore-install

core_data = @srcdir@/extras/ils_events.xml \
	    $(examples)/hold_notification_template.example

sysconf_DATA = $(examples)/opensrf.xml.example \
	       $(examples)/opensrf_core.xml.example \
	       $(examples)/fm_IDL.xml \
	       $(examples)/oils_sip.xml.example \
	       $(examples)/lib_ips.txt.example

core_scripts =   $(examples)/oils_ctl.sh \
		 $(supportscr)/fine_generator.pl \
		 $(supportscr)/hold_targeter.pl \
		 $(supportscr)/reshelving_complete.srfsh \
		 $(supportscr)/thaw_expired_frozen_holds.srfsh \
		 $(supportscr)/long-overdue-status-update.pl \
		 $(srcdir)/extras/openurl_map.pl 
	 
installautojs = $(autojsbinscripts)

#circ-rules-install
circrules_SCRIPTS = $(jsbackend)/circ/circ_duration.js \
		    $(jsbackend)/circ/circ_groups.js \
		    $(jsbackend)/circ/circ_item_config.js \
		    $(jsbackend)/circ/circ_lib.js \
		    $(jsbackend)/circ/circ_permit_copy.js \
		    $(jsbackend)/circ/circ_permit_hold.js \
		    $(jsbackend)/circ/circ_permit_patron.js \
		    $(jsbackend)/circ/circ_permit_renew.js 
penaltyrules_SCRIPTS = $(jsbackend)/penalty/patron_penalty.js
catalogscript_SCRIPTS = $(jsbackend)/catalog/biblio_descriptor.js \
		        $(jsbackend)/catalog/biblio_fingerprint.js \
			$(jsbackend)/catalog/fixed_fields.js \
		        $(jsbackend)/catalog/phys_char.js \
	                $(jsbackend)/catalog/record_type.js

endif

#--------------------
# Build ILS WEB
#--------------------

if BUILDILSWEB
OILSWEB_DIRS = apachemods
OILSWEB_INST = webcore-install offline-install cgi-bootstrap

#webcore-install

reports_SCRIPTS = @top_srcdir@/Open-ILS/xul/staff_client/server/admin/adminlib.js
opacjs_SCRIPTS = $(OPENSRF_LIBS)/javascript/DojoSRF.js \
		 $(OPENSRF_LIBS)/javascript/JSON_v0.js \
		 $(OPENSRF_LIBS)/javascript/JSON_v1.js \
		 $(OPENSRF_LIBS)/javascript/md5.js \
		 $(OPENSRF_LIBS)/javascript/opensrf.js \
		 $(OPENSRF_LIBS)/javascript/opensrf_xhr.js \
		 $(OPENSRF_LIBS)/javascript/opensrf_xmpp.js \
		 @top_srcdir@/Open-ILS/xul/staff_client/chrome//content//util/date.js
jsdojo_SCRIPTS = $(OPENSRF_LIBS)/javascript/DojoSRF.js
jsdojoosrf_SCRIPTS = $(OPENSRF_LIBS)/javascript/md5.js \
		     $(OPENSRF_LIBS)/javascript/JSON_v1.js \
		     $(OPENSRF_LIBS)/javascript/opensrf.js \
		     $(OPENSRF_LIBS)/javascript/opensrf_xhr.js \
		     $(OPENSRF_LIBS)/javascript/opensrf_xmpp.js

installautojs = $(autojsbinscripts)


endif


#---------------------
# Build ILS Reporter
#---------------------

if BUILDILSREPORTER
OILSREP_INST = reporter-install
#reporter-install
reporter_scripts = @srcdir@/reporter/clark-kent.pl \
		   @srcdir@/reporter/find_orphaned_reports.pl
reporter_data = @srcdir@/reporter/report-fail \
	       @srcdir@/reporter/report-success
endif

#------------------------------
# Build ILS XUL CLIENT/SERVER
#------------------------------

if BUILDILSCLIENT
OILSCLIENT_DIRS = ../xul/staff_client
OILSSERVER_INST = server-xul
endif

#------------------------------
# Build EVERGREEN PYTHON
#------------------------------

if BUILDEGPYTHON
OILSPYTHON_DIR = python
endif

#------------------------------
# Build EVERGREEN JAVA
#------------------------------

if BUILDEGJAVA
OILSJAVA_DIR = java
endif

bin_SCRIPTS = $(core_scripts) $(reporter_scripts) $(installautojs) @srcdir@/extras/eg_config
data_DATA = $(core_data) $(reporter_data)

# Take care of which subdirectories to build, and which extra files to include in a distibution.

SUBDIRS = $(OILSCORE_DIRS) $(OILSWEB_DIRS) $(OILSCLIENT_DIRS) $(OILSPYTHON_DIR) $(OILSJAVA_DIR)

EXTRA_DIST = @srcdir@/perlmods @srcdir@/templates @top_srcdir@/Open-ILS/xsl @srcdir@/cgi-bin

# Install header files

oilsincludedir = $(DESTDIR)@includedir@/openils
headsdir = @top_srcdir@/Open-ILS/include/openils
oilsinclude_HEADERS = $(headsdir)/idl_fieldmapper.h $(headsdir)/oils_constants.h $(headsdir)/oils_event.h $(headsdir)/oils_idl.h $(headsdir)/oils_utils.h

# Install everything that did not get installed by autotools

install-data-hook: $(OILSCORE_INST) $(OILSWEB_INST) $(OILSREP_INST) $(OILSSERVER_INST)

uninstall-hook:
	rm -R $(perldir)
	rm -R $(TEMPLATEDIR)
	rm -R $(XSLDIR)
	rm -R $(CGIDIR)
	rm -R $(webdir)
	rm -R $(opacextrasdir)


#perl-install and string-templates-install	
ilscore-install:
	@echo $@
	@echo "Installing Perl modules"
	mkdir -p $(perldir)
	mkdir -p $(TEMPLATEDIR)
	cp -r @srcdir@/perlmods/* $(perldir)
	cp -r @srcdir@/templates/marc $(TEMPLATEDIR)
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@libdir@/perl5/OpenILS/WWW/Web.pm'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@libdir@/perl5/OpenILS/WWW/Method.pm'
	@echo "Installing string templates to $(TEMPLATEDIR)"
	mkdir -p $(TEMPLATEDIR)
	mkdir -p $(datadir)/overdue/
	cp -r @srcdir@/templates/strings $(TEMPLATEDIR)
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@sysconfdir@/oils_sip.xml.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@sysconfdir@/oils_sip.xml.example'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@sysconfdir@/opensrf_core.xml.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@sysconfdir@/opensrf_core.xml.example'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@sysconfdir@/opensrf.xml.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@sysconfdir@/opensrf.xml.example'
	sed -i 's|LIBDIR|@libdir@|g' '$(DESTDIR)@sysconfdir@/opensrf.xml.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/reshelving_complete.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/long-overdue-status-update.pl'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/long-overdue-status-update.pl'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/thaw_expired_frozen_holds.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/offline-blocked-list.pl'

webcore-install:
	mkdir -p $(WEBDIR)
	mkdir -p $(WEBDIR)/opac/extras/slimpac/
	mkdir -p $(WEBDIR)/standalone/
	mkdir -p $(opacextrasdir)
	mkdir -p $(DESTDIR)$(reportsdir)
	mkdir -p $(XSLDIR)
	rm -f $(DESTDIR)$(reportsdir)/fm_IDL.xml
	cp $(DESTDIR)@sysconfdir@/fm_IDL.xml $(DESTDIR)$(WEBDIR)/reports/
	cp -r @top_srcdir@/Open-ILS/web/. $(DESTDIR)$(WEBDIR)
	cp @top_srcdir@/Open-ILS/xsl/*.xsl $(opacextrasdir)
	cp @top_srcdir@/Open-ILS/xsl/*.xsl $(XSLDIR)
	cp -r $(DESTDIR)$(WEBDIR)/opac/skin/default $(DESTDIR)$(WEBDIR)/opac/skin/craftsman
	cp -r @top_srcdir@/Open-ILS/web/opac/skin/craftsman/* $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/mresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/rresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/rdetail.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/advanced.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/myopac.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/default/xml/cnbrowse.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/mresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/rresult.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/rdetail.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/advanced.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/myopac.xml
	ln -sf $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/index.xml $(DESTDIR)$(WEBDIR)/opac/skin/craftsman/xml/cnbrowse.xml


offline-install:
	@echo "Installing offline CGIs to $(CGIDIR)/offline";
	mkdir -p $(TMP)
	mkdir -p $(CGIDIR)/offline;
	mkdir -p $(datadir)/offline;
	perl -pe "s{##CONFIG##}{@sysconfdir@}" < @srcdir@/offline/offline.pl > $(TMP)/offline.pl;
	cp $(TMP)/offline.pl $(DESTDIR)$(CGIDIR)/offline/
	chmod +x $(DESTDIR)$(CGIDIR)/offline/offline.pl

cgi-bootstrap:
	@echo "Installing cgi's to $(CGIDIR)"
	mkdir -p $(TMP)/cgi-bin
	mkdir -p $(CGIDIR)
	for i in @srcdir@/cgi-bin/*cgi; do perl -pe "s{##CONFIG##}{@sysconfdir@}" < $$i > $(TMP)/$$i; done
	cp $(TMP)/cgi-bin/*cgi $(CGIDIR)
	cp -r @srcdir@/cgi-bin/support $(CGIDIR)
	chmod 755 $(DESTDIR)$(CGIDIR)/*cgi

server-xul:
	@echo $@
	mkdir -p $(WEBDIR)
	mkdir -p $(WEBDIR)/xul/
	@echo "BUILD_ID = $(STAFF_CLIENT_BUILD_ID)"
	@echo "Copying xul into $(WEBDIR)/xul/$(STAFF_CLIENT_BUILD_ID)"
	mkdir -p "$(WEBDIR)/xul/$(STAFF_CLIENT_BUILD_ID)"
	cp -R @top_srcdir@/Open-ILS/xul/staff_client/build/server "${WEBDIR}/xul/${STAFF_CLIENT_BUILD_ID}/"

reporter-install:
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/clark-kent.pl'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/find_orphaned_reports.pl'


