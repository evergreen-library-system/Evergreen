#---------------------------------------------------------
# Makefile.am for updates
## Process this file with automake to generate Makefile.in
#---------------------------------------------------------

if BUILDILSUPDATES
OILSUPDATES_INST = updates-install

endif

install-exec-local: updates-install

uninstall-hook:
	rm -R $(UPDATESDIR)

updates-install:
	$(MKDIR_P) $(DESTDIR)$(UPDATESDIR)
	$(MKDIR_P) $(DESTDIR)$(UPDATESDIR)/patch
	$(MKDIR_P) $(DESTDIR)$(UPDATESDIR)/pub
	$(MKDIR_P) $(DESTDIR)$(UPDATESDIR)/archives
	cp @top_srcdir@/Open-ILS/updates/check $(DESTDIR)$(UPDATESDIR)/pub
	cp @top_srcdir@/Open-ILS/updates/download $(DESTDIR)$(UPDATESDIR)/pub
	cp @top_srcdir@/Open-ILS/updates/manualupdate.html $(DESTDIR)$(UPDATESDIR)/pub
	cp @top_srcdir@/Open-ILS/updates/update.rdf $(DESTDIR)$(UPDATESDIR)/pub
	cp @top_srcdir@/Open-ILS/updates/updatedetails.html $(DESTDIR)$(UPDATESDIR)/pub
