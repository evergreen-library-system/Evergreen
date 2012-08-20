PO=po
PROJECT=locale
LOCALE=fr-CA
STARTDIR=$(shell pwd)
POTLIST=$(shell ls -d po/*)
DTDDIR=../../Open-ILS/web/opac/locale
CHROME_PROPSDIR=../../Open-ILS/xul/staff_client/chrome/locale
SERVER_PROPSDIR=../../Open-ILS/xul/staff_client/server/locale
TT2_DATA_DIR=../../Open-ILS/src/data/locale
DOJO_LOCALE := $(shell echo ${LOCALE} | tr '[:upper:]' '[:lower:]')
DOJO_ACQ_SRC=../../Open-ILS/web/js/dojo/openils/acq/nls
DOJO_ACTOR_SRC=../../Open-ILS/web/js/dojo/openils/actor/nls
DOJO_AUTHORITY_SRC=../../Open-ILS/web/js/dojo/openils/authority/nls
DOJO_BOOKING_SRC=../../Open-ILS/web/js/dojo/openils/booking/nls
DOJO_CIRC_SRC=../../Open-ILS/web/js/dojo/openils/circ/nls
DOJO_CON_SRC=../../Open-ILS/web/js/dojo/openils/conify/nls
DOJO_OPAC_SRC=../../Open-ILS/web/js/dojo/openils/opac/nls
DOJO_RPT_SRC=../../Open-ILS/web/js/dojo/openils/reports/nls
DOJO_USER_SRC=../../Open-ILS/web/js/dojo/openils/User/nls
DOJO_WIDGET_SRC=../../Open-ILS/web/js/dojo/openils/widget/nls
FMIDLSRC=../../Open-ILS/examples/fm_IDL.xml
FMIDLOUT=fm_IDL.dtd.pot
FMIDLENT=fm_IDL.xml
FMIDLENTITY=fm_IDL.dtd
EVTSRC=../../Open-ILS/src/extras/ils_events.xml
EVTOUT=ils_events.xml.pot
EVTPO=ils_events.xml.po
EVTXML=ils_events.xml
REPORTDIR=../../Open-ILS/web/reports/
SQLSRCDIR=../../Open-ILS/src/sql/Pg/
SQLSRCFILE=950.data.seed-values.sql
SQLPOT=db.seed.pot
SQLPO=db.seed.po
SQLOUT=950.data.seed-values
TPAC_SRC=../../Open-ILS/src/templates/opac/
TT_LOCALE=../../Open-ILS/src/templates/locale/
PROGRESS=--progress none

# This Makefile can be used to generate and update PO files for Evergreen,
# as well as generate updated SQL, fieldmapper IDL, DTD and JavaScript
# property files from the PO.
#
# Usage:
#
# To create a new set of untranslated PO files for locale ll-LL:
#   make LOCALE=ll-LL newpo
#
# To create a new set of POT files from the en-US source:
#   make LOCALE=ll-LL newpot
#
# To update a set of translated PO files with new or changed en-US strings:
#   make LOCALE=ll-LL updatepo
#
# To create a set of translated project files (DTDs, JavaScript message catalogs):
#   make LOCALE=ll-LL project
#
# To install a set of translated project files:
#   make LOCALE=ll-LL install

# Generate PO files from all POT files in PO for locale LOCALE
#
# The template for the standard GNU gettext format is
# template1/template1.pot
# template1/ll-LL.po
# template2/template2.pot
# template2/ll-LL.po

# So, iterate over the list of POT directories and 
# generate / update the specified locale PO file
newpo: 
	@pot2po $(PROGRESS) -i po/acq.js/acq.js.pot -o $(PO)/acq.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/admin.properties/admin.properties.pot -o $(PO)/admin.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/auth.properties/auth.properties.pot -o $(PO)/auth.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/authority.js/authority.js.pot -o $(PO)/authority.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/capture.js/capture.js.pot -o $(PO)/capture.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/cat.properties/cat.properties.pot -o $(PO)/cat.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/circ.properties/circ.properties.pot -o $(PO)/circ.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/common.properties/common.properties.pot -o $(PO)/common.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.dtd/conify.dtd.pot -o $(PO)/conify.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.js/conify.js.pot -o $(PO)/conify.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/db.seed/db.seed.pot -o $(PO)/db.seed/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/fm_IDL.dtd/fm_IDL.dtd.pot -o $(PO)/fm_IDL.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/ils_events.xml/ils_events.xml.pot -o $(PO)/ils_events.xml/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/lang.dtd/lang.dtd.pot -o $(PO)/lang.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/multiclass_search_help.html/multiclass_search_help.html.pot -o $(PO)/multiclass_search_help.html/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/offline.properties/offline.properties.pot -o $(PO)/offline.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.dtd/opac.dtd.pot -o $(PO)/opac.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.js/opac.js.pot -o $(PO)/opac.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/patron.properties/patron.properties.pot -o $(PO)/patron.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/pickup_and_return.js/pickup_and_return.js.pot -o $(PO)/pickup_and_return.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/pull_list.js/pull_list.js.pot -o $(PO)/pull_list.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/register.js/register.js.pot -o $(PO)/register.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.dtd/reports.dtd.pot -o $(PO)/reports.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.js/reports.js.pot -o $(PO)/reports.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reservation.js/reservation.js.pot -o $(PO)/reservation.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/selfcheck.js/selfcheck.js.pot -o $(PO)/selfcheck.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/serial.properties/serial.properties.pot -o $(PO)/serial.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/tpac/tpac.pot -o $(PO)/tpac/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/AutoFieldWidget.js/AutoFieldWidget.js.pot -o $(PO)/AutoFieldWidget.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/Searcher.js/Searcher.js.pot -o $(PO)/Searcher.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/TranslatorPopup.js/TranslatorPopup.js.pot -o $(PO)/TranslatorPopup.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/XULTermLoader.js/XULTermLoader.js.pot -o $(PO)/XULTermLoader.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/User.js/User.js.pot -o $(PO)/User.js/$(LOCALE).po 
	@echo "Generated new PO files for locale $(LOCALE)"

# Generate a new set of POT files and entityized fieldmapper IDL
newpot: dtds2pot fmidl2pot fmidl2fmidlent ils2pot props2pot sql2pot dojo2pot tpac2pot
	@echo "Generated new POT files"

# Generate DTD, JavaScript message catalogs, fieldmapper IDL,
# and SQL insert files from PO for locale LOCALE
project: prep_output po2dtds po2props po2sql fmidlpo2entity po2ils po2dojo
	@echo "Generated project files for locale $(LOCALE)"

# Update PO files with new and changed strings from POT files
updatepo: prep_output  
	@pot2po $(PROGRESS) -i po/acq.js/acq.js.pot -o $(PO)/acq.js/$(LOCALE).po  -t $(PO)/acq.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/admin.properties/admin.properties.pot -o $(PO)/admin.properties/$(LOCALE).po  -t $(PO)/admin.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/auth.properties/auth.properties.pot -o $(PO)/auth.properties/$(LOCALE).po  -t $(PO)/auth.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/authority.js/authority.js.pot -o $(PO)/authority.js/$(LOCALE).po  -t $(PO)/authority.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/capture.js/capture.js.pot -o $(PO)/capture.js/$(LOCALE).po  -t $(PO)/capture.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/cat.properties/cat.properties.pot -o $(PO)/cat.properties/$(LOCALE).po  -t $(PO)/cat.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/circ.properties/circ.properties.pot -o $(PO)/circ.properties/$(LOCALE).po  -t $(PO)/circ.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/common.properties/common.properties.pot -o $(PO)/common.properties/$(LOCALE).po  -t $(PO)/common.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.dtd/conify.dtd.pot -o $(PO)/conify.dtd/$(LOCALE).po  -t $(PO)/conify.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.js/conify.js.pot -o $(PO)/conify.js/$(LOCALE).po  -t $(PO)/conify.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/db.seed/db.seed.pot -o $(PO)/db.seed/$(LOCALE).po  -t $(PO)/db.seed/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/fm_IDL.dtd/fm_IDL.dtd.pot -o $(PO)/fm_IDL.dtd/$(LOCALE).po  -t $(PO)/fm_IDL.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/ils_events.xml/ils_events.xml.pot -o $(PO)/ils_events.xml/$(LOCALE).po  -t $(PO)/ils_events.xml/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/lang.dtd/lang.dtd.pot -o $(PO)/lang.dtd/$(LOCALE).po  -t $(PO)/lang.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/multiclass_search_help.html/multiclass_search_help.html.pot -o $(PO)/multiclass_search_help.html/$(LOCALE).po  -t $(PO)/multiclass_search_help.html/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/offline.properties/offline.properties.pot -o $(PO)/offline.properties/$(LOCALE).po  -t $(PO)/offline.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.dtd/opac.dtd.pot -o $(PO)/opac.dtd/$(LOCALE).po  -t $(PO)/opac.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.js/opac.js.pot -o $(PO)/opac.js/$(LOCALE).po  -t $(PO)/opac.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/patron.properties/patron.properties.pot -o $(PO)/patron.properties/$(LOCALE).po  -t $(PO)/patron.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/pickup_and_return.js/pickup_and_return.js.pot -o $(PO)/pickup_and_return.js/$(LOCALE).po  -t $(PO)/pickup_and_return.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/pull_list.js/pull_list.js.pot -o $(PO)/pull_list.js/$(LOCALE).po  -t $(PO)/pull_list.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/register.js/register.js.pot -o $(PO)/register.js/$(LOCALE).po  -t $(PO)/register.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.dtd/reports.dtd.pot -o $(PO)/reports.dtd/$(LOCALE).po  -t $(PO)/reports.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.js/reports.js.pot -o $(PO)/reports.js/$(LOCALE).po  -t $(PO)/reports.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reservation.js/reservation.js.pot -o $(PO)/reservation.js/$(LOCALE).po  -t $(PO)/reservation.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/selfcheck.js/selfcheck.js.pot -o $(PO)/selfcheck.js/$(LOCALE).po  -t $(PO)/selfcheck.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/serial.properties/serial.properties.pot -o $(PO)/serial.properties/$(LOCALE).po  -t $(PO)/serial.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/tpac/tpac.pot -o $(PO)/tpac/$(LOCALE).po -t $(PO)/tpac/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/AutoFieldWidget.js/AutoFieldWidget.js.pot -o $(PO)/AutoFieldWidget.js/$(LOCALE).po  -t $(PO)/AutoFieldWidget.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/Searcher.js/Searcher.js.pot -o $(PO)/Searcher.js/$(LOCALE).po  -t $(PO)/Searcher.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/TranslatorPopup.js/TranslatorPopup.js.pot -o $(PO)/TranslatorPopup.js/$(LOCALE).po  -t $(PO)/TranslatorPopup.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/User.js/User.js.pot -o $(PO)/User.js/$(LOCALE).po  -t $(PO)/User.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/XULTermLoader.js/XULTermLoader.js.pot -o $(PO)/XULTermLoader.js/$(LOCALE).po  -t $(PO)/XULTermLoader.js/$(LOCALE).po 
	@echo "Updated PO files for locale $(LOCALE)"

dtds2pot:
	@moz2po -P $(PROGRESS) -o $(PO)/conify.dtd/conify.dtd.pot -i $(DTDDIR)/en-US/conify.dtd 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/lang.dtd/lang.dtd.pot -i $(DTDDIR)/en-US/lang.dtd 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/opac.dtd/opac.dtd.pot -i $(DTDDIR)/en-US/opac.dtd 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/reports.dtd/reports.dtd.pot -i $(DTDDIR)/en-US/reports.dtd 2>&1

dojo2pot:
	@scripts/dojo_resource.py --pot $(DOJO_ACQ_SRC)/acq.js --output $(PO)/acq.js/acq.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_ACTOR_SRC)/register.js --output $(PO)/register.js/register.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_AUTHORITY_SRC)/authority.js --output $(PO)/authority.js/authority.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_BOOKING_SRC)/capture.js --output $(PO)/capture.js/capture.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_BOOKING_SRC)/pickup_and_return.js --output $(PO)/pickup_and_return.js/pickup_and_return.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_BOOKING_SRC)/pull_list.js --output $(PO)/pull_list.js/pull_list.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_BOOKING_SRC)/reservation.js --output $(PO)/reservation.js/reservation.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_CIRC_SRC)/selfcheck.js --output $(PO)/selfcheck.js/selfcheck.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_CON_SRC)/conify.js --output $(PO)/conify.js/conify.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_OPAC_SRC)/opac.js --output $(PO)/opac.js/opac.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_RPT_SRC)/reports.js --output $(PO)/reports.js/reports.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_USER_SRC)/User.js --output $(PO)/User.js/User.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_WIDGET_SRC)/AutoFieldWidget.js --output $(PO)/AutoFieldWidget.js/AutoFieldWidget.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_WIDGET_SRC)/Searcher.js --output $(PO)/Searcher.js/Searcher.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_WIDGET_SRC)/TranslatorPopup.js --output $(PO)/TranslatorPopup.js/TranslatorPopup.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_WIDGET_SRC)/XULTermLoader.js --output $(PO)/XULTermLoader.js/XULTermLoader.js.pot

po2dojo: mklocale
	@scripts/dojo_resource.py --create $(PO)/acq.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/acq.js
	@scripts/dojo_resource.py --create $(PO)/authority.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/authority.js
	@scripts/dojo_resource.py --create $(PO)/capture.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/capture.js
	@scripts/dojo_resource.py --create $(PO)/conify.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/conify.js
	@scripts/dojo_resource.py --create $(PO)/opac.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/opac.js
	@scripts/dojo_resource.py --create $(PO)/pickup_and_return.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/pickup_and_return.js
	@scripts/dojo_resource.py --create $(PO)/pull_list.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/pull_list.js
	@scripts/dojo_resource.py --create $(PO)/register.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/register.js
	@scripts/dojo_resource.py --create $(PO)/reservation.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/reservation.js
	@scripts/dojo_resource.py --create $(PO)/reports.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/reports.js
	@scripts/dojo_resource.py --create $(PO)/selfcheck.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/selfcheck.js
	@scripts/dojo_resource.py --create $(PO)/AutoFieldWidget.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/AutoFieldWidget.js
	@scripts/dojo_resource.py --create $(PO)/Searcher.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/Searcher.js
	@scripts/dojo_resource.py --create $(PO)/TranslatorPopup.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/TranslatorPopup.js
	@scripts/dojo_resource.py --create $(PO)/User.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/User.js
	@scripts/dojo_resource.py --create $(PO)/XULTermLoader.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/XULTermLoader.js

ils2pot:
	@scripts/ils_events.py --pot $(EVTSRC) --output $(PO)/ils_events.xml/$(EVTOUT)

po2ils: mklocale
	@scripts/ils_events.py --create $(PO)/ils_events.xml/$(LOCALE).po --locale $(LOCALE) --output $(PROJECT)/$(LOCALE)/$(EVTXML) 

props2pot: mklocale
	@moz2po -P $(PROGRESS) -o $(PO)/auth.properties/auth.properties.pot -i $(CHROME_PROPSDIR)/en-US/auth.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/offline.properties/offline.properties.pot -i $(CHROME_PROPSDIR)/en-US/offline.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/admin.properties/admin.properties.pot -i $(SERVER_PROPSDIR)/en-US/admin.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/cat.properties/cat.properties.pot -i $(SERVER_PROPSDIR)/en-US/cat.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/circ.properties/circ.properties.pot -i $(SERVER_PROPSDIR)/en-US/circ.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/common.properties/common.properties.pot -i $(SERVER_PROPSDIR)/en-US/common.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/multiclass_search_help.html/multiclass_search_help.html.pot -i $(SERVER_PROPSDIR)/en-US/multiclass_search_help.html 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/patron.properties/patron.properties.pot -i $(SERVER_PROPSDIR)/en-US/patron.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/serial.properties/serial.properties.pot -i $(SERVER_PROPSDIR)/en-US/serial.properties 2>&1

tpac2pot: mklocale
	@mkdir -p po/tpac
	@xgettext.pl --plugin=tt2 --directory=$(TPAC_SRC) --output-dir=po/tpac/ --output=tpac.pot

mklocale:
	@mkdir -p locale/$(LOCALE)

# There are some hacky things we need to do to make po2moz happy,
# like ensure that the .po file has either ".dtd" or ".properties" in
# the name to generate the appropriate output, even though that breaks
# GNU gettext recommended layout of foo.dtd/ll-LL.po
prep_output: mklocale
	@for i in `ls -d $(PO)/*.dtd`; do cd $(STARTDIR)/$$i && ln -sf $(LOCALE).po $(LOCALE).dtd.po; done
	@for i in `ls -d $(PO)/*.properties`; do cd $(STARTDIR)/$$i && ln -sf $(LOCALE).po $(LOCALE).properties.po; done
	@for i in `ls -d $(PO)/*.html`; do cd $(STARTDIR)/$$i && ln -sf $(LOCALE).po $(LOCALE).html.po; done
	@cd $(STARTDIR)

po2dtds: mklocale
	@po2moz $(PROGRESS) -i $(PO)/conify.dtd/$(LOCALE).dtd.po -o $(PROJECT)/$(LOCALE)/conify.dtd -t $(DTDDIR)/en-US/conify.dtd 2>&1
	@po2moz $(PROGRESS) -i $(PO)/lang.dtd/$(LOCALE).dtd.po -o $(PROJECT)/$(LOCALE)/lang.dtd -t $(DTDDIR)/en-US/lang.dtd 2>&1
	@po2moz $(PROGRESS) -i $(PO)/opac.dtd/$(LOCALE).dtd.po -o $(PROJECT)/$(LOCALE)/opac.dtd -t $(DTDDIR)/en-US/opac.dtd 2>&1
	@po2moz $(PROGRESS) -i $(PO)/reports.dtd/$(LOCALE).dtd.po -o $(PROJECT)/$(LOCALE)/reports.dtd -t $(DTDDIR)/en-US/reports.dtd 2>&1

po2props:
	@po2moz $(PROGRESS) -i $(PO)/auth.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/auth.properties -t $(CHROME_PROPSDIR)/en-US/auth.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/offline.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/offline.properties -t $(CHROME_PROPSDIR)/en-US/offline.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/admin.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/admin.properties -t $(SERVER_PROPSDIR)/en-US/admin.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/cat.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/cat.properties -t $(SERVER_PROPSDIR)/en-US/cat.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/circ.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/circ.properties -t $(SERVER_PROPSDIR)/en-US/circ.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/common.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/common.properties -t $(SERVER_PROPSDIR)/en-US/common.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/multiclass_search_help.html/$(LOCALE).html.po -o $(PROJECT)/$(LOCALE)/multiclass_search_help.html -t $(SERVER_PROPSDIR)/en-US/multiclass_search_help.html 2>&1
	@po2moz $(PROGRESS) -i $(PO)/patron.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/patron.properties -t $(SERVER_PROPSDIR)/en-US/patron.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/serial.properties/$(LOCALE).properties.po -o $(PROJECT)/$(LOCALE)/serial.properties -t $(SERVER_PROPSDIR)/en-US/serial.properties 2>&1

sql2pot:
	@scripts/db-seed-i18n.py --pot $(SQLSRCDIR)/$(SQLSRCFILE) --output $(PO)/db.seed/$(SQLPOT)
#	@msghack --empty -o $(PO)/$(SQLPOT) $(PO)/$(SQLPOT)

po2sql: mklocale
	@scripts/db-seed-i18n.py --sql $(PO)/db.seed/$(LOCALE).po --locale $(LOCALE) --output $(PROJECT)/$(LOCALE)/$(SQLOUT).sql

# Generate a fieldmapper IDL file that uses entities instead of hard-coded strings
fmidl2fmidlent:
	@scripts/fieldmapper.py --convert $(FMIDLSRC) --output $(PO)/$(FMIDLENT)

# Generate a POT file for translating the entity values
fmidl2pot:
	@scripts/fieldmapper.py --pot $(FMIDLSRC) --output $(PO)/fm_IDL.dtd/$(FMIDLOUT)

# Generate a set of entity declarations from a PO file
fmidlpo2entity: mklocale
	@scripts/fieldmapper.py --entity $(PO)/fm_IDL.dtd/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/$(FMIDLENTITY)

# Generate en-US DTD from a POT file; required if any other locale is installed
fmidlpo2entity-en:
	mkdir -p $(PROJECT)/en-US
	@scripts/fieldmapper.py --entity $(PO)/fm_IDL.dtd/$(FMIDLOUT) --output $(PROJECT)/en-US/$(FMIDLENTITY)
	cp $(PROJECT)/en-US/$(FMIDLENTITY) $(DTDDIR)/en-US/

# Install updated project files to their corresponding location in the source tree
install: updatepo project fmidl2fmidlent fmidlpo2entity-en
	mkdir -p $(CHROME_PROPSDIR)/$(LOCALE)
	cp $(PROJECT)/$(LOCALE)/auth.properties $(CHROME_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/offline.properties $(CHROME_PROPSDIR)/$(LOCALE)/.
	mkdir -p $(SERVER_PROPSDIR)/$(LOCALE)
	cp $(PROJECT)/$(LOCALE)/admin.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/cat.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/circ.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/common.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/multiclass_search_help.html $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/patron.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	mkdir -p $(DTDDIR)/$(LOCALE)
	cp $(PROJECT)/$(LOCALE)/conify.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/lang.dtd $(CHROME_PROPSDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/lang.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/opac.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/reports.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/serial.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	mkdir -p $(TT_LOCALE)
	cp po/tpac/$(LOCALE).po $(TT_LOCALE)/tpac.$(LOCALE).po
	cp $(PROJECT)/$(LOCALE)/$(FMIDLENTITY) $(DTDDIR)/$(LOCALE)/
	@scripts/merge_ils_events.py --master $(EVTSRC) --localization $(PROJECT)/$(LOCALE)/$(EVTXML) --output $(EVTSRC)
	cp $(PROJECT)/$(LOCALE)/$(SQLOUT).sql $(SQLSRCDIR)/$(SQLOUT)-$(LOCALE).sql
	cp $(PO)/$(FMIDLENT) $(REPORTDIR)/$(FMIDLENT)
	mkdir -p $(DOJO_ACQ_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/acq.js $(DOJO_ACQ_SRC)/$(DOJO_LOCALE)/acq.js
	mkdir -p $(DOJO_ACTOR_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/register.js $(DOJO_ACTOR_SRC)/$(DOJO_LOCALE)/register.js
	mkdir -p $(DOJO_AUTHORITY_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/authority.js $(DOJO_AUTHORITY_SRC)/$(DOJO_LOCALE)/authority.js
	mkdir -p $(DOJO_BOOKING_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/capture.js $(DOJO_BOOKING_SRC)/$(DOJO_LOCALE)/capture.js
	cp $(PROJECT)/$(LOCALE)/pickup_and_return.js $(DOJO_BOOKING_SRC)/$(DOJO_LOCALE)/pickup_and_return.js
	cp $(PROJECT)/$(LOCALE)/pull_list.js $(DOJO_BOOKING_SRC)/$(DOJO_LOCALE)/pull_list.js
	cp $(PROJECT)/$(LOCALE)/reservation.js $(DOJO_BOOKING_SRC)/$(DOJO_LOCALE)/reservation.js
	mkdir -p $(DOJO_CIRC_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/selfcheck.js $(DOJO_CIRC_SRC)/$(DOJO_LOCALE)/selfcheck.js
	mkdir -p $(DOJO_CON_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/conify.js $(DOJO_CON_SRC)/$(DOJO_LOCALE)/conify.js
	mkdir -p $(DOJO_OPAC_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/opac.js $(DOJO_OPAC_SRC)/$(DOJO_LOCALE)/opac.js
	mkdir -p $(DOJO_RPT_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/reports.js $(DOJO_RPT_SRC)/$(DOJO_LOCALE)/reports.js
	mkdir -p $(DOJO_USER_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/User.js $(DOJO_USER_SRC)/$(DOJO_LOCALE)/User.js
	mkdir -p $(DOJO_WIDGET_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/AutoFieldWidget.js $(DOJO_WIDGET_SRC)/$(DOJO_LOCALE)/AutoFieldWidget.js
	cp $(PROJECT)/$(LOCALE)/Searcher.js $(DOJO_WIDGET_SRC)/$(DOJO_LOCALE)/Searcher.js
	cp $(PROJECT)/$(LOCALE)/TranslatorPopup.js $(DOJO_WIDGET_SRC)/$(DOJO_LOCALE)/TranslatorPopup.js
	cp $(PROJECT)/$(LOCALE)/XULTermLoader.js $(DOJO_WIDGET_SRC)/$(DOJO_LOCALE)/XULTermLoader.js
	mkdir -p $(TT2_DATA_DIR)
	cp $(PO)/tpac/$(LOCALE).po $(TT2_DATA_DIR)/.

install_all_locales: newpot
	for i in `ls po/*/*po|grep -v en-US | cut -f3 -d'/' | cut -f1 -d. | sort | uniq`; \
	do \
	make LOCALE=$$i install; \
	RC=$$?; \
	if [ "$$RC" -gt 0 ]; \
	then echo $$RC; exit $$RC; \
	fi; done

update_all_locales: newpot
	for i in `ls po/*/*po|grep -v en-US | cut -f3 -d'/' | cut -f1 -d. | sort | uniq`; \
	do \
	make LOCALE=$$i updatepo; \
	RC=$$?; \
	if [ "$$RC" -gt 0 ]; \
	then echo $$RC; exit $$RC; \
	fi; done
