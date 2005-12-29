# ------------------------------------------------------------------------
# Evergreen makefile
# ------------------------------------------------------------------------

NEW_OPAC_URL=myopac.domain
NEW_XUL_PACKAGE_NAME=openils
NEW_XUL_PACKAGE_LABEL=OpenILS

# A kludge until we move the generic parts of the staff client to Open-ILS

all:	xul 

install: 	circ-install iplist-install

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
	cp circ_rules/*.rules $(CIRCRULESDIR)/

iplist-install:
	@echo $@
	mkdir -p $(ETCDIR)
	cp conf/lib_ips.txt $(ETCDIR)

clean:
	if [ -d local_staff_client ]; then make -C local_staff_client clean; fi;

