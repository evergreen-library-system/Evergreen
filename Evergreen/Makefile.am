#--------------------------------------------------------------------
# Makefile.am for Evergreen
# Author: Kevin Beswick (kevinbeswick00@gmail.com)
## Process this file with automake to generate Makefile.in
#-------------------------------------------------------------------

NEW_OPAC_URL=myopac.domain
NEW_XUL_PACKAGE_NAME=openils
NEW_XUL_PACKAGE_LABEL=OpenILS

if BUILDEGCORE
EGCORE_INST = circ-install iplist-install perl-install web-install
endif 

if BUILDEGXULCLIENT
EGXUL_INST = xul
endif

install-data-hook: $(EGCORE_INST) $(EGXUL_INST)

xul:
	@echo $@
	cp -R staff_client local_staff_client
	find local_staff_client/ -type f -exec sed -i s/evergreen/${NEW_XUL_PACKAGE_NAME}/g {} \;
	find local_staff_client/ -type f -exec sed -i s/Evergreen/${NEW_XUL_PACKAGE_LABEL}/g {} \;
	(cd local_staff_client/chrome/skin/evergreen; mv evergreen.css ${NEW_XUL_PACKAGE_NAME}.css)
	(cd local_staff_client/defaults/preferences; mv evergreen.js ${NEW_XUL_PACKAGE_NAME}.js)
	(cd local_staff_client/chrome/content; mv evergreen ${NEW_XUL_PACKAGE_NAME})
	(cd local_staff_client/chrome/locale/en-US/; mv evergreen ${NEW_XUL_PACKAGE_NAME})
	(cd local_staff_client/chrome/skin; mv evergreen ${NEW_XUL_PACKAGE_NAME})
	make -C local_staff_client build
	find local_staff_client/ -type f -exec sed -i s/gapines.org/${NEW_OPAC_URL}/g {} \;
	make -C local_staff_client package

perl-install:
	@echo $@
	mkdir -p $(PERLDIR)
	cp -r src/perlmods/* $(PERLDIR)

circ-install:
	@echo $@
	mkdir -p $(CIRCRULESDIR)
	cp src/javascript/backend/circ/*.js $(CIRCRULESDIR)

iplist-install:
	@echo $@
	mkdir -p $(ETCDIR)
	cp conf/lib_ips.txt $(ETCDIR)

web-install:
	@echo $@
	cp web/opac/images/* $(WEBDIR)/opac/images/

