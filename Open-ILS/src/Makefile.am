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


export STAFF_CLIENT_BUILD_ID = `/bin/cat @top_srcdir@/Open-ILS/xul/staff_client/build/BUILD_ID`
export DEF_LDFLAGS = -L. -L$(TMP) -L$(OPENSRF_LIBS)
export DEF_CFLAGS = -D_LARGEFILE64_SOURCE -pipe -g -Wall -O2 -fPIC -I@top_srcdir@/include -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) -I$(APR_HEADERS)  -I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(OPENSRF_HEADERS) -I$(HIREDIS_HEADERS)
export DEF_LDLIBS = -lopensrf 


# Establish some installation directories and such
prefix=@prefix@
exec_prefix=@exec_prefix@
datadir=@localstatedir@/data
examples = @top_srcdir@/Open-ILS/examples
supportscr = @srcdir@/support-scripts

# Collect files to be used by multiple targets

autojsbinscripts = @srcdir@/extras/autogen.sh

# Decide which entities to build

sysconf_DATA = $(examples)/action_trigger_filters.json.example \
	       $(examples)/opensrf.xml.example \
	       $(examples)/opensrf_core.xml.example \
	       $(examples)/fm_IDL.xml \
	       $(examples)/oils_sip.xml.example \
	       $(examples)/lib_ips.txt.example \
	       $(examples)/oils_yaz.xml.example \
	       $(examples)/kpac.xml.example \
	       $(examples)/oils_z3950.xml.example \
	       $(examples)/marc_stream_importer.conf.example

#----------------------------
# Build ILS CORE
#----------------------------

if BUILDILSCORE

#Add directories to build
OILSCORE_DIRS = c-apps extras perlmods
#Add manual (non-automake) install targets for simplicity of installing.
OILSCORE_INST = ilscore-install

core_data = @srcdir@/extras/ils_events.xml \
	    $(examples)/hold_notification_template.example

core_scripts =   $(examples)/oils_ctl.sh \
		 $(supportscr)/fine_generator.pl \
		 $(supportscr)/hold_targeter.pl \
		 $(supportscr)/hold_targeter_legacy.pl \
		 $(supportscr)/reshelving_complete.srfsh \
		 $(supportscr)/clear_expired_circ_history.srfsh \
		 $(supportscr)/update_hard_due_dates.srfsh \
		 $(supportscr)/refresh_carousels.srfsh \
		 $(supportscr)/juv_to_adult.srfsh \
		 $(supportscr)/thaw_expired_frozen_holds.srfsh \
		 $(supportscr)/long-overdue-status-update.pl \
		 $(supportscr)/oils_header.pl \
		 $(supportscr)/badge_score_generator.pl \
		 $(supportscr)/purge_at_events.srfsh \
		 $(supportscr)/purge_holds.srfsh \
		 $(supportscr)/purge_circulations.srfsh \
		 $(supportscr)/purge_pending_users.srfsh \
		 $(supportscr)/clear_cc_number.srfsh \
		 $(supportscr)/age_money.srfsh \
		 $(supportscr)/sitemap_generator \
		 $(srcdir)/extras/eg_config \
		 $(srcdir)/extras/openurl_map.pl \
		 $(srcdir)/extras/import/marc_add_ids \
		 $(supportscr)/pingest.pl \
		 $(supportscr)/ingest_ctl \
		 $(supportscr)/background_import_mgr.pl \
		 $(supportscr)/edi_fetcher.pl \
		 $(supportscr)/edi_order_pusher.pl \
		 $(supportscr)/edi_pusher.pl \
		 $(supportscr)/purge_hold_reset_reason_entries.srfsh

installautojs = $(autojsbinscripts)

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

# scripts that are generated from *.in files and can
# be deleted by a make clean
gen_scripts = \
	@srcdir@/extras/fast-extract \
	@srcdir@/extras/import/marc2are.pl \
	@srcdir@/extras/import/marc2bre.pl \
	@srcdir@/extras/import/marc2sre.pl \
	@srcdir@/extras/import/parallel_pg_loader.pl \
	$(supportscr)/action_trigger_aggregator.pl \
	$(supportscr)/action_trigger_runner.pl \
	$(supportscr)/authority_control_fields.pl \
	$(supportscr)/authority_authority_linker.pl \
	$(supportscr)/eg_db_config \
	$(supportscr)/marc_export \
	$(supportscr)/marc_stream_importer.pl \
	$(supportscr)/offline-blocked-list.pl

# config files that are generated from *.in files and can
# be deleted by a make clean
gen_docs = \
	$(examples)/apache_24/eg_startup \
	$(examples)/apache_24/eg_24.conf \
	$(examples)/apache_24/eg_vhost_24.conf

bin_SCRIPTS = $(core_scripts) $(gen_scripts) $(reporter_scripts) $(installautojs)

CLEANFILES = $(gen_scripts)

data_DATA = $(core_data) $(reporter_data)

doc_DATA = $(gen_docs)

# Take care of which subdirectories to build, and which extra files to include in a distribution.

SUBDIRS = $(OILSCORE_DIRS) $(OILSWEB_DIR)

EXTRA_DIST = @srcdir@/perlmods \
	@srcdir@/data \
	@srcdir@/templates \
	@top_srcdir@/Open-ILS/xsl \
	@srcdir@/cgi-bin \
	$(gen_scripts) \
	$(gen_docs) \
	@srcdir@/extras/eg_config

do_subst = $(SED) \
	-e 's,[@]bindir[@],$(bindir),g' \
	-e 's,[@]datarootdir[@],$(datarootdir),g' \
	-e 's,[@]docdir[@],$(docdir),g' \
	-e 's,[@]exec_prefix[@],$(exec_prefix),g' \
	-e 's,[@]includedir[@],$(includedir),g' \
	-e 's,[@]libdir[@],$(libdir),g' \
	-e 's,[@]localstatedir[@],$(localstatedir),g' \
	-e 's,[@]prefix[@],$(prefix),g' \
	-e 's,[@]sysconfdir[@],$(sysconfdir),g'

# Install header files

oilsincludedir = @includedir@/openils
headsdir = @top_srcdir@/Open-ILS/include/openils
oilsinclude_HEADERS = $(headsdir)/idl_fieldmapper.h $(headsdir)/oils_constants.h $(headsdir)/oils_event.h $(headsdir)/oils_idl.h $(headsdir)/oils_utils.h

# Install everything that did not get installed by autotools

install-data-hook: $(OILSCORE_INST) $(OILSWEB_INST) $(OILSUPDATES_INST) $(OILSREP_INST)

uninstall-hook:
	rm -R $(TEMPLATEDIR)
	rm -R $(BOOTSTRAPTEMPLATEDIR)
	rm -R $(XSLDIR)
	rm -R $(CGIDIR)

@srcdir@/extras/fast-extract: Makefile @srcdir@/extras/fast-extract.in
	$(do_subst) @srcdir@/extras/fast-extract.in > "$@"
	chmod 755 "$@"

@srcdir@/extras/import/marc2are.pl: Makefile @srcdir@/extras/import/marc2are.pl.in
	$(do_subst) @srcdir@/extras/import/marc2are.pl.in > "$@"
	chmod 755 "$@"

@srcdir@/extras/import/marc2bre.pl: Makefile @srcdir@/extras/import/marc2bre.pl.in
	$(do_subst) @srcdir@/extras/import/marc2bre.pl.in > "$@"
	chmod 755 "$@"

@srcdir@/extras/import/marc2sre.pl: Makefile @srcdir@/extras/import/marc2sre.pl.in
	$(do_subst) @srcdir@/extras/import/marc2sre.pl.in > "$@"
	chmod 755 "$@"

@srcdir@/extras/import/parallel_pg_loader.pl: Makefile @srcdir@/extras/import/parallel_pg_loader.pl.in
	$(do_subst) @srcdir@/extras/import/parallel_pg_loader.pl.in > "$@"
	chmod 755 "$@"

$(supportscr)/action_trigger_aggregator.pl: Makefile $(supportscr)/action_trigger_aggregator.pl.in
	$(do_subst) $(supportscr)/action_trigger_aggregator.pl.in > "$@"
	chmod 755 "$@"

$(supportscr)/action_trigger_runner.pl: Makefile $(supportscr)/action_trigger_runner.pl.in
	$(do_subst) $(supportscr)/action_trigger_runner.pl.in > "$@"
	chmod 755 "$@"

$(supportscr)/authority_authority_linker.pl: Makefile $(supportscr)/authority_authority_linker.pl.in
	$(do_subst) $(supportscr)/authority_authority_linker.pl.in > "$@"
	chmod 755 "$@"

$(supportscr)/authority_control_fields.pl: Makefile $(supportscr)/authority_control_fields.pl.in
	$(do_subst) $(supportscr)/authority_control_fields.pl.in > "$@"
	chmod 755 "$@"

$(supportscr)/eg_db_config: Makefile $(supportscr)/eg_db_config.in
	$(do_subst) $(supportscr)/eg_db_config.in > "$@"
	chmod 755 "$@"

$(supportscr)/marc_export: Makefile $(supportscr)/marc_export.in
	$(do_subst) $(supportscr)/marc_export.in > "$@"
	chmod 755 "$@"

$(supportscr)/marc_stream_importer.pl: Makefile $(supportscr)/marc_stream_importer.pl.in
	$(do_subst) $(supportscr)/marc_stream_importer.pl.in > "$@"
	chmod 755 "$@"

$(supportscr)/offline-blocked-list.pl: Makefile $(supportscr)/offline-blocked-list.pl.in
	$(do_subst) $(supportscr)/offline-blocked-list.pl.in > "$@"
	chmod 755 "$@"

$(examples)/apache_24/eg_startup: Makefile $(examples)/apache_24/eg_startup.in
	$(do_subst) $(examples)/apache_24/eg_startup.in > "$@"

$(examples)/apache_24/eg_24.conf: Makefile $(examples)/apache_24/eg.conf.in
	$(do_subst) $(examples)/apache_24/eg.conf.in > "$@"

$(examples)/apache_24/eg_vhost_24.conf: Makefile $(examples)/apache_24/eg_vhost.conf.in
	$(do_subst) $(examples)/apache_24/eg_vhost.conf.in > "$@"

#perl-install and string-templates-install	
ilscore-install:
	@echo $@
	$(MKDIR_P) $(DESTDIR)$(TEMPLATEDIR)
	@echo "Installing templates to $(DESTDIR)$(TEMPLATEDIR)"
	cp -r @srcdir@/templates/* $(DESTDIR)$(TEMPLATEDIR)
	$(MKDIR_P) $(DESTDIR)$(BOOTSTRAPTEMPLATEDIR)
	@echo "Installing Bootstrap templates to $(DESTDIR)$(BOOTSTRAPTEMPLATEDIR)"
	cp -r @srcdir@/templates-bootstrap/* $(DESTDIR)$(BOOTSTRAPTEMPLATEDIR)
	-@if test -d @srcdir@/data/locale; then \
		$(MKDIR_P) $(DESTDIR)$(datadir)/locale/ && \
		echo "Installing template data files to $(datadir)/locale/" && \
		cp -r @srcdir@/data/locale/* $(datadir)/locale/ ;\
	fi;
	$(MKDIR_P) $(DESTDIR)$(datadir)/overdue/
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@sysconfdir@/oils_sip.xml.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@sysconfdir@/oils_sip.xml.example'
	sed -i 's|LIBDIR|@libdir@|g' '$(DESTDIR)@sysconfdir@/oils_sip.xml.example'
	sed -i 's|OPENSRF_BUS_PASSWORD|@OPENSRF_BUS_PASSWORD@|g' '$(DESTDIR)@sysconfdir@/opensrf_core.xml.example'
	sed -i 's|GATEWAY_BUS_PASSWORD|@GATEWAY_BUS_PASSWORD@|g' '$(DESTDIR)@sysconfdir@/opensrf_core.xml.example'
	sed -i 's|ROUTER_BUS_PASSWORD|@ROUTER_BUS_PASSWORD@|g' '$(DESTDIR)@sysconfdir@/opensrf_core.xml.example'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@sysconfdir@/opensrf_core.xml.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@sysconfdir@/opensrf_core.xml.example'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@sysconfdir@/opensrf.xml.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@sysconfdir@/opensrf.xml.example'
	sed -i 's|LIBDIR|@libdir@|g' '$(DESTDIR)@sysconfdir@/opensrf.xml.example'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@sysconfdir@/marc_stream_importer.conf.example'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@sysconfdir@/marc_stream_importer.conf.example'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/autogen.sh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/reshelving_complete.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/clear_expired_circ_history.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/update_hard_due_dates.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/refresh_carousels.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/juv_to_adult.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/purge_hold_reset_reason_entries.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/long-overdue-status-update.pl'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/long-overdue-status-update.pl'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/thaw_expired_frozen_holds.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/clear_cc_number.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/age_money.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/purge_at_events.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/purge_circulations.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/purge_holds.srfsh'
	sed -i 's|BINDIR|@bindir@|g' '$(DESTDIR)@bindir@/purge_pending_users.srfsh'
	sed -i 's|LOCALSTATEDIR|@localstatedir@|g' '$(DESTDIR)@bindir@/oils_ctl.sh'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/oils_ctl.sh'

reporter-install:
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/clark-kent.pl'
	sed -i 's|SYSCONFDIR|@sysconfdir@|g' '$(DESTDIR)@bindir@/find_orphaned_reports.pl'

docs-install: gen_docs
	$(MKDIR_P) $(DESTDIR)$(docdir)
