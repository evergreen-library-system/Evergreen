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

sysconf_DATA = $(examples)/opensrf.xml.example \
	       $(examples)/opensrf_core.xml.example \
	       $(examples)/fm_IDL.xml \
	       $(examples)/oils_sip.xml.example \
	       $(examples)/oils_web.xml.example \
	       $(examples)/lib_ips.txt.example

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

core_scripts =   $(examples)/oils_ctl.sh \
		 $(supportscr)/fine_generator.pl \
		 $(supportscr)/hold_targeter.pl \
		 $(supportscr)/reshelving_complete.srfsh \
		 $(supportscr)/juv_to_adult.srfsh \
		 $(supportscr)/thaw_expired_frozen_holds.srfsh \
		 $(supportscr)/long-overdue-status-update.pl \
		 $(srcdir)/extras/openurl_map.pl \
		 $(srcdir)/extras/fast-extract \
		 $(srcdir)/extras/import/marc_add_ids
	 
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
# Build Apache modules
#--------------------

if BUILDAPACHEMODS
OILSWEB_DIR = apachemods
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

# Take care of which subdirectories to build, and which extra files to include in a distribution.

SUBDIRS = $(OILSCORE_DIRS) $(OILSWEB_DIR) $(OILSPYTHON_DIR) $(OILSJAVA_DIR)

EXTRA_DIST = @srcdir@/perlmods @srcdir@/templates @top_srcdir@/Open-ILS/xsl @srcdir@/cgi-bin

# Install header files

oilsincludedir = $(DESTDIR)@includedir@/openils
headsdir = @top_srcdir@/Open-ILS/include/openils
oilsinclude_HEADERS = $(headsdir)/idl_fieldmapper.h $(headsdir)/oils_constants.h $(headsdir)/oils_event.h $(headsdir)/oils_idl.h $(headsdir)/oils_utils.h

# Install everything that did not get installed by autotools

install-data-hook: $(OILSCORE_INST) $(OILSWEB_INST) $(OILSREP_INST)

uninstall-hook:
	rm -R $(perldir)
	rm -R $(TEMPLATEDIR)
	rm -R $(XSLDIR)
	rm -R $(CGIDIR)


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
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/reshelving_complete.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/juv_to_adult.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/long-overdue-status-update.pl'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/long-overdue-status-update.pl'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/thaw_expired_frozen_holds.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/offline-blocked-list.pl'

reporter-install:
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/clark-kent.pl'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/find_orphaned_reports.pl'


